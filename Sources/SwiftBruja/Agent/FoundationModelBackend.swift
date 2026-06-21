import Foundation
import FoundationModels

// MARK: - Foundation Models Backend (S9)

/// The Foundation Models backend that drives `SystemLanguageModel.default` through
/// `LanguageModelSession(model:tools:instructions:)` (macOS 26). The framework owns the tool
/// round-trip for this backend.
///
/// It consumes the SAME `[any Tool]` array from `ToolRegistry.defaultTools()` as the MLX backend —
/// there is NO second tool adapter (R4). The MLX backend drives those same tools through its own
/// hand-rolled `MLXAgentLoop` instead of `LanguageModelSession`.
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
  /// The typed FM error enum (`LanguageModelError`) is macOS-27-only, and the older
  /// `LanguageModelSession.GenerationError` is deprecated as of macOS 27 — so to keep this one code
  /// path compiling cleanly against the macOS 26 SDK we classify by message text rather than by
  /// switching on a versioned enum. The heuristic routes context-window overflows to
  /// `.contextWindowExceeded` and everything else to `.queryFailed(localizedDescription)`.
  ///
  /// Already-typed `BrujaError`s pass through unchanged (idempotent).
  public static func mapFMError(_ error: any Error) -> BrujaError {
    if let bruja = error as? BrujaError { return bruja }

    // Classify on the structural description only. (Swift's default `localizedDescription` for a
    // plain `Error` embeds the literal string "unknown context", which would false-match "context".)
    let text = String(describing: error).lowercased()
    if text.contains("context") || text.contains("overflow") || text.contains("too long")
      || text.contains("exceed") || text.contains("window") || text.contains("max position")
      || text.contains("sequence length")
    {
      return .contextWindowExceeded(tokenCount: 0, limit: 0)
    }
    return .queryFailed(error.localizedDescription)
  }
}
