import Foundation
import XCTest

import FoundationModels
import SwiftAcervo
import os

@testable import SwiftBruja

/// S2 agent-seam spike: proves a `read_file` tool call round-trips end-to-end through
/// `LanguageModelSession(model:tools:)` driving an MLX model via the custom-provider executor.
///
/// The spike wires the real S1 `ReadFileTool` (wrapped in a recording shim so the test can observe
/// the invocation) behind an `MLXLanguageModel` whose generation is produced by
/// `MLXLanguageModelExecutor` on top of `mlx-swift-lm`. The fixture model
/// `mlx-community/Qwen2.5-0.5B-Instruct-4bit` is small (~280 MB), instruction-tuned, and supports
/// tool calling — small enough for a fast, deterministic-ish round-trip.
///
/// Exit criteria proven here:
/// 1. A `read_file` tool call is observed (the recording shim's `call` fires with the temp path).
/// 2. The temp file's sentinel content round-trips back into the framework loop — it appears in the
///    session transcript (specifically the `.toolOutput` entry the framework appends after dispatch).
///
/// **Requirements:** Apple Silicon, the fixture model present in the
/// `group.intrusive-memory.models` App Group container (download via
/// `./bin/bruja download -m mlx-community/Qwen2.5-0.5B-Instruct-4bit`), and the binary codesigned
/// with the App Group entitlement so SwiftAcervo can reach the container.
@available(macOS 27.0, *)
final class AgentSeamSpikeTest: XCTestCase {

  /// Small, instruct-tuned, tool-calling fixture model.
  private let fixtureModelId = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"

  /// Generous ceiling — first run loads + compiles the model.
  private let timeout: TimeInterval = 240.0

  /// The App Group container the fixture model is downloaded into. SwiftAcervo resolves the
  /// shared-models directory from `ACERVO_APP_GROUP_ID` first (see `Acervo+PathResolution`); the
  /// xctest host's *default* entitlement is `group.acervo.testbundle.default`, which is NOT where
  /// `bruja download` puts models. We pin the env var in `setUp` so the test process resolves to the
  /// same `group.intrusive-memory.models` container the CLI wrote to. Set via `setenv` because
  /// xcodebuild does not forward the parent shell environment to the test host, and Acervo reads
  /// `ProcessInfo.environment` live on every resolution (no caching), so this takes effect.
  private let appGroupId = "group.intrusive-memory.models"

  override func setUp() {
    super.setUp()
    setenv("ACERVO_APP_GROUP_ID", appGroupId, 1)
  }

  // MARK: - Recording tool shim

  /// Wraps the real ``ReadFileTool`` and records each invocation so the test can assert the
  /// tool-calling seam fired. Forwards `call` verbatim to the real tool — the result the model
  /// sees is exactly what S1 produces.
  private final class RecordingReadFileTool: Tool, Sendable {
    // The mutable state lives behind an `OSAllocatedUnfairLock`, which is `Sendable` and safe to use
    // from the async `call` the framework dispatches off the test actor.
    typealias Arguments = ReadFileTool.Arguments

    let name = "read_file"
    let description =
      "Read the contents of a file at the given path and return it as text. "
      + "Use this to inspect source files, configuration, or any readable text file."

    private let inner = ReadFileTool()

    private struct State {
      var invocations: [String] = []
      var results: [String] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    var invocations: [String] { state.withLock { $0.invocations } }
    var results: [String] { state.withLock { $0.results } }

    func call(arguments: Arguments) async throws -> String {
      let path = arguments.path
      let result = try await inner.call(arguments: arguments)
      state.withLock {
        $0.invocations.append(path)
        $0.results.append(result)
      }
      return result
    }
  }

  // MARK: - Test

