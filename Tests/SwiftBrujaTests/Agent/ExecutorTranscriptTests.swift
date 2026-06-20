import XCTest

import MLXLMCommon
import FoundationModels

@testable import SwiftBruja

/// Sortie 5 exit-criteria tests for `MLXLanguageModelExecutor` hardening.
///
/// All three tests run with a MOCK ``GenerationSource`` — no MLX model, no `ModelContainer`, no
/// network — so they execute under the standard `make test`:
///   (a) the running transcript is mapped into ordered MLX chat messages across two turns,
///   (b) the configured step cap throws ``BrujaError/agentStepLimitExceeded(limit:)`` at the limit,
///   (c) a simulated context overflow yields a typed ``BrujaError`` (no crash).
@available(macOS 27.0, *)
final class ExecutorTranscriptTests: XCTestCase {

  // MARK: - Mock generation source

  /// Records the chat messages it was handed each turn, and replays scripted events. Optionally
  /// throws to simulate a generation/context failure.
  ///
  /// `@unchecked Sendable`: `generate` is invoked strictly sequentially by the tests (each turn is
  /// awaited before the next), and the concurrent channel-drain task touches only the channel, never
  /// this object — so the unsynchronized mutable state is accessed single-threaded in practice.
  final class MockGenerationSource: GenerationSource, @unchecked Sendable {
    /// The messages captured from each `generate` call, one entry per turn, in call order.
    private(set) var receivedTurns: [[Chat.Message]] = []

    /// Scripted events to replay each turn. A `nil` entry means "throw `errorToThrow`".
    private var scripts: [[BrujaGenerationEvent]?]
    private let errorToThrow: (any Error)?

    init(scripts: [[BrujaGenerationEvent]?], errorToThrow: (any Error)? = nil) {
      self.scripts = scripts
      self.errorToThrow = errorToThrow
    }

    func generate(
      messages: [Chat.Message],
      toolSpecs: [ToolSpec],
      parameters: GenerateParameters,
      turnState: TurnState
    ) async throws -> AsyncThrowingStream<BrujaGenerationEvent, any Error> {
      receivedTurns.append(messages)
      let script = scripts.isEmpty ? [] : scripts.removeFirst()

      guard let events = script else {
        throw errorToThrow ?? BrujaError.queryFailed("mock failure")
      }

      return AsyncThrowingStream { continuation in
        for event in events {
          continuation.yield(event)
        }
        continuation.finish()
      }
    }
  }

  // MARK: - Channel-event collection helper

  /// Drive `respond` to completion. A detached task drains the channel concurrently (so suspended
  /// `send`s make progress); once `respond` returns or throws, that drain task is cancelled. The
  /// channel never auto-`finish()`es — the framework, not the executor, owns its lifetime — so we
  /// must not block waiting for it to end. These tests assert on the mock's captured state and on
  /// thrown errors rather than on collected channel events, so the drained events are discarded.
  private func runRespond(
    executor: MLXLanguageModelExecutor,
    model: MLXLanguageModel,
    request: LanguageModelExecutorGenerationRequest
  ) async throws {
    let channel = LanguageModelExecutorGenerationChannel()

    let drain = Task {
      for try await _ in channel { /* discard; keeps the producer unblocked */ }
    }
    defer { drain.cancel() }

    try await executor.respond(to: request, model: model, streamingInto: channel)
  }

  // MARK: - Transcript construction helpers

  private func instructions(_ text: String) -> Transcript.Entry {
    .instructions(
      Transcript.Instructions(
        segments: [.text(Transcript.TextSegment(content: text))],
        toolDefinitions: []
      )
    )
  }

