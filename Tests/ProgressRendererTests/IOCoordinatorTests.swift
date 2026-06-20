import BrujaHelpers
import XCTest

// MARK: - In-Memory Test Doubles

/// An `OutputWriter` that records every written string in order.
///
/// All state is protected by an `NSLock` so it is safe to call from concurrent
/// tasks even though `OutputWriter` itself is `Sendable`.
final class RecordingOutputWriter: OutputWriter, @unchecked Sendable {
  private let lock = NSLock()
  private var _chunks: [String] = []
  private var _flushCount: Int = 0

  /// Every call to `write(_:)` appended in call order.
  var chunks: [String] {
    lock.withLock { _chunks }
  }

  /// Number of times `flush()` was called.
  var flushCount: Int {
    lock.withLock { _flushCount }
  }

  /// All chunks joined into a single string for easy assertion.
  var allOutput: String {
    chunks.joined()
  }

  func write(_ text: String) {
    lock.withLock { _chunks.append(text) }
  }

  func flush() {
    lock.withLock { _flushCount += 1 }
  }
}

/// A `LineReader` that returns scripted lines from a pre-loaded queue.
///
/// Thread-safe; safe to call from any concurrent context.
final class ScriptedLineReader: LineReader, @unchecked Sendable {
  private let lock = NSLock()
  private var _lines: [String]

  init(lines: [String]) {
    self._lines = lines
  }

  func readLine() -> String? {
    lock.withLock {
      guard !_lines.isEmpty else { return nil }
      return _lines.removeFirst()
    }
  }
}

// MARK: - IOCoordinatorTests

/// Unit tests for `IOCoordinator`.
///
/// All tests use injected `RecordingOutputWriter` and `ScriptedLineReader` — no real
/// TTY, no real stdin.  The core invariant exercised is:
///
///   *A prompt fired during a token stream must not interleave with the stream:*
///   *tokens flushed → prompt shown → input captured → buffered tokens drained.*
final class IOCoordinatorTests: XCTestCase {

  // MARK: - Basic Token Streaming

  /// Tokens emitted while NOT paused are written immediately to the output sink.
  func testStreamToken_WritesImmediatelyWhenNotPaused() async {
    let out = RecordingOutputWriter()
    let coordinator = IOCoordinator(
      output: out,
      input: ScriptedLineReader(lines: []),
      isTTY: false
    )

    await coordinator.streamToken("Hello")
    await coordinator.streamToken(", ")
    await coordinator.streamToken("world")

    XCTAssertEqual(out.allOutput, "Hello, world")
  }

  // MARK: - Core No-Interleave Invariant

