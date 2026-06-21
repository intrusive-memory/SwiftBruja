import Foundation
import XCTest

import SwiftAcervo

@testable import SwiftBruja

/// Agent-loop spike: proves a `read_file` tool call round-trips end-to-end through the macOS-26
/// ``MLXAgentLoop`` driving an MLX model via `MLXLMCommon` native tool-call parsing (the
/// replacement for the removed macOS-27 `LanguageModelSession`/`MLXLanguageModelExecutor` seam).
///
/// The spike runs the real `ReadFileTool` (via ``RegistryToolHandler``) behind the hand-rolled loop
/// against the fixture model `mlx-community/Qwen2.5-0.5B-Instruct-4bit` (~280 MB, instruction-tuned,
/// tool-calling) — small enough for a fast, deterministic-ish round-trip.
///
/// Exit criteria proven here:
/// 1. A `read_file` tool call is observed (a `.toolCallStarted` event fires with the temp path).
/// 2. The temp file's sentinel content round-trips back into the loop — it appears in the
///    `.toolFinished` result the loop feeds back to the model.
///
/// **Requirements:** Apple Silicon, the fixture model present in the `group.intrusive-memory.models`
/// App Group container (download via `./bin/bruja download -m mlx-community/Qwen2.5-0.5B-Instruct-4bit`),
/// and the binary codesigned with the App Group entitlement so SwiftAcervo can reach the container.
@available(macOS 26.0, *)
final class AgentSeamSpikeTest: XCTestCase {

  /// Small, instruct-tuned, tool-calling fixture model.
  private let fixtureModelId = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"

  /// The App Group container the fixture model is downloaded into. SwiftAcervo resolves the
  /// shared-models directory from `ACERVO_APP_GROUP_ID` first; the xctest host's default entitlement
  /// is not where `bruja download` puts models, so we pin the env var to the CLI's container.
  private let appGroupId = "group.intrusive-memory.models"

  override func setUp() {
    super.setUp()
    setenv("ACERVO_APP_GROUP_ID", appGroupId, 1)
  }

  /// Thread-safe sink for the loop's `@Sendable` event callback.
  private actor EventLog {
    private(set) var toolCalls: [(name: String, argumentsJSON: String)] = []
    private(set) var toolResults: [String] = []
    private(set) var assistantText = ""

    func record(_ event: AgentTurnEvent) {
      switch event {
      case .assistantText(let text):
        assistantText += text
      case .toolCallStarted(let name, let argumentsJSON):
        toolCalls.append((name: name, argumentsJSON: argumentsJSON))
      case .toolFinished(_, let result):
        toolResults.append(result)
      }
    }
  }

  // MARK: - Test

  func testReadFileToolRoundTripsThroughMLXSession() async throws {
    // 1. Create an isolated working directory and place the fixture file INSIDE it, so the
    //    read_file call stays within the cwd and PathGuard allows it (no CONSENT_REQUIRED).
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

    print("\n📌 agent-loop spike: workDir \(workDir.path), file \(fileName)")
    print("   sentinel = \(sentinel)")

    // Skip with a clear diagnostic if the model is not reachable. Under a SANDBOXED test host
    // (`xcodebuild test`) the process cannot read another App Group's container even though the path
    // resolves; run via `make test-agent-seam` (an unsandboxed `xctest` host) to exercise it.
    guard SwiftAcervo.Acervo.isModelAvailable(fixtureModelId) else {
      throw XCTSkip(
        "Fixture model '\(fixtureModelId)' is not reachable from this test process at "
          + "\(SwiftAcervo.Acervo.sharedModelsDirectory.path). Download it "
          + "(`./bin/bruja download -m \(fixtureModelId)`) and run via an unsandboxed host "
          + "(`make test-agent-seam`). The sandboxed `xcodebuild test` runner cannot read the "
          + "App Group container — a pre-existing environmental limitation."
      )
    }

    // 2. Build the MLX-backed agent loop with the real read_file tool.
    let instructions =
      "You are a file-reading assistant. When asked about a file, you MUST call the "
      + "read_file tool with the exact path provided, then answer using its contents. "
      + "Always call read_file before answering questions about file contents."

    let loop = MLXAgentLoop(
      configuration: MLXAgentLoop.Configuration(
        modelId: fixtureModelId,
        temperature: 0.0,
        maxTokens: 256,
        instructions: instructions
      ),
      tools: RegistryToolHandler()
    )

    let prompt =
      "Read the file at the path '\(fileName)' and tell me the secret pass phrase it contains."

    // 3. Run the prompt — the loop dispatches read_file, appends the output, and re-generates.
    print("🔄 Running loop.runTurn(...) — first call loads the MLX model")
    let log = EventLog()
    let startTime = Date()

    try await loop.runTurn(prompt) { event in await log.record(event) }

    let duration = Date().timeIntervalSince(startTime)
    print("✅ runTurn completed in \(String(format: "%.2f", duration))s")
    let assistantText = await log.assistantText
    print("📝 model response: \(assistantText)")

    // 4. Assert (a): a read_file tool call was observed against the fixture path.
    let toolCalls = await log.toolCalls
    print("🔧 tool calls: \(toolCalls.map { "\($0.name)(\($0.argumentsJSON))" })")
    XCTAssertTrue(
      toolCalls.contains { $0.name == "read_file" },
      "Expected the model to call read_file at least once; tool-calling did not fire. Got: \(toolCalls)"
    )
    XCTAssertTrue(
      toolCalls.contains { $0.name == "read_file" && $0.argumentsJSON.contains(fileName) },
      "read_file was called but not with the fixture file path. Got: \(toolCalls)"
    )

    // 5. Assert (b): the file content round-tripped back into the loop — the tool result the loop
    //    fed back to the model carries the sentinel.
    let toolResults = await log.toolResults
    XCTAssertTrue(
      toolResults.contains { $0.contains(sentinel) },
      "read_file returned a result but it did not contain the file's sentinel. Results: \(toolResults)"
    )

    print("✅ agent-loop spike PASSED: read_file call observed + sentinel round-tripped.")
  }
}
