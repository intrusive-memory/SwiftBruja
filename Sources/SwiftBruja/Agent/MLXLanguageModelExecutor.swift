import Foundation

import FoundationModels
import MLX
import MLXLMCommon

// MARK: - MLXLanguageModel

/// A `FoundationModels.LanguageModel` whose generation is driven by an MLX model behind the
/// custom-provider executor seam.
///
/// This is the model you hand to a `LanguageModelSession(model:tools:instructions:)`. The
/// framework reads its ``executorConfiguration`` and builds an ``MLXLanguageModelExecutor`` from it
/// via `init(configuration:)`. **You never construct the executor yourself** — you pass this model.
///
/// macOS 27.0+: the `LanguageModel`/`LanguageModelExecutor` custom-provider seam is 27.0-only even
/// though the rest of FoundationModels (`Tool`, `LanguageModelSession`) is 26.0.
@available(macOS 27.0, *)
public struct MLXLanguageModel: FoundationModels.LanguageModel {

  public typealias Executor = MLXLanguageModelExecutor

  /// Configuration the framework uses to build the executor. Carries the resolved model id.
  public struct Configuration: Hashable, Sendable {
    /// SwiftAcervo / mlx-community model identifier, e.g. `mlx-community/Qwen2.5-0.5B-Instruct-4bit`.
    public var modelId: String

    /// Generation temperature.
    public var temperature: Float

    /// Maximum tokens to generate per turn.
    public var maxTokens: Int

    public init(modelId: String, temperature: Float = 0.7, maxTokens: Int = 1024) {
      self.modelId = modelId
      self.temperature = temperature
      self.maxTokens = maxTokens
    }
  }

  public let executorConfiguration: Configuration

  public init(_ configuration: Configuration) {
    self.executorConfiguration = configuration
  }

  /// Convenience initializer from a model id.
  public init(
    modelId: String,
    temperature: Float = 0.7,
    maxTokens: Int = 1024
  ) {
    self.init(Configuration(modelId: modelId, temperature: temperature, maxTokens: maxTokens))
  }

  /// MLX instruct models in the agentic allowlist support tool calling; advertise that so the
  /// session enables tool dispatch.
  public var capabilities: LanguageModelCapabilities {
    LanguageModelCapabilities(capabilities: [.toolCalling])
  }
}

// MARK: - MLXLanguageModelExecutor

/// The single MLX-backed `LanguageModelExecutor` (the locked architecture — see OQ-1).
///
/// `respond(to:model:streamingInto:)` is the one place we control (REQUIREMENTS §3a):
/// it maps the FoundationModels `Transcript` into an MLX chat, runs `mlx-swift-lm` generation
/// through the `ModelContainer` resolved by ``BrujaQuery/resolveModel(_:)`` (tokenizer via
/// `SwiftTransformersTokenizerLoader`), and translates MLX `Generation` events into channel
/// events:
/// * model text → `.response(action: .appendText(...))`
/// * a parsed MLX tool call → `.toolCalls(action: .toolCall(id:name:action: .appendArguments(json)))`
///
/// When a tool call is emitted, the framework dispatches the matching `FoundationModels.Tool`,
/// appends a `.toolOutput` to the transcript, and calls `respond` again — that is the round-trip.
@available(macOS 27.0, *)
public struct MLXLanguageModelExecutor: FoundationModels.LanguageModelExecutor {

  public typealias Model = MLXLanguageModel
  public typealias Configuration = MLXLanguageModel.Configuration

  private let configuration: Configuration

  public init(configuration: Configuration) throws {
    self.configuration = configuration
  }

  /// Optional: warm the model container so the first `respond` is faster. Best-effort.
  public func prewarm(model: MLXLanguageModel, transcript: Transcript) {
    let modelId = configuration.modelId
    Task {
      _ = try? await BrujaQuery.resolveModel(modelId)
    }
  }

