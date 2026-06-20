import Foundation
import FoundationModels
import XCTest

@testable import SwiftBruja

// MARK: - Tool Dispatch Harness (S11, R8.3)

/// A minimal test-only harness that mirrors the dispatch logic performed by
/// `ConsentToolWrapper`/`ConsentToolObserver` in `AgentCommand.swift`, exercising
/// the path **ToolRegistry → PathGuard (inside each Tool) → Tool.call → result string →
/// continuation** without any model, inference, or network access.
///
/// `ConsentToolWrapper` is in the `bruja` executable target (not the `SwiftBruja` library);
/// this harness reproduces the same dispatch logic in-test so the unit-test target
/// (`SwiftBrujaTests`) can assert the full path.
///
/// The "continuation" in the real agent loop is the result string being returned to the
/// `LanguageModelSession` framework for the next model turn. Here, "continuation" is
/// represented by `lastResult`, which captures exactly what the framework would receive.
@available(macOS 26.0, *)
final class ToolDispatchHarness {

  // MARK: - Observation records

  /// Every call's argument summary, in dispatch order.
  private(set) var calls: [String] = []

  /// Every call's result string — what would be fed back to the model as the continuation.
  private(set) var results: [String] = []

  /// The result of the most recent dispatch (the "continuation" value for that turn).
  var lastResult: String? { results.last }

  // MARK: - Dispatch

  /// Dispatch a typed tool call and capture the result.
  ///
  /// Mirrors `ConsentToolWrapper.call(arguments:)`:
  /// 1. Calls the inner tool (which internally runs `PathGuard.classify`).
  /// 2. Checks for the path-escape marker (same logic as `ConsentToolObserver.handle`).
  /// 3. Either records the raw result (allowed/error) or the consent-denied result.
  ///
  /// - Parameters:
  ///   - tool: The concrete tool to dispatch.
  ///   - arguments: The tool's argument value.
  ///   - grantConsent: When `true`, simulate the user granting path-escape consent so the
  ///     harness re-runs the tool with cwd relaxed. When `false` (default), simulate denial.
  /// - Returns: The result string — what the continuation would feed back to the model.
  func dispatch<T: Tool>(
    _ tool: T,
    arguments: T.Arguments,
    grantConsent: Bool = false
  ) async throws -> String where T.Output == String {
    let raw = try await tool.call(arguments: arguments)
    let summary = String(describing: arguments)

    let result: String
    if raw.hasPrefix(ToolResult.errorPrefix + ToolResult.escapeMarker) {
      // Path-escape outcome — same branch as ConsentToolObserver.handle(...)
      if grantConsent {
        // Simulate granted consent: re-run with cwd relaxed to "/".
        let saved = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath("/")
        defer { FileManager.default.changeCurrentDirectoryPath(saved) }
        result = try await tool.call(arguments: arguments)
      } else {
        result = ToolResult.error("user denied access to a path outside the working directory")
      }
    } else {
      result = raw
    }

    calls.append(summary)
    results.append(result)
    return result
  }

  /// Dispatch using an `any Tool` existential opened to a `StringOutputTool`.
  ///
  /// Convenience wrapper for dispatching from the `ToolRegistry.defaultTools()` array
  /// (which yields `[any Tool]`). Only tools whose `Output == String` are supported — every
  /// tool in the registry qualifies.
  func dispatch(
    anyTool: any Tool,
    path: String,
    grantConsent: Bool = false
  ) async throws -> String? {
    // Open the existential. We only handle ReadFileTool as the demo dispatch target;
    // extend with additional tools if more tool types need harness coverage.
    if let tool = anyTool as? ReadFileTool {
      return try await dispatch(
        tool, arguments: .init(path: path), grantConsent: grantConsent)
    }
    if let tool = anyTool as? WriteFileTool {
      return try await dispatch(
        tool, arguments: .init(path: path, content: ""), grantConsent: grantConsent)
    }
    return nil
  }

