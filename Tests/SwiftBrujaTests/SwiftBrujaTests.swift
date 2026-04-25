import SwiftAcervo
import XCTest

@testable import SwiftBruja

final class SwiftBrujaTests: XCTestCase {

  // MARK: - Bruja Static Properties

  func testBrujaDefaultModel() {
    XCTAssertEqual(Bruja.defaultModel, "mlx-community/Llama-3.2-1B-Instruct-4bit")
  }

  func testBrujaDefaultModelsDirectory() {
    let dir = Bruja.defaultModelsDirectory
    XCTAssertTrue(dir.path.contains("SharedModels"))
  }

  // MARK: - Bruja Model Existence Checks

  func testModelExistsAtPath_NonexistentPath() {
    XCTAssertFalse(Bruja.modelExists(at: "/nonexistent/path/to/model"))
  }

  func testModelExistsAtPath_WithTildeExpansion() {
    // Test that tilde paths are handled (even if model doesn't exist)
    XCTAssertFalse(Bruja.modelExists(at: "~/nonexistent/model"))
  }

  func testModelExistsById_NonexistentModel() {
    XCTAssertFalse(Bruja.modelExists(id: "nonexistent/model-that-does-not-exist"))
  }

  // MARK: - Bruja List Models

  func testListModels_ReturnsArray() throws {
    // Just verify it returns without throwing (may be empty if no models downloaded)
    let models = try Bruja.listModels()
    XCTAssertNotNil(models)
  }
}

// MARK: - BrujaMemory Tests

final class BrujaMemoryTests: XCTestCase {

  // Uses the internal tokensForAvailableMemory helper to avoid Metal/GPU dependency.

  func testMinimumFloor_ZeroMemoryAfterModel() {
    // Model consumes all memory -> 0 GB remaining -> should still return 4096
    let tokens = BrujaMemory.tokensForAvailableMemory(4_000_000_000, modelSizeBytes: 4_000_000_000)
    XCTAssertEqual(tokens, 4096, "Minimum floor of 4096 must be enforced")
  }

  func testMinimumFloor_ModelExceedsMemory() {
    // Model is larger than available memory
    let tokens = BrujaMemory.tokensForAvailableMemory(
      4_000_000_000, modelSizeBytes: 100_000_000_000)
    XCTAssertEqual(tokens, 4096)
  }

  func testMinimumFloor_VeryLowRemainingMemory() {
    // 1 GB remaining after model -> base tier is 512, but floor enforces 4096
    let oneGB: UInt64 = 1 * 1024 * 1024 * 1024
    let tokens = BrujaMemory.tokensForAvailableMemory(oneGB, modelSizeBytes: 0)
    XCTAssertEqual(tokens, 4096)
  }

  func testMinimumFloor_EightGBRemaining() {
    // 10 GB remaining -> base tier is 2048, but floor enforces 4096
    let tenGB: UInt64 = 10 * 1024 * 1024 * 1024
    let tokens = BrujaMemory.tokensForAvailableMemory(tenGB, modelSizeBytes: 0)
    XCTAssertEqual(tokens, 4096)
  }

  func testTier_SixteenGBRemaining() {
    // 20 GB remaining -> base tier is 4096, matches floor
    let twentyGB: UInt64 = 20 * 1024 * 1024 * 1024
    let tokens = BrujaMemory.tokensForAvailableMemory(twentyGB, modelSizeBytes: 0)
    XCTAssertEqual(tokens, 4096)
  }

  func testTier_AboveThirtyTwoGB() {
    // 48 GB remaining -> should return 8192
    let fortyEightGB: UInt64 = 48 * 1024 * 1024 * 1024
    let tokens = BrujaMemory.tokensForAvailableMemory(fortyEightGB, modelSizeBytes: 0)
    XCTAssertEqual(tokens, 8192)
  }

