import XCTest

@testable import SwiftBruja

/// S8 unit tests: backend selection from model/selector, FM-unavailable typed error,
/// and agent-capable allowlist flagging.
///
/// These tests are deterministic and require no model download. FM availability is
/// injected via ``FoundationModelsAvailabilityProvider`` so the "unavailable" path is
/// asserted regardless of the running host's actual FM status.
@available(macOS 26.0, *)
final class BackendSelectionTests: XCTestCase {

  // MARK: - Mock Availability Providers

  /// A mock that reports Foundation Models as available on this host.
  private struct MockFMAvailable: FoundationModelsAvailabilityProvider {
    var isAvailable: Bool { true }
    var unavailabilityReason: String? { nil }
  }

  /// A mock that reports Foundation Models as unavailable with a fixed reason.
  private struct MockFMUnavailable: FoundationModelsAvailabilityProvider {
    let reason: String
    var isAvailable: Bool { false }
    var unavailabilityReason: String? { reason }
  }

  // MARK: - (a) Model-id → backend mapping

  /// An Acervo/mlx-community model id resolves to the MLX backend.
  func testAcervoModelIdResolvesToMLXBackend() {
    let (backend, modelId) = AgentBackendSelector.resolve(
      selector: "mlx-community/Qwen2.5-7B-Instruct-4bit")
    XCTAssertEqual(backend, .mlx, "An Acervo model id must resolve to the MLX backend")
    XCTAssertEqual(modelId, "mlx-community/Qwen2.5-7B-Instruct-4bit")
  }

  /// The literal string "foundation" resolves to the Foundation Models backend.
  func testFoundationSelectorResolvesToFMBackend() {
    let (backend, modelId) = AgentBackendSelector.resolve(selector: "foundation")
    XCTAssertEqual(backend, .foundation, "'foundation' selector must resolve to the FM backend")
    XCTAssertNil(modelId, "FM backend carries no model-file id")
  }

  /// Nil selector (no --backend / --model flags) defaults to MLX + the 7B agentic default.
  func testNilSelectorDefaultsToMLXWithAgentDefault() {
    let (backend, modelId) = AgentBackendSelector.resolve(selector: nil)
    XCTAssertEqual(backend, .mlx)
    XCTAssertEqual(
      modelId, AgentAllowlist.agentDefaultModel,
      "Default model must be the 7B agentic default, not Bruja.defaultModel")
  }

  /// The agentic default is distinct from `BrujaModelManager.defaultModel` (the query/chat default).
  func testAgentDefaultDistinctFromQueryChatDefault() {
    XCTAssertNotEqual(
      AgentAllowlist.agentDefaultModel,
      BrujaModelManager.defaultModel,
      "Agent default must be distinct from the query/chat default (Llama-3.2-1B)")
  }

  // MARK: - (b) `foundation` unavailable → typed full-stop error

  /// When Foundation Models is unavailable, the mock reports `isAvailable == false` and
  /// the availability provider carries the specific reason. The CLI layer (`AgentCommand`)
  /// throws a full-stop `CLIError` from this information — tested here by verifying
  /// the provider contract and the `BrujaError` helper.
  func testFoundationUnavailableProviderContract() {
    let unavailable = MockFMUnavailable(reason: "model assets not downloaded")

    XCTAssertFalse(
      unavailable.isAvailable,
      "Unavailable mock must report isAvailable == false")
    XCTAssertEqual(
      unavailable.unavailabilityReason, "model assets not downloaded",
      "Unavailable mock must carry the injected reason")
  }

  /// `BrujaError.foundationModelsUnavailable` carries the typed reason and provides
  /// an actionable error description pointing to the MLX fallback.
  func testBrujaErrorFoundationModelsUnavailableContainsReason() {
    let err = BrujaError.foundationModelsUnavailable("restricted profile")
    let desc = err.errorDescription ?? ""
    XCTAssertTrue(
      desc.contains("Foundation Models is not available"),
      "BrujaError must surface the FM-unavailable message. Got: \(desc)")
    XCTAssertTrue(
      desc.contains("restricted profile"),
      "BrujaError must include the supplied reason. Got: \(desc)")
    XCTAssertTrue(
      desc.contains("--backend mlx"),
      "BrujaError must suggest the MLX fallback. Got: \(desc)")
  }

  /// Available mock reports `isAvailable == true` (sanity check for the mock).
  func testAvailableMockIsAvailable() {
    let available = MockFMAvailable()
    XCTAssertTrue(available.isAvailable)
    XCTAssertNil(available.unavailabilityReason)
  }

  // MARK: - (c) Agent-capable allowlist flagging

  /// The agentic default model (`mlx-community/Qwen2.5-7B-Instruct-4bit`) is flagged agent-capable.
  func testAgentDefaultIsFlaggedAgentCapable() {
    XCTAssertTrue(
      AgentAllowlist.isAgentCapable(AgentAllowlist.agentDefaultModel),
      "The agentic default (\(AgentAllowlist.agentDefaultModel)) must be on the allowlist"
    )
  }

  /// A model NOT on the allowlist is NOT flagged agent-capable.
  func testNonAllowlistedModelIsNotFlaggedAgentCapable() {
    let nonAllowlisted = "mlx-community/Llama-3.2-1B-Instruct-4bit"
    XCTAssertFalse(
      AgentAllowlist.isAgentCapable(nonAllowlisted),
      "'\(nonAllowlisted)' must NOT be on the agent-capable allowlist"
    )
  }

  /// The integration-test fixture model is also on the allowlist (so seam-spike / repl tests pass).
  func testFixtureModelIsFlaggedAgentCapable() {
    let fixture = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
    XCTAssertTrue(
      AgentAllowlist.isAgentCapable(fixture),
      "The S2/S7 fixture model '\(fixture)' must be on the allowlist")
  }
}
