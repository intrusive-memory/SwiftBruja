import Foundation
import MLXLMCommon
import Tokenizers

// MARK: - TokenizerBridge

/// Bridges huggingface/swift-transformers' tokenizer to the `MLXLMCommon.Tokenizer` seam.
///
/// **Why this exists (OQ-2).** mlx-swift-lm 3.x ships `MLXLMCommon.Tokenizer` and
/// `MLXLMCommon.TokenizerLoader` as **protocols only** — there is no concrete tokenizer in the
/// MLX dependency tree. swift-transformers supplies a real, offline, local-folder tokenizer
/// (`AutoTokenizer.from(modelFolder:)`) plus the Jinja chat-template engine, and it is independent
/// of mlx-swift-lm so it does not collide with our `ml-explore/mlx-swift-lm` pin. This file is the
/// thin adapter that lets MLX's model factory consume a swift-transformers tokenizer.
///
/// The two `Tokenizer` protocols are almost identical; the only mismatches handled here are:
/// * `decode(tokenIds:…)` (MLX) vs `decode(tokens:…)` (swift-transformers)
/// * MLX has no `tokenize(text:)`/`callAsFunction` requirements, so we only forward what MLX needs.
/// * `Message` / `ToolSpec` are `[String: any Sendable]` in **both** packages, so chat-template
///   forwarding is a direct pass-through.

/// A `MLXLMCommon.Tokenizer` backed by a swift-transformers `Tokenizers.Tokenizer`.
///
/// `swift-transformers`' `PreTrainedTokenizer` is `@unchecked Sendable`; wrapping it in a value
/// type that is itself `Sendable` (holding an `any Tokenizers.Tokenizer`, which is `Sendable`)
/// satisfies the `MLXLMCommon.Tokenizer: Sendable` requirement.
public struct SwiftTransformersTokenizer: MLXLMCommon.Tokenizer {

  /// The wrapped swift-transformers tokenizer.
  private let upstream: any Tokenizers.Tokenizer

  public init(_ upstream: any Tokenizers.Tokenizer) {
    self.upstream = upstream
  }

  // MARK: Encode / Decode

  public func encode(text: String, addSpecialTokens: Bool) -> [Int] {
    upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
  }

  public func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
    // swift-transformers spells the parameter `tokens:`, not `tokenIds:`.
    upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
  }

  public func convertTokenToId(_ token: String) -> Int? {
    upstream.convertTokenToId(token)
  }

  public func convertIdToToken(_ id: Int) -> String? {
    upstream.convertIdToToken(id)
  }

  // MARK: Special tokens

  public var bosToken: String? { upstream.bosToken }
  public var eosToken: String? { upstream.eosToken }
  public var unknownToken: String? { upstream.unknownToken }

  // MARK: Chat template

  /// Forward chat-template application to swift-transformers' Jinja engine.
  ///
  /// `Message` and `ToolSpec` are `[String: any Sendable]` in both packages, so the dictionaries
  /// cross the boundary unchanged. `addGenerationPrompt` is forced on so the model is prompted to
  /// produce the assistant turn (matching the default MLXLMCommon behavior).
  public func applyChatTemplate(
    messages: [[String: any Sendable]],
    tools: [[String: any Sendable]]?,
    additionalContext: [String: any Sendable]?
  ) throws -> [Int] {
    try upstream.applyChatTemplate(
      messages: messages,
      chatTemplate: nil,
      addGenerationPrompt: true,
      truncation: false,
      maxLength: nil,
      tools: tools,
      additionalContext: additionalContext
    )
  }
}

// MARK: - TokenizerLoader

/// A `MLXLMCommon.TokenizerLoader` that loads a swift-transformers tokenizer from a local model
/// directory — **fully offline**, from the SwiftAcervo-resolved model folder, with no Hub download.
///
/// `AutoTokenizer.from(modelFolder:)` reads `tokenizer.json` / `tokenizer_config.json` (and any
/// `*.jinja` chat template) directly from disk. The default `HubApi` is never asked to fetch
/// anything because the folder already contains the tokenizer files.
public struct SwiftTransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {

  public init() {}

  public func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
    let upstream = try await AutoTokenizer.from(modelFolder: directory)
    return SwiftTransformersTokenizer(upstream)
  }
}
