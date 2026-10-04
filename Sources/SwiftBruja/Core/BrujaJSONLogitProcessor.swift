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
/// The schema's `maxLength` and `maxItems` bounds are not part of the state,
/// so they are not part of the cache key. The cached set for a state is built
/// as if none of the bound had been used. When the string being written is
/// close enough to its `maxLength` for some token to cross it, or an array
/// with a `maxItems` is open, a second filter runs over the cached set and
/// drops every token that would carry the string past its bound or the array
/// past its item count. The filter reads the cached set; it never rescans the
/// vocabulary. Most of its tokens are cleared by their length and comma count
/// alone, and only the rest are run through the acceptor.
///
/// A ``RepetitionContext`` can be given to discourage loops (one word over and
/// over in a string, the same item again in an array). Its penalty is applied
/// to the logits first and the mask second, so the penalty only moves the
/// order of the legal tokens: a masked token is `-inf` whatever the penalty
/// did to it.
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

  /// For each candidate, by its index: how many characters it has.
  private let candidateLengths: [Int]

  /// For each candidate, by its index: how many of its characters are commas.
  /// A token can add at most that many items to an open array.
  private let candidateCommas: [Int]

  /// The character count of the longest candidate.
  private let longestCandidateLength: Int

  /// The comma count of the candidate with the most commas.
  private let mostCandidateCommas: Int

  /// Token id to character sequence, for ``didSample(token:)``.
  private let charactersByToken: [Int: [Character]]

  private let cache = MaskCache()

  /// Penalises the tokens of the recent context before the mask is applied.
  /// `nil` when the penalty is off.
  private var repetitionContext: RepetitionContext?

  /// The acceptor looks this many characters past the one it is given before
  /// it lets an escape start: `\u` needs room for four hex digits. A token
  /// that leaves at least this much of the bound unused needs no second look.
  private static let escapeLookahead = 4

  /// - Parameters:
  ///   - acceptor: the acceptor for the schema, at the state generation starts
  ///     from (normally a fresh one).
  ///   - vocabulary: the text of each token id, each token decoded on its own.
  ///   - eosTokenIds: the ids that end generation. They are masked until the
  ///     object closes, whatever text the vocabulary gives them.
  ///   - repetitionContext: the repetition penalty to apply before the mask,
  ///     or `nil` for none.
  init(
    acceptor: BrujaJSONAcceptor, vocabulary: [Int: String], eosTokenIds: Set<Int>,
    repetitionContext: RepetitionContext? = nil
  ) {
    self.acceptor = acceptor
    self.repetitionContext = repetitionContext
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
    self.candidateLengths = candidates.map { $0.characters.count }
    self.candidateCommas = candidates.map { candidate in
      candidate.characters.reduce(0) { $1 == "," ? $0 + 1 : $0 }
    }
    self.longestCandidateLength = candidateLengths.max() ?? 0
    self.mostCandidateCommas = candidateCommas.max() ?? 0
    self.charactersByToken = Dictionary(
      uniqueKeysWithValues: candidates.map { ($0.id, $0.characters) })
  }

  // MARK: - LogitProcessor

  /// The mask depends on the generated text only, not on the prompt. The
  /// prompt goes to the repetition context, which counts its last tokens as
  /// recent context.
  mutating func prompt(_ prompt: MLXArray) {
    repetitionContext?.prompt(prompt)
  }

  /// Returns `logits` with the repetition penalty applied, if there is one,
  /// and then every token that is not legal in the current state set to
  /// `-inf`. The last axis is the vocabulary.
  func process(logits: MLXArray) -> MLXArray {
    let penalised = repetitionContext?.process(logits: logits) ?? logits
    return penalised + mask(width: logits.dim(-1), dtype: logits.dtype)
  }

  /// Moves the acceptor past the text of `token`.
  ///
  /// A token the mask would not have allowed (or an EOS id) leaves the state
  /// unchanged.
  mutating func didSample(token: MLXArray) {
    repetitionContext?.didSample(token: token)
    guard token.size == 1 else { return }
    didSample(tokenId: token.item(Int.self))
  }

  // MARK: - Internals

  /// True once the top-level object has closed.
  var isComplete: Bool { acceptor.isComplete }

  /// The token ids left unmasked at the current position, ascending.
  var allowedTokenIds: [Int] {
    let state = acceptor.state
    if acceptor.isComplete(state) { return eosTokenIds }
    let unbounded = allowedCandidates(in: state)
    return (withinBounds(unbounded) ?? unbounded).map { candidates[$0].id }
  }

  /// How many times the vocabulary has been scanned. One scan per distinct
  /// state visited.
  var vocabularyScanCount: Int { cache.scanCount }

  mutating func didSample(tokenId: Int) {
    guard let characters = charactersByToken[tokenId] else { return }
    var state = acceptor.state
    var counters = acceptor.counters
    if consume(characters, state: &state, counters: &counters) {
      acceptor.state = state
      acceptor.counters = counters
    }
  }

  /// Runs `characters` through the acceptor from `state` with `counters`.
  /// False if any character is not legal.
  private func consume(
    _ characters: [Character], state: inout BrujaJSONAcceptor.State,
    counters: inout BrujaJSONAcceptor.Counters
  ) -> Bool {
    for character in characters {
      guard let next = acceptor.state(after: character, from: state, counters: &counters) else {
        return false
      }
      state = next
    }
    return true
  }

  /// The candidates, by index, that are legal in `state` when none of its
  /// bounds has been used. Cached per state. Empty once the object has closed.
  private func allowedCandidates(in state: BrujaJSONAcceptor.State) -> [Int] {
    if let cached = cache.allowed[state] { return cached }

    var allowed: [Int] = []
    if !acceptor.isComplete(state) {
      let unused = acceptor.unusedCounters(for: state)
      for index in candidates.indices {
        var current = state
        var counters = unused
        if consume(candidates[index].characters, state: &current, counters: &counters) {
          allowed.append(index)
        }
      }
    }
    cache.scanCount += 1
    cache.allowed[state] = allowed
    return allowed
  }

  /// The second filter: `allowed` without the candidates that would carry the
  /// string being written past its `maxLength`, or an open array past its
  /// `maxItems`, from the acceptor's current counters.
  ///
  /// - Returns: `nil` when the filter drops nothing, so the cached mask stands.
  private func withinBounds(_ allowed: [Int]) -> [Int]? {
    let counters = acceptor.counters
    let lengthLeft = counters.remainingLength ?? .max
    let itemsLeft = counters.fewestRemainingItems ?? .max

    // No token is long enough to reach the end of the string, and none has
    // enough commas to fill an open array: nothing to filter.
    let lengthMatters =
      lengthLeft != .max && lengthLeft < longestCandidateLength + Self.escapeLookahead
    guard lengthMatters || itemsLeft < mostCandidateCommas else { return nil }

    // A token is cleared without the acceptor when it leaves the lookahead
    // unused and has no more commas than the fullest open array has room for.
    let clearLength = lengthLeft == .max ? Int.max : lengthLeft - Self.escapeLookahead
    let state = acceptor.state
    var kept: [Int] = []
    kept.reserveCapacity(allowed.count)
    for index in allowed {
      if candidateLengths[index] <= clearLength && candidateCommas[index] <= itemsLeft {
        kept.append(index)
        continue
      }
      var current = state
      var moved = counters
      if consume(candidates[index].characters, state: &current, counters: &moved) {
        kept.append(index)
      }
    }
    return kept.count == allowed.count ? nil : kept
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

    let complete = acceptor.isComplete(state)
    let unbounded = allowedCandidates(in: state)
    let bounded = complete ? nil : withinBounds(unbounded)
    if bounded == nil, let cached = cache.masks[state] { return cached }

    var values = [Float](repeating: -.infinity, count: width)
    if complete {
      for id in eosTokenIds where id < width {
        values[id] = 0
      }
    } else {
      for index in bounded ?? unbounded {
        let id = candidates[index].id
        if id < width { values[id] = 0 }
      }
    }
    let mask = MLXArray(values).asType(dtype)
    // Only the mask for the state alone is cached. A mask narrowed by a bound
    // depends on the counters and is built each time.
    if bounded == nil { cache.masks[state] = mask }
    return mask
  }

  /// Shared by copies of the processor, so that the non-mutating
  /// `process(logits:)` can fill it.
  private final class MaskCache {
    /// Candidate indices, not token ids.
    var allowed: [BrujaJSONAcceptor.State: [Int]] = [:]
    var masks: [BrujaJSONAcceptor.State: MLXArray] = [:]
    var width = -1
    var dtype: DType?
    var scanCount = 0
  }
}
