import XCTest
@testable import SwiftBruja

final class SwiftBrujaTests: XCTestCase {

    // MARK: - Bruja Static Properties

    func testBrujaDefaultModel() {
        XCTAssertEqual(Bruja.defaultModel, "mlx-community/Phi-3-mini-4k-instruct-4bit")
    }

    func testBrujaDefaultModelsDirectory() {
        let dir = Bruja.defaultModelsDirectory
        XCTAssertTrue(dir.path.contains("intrusive-memory/Models"))
        XCTAssertTrue(dir.path.contains("LLM"))
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

    func testListModels_EmptyDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrujaTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let models = try Bruja.listModels(in: tempDir)
        XCTAssertTrue(models.isEmpty)
    }

    func testListModels_NonexistentDirectory() throws {
        let nonexistentDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NonexistentDir-\(UUID().uuidString)")

        let models = try Bruja.listModels(in: nonexistentDir)
        XCTAssertTrue(models.isEmpty)
    }
}

// MARK: - BrujaError Tests

final class BrujaErrorTests: XCTestCase {

    func testModelNotDownloadedError() {
        let error = BrujaError.modelNotDownloaded("test-model")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("test-model"))
        XCTAssertTrue(error.errorDescription!.contains("not downloaded"))
    }

    func testModelNotFoundError() {
        let error = BrujaError.modelNotFound("/path/to/model")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("/path/to/model"))
        XCTAssertTrue(error.errorDescription!.contains("not found"))
    }

    func testModelLoadFailedError() {
        let underlyingError = NSError(domain: "TestDomain", code: 123, userInfo: [NSLocalizedDescriptionKey: "Test failure"])
        let error = BrujaError.modelLoadFailed(underlyingError)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Failed to load"))
    }

    func testDownloadFailedError() {
        let error = BrujaError.downloadFailed("Network timeout")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Network timeout"))
        XCTAssertTrue(error.errorDescription!.contains("download failed"))
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
            .modelNotDownloaded("test"),
            .modelNotFound("test"),
            .modelLoadFailed(NSError(domain: "", code: 0)),
            .downloadFailed("test"),
            .queryFailed("test"),
            .invalidResponse("test"),
            .jsonParsingFailed("test"),
            .invalidModelPath("test")
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
            response: "Test response with special chars: é, ñ, 中文",
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
            sizeBytes: 1024 * 1024 * 500, // 500 MB
            downloadDate: date
        )

        XCTAssertEqual(info.id, "mlx-community/test-model")
        XCTAssertEqual(info.path, "/path/to/model")
        XCTAssertEqual(info.sizeBytes, 524288000)
        XCTAssertEqual(info.downloadDate, date)
    }

    func testCodableRoundTrip() throws {
        let date = Date()
        let original = BrujaModelInfo(
            id: "test/model",
            path: "/test/path",
            sizeBytes: 123456789,
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
        XCTAssertEqual(decoded.downloadDate.timeIntervalSince1970, original.downloadDate.timeIntervalSince1970, accuracy: 1.0)
    }

    func testFormattedSize_Bytes() {
        let info = BrujaModelInfo(id: "test", path: "/", sizeBytes: 500, downloadDate: Date())
        // ByteCountFormatter returns localized strings, so just check it's not empty
        XCTAssertFalse(info.formattedSize.isEmpty)
    }

    func testFormattedSize_Kilobytes() {
        let info = BrujaModelInfo(id: "test", path: "/", sizeBytes: 1024, downloadDate: Date())
        XCTAssertFalse(info.formattedSize.isEmpty)
        // Should be ~1 KB
    }

    func testFormattedSize_Megabytes() {
        let info = BrujaModelInfo(id: "test", path: "/", sizeBytes: 1024 * 1024 * 50, downloadDate: Date())
        XCTAssertFalse(info.formattedSize.isEmpty)
        // Should be ~50 MB
    }

    func testFormattedSize_Gigabytes() {
        let info = BrujaModelInfo(id: "test", path: "/", sizeBytes: 1024 * 1024 * 1024 * 2, downloadDate: Date())
        XCTAssertFalse(info.formattedSize.isEmpty)
        // Should be ~2 GB
    }

    func testFormattedSize_Zero() {
        let info = BrujaModelInfo(id: "test", path: "/", sizeBytes: 0, downloadDate: Date())
        XCTAssertFalse(info.formattedSize.isEmpty)
        // Should handle zero bytes gracefully
    }
}

// MARK: - BrujaModelManager Tests

final class BrujaModelManagerTests: XCTestCase {

    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrujaModelManagerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - Model Directory Tests

    func testModelDirectory() {
        let manager = BrujaModelManager.shared
        let dir = manager.modelDirectory(for: "mlx-community/test-model")
        XCTAssertTrue(dir.path.contains("mlx-community_test-model"))
    }

    func testModelDirectory_SlashReplacement() {
        let manager = BrujaModelManager.shared
        let dir = manager.modelDirectory(for: "org/sub/model")
        XCTAssertTrue(dir.path.contains("org_sub_model"))
        XCTAssertFalse(dir.lastPathComponent.contains("/"))
    }

    func testModelDirectory_SimpleId() {
        let manager = BrujaModelManager.shared
        let dir = manager.modelDirectory(for: "simple-model")
        XCTAssertTrue(dir.lastPathComponent == "simple-model")
    }

    // MARK: - Model Availability Tests