  private func prompt(_ text: String) -> Transcript.Entry {
    .prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: text))]))
  }

  private func response(_ text: String) -> Transcript.Entry {
    .response(Transcript.Response(segments: [.text(Transcript.TextSegment(content: text))]))
  }

  private func makeRequest(_ entries: [Transcript.Entry]) -> LanguageModelExecutorGenerationRequest {
    LanguageModelExecutorGenerationRequest(
      id: UUID(),
      transcript: Transcript(entries: entries),
      enabledTools: [],
      generationOptions: GenerationOptions(),
      contextOptions: ContextOptions(),
      metadata: [:]
    )
  }

  private func makeModel() -> MLXLanguageModel {
    MLXLanguageModel(modelId: "mock/test-model", maxSteps: 8)
  }

  // MARK: - (a) Two-turn transcript ordering

  func testTranscriptMappingOrderedAcrossTwoTurns() async throws {
    let mock = MockGenerationSource(
      scripts: [
        [.text("Hi there!")],
        [.text("Two plus two is four.")],
      ]
    )
    let config = MLXLanguageModel.Configuration(modelId: "mock/test-model", maxSteps: 8)
    let turnState = TurnState(maxSteps: 8)
    let executor = MLXLanguageModelExecutor(
      configuration: config, source: mock, turnState: turnState)
    let model = makeModel()

    // Turn 1: system + first user prompt.
    let turn1 = makeRequest([
      instructions("You are a helpful assistant."),
      prompt("Hello"),
    ])
    try await runRespond(executor: executor, model: model, request: turn1)

    // Turn 2: the running transcript now includes the assistant's first response and the new prompt.
    let turn2 = makeRequest([
      instructions("You are a helpful assistant."),
      prompt("Hello"),
      response("Hi there!"),
      prompt("What is two plus two?"),
    ])
    try await runRespond(executor: executor, model: model, request: turn2)

    let turns = mock.receivedTurns
    XCTAssertEqual(turns.count, 2, "executor should call the source once per turn")

    // Turn 1 mapping: [system, user].
    let t1 = turns[0]
    XCTAssertEqual(t1.map(\.role), [.system, .user])
    XCTAssertEqual(t1.map(\.content), ["You are a helpful assistant.", "Hello"])

    // Turn 2 mapping must preserve full conversation order:
    // [system, user("Hello"), assistant("Hi there!"), user("What is two plus two?")].
    let t2 = turns[1]
    XCTAssertEqual(t2.map(\.role), [.system, .user, .assistant, .user])
    XCTAssertEqual(
      t2.map(\.content),
      [
        "You are a helpful assistant.",
        "Hello",
        "Hi there!",
        "What is two plus two?",
      ]
    )
  }

  // MARK: - (b) Step cap

  func testStepCapThrowsAgentStepLimitExceeded() async throws {
    let limit = 3
    let mock = MockGenerationSource(
      scripts: Array(repeating: [.text("ok")], count: 10)
    )
    let config = MLXLanguageModel.Configuration(modelId: "mock/test-model", maxSteps: limit)
    // Share one TurnState across all turns so the step counter accumulates.
    let turnState = TurnState(maxSteps: limit)
    let executor = MLXLanguageModelExecutor(
      configuration: config, source: mock, turnState: turnState)
    let model = makeModel()

    // The first `limit` turns must succeed.
    for i in 0..<limit {
      let request = makeRequest([prompt("turn \(i)")])
      try await runRespond(executor: executor, model: model, request: request)
    }

    // The next turn must throw the typed step-limit error.
    do {
      let request = makeRequest([prompt("one too many")])
      try await runRespond(executor: executor, model: model, request: request)
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

    let mock = MockGenerationSource(scripts: [nil], errorToThrow: OverflowError())
    let config = MLXLanguageModel.Configuration(modelId: "mock/test-model", maxSteps: 8)
    let executor = MLXLanguageModelExecutor(
      configuration: config, source: mock, turnState: TurnState(maxSteps: 8))
    let model = makeModel()

    let request = makeRequest([prompt("a very long prompt that overflows the window")])

    do {
      try await runRespond(executor: executor, model: model, request: request)
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