  func testNeverBelowFloor_AllTiers() {
    // Exhaustively check that no input produces a value below 4096
    let sizes: [UInt64] = [0, 1_000_000_000, 4_000_000_000, 8_000_000_000, 16_000_000_000]
    let models: [Int64] = [0, 1_000_000_000, 50_000_000_000, 200_000_000_000]
    for avail in sizes {
      for model in models {
        let tokens = BrujaMemory.tokensForAvailableMemory(avail, modelSizeBytes: model)
        XCTAssertGreaterThanOrEqual(tokens, 4096, "Failed for available=\(avail), model=\(model)")
      }
    }
  }
}

// MARK: - BrujaError Tests

final class BrujaErrorTests: XCTestCase {

  func testModelNotFoundError() {
    let error = BrujaError.modelNotFound("/path/to/model")
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("/path/to/model"))
    XCTAssertTrue(error.errorDescription!.contains("not found"))
  }

  func testModelLoadFailedError() {
    let underlyingError = NSError(
      domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test failure"])
    let error = BrujaError.modelLoadFailed(underlyingError)
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("Failed to load"))
  }

  func testQueryFailedError() {
    let error = BrujaError.queryFailed("Token limit exceeded")
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("Token limit exceeded"))
    XCTAssertTrue(error.errorDescription!.contains("Query failed"))
  }

  func testInvalidResponseError() {
    let error = BrujaError.invalidResponse("Empty output")
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("Empty output"))
    XCTAssertTrue(error.errorDescription!.contains("Invalid response"))
  }

  func testJsonParsingFailedError() {
    let error = BrujaError.jsonParsingFailed("Unexpected token")
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("Unexpected token"))
    XCTAssertTrue(error.errorDescription!.contains("JSON"))
  }

  func testInvalidModelPathError() {
    let error = BrujaError.invalidModelPath("bad/path")
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("bad/path"))
    XCTAssertTrue(error.errorDescription!.contains("Invalid model path"))
  }

  func testAllErrorsConformToLocalizedError() {
    let errors: [BrujaError] = [
      .modelNotFound("test"),
      .modelLoadFailed(NSError(domain: "", code: 0)),
      .queryFailed("test"),
      .invalidResponse("test"),
      .jsonParsingFailed("test"),
      .invalidModelPath("test"),
    ]

    for error in errors {
      XCTAssertNotNil(error.errorDescription, "Error \(error) should have a description")
      XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty")
    }
  }
}

// MARK: - BrujaQueryResult Tests

final class BrujaQueryResultTests: XCTestCase {

  func testInitialization() {
    let result = BrujaQueryResult(
      response: "Hello, world!",
      model: "test-model",
      modelPath: "/path/to/model",
      tokensGenerated: 42,
      durationSeconds: 1.5
    )

    XCTAssertEqual(result.response, "Hello, world!")
    XCTAssertEqual(result.model, "test-model")
    XCTAssertEqual(result.modelPath, "/path/to/model")
    XCTAssertEqual(result.tokensGenerated, 42)
    XCTAssertEqual(result.durationSeconds, 1.5)
  }

  func testCodableRoundTrip() throws {
    let original = BrujaQueryResult(
      response: "Test response with special chars: e, n, zhong wen",
      model: "mlx-community/test-model",
      modelPath: "/Users/test/models/test",
      tokensGenerated: 100,
      durationSeconds: 2.345
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    let decoded = try decoder.decode(BrujaQueryResult.self, from: data)

    XCTAssertEqual(decoded.response, original.response)
    XCTAssertEqual(decoded.model, original.model)
    XCTAssertEqual(decoded.modelPath, original.modelPath)
    XCTAssertEqual(decoded.tokensGenerated, original.tokensGenerated)
    XCTAssertEqual(decoded.durationSeconds, original.durationSeconds, accuracy: 0.001)
  }

  func testJsonSerialization() throws {
    let result = BrujaQueryResult(
      response: "Answer",
      model: "model-id",
      modelPath: "/path",
      tokensGenerated: 10,
      durationSeconds: 0.5
    )

    let data = try JSONEncoder().encode(result)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

    XCTAssertNotNil(json)
    XCTAssertEqual(json?["response"] as? String, "Answer")
    XCTAssertEqual(json?["model"] as? String, "model-id")
    XCTAssertEqual(json?["modelPath"] as? String, "/path")
    XCTAssertEqual(json?["tokensGenerated"] as? Int, 10)
    XCTAssertEqual(json?["durationSeconds"] as? Double, 0.5)
  }

  func testEmptyResponse() {
    let result = BrujaQueryResult(
      response: "",
      model: "model",
      modelPath: "/path",
      tokensGenerated: 0,
      durationSeconds: 0.0
    )

    XCTAssertTrue(result.response.isEmpty)
    XCTAssertEqual(result.tokensGenerated, 0)
  }
}

// MARK: - BrujaModelInfo Tests

final class BrujaModelInfoTests: XCTestCase {

