import Foundation
import MLXLMCommon
import XCTest

@testable import SwiftBruja

/// `SwiftTokenizersLoader` over a tiny hand-written tokenizer, so the adapter is
/// checked without a model download.
final class SwiftTokenizersLoaderTests: XCTestCase {

  /// A word-level tokenizer: four words, `<unk>`, and `</s>` as end of sequence.
  static let tokenizerJSON = """
    {
      "version": "1.0",
      "truncation": null,
      "padding": null,
      "added_tokens": [
        {"id": 0, "content": "<unk>", "single_word": false, "lstrip": false, "rstrip": false, "normalized": false, "special": true},
        {"id": 1, "content": "</s>", "single_word": false, "lstrip": false, "rstrip": false, "normalized": false, "special": true}
      ],
      "normalizer": null,
      "pre_tokenizer": {"type": "Whitespace"},
      "post_processor": null,
      "decoder": null,
      "model": {
        "type": "WordLevel",
        "vocab": {"<unk>": 0, "</s>": 1, "hello": 2, "world": 3, "user": 4, "says": 5},
        "unk_token": "<unk>"
      }
    }
    """

  func makeTokenizerDirectory(chatTemplate: String?) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("bruja-tokenizer-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Self.tokenizerJSON.write(
      to: dir.appendingPathComponent("tokenizer.json"), atomically: true, encoding: .utf8)
    var config: [String: Any] = ["eos_token": "</s>", "unk_token": "<unk>"]
    if let chatTemplate { config["chat_template"] = chatTemplate }
    try JSONSerialization.data(withJSONObject: config)
      .write(to: dir.appendingPathComponent("tokenizer_config.json"))
    addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
    return dir
  }

  func testEncodeDecodeAndSpecialTokens() async throws {
    let tokenizer = try await SwiftTokenizersLoader().load(
      from: makeTokenizerDirectory(chatTemplate: nil))

    let ids = tokenizer.encode(text: "hello world", addSpecialTokens: false)
    XCTAssertEqual(ids, [2, 3])
    XCTAssertEqual(tokenizer.decode(tokenIds: ids, skipSpecialTokens: true), "hello world")
    XCTAssertEqual(tokenizer.convertTokenToId("world"), 3)
    XCTAssertEqual(tokenizer.convertIdToToken(2), "hello")
    XCTAssertEqual(tokenizer.eosToken, "</s>")
    XCTAssertEqual(tokenizer.eosTokenId, 1)
    XCTAssertEqual(tokenizer.unknownToken, "<unk>")
  }

  func testChatTemplateRenders() async throws {
    let template =
      "{% for message in messages %}{{ message['role'] }} says {{ message['content'] }} {% endfor %}"
    let tokenizer = try await SwiftTokenizersLoader().load(
      from: makeTokenizerDirectory(chatTemplate: template))

    let ids = try tokenizer.applyChatTemplate(messages: [["role": "user", "content": "hello"]])
    XCTAssertEqual(ids, [4, 5, 2])
  }

  func testMissingChatTemplateIsMLXLMCommonError() async throws {
    let tokenizer = try await SwiftTokenizersLoader().load(
      from: makeTokenizerDirectory(chatTemplate: nil))

    XCTAssertThrowsError(
      try tokenizer.applyChatTemplate(messages: [["role": "user", "content": "hello"]])
    ) { error in
      guard case MLXLMCommon.TokenizerError.missingChatTemplate = error else {
        return XCTFail("expected MLXLMCommon.TokenizerError.missingChatTemplate, got \(error)")
      }
    }
  }
}
