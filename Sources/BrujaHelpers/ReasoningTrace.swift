import Foundation

/// Strips chain-of-thought "reasoning" that thinking models (e.g. Qwen3.5) emit before their
/// answer, so the user sees only the final response unless they opt into `--verbose`.
///
/// Thinking models wrap their private reasoning in a `<think>…</think>` block that precedes the
/// user-facing answer. Two shapes occur in practice:
///
/// * **Explicit**: `<think>reasoning…</think>\n\nanswer` — both tags emitted by the model.
/// * **Primed**: `reasoning…</think>\n\nanswer` — the chat template opens `<think>` in the prompt,
///   so the model only emits the *closing* tag. (This is what Qwen3.5 does through
///   `#huggingFaceTokenizerLoader()`'s `applyChatTemplate`.)
///
/// Both shapes are handled by keying on the closing tag: the answer is whatever follows the final
/// `</think>`. Text with no reasoning markers is returned unchanged.
public enum ReasoningTrace {

  private static let closeTag = "</think>"
  private static let openTag = "<think>"

  /// Returns the user-facing answer with any leading reasoning block removed.
  ///
  /// - If a `</think>` is present, returns the text after the **last** one (trimmed) — this drops
  ///   both explicit and primed reasoning, and keeps only the final answer when several think
  ///   blocks are chained.
  /// - If only an *unclosed* `<think>` is present (reasoning truncated by the token cap), returns
  ///   whatever preceded it (trimmed) — usually empty, which the caller surfaces as "no answer".
  /// - Otherwise returns `text` unchanged.
  public static func stripped(_ text: String) -> String {
    if let close = text.range(of: closeTag, options: .backwards) {
      return String(text[close.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let open = text.range(of: openTag) {
      return String(text[..<open.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return text
  }

  /// Returns `text` unchanged when `verbose` is true, otherwise the reasoning-stripped answer.
  /// Convenience for the common `verbose ? raw : stripped` call site.
  public static func render(_ text: String, verbose: Bool) -> String {
    verbose ? text : stripped(text)
  }
}
