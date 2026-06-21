import Foundation
import MLXLMCommon

// MARK: - MLX Agent Loop

/// The macOS-26 hand-rolled agentic loop for the MLX backend.
///
/// This replaces the removed macOS-27 custom-provider seam (`MLXLanguageModel` /
/// `MLXLanguageModelExecutor` riding inside `LanguageModelSession`). Instead of handing MLX to the
/// FoundationModels framework and letting it own the tool round-trip, we own the round-trip here:
///
/// 1. Append the user turn to an in-memory `[Chat.Message]` transcript.
/// 2. Generate against the resolved MLX model via a ``GenerationSource``. `MLXLMCommon` parses tool
///    calls out of the model's output natively (`Generation.toolCall`).
/// 3. If the model produced tool calls, dispatch each through the injected ``AgentToolHandling``,
///    append the results as `.tool` messages, and generate again (the round-trip).
/// 4. When a generation produces no tool calls, the turn is complete.
///
/// The KV cache is reused across generations via ``TurnState`` (prompt-prefix reuse), and the step
/// counter bounds runaway tool loops (R5.3). The transcript persists across `runTurn` calls so the
/// REPL keeps conversation context (R5.4).
@available(macOS 26.0, *)
public final class MLXAgentLoop {

  /// Loop configuration.
  public struct Configuration: Sendable {
    /// SwiftAcervo / mlx-community model identifier.
    public var modelId: String
    /// Generation temperature.
    public var temperature: Float
    /// Maximum tokens to generate per model turn.
    public var maxTokens: Int
    /// Maximum number of model turns (including tool round-trips) per conversation before
    /// ``BrujaError/agentStepLimitExceeded(limit:)``.
    public var maxSteps: Int
    /// System instructions injected as the first transcript message.
    public var instructions: String

    public init(
      modelId: String,
      temperature: Float = 0.0,
      maxTokens: Int = 1024,
      maxSteps: Int = 32,
      instructions: String
    ) {
      self.modelId = modelId
      self.temperature = temperature
      self.maxTokens = maxTokens
      self.maxSteps = maxSteps
      self.instructions = instructions
    }
  }

  private let configuration: Configuration
  private let source: any GenerationSource
  private let tools: any AgentToolHandling
  private let turnState: TurnState

  /// The in-memory chat transcript. Seeded with the system instructions; grows across turns.
  private var messages: [Chat.Message]

  /// Production initializer: drive the resolved MLX container.
  public convenience init(configuration: Configuration, tools: any AgentToolHandling) {
    self.init(
      configuration: configuration,
      tools: tools,
      source: ContainerGenerationSource(modelId: configuration.modelId)
    )
  }

  /// Designated initializer; inject a scripted ``GenerationSource`` for tests.
  public init(
    configuration: Configuration,
    tools: any AgentToolHandling,
    source: any GenerationSource
  ) {
    self.configuration = configuration
    self.tools = tools
    self.source = source
    self.turnState = TurnState(maxSteps: configuration.maxSteps)
    self.messages = [.system(configuration.instructions)]
  }

  /// Human-readable model label for the REPL banner.
  public var modelLabel: String { configuration.modelId }

  /// Best-effort model warm-up.
  public func prewarm() { source.prewarm() }

  /// Reset the conversation: clear the transcript (keeping instructions) and the KV cache + step
  /// counter. The model stays resolvable.
  public func reset() async {
    messages = [.system(configuration.instructions)]
    await turnState.reset()
  }

  /// Run exactly one agent turn for `userInput`.
  ///
  /// Streams assistant text and tool activity through `onEvent`. Tool dispatch (and any consent
  /// flow) is owned by the injected ``AgentToolHandling``. Returns when the model produces a turn
  /// with no tool calls; throws a typed ``BrujaError`` on generation failure or step-cap overflow.
  public func runTurn(
    _ userInput: String,
    onEvent: @Sendable (AgentTurnEvent) async -> Void
  ) async throws {
    messages.append(.user(userInput))

    let toolSpecs = tools.toolSpecs()
    let parameters = GenerateParameters(
      maxTokens: configuration.maxTokens,
      temperature: configuration.temperature
    )

    // Tool round-trip loop: each pass is one model turn. A turn that emits tool calls dispatches
    // them, appends the results, and re-enters; a turn with no tool calls completes the agent turn.
    while true {
      try await turnState.beginStep()

      let stream: AsyncThrowingStream<BrujaGenerationEvent, any Error>
      do {
        stream = try await source.generate(
          messages: messages,
          toolSpecs: toolSpecs,
          parameters: parameters,
          turnState: turnState
        )
      } catch {
        throw mapMLXGenerationError(error)
      }

      var assistantText = ""
      var pendingToolCalls: [(id: String, name: String, argumentsJSON: String)] = []

      do {
        for try await event in stream {
          switch event {
          case .text(let text):
            guard !text.isEmpty else { continue }
            assistantText += text
            await onEvent(.assistantText(text))
          case .toolCall(let id, let name, let argumentsJSON):
            pendingToolCalls.append((id: id, name: name, argumentsJSON: argumentsJSON))
          case .info:
            continue
          }
        }
      } catch {
        throw mapMLXGenerationError(error)
      }

      if !assistantText.isEmpty {
        messages.append(.assistant(assistantText))
      }

      // No tool calls → the model answered; the turn is complete.
      if pendingToolCalls.isEmpty {
        return
      }

      // Record the assistant's requested tool calls as text so the model has context for the tool
      // outputs that follow, then dispatch each and append its result as a `.tool` message.
      let rendered = pendingToolCalls.map { "\($0.name)(\($0.argumentsJSON))" }
        .joined(separator: ", ")
      messages.append(.assistant("[called tools: \(rendered)]"))

      for call in pendingToolCalls {
        await onEvent(.toolCallStarted(name: call.name, argumentsJSON: call.argumentsJSON))
        let result = try await tools.dispatch(name: call.name, argumentsJSON: call.argumentsJSON)
        await onEvent(.toolFinished(name: call.name, result: result))
        messages.append(.tool(result))
      }
      // Loop: generate again with the tool outputs now in context.
    }
  }
}
