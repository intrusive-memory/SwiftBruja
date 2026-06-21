import ArgumentParser
import BrujaHelpers
import Foundation
import FoundationModels
import MLXLMCommon
import SwiftAcervo
import SwiftBruja
import os

// MARK: - Agent Command

/// `bruja agent` — the agent loop wired into a CLI verb (Sortie 7, R5.1–R5.4).
///
/// Two surfaces over the **same** loop (R5.1):
/// * No positional task → an interactive REPL: read a line, run one agent turn, repeat.
/// * A task string → a one-shot wrapper that runs exactly one turn on that same loop and exits.
///
/// Backend selection (`--backend`/`--model`):
/// * `mlx` (default) drives any SwiftAcervo / mlx-community model through the macOS-26 hand-rolled
///   ``MLXAgentLoop``: `MLXLMCommon` generation parses tool calls natively, and this loop owns the
///   tool round-trip, dispatching each call through a consent-aware ``AgentToolHandling``.
/// * `foundation` drives `SystemLanguageModel.default` through `LanguageModelSession`, which owns
///   the tool round-trip itself.
///
/// Both backends share ONE tool definition: `ToolRegistry.defaultTools()` wrapped in
/// `ConsentToolObserver`s (R2.2, R4). We surface assistant text and each tool call + result through
/// the shared ``IOCoordinator`` (R5.2), wire the Sortie-4 path-escape consent prompt into the tool
/// dispatch path (R5.2/R6.5), honor the Sortie-5 step cap, handle Ctrl-C/`/quit` for graceful stop,
/// and keep the conversation transcript in memory across REPL turns (R5.3–R5.4).
@available(macOS 26.0, *)
struct AgentCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "agent",
    abstract: "Run the on-device agent loop (MLX) with the tool suite",
    discussion: """
      Runs the bruja agent loop: the model can call tools (read_file, write_file,
      edit_file, list_dir, grep, glob, run_shell) to inspect and modify files under
      the current working directory, then answer using the results.

      With no task argument, starts an interactive REPL. With a task string, runs
      that single task end-to-end and exits (same loop, one-shot).

      Filesystem tools are confined to the current working directory. When a tool
      targets a path OUTSIDE the working directory, the agent pauses and asks for
      explicit permission before proceeding.

      Commands (interactive mode):
        /quit   — Exit the agent session
        /clear  — Reset the conversation transcript (model stays loaded)

      Examples:
        bruja agent
        bruja agent "Read ./README.md and summarize the first paragraph"
      """
  )

  @Argument(help: "Optional task to run once and exit. Omit for an interactive REPL.")
  var task: String?

  @Option(name: .long, help: "Sampling temperature (0.0-1.0, default: 0.0 for determinism)")
  var temperature: Float = 0.0

  @Option(name: .long, help: "Maximum tokens to generate per turn (default: 1024)")
  var maxTokens: Int = 1024

  @Flag(name: .shortAndLong, help: "Suppress startup and informational output")
  var quiet = false

  /// Select the inference backend: `mlx` (default) or `foundation`.
  ///
  /// `mlx` routes through the hand-rolled ``MLXAgentLoop`` against any SwiftAcervo model id.
  /// `foundation` routes through `SystemLanguageModel` (Foundation Models, S9); selecting it
  /// when FM is unavailable on this host is a full-stop typed error — no silent fallback.
  @Option(
    name: .long,
    help:
      "Backend to use: 'mlx' (default, any acervo model id) or 'foundation' (on-device FM, S9)."
  )
  var backend: String?

  /// Override the model id used by the MLX backend.
  ///
  /// Ignored when `--backend foundation` is selected (Foundation Models uses
  /// `SystemLanguageModel.default`, not a model-file id). When omitted with the MLX backend,
  /// defaults to ``AgentAllowlist/agentDefaultModel``.
  @Option(
    name: [.short, .long],
    help:
      "MLX model id (e.g., mlx-community/Qwen2.5-7B-Instruct-4bit). Ignored with --backend foundation."
  )
  var model: String?

  // MARK: - Constants

  /// The agentic default model id (Sortie 8, R7 / OQ-3).
  ///
  /// Deliberately distinct from `Bruja.defaultModel` ("mlx-community/Llama-3.2-1B-Instruct-4bit"),
  /// which is the lighter-weight default used by `query`/`chat`. The agent path requires a
  /// larger, tool-capable instruct model. This 7B model is CDN-verified present (4.3 GB, 10 files).
  /// Do NOT use `Qwen2.5-Coder-7B-Instruct-4bit` — it returns HTTP 404 on the CDN (OQ-3).
  static let agentDefaultModel: String = AgentAllowlist.agentDefaultModel

  // MARK: - Run

  func run() async throws {
    try await runCLI {
      let renderer = ProgressRenderer(quiet: quiet)
      await renderer.logStartup("[bruja] SharedModels: \(Acervo.sharedModelsDirectory.path)")

      // Resolve backend + effective model id from --backend / --model flags.
      // The selector is the explicit --backend flag if set; otherwise the explicit --model id
      // (which implies the MLX backend); otherwise nil (use defaults).
      let selector = backend ?? model
      let (resolvedBackend, resolvedModelId) = AgentBackendSelector.resolve(selector: selector)

      // When a --model is given but --backend is 'foundation', warn that --model is ignored.
      if resolvedBackend == .foundation, let explicitModel = model {
        if !quiet {
          print(
            "[bruja] Warning: --model '\(explicitModel)' is ignored when --backend foundation is selected."
          )
        }
      }

      switch resolvedBackend {
      case .foundation:
        // S9: Foundation Models backend — availability gate + real FM session.
        let availability = LiveFoundationModelsAvailability()
        guard availability.isAvailable else {
          let reason =
            availability.unavailabilityReason ?? "unknown reason"
          throw CLIError(
            "Foundation Models is not available on this host: \(reason). "
              + "Use '--backend mlx' (or omit --backend) to run with an MLX model instead."
          )
        }

        let io = IOCoordinator(quiet: quiet)
        let loop = AgentLoop(
          backend: .foundation,
          io: io,
          quiet: quiet
        )

        if let task, !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          // One-shot: a single turn on the same loop, then exit.
          do {
            try await loop.runTurn(task)
          } catch let bruja as BrujaError {
            throw CLIError(bruja.errorDescription ?? "\(bruja)")
          }
        } else {
          try await loop.runInteractive()
        }

      case .mlx:
        let effectiveModel = resolvedModelId ?? Self.agentDefaultModel

        // Warn if the selected model is not on the curated agent-capable allowlist (R3.3 / R7.3).
        if !AgentAllowlist.isAgentCapable(effectiveModel), !quiet {
          print(
            "[bruja] Warning: '\(effectiveModel)' is not on the agent-capable allowlist and may not tool-call reliably."
          )
        }

        // Preflight: the MLX model must exist on the CDN (unless already present
        // locally). Throws and stops before loading if it is not published. The
        // Foundation Models backend has no model file, so this gate is MLX-only.
        try await ensureModelObtainable(effectiveModel)

        let io = IOCoordinator(quiet: quiet)
        let loop = AgentLoop(
          modelId: effectiveModel,
          temperature: temperature,
          maxTokens: maxTokens,
          io: io,
          quiet: quiet
        )

        if let task, !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          // One-shot: a single turn on the same loop, then exit.
          try await loop.runTurn(task)
        } else {
          try await loop.runInteractive()
        }
      }
    }
  }
}