  public nonisolated func respond(
    to request: LanguageModelExecutorGenerationRequest,
    model: MLXLanguageModel,
    streamingInto channel: LanguageModelExecutorGenerationChannel
  ) async throws {
    // 1. Resolve the MLX container (loads + caches via SwiftAcervo's local model dir, offline).
    let (container, _, _) = try await BrujaQuery.resolveModel(configuration.modelId)

    // 2. Map the FoundationModels transcript into an MLX chat.
    let messages = Self.chatMessages(from: request.transcript)

    // 3. Map the enabled FoundationModels tools into MLX tool specs so the chat template
    //    advertises them to the model.
    let toolSpecs = Self.toolSpecs(from: request.enabledToolDefinitions)

    // 4. Prepare input and run generation.
    let userInput = UserInput(
      chat: messages,
      tools: toolSpecs.isEmpty ? nil : toolSpecs
    )

    let parameters = GenerateParameters(
      maxTokens: configuration.maxTokens,
      temperature: configuration.temperature
    )

    let input = try await container.prepare(input: userInput)
    let stream = try await container.generate(input: input, parameters: parameters)

    // 5. Translate MLX generation events into channel events.
    var emittedToolCall = false
    var emittedText = false

    for await item in stream {
      switch item {
      case .chunk(let text):
        guard !text.isEmpty else { continue }
        emittedText = true
        await channel.send(
          .response(action: .appendText(text, tokenCount: 0))
        )

      case .toolCall(let call):
        emittedToolCall = true
        let argumentsJSON = Self.argumentsJSON(for: call)
        let id = UUID().uuidString
        await channel.send(
          .toolCalls(
            action: .toolCall(
              id: id,
              name: call.function.name,
              action: .appendArguments(argumentsJSON, tokenCount: 0)
            )
          )
        )

      case .info:
        // token-rate / completion metadata — not surfaced as a channel event in S2.
        continue
      }
    }

    // If the model produced neither text nor a tool call (e.g. an immediate stop), emit an empty
    // response so the framework sees a well-formed (if empty) turn rather than nothing.
    if !emittedToolCall && !emittedText {
      await channel.send(.response(action: .appendText("", tokenCount: 0)))
    }
  }

  // MARK: - Transcript → chat mapping

  /// Build an MLX `[Chat.Message]` from the FoundationModels transcript.
  ///
  /// Mapping:
  /// * `.instructions` → `.system`
  /// * `.prompt` → `.user`
  /// * `.response` → `.assistant`
  /// * `.toolCalls` → `.assistant` (a compact textual record of the requested call)
  /// * `.toolOutput` → `.tool` (the tool's result, which is what round-trips back into the model)
  static func chatMessages(from transcript: Transcript) -> [Chat.Message] {
    var messages: [Chat.Message] = []

    for entry in transcript {
      switch entry {
      case .instructions(let instructions):
        let text = plainText(from: instructions.segments)
        if !text.isEmpty { messages.append(.system(text)) }

      case .prompt(let prompt):
        let text = plainText(from: prompt.segments)
        if !text.isEmpty { messages.append(.user(text)) }

      case .response(let response):
        let text = plainText(from: response.segments)
        if !text.isEmpty { messages.append(.assistant(text)) }

      case .toolCalls(let calls):
        // Record the assistant's requested tool calls as text so the model has context for the
        // tool outputs that follow. (Most chat templates do not need the structured call here;
        // the tool *output* is the load-bearing part for the round-trip.)
        let rendered = calls.map { "\($0.toolName)(\($0.arguments.jsonString))" }
          .joined(separator: ", ")
        if !rendered.isEmpty {
          messages.append(.assistant("[called tools: \(rendered)]"))
        }

      case .toolOutput(let output):
        let text = plainText(from: output.segments)
        messages.append(.tool(text))

      case .reasoning:
        // reasoning traces are not replayed into the MLX prompt in S2.
        continue

      @unknown default:
        continue
      }
    }

    return messages
  }

  /// Extract plain text from a list of transcript segments.
  static func plainText(from segments: [Transcript.Segment]) -> String {
    var parts: [String] = []
    for segment in segments {
      switch segment {
      case .text(let textSegment):
        parts.append(textSegment.content)
      case .structure(let structured):
        parts.append(structured.content.jsonString)
      default:
        continue
      }
    }
    return parts.joined(separator: "\n")
  }

  // MARK: - Tool mapping

  /// Convert FoundationModels tool definitions into MLX `ToolSpec` dictionaries (OpenAI-style
  /// function schema) so the chat template can advertise the tools to the model.
  static func toolSpecs(from definitions: [Transcript.ToolDefinition]) -> [ToolSpec] {
    definitions.map { definition in
      var function: [String: any Sendable] = [
        "name": definition.name,
        "description": definition.description,
      ]
      // Best-effort parameter schema: decode the generation schema's JSON if available.
      if let parameters = try? schemaObject(from: definition.parameters) {
        function["parameters"] = parameters
      }
      return [
        "type": "function",
        "function": function,
      ]
    }
  }

  /// Decode a `GenerationSchema` into a JSON-object dictionary for the tool spec.
  static func schemaObject(from schema: GenerationSchema) throws -> [String: any Sendable] {
    let data = try JSONEncoder().encode(schema)
    let object = try JSONSerialization.jsonObject(with: data)
    return (object as? [String: any Sendable]) ?? [:]
  }

  /// Serialize an MLX `ToolCall`'s arguments into a JSON string for `.appendArguments`.
  static func argumentsJSON(for call: ToolCall) -> String {
    let anyArgs = call.function.arguments.mapValues { $0.anyValue }
    if let data = try? JSONSerialization.data(withJSONObject: anyArgs),
      let string = String(data: data, encoding: .utf8)
    {
      return string
    }
    return "{}"
  }
}
