import BrujaHelpers
import XCTest

/// Covers `ReasoningTrace`, which strips `<think>…</think>` chain-of-thought traces from thinking
/// models (Qwen3.5) so the user sees only the answer unless `--verbose`.
final class ReasoningTraceTests: XCTestCase {

  /// Explicit block: both tags present. Only the post-`</think>` answer survives.
  func testStripsExplicitThinkBlock() {
    let input = "<think>\nlet me reason about this\n</think>\n\n42"
    XCTAssertEqual(ReasoningTrace.stripped(input), "42")
  }

  /// Primed block: the chat template opened `<think>` in the prompt, so the model emits only the
  /// closing tag. This is the Qwen3.5-through-`applyChatTemplate` shape.
  func testStripsPrimedThinkBlockWithNoOpeningTag() {
    let input = "reasoning the model drafted here\n</think>\n\nThe answer is alpha and beta."
    XCTAssertEqual(ReasoningTrace.stripped(input), "The answer is alpha and beta.")
  }

  /// No reasoning markers → text is returned unchanged.
  func testPassthroughWhenNoThinkMarkers() {
    let input = "Just a plain answer with no reasoning."
    XCTAssertEqual(ReasoningTrace.stripped(input), input)
  }

  /// Several chained think blocks → keep only what follows the LAST close.
  func testKeepsOnlyTextAfterFinalClose() {
    let input = "<think>a</think>interim<think>b</think>final answer"
    XCTAssertEqual(ReasoningTrace.stripped(input), "final answer")
  }

  /// Unclosed reasoning (truncated by the token cap): drop from the opening tag onward.
  func testUnclosedThinkIsDropped() {
    let input = "<think>reasoning that never finished because tokens ran out"
    XCTAssertEqual(ReasoningTrace.stripped(input), "")
  }

  /// A reasoning-only turn (no answer after the close) strips to empty — the caller surfaces the
  /// "no answer produced" path.
  func testReasoningOnlyStripsToEmpty() {
    let input = "<think>only thinking, no answer</think>   \n"
    XCTAssertEqual(ReasoningTrace.stripped(input), "")
  }

  /// `render(verbose: true)` is a passthrough — the trace is preserved.
  func testRenderVerbosePreservesTrace() {
    let input = "<think>reasoning</think>\n\nanswer"
    XCTAssertEqual(ReasoningTrace.render(input, verbose: true), input)
  }

  /// `render(verbose: false)` strips, matching `stripped(_:)`.
  func testRenderNonVerboseStrips() {
    let input = "<think>reasoning</think>\n\nanswer"
    XCTAssertEqual(ReasoningTrace.render(input, verbose: false), "answer")
  }
}