// MARK: - Agent Loop

/// The shared agent loop backing both the one-shot and interactive surfaces of `bruja agent`.
///
/// Holds one backend engine so the conversation transcript persists across REPL turns (R5.4). All
/// terminal I/O routes through the injected ``IOCoordinator`` (R5.2). Both backends consume the
/// SAME `ToolRegistry.defaultTools()` array wrapped in `ConsentToolObserver`s (R2.2, R4); they
/// differ only in who owns the tool round-trip:
/// * `.mlx` → the hand-rolled ``MLXAgentLoop`` (macOS 26, `MLXLMCommon` generation).
/// * `.foundation` → `LanguageModelSession` (the framework owns the round-trip).
@available(macOS 26.0, *)
final class AgentLoop {
  private let io: IOCoordinator
  private let quiet: Bool

  /// Human-readable model label surfaced in the REPL startup banner.
  let modelLabel: String

  /// The recording/consent tool wrappers backing this loop. Their accumulated observations are how
  /// the REPL surfaces tool calls + results (R5.2) and how `AgentReplTest` asserts the round-trip.
  let toolObservers: [ConsentToolObserver]

  private let engine: Engine

  private enum Engine {
    /// Foundation Models: the framework owns the tool round-trip.
    case foundation(LanguageModelSession)
    /// MLX: the hand-rolled loop owns the tool round-trip.
    case mlx(MLXAgentLoop)
  }

