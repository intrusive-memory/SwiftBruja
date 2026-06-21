import Foundation
import FoundationModels
import SwiftAcervo
import XCTest

/// S9 integration test: proves `bruja agent --backend foundation "<task>"` drives
/// `SystemLanguageModel` through the SAME tool seam as the MLX path.
///
/// This test drives the REAL signed binary at `./bin/bruja` — the same surface a user invokes.
/// It asserts the correct branch FOR THE RUNNING HOST:
/// - FM-available host: `--backend foundation` exits 0, round-trips a `read_file` tool call.
/// - FM-unavailable host: `--backend foundation` exits non-zero with the `.unavailable` reason
///   in stderr.
///
/// **Requirements for the FM-available path:** `make install && make codesign-cli` must have been
/// run, and `SystemLanguageModel.default.availability` must be `.available` on this machine.
/// Run via `make test-agent-fm` (an unsandboxed xctest host, same pattern as `test-agent-repl`).
@available(macOS 26.0, *)
final class FoundationBackendIntegrationTest: XCTestCase {

  private let appGroupId = "group.intrusive-memory.models"

  override func setUp() {
    super.setUp()
    setenv("ACERVO_APP_GROUP_ID", appGroupId, 1)
  }

  /// Resolve the repo-root `./bin/bruja` relative to this source file.
  private func brujaBinaryURL() -> URL {
    // This file: <repo>/Tests/BrujaIntegrationTests/FoundationBackendIntegrationTest.swift
    let thisFile = URL(fileURLWithPath: #filePath)
    let repoRoot =
      thisFile
      .deletingLastPathComponent()  // BrujaIntegrationTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // repo root
    return repoRoot.appendingPathComponent("bin/bruja")
  }

  /// Determine whether FM is actually available on this host (live check, same as CLI path).
  private func fmIsAvailable() -> Bool {
    if case .available = SystemLanguageModel.default.availability { return true }
    return false
  }

  // MARK: - Integration test

  func testFoundationBackendRoundTripsOrFailsLoudly() async throws {
    let binary = brujaBinaryURL()

    guard FileManager.default.isExecutableFile(atPath: binary.path) else {
      throw XCTSkip(
        "Built binary not found at \(binary.path). Build + sign it first: "
          + "`make install && make codesign-cli`, then re-run (`make test-agent-fm`)."
      )
    }

    let sentinel = "SWIFTBRUJA_S9_SENTINEL_\(UUID().uuidString.prefix(8))"

    // Create an isolated working directory with the fixture file inside it.
    let workDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("bruja_s9_fm_\(UUID().uuidString)")
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
    process.arguments = ["agent", "--backend", "foundation", task]
    process.currentDirectoryURL = workDir

    var environment = ProcessInfo.processInfo.environment
    environment["ACERVO_APP_GROUP_ID"] = appGroupId
    process.environment = environment

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardInput = FileHandle.nullDevice
    process.standardError = stderrPipe

    print(
      "\n[S9] Running: \(binary.path) agent --backend foundation \"\(task)\"  (cwd: \(workDir.path))"
    )
    let start = Date()
    try process.run()
    process.waitUntilExit()
    let duration = Date().timeIntervalSince(start)

    let stdout =
      String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr =
      String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    print("[S9] exited \(process.terminationStatus) in \(String(format: "%.2f", duration))s")
    print("---- stdout ----\n\(stdout)\n---- stderr ----\n\(stderr)\n----------------")

    if fmIsAvailable() {
      // FM-AVAILABLE PATH: must exit 0 and round-trip a tool call.
      XCTAssertEqual(
        process.terminationStatus, 0,
        "[S9 FM-available] bruja agent --backend foundation should exit 0. "
          + "stderr:\n\(stderr)\nstdout:\n\(stdout)")

      let calledReadFile = stdout.contains("read_file") || stderr.contains("read_file")
      XCTAssertTrue(
        calledReadFile,
        "[S9 FM-available] Expected a read_file tool call to be surfaced. "
          + "stdout:\n\(stdout)\nstderr:\n\(stderr)")

      XCTAssertTrue(
        stdout.contains(sentinel),
        "[S9 FM-available] The file's sentinel did not round-trip into the agent output. "
          + "stdout:\n\(stdout)")

      print("[S9] PASS: FM-available path — read_file dispatched + sentinel round-tripped.")
    } else {
      // FM-UNAVAILABLE PATH: must exit non-zero with the unavailability reason.
      XCTAssertNotEqual(
        process.terminationStatus, 0,
        "[S9 FM-unavailable] bruja agent --backend foundation should exit non-zero when FM is "
          + "unavailable. stdout:\n\(stdout)\nstderr:\n\(stderr)")

      // The unavailability reason must appear in stderr (the CLI error message).
      let combinedOutput = stdout + stderr
      let mentionsUnavailability =
        combinedOutput.contains("not available")
        || combinedOutput.contains("Apple Intelligence")
        || combinedOutput.contains("Foundation Models")
      XCTAssertTrue(
        mentionsUnavailability,
        "[S9 FM-unavailable] Stderr must explain why FM is unavailable. "
          + "stdout:\n\(stdout)\nstderr:\n\(stderr)")

      print("[S9] PASS: FM-unavailable path — non-zero exit + unavailability reason in output.")
    }
  }
}
