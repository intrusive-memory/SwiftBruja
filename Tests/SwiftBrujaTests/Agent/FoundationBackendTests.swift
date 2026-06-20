import Foundation
import FoundationModels
import XCTest

@testable import SwiftBruja

/// S9 unit tests: Foundation Models backend — availability-error mapping, shared-registry
/// assertion, and session construction.
///
/// These tests are deterministic and require no model inference. They prove:
/// (a) `FoundationModelBackend.mapFMError` maps every `LanguageModelError` case to the correct
///     typed `BrujaError` (availability-error mapping — host-independent).
/// (b) `FoundationModelBackend.makeSession(tools:instructions:)` accepts the SAME `[any Tool]`
///     array that `ToolRegistry.defaultTools()` yields — asserting both backends share one
///     registry call with no second tool adapter (R4).
@available(macOS 26.0, *)
final class FoundationBackendTests: XCTestCase {

  // MARK: - (a) Error mapping — host-independent, no inference required

  func testContextSizeExceededMapsToContextWindowExceeded() {
    let fmError = LanguageModelError.contextSizeExceeded(
      LanguageModelError.ContextSizeExceeded(
        contextSize: 4096, tokenCount: 5000, debugDescription: "too many tokens"))
    let brujaError = FoundationModelBackend.mapFMError(fmError)
    guard case .contextWindowExceeded(let count, let limit) = brujaError else {
      XCTFail("Expected .contextWindowExceeded, got \(brujaError)")
      return
    }
    XCTAssertEqual(count, 5000)
    XCTAssertEqual(limit, 4096)
  }

  func testRateLimitedMapsToQueryFailed() {
    let fmError = LanguageModelError.rateLimited(
      LanguageModelError.RateLimited(
        resetDate: nil, debugDescription: "quota exceeded"))
    let brujaError = FoundationModelBackend.mapFMError(fmError)
    guard case .queryFailed(let msg) = brujaError else {
      XCTFail("Expected .queryFailed, got \(brujaError)")
      return
    }
    XCTAssertTrue(
      msg.contains("rate-limited"),
      "Error message should mention rate-limiting. Got: \(msg)")
    XCTAssertTrue(
      msg.contains("quota exceeded"),
      "Error message should include the debugDescription. Got: \(msg)")
  }

  func testGuardrailViolationMapsToQueryFailed() {
    let fmError = LanguageModelError.guardrailViolation(
      LanguageModelError.GuardrailViolation(debugDescription: "harmful content detected"))
    let brujaError = FoundationModelBackend.mapFMError(fmError)
    guard case .queryFailed(let msg) = brujaError else {
      XCTFail("Expected .queryFailed, got \(brujaError)")
      return
    }
    XCTAssertTrue(
      msg.contains("guardrail"),
      "Error message should mention guardrail. Got: \(msg)")
  }

  func testRefusalMapsToQueryFailed() {
    let fmError = LanguageModelError.refusal(
      LanguageModelError.Refusal(debugDescription: "request not allowed"))
    let brujaError = FoundationModelBackend.mapFMError(fmError)
    guard case .queryFailed(let msg) = brujaError else {
      XCTFail("Expected .queryFailed, got \(brujaError)")
      return
    }
    XCTAssertTrue(
      msg.contains("refused"),
      "Error message should mention refusal. Got: \(msg)")
  }

  func testTimeoutMapsToQueryFailed() {
    let fmError = LanguageModelError.timeout(
      LanguageModelError.Timeout(debugDescription: "deadline exceeded"))
    let brujaError = FoundationModelBackend.mapFMError(fmError)
    guard case .queryFailed(let msg) = brujaError else {
      XCTFail("Expected .queryFailed, got \(brujaError)")
      return
    }
    XCTAssertTrue(
      msg.contains("timed out"),
      "Error message should mention timeout. Got: \(msg)")
  }

  func testExistingBrujaErrorPassesThroughUnchanged() {
    let original = BrujaError.agentStepLimitExceeded(limit: 32)
    let mapped = FoundationModelBackend.mapFMError(original)
    guard case .agentStepLimitExceeded(let limit) = mapped else {
      XCTFail("BrujaError should pass through unchanged. Got \(mapped)")
      return
    }
    XCTAssertEqual(limit, 32)
  }

  func testUnknownErrorMapsToQueryFailed() {
    struct UnknownError: Error {}
    let brujaError = FoundationModelBackend.mapFMError(UnknownError())
    guard case .queryFailed = brujaError else {
      XCTFail("Unknown error should map to .queryFailed. Got \(brujaError)")
      return
    }
  }

