import Foundation
import SwiftAcervo
import XCTest

@testable import SwiftBruja

/// Acceptance tests for what Personaje needs from SwiftBruja (BR-P1 … BR-P4).
///
/// Every test here drives real MLX inference against Personaje's default model, so the class
/// skips when that model is not reachable from the test process. Under the SANDBOXED
/// `xcodebuild test` host the App Group container is unreadable and the tests skip; run them
/// through `make test-personaje`, which uses the unsandboxed `xcrun xctest` host with
/// `ACERVO_APP_GROUP_ID` set.
///
/// **Requirements:** Apple Silicon and the default model present in the
/// `group.intrusive-memory.models` App Group container.
final class PersonajeAcceptanceTests: XCTestCase {

  /// Personaje's default model. This is NOT `BrujaModelManager.defaultModel`.
  static let defaultModelId = "mlx-community/Qwen2.5-7B-Instruct-4bit"

  /// The App Group container the models are downloaded into. SwiftAcervo resolves the
  /// shared-models directory from `ACERVO_APP_GROUP_ID` first.
  private let appGroupId = "group.intrusive-memory.models"

  override func setUp() {
    super.setUp()
    setenv("ACERVO_APP_GROUP_ID", appGroupId, 1)
  }

  /// Skips the calling test unless `modelId` is on disk and readable from this process.
  func skipUnlessModelPresent(_ modelId: String = PersonajeAcceptanceTests.defaultModelId) throws {
    try XCTSkipUnless(
      Acervo.isModelConfigPresent(modelId),
      "Model '\(modelId)' is not reachable from this test process at "
        + "\(Acervo.sharedModelsDirectory.path). Run via the unsandboxed host "
        + "(`make test-personaje`); the sandboxed `xcodebuild test` runner cannot read the "
        + "App Group container."
    )
  }

  // MARK: - BR-P4: the default model answers through Bruja

  func testDefaultModelAnswersThroughBruja() async throws {
    let modelId = Self.defaultModelId
    try skipUnlessModelPresent(modelId)

    let result = try await Bruja.queryWithMetadata(
      "Reply with the single word: ready",
      model: modelId,
      maxTokens: 16
    )

    print("PersonajeAcceptanceTests default-model response: \(result.response)")
    XCTAssertFalse(
      result.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      "Expected a non-empty response from \(modelId)"
    )
  }
}