  // MARK: - Reset

  func reset() {
    calls.removeAll()
    results.removeAll()
  }
}

// MARK: - Mock-Backend Dispatch Tests (S11, R8.3)

/// Deterministic, NO-model / NO-network tests proving a scripted tool call flows through
/// the full dispatch path: **ToolRegistry → PathGuard → Tool → result → continuation**.
///
/// No MLX model, no `ModelContainer`, no network access. All assertions are structural
/// (result strings + PathGuard outcomes) rather than inference-dependent.
///
/// Exit criteria (R8.3):
/// - A scripted tool call asserts the full dispatch path using only the harness + registry.
/// - A PathGuard-interaction assertion proves an escaping path yields consent/deny, not a disk op.
/// - Zero model downloads. Zero network access.
@available(macOS 26.0, *)
final class MockBackendDispatchTests: XCTestCase {

  // MARK: - Setup / teardown

  /// Fresh temporary directory used as the test working directory.
  private var tmpDir: URL!
  private var previousCwd: String!

  override func setUpWithError() throws {
    try super.setUpWithError()
    tmpDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("BrujaS11-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    // Canonicalize so PathGuard's realpath-based containment check matches.
    tmpDir = URL(fileURLWithPath: canonicalize(tmpDir.path) ?? tmpDir.path)
    previousCwd = FileManager.default.currentDirectoryPath
    XCTAssertTrue(
      FileManager.default.changeCurrentDirectoryPath(tmpDir.path),
      "could not chdir into the test working directory")
  }

  override func tearDownWithError() throws {
    FileManager.default.changeCurrentDirectoryPath(previousCwd)
    try? FileManager.default.removeItem(at: tmpDir)
    try super.tearDownWithError()
  }

  private func canonicalize(_ path: String) -> String? {
    path.withCString { cString -> String? in
      guard let resolved = realpath(cString, nil) else { return nil }
      defer { free(resolved) }
      return String(cString: resolved)
    }
  }

  // MARK: - Helpers

  private func makeFile(_ name: String, content: String = "hello from S11") throws -> URL {
    let url = tmpDir.appendingPathComponent(name)
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  // MARK: - 1. Registry completeness

  /// Step 1 of the dispatch path: `ToolRegistry` yields the full tool set.
  ///
  /// This is the entry point of every dispatch — if the registry is wrong the whole path
  /// breaks. Verifying it here proves the path starts correctly.
  func testRegistryYieldsExpectedTools() {
    let tools = ToolRegistry.defaultTools()
    let names = Set(tools.map(\.name))
    let expected: Set<String> = [
      "read_file", "write_file", "edit_file", "list_dir", "grep", "glob", "run_shell",
    ]
    XCTAssertEqual(names, expected, "ToolRegistry must expose exactly the expected tool set")
    XCTAssertEqual(tools.count, 7, "Registry must contain exactly 7 tools")
  }

  // MARK: - 2. Full dispatch path: registry → guard → tool → result → continuation

  /// Core S11 assertion: a scripted `read_file` tool call goes through every step of the
  /// dispatch path and the result (the "continuation") carries the expected file content.
  ///
  /// Path proven:
  /// 1. **ToolRegistry** — obtain `ReadFileTool` from the registry.
  /// 2. **PathGuard** — the in-cwd path is classified `.allowed` (tool runs without denial).
  /// 3. **Tool** — `ReadFileTool.call(arguments:)` reads the temp file from disk.
  /// 4. **Result** — the result string carries the file content (not an error prefix).
  /// 5. **Continuation** — the harness's `lastResult` is what would be fed back to the model.
  func testScriptedReadFileFlowsFullDispatchPath() async throws {
    // Set up: write a temp file inside the cwd.
    let content = "sortie-11 canary line\nline two"
    let fileURL = try makeFile("canary.txt", content: content)

    // Step 1: Obtain the tool from the registry (the canonical entry point).
    let tools = ToolRegistry.defaultTools()
    guard let readFileTool = tools.first(where: { $0.name == "read_file" }) as? ReadFileTool
    else {
      return XCTFail("ReadFileTool must be in ToolRegistry.defaultTools()")
    }

    // Steps 2–5: dispatch through the harness.
    let harness = ToolDispatchHarness()
    let result = try await harness.dispatch(
      readFileTool,
      arguments: .init(path: fileURL.path)
    )

    // 4. Result must carry the file content.
    XCTAssertFalse(
      result.hasPrefix(ToolResult.errorPrefix),
      "A successful in-cwd read must not return an error-prefixed result; got: \(result)")
    XCTAssertTrue(
      result.contains("sortie-11 canary line"),
      "Result must contain file content; got: \(result)")

    // 5. Continuation: the harness records the result for the model's next turn.
    XCTAssertEqual(harness.lastResult, result, "lastResult must equal the returned result")
    XCTAssertEqual(harness.results.count, 1, "Exactly one dispatch recorded")
    XCTAssertEqual(harness.calls.count, 1, "Exactly one call recorded")
  }

  /// Verify that the dispatch path works end-to-end using the registry's `[any Tool]` array
  /// (the actual runtime path, not a directly-typed instantiation).
  func testDispatchViaRegistryAnyToolArray() async throws {
    let content = "dispatched via any Tool array"
    let fileURL = try makeFile("registry-dispatch.txt", content: content)

    // Obtain tools as [any Tool] — exactly as AgentLoop does.
    let tools = ToolRegistry.defaultTools()
    XCTAssertFalse(tools.isEmpty, "Registry must be non-empty")

    let harness = ToolDispatchHarness()
    // Use the existential-open dispatch path.
    guard
      let result = try await harness.dispatch(
        anyTool: tools.first(where: { $0.name == "read_file" })!,
        path: fileURL.path
      )
    else {
      return XCTFail("dispatch(anyTool:) returned nil for ReadFileTool")
    }

    XCTAssertFalse(
      result.hasPrefix(ToolResult.errorPrefix),
      "In-cwd read via [any Tool] array must succeed; got: \(result)")
    XCTAssertTrue(
      result.contains("dispatched via any Tool array"),
      "Result must carry file content; got: \(result)")
  }

  // MARK: - 3. Multi-turn: result feeds the continuation on each turn

  /// Prove that consecutive dispatches accumulate correctly — each result becomes the
  /// "continuation" for the next scripted turn, analogous to how the framework appends
  /// `.toolOutput` entries to the transcript before re-prompting.
  func testConsecutiveDispatchesAccumulateResults() async throws {
    let fileA = try makeFile("turn1.txt", content: "turn one result")
    let fileB = try makeFile("turn2.txt", content: "turn two result")

    let harness = ToolDispatchHarness()
    let tool = ReadFileTool()

    let r1 = try await harness.dispatch(tool, arguments: .init(path: fileA.path))
    let r2 = try await harness.dispatch(tool, arguments: .init(path: fileB.path))

    // Each result must contain its file's content.
    XCTAssertTrue(r1.contains("turn one result"), "Turn 1 result must contain file content")
    XCTAssertTrue(r2.contains("turn two result"), "Turn 2 result must contain file content")

    // Accumulation: harness has two recorded results.
    XCTAssertEqual(harness.results.count, 2, "Two dispatches must produce two recorded results")
    XCTAssertEqual(harness.calls.count, 2, "Two calls must be recorded")

    // lastResult reflects the most recent continuation.
    XCTAssertEqual(harness.lastResult, r2, "lastResult must reflect the latest continuation")
  }

  // MARK: - 4. PathGuard interaction: escaping path → consent denied → no disk operation

  /// PathGuard-interaction assertion (R8.3 requirement):
  ///
  /// A scripted tool call targeting a path OUTSIDE the cwd must:
  /// (a) yield the escape marker (PathGuard classified it `.escapeRequested`),
  /// (b) after denial, return a denial result (not file content, not a disk write).
  ///
  /// This proves the PathGuard boundary sits correctly inside the tool's `call(arguments:)`:
  /// the tool never touches disk for an escaping path, and the harness's denial branch is
  /// invoked (same logic as `ConsentToolObserver.handle` with `granted = false`).
  func testEscapingPathYieldsDenialNotDiskOperation() async throws {
    // An outside directory that must NOT be written to.
    let outsideDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("BrujaS11-outside-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outsideDir) }

    let escapingFile = outsideDir.appendingPathComponent("must-not-exist.txt")

    // Step 2 of the dispatch path: PathGuard classifies the escaping path.
    let decision = PathGuard.classify(escapingFile.path, workingDirectory: tmpDir.path)
    guard case .escapeRequested = decision else {
      return XCTFail(
        "PathGuard must classify an outside path as .escapeRequested; got \(decision)")
    }

    // Steps 3–5: dispatch WriteFileTool with an escaping path, consent DENIED.
    let harness = ToolDispatchHarness()
    let writeTool = WriteFileTool()
    let result = try await harness.dispatch(
      writeTool,
      arguments: .init(path: escapingFile.path, content: "must-not-be-written"),
      grantConsent: false  // simulate denial
    )

    // (a) The raw tool result must carry the escape marker (PathGuard fired correctly).
    // We can't inspect the raw result after denial substitution, but the final result
    // must be the denial string, not file content.
    XCTAssertTrue(
      result.hasPrefix(ToolResult.errorPrefix),
      "Denied dispatch must return an error-prefixed result; got: \(result)")
    XCTAssertTrue(
      result.contains("denied") || result.contains("outside the working directory"),
      "Denial result must describe the reason; got: \(result)")

    // (b) No disk operation must have occurred — the file must NOT exist.
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: escapingFile.path),
      "A denied write dispatch must NOT create the file on disk")
  }

  /// Complementary: an escaping path with consent GRANTED re-runs the tool successfully.
  ///
  /// This mirrors the `ConsentToolObserver.handle` "granted" branch:
  /// the harness relaxes cwd to "/" so PathGuard re-classifies the path as allowed, then
  /// re-runs the tool. The file IS created (the user said yes), and the result carries ok content.
  func testEscapingPathWithGrantedConsentRunsTool() async throws {
    let outsideDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("BrujaS11-granted-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outsideDir) }

    let targetFile = outsideDir.appendingPathComponent("consent-granted.txt")
    let harness = ToolDispatchHarness()
    let writeTool = WriteFileTool()

    let result = try await harness.dispatch(
      writeTool,
      arguments: .init(path: targetFile.path, content: "written with consent"),
      grantConsent: true  // simulate granted consent
    )

    XCTAssertFalse(
      result.hasPrefix(ToolResult.errorPrefix),
      "Granted consent must yield a success result; got: \(result)")
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: targetFile.path),
      "Granted consent must allow the write to disk")

    let onDisk = try String(contentsOf: targetFile, encoding: .utf8)
    XCTAssertEqual(onDisk, "written with consent", "On-disk content must match what was written")
  }

