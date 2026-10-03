import Foundation
import MLX
import MLXLMCommon

/// Masks the logits of every token that would take the output outside a
/// ``BrujaJSONSchema``.
///
/// On each step ``process(logits:)`` sets to `-inf` every token whose text the
/// acceptor cannot consume, in full, from its current state. The sampler then
/// picks among the tokens that are left, and ``didSample(token:)`` moves the
/// acceptor past the text of the token it picked. Once the top-level object
/// has closed, only the EOS token ids stay unmasked, so generation ends there.
///
/// A token's text is tested one `Character` at a time. A token may span a
/// structural boundary (for example `",` or `":`); it is allowed when every
/// character of it is legal in turn.
///
/// Always masked, in every state:
/// - a token id that is not in the vocabulary table (including logit columns
///   past the end of the table);
/// - a token whose text is empty;
/// - a token whose text contains U+FFFD. In a byte-level vocabulary that is a
///   partial UTF-8 sequence decoded on its own.
/// - an EOS token id, until the object has closed.
///
/// - Important: Known limit. A character the tokenizer can only spell as
///   split-byte tokens (each of which decodes, alone, to U+FFFD) cannot be
///   generated on this path. Characters that have a whole token of their own,
///   or that sit inside a longer whole token, are not affected.
///
/// The allowed-token set is cached per acceptor state, so the vocabulary is
/// scanned once for each state the generation visits, not once per step. The
/// cache is shared by copies of the processor.
///
/// One processor serves one generation with a batch size of one. If no token
/// in the vocabulary is legal in some state, every logit comes back `-inf`.
struct BrujaJSONLogitProcessor: LogitProcessor {

  /// The acceptor, at the position after the last sampled token.
  private(set) var acceptor: BrujaJSONAcceptor

  /// The EOS token ids, ascending.
  let eosTokenIds: [Int]

  /// Every token that can ever be allowed before completion, ascending by id,
  /// with its text split into characters once.
  private let candidates: [(id: Int, characters: [Character])]

  /// Token id to character sequence, for ``didSample(token:)``.
  private let charactersByToken: [Int: [Character]]

  private let cache = MaskCache()

  /// - Parameters:
  ///   - acceptor: the acceptor for the schema, at the state generation starts
  ///     from (normally a fresh one).
  ///   - vocabulary: the text of each token id, each token decoded on its own.
  ///   - eosTokenIds: the ids that end generation. They are masked until the
  ///     object closes, whatever text the vocabulary gives them.
  init(acceptor: BrujaJSONAcceptor, vocabulary: [Int: String], eosTokenIds: Set<Int>) {
    self.acceptor = acceptor
    self.eosTokenIds = eosTokenIds.filter { $0 >= 0 }.sorted()

    var candidates: [(id: Int, characters: [Character])] = []
    candidates.reserveCapacity(vocabulary.count)
    for (id, text) in vocabulary {
      guard id >= 0, !eosTokenIds.contains(id), !text.isEmpty else { continue }
      guard !text.unicodeScalars.contains("\u{FFFD}") else { continue }
      candidates.append((id, Array(text)))
    }
    candidates.sort { $0.id < $1.id }
    self.candidates = candidates
    self.charactersByToken = Dictionary(
      uniqueKeysWithValues: candidates.map { ($0.id, $0.characters) })
  }

  // MARK: - LogitProcessor

  /// Nothing to do: the mask depends on the generated text only, not on the prompt.
  mutating func prompt(_ prompt: MLXArray) {}

  /// Returns `logits` with every token that is not legal in the current state
  /// set to `-inf`. The last axis is the vocabulary.
  func process(logits: MLXArray) -> MLXArray {
    logits + mask(width: logits.dim(-1), dtype: logits.dtype)
  }

  /// Moves the acceptor past the text of `token`.
  ///
  /// A token the mask would not have allowed (or an EOS id) leaves the state
  /// unchanged.
  mutating func didSample(token: MLXArray) {
    guard token.size == 1 else { return }
    didSample(tokenId: token.item(Int.self))
  }

  // MARK: - Internals

  /// True once the top-level object has closed.
  var isComplete: Bool { acceptor.isComplete }

  /// The token ids left unmasked in the current state, ascending.
  var allowedTokenIds: [Int] {
    allowedTokenIds(in: acceptor.state)
  }

  /// How many times the vocabulary has been scanned. One scan per distinct
  /// state visited.
  var vocabularyScanCount: Int { cache.scanCount }

  mutating func didSample(tokenId: Int) {
    guard let characters = charactersByToken[tokenId] else { return }
    if let next = state(after: characters, from: acceptor.state) {
      acceptor.state = next
    }
  }

  private func state(
    after characters: [Character], from state: BrujaJSONAcceptor.State
  ) -> BrujaJSONAcceptor.State? {
    var current = state
    for character in characters {
      guard let next = acceptor.state(after: character, from: current) else { return nil }
      current = next
    }
    return current
  }

  private func allowedTokenIds(in state: BrujaJSONAcceptor.State) -> [Int] {
    if let cached = cache.allowed[state] { return cached }

    let allowed: [Int]
    if acceptor.isComplete(state) {
      allowed = eosTokenIds
    } else {
      allowed = candidates.compactMap { candidate in
        self.state(after: candidate.characters, from: state) != nil ? candidate.id : nil
      }
    }
    cache.scanCount += 1
    cache.allowed[state] = allowed
    return allowed
  }

  /// A vector of `width` values to add to the logits: 0 for an allowed token,
  /// `-inf` for a masked one.
  private func mask(width: Int, dtype: DType) -> MLXArray {
    let state = acceptor.state
    if cache.width != width || cache.dtype != dtype {
      cache.masks.removeAll()
      cache.width = width
      cache.dtype = dtype
    }
    if let cached = cache.masks[state] { return cached }

    var values = [Float](repeating: -.infinity, count: width)
    for id in allowedTokenIds(in: state) where id < width {
      values[id] = 0
    }
    let mask = MLXArray(values).asType(dtype)
    cache.masks[state] = mask
    return mask
  }

  /// Shared by copies of the processor, so that the non-mutating
  /// `process(logits:)` can fill it.
  private final class MaskCache {
    var allowed: [BrujaJSONAcceptor.State: [Int]] = [:]
    var masks: [BrujaJSONAcceptor.State: MLXArray] = [:]
    var width = -1
    var dtype: DType?
    var scanCount = 0
  }
}
