import Foundation
import FoundationModels
import MLXLMCommon

// MARK: - Tool encoding (FoundationModels.Tool -> MLX ToolSpec)

/// Converts `FoundationModels.Tool` definitions into the MLX `ToolSpec` dictionaries the chat
/// template advertises to the model, and serializes MLX `ToolCall` arguments back to JSON.
///
/// All of this is macOS-26 (`Tool`, `GenerationSchema`, `ToolSpec`). It replaces the transcript-
/// derived encoding that used to live in the removed macOS-27 executor seam.
@available(macOS 26.0, *)
public enum MLXToolEncoding {

  /// Build MLX `ToolSpec`s (OpenAI-style function schemas) from the tool suite so the chat template
  /// can advertise the tools to the model.
  public static func toolSpecs(from tools: [any FoundationModels.Tool]) -> [ToolSpec] {
    tools.map { tool in
      var function: [String: any Sendable] = [
        "name": tool.name,
        "description": tool.description,
      ]
      // Best-effort parameter schema: encode the tool's generation schema to a JSON object.
      if let parameters = try? schemaObject(from: tool.parameters) {
        function["parameters"] = parameters
      }
      return [
        "type": "function",
        "function": function,
      ]
    }
  }

  /// Decode a `GenerationSchema` into a JSON-object dictionary for the tool spec.
  public static func schemaObject(from schema: GenerationSchema) throws -> [String: any Sendable] {
    let data = try JSONEncoder().encode(schema)
    let object = try JSONSerialization.jsonObject(with: data)
    return (object as? [String: any Sendable]) ?? [:]
  }

  /// Serialize an MLX `ToolCall`'s arguments into a JSON string for the loop's tool dispatch.
  public static func argumentsJSON(for call: ToolCall) -> String {
    let anyArgs = call.function.arguments.mapValues { $0.anyValue }
    if let data = try? JSONSerialization.data(withJSONObject: anyArgs),
      let string = String(data: data, encoding: .utf8)
    {
      return string
    }
    return "{}"
  }
}

// MARK: - StringOutputTool

/// A `Tool` whose `Output` is `String`. Used to open an `any FoundationModels.Tool` existential to a concrete type
/// so the model's JSON tool-call arguments can be decoded into the tool's `@Generable` `Arguments`
/// and dispatched. Every tool in ``ToolRegistry`` returns `String`.
@available(macOS 26.0, *)
public protocol StringOutputTool: FoundationModels.Tool where Output == String {}

@available(macOS 26.0, *) extension ReadFileTool: StringOutputTool {}
@available(macOS 26.0, *) extension WriteFileTool: StringOutputTool {}
@available(macOS 26.0, *) extension EditFileTool: StringOutputTool {}
@available(macOS 26.0, *) extension ListDirTool: StringOutputTool {}
@available(macOS 26.0, *) extension GrepTool: StringOutputTool {}
@available(macOS 26.0, *) extension GlobTool: StringOutputTool {}
@available(macOS 26.0, *) extension RunShellTool: StringOutputTool {}

// MARK: - JSON tool dispatch

/// Dispatch an `any FoundationModels.Tool` from the model's JSON tool-call arguments.
///
/// Decodes `argumentsJSON` into the tool's `@Generable` `Arguments` via `GeneratedContent(json:)`
/// (macOS 26), then calls the tool. A tool that does not return `String`, or arguments that fail to
/// decode, yield a typed error *string* (never a throw) so the model can recover on the next turn.
@available(macOS 26.0, *)
public func dispatchTool(_ tool: any FoundationModels.Tool, argumentsJSON: String) async throws -> String {
  guard let stringTool = tool as? any StringOutputTool else {
    return ToolResult.error("tool '\(tool.name)' is not dispatchable (non-String output)")
  }
  return try await dispatchStringTool(stringTool, argumentsJSON: argumentsJSON)
}

@available(macOS 26.0, *)
private func dispatchStringTool<T: StringOutputTool>(
  _ tool: T,
  argumentsJSON: String
) async throws -> String {
  let content: GeneratedContent
  do {
    content = try GeneratedContent(json: argumentsJSON)
  } catch {
    return ToolResult.error(
      "invalid tool-call arguments JSON for '\(tool.name)': \(error.localizedDescription)")
  }

  let arguments: T.Arguments
  do {
    arguments = try T.Arguments(content)
  } catch {
    return ToolResult.error(
      "could not decode arguments for '\(tool.name)': \(error.localizedDescription)")
  }

  return try await tool.call(arguments: arguments)
}

// MARK: - Agent tool handling

/// The tool-side seam ``MLXAgentLoop`` calls: advertise the tools to the model and dispatch a tool
/// call by name. The CLI injects a consent-aware implementation; tests use ``RegistryToolHandler``.
@available(macOS 26.0, *)
public protocol AgentToolHandling: Sendable {
  /// The MLX tool specs advertised to the model in the chat template.
  func toolSpecs() -> [ToolSpec]

  /// Dispatch the named tool with the model's JSON arguments and return the result string fed back
  /// to the model on the next turn.
  func dispatch(name: String, argumentsJSON: String) async throws -> String
}

/// A consent-free ``AgentToolHandling`` over a fixed tool suite (defaults to
/// ``ToolRegistry/defaultTools()``). Used by unit tests and as the baseline dispatcher.
@available(macOS 26.0, *)
public struct RegistryToolHandler: AgentToolHandling {
  private let tools: [any FoundationModels.Tool]

  public init(tools: [any FoundationModels.Tool] = ToolRegistry.defaultTools()) {
    self.tools = tools
  }

  public func toolSpecs() -> [ToolSpec] {
    MLXToolEncoding.toolSpecs(from: tools)
  }

  public func dispatch(name: String, argumentsJSON: String) async throws -> String {
    guard let tool = tools.first(where: { $0.name == name }) else {
      return ToolResult.error("unknown tool: \(name)")
    }
    return try await dispatchTool(tool, argumentsJSON: argumentsJSON)
  }
}

// MARK: - Agent turn events

/// Events surfaced by ``MLXAgentLoop/runTurn(_:onEvent:)`` so the CLI can stream assistant text and
/// echo tool activity through its `IOCoordinator`.
public enum AgentTurnEvent: Sendable {
  /// A streamed chunk of assistant text.
  case assistantText(String)
  /// A tool call is about to be dispatched (model-requested).
  case toolCallStarted(name: String, argumentsJSON: String)
  /// A tool call finished; `result` is what is fed back to the model.
  case toolFinished(name: String, result: String)
}
