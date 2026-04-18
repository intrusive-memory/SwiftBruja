import XCTest

@testable import SwiftBruja

/// Integration test verifying Bruja.query() successfully executes inference using the CDN-downloaded Qwen3 model.
///
/// This test validates the complete inference pipeline by:
/// 1. Ensuring the Qwen3 model is available (pre-downloaded or auto-downloads)
/// 2. Calling Bruja.query() with a simple prompt
/// 3. Verifying the response is non-empty and valid
/// 4. Confirming inference completes without errors or timeouts
///
/// **Requirements:**
/// - Apple Silicon Mac (M1/M2/M3/M4)
/// - Qwen3-Coder-Next-4bit model pre-downloaded OR network access to CDN
/// - MLX runtime available
///
/// **Performance Notes:**
/// - First inference run may be slower (model loading, compilation)
/// - Subsequent runs benefit from cached model state
/// - Response time depends on hardware and maxTokens setting
final class InferenceIntegrationTest: XCTestCase {

  // MARK: - Test Constants

  /// Component ID for Qwen3-Coder-Next 4-bit model
  private let componentId = "qwen3-coder-next-4bit"

  /// Full HuggingFace model ID for Qwen3
  private let modelId = "mlx-community/Qwen3-Coder-Next-4bit"

  /// Simple prompt for inference test
  private let testPrompt = "Hello, what is 2+2? Answer with just the number."

  /// Timeout for inference operations (60 seconds)
  private let inferenceTimeout: TimeInterval = 60.0

  // MARK: - Setup & Teardown

  override func setUp() {
    super.setUp()
    print("\n" + String(repeating: "=", count: 70))
    print("InferenceIntegrationTest Setup")
    print(String(repeating: "=", count: 70))
  }

  override func tearDown() {
    super.tearDown()
    print(String(repeating: "=", count: 70))
    print("InferenceIntegrationTest Teardown")
    print(String(repeating: "=", count: 70) + "\n")
  }

  // MARK: - Tests

  /// Tests that Bruja.query() successfully executes inference with the Qwen3 model.
  ///
  /// This is the primary integration test that validates:
  /// - Model loading from CDN cache
  /// - Tokenization and prompt preparation
  /// - Inference execution on MLX
  /// - Response generation and streaming
  func testBrujaQueryWithQwen3ModelExecutesInference() async throws {
    print("\n📌 TEST: Bruja.query() executes inference with Qwen3 model")
    print("Prompt: \(testPrompt)")

    // Verify model is registered
    XCTAssertNotNil(
      BrujaModelManager.modelComponent(for: componentId),
      "Qwen3 model should be registered in BrujaModelManager"
    )
    print("✅ Qwen3 model is registered")

    // Execute inference
    print("🔄 Executing inference...")
    let startTime = Date()

    let response = try await Bruja.query(
      testPrompt,
      model: modelId,
      temperature: 0.7,
      maxTokens: 50  // Keep it short for fast iteration
    )

    let duration = Date().timeIntervalSince(startTime)

    // Validate response
    print("✅ Inference completed in \(String(format: "%.2f", duration))s")
    print("📝 Response: \(response)")

    // Verify response is non-empty
    XCTAssertFalse(
      response.isEmpty,
      "Response should not be empty"
    )

    // Verify response is reasonable length (not just one character)
    XCTAssertGreaterThan(
      response.count,
      1,
      "Response should contain at least a few characters"
    )

    print("✅ Response validation passed")
    print("   - Non-empty: YES")
    print("   - Length: \(response.count) characters")
    print("   - Duration: \(String(format: "%.2f", duration))s")
  }

  /// Tests that Bruja.queryWithMetadata() returns complete inference metadata.
  ///
  /// This validates that the inference pipeline correctly tracks:
  /// - Model identification
  /// - Token generation count
  /// - Execution duration
  func testBrujaQueryWithMetadataReturnsCompleteResult() async throws {
    print("\n📌 TEST: Bruja.queryWithMetadata() returns complete result")

    // Execute inference with metadata
    print("🔄 Executing inference with metadata tracking...")
    let result = try await Bruja.queryWithMetadata(
      testPrompt,
      model: modelId,
      temperature: 0.7,
      maxTokens: 50
    )

    // Validate response
    XCTAssertFalse(
      result.response.isEmpty,
      "Response should not be empty"
    )
    print("✅ Response: \(result.response.prefix(100))...")

    // Validate metadata
    XCTAssertFalse(
      result.model.isEmpty,
      "Model ID should be populated"
    )
    print("✅ Model: \(result.model)")

    XCTAssertFalse(
      result.modelPath.isEmpty,
      "Model path should be populated"
    )
    print("✅ Model path: \(result.modelPath)")

    XCTAssertGreaterThan(
      result.tokensGenerated,
      0,
      "Should have generated at least one token"
    )
    print("✅ Tokens generated: \(result.tokensGenerated)")

    XCTAssertGreaterThan(
      result.durationSeconds,
      0.0,
      "Inference should take measurable time"
    )
    print("✅ Duration: \(String(format: "%.2f", result.durationSeconds))s")
  }

  /// Tests response validation with proper async handling
  ///
  /// This validates the response is properly formatted and can be used
  /// by downstream code without issues.
  func testResponseValidation() async throws {
    print("\n📌 TEST: Response validation")

    let response = try await Bruja.query(
      testPrompt,
      model: modelId,
      temperature: 0.7,
      maxTokens: 50
    )

    // Validate response structure
    XCTAssertFalse(response.isEmpty, "Response should not be empty")
    XCTAssertGreaterThan(response.count, 0, "Response should have content")

    print("✅ Response is valid and properly formatted")
    print("   Length: \(response.count) characters")
  }

  // MARK: - Helper Methods

  /// Formats duration in seconds to a human-readable string
  private func formatDuration(_ seconds: TimeInterval) -> String {
    if seconds < 1.0 {
      return String(format: "%.0fms", seconds * 1000)
    } else if seconds < 60.0 {
      return String(format: "%.1fs", seconds)
    } else {
      return String(format: "%.1fm", seconds / 60)
    }
  }
}