  func testReadFileToolRoundTripsThroughMLXSession() async throws {
    // 1. Create an isolated working directory and place the fixture file INSIDE it, so the
    //    read_file call stays within the cwd and PathGuard allows it (no CONSENT_REQUIRED).
    //    Mirror the same pattern as AgentReplTest: chdir into the workdir, use a relative path.
    let sentinel = "SWIFTBRUJA_S2_SENTINEL_\(UUID().uuidString.prefix(8))"
    let workDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("bruja_s2_spike_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workDir) }

    let fileName = "bruja_s2_spike.txt"
    let fileURL = workDir.appendingPathComponent(fileName)
    let fileContents = "The secret pass phrase is: \(sentinel)\n"
    try fileContents.write(to: fileURL, atomically: true, encoding: .utf8)

    // Chdir into the workdir so PathGuard's cwd-confinement permits a relative read.
    let savedCwd = FileManager.default.currentDirectoryPath
    FileManager.default.changeCurrentDirectoryPath(workDir.path)
    defer { FileManager.default.changeCurrentDirectoryPath(savedCwd) }

    print("\n📌 S2 spike: workDir \(workDir.path), file \(fileName)")
    print("   sentinel = \(sentinel)")

    // Skip with a clear diagnostic if the model is not reachable. Under a SANDBOXED test host
    // (`xcodebuild test`), the process cannot read another App Group's container even though the
    // path resolves correctly — that is a known environmental limitation shared by every
    // model-backed test in this suite. Run via `make test-agent-seam` (an unsandboxed `xctest`
    // host with the App Group env var) to actually exercise the round-trip.
    guard SwiftAcervo.Acervo.isModelAvailable(fixtureModelId) else {
      throw XCTSkip(
        "Fixture model '\(fixtureModelId)' is not reachable from this test process at "
          + "\(SwiftAcervo.Acervo.sharedModelsDirectory.path). Download it "
          + "(`./bin/bruja download -m \(fixtureModelId)`) and run via an unsandboxed host "
          + "(`make test-agent-seam`). The sandboxed `xcodebuild test` runner cannot read the "
          + "App Group container — a pre-existing environmental limitation."
      )
    }

    // 2. Build the MLX-backed model + session with the recording read_file tool.
    let recorder = RecordingReadFileTool()
    let model = MLXLanguageModel(modelId: fixtureModelId, temperature: 0.0, maxTokens: 256)

    let instructions =
      "You are a file-reading assistant. When asked about a file, you MUST call the "
      + "read_file tool with the exact path provided, then answer using its contents. "
      + "Always call read_file before answering questions about file contents."

    let session = LanguageModelSession(
      model: model,
      tools: [recorder],
      instructions: instructions
    )

    let prompt =
      "Read the file at the path '\(fileName)' and tell me the secret pass phrase it contains."

    // 3. Run the prompt — the framework dispatches read_file, appends the output, and re-prompts.
    print("🔄 Running session.respond(...) — first call loads the MLX model")
    let startTime = Date()

    let response = try await session.respond(to: prompt)

    let duration = Date().timeIntervalSince(startTime)
    print("✅ respond completed in \(String(format: "%.2f", duration))s")
    print("📝 model response: \(response.content)")

    // 4. Assert (a): a read_file tool call was observed against the temp path.
    let invocations = recorder.invocations
    print("🔧 read_file invocations: \(invocations)")
    XCTAssertFalse(
      invocations.isEmpty,
      "Expected the model to call read_file at least once; it did not. "
        + "The tool-calling seam did not fire."
    )
    XCTAssertTrue(
      invocations.contains { $0.contains(fileName) || $0 == fileURL.path },
      "read_file was called but not with the fixture file path. Got: \(invocations)"
    )

    // 5. Assert (b): the file content round-tripped back into the framework loop.
    //    The recorder's result (the S1 ToolResult.ok payload) must carry the sentinel, and that
    //    same content is what the framework appends to the transcript as a `.toolOutput` and feeds
    //    back to the model on the second turn — that is the end-to-end round-trip.
    let toolResults = recorder.results
    XCTAssertTrue(
      toolResults.contains { $0.contains(sentinel) },
      "read_file returned a result but it did not contain the file's sentinel. "
        + "Results: \(toolResults)"
    )

    // The sentinel must also be present in the session transcript — proving the tool output was
    // injected back into the conversation the model continued from.
    let transcriptText = Self.fullText(of: session.transcript)
    XCTAssertTrue(
      transcriptText.contains(sentinel),
      "The file's sentinel did not round-trip into the session transcript. The tool output was "
        + "not fed back into the model loop. Transcript:\n\(transcriptText)"
    )

    print("✅ S2 spike PASSED: read_file call observed + sentinel round-tripped into transcript.")
  }

  // MARK: - Helpers

  /// Flatten every text/structure segment across every transcript entry into one string.
  private static func fullText(of transcript: Transcript) -> String {
    var parts: [String] = []
    for entry in transcript {
      switch entry {
      case .instructions(let i): parts.append(text(of: i.segments))
      case .prompt(let p): parts.append(text(of: p.segments))
      case .response(let r): parts.append(text(of: r.segments))
      case .toolOutput(let o): parts.append(text(of: o.segments))
      case .toolCalls(let calls):
        parts.append(calls.map { "\($0.toolName)(\($0.arguments.jsonString))" }.joined(separator: " "))
      default:
        continue
      }
    }
    return parts.joined(separator: "\n")
  }

  private static func text(of segments: [Transcript.Segment]) -> String {
    var parts: [String] = []
    for segment in segments {
      switch segment {
      case .text(let t): parts.append(t.content)
      case .structure(let s): parts.append(s.content.jsonString)
      default: continue
      }
    }
    return parts.joined(separator: "\n")
  }
}