  /// A prompt that fires concurrently with a token stream must not interleave:
  ///
  /// Expected write order:
  ///   token("A") → token("B") → [prompt pause] → token("C") buffered →
  ///   prompt question → [user input captured] → token("C") drained → token("D")
  ///
  /// The test proves ordering by checking that the question appears AFTER the
  /// pre-pause tokens and BEFORE any post-pause token output.
  func testPromptDuringStream_NoInterleaving() async throws {
    let out = RecordingOutputWriter()
    let reader = ScriptedLineReader(lines: ["y"])

    let coordinator = IOCoordinator(
      output: out,
      input: reader,
      isTTY: false  // non-TTY: no ANSI, no leading newline from the coordinator
    )

    // Phase 1: emit two tokens before the prompt fires.
    await coordinator.streamToken("token_A ")
    await coordinator.streamToken("token_B ")

    // Phase 2: fire the prompt AND emit a third token concurrently.
    //   - The prompt acquires the actor and sets isPaused = true first.
    //   - The concurrent streamToken for "token_C" must then buffer.
    //   - After promptUser returns, "token_C" is drained before "token_D".
    async let promptResponse = coordinator.promptUser("Allow?")
    // Give the prompt task a brief scheduling opportunity to acquire the actor
    // and set isPaused before we emit the concurrent token.
    try await Task.sleep(nanoseconds: 5_000_000)  // 5 ms
    await coordinator.streamToken("token_C ")
    let response = await promptResponse

    // Phase 3: emit a token after the prompt has returned.
    await coordinator.streamToken("token_D")

    // --- Assertions ---

    // 1. The response captured is the scripted "y".
    XCTAssertEqual(response, "y", "promptUser should return the scripted response")

    let allChunks = out.chunks
    let allText = out.allOutput

    // 2. Pre-pause tokens appear first.
    XCTAssertTrue(
      allText.hasPrefix("token_A "),
      "token_A must appear first; got: \(allText.debugDescription)"
    )

    // 3. The prompt question appears in the output (after pre-pause tokens).
    let promptIndex = allText.range(of: "Allow?")
    XCTAssertNotNil(promptIndex, "Prompt question must appear in output; got: \(allText.debugDescription)")

    // 4. token_B appears before the prompt question.
    let tokenBIndex = allText.range(of: "token_B ")
    let promptStart = promptIndex!.lowerBound
    if let tokenBStart = tokenBIndex?.lowerBound {
      XCTAssertLessThan(
        tokenBStart, promptStart,
        "token_B must appear before the prompt question"
      )
    } else {
      XCTFail("token_B not found in output: \(allText.debugDescription)")
    }

    // 5. token_C appears AFTER the prompt question (it was buffered during the pause).
    let tokenCIndex = allText.range(of: "token_C ")
    if let tokenCStart = tokenCIndex?.lowerBound {
      XCTAssertGreaterThan(
        tokenCStart, promptStart,
        "token_C must appear after the prompt question (was buffered during pause)"
      )
    } else {
      XCTFail("token_C not found in output: \(allText.debugDescription)")
    }

    // 6. token_D appears after token_C (post-prompt, normal streaming).
    let tokenDIndex = allText.range(of: "token_D")
    if let tokenCStart = tokenCIndex?.lowerBound, let tokenDStart = tokenDIndex?.lowerBound {
      XCTAssertLessThan(
        tokenCStart, tokenDStart,
        "token_C (buffered) must appear before token_D (post-prompt)"
      )
    } else if tokenDIndex == nil {
      XCTFail("token_D not found in output: \(allText.debugDescription)")
    }

    // 7. Verify write order via the raw chunks array:
    //    chunks must include "token_A ", "token_B " before any chunk containing "Allow?"
    let promptChunkIndex = allChunks.firstIndex(where: { $0.contains("Allow?") })
    let tokenAChunkIndex = allChunks.firstIndex(where: { $0.contains("token_A") })
    let tokenBChunkIndex = allChunks.firstIndex(where: { $0.contains("token_B") })
    let tokenCChunkIndex = allChunks.firstIndex(where: { $0.contains("token_C") })

    if let pi = promptChunkIndex, let ai = tokenAChunkIndex, let bi = tokenBChunkIndex {
      XCTAssertLessThan(ai, pi, "token_A chunk must precede the prompt chunk")
      XCTAssertLessThan(bi, pi, "token_B chunk must precede the prompt chunk")
    }
    if let pi = promptChunkIndex, let ci = tokenCChunkIndex {
      XCTAssertGreaterThan(ci, pi, "token_C chunk must follow the prompt chunk")
    }
  }

  // MARK: - Flush Before Prompt

  /// `promptUser` calls `flush()` on the output writer before writing the question.
  func testPromptUser_FlushesBeforePrompt() async {
    let out = RecordingOutputWriter()
    let coordinator = IOCoordinator(
      output: out,
      input: ScriptedLineReader(lines: ["n"]),
      isTTY: false
    )

    await coordinator.streamToken("partial token")
    let flushCountBefore = out.flushCount

    _ = await coordinator.promptUser("Question?")

    // flush() is called at least once before the question (and once after resume).
    XCTAssertGreaterThan(
      out.flushCount, flushCountBefore,
      "flush() must be called at least once by promptUser"
    )
    XCTAssertTrue(
      out.allOutput.contains("Question?"),
      "Prompt question must appear in output"
    )
  }

  // MARK: - TTY vs Non-TTY Prompt Formatting

  /// In TTY mode, `promptUser` prepends a newline to move the cursor off the token line.
  func testTTYMode_PrependNewlineBeforePrompt() async {
    let out = RecordingOutputWriter()
    let coordinator = IOCoordinator(
      output: out,
      input: ScriptedLineReader(lines: ["y"]),
      isTTY: true
    )

    await coordinator.streamToken("some token")
    _ = await coordinator.promptUser("Proceed?")

    // In TTY mode a "\n" must appear between the last token and the prompt.
    let text = out.allOutput
    let newlineIndex = text.range(of: "\n")
    let promptIndex = text.range(of: "Proceed?")

    XCTAssertNotNil(newlineIndex, "TTY mode must emit a newline before the prompt")
    if let ni = newlineIndex?.lowerBound, let pi = promptIndex?.lowerBound {
      XCTAssertLessThan(ni, pi, "The newline must appear before the prompt text")
    }
  }

  /// In non-TTY mode, `promptUser` does NOT prepend a leading newline.
  func testNonTTYMode_NoLeadingNewlineBeforePrompt() async {
    let out = RecordingOutputWriter()
    let coordinator = IOCoordinator(
      output: out,
      input: ScriptedLineReader(lines: ["y"]),
      isTTY: false
    )

    _ = await coordinator.promptUser("Proceed?")

    // Non-TTY: output must start directly with the prompt text (no leading \n).
    XCTAssertTrue(
      out.allOutput.hasPrefix("Proceed?"),
      "Non-TTY output must start with the prompt text; got: \(out.allOutput.debugDescription)"
    )
  }

  // MARK: - EOF Handling

