import Foundation
import MLXLMCommon

@testable import SwiftBruja

/// Reusable scripted ``GenerationSource`` for unit tests.
///
/// Replays a fixed sequence of ``BrujaGenerationEvent`` arrays — one array per `generate` call —
/// without touching any MLX model, model container, or network. Each call pops the front of
/// `scripts`; a `nil` entry throws `errorToThrow` (or a generic failure if none is set).
///
/// This is a promoted, shareable version of the inline mock originally defined inside
/// ``ExecutorTranscriptTests`` (S5). Both S5 tests and S11 dispatch tests can use this type;
/// the S5 file retains its own nested copy for backward-compatibility so no churn is needed
/// there. New tests should import via this file.
///
/// `@unchecked Sendable`: `generate` is invoked strictly sequentially by the tests (each turn is
/// awaited before the next), so unsynchronised mutable state is accessed single-threaded in practice.
@available(macOS 27.0, *)
public final class SharedMockGenerationSource: GenerationSource, @unchecked Sendable {

  /// The messages captured from each `generate` call, one entry per turn, in call order.
  public private(set) var receivedTurns: [[Chat.Message]] = []

  /// Scripted events to replay each turn. A `nil` entry means "throw `errorToThrow`".
  private var scripts: [[BrujaGenerationEvent]?]
  private let errorToThrow: (any Error)?

  public init(scripts: [[BrujaGenerationEvent]?], errorToThrow: (any Error)? = nil) {
    self.scripts = scripts
    self.errorToThrow = errorToThrow
  }

  public func generate(
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