    func testModelNotAvailableByDefault() {
        let manager = BrujaModelManager.shared
        XCTAssertFalse(manager.isModelAvailable("nonexistent/model"))
    }

    func testIsModelAvailable_EmptyDirectory() throws {
        let manager = BrujaModelManager.shared
        // Create an empty directory (no config.json)
        let modelDir = tempDirectory.appendingPathComponent("empty-model")
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Model should not be considered available without config.json
        XCTAssertFalse(manager.isModelAvailable("nonexistent/empty-model"))
    }

    // MARK: - Models Directory Tests

    func testModelsDirectory() {
        let manager = BrujaModelManager.shared
        let dir = manager.modelsDirectory
        XCTAssertTrue(dir.path.contains("Caches"))
        XCTAssertTrue(dir.path.contains("intrusive-memory/Models/LLM"))
    }

    // MARK: - List Models Tests

    func testListModels_EmptyDirectory() throws {
        let manager = BrujaModelManager.shared
        let models = try manager.listModels(in: tempDirectory)
        XCTAssertTrue(models.isEmpty)
    }

    func testListModels_NonexistentDirectory() throws {
        let manager = BrujaModelManager.shared
        let nonexistentDir = tempDirectory.appendingPathComponent("nonexistent")
        let models = try manager.listModels(in: nonexistentDir)
        XCTAssertTrue(models.isEmpty)
    }

    func testListModels_WithValidModel() throws {
        let manager = BrujaModelManager.shared

        // Create a fake model directory with config.json
        let modelDir = tempDirectory.appendingPathComponent("test_model")
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try "{}".write(to: modelDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)

        let models = try manager.listModels(in: tempDirectory)
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models.first?.id, "test/model") // Underscore converted back to slash
    }

    func testListModels_IgnoresFilesWithoutConfigJson() throws {
        let manager = BrujaModelManager.shared

        // Create a directory without config.json
        let invalidDir = tempDirectory.appendingPathComponent("invalid_model")
        try FileManager.default.createDirectory(at: invalidDir, withIntermediateDirectories: true)
        try "test".write(to: invalidDir.appendingPathComponent("other.txt"), atomically: true, encoding: .utf8)

        let models = try manager.listModels(in: tempDirectory)
        XCTAssertTrue(models.isEmpty)
    }

    func testListModels_MultipleModels() throws {
        let manager = BrujaModelManager.shared

        // Create multiple fake models
        for i in 1...3 {
            let modelDir = tempDirectory.appendingPathComponent("model_\(i)")
            try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
            try "{}".write(to: modelDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        }

        let models = try manager.listModels(in: tempDirectory)
        XCTAssertEqual(models.count, 3)
    }

    // MARK: - Model Info Tests

    func testModelInfo_ValidModel() throws {
        let manager = BrujaModelManager.shared

        // Create a fake model with some content
        let modelDir = tempDirectory.appendingPathComponent("info_test_model")
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try "{}".write(to: modelDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try "tokenizer data".write(to: modelDir.appendingPathComponent("tokenizer.json"), atomically: true, encoding: .utf8)

        let info = try manager.modelInfo(at: modelDir)

        XCTAssertEqual(info.id, "info/test/model") // Underscores become slashes
        XCTAssertEqual(info.path, modelDir.path)
        XCTAssertGreaterThan(info.sizeBytes, 0)
        XCTAssertNotNil(info.downloadDate)
    }

    func testModelInfo_NonexistentPath() {
        let manager = BrujaModelManager.shared
        let nonexistentPath = tempDirectory.appendingPathComponent("nonexistent")

        XCTAssertThrowsError(try manager.modelInfo(at: nonexistentPath)) { error in
            guard let brujaError = error as? BrujaError else {
                XCTFail("Expected BrujaError")
                return
            }
            if case .modelNotFound = brujaError {
                // Expected
            } else {
                XCTFail("Expected modelNotFound error")
            }
        }
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

    // MARK: - Delete Model Tests

    func testDeleteModel_ExistingModel() async throws {
        let manager = BrujaModelManager.shared

        // Create a fake model
        let modelId = "delete_test_model"
        let modelDir = manager.modelDirectory(for: modelId)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try "{}".write(to: modelDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: modelDir.path))

        try await manager.deleteModel(modelId)

        XCTAssertFalse(FileManager.default.fileExists(atPath: modelDir.path))
    }

    func testDeleteModel_NonexistentModel() async throws {
        let manager = BrujaModelManager.shared
        // Should not throw for nonexistent model
        try await manager.deleteModel("nonexistent_model_to_delete")
    }

    // MARK: - Default Model Constant

    func testDefaultModelConstant() {
        XCTAssertEqual(BrujaModelManager.defaultModel, "mlx-community/Phi-3-mini-4k-instruct-4bit")
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
        try "{}".write(to: tempDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        XCTAssertTrue(Bruja.modelExists(at: tempDir.path))
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
                    manager.isModelAvailable("concurrent-test-model-\(i)")
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

    func testConcurrentModelDirectoryAccess() async {
        let manager = BrujaModelManager.shared

        await withTaskGroup(of: URL.self) { group in
            for i in 0..<100 {
                group.addTask {
                    manager.modelDirectory(for: "test/model-\(i)")
                }
            }

            var results: [URL] = []
            for await result in group {
                results.append(result)
            }

            XCTAssertEqual(results.count, 100)
            // Verify all paths are unique
            let uniquePaths = Set(results.map { $0.path })
            XCTAssertEqual(uniquePaths.count, 100)
        }
    }
}