  /// When the `LineReader` returns `nil` (EOF), `promptUser` returns `nil`.
  func testPromptUser_ReturnsNilOnEOF() async {
    let coordinator = IOCoordinator(
      output: RecordingOutputWriter(),
      input: ScriptedLineReader(lines: []),  // empty → EOF immediately
      isTTY: false
    )

    let result = await coordinator.promptUser("Question?")
    XCTAssertNil(result, "promptUser must return nil when the LineReader reaches EOF")
  }

  // MARK: - Response Trimming

  /// `promptUser` trims surrounding whitespace/newlines from the captured line.
  func testPromptUser_TrimsResponse() async {
    let coordinator = IOCoordinator(
      output: RecordingOutputWriter(),
      input: ScriptedLineReader(lines: ["  yes  "]),
      isTTY: false
    )

    let result = await coordinator.promptUser("Q?")
    XCTAssertEqual(result, "yes", "promptUser must trim surrounding whitespace from the response")
  }

  // MARK: - Path Escape Consent (R6.5)

  /// Consent granted when the user responds "y".
  func testRequestPathEscapeConsent_GrantedOnY() async {
    let coordinator = IOCoordinator(
      output: RecordingOutputWriter(),
      input: ScriptedLineReader(lines: ["y"]),
      isTTY: false
    )

    let granted = await coordinator.requestPathEscapeConsent(
      operation: "read_file",
      resolvedPath: "/etc/passwd"
    )
    XCTAssertTrue(granted, "Consent should be granted for 'y'")
  }

  /// Consent granted when the user responds "yes" (case-insensitive).
  func testRequestPathEscapeConsent_GrantedOnYes() async {
    let coordinator = IOCoordinator(
      output: RecordingOutputWriter(),
      input: ScriptedLineReader(lines: ["YES"]),
      isTTY: false
    )

    let granted = await coordinator.requestPathEscapeConsent(
      operation: "write_file",
      resolvedPath: "/tmp/out.txt"
    )
    XCTAssertTrue(granted, "Consent should be granted for 'YES' (case-insensitive)")
  }

  /// Consent denied when the user responds "n".
  func testRequestPathEscapeConsent_DeniedOnN() async {
    let coordinator = IOCoordinator(
      output: RecordingOutputWriter(),
      input: ScriptedLineReader(lines: ["n"]),
      isTTY: false
    )

    let granted = await coordinator.requestPathEscapeConsent(
      operation: "edit_file",
      resolvedPath: "/etc/hosts"
    )
    XCTAssertFalse(granted, "Consent should be denied for 'n'")
  }

  /// Consent denied on EOF.
  func testRequestPathEscapeConsent_DeniedOnEOF() async {
    let coordinator = IOCoordinator(
      output: RecordingOutputWriter(),
      input: ScriptedLineReader(lines: []),
      isTTY: false
    )

    let granted = await coordinator.requestPathEscapeConsent(
      operation: "list_dir",
      resolvedPath: "/etc"
    )
    XCTAssertFalse(granted, "Consent should be denied on EOF")
  }

  // MARK: - Buffer Drains in Order

  /// Multiple tokens buffered during a pause are drained in the correct order.
  func testMultipleTokensBufferedAndDrainedInOrder() async throws {
    let out = RecordingOutputWriter()
    let coordinator = IOCoordinator(
      output: out,
      input: ScriptedLineReader(lines: ["y"]),
      isTTY: false
    )

    // Start the prompt (which sets isPaused = true on first actor turn).
    async let prompt = coordinator.promptUser("Q?")

    // Allow the prompt to acquire the actor and set isPaused before we buffer tokens.
    try await Task.sleep(nanoseconds: 5_000_000)

    // Buffer several tokens in order while paused.
    await coordinator.streamToken("X")
    await coordinator.streamToken("Y")
    await coordinator.streamToken("Z")

    // Await the prompt to complete (drains X, Y, Z after the prompt question).
    _ = await prompt

    let text = out.allOutput
    let promptIdx = text.range(of: "Q?")!.lowerBound
    let xIdx = text.range(of: "X")!.lowerBound
    let yIdx = text.range(of: "Y")!.lowerBound
    let zIdx = text.range(of: "Z")!.lowerBound

    XCTAssertLessThan(promptIdx, xIdx, "X must appear after the prompt")
    XCTAssertLessThan(xIdx, yIdx, "X must appear before Y")
    XCTAssertLessThan(yIdx, zIdx, "Y must appear before Z")
  }

  // MARK: - flushOutput

  /// `flushOutput` calls `flush()` on the underlying writer.
  func testFlushOutput_CallsFlush() async {
    let out = RecordingOutputWriter()
    let coordinator = IOCoordinator(
      output: out,
      input: ScriptedLineReader(lines: []),
      isTTY: false
    )

    let before = out.flushCount
    await coordinator.flushOutput()
    XCTAssertEqual(out.flushCount, before + 1, "flushOutput must call flush() exactly once")
  }
}