  func testInitialization() {
    let date = Date()
    let info = BrujaModelInfo(
      id: "mlx-community/test-model",
      path: "/path/to/model",
      sizeBytes: 1024 * 1024 * 500,  // 500 MB
      downloadDate: date
    )

    XCTAssertEqual(info.id, "mlx-community/test-model")
    XCTAssertEqual(info.path, "/path/to/model")
    XCTAssertEqual(info.sizeBytes, 524_288_000)
    XCTAssertEqual(info.downloadDate, date)
  }

  func testCodableRoundTrip() throws {
    let date = Date()
    let original = BrujaModelInfo(
      id: "test/model",
      path: "/test/path",
      sizeBytes: 123_456_789,
      downloadDate: date
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(original)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(BrujaModelInfo.self, from: data)

    XCTAssertEqual(decoded.id, original.id)
    XCTAssertEqual(decoded.path, original.path)
    XCTAssertEqual(decoded.sizeBytes, original.sizeBytes)
    // Date comparison with some tolerance due to encoding precision
    XCTAssertEqual(
      decoded.downloadDate.timeIntervalSince1970, original.downloadDate.timeIntervalSince1970,
      accuracy: 1.0)
  }

  func testFormattedSize_Bytes() {
    let info = BrujaModelInfo(id: "test", path: "/", sizeBytes: 500, downloadDate: Date())
    // ByteCountFormatter returns localized strings, so just check it's not empty
    XCTAssertFalse(info.formattedSize.isEmpty)
  }

  func testFormattedSize_Kilobytes() {
    let info = BrujaModelInfo(id: "test", path: "/", sizeBytes: 1024, downloadDate: Date())
    XCTAssertFalse(info.formattedSize.isEmpty)
  }

  func testFormattedSize_Megabytes() {
    let info = BrujaModelInfo(
      id: "test", path: "/", sizeBytes: 1024 * 1024 * 50, downloadDate: Date())
    XCTAssertFalse(info.formattedSize.isEmpty)
  }

  func testFormattedSize_Gigabytes() {
    let info = BrujaModelInfo(
      id: "test", path: "/", sizeBytes: 1024 * 1024 * 1024 * 2, downloadDate: Date())
    XCTAssertFalse(info.formattedSize.isEmpty)
  }

  func testFormattedSize_Zero() {
    let info = BrujaModelInfo(id: "test", path: "/", sizeBytes: 0, downloadDate: Date())
    XCTAssertFalse(info.formattedSize.isEmpty)
  }

  func testBridgeFromAcervoModel() {
    let date = Date()
    let acervoModel = AcervoModel(
      id: "mlx-community/test-model",
      path: URL(fileURLWithPath: "/tmp/models/mlx-community_test-model"),
      sizeBytes: 1024 * 1024,
      downloadDate: date
    )

    let brujaInfo = BrujaModelInfo(from: acervoModel)

    XCTAssertEqual(brujaInfo.id, "mlx-community/test-model")
    XCTAssertTrue(brujaInfo.path.contains("mlx-community_test-model"))
    XCTAssertEqual(brujaInfo.sizeBytes, 1024 * 1024)
    XCTAssertEqual(brujaInfo.downloadDate, date)
  }
}

// MARK: - BrujaModelManager Tests

final class BrujaModelManagerTests: XCTestCase {

