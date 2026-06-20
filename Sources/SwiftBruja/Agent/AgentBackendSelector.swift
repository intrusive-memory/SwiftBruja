import Foundation
import FoundationModels

// MARK: - Agent Backend

/// The backend that drives an `AgentLoop` generation turn.
///
/// S8 wires selection + the FM-unavailable error path.
/// S9 wires the actual FM session and streaming.
public enum AgentBackend: String, CaseIterable, Sendable {
  /// Any SwiftAcervo / mlx-community model id — routed through `MLXLanguageModelExecutor`.
  case mlx
  /// The on-device Foundation Models system model (`SystemLanguageModel`).
  case foundation
}

// MARK: - Agent Capability Allowlist

/// A curated allowlist of mlx-community model ids known to tool-call reliably.
///
/// Policy (R3.3 / R7.3): models in this list are flagged "agent-capable" in `bruja list`.
/// Models NOT on this list may still be used for agent tasks but emit a one-line degradation
/// warning. The list is intentionally small and manually curated; it is NOT an exhaustive
/// catalogue of every tool-capable model.
public enum AgentAllowlist {
  /// The agentic default model id (Sortie 8, R7 / OQ-3).
  ///
  /// Deliberately distinct from `BrujaModelManager.defaultModel` ("mlx-community/Llama-3.2-1B-Instruct-4bit"),
  /// which is the lighter weight default for `query`/`chat` paths. The agent path requires a
  /// larger, tool-capable instruct model. The 0.5B fixture (`mlx-community/Qwen2.5-0.5B-Instruct-4bit`)
  /// was used during Sortie 7 development; this 7B model is the real agentic default (CDN-verified
  /// present, 4.3 GB, 10 files; OQ-3 resolved 2026-06-19).
  public static let agentDefaultModel = "mlx-community/Qwen2.5-7B-Instruct-4bit"

  /// Curated allowlist of model ids that are known to support reliable tool-calling.
  public static let agentCapableModels: Set<String> = [
    agentDefaultModel,
    "mlx-community/Qwen2.5-0.5B-Instruct-4bit",  // small fixture (integration-test use)
    "mlx-community/Qwen2.5-3B-Instruct-4bit",
    "mlx-community/Qwen2.5-14B-Instruct-4bit",
    "mlx-community/Qwen2.5-72B-Instruct-4bit",
  ]

  /// Returns `true` when `modelId` is on the curated agent-capable allowlist.
  public static func isAgentCapable(_ modelId: String) -> Bool {
    agentCapableModels.contains(modelId)
  }
}

// MARK: - Backend Selector

/// Resolves a user-supplied model/backend selector to a concrete `AgentBackend`.
///
/// Rules (R7.1):
/// * The literal string `"foundation"` → `.foundation` backend.
/// * Any other non-empty string (a SwiftAcervo / mlx-community model id) → `.mlx` backend.
/// * `nil` → default backend (`.mlx`) using `AgentAllowlist.agentDefaultModel`.
public struct AgentBackendSelector: Sendable {

  /// Resolve `selector` to a backend + effective model id.
  ///
  /// - Parameter selector: The raw `--backend`/`--model` value from the CLI, or `nil` for defaults.
  /// - Returns: A `(backend, modelId)` pair. `modelId` is `nil` for the `.foundation` backend
  ///   (it uses `SystemLanguageModel.default`, not a model-file identifier).
  public static func resolve(selector: String?) -> (backend: AgentBackend, modelId: String?) {
    switch selector {
    case "foundation":
      return (.foundation, nil)
    case let id? where !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
      return (.mlx, id)
    default:
      return (.mlx, AgentAllowlist.agentDefaultModel)
    }
  }
}

// MARK: - Foundation Models Availability (mockable)

/// Describes the availability of the on-device Foundation Models system model.
///
/// The real implementation delegates to `SystemLanguageModel.default.availability`. The protocol
/// exists so `BackendSelectionTests` can inject a deterministic mock without requiring the running
/// host to have FM available (or unavailable).
public protocol FoundationModelsAvailabilityProvider: Sendable {
  /// Returns `true` when Foundation Models is ready for inference on this host.
  var isAvailable: Bool { get }
  /// Human-readable unavailability reason, or `nil` when available.
  var unavailabilityReason: String? { get }
}

/// The live implementation backed by `SystemLanguageModel.default.availability`.
@available(macOS 26.0, *)
public struct LiveFoundationModelsAvailability: FoundationModelsAvailabilityProvider {
  public init() {}

  public var isAvailable: Bool {
    if case .available = SystemLanguageModel.default.availability { return true }
    return false
  }

  public var unavailabilityReason: String? {
    if case .unavailable(let reason) = SystemLanguageModel.default.availability {
      return Self.describeReason(reason)
    }
    return nil
  }

  /// Map a `SystemLanguageModel.Availability.UnavailableReason` to a human-readable string.
  ///
  /// `UnavailableReason` is an enum (not `LocalizedError`) so we switch on its cases.
  private static func describeReason(
    _ reason: SystemLanguageModel.Availability.UnavailableReason
  ) -> String {
    switch reason {
    case .deviceNotEligible:
      return "this device does not support Apple Intelligence"
    case .appleIntelligenceNotEnabled:
      return "Apple Intelligence is not enabled — enable it in System Settings › Apple Intelligence & Siri"
    case .modelNotReady:
      return "Foundation Models assets are not yet downloaded to this device"
    @unknown default:
      return "unknown reason (\(reason))"
    }
  }
}

// MARK: - Backend Validation

/// Error thrown when `--backend foundation` is selected but Foundation Models is unavailable.
public struct FoundationModelsUnavailableError: Error, CustomStringConvertible, Sendable {
  /// The reason returned by `SystemLanguageModel.default.availability`.
  public let reason: String

  public init(reason: String) {
    self.reason = reason
  }

  public var description: String {
    "Foundation Models is not available on this host: \(reason). "
      + "Use '--backend mlx' (or omit --backend) to run with an MLX model instead."
  }
}

extension BrujaError {
  /// Foundation Models is unavailable on this host.
  ///
  /// Thrown (S8) when the user selects `--backend foundation` but
  /// `SystemLanguageModel.default.availability` is `.unavailable`. S9 wires the actual FM session;
  /// S8 only wires this full-stop error path.
  public static func foundationModelsUnavailable(_ reason: String) -> BrujaError {
    .queryFailed(
      "Foundation Models is not available on this host: \(reason). "
        + "Use '--backend mlx' (or omit --backend) to run with an MLX model instead.")
  }
}
