import Foundation
import MLXLMCommon
import Tokenizers

/// Loads a model's tokenizer with swift-tokenizers and adapts it to
/// mlx-swift-lm's `MLXLMCommon.Tokenizer`.
///
/// mlx-swift-lm 3.x ships the `Tokenizer` and `TokenizerLoader` protocols only;
/// every `LLMModelFactory.loadContainer` overload needs a concrete loader. This
/// is that loader, over DePasqualeOrg/swift-tokenizers (the Rust `tokenizers`
/// crate, with Jinja chat templates). It replaces swift-transformers and
/// mlx-swift-lm's `#huggingFaceTokenizerLoader()` macro: both packages define a
/// `Tokenizers` module, and the image stack (SwiftTuberia, flux-2-swift-mlx,
/// SwiftVinetas, mlx-audio-swift) uses swift-tokenizers, so an app linking
/// SwiftBruja beside it could not build.
///
/// The load is local and offline: SwiftAcervo has already placed the
/// tokenizer files in the model directory.
struct SwiftTokenizersLoader: MLXLMCommon.TokenizerLoader {
  func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
    TokenizerAdapter(try await Tokenizers.AutoTokenizer.from(directory: directory))
  }
}

/// A swift-tokenizers tokenizer seen as an `MLXLMCommon.Tokenizer`.
///
/// swift-tokenizers' `encode` and `decode` throw (typed `TokenizerError`);
/// `MLXLMCommon.Tokenizer`'s don't. The Rust backend fails only on internal
/// errors, not on any input text, so those calls return an empty result rather
/// than trap. `applyChatTemplate` throws, and a missing template is reported
/// as `MLXLMCommon.TokenizerError.missingChatTemplate`, as mlx-swift-lm expects.
struct TokenizerAdapter: MLXLMCommon.Tokenizer {
  let upstream: any Tokenizers.Tokenizer

  init(_ upstream: any Tokenizers.Tokenizer) {
    self.upstream = upstream
  }

  func encode(text: String, addSpecialTokens: Bool) -> [Int] {
    (try? upstream.encode(text: text, addSpecialTokens: addSpecialTokens)) ?? []
  }

  func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
    (try? upstream.decode(tokenIds: tokenIds, skipSpecialTokens: skipSpecialTokens)) ?? ""
  }

  func convertTokenToId(_ token: String) -> Int? {
    upstream.convertTokenToId(token)
  }

  func convertIdToToken(_ id: Int) -> String? {
    upstream.convertIdToToken(id)
  }

  var bosToken: String? { upstream.bosToken }
  var eosToken: String? { upstream.eosToken }
  var unknownToken: String? { upstream.unknownToken }

  func applyChatTemplate(
    messages: [[String: any Sendable]],
    tools: [[String: any Sendable]]?,
    additionalContext: [String: any Sendable]?
  ) throws -> [Int] {
    do {
      return try upstream.applyChatTemplate(
        messages: messages, tools: tools, additionalContext: additionalContext)
    } catch .missingChatTemplate {
      throw MLXLMCommon.TokenizerError.missingChatTemplate
    }
  }
}