  /// The agent's system instructions — identical for both backends.
  static let agentInstructions =
    "You are a capable command-line agent operating in the user's current working directory. "
    + "You can call tools to inspect and modify files: read_file, write_file, edit_file, "
    + "list_dir, grep, glob, run_shell. "
    + "When asked about a file's contents, you MUST call the read_file tool with the EXACT path "
    + "provided before answering — do NOT guess or claim the file is missing without calling "
    + "read_file first. After a tool returns, answer using its result. Be concise."

  // MARK: - MLX initializer

  /// Initialise an MLX-backed agent loop driving the hand-rolled ``MLXAgentLoop``.
  ///
  /// Tool calls are dispatched through a ``ConsentToolDispatcher`` that wraps every registry tool in
  /// a `ConsentToolObserver` so the loop can surface each call + result through the IOCoordinator and
  /// intercept the Sortie-4 path-escape outcome to fire the consent prompt (R5.2/R6.5).
  init(
    modelId: String,
    temperature: Float,
    maxTokens: Int,
    io: IOCoordinator,
    quiet: Bool
  ) {
    self.io = io
    self.quiet = quiet
    self.modelLabel = modelId

    let dispatcher = ConsentToolDispatcher(io: io)
    self.toolObservers = dispatcher.observers

    let loop = MLXAgentLoop(
      configuration: MLXAgentLoop.Configuration(
        modelId: modelId,
        temperature: temperature,
        maxTokens: maxTokens,
        maxSteps: 32,
        instructions: Self.agentInstructions
      ),
      tools: dispatcher
    )
    self.engine = .mlx(loop)
  }

  // MARK: - Foundation Models initializer (S9)

  /// Initialise a Foundation Models–backed agent loop.
  ///
  /// Builds a `LanguageModelSession(model: SystemLanguageModel.default, tools:, instructions:)`
  /// using the SAME `ToolRegistry.defaultTools()` array wrapped in the SAME `ConsentToolObserver`s
  /// as the MLX path — NO second tool adapter (R2.2, R4).
  ///
  /// - Parameters:
  ///   - backend: Must be `.foundation`. The `backend` label selects this initializer over the MLX
  ///     one; it has no runtime role.
  ///   - io: Shared IOCoordinator for all terminal I/O.
  ///   - quiet: Forwarded to `IOCoordinator` construction.
  init(
    backend: AgentBackend,
    io: IOCoordinator,
    quiet: Bool
  ) {
    precondition(backend == .foundation, "This initializer is for the Foundation Models backend")
    self.io = io
    self.quiet = quiet
    self.modelLabel = "SystemLanguageModel.default (Foundation Models)"

    // SAME ConsentToolObserver wrapping of the SAME ToolRegistry array as the MLX path.
    let observers = ToolRegistry.defaultTools().map { ConsentToolObserver(inner: $0, io: io) }
    self.toolObservers = observers
    let wrappedTools: [any FoundationModels.Tool] = observers.map { $0.makeWrapper() }

    self.engine = .foundation(
      FoundationModelBackend.makeSession(
        tools: wrappedTools,
        instructions: Self.agentInstructions
      )
    )
  }

  // MARK: - Interactive REPL

