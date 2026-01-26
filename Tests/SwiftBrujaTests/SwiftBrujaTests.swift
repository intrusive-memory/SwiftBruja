import XCTest
@testable import SwiftBruja

final class SwiftBrujaTests: XCTestCase {
    func testBrujaDefaultModel() {
        XCTAssertEqual(Bruja.defaultModel, "mlx-community/Phi-3-mini-4k-instruct-4bit")
    }

    func testModelDirectory() {
        let manager = BrujaModelManager.shared
        let dir = manager.modelDirectory(for: "mlx-community/test-model")
        XCTAssertTrue(dir.path.contains("mlx-community_test-model"))
    }

    func testModelNotAvailableByDefault() {
        let manager = BrujaModelManager.shared
        XCTAssertFalse(manager.isModelAvailable("nonexistent/model"))
    }
}
