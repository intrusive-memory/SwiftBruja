import Darwin
import Foundation

// MARK: - I/O Abstraction Protocols

/// A sink for writing text output (tokens, prompts, etc.).
///
/// The production implementation writes to real stdout; test implementations
/// capture output into an in-memory buffer so no real TTY is required.
public protocol OutputWriter: Sendable {
  /// Write `text` to the output destination, flushing immediately.
  func write(_ text: String)
  /// Flush any pending buffered output.
  func flush()
}

/// A source for reading a single line of user input.
///
/// The production implementation reads from real stdin via `readLine(strippingNewline:)`;
/// test implementations return scripted lines from an in-memory queue.
public protocol LineReader: Sendable {
  /// Read and return the next line of input, or `nil` on EOF.
  ///
  /// This call MUST block (or appear to block) until input is available so
  /// the coordinator can use it as a synchronization point.
  func readLine() -> String?
}

// MARK: - Production Implementations

/// `OutputWriter` that writes to real stdout, flushing with `fflush(stdout)`.
public struct StandardOutputWriter: OutputWriter {
  public init() {}

  public func write(_ text: String) {
    print(text, terminator: "")
    fflush(stdout)
  }

  public func flush() {
    fflush(stdout)
  }
}

/// `LineReader` that reads from real stdin via Swift's `readLine(strippingNewline:)`.
public struct StandardLineReader: LineReader {
  public init() {}

  public func readLine() -> String? {
    Swift.readLine(strippingNewline: true)
  }
}

// MARK: - IOCoordinator

