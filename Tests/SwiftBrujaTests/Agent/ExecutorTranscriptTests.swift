import XCTest

import MLXLMCommon

@testable import SwiftBruja

/// Exit-criteria tests for the macOS-26 ``MLXAgentLoop`` (the hand-rolled replacement for the
/// removed macOS-27 `MLXLanguageModelExecutor` seam).
///
/// All tests run with a MOCK ``GenerationSource`` — no MLX model, no `ModelContainer`, no network —
/// so they execute under the standard `make test`:
///   (a) the running transcript is built into ordered MLX chat messages across two turns,
///   (b) the configured step cap throws ``BrujaError/agentStepLimitExceeded(limit:)`` at the limit,
///   (c) a simulated context overflow yields a typed ``BrujaError`` (no crash).
@available(macOS 26.0, *)
final class MLXAgentLoopTranscriptTests: XCTestCase {

  private static let instructions = "You are a helpful assistant."

  private func makeLoop(
    source: any GenerationSource,
    maxSteps: Int = 8
  ) -> MLXAgentLoop {
    MLXAgentLoop(
      configuration: MLXAgentLoop.Configuration(
        modelId: "mock/test-model",
        maxSteps: maxSteps,
        instructions: Self.instructions
      ),
      tools: RegistryToolHandler(tools: []),
      source: source
    )
  }

  // MARK: - (a) Two-turn transcript ordering

  func testTranscriptMappingOrderedAcrossTwoTurns() async throws {
    let mock = SharedMockGenerationSource(
      scripts: [
        [.text("Hi there!")],
        [.text("Two plus two is four.")],
      ]
    )
    let loop = makeLoop(source: mock)

    try await loop.runTurn("Hello") { _ in }
    try await loop.runTurn("What is two plus two?") { _ in }

    let turns = mock.receivedTurns
    XCTAssertEqual(turns.count, 2, "the loop should call the source once per turn")

    // Turn 1 mapping: [system, user].
    let t1 = turns[0]
    XCTAssertEqual(t1.map(\.role), [.system, .user])
    XCTAssertEqual(t1.map(\.content), [Self.instructions, "Hello"])

    // Turn 2 mapping must preserve full conversation order:
    // [system, user("Hello"), assistant("Hi there!"), user("What is two plus two?")].
    let t2 = turns[1]
    XCTAssertEqual(t2.map(\.role), [.system, .user, .assistant, .user])
    XCTAssertEqual(
      t2.map(\.content),
      [
        Self.instructions,
        "Hello",
        "Hi there!",
        "What is two plus two?",
      ]
    )
  }

  // MARK: - (b) Step cap

  func testStepCapThrowsAgentStepLimitExceeded() async throws {
    let limit = 3
    let mock = SharedMockGenerationSource(
      scripts: Array(repeating: [.text("ok")], count: 10)
    )
    // One loop instance shares its TurnState across turns, so the step counter accumulates.
    let loop = makeLoop(source: mock, maxSteps: limit)

    // The first `limit` turns (one model step each) must succeed.
    for i in 0..<limit {
      try await loop.runTurn("turn \(i)") { _ in }
    }

    // The next turn must throw the typed step-limit error.
    do {
      try await loop.runTurn("one too many") { _ in }
      XCTFail("expected agentStepLimitExceeded once the step cap is reached")
    } catch let error as BrujaError {
      guard case .agentStepLimitExceeded(let reported) = error else {
        return XCTFail("expected .agentStepLimitExceeded, got \(error)")
      }
      XCTAssertEqual(reported, limit)
    }
  }

  // MARK: - (c) Simulated context overflow → typed error

  func testSimulatedContextOverflowYieldsTypedError() async throws {
    struct OverflowError: Error { let message = "model context window overflow: sequence too long" }

    let mock = SharedMockGenerationSource(scripts: [nil], errorToThrow: OverflowError())
    let loop = makeLoop(source: mock)

    do {
      try await loop.runTurn("a very long prompt that overflows the window") { _ in }
      XCTFail("expected a typed BrujaError on simulated context overflow")
    } catch let error as BrujaError {
      // The "context"/"overflow" keywords route to contextWindowExceeded; either way it must be a
      // typed BrujaError and never a crash.
      guard case .contextWindowExceeded = error else {
        return XCTFail("expected .contextWindowExceeded, got \(error)")
      }
    }
  }
}
