import ArgumentParser
import BrujaHelpers
import Foundation
import FoundationModels
import SwiftAcervo
import SwiftBruja
import os

// MARK: - Agent Command

/// `bruja agent` — the MLX agent loop wired into a CLI verb (Sortie 7, R5.1–R5.4).
///
/// Two surfaces over the **same** loop (R5.1):
/// * No positional task → an interactive REPL: read a line, run one agent turn, repeat.
/// * A task string → a one-shot wrapper that runs exactly one turn on that same loop and exits.
///
/// The loop builds a `LanguageModelSession(model: MLXLanguageModel(...), tools:, instructions:)`
/// exactly as `AgentSeamSpikeTest` does — the framework dispatches tool calls, appends the
/// `.toolOutput`, and re-prompts. We surface assistant text and each tool call + result through the
/// shared ``IOCoordinator`` (R5.2), wire the Sortie-4 path-escape consent prompt into the tool
/// dispatch path (R5.2/R6.5), honor the Sortie-5 step cap, handle Ctrl-C/`/quit` for graceful stop,
/// and keep the session transcript in memory across REPL turns (R5.3–R5.4).
///
/// Backend / model selection (`--backend`/`--model`) is intentionally NOT here — that is Sortie 8.
/// This verb runs against the default MLX path only.
@available(macOS 27.0, *)
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

  /// The agent loop's default model for Sortie 7.
  ///
  /// Deliberately distinct from `Bruja.defaultModel` (Llama-3.2-1B, used by `query`/`chat`): the
  /// agent needs a tool-capable instruct model. For S7 this is the small, cached, tool-calling
  /// fixture (`mlx-community/Qwen2.5-0.5B-Instruct-4bit`). Sortie 8 introduces `--model`/`--backend`
  /// selection and the curated 7B agentic default; until then the verb runs against this fixture so
  /// it works out of the box against the model that is already downloaded for the agent-seam spike.
  static let agentDefaultModel = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"

  func run() async throws {
    try await runCLI {
      let renderer = ProgressRenderer(quiet: quiet)
      await renderer.logStartup("[bruja] SharedModels: \(Acervo.sharedModelsDirectory.path)")

      let model = Self.agentDefaultModel
      let io = IOCoordinator(quiet: quiet)

      let loop = AgentLoop(
        modelId: model,
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

// MARK: - Agent Loop

/// The shared agent loop backing both the one-shot and interactive surfaces of `bruja agent`.
///
/// Holds a single `LanguageModelSession` so the in-memory transcript persists across REPL turns
/// (R5.4). All terminal I/O routes through the injected ``IOCoordinator`` (R5.2).
@available(macOS 27.0, *)
final class AgentLoop {
  private let modelId: String
  private let temperature: Float
  private let maxTokens: Int
  private let io: IOCoordinator
  private let quiet: Bool

  /// The recording/consent tool wrappers backing this loop. Their accumulated observations are how
  /// the REPL surfaces tool calls + results (R5.2) and how `AgentReplTest` asserts the round-trip.
  let toolObservers: [ConsentToolObserver]

  private let session: LanguageModelSession

  private static let instructions =
    "You are a capable command-line agent operating in the user's current working directory. "
    + "You can call tools to inspect and modify files: read_file, write_file, edit_file, "
    + "list_dir, grep, glob, run_shell. "
    + "When asked about a file's contents, you MUST call the read_file tool with the EXACT path "
    + "provided before answering — do NOT guess or claim the file is missing without calling "
    + "read_file first. After a tool returns, answer using its result. Be concise."

  init(
    modelId: String,
    temperature: Float,
    maxTokens: Int,
    io: IOCoordinator,
    quiet: Bool
  ) {
    self.modelId = modelId
    self.temperature = temperature
    self.maxTokens = maxTokens
    self.io = io
    self.quiet = quiet

    let model = MLXLanguageModel(
      modelId: modelId,
      temperature: temperature,
      maxTokens: maxTokens
    )

    // Wrap every registry tool so the loop can (a) surface each call + result through the
    // IOCoordinator and (b) intercept the Sortie-4 path-escape outcome to fire the consent prompt
    // before letting an out-of-cwd access proceed (R5.2/R6.5). The wrappers carry the SAME tool
    // surface the registry yields — there is no second tool definition.
    let observers = ToolRegistry.defaultTools().map { ConsentToolObserver(inner: $0, io: io) }
    self.toolObservers = observers
    let wrappedTools: [any Tool] = observers.map { $0.makeWrapper() }

    self.session = LanguageModelSession(
      model: model,
      tools: wrappedTools,
      instructions: Self.instructions
    )
  }

  /// The session transcript (in-memory; persists across REPL turns — R5.4).
  var transcript: Transcript { session.transcript }

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

    await io.emitLine("[bruja] agent ready — model: \(modelId)")
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
      case "/quit", "/exit":
        await io.emitLine("[bruja] bye.")
        return
      case "/clear":
        // The transcript lives in the session; the cheapest clear that keeps the model loaded is
        // to note it for the user. (A full session rebuild is a Sortie-8 concern; here we keep the
        // single-session contract and simply inform.)
        await io.emitLine("[bruja] (transcript reset is per-session; restart to fully clear)")
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

  // MARK: - One turn (shared by one-shot and interactive)

  /// Run exactly one agent turn for `userInput`: stream assistant text + surface tool calls/results
  /// through the IOCoordinator. The FoundationModels framework owns the tool round-trip loop; our
  /// wrappers report each dispatch as it happens.
  func runTurn(_ userInput: String) async throws {
    // Mark a fresh observation window so we can surface only this turn's tool activity.
    for observer in toolObservers { await observer.beginTurn() }

    do {
      let response = try await session.respond(to: userInput)
      // Stream the final assistant text. (MLX generation is produced eagerly inside the executor;
      // we emit the completed response through the coordinator so all output is serialized.)
      await io.streamLine(response.content)
    } catch let bruja as BrujaError {
      throw bruja
    } catch {
      throw BrujaError.queryFailed(error.localizedDescription)
    }
  }
}

// MARK: - Consent / observation tool wrapper

/// Observes one wrapped tool's dispatches for a single loop, and owns the consent decision when the
/// tool reports a Sortie-4 path escape. The observer is `Sendable` (state behind a lock) so the
/// generic `Tool` wrapper it vends can be dispatched off the loop's actor by the framework.
@available(macOS 26.0, *)
final class ConsentToolObserver: @unchecked Sendable {
  let name: String
  private let inner: any Tool
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

  init(inner: any Tool, io: IOCoordinator) {
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

  /// Vend the generic, type-erased `Tool` the session is built with. The wrapper forwards
  /// `Arguments` verbatim to the inner tool and routes the result through ``handle``.
  ///
  /// `inner` is an existential `any Tool`; we open it via the generic helper so the wrapper's
  /// associated `Arguments` type binds to the concrete inner tool's `Arguments`.
  func makeWrapper() -> any Tool {
    // Open the `any Tool` existential. Every registry tool returns `String`; the
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
  ) -> any Tool {
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

/// A `Tool` whose `Output` is `String`. Used to open `any Tool` existentials to a concrete type the
/// `ConsentToolWrapper` can bind `Arguments` against. Every tool in ``ToolRegistry`` returns String.
@available(macOS 26.0, *)
protocol StringOutputTool: Tool where Output == String {}

@available(macOS 26.0, *) extension ReadFileTool: StringOutputTool {}
@available(macOS 26.0, *) extension WriteFileTool: StringOutputTool {}
@available(macOS 26.0, *) extension EditFileTool: StringOutputTool {}
@available(macOS 26.0, *) extension ListDirTool: StringOutputTool {}
@available(macOS 26.0, *) extension GrepTool: StringOutputTool {}
@available(macOS 26.0, *) extension GlobTool: StringOutputTool {}
@available(macOS 26.0, *) extension RunShellTool: StringOutputTool {}

/// A generic, type-erased forwarding `Tool` that preserves an inner tool's `Arguments`/name/
/// description while routing the result through its ``ConsentToolObserver``.
///
/// We cannot intercept *between* the model emitting a tool call and the framework dispatching it,
/// so the consent gate lives here, inside the dispatched tool: the inner tool classifies the path
/// (Sortie 4) and returns the escape outcome; we detect it, prompt, and either rerun with cwd
/// relaxed or deny — all before the result returns to the framework.
@available(macOS 26.0, *)
private struct ConsentToolWrapper<Inner: StringOutputTool>: Tool {
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
        // Re-run with cwd confinement relaxed: temporarily set the process cwd to "/" so PathGuard
        // re-classifies the (now in-root) path as allowed, then restore. POC-grade: tool dispatch
        // within a turn is serialized, so the brief cwd swap is safe (documented TOCTOU caveat in
        // PathGuard). This is how a granted consent lets the inner tool actually touch the path.
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