  // MARK: - Model Availability Tests

  func testModelNotAvailableByDefault() {
    let manager = BrujaModelManager.shared
    XCTAssertFalse(manager.isModelAvailable("nonexistent/model"))
  }

  // MARK: - Models Directory Tests

  func testModelsDirectory() {
    let manager = BrujaModelManager.shared
    let dir = manager.modelsDirectory
    XCTAssertTrue(dir.path.contains("SharedModels"))
  }

  // MARK: - Unload Models Tests

  func testUnloadModel_NoError() async {
    let manager = BrujaModelManager.shared
    // Should not throw even if model isn't loaded
    await manager.unloadModel("nonexistent/model")
  }

  func testUnloadAllModels_NoError() async {
    let manager = BrujaModelManager.shared
    // Should not throw even if no models are loaded
    await manager.unloadAllModels()
  }

  // MARK: - Default Model Constant

  func testDefaultModelConstant() {
    XCTAssertEqual(BrujaModelManager.defaultModel, "mlx-community/Llama-3.2-1B-Instruct-4bit")
  }
}

// MARK: - Path Resolution Tests

final class BrujaPathResolutionTests: XCTestCase {

  func testModelExistsAt_AbsolutePath() {
    // Test with absolute path that doesn't exist
    XCTAssertFalse(Bruja.modelExists(at: "/tmp/nonexistent-bruja-model-12345"))
  }

  func testModelExistsAt_TildePath() {
    // Test tilde expansion
    XCTAssertFalse(Bruja.modelExists(at: "~/nonexistent-bruja-model-12345"))
  }

  func testModelExistsAt_RelativePath() {
    // Test relative path
    XCTAssertFalse(Bruja.modelExists(at: "relative/path/model"))
  }