  func runInteractive() async throws {
    // Graceful Ctrl-C: install a SIGINT source that flushes a goodbye line and exits 0 rather than
    // killing the process mid-write. `signal(SIGINT, SIG_IGN)` first so the default terminate
    // disposition does not race the dispatch source. The source lives for the REPL's lifetime.
    signal(SIGINT, SIG_IGN)
    let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigintSource.setEventHandler {
      FileHandle.standardError.write(Data("\n[bruja] interrupted — exiting.\n".utf8))
      Foundation.exit(0)
    }
    sigintSource.resume()
    defer { sigintSource.cancel() }

    await io.emitLine("[bruja] agent ready — model: \(modelLabel)")
    await io.emitLine("[bruja] Type /quit to exit, /clear to reset the conversation.")

    while true {
      guard let line = await io.prompt(">") else {
        // EOF (Ctrl-D) — graceful stop.
        await io.emitLine("")
        break
      }

      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty { continue }

      switch trimmed.lowercased() {
      case "/quit", "/exit", "quit", "exit":
        await io.emitLine("[bruja] bye.")
        return
      case "/clear":
        await resetConversation()
        await io.emitLine("[bruja] conversation reset (model stays loaded).")
        continue
      default:
        break
      }

      do {
        try await runTurn(trimmed)
      } catch let bruja as BrujaError {
        // Step-cap and generation errors are recoverable in a REPL — report and keep going.
        await io.emitLine("[bruja] \(bruja.errorDescription ?? "\(bruja)")")
      } catch is CancellationError {
        await io.emitLine("\n[bruja] interrupted.")
      }
    }
  }

  /// Reset the in-memory conversation. The MLX loop clears its transcript + KV cache; the
  /// Foundation Models session's transcript is framework-owned and cannot be reset in place.
  private func resetConversation() async {
    if case .mlx(let loop) = engine {
      await loop.reset()
    }
  }

  // MARK: - One turn (shared by one-shot and interactive)

  /// Run exactly one agent turn for `userInput`: stream assistant text + surface tool calls/results
  /// through the IOCoordinator. The owner of the tool round-trip differs per backend; the consent
  /// observers report each dispatch as it happens regardless.
  func runTurn(_ userInput: String) async throws {
    // Mark a fresh observation window so we can surface only this turn's tool activity.
    for observer in toolObservers { await observer.beginTurn() }

    switch engine {
    case .foundation(let session):
      do {
        let response = try await session.respond(to: userInput)
        await io.streamLine(response.content)
      } catch let bruja as BrujaError {
        throw bruja
      } catch {
        // Map FM errors (LanguageModelError) into typed BrujaErrors.
        throw FoundationModelBackend.mapFMError(error)
      }

    case .mlx(let loop):
      // The consent observers echo each tool call/result via the IOCoordinator as they happen, so
      // here we only need to accumulate the model's final answer and emit it once the turn settles.
      // Resetting on each tool round-trip keeps only the final (post-tool) assistant text.
      let answer = AnswerAccumulator()
      try await loop.runTurn(userInput) { event in
        switch event {
        case .assistantText(let text):
          await answer.append(text)
        case .toolCallStarted:
          await answer.reset()
        case .toolFinished:
          break
        }
      }
      let finalAnswer = await answer.value
      if !finalAnswer.isEmpty {
        await io.streamLine(finalAnswer)
      } else {
        // The model generated tokens but nothing usable surfaced — typically a malformed tool call
        // (e.g. invalid JSON arguments) that the parser drops. Don't exit silently on an empty turn.
        await io.emitLine(
          "[bruja] (no answer produced — the model likely emitted an unparseable tool call; "
            + "try the default model or a larger one, e.g. mlx-community/Qwen2.5-7B-Instruct-4bit)")
      }
    }
  }
}

/// Accumulates the MLX loop's streamed assistant text for a single turn. An actor so the loop's
/// `@Sendable` event closure can mutate it safely.
@available(macOS 26.0, *)
private actor AnswerAccumulator {
  private(set) var value = ""
  func append(_ text: String) { value += text }
  func reset() { value = "" }
}

// MARK: - Consent-aware MLX tool dispatcher

/// The MLX backend's ``AgentToolHandling``: advertises `ToolRegistry.defaultTools()` to the model
/// and dispatches each tool call by name, routing the result through a `ConsentToolObserver` so the
/// Sortie-4 path-escape consent prompt fires before an out-of-cwd access proceeds (R5.2/R6.5).
///
/// `@unchecked Sendable`: all stored state is immutable after init and itself Sendable
/// (`ConsentToolObserver` is `@unchecked Sendable`; tools are `Sendable`).
@available(macOS 26.0, *)
final class ConsentToolDispatcher: AgentToolHandling, @unchecked Sendable {
  /// The consent/observation wrappers, one per tool — exposed so `AgentLoop` can `beginTurn()` them.
  let observers: [ConsentToolObserver]

