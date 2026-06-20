import Foundation
import SwiftAcervo
import XCTest

/// S7 integration test: proves `bruja agent "<task>"` runs the MLX agent loop end-to-end and
/// round-trips a `read_file` tool call against the fixture model.
///
/// Unlike the in-process `AgentSeamSpikeTest`, the agent loop (`AgentLoop`, `ConsentToolObserver`)
/// lives in the `bruja` **executable** target, which cannot be `@testable import`-ed. So this test
/// drives the REAL signed binary at `./bin/bruja` — the same surface a user invokes — and asserts on
/// its output. The binary is unsandboxed and codesigned with the App Group entitlement, so it can
/// reach the `group.intrusive-memory.models` container the fixture model was downloaded into.
///
/// Exit criteria proven here (mirrors the Sortie-7 plan):
/// 1. `bruja agent "<task>"` exits 0.
/// 2. Its output surfaces a `read_file` tool call (the loop echoes `→ read_file(...)`).
/// 3. The file's unique sentinel round-trips back (the model answers using the file contents).
///
/// **Requirements:** Apple Silicon, the fixture model present in the App Group container, and a
/// built+signed `./bin/bruja` (`make install && make codesign-cli`). Skips with a clear diagnostic
/// when either is missing — the same environmental contract as every model-backed test here.
@available(macOS 27.0, *)
final class AgentReplTest: XCTestCase {

  private let fixtureModelId = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"
  private let appGroupId = "group.intrusive-memory.models"

  override func setUp() {
    super.setUp()
    setenv("ACERVO_APP_GROUP_ID", appGroupId, 1)
  }

  /// Resolve the repo-root `./bin/bruja` relative to this source file.
  private func brujaBinaryURL() -> URL {
    // This file: <repo>/Tests/BrujaIntegrationTests/AgentReplTest.swift
    let thisFile = URL(fileURLWithPath: #filePath)
    let repoRoot =
      thisFile
      .deletingLastPathComponent()  // BrujaIntegrationTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // repo root
    return repoRoot.appendingPathComponent("bin/bruja")
  }

  func testAgentVerbRoundTripsReadFileAgainstFixtureModel() async throws {
    let binary = brujaBinaryURL()

    guard FileManager.default.isExecutableFile(atPath: binary.path) else {
      throw XCTSkip(
        "Built binary not found at \(binary.path). Build + sign it first: "
          + "`make install && make codesign-cli`, then re-run "
          + "(`make test-agent-repl` or directly)."
      )
    }

    guard SwiftAcervo.Acervo.isModelAvailable(fixtureModelId) else {
      throw XCTSkip(
        "Fixture model '\(fixtureModelId)' is not reachable. Download it "
          + "(`./bin/bruja download -m \(fixtureModelId)`) and run via an unsandboxed host. The "
          + "sandboxed `xcodebuild test` runner cannot read the App Group container — a pre-existing "
          + "environmental limitation."
      )
    }

    // Unique sentinel the model could not have invented.
    let sentinel = "SWIFTBRUJA_S7_SENTINEL_\(UUID().uuidString.prefix(8))"

    // Create an isolated working directory and put the fixture file INSIDE it, so the filesystem
    // tool stays within the cwd (PathGuard allows it — no consent prompt would block on stdin). We
    // reference the file by basename and run the binary with cwd set to this directory.
    let workDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("bruja_s7_repl_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workDir) }

    let fileName = "secret.txt"
    let fileURL = workDir.appendingPathComponent(fileName)
    try "The secret pass phrase is: \(sentinel)\n".write(
      to: fileURL, atomically: true, encoding: .utf8)

    let task =
      "Read the file at the path '\(fileName)' and tell me the secret pass phrase it contains."

    let process = Process()
    process.executableURL = binary
    process.arguments = ["agent", task]
    // Run with cwd set to the work dir so the read (by basename) stays inside the working directory
    // (no consent prompt — the binary would block on stdin otherwise). PathGuard confines to the
    // process cwd.
    process.currentDirectoryURL = workDir

    var environment = ProcessInfo.processInfo.environment
    environment["ACERVO_APP_GROUP_ID"] = appGroupId
    process.environment = environment

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardInput = FileHandle.nullDevice  // EOF immediately → one-shot never blocks.
    process.standardError = stderrPipe

    print("🔄 Running: \(binary.path) agent \"\(task)\"  (cwd: \(workDir.path))")
    let start = Date()
    try process.run()
    process.waitUntilExit()
    let duration = Date().timeIntervalSince(start)

    let stdout =
      String(
        data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr =
      String(
        data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    print("✅ exited \(process.terminationStatus) in \(String(format: "%.2f", duration))s")
    print("---- stdout ----\n\(stdout)\n---- stderr ----\n\(stderr)\n----------------")

    XCTAssertEqual(
      process.terminationStatus, 0,
      "bruja agent should exit 0. stderr:\n\(stderr)\nstdout:\n\(stdout)")

    // The loop echoes each tool dispatch as "→ read_file(...)". Either the echo or an audit line
    // ("[bruja audit] read_file") proves the read_file tool was dispatched.
    let calledReadFile =
      stdout.contains("read_file") || stderr.contains("read_file")
    XCTAssertTrue(
      calledReadFile,
      "Expected a read_file tool call to be surfaced. stdout:\n\(stdout)\nstderr:\n\(stderr)")

    // The file sentinel must round-trip back — either echoed in the tool result line or used in the
    // model's final answer.
    XCTAssertTrue(
      stdout.contains(sentinel),
      "The file's sentinel did not round-trip into the agent output. stdout:\n\(stdout)")

    print("✅ S7 AgentReplTest PASSED: read_file dispatched + sentinel round-tripped.")
  }
}