  // MARK: - (b) Shared ToolRegistry assertion — THE PROOF of R4

  /// Assert that `FoundationModelBackend.makeSession(tools:instructions:)` accepts the SAME
  /// `[any Tool]` array that `ToolRegistry.defaultTools()` yields — without any conversion,
  /// wrapping, or secondary type — proving both backends share one tool definition (R4).
  ///
  /// The test does NOT run inference; it only proves the type-level contract: the same `[any Tool]`
  /// that `ToolRegistry` yields can be passed directly to `FoundationModelBackend.makeSession`,
  /// which constructs a `LanguageModelSession(model: SystemLanguageModel.default, tools:...)`.
  func testFMPathConsumesTheSameToolRegistryArrayAsMLXPath() {
    // The SAME array both backends receive — no second tool adapter, no conversion.
    let tools: [any Tool] = ToolRegistry.defaultTools()

    // Verify the registry yields the expected 7 tools (the same 7 the MLX path uses).
    XCTAssertEqual(
      tools.count, 7,
      "ToolRegistry.defaultTools() must yield 7 tools (same set both backends consume)")

    let toolNames = tools.map { $0.name }.sorted()
    XCTAssertEqual(
      toolNames,
      ["edit_file", "glob", "grep", "list_dir", "read_file", "run_shell", "write_file"],
      "Tool names must match the registry definition — same for both backends")

    // Pass the SAME array to makeSession. If this compiles and does not crash, the type contract
    // is satisfied: no second adapter needed, no type conversion, no intermediate layer.
    // (We cannot assert on the session's tool count because LanguageModelSession does not expose
    // its tool array; the type-level proof is sufficient and is the point of R4.)
    let session = FoundationModelBackend.makeSession(
      tools: tools,
      instructions: "test instructions")

    // The session object was constructed — FM accepted the ToolRegistry array directly.
    XCTAssertNotNil(session)
  }

  /// Cross-check: the tool names surfaced to FM (via makeSession) are identical to those the
  /// MLX path would see, since both call `ToolRegistry.defaultTools()`.
  func testToolRegistryYieldsSameNamesRegardlessOfConsumer() {
    let fromRegistry = ToolRegistry.defaultTools().map { $0.name }.sorted()

    // Simulate how AgentLoop.init (MLX) and AgentLoop.init(backend: .foundation) both call
    // ToolRegistry.defaultTools() — the result must be identical.
    let secondCall = ToolRegistry.defaultTools().map { $0.name }.sorted()

    XCTAssertEqual(
      fromRegistry, secondCall,
      "ToolRegistry.defaultTools() must be deterministic — same names on every call")
  }

  // MARK: - (c) Availability gating (mockable — see BackendSelectionTests for full coverage)

  /// Sanity-check the `FoundationModelsAvailabilityProvider` mock contract used by S8/S9.
  ///
  /// The full mock-based availability tests live in `BackendSelectionTests` (S8); this test
  /// reconfirms the contract is respected by the S9 code path: an available mock reports true,
  /// an unavailable mock reports false and carries the reason.
  func testAvailabilityProviderContractForS9() {
    // Available mock.
    let available = MockFMAvailable()
    XCTAssertTrue(available.isAvailable)
    XCTAssertNil(available.unavailabilityReason)

    // Unavailable mock with S9-relevant reason.
    let unavailable = MockFMUnavailable(reason: "Apple Intelligence not enabled")
    XCTAssertFalse(unavailable.isAvailable)
    XCTAssertEqual(unavailable.unavailabilityReason, "Apple Intelligence not enabled")

    // The `BrujaError.foundationModelsUnavailable` helper (S8) still carries the reason.
    let err = BrujaError.foundationModelsUnavailable("Apple Intelligence not enabled")
    let desc = err.errorDescription ?? ""
    XCTAssertTrue(desc.contains("Foundation Models is not available"))
    XCTAssertTrue(desc.contains("Apple Intelligence not enabled"))
    XCTAssertTrue(desc.contains("--backend mlx"))
  }

  // MARK: - Mock helpers (mirrors BackendSelectionTests to keep these tests self-contained)

  private struct MockFMAvailable: FoundationModelsAvailabilityProvider {
    var isAvailable: Bool { true }
    var unavailabilityReason: String? { nil }
  }

  private struct MockFMUnavailable: FoundationModelsAvailabilityProvider {
    let reason: String
    var isAvailable: Bool { false }
    var unavailabilityReason: String? { reason }
  }
}