/// Serializes all terminal I/O for the `bruja agent` REPL.
///
/// A single shared `IOCoordinator` is the **only** path to stdout/stdin in the agent
/// loop. All three sources of I/O — streamed token output, `ProgressRenderer` progress
/// updates, and path-escape consent prompts — acquire the coordinator's serialization
/// guarantees before writing.
///
/// ## Pause / flush / prompt / resume primitive (R6.5)
///
/// When a path-escape consent prompt fires *inside* a tool handler while tokens may
/// still be streaming, the coordinator:
/// 1. Pauses further token emission (tokens sent during the pause are buffered).
/// 2. Flushes any tokens already written to the output sink.
/// 3. Presents the consent question to the user on a fresh line.
/// 4. Captures the user's response with a blocking `readLine`.
/// 5. Resumes normal token emission, draining the buffer first.
///
/// This guarantees the prompt and the token stream never interleave.
///
/// ## Relationship to `ProgressRenderer`
///
/// `IOCoordinator` does **not** re-implement `ProgressRenderer`'s TTY/non-TTY logic.
/// Instead, it exposes `streamToken(_:)` for token-by-token output (which respects the
/// pause/resume gate) and delegates progress-specific formatting concerns to the
/// `ProgressRenderer` you pass at init. Callers that previously wrote directly to
/// stdout via `ProgressRenderer` now route those calls through the coordinator so the
/// same serialization applies.
///
/// ## Actor isolation
///
/// `IOCoordinator` is a Swift `actor`. All state mutation is actor-isolated. The
/// blocking `readLine` call is wrapped in a `Task.detached` + continuation bridge so it
/// does not stall the actor's executor.
///
/// ## Thread / task safety
///
/// Token streams are expected to `await streamToken(_:)` from one `Task`; the prompt
/// may fire from a different `Task` (the tool handler). The actor serializes both, so
/// there is no race: either the prompt wins the actor and pauses the stream, or the
/// token wins and completes before the prompt acquires the lock.
public actor IOCoordinator {

  // MARK: - Dependencies

  /// Destination for all text output (tokens, prompts).
  private let output: any OutputWriter

  /// Source for interactive user input.
  private let input: any LineReader

  /// Whether stdout is a real TTY (forwarded from `ProgressRenderer` TTY detection).
  ///
  /// Stored here so prompt formatting can vary (TTY gets a newline-prefixed prompt;
  /// non-TTY emits a plain newline-terminated prompt line that is safe for log files
  /// and CI output capture).
  public let isTTY: Bool

  // MARK: - Streaming state

  /// When `true`, `streamToken(_:)` buffers tokens rather than writing them immediately.
  private var isPaused: Bool = false

  /// Tokens buffered while a prompt is in progress.
  private var tokenBuffer: [String] = []

  // MARK: - Initialisation

  /// Creates a coordinator backed by real stdin/stdout, auto-detecting TTY via
  /// `ProgressRenderer`'s TIOCGWINSZ logic.
  ///
  /// - Parameter quiet: Forwarded to the embedded `ProgressRenderer` to suppress
  ///   progress output in quiet mode. Token streaming and prompts are **not** affected
  ///   by `quiet` — only `ProgressRenderer` progress calls respect it.
  public init(quiet: Bool = false) {
    self.output = StandardOutputWriter()
    self.input = StandardLineReader()
    // Reuse ProgressRenderer's TTY detection (TIOCGWINSZ). We do NOT create the
    // ProgressRenderer here because it's an actor and we cannot await inside init.
    // Instead, copy the same TIOCGWINSZ logic inline (single source of truth lives
    // in ProgressRenderer.swift; this call is deliberately the same idiom).
    var windowSize = winsize()
    let ioctlResult = ioctl(STDOUT_FILENO, TIOCGWINSZ, &windowSize)
    self.isTTY = (ioctlResult == 0 && windowSize.ws_col > 0)
  }

  /// Creates a coordinator with explicit TTY override and injected I/O.
  ///
  /// This initialiser is for **testing** — it lets tests supply an in-memory
  /// `OutputWriter` and `LineReader` without a real terminal.
  ///
  /// - Parameters:
  ///   - output: The output sink (tokens + prompts).
  ///   - input: The line reader (interactive user input).
  ///   - isTTY: Whether to treat the output as a TTY (affects prompt formatting).
  public init(output: any OutputWriter, input: any LineReader, isTTY: Bool) {
    self.output = output
    self.input = input
    self.isTTY = isTTY
  }

  // MARK: - Token Streaming

  /// Emit a single token to the output sink.
  ///
  /// If a prompt is currently in progress (`isPaused == true`), the token is
  /// appended to `tokenBuffer` and will be flushed once `promptUser` returns.
  /// Otherwise the token is written to the output sink immediately.
  ///
  /// - Parameter token: The text token to emit (may be a word, sub-word, or character).
  public func streamToken(_ token: String) {
    if isPaused {
      tokenBuffer.append(token)
    } else {
      output.write(token)
    }
  }

  /// Flush any pending output to the sink.
  ///
  /// Call this after all tokens in a generation turn have been emitted so
  /// the terminal is up to date before presenting a prompt.
  public func flushOutput() {
    output.flush()
  }

  // MARK: - Prompt / Pause / Resume

  /// Present `question` to the user, capturing their response.
  ///
  /// This is the **pause/flush/prompt/resume** primitive (R6.5):
  ///
  /// 1. **Pause** — sets `isPaused = true` so concurrent `streamToken(_:)` calls
  ///    buffer rather than write.
  /// 2. **Flush** — drains the output sink so no half-written token line is visible.
  /// 3. **Newline** — if the cursor is mid-line (TTY path after in-line token output),
  ///    emits a newline to put the prompt on its own line.
  /// 4. **Prompt** — writes `question` followed by a space so the user types on the
  ///    same line (TTY) or on a clearly labelled line (non-TTY).
  /// 5. **Read** — calls `input.readLine()` to capture the user's input.
  /// 6. **Resume** — sets `isPaused = false` and drains `tokenBuffer` to the sink.
  ///
  /// The blocking `readLine` is dispatched to a detached thread so the actor
  /// executor is not stalled.
  ///
  /// - Parameter question: The prompt text shown to the user.
  /// - Returns: The trimmed line entered by the user, or `nil` if EOF was reached.
  public func promptUser(_ question: String) async -> String? {
    // 1. Pause streaming so concurrent streamToken calls buffer.
    isPaused = true

    // 2. Flush any output already written to the sink.
    output.flush()

    // 3. Emit a newline if we're mid-line (TTY), then the prompt.
    if isTTY {
      output.write("\n")
    }
    output.write("\(question) ")
    output.flush()

    // 4. Perform the blocking readLine off the actor executor so we don't stall it.
    //    We capture `input` before crossing the isolation boundary.
    let lineReader = self.input
    let response = await withCheckedContinuation {
      (continuation: CheckedContinuation<String?, Never>) in
      Task.detached {
        let line = lineReader.readLine()
        continuation.resume(returning: line)
      }
    }

    // 5. Resume: drain the token buffer in order.
    isPaused = false
    for buffered in tokenBuffer {
      output.write(buffered)
    }
    tokenBuffer.removeAll(keepingCapacity: true)
    output.flush()

    return response?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Line helpers (S7 REPL convenience)

  /// Emit `text` followed by a newline, respecting the pause/resume gate.
  ///
  /// Used by the agent REPL for status lines, tool-call/result echoes, and the final assistant
  /// response. Routing these through the coordinator keeps them serialized with token streaming and
  /// consent prompts so output never interleaves.
  public func emitLine(_ text: String) {
    streamToken(text + "\n")
    flushOutput()
  }

  /// Emit `text` as a streamed line (same as ``emitLine(_:)`` today; named separately so the agent
  /// loop can later swap in token-by-token streaming without touching call sites).
  public func streamLine(_ text: String) {
    streamToken(text + "\n")
    flushOutput()
  }

  /// Present a one-line prompt (e.g. `>`) and return the user's trimmed input, or `nil` on EOF.
  public func prompt(_ label: String) async -> String? {
    await promptUser(label)
  }

  // MARK: - Path-Escape Consent (R6.5)

  /// Ask the user for explicit consent to allow a tool to access a path outside
  /// the working directory.
  ///
  /// This is the concrete consent-prompt called by the tool-escape flow (S4 raised
  /// `ToolResult.escapeRequested`; the REPL loop in S7 will call this). Presents
  /// the canonical consent question and returns `true` if the user confirms with
  /// "y" or "yes" (case-insensitive).
  ///
  /// - Parameters:
  ///   - operation: The tool that triggered the escape (e.g. `read_file`).
  ///   - resolvedPath: The canonicalized path outside the cwd.
  /// - Returns: `true` when the user grants consent; `false` on denial or EOF.
  public func requestPathEscapeConsent(operation: String, resolvedPath: String) async -> Bool {
    let question =
      "[bruja] \(operation) wants to access a path outside the working directory:\n"
      + "  \(resolvedPath)\n"
      + "Allow? (y/N)"
    guard let response = await promptUser(question) else { return false }
    let normalized = response.lowercased()
    return normalized == "y" || normalized == "yes"
  }
}