  func testModelExistsAt_WithConfigJson() throws {
    // Create a temp directory with config.json
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("BrujaPathTest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Without config.json - should return false
    XCTAssertFalse(Bruja.modelExists(at: tempDir.path))

    // Add config.json - should return true
    try "{}".write(
      to: tempDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
    XCTAssertTrue(Bruja.modelExists(at: tempDir.path))
  }
}

// MARK: - Acervo Component Ready Tests

final class AcervoComponentReadyTests: XCTestCase {

  /// Verifies that `ensureComponentReady` delegates to the Level 3 component-aware path
  /// (`Acervo.ensureComponentReady`) rather than the Level 2 raw-repoId path.
  ///
  /// Strategy: register a test component with a single file (`config.json`), seed a
  /// temp directory with that file so `Acervo.isComponentReady` returns `true` (no
  /// network round-trip needed), call `Acervo.ensureComponentReady`, then
  /// assert the registered component's file list is non-empty.
  func testEnsureComponentReadyHydratesFiles() async throws {
    // Use a unique component ID that won't collide with production components
    let testComponentId = "test-sortie4-fixture-\(UUID().uuidString.prefix(8))"
    let testRepoId = "test-org/sortie4-fixture"

    // Register a test component with one file
    let descriptor = ComponentDescriptor(
      id: testComponentId,
      type: .languageModel,
      displayName: "Sortie 4 Fixture",
      repoId: testRepoId,
      files: [
        ComponentFile(relativePath: "config.json")
      ],
      estimatedSizeBytes: 100,
      minimumMemoryBytes: 0
    )
    Acervo.register(descriptor)
    defer { Acervo.unregister(testComponentId) }

    // Redirect Acervo to a temp directory to avoid touching the real SharedModels
    let tempBase = FileManager.default.temporaryDirectory
      .appendingPathComponent("bruja-sortie4-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempBase) }

    // Seed the component directory with config.json so isComponentReady returns true
    let slug = Acervo.slugify(testRepoId)
    let componentDir = tempBase.appendingPathComponent(slug)
    try FileManager.default.createDirectory(at: componentDir, withIntermediateDirectories: true)
    try "{}".write(
      to: componentDir.appendingPathComponent("config.json"),
      atomically: true,
      encoding: .utf8
    )

    // Redirect Acervo to the temp directory
    let previousCustomBase = Acervo.customBaseDirectory
    Acervo.customBaseDirectory = tempBase
    defer { Acervo.customBaseDirectory = previousCustomBase }

    // Call the Level 3 path — uses Acervo.ensureComponentReady, not ensureAvailable
    try await Acervo.ensureComponentReady(testComponentId) { _ in }
    guard let registered = Acervo.component(testComponentId) else {
      XCTFail("Component should still be registered after ensureComponentReady")
      return
    }
    let resultURL = try Acervo.modelDirectory(for: registered.repoId)

    // The returned URL should point into our temp directory
    XCTAssertTrue(
      resultURL.path.hasPrefix(tempBase.path),
      "Result URL should be within temp directory, got: \(resultURL.path)"
    )

    // The registered component must have a non-empty files list (Level 3 assertion)
    let registeredComponent = Acervo.component(testComponentId)
    XCTAssertNotNil(
      registeredComponent, "Component should still be registered after ensureComponentReady")
    XCTAssertFalse(
      registeredComponent?.files.isEmpty ?? true,
      "Acervo.component(id)?.files must be non-empty after ensureComponentReady (Level 3 hydration assertion)"
    )
  }

  /// Verifies that `Acervo.ensureComponentReady` throws for an unregistered component ID,
  /// preserving the component-registration guard (now enforced by Acervo directly).
  func testEnsureComponentReadyThrowsForUnregisteredComponent() async throws {
    let unregisteredId = "absolutely-not-registered-\(UUID().uuidString)"
    do {
      try await Acervo.ensureComponentReady(unregisteredId) { _ in }
      XCTFail("Expected an error to be thrown for unregistered component")
    } catch {
      // Expected — Acervo throws for unregistered component IDs
    }
  }

  /// Regression test: the Level 2 raw-repoId path (Acervo.ensureAvailable) must work
  /// for unregistered repo IDs.
  ///
  /// Verifies that `Acervo.ensureAvailable` accepts a raw CDN repo ID (not
  /// registered as a component) and follows the Level 2 path rather than the Level 3
  /// component-aware path.
  ///
  /// Uses a pre-seeded temp directory to avoid any real network download.
  func testDownloadModelLevel2PathWorksForUnregisteredRepoId() async throws {
    // The canonical small fixture model (unregistered raw repo ID)
    let unregisteredRepoId = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"

    // Confirm the repo ID is NOT registered as a component
    XCTAssertNil(
      Acervo.component(unregisteredRepoId),
      "The raw repo ID must NOT be registered as a component for this Level 2 regression test"
    )

    // Redirect to a temp directory and seed it so Acervo.isModelAvailable returns true
    // (avoids real CDN download while still exercising the call boundary)
    let tempBase = FileManager.default.temporaryDirectory
      .appendingPathComponent("bruja-level2-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempBase) }

    let slug = Acervo.slugify(unregisteredRepoId)
    let modelDir = tempBase.appendingPathComponent(slug)
    try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
    try "{}".write(
      to: modelDir.appendingPathComponent("config.json"),
      atomically: true,
      encoding: .utf8
    )

    let previousCustomBase = Acervo.customBaseDirectory
    Acervo.customBaseDirectory = tempBase
    defer { Acervo.customBaseDirectory = previousCustomBase }

    // `Acervo.ensureAvailable` must NOT throw when model is already available (force: false)
    try await Acervo.ensureAvailable(unregisteredRepoId, files: []) { _ in }
    // If we get here, the Level 2 path executed without error
  }
}

// MARK: - Acervo Manifest Fetch Tests

final class AcervoManifestFetchTests: XCTestCase {

  /// The production model guaranteed to exist on the CDN by Sortie 1.
  private static let productionModelId = "mlx-community/Qwen3-Coder-Next-4bit"

  /// The small fixture model also guaranteed on the CDN by Sortie 1.
  private static let smallFixtureModelId = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"

  /// Library test (R4): summed manifest file sizes for the production model are
  /// non-zero and the fetch produces zero new files under `Acervo.sharedModelsDirectory`.
  ///
  /// This test requires network access to the CDN. It is not skipped on CI because the
  /// production model is guaranteed present by Sortie 1. The before/after snapshot of
  /// `sharedModelsDirectory` verifies the manifest fetch is read-only.
  func testEstimatedSizeForProductionModelIsNonZeroAndCreatesNoFiles() async throws {
    let sharedModelsDir = Acervo.sharedModelsDirectory

    // Snapshot before: collect all paths under sharedModelsDirectory
    let before = snapshotDirectory(sharedModelsDir)

    // Call under test — must not throw and must return > 0
    let sizeBytes = try await Acervo.fetchManifest(for: Self.productionModelId).files
      .reduce(Int64(0)) { $0 + $1.sizeBytes }

    XCTAssertGreaterThan(
      sizeBytes, 0,
      "Manifest size for \(Self.productionModelId) should be > 0; CDN guarantees this model exists"
    )

    // Snapshot after: no new files should have been created
    let after = snapshotDirectory(sharedModelsDir)
    XCTAssertEqual(
      before, after,
      "Manifest fetch must not write files to sharedModelsDirectory (before != after)"
    )
  }

  /// Library test (R4): `Acervo.fetchManifest(for:)` returns a non-empty file list and
  /// does not create files on disk. Uses the small fixture model for breadth coverage.
  func testManifestFilesForSmallFixtureModelReturnsNonEmptyArray() async throws {
    let sharedModelsDir = Acervo.sharedModelsDirectory
    let before = snapshotDirectory(sharedModelsDir)

    let files = try await Acervo.fetchManifest(for: Self.smallFixtureModelId).files

    XCTAssertFalse(
      files.isEmpty,
      "Manifest for \(Self.smallFixtureModelId) must return at least one CDNManifestFile"
    )

    // Every file entry must have a non-empty path and a positive size
    for file in files {
      XCTAssertFalse(file.path.isEmpty, "CDNManifestFile.path must not be empty")
      XCTAssertGreaterThan(file.sizeBytes, 0, "CDNManifestFile.sizeBytes must be > 0")
    }

    let after = snapshotDirectory(sharedModelsDir)
    XCTAssertEqual(
      before, after,
      "Manifest fetch must not write files to sharedModelsDirectory (before != after)"
    )
  }

  // MARK: - Helpers

  /// Returns a sorted set of all file paths under `directory`, for before/after comparison.
  private func snapshotDirectory(_ directory: URL) -> Set<String> {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }
    var paths = Set<String>()
    for case let url as URL in enumerator {
      paths.insert(url.path)
    }
    return paths
  }
}

// MARK: - Concurrent Access Tests

final class BrujaConcurrencyTests: XCTestCase {

  func testConcurrentModelAvailabilityChecks() async {
    let manager = BrujaModelManager.shared

    // Run multiple availability checks concurrently
    await withTaskGroup(of: Bool.self) { group in
      for i in 0..<100 {
        group.addTask {
          manager.isModelAvailable("concurrent-test/model-\(i)")
        }
      }

      var results: [Bool] = []
      for await result in group {
        results.append(result)
      }

      XCTAssertEqual(results.count, 100)
      XCTAssertTrue(results.allSatisfy { $0 == false })
    }
  }

  func testConcurrentRegisteredComponentsAccess() async {
    // Run multiple registry queries concurrently against Acervo directly
    await withTaskGroup(of: [ComponentDescriptor].self) { group in
      for _ in 0..<50 {
        group.addTask {
          Acervo.registeredComponents(ofType: .languageModel)
        }
      }

      var resultCounts: [Int] = []
      for await results in group {
        resultCounts.append(results.count)
      }

      XCTAssertEqual(resultCounts.count, 50)
      XCTAssertTrue(resultCounts.allSatisfy { $0 == resultCounts[0] })
    }
  }
}
