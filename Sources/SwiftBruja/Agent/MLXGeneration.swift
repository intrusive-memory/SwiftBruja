import Foundation
import MLX
import MLXLMCommon

// MARK: - Generation seam
//
// The MLX generation core for the agent loop. This is entirely macOS-26-capable: it is built on
// `MLXLMCommon` (`Chat.Message`, `ToolSpec`, `GenerateParameters`, `KVCache`, `Generation`,
// `ToolCall`), which parses tool calls out of the model's output natively — no FoundationModels
// custom-provider seam (the removed macOS-27-only `LanguageModel`/`LanguageModelExecutor`) is
// involved. ``MLXAgentLoop`` drives this seam directly.

/// A backend-neutral generation event. This is the seam between the agent loop's event handling and
/// the actual token producer. Mirroring MLX's `Generation` into a small MLX-free enum lets unit
/// tests script generation without a model, network, or any MLX types.
public enum BrujaGenerationEvent: Sendable {
  /// A decoded text chunk.
  case text(String)
  /// A parsed tool call (id + name + already-serialized JSON arguments).
  case toolCall(id: String, name: String, argumentsJSON: String)
  /// Completion / token-rate metadata; not surfaced as a loop event.
  case info
}

/// The injectable token producer behind ``MLXAgentLoop``. The production implementation drives an
/// MLX `ModelContainer`; tests provide a scripted mock.
public protocol GenerationSource: Sendable {
  /// Best-effort warm-up. No-op for mocks.
  func prewarm()

  /// Produce a stream of generation events for the given chat. The full transcript is supplied on
  /// every call (``MLXAgentLoop`` replays it each pass), so implementations prefill from scratch;
  /// `turnState` is consulted only for the step cap.
  func generate(
    messages: [Chat.Message],
    toolSpecs: [ToolSpec],
    parameters: GenerateParameters,
    turnState: TurnState
  ) async throws -> AsyncThrowingStream<BrujaGenerationEvent, any Error>
}

extension GenerationSource {
  public func prewarm() {}
}

// MARK: - Per-conversation state

/// Per-conversation mutable state shared across generation turns: the step counter that enforces the
/// configured cap (R5.3). An actor because the loop may re-enter generation across tool round-trips.
///
/// Note: this deliberately does NOT carry a reused KV cache. ``MLXAgentLoop`` replays the full
/// transcript on every generation pass, so each pass prefills from scratch against a fresh cache
/// (see ``ContainerGenerationSource``). Reusing a cache across passes while *also* replaying the full
/// prompt would double-encode the context. Cross-pass prefix reuse would require sending only the
/// per-turn delta and is left as a future optimization.
public actor TurnState {
  /// Number of steps (model turns) taken so far in this conversation.
  private(set) var stepCount: Int = 0

  /// The configured maximum number of steps before ``BrujaError/agentStepLimitExceeded(limit:)``.
  public let maxSteps: Int

  public init(maxSteps: Int) {
    self.maxSteps = maxSteps
  }

  /// Record the start of a step, throwing once the configured cap is exceeded.
  public func beginStep() throws {
    guard stepCount < maxSteps else {
      throw BrujaError.agentStepLimitExceeded(limit: maxSteps)
    }
    stepCount += 1
  }

  /// Reset the conversation state (step counter) — e.g. on `/clear` / new session.
  public func reset() {
    stepCount = 0
  }
}

// MARK: - Generation error mapping (R2.4)

/// Map a generation/context failure into a typed ``BrujaError``. Already-typed `BrujaError`s pass
/// through unchanged; everything else is heuristically classified as context-window overflow vs. a
/// generic query failure so callers never see a raw crash.
func mapMLXGenerationError(_ error: any Error) -> BrujaError {
  if let bruja = error as? BrujaError {
    return bruja
  }
  let text = String(describing: error).lowercased()
  if text.contains("context")
    || text.contains("overflow")
    || text.contains("too long")
    || text.contains("exceed")
    || text.contains("window")
    || text.contains("max position")
    || text.contains("sequence length")
  {
    return .contextWindowExceeded(tokenCount: 0, limit: 0)
  }
  return .queryFailed(error.localizedDescription)
}

