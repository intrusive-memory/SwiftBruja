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

    /// Maximum number of agent steps (model turns / tool round-trips) allowed for a single
    /// conversation before the executor surfaces ``BrujaError/agentStepLimitExceeded(limit:)``
    /// (R5.3). A "step" is one `respond` invocation; tool round-trips re-enter `respond`, so this
    /// caps runaway tool loops. The default is intentionally generous for interactive use.
    public var maxSteps: Int

    public init(
      modelId: String,
      temperature: Float = 0.7,
      maxTokens: Int = 1024,
      maxSteps: Int = 32
    ) {
      self.modelId = modelId
      self.temperature = temperature
      self.maxTokens = maxTokens
      self.maxSteps = maxSteps
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
    maxTokens: Int = 1024,
    maxSteps: Int = 32
  ) {
    self.init(
      Configuration(
        modelId: modelId,
        temperature: temperature,
        maxTokens: maxTokens,
        maxSteps: maxSteps
      )
    )
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

  /// The generation source the executor pulls events from. In production this is a
  /// ``ContainerGenerationSource`` that drives the resolved MLX `ModelContainer` while reusing a
  /// KV cache across turns; in tests it can be a scripted mock (see ``GenerationSource``).
  private let source: any GenerationSource

  /// Per-conversation mutable state (reused KV cache + step counter) shared across `respond`
  /// invocations. `respond` is `nonisolated`, so this state lives behind an actor.
  private let turnState: TurnState

  public init(configuration: Configuration) throws {
    self.configuration = configuration
    self.source = ContainerGenerationSource(modelId: configuration.modelId)
    self.turnState = TurnState(maxSteps: configuration.maxSteps)
  }

  /// Internal designated initializer used for testing: inject a scripted ``GenerationSource`` and
  /// optionally share a ``TurnState`` so step-cap behavior can be asserted across turns.
  internal init(
    configuration: Configuration,
    source: any GenerationSource,
    turnState: TurnState? = nil
  ) {
    self.configuration = configuration
    self.source = source
    self.turnState = turnState ?? TurnState(maxSteps: configuration.maxSteps)
  }

  /// Optional: warm the model container so the first `respond` is faster. Best-effort.
  public func prewarm(model: MLXLanguageModel, transcript: Transcript) {
    source.prewarm()
  }

  public nonisolated func respond(
    to request: LanguageModelExecutorGenerationRequest,
    model: MLXLanguageModel,
    streamingInto channel: LanguageModelExecutorGenerationChannel
  ) async throws {
    // 0. Enforce the per-conversation step/turn cap (R5.3). Each `respond` is one step; tool
    //    round-trips re-enter `respond`, so this bounds runaway tool loops. Throws a typed
    //    `BrujaError` rather than spinning forever.
    try await turnState.beginStep()

    // 1. Map the FoundationModels transcript into an ordered MLX chat (multi-turn correctness).
    let messages = Self.chatMessages(from: request.transcript)

    // 2. Map the enabled FoundationModels tools into MLX tool specs so the chat template
    //    advertises them to the model.
    let toolSpecs = Self.toolSpecs(from: request.enabledToolDefinitions)

    let parameters = GenerateParameters(
      maxTokens: configuration.maxTokens,
      temperature: configuration.temperature
    )

    // 3. Pull generation events from the source. The container source reuses the KV cache held in
    //    `turnState` across turns; any context-overflow / generation failure is surfaced as a typed
    //    `BrujaError` (R2.4) rather than crashing.
    let stream: AsyncThrowingStream<BrujaGenerationEvent, any Error>
    do {
      stream = try await source.generate(
        messages: messages,
        toolSpecs: toolSpecs,
        parameters: parameters,
        turnState: turnState
      )
    } catch {
      throw Self.mapGenerationError(error)
    }

    // 4. Translate generation events into channel events.
    var emittedToolCall = false
    var emittedText = false

    do {
      for try await item in stream {
        switch item {
        case .text(let text):
          guard !text.isEmpty else { continue }
          emittedText = true
          await channel.send(
            .response(action: .appendText(text, tokenCount: 0))
          )

        case .toolCall(let id, let name, let argumentsJSON):
          emittedToolCall = true
          await channel.send(
            .toolCalls(
              action: .toolCall(
                id: id,
                name: name,
                action: .appendArguments(argumentsJSON, tokenCount: 0)
              )
            )
          )

        case .info:
          // token-rate / completion metadata — not surfaced as a channel event.
          continue
        }
      }
    } catch {
      throw Self.mapGenerationError(error)
    }

    // If the model produced neither text nor a tool call (e.g. an immediate stop), emit an empty
    // response so the framework sees a well-formed (if empty) turn rather than nothing.
    if !emittedToolCall && !emittedText {
      await channel.send(.response(action: .appendText("", tokenCount: 0)))
    }
  }

  // MARK: - Error mapping (R2.4)

  /// Map a generation/context failure into a typed ``BrujaError``. Already-typed `BrujaError`s pass
  /// through unchanged; everything else is heuristically classified as context-window overflow vs.
  /// a generic query failure so callers never see a raw crash.
  static func mapGenerationError(_ error: any Error) -> BrujaError {
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

// MARK: - Generation seam

/// A backend-neutral generation event. This is the seam between the executor's channel-mapping
/// logic and the actual token producer. Mirroring MLX's `Generation` into a small MLX-free enum
/// lets unit tests script generation without a model, network, or any MLX types.
@available(macOS 27.0, *)
public enum BrujaGenerationEvent: Sendable {
  /// A decoded text chunk.
  case text(String)
  /// A parsed tool call (id + name + already-serialized JSON arguments).
  case toolCall(id: String, name: String, argumentsJSON: String)
  /// Completion / token-rate metadata; not surfaced as a channel event.
  case info
}

/// The injectable token producer behind ``MLXLanguageModelExecutor``. The production
/// implementation drives an MLX `ModelContainer`; tests provide a scripted mock.
@available(macOS 27.0, *)
public protocol GenerationSource: Sendable {
  /// Best-effort warm-up. No-op for mocks.
  func prewarm()

  /// Produce a stream of generation events for the given chat. Implementations that maintain a KV
  /// cache should reuse the one held by `turnState` across turns.
  func generate(
    messages: [Chat.Message],
    toolSpecs: [ToolSpec],
    parameters: GenerateParameters,
    turnState: TurnState
  ) async throws -> AsyncThrowingStream<BrujaGenerationEvent, any Error>
}

@available(macOS 27.0, *)
extension GenerationSource {
  public func prewarm() {}
}

/// Per-conversation mutable state shared across `respond` invocations: the reused KV cache and the
/// step counter that enforces the configured cap (R5.3). An actor because `respond` is
/// `nonisolated` and may be re-entered concurrently by tool round-trips.
/// An `@unchecked Sendable` wrapper for the non-`Sendable` `[KVCache]`. The cache is only ever
/// read/mutated inside the model container's serialized `context.read` closure (single-threaded
/// model access), so transferring the *reference* across the actor boundary is sound even though
/// the type is not nominally `Sendable`.
@available(macOS 27.0, *)
final class KVCacheBox: @unchecked Sendable {
  let cache: [KVCache]
  init(_ cache: [KVCache]) { self.cache = cache }
}

@available(macOS 27.0, *)
public actor TurnState {
  /// The KV cache reused across turns, boxed for `Sendable` transfer. `Any` so this type stays
  /// usable by MLX-free mocks; the container source casts it back to ``KVCacheBox``.
  private var kvCache: Any?

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

  /// Reset the conversation state (cache + step counter) — e.g. on `/clear` / new session.
  public func reset() {
    kvCache = nil
    stepCount = 0
  }

  /// Retrieve the reused KV cache (typed by the caller).
  func cache<T>(as type: T.Type) -> T? {
    kvCache as? T
  }

  /// Store the KV cache for reuse on the next turn.
  func setCache(_ cache: Any) {
    kvCache = cache
  }
}

// MARK: - Container-backed generation source (production)

/// Production ``GenerationSource`` that drives the resolved MLX `ModelContainer`, reusing a KV
/// cache across turns so prompt prefixes are not re-encoded every turn.
///
/// Correctness note: cache reuse uses the lower-level `MLXLMCommon.generate(input:cache:…)` API,
/// passing the `[KVCache]` held by ``TurnState``. The first turn allocates the cache via
/// `model.newCache(parameters:)`; subsequent turns hand the same cache back. This mirrors how the
/// MLX `ChatSession` reuses caches across turns.
@available(macOS 27.0, *)
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

    let userInput = UserInput(
      chat: messages,
      tools: toolSpecs.isEmpty ? nil : toolSpecs
    )

    // Reuse the KV cache across turns. On the first turn we allocate a fresh cache on the model and
    // persist the (boxed) instance in turnState; on later turns we hand the *same* box back. The
    // single box instance is what both generation and persistence reference, so the cache populated
    // during one turn is the one prefilled-against on the next (prompt-prefix reuse).
    let box: KVCacheBox
    if let existing = await turnState.cache(as: KVCacheBox.self) {
      box = existing
    } else {
      box = await container.perform { (context: ModelContext) in
        KVCacheBox(context.model.newCache(parameters: parameters))
      }
      await turnState.setCache(box)
    }

    // Prepare the input and run generation inside one serialized model access, passing the reused
    // KV cache. `UserInput`/`LMInput` are non-`Sendable`, so they are constructed/consumed entirely
    // within the closure's isolation (via the `nonSendable:` overload). The cache box is
    // `@unchecked Sendable` and safe to capture (only touched here, single-threaded).
    let mlxStream: AsyncStream<Generation> = try await container.perform(nonSendable: userInput) {
      (context: ModelContext, userInput: UserInput) -> AsyncStream<Generation> in
      let input = try await context.processor.prepare(input: userInput)
      return try MLXLMCommon.generate(
        input: input,
        cache: box.cache,
        parameters: parameters,
        context: context
      )
    }

    return AsyncThrowingStream<BrujaGenerationEvent, any Error> { continuation in
      let task = Task {
        for await item in mlxStream {
          switch item {
          case .chunk(let text):
            continuation.yield(.text(text))
          case .toolCall(let call):
            continuation.yield(
              .toolCall(
                id: UUID().uuidString,
                name: call.function.name,
                argumentsJSON: MLXLanguageModelExecutor.argumentsJSON(for: call)
              )
            )
          case .info:
            continuation.yield(.info)
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
