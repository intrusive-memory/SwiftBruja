import Foundation
import FoundationModels

// MARK: - Foundation Models Backend (S9)

/// The Foundation Models backend that drives `SystemLanguageModel.default` through the SAME
/// `LanguageModelSession(model:tools:instructions:)` seam as the MLX path.
///
/// **THE PROOF of the architecture**: this is the second conformer. It consumes the SAME
/// `[any Tool]` array from `ToolRegistry.defaultTools()` with NO second tool adapter. The only
/// difference from the MLX path is the `model:` argument — `SystemLanguageModel.default` instead
/// of `MLXLanguageModel(...)`. The framework handles tool dispatch identically for both.
///
/// Responsibility split:
/// - This type (in `SwiftBruja`) builds the session and maps FM-specific errors — it is
///   testable from `SwiftBrujaTests` with any `[any Tool]` array.
/// - `AgentCommand` (in the `bruja` CLI target) wraps `ToolRegistry.defaultTools()` with
///   `ConsentToolObserver`s (path-escape consent + IO surfacing) before handing the array
///   here — the SAME wrappers the MLX path uses (R2.2, R4).
@available(macOS 26.0, *)
public enum FoundationModelBackend {

  // MARK: - Session factory

  /// Build a `LanguageModelSession` backed by `SystemLanguageModel.default` consuming the
  /// supplied `[any Tool]` array.
  ///
  /// This is the SAME call-site as the MLX path — only the `model:` argument differs:
  /// ```
  /// // MLX path (AgentLoop.init):
  /// LanguageModelSession(model: MLXLanguageModel(...), tools: tools, instructions: instructions)
  /// // FM path (this method):
  /// LanguageModelSession(model: SystemLanguageModel.default, tools: tools, instructions: instructions)
  /// ```
  /// There is no per-backend tool adapter; `tools` is the SAME array both backends receive
  /// (R4 — tools defined once, consumed by both backends identically).
  ///
  /// - Parameters:
  ///   - tools: The `[any Tool]` array from `ToolRegistry.defaultTools()` (optionally wrapped
  ///     by `ConsentToolObserver` in the CLI layer).
  ///   - instructions: The system-prompt instructions string (same text used for the MLX path).
  /// - Returns: A ready-to-use `LanguageModelSession`.
  public static func makeSession(
    tools: [any Tool],
    instructions: String
  ) -> LanguageModelSession {
    LanguageModelSession(
      model: SystemLanguageModel.default,
      tools: tools,
      instructions: instructions
    )
  }

  // MARK: - Error mapping (R2.4)

  /// Map a Foundation Models error into a typed ``BrujaError``.
  ///
  /// FM errors come as `LanguageModelError` (the current non-deprecated enum) or as the older
  /// `LanguageModelSession.GenerationError`. Both are mapped to the closest `BrujaError` case:
  ///
  /// | FM Error | BrujaError |
  /// |---|---|
  /// | `.contextSizeExceeded` | `.contextWindowExceeded(tokenCount:limit:)` |
  /// | `.rateLimited` | `.queryFailed("rate limited …")` |
  /// | `.guardrailViolation` | `.queryFailed("content guardrail triggered …")` |
  /// | `.refusal` | `.queryFailed("model refused request …")` |
  /// | `.timeout` | `.queryFailed("request timed out …")` |
  /// | `.unsupportedCapability` | `.queryFailed("unsupported capability …")` |
  /// | anything else | `.queryFailed(localizedDescription)` |
  ///
  /// Already-typed `BrujaError`s pass through unchanged (idempotent).
  public static func mapFMError(_ error: any Error) -> BrujaError {
    if let bruja = error as? BrujaError { return bruja }

    if let lmError = error as? LanguageModelError {
      return mapLanguageModelError(lmError)
    }

    // Fall back to the string-based heuristic (mirrors MLXLanguageModelExecutor.mapGenerationError).
    let text = String(describing: error).lowercased()
    if text.contains("context") || text.contains("overflow") || text.contains("too long")
      || text.contains("exceed") || text.contains("window") || text.contains("max position")
      || text.contains("sequence length")
    {
      return .contextWindowExceeded(tokenCount: 0, limit: 0)
    }
    return .queryFailed(error.localizedDescription)
  }

  // MARK: - Private helpers

  private static func mapLanguageModelError(_ error: LanguageModelError) -> BrujaError {
    switch error {
    case .contextSizeExceeded(let info):
      return .contextWindowExceeded(tokenCount: info.tokenCount, limit: info.contextSize)

    case .rateLimited(let info):
      return .queryFailed("Foundation Models rate-limited this request: \(info.debugDescription)")

    case .guardrailViolation(let info):
      return .queryFailed(
        "Foundation Models content guardrail triggered: \(info.debugDescription)")

    case .refusal(let info):
      return .queryFailed("Foundation Models refused the request: \(info.debugDescription)")

    case .timeout(let info):
      return .queryFailed("Foundation Models request timed out: \(info.debugDescription)")

    case .unsupportedCapability(let info):
      return .queryFailed(
        "Foundation Models does not support this capability on this device: \(info.debugDescription)"
      )

    case .unsupportedTranscriptContent(let info):
      return .queryFailed(
        "Foundation Models does not support this transcript content: \(info.debugDescription)")

    case .unsupportedGenerationGuide(let info):
      return .queryFailed(
        "Foundation Models does not support the requested generation guide: \(info.debugDescription)"
      )

    case .unsupportedLanguageOrLocale(let info):
      return .queryFailed(
        "Foundation Models does not support the requested language or locale: \(info.debugDescription)"
      )

    @unknown default:
      return .queryFailed(error.localizedDescription)
    }
  }
}