// MARK: - Container-backed generation source (production)

/// An `@unchecked Sendable` wrapper for a turn's non-`Sendable` chat input (`[Chat.Message]` can
/// carry MLXArray-backed media). The messages are only read inside the model container's serialized
/// `perform` closure (single-threaded model access), so transferring the reference across the
/// producer-task boundary is sound even though the type is not nominally `Sendable`.
final class ChatInputBox: @unchecked Sendable {
  let messages: [Chat.Message]
  let toolSpecs: [ToolSpec]?
  init(messages: [Chat.Message], toolSpecs: [ToolSpec]?) {
    self.messages = messages
    self.toolSpecs = toolSpecs
  }
}

/// Production ``GenerationSource`` that drives the resolved MLX `ModelContainer`.
///
/// Correctness note: the entire generation — prompt prep, the `TokenIterator`, consuming the
/// `Generation` stream, and `await`-ing the generation task to settle — runs inside a single
/// `container.perform` closure, so the model, its weights, and the KV cache are only ever touched
/// under the container's serialized isolation. This mirrors `MLXLMCommon.ChatSession.streamMap`. The
/// earlier version consumed the stream OUTSIDE the lock and never awaited the generation task, which
/// produced empty output. A fresh KV cache is allocated per pass (the loop replays the full
/// transcript each time — see ``TurnState``); chunks are bridged out through an `AsyncThrowingStream`
/// so the loop still observes true streaming while the lock is held for the single pass.
struct ContainerGenerationSource: GenerationSource {
  let modelId: String

  func prewarm() {
    let id = modelId
    Task { _ = try? await BrujaQuery.resolveModel(id) }
  }

  func generate(
    messages: [Chat.Message],
    toolSpecs: [ToolSpec],
    parameters: GenerateParameters,
    turnState: TurnState
  ) async throws -> AsyncThrowingStream<BrujaGenerationEvent, any Error> {
    // Resolve the MLX container (loads + caches via SwiftAcervo's local model dir, offline).
    let (container, _, _) = try await BrujaQuery.resolveModel(modelId)

    // `[Chat.Message]` / `UserInput` are non-`Sendable` (they can carry MLXArray-backed media), so
    // box the turn's chat to cross into the producer task; `UserInput` is built inside the model
    // closure where it is consumed.
    let inputBox = ChatInputBox(messages: messages, toolSpecs: toolSpecs.isEmpty ? nil : toolSpecs)

    let (bridged, continuation) = AsyncThrowingStream<BrujaGenerationEvent, any Error>.makeStream()

    let work = Task {
      do {
        try await container.perform { (context: ModelContext) in
          let userInput = UserInput(chat: inputBox.messages, tools: inputBox.toolSpecs)
          let input = try await context.processor.prepare(input: userInput)

          // Fresh cache per pass: the loop replays the full transcript, so prefilling against a
          // reused cache would double-encode the context. `cache: nil` lets the iterator allocate.
          let iterator = try TokenIterator(
            input: input,
            model: context.model,
            cache: nil,
            parameters: parameters
          )

          let (stream, genTask) = MLXLMCommon.generateTask(
            promptTokenCount: input.text.tokens.size,
            modelConfiguration: context.configuration,
            tokenizer: context.tokenizer,
            iterator: iterator
          )

          for await item in stream {
            switch item {
            case .chunk(let text):
              continuation.yield(.text(text))
            case .toolCall(let call):
              continuation.yield(
                .toolCall(
                  id: UUID().uuidString,
                  name: call.function.name,
                  argumentsJSON: MLXToolEncoding.argumentsJSON(for: call)
                )
              )
            case .info:
              continuation.yield(.info)
            }
          }

          // The generation task can briefly outlive the stream (still using the model/cache); wait
          // for it to settle before releasing the lock so the pass is fully evaluated and complete.
          await genTask.value
        }
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
    continuation.onTermination = { _ in work.cancel() }
    return bridged
  }
}
