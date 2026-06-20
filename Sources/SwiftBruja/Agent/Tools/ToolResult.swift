import Foundation

/// The tool-result contract shared by every `FoundationModels.Tool` in the agent.
///
/// Tools return a **compact result string** for the model to reason about. We keep
/// the convention deliberately string-shaped (rather than a rich typed payload):
/// `Tool.Output` is constrained to `PromptRepresentable`, and a plain `String` is the
/// simplest output that round-trips cleanly back into the model's transcript for both
/// the MLX and Foundation Models backends.
///
/// This type centralizes two concerns so every tool behaves identically:
/// 1. A uniform way to render an **ok** result and a **typed error** result, so a failing
///    tool returns a descriptive string instead of throwing an uncaught error or crashing.
/// 2. The **large-output truncation policy** seam (R4.5). Sortie 1 establishes the threshold
///    constant + a truncation helper; the full policy (per-tool tuning, head/tail windows,
///    byte vs. character accounting) is exercised in Sortie 3.
public enum ToolResult {

  // MARK: - Truncation policy (R4.5 seam — full policy lands in S3)

  /// Maximum number of characters a tool result may contain before truncation.
  ///
  /// This is a single shared seam so every tool truncates consistently. The value is
  /// intentionally conservative for S1; S3 may tune it per-tool. Large model-facing
  /// outputs waste context-window budget and degrade tool-calling reliability, so we
  /// cap them and tell the model the output was truncated.
  public static let maxResultCharacters = 8_000

  /// Marker appended to a truncated result so the model knows content was elided.
  public static let truncationMarker = "\n…[truncated]"

  /// Truncate `text` to the shared policy threshold, appending ``truncationMarker``
  /// when content is elided.
  ///
  /// S1 implements the simple head-window form. S3 may extend this to a head/tail
  /// window or byte-accurate accounting; callers should not assume a particular shape
  /// beyond "returns a string no longer than the policy allows, plus the marker."
  ///
  /// - Parameters:
  ///   - text: The raw tool output.
  ///   - limit: Override for the character limit (defaults to ``maxResultCharacters``).
  /// - Returns: `text` unchanged if within the limit, otherwise a truncated prefix
  ///   followed by ``truncationMarker``.
  public static func truncated(
    _ text: String,
    limit: Int = ToolResult.maxResultCharacters
  ) -> String {
    guard text.count > limit else { return text }
    let head = String(text.prefix(limit))
    return head + truncationMarker
  }

  // MARK: - Result rendering

  /// Render a successful tool result, applying the truncation policy.
  ///
  /// - Parameter text: The successful output to return to the model.
  /// - Returns: A compact, possibly-truncated result string.
  public static func ok(_ text: String) -> String {
    truncated(text)
  }

  /// Render a typed error as a compact result **string** (never thrown to the model).
  ///
  /// Tools surface failures to the model as descriptive strings rather than throwing,
  /// so the model can recover (e.g. retry with a corrected path) instead of the agent
  /// loop aborting. The string is prefixed with ``errorPrefix`` so the model — and our
  /// own tests — can distinguish an error from a normal result.
  ///
  /// - Parameter message: A human/model-readable description of what went wrong.
  /// - Returns: A truncated error string prefixed with ``errorPrefix``.
  public static func error(_ message: String) -> String {
    truncated(errorPrefix + message)
  }

  /// Prefix marking a tool result as a typed error (see ``error(_:)``).
  public static let errorPrefix = "ERROR: "

  // MARK: - Path-escape consent outcome (R6.2)

  /// Render the "escape requested" outcome for a path that resolved **outside** the cwd
  /// subtree. The consent UI itself lands in Sortie 6/7; until then a tool surfaces this as a
  /// typed error string so the agent loop does not silently touch an out-of-tree path.
  ///
  /// The string carries ``escapeMarker`` (after ``errorPrefix``) so the future consent flow —
  /// and our tests — can distinguish a consent-required escape from an ordinary error.
  ///
  /// - Parameters:
  ///   - operation: A short label for the attempted operation (e.g. `write_file`).
  ///   - resolvedPath: The fully canonicalized path that escaped the cwd subtree.
  public static func escapeRequested(operation: String, resolvedPath: String) -> String {
    error(
      escapeMarker
        + "\(operation) target resolves outside the working directory; "
        + "explicit user consent is required (path: \(resolvedPath))")
  }

  /// Marker (after ``errorPrefix``) identifying a consent-required path escape.
  public static let escapeMarker = "CONSENT_REQUIRED: "

  // MARK: - Auditable echo (R6.3)

  /// Emit an auditable echo of an operation the agent performed, even when not prompting (R6.3),
  /// so the transcript shows exactly what the agent did.
  ///
  /// Written to standard error so it never contaminates a tool's model-facing result string.
  ///
  /// - Parameters:
  ///   - operation: The tool/operation name (e.g. `edit_file`, `run_shell`).
  ///   - detail: A compact description of the target (path, command, etc.).
  public static func audit(operation: String, detail: String) {
    FileHandle.standardError.write(Data("[bruja audit] \(operation): \(detail)\n".utf8))
  }
}
