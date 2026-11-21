import XCTest

@testable import SwiftBruja

/// mlx-swift-lm 3.33 delivers a thinking model's reasoning apart from its answer
/// (`Generation.reasoning`). These check, with a mock source and no model, that Bruja still shows
/// it as `<think>…</think>` and keeps it out of the replayed transcript.
@available(macOS 26.0, *)
final class ReasoningEventTests: XCTestCase {

  private func makeLoop(source: any GenerationSource) -> MLXAgentLoop {
    MLXAgentLoop(
      configuration: MLXAgentLoop.Configuration(
        modelId: "mock/test-model", maxSteps: 8, instructions: "Be brief."),
      tools: RegistryToolHandler(tools: []),
      source: source)
  }

  func testReasoningIsShownInsideThinkTags() async throws {
    let mock = SharedMockGenerationSource(scripts: [
      [.reasoning("The user "), .reasoning("wants a number."), .text("Four.")]
    ])
    let collected = TextCollector()
    try await makeLoop(source: mock).runTurn("Two plus two?") { event in
      if case .assistantText(let text) = event { await collected.append(text) }
    }
    let shown = await collected.text
    XCTAssertEqual(shown, "<think>The user wants a number.</think>\n\nFour.")
    XCTAssertEqual(ReasoningTraceCheck.stripped(shown), "Four.")
  }

  func testReasoningIsNotReplayedInTheTranscript() async throws {
    let mock = SharedMockGenerationSource(scripts: [
      [.reasoning("Thinking."), .text("Hi.")],
      [.text("Bye.")],
    ])
    let loop = makeLoop(source: mock)
    try await loop.runTurn("Hello") { _ in }
    try await loop.runTurn("Goodbye") { _ in }
    XCTAssertEqual(mock.receivedTurns[1].map(\.content), ["Be brief.", "Hello", "Hi.", "Goodbye"])
  }

  func testAnswerWithoutReasoningIsUnchanged() async throws {
    let mock = SharedMockGenerationSource(scripts: [[.text("Plain answer.")]])
    let collected = TextCollector()
    try await makeLoop(source: mock).runTurn("Hi") { event in
      if case .assistantText(let text) = event { await collected.append(text) }
    }
    let shown = await collected.text
    XCTAssertEqual(shown, "Plain answer.")
  }

  func testQueryCombinesReasoningInFrontOfTheAnswer() {
    XCTAssertEqual(
      BrujaQuery.combine(reasoning: "  Let me count.\n", answer: "Four.\n"),
      "<think>\nLet me count.\n</think>\n\nFour.")
    XCTAssertEqual(BrujaQuery.combine(reasoning: "", answer: "Four."), "Four.")
    XCTAssertEqual(BrujaQuery.combine(reasoning: " \n", answer: "Four."), "Four.")
  }
}

/// Collects streamed text across the loop's async callbacks.
private actor TextCollector {
  private(set) var text = ""
  func append(_ piece: String) { text += piece }
}

/// `ReasoningTrace` lives in BrujaHelpers, which this test target doesn't link; this mirrors its
/// closing-tag rule for the check above.
private enum ReasoningTraceCheck {
  static func stripped(_ text: String) -> String {
    guard let close = text.range(of: "</think>", options: .backwards) else { return text }
    return String(text[close.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