  private let tools: [any FoundationModels.Tool]
  private let toolByName: [String: any FoundationModels.Tool]
  private let observerByName: [String: ConsentToolObserver]

  init(io: IOCoordinator, tools: [any FoundationModels.Tool] = ToolRegistry.defaultTools()) {
    self.tools = tools
    let obs = tools.map { ConsentToolObserver(inner: $0, io: io) }
    self.observers = obs
    self.toolByName = Dictionary(tools.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    self.observerByName = Dictionary(obs.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
  }

  func toolSpecs() -> [ToolSpec] {
    MLXToolEncoding.toolSpecs(from: tools)
  }

  func dispatch(name: String, argumentsJSON: String) async throws -> String {
    guard let tool = toolByName[name] else {
      return ToolResult.error("unknown tool: \(name)")
    }
    // Dispatch the tool (which runs PathGuard internally and may return the escape marker).
    let raw = try await dispatchTool(tool, argumentsJSON: argumentsJSON)

    guard let observer = observerByName[name] else { return raw }
    return try await observer.handle(
      argumentSummary: argumentsJSON,
      rawResult: raw,
      rerun: {
        // Re-run with cwd confinement relaxed: temporarily set the process cwd to "/" so PathGuard
        // re-classifies the (now in-root) path as allowed, then restore. Tool dispatch within a
        // turn is serialized, so the brief cwd swap is safe (documented TOCTOU caveat in PathGuard).
        let saved = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath("/")
        defer { FileManager.default.changeCurrentDirectoryPath(saved) }
        return try await dispatchTool(tool, argumentsJSON: argumentsJSON)
      }
    )
  }
}

// MARK: - Consent / observation tool wrapper

/// Observes one wrapped tool's dispatches for a single loop, and owns the consent decision when the
/// tool reports a Sortie-4 path escape. The observer is `Sendable` (state behind a lock) so it can
/// be shared across the loop's tool dispatch and the generic `Tool` wrapper it vends for the
/// Foundation Models path.
@available(macOS 26.0, *)
final class ConsentToolObserver: @unchecked Sendable {
  let name: String
  private let inner: any FoundationModels.Tool
  private let io: IOCoordinator

  private struct State {
    var calls: [String] = []
    var results: [String] = []
  }
  private let state = OSAllocatedUnfairLock(initialState: State())

  /// Tool calls observed since the last ``beginTurn()``.
  var calls: [String] { state.withLock { $0.calls } }
  /// Tool results observed since the last ``beginTurn()``.
  var results: [String] { state.withLock { $0.results } }

  init(inner: any FoundationModels.Tool, io: IOCoordinator) {
    self.name = inner.name
    self.inner = inner
    self.io = io
  }

  func beginTurn() async {
    state.withLock {
      $0.calls.removeAll(keepingCapacity: true)
      $0.results.removeAll(keepingCapacity: true)
    }
  }

  /// Record + report a dispatch, and run the consent flow if the inner result is a path escape.
  ///
  /// - Parameters:
  ///   - argumentSummary: A compact rendering of the call's arguments for the audit line.
  ///   - rawResult: The string the inner tool returned.
  ///   - rerun: A closure that re-invokes the inner tool with cwd confinement relaxed, used to
  ///     proceed after the user grants consent.
  /// - Returns: The result string to hand back to the model (the original, the post-consent rerun,
  ///   or a denial).
  func handle(
    argumentSummary: String,
    rawResult: String,
    rerun: () async throws -> String
  ) async rethrows -> String {
    await io.emitLine("[bruja] → \(name)(\(argumentSummary))")

    // Path-escape consent (R6.5): the Sortie-4 outcome is a typed error carrying `escapeMarker`.
    if rawResult.hasPrefix(ToolResult.errorPrefix + ToolResult.escapeMarker) {
      let resolved = Self.extractResolvedPath(from: rawResult)
      let granted = await io.requestPathEscapeConsent(
        operation: name, resolvedPath: resolved)
      if granted {
        let after = try await rerun()
        record(call: argumentSummary, result: after)
        await io.emitLine("[bruja]   ✓ permitted; result: \(Self.summarize(after))")
        return after
      } else {
        let denial = ToolResult.error("user denied access to a path outside the working directory")
        record(call: argumentSummary, result: denial)
        await io.emitLine("[bruja]   ✗ denied")
        return denial
      }
    }

    record(call: argumentSummary, result: rawResult)
    await io.emitLine("[bruja]   result: \(Self.summarize(rawResult))")
    return rawResult
  }

  private func record(call: String, result: String) {
    state.withLock {
      $0.calls.append(call)
      $0.results.append(result)
    }
  }

  /// Vend the generic, type-erased `Tool` the Foundation Models session is built with. The wrapper
  /// forwards `Arguments` verbatim to the inner tool and routes the result through ``handle``.
  ///
  /// `inner` is an existential `any FoundationModels.Tool`; we open it via the generic helper so the wrapper's
  /// associated `Arguments` type binds to the concrete inner tool's `Arguments`.
  func makeWrapper() -> any FoundationModels.Tool {
    // Open the `any FoundationModels.Tool` existential. Every registry tool returns `String`; the
    // `StringOutputTool` refinement lets the opened type bind `Output == String` so the typed
    // `ConsentToolWrapper` can be constructed. A tool that did not return String (none today) would
    // fall through to the unwrapped tool.
    if let stringTool = inner as? any StringOutputTool {
      return Self.wrap(stringTool, observer: self)
    }
    return inner
  }

  /// Build a typed wrapper from an opened `StringOutputTool` existential.
  private static func wrap<T: StringOutputTool>(
    _ tool: T, observer: ConsentToolObserver
  ) -> any FoundationModels.Tool {
    ConsentToolWrapper(observer: observer, inner: tool)
  }

  private static func summarize(_ text: String) -> String {
    let oneLine = text.replacingOccurrences(of: "\n", with: " ")
    return oneLine.count > 200 ? String(oneLine.prefix(200)) + "…" : oneLine
  }

  private static func extractResolvedPath(from result: String) -> String {
    // Format: "ERROR: CONSENT_REQUIRED: <op> ... (path: <resolved>)"
    if let range = result.range(of: "(path: "),
      let close = result.range(of: ")", range: range.upperBound..<result.endIndex)
    {
      return String(result[range.upperBound..<close.lowerBound])
    }
    return "(unknown)"
  }
}

/// A generic, type-erased forwarding `Tool` that preserves an inner tool's `Arguments`/name/
/// description while routing the result through its ``ConsentToolObserver``.
///
/// Used only by the Foundation Models path, where the framework dispatches `Tool`s and we cannot
/// intercept *between* the model emitting a tool call and the framework dispatching it — so the
/// consent gate lives here, inside the dispatched tool. (The MLX path owns its round-trip and routes
/// consent through ``ConsentToolDispatcher`` instead.)
@available(macOS 26.0, *)
private struct ConsentToolWrapper<Inner: StringOutputTool>: FoundationModels.Tool {
  typealias Arguments = Inner.Arguments
  typealias Output = String

  let observer: ConsentToolObserver
  let inner: Inner

  init(observer: ConsentToolObserver, inner: Inner) {
    self.observer = observer
    self.inner = inner
  }

  var name: String { inner.name }
  var description: String { inner.description }
  var parameters: GenerationSchema { inner.parameters }

  func call(arguments: Arguments) async throws -> String {
    let raw = try await inner.call(arguments: arguments)
    return try await observer.handle(
      argumentSummary: Self.summarizeArguments(arguments),
      rawResult: raw,
      rerun: {
        let saved = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath("/")
        defer { FileManager.default.changeCurrentDirectoryPath(saved) }
        return try await inner.call(arguments: arguments)
      }
    )
  }

  /// Best-effort compact rendering of the call arguments for the audit line.
  private static func summarizeArguments(_ arguments: Arguments) -> String {
    String(describing: arguments)
  }
}