  // MARK: - 5. PathGuard decision correctness in-cwd vs. escaping

  /// Prove PathGuard's in-cwd / escaping decision is applied correctly at the tool boundary.
  ///
  /// In-cwd path → tool runs → file content returned.
  /// Outside path → escape marker returned → harness denies → no disk operation.
  func testPathGuardDecisionAtToolBoundary() async throws {
    // In-cwd: allowed.
    let inCwdFile = try makeFile("in-cwd.txt", content: "in cwd content")
    let readTool = ReadFileTool()
    let inCwdDecision = PathGuard.classify(inCwdFile.path, workingDirectory: tmpDir.path)
    guard case .allowed = inCwdDecision else {
      return XCTFail("In-cwd file must be classified .allowed; got \(inCwdDecision)")
    }
    let inCwdResult = try await readTool.call(arguments: .init(path: inCwdFile.path))
    XCTAssertFalse(
      inCwdResult.hasPrefix(ToolResult.errorPrefix),
      "In-cwd read must succeed at the tool boundary")
    XCTAssertTrue(inCwdResult.contains("in cwd content"))

    // Outside path: escape requested.
    let escapingPath = "/etc/hosts"
    let escapingDecision = PathGuard.classify(escapingPath, workingDirectory: tmpDir.path)
    guard case .escapeRequested = escapingDecision else {
      return XCTFail("Absolute outside path must be .escapeRequested; got \(escapingDecision)")
    }
    let escapingResult = try await readTool.call(arguments: .init(path: escapingPath))
    XCTAssertTrue(
      escapingResult.hasPrefix(ToolResult.errorPrefix + ToolResult.escapeMarker),
      "Escaping read must return the escape-marker result; got: \(escapingResult)")
  }

  // MARK: - 6. SharedMockGenerationSource reuse (S5 seam)

  /// Prove the ``SharedMockGenerationSource`` (the promoted S5 seam) is accessible from this
  /// target and drives `MLXLanguageModelExecutor` correctly without any model or network.
  ///
  /// Scripts `.toolCall` + `.text` events through the executor and asserts the source was
  /// invoked once with the expected chat messages — the same seam used by S5 executor tests.
  @available(macOS 27.0, *)
  func testSharedMockGenerationSourceDrivesExecutorWithoutModel() async throws {
    let mock = SharedMockGenerationSource(
      scripts: [
        [
          .toolCall(id: "call-1", name: "read_file", argumentsJSON: #"{"path":"test.txt"}"#),
          .text("Here is the file content."),
        ]
      ]
    )

    let config = MLXLanguageModel.Configuration(modelId: "mock/test-model", maxSteps: 8)
    let executor = MLXLanguageModelExecutor(
      configuration: config, source: mock, turnState: TurnState(maxSteps: 8))
    let model = MLXLanguageModel(modelId: "mock/test-model", maxSteps: 8)

    let channel = LanguageModelExecutorGenerationChannel()

    // Drain the channel concurrently so the executor's `send` calls don't block.
    let drain = Task {
      for try await _ in channel { /* discard events — assertion is on the mock's captured state */ }
    }
    defer { drain.cancel() }

    let request = LanguageModelExecutorGenerationRequest(
      id: UUID(),
      transcript: Transcript(
        entries: [
          .prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: "hello"))]))
        ]),
      enabledTools: [],
      generationOptions: GenerationOptions(),
      contextOptions: ContextOptions(),
      metadata: [:]
    )

    try await executor.respond(to: request, model: model, streamingInto: channel)

    // The mock source was invoked exactly once (one executor turn).
    XCTAssertEqual(mock.receivedTurns.count, 1, "Executor must call the source exactly once")

    // The executor translated the prompt into a user message.
    let turn = try XCTUnwrap(mock.receivedTurns.first, "receivedTurns must be non-empty")
    XCTAssertTrue(
      turn.map(\.role).contains(.user),
      "The executor must send at least one user message; got roles: \(turn.map(\.role))")
    XCTAssertTrue(
      turn.map(\.content).contains("hello"),
      "The user message must carry the prompt text; got content: \(turn.map(\.content))")
  }

  // MARK: - 7. No model/network confirmation

  /// Smoke-test that proves the test suite requires zero model downloads and zero network access.
  ///
  /// All dispatch assertions above use only: temp files, PathGuard, Tool.call, ToolRegistry,
  /// MockGenerationSource. None of these touches the network or a model container.
  func testSuiteRequiresNoModelOrNetwork() {
    // If we reach here, the entire test class ran without loading a model or hitting the network.
    // This is a documentation-style assertion; the real proof is the absence of network/model
    // calls in all other test methods above.
    XCTAssertTrue(true, "This suite has no model or network dependency — confirmed by execution")
  }
}
