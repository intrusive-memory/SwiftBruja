import XCTest

/// Sortie 7 (R5): Smoke tests for the `[bruja] SharedModels:` stderr self-diagnostic line.
///
/// These tests verify three properties of the stderr logging added in Sortie 7:
///
/// 1. **JSON stdout purity** — when `--json` is passed, stdout remains valid JSON even though
///    the `[bruja] SharedModels:` line is present on stderr. (stderr must NOT bleed into stdout.)
///
/// 2. **Line present on stderr** — `bruja query "hi"` without `--quiet` emits the
///    `[bruja] SharedModels:` line on stderr.
///
/// 3. **Line suppressed under `--quiet`** — `bruja query "hi" --quiet` does NOT emit
///    the `[bruja] SharedModels:` line on stderr.
///
/// All three tests run `bruja query "hi"` against the default model.  Because the model may
/// not be pre-downloaded in all CI environments, the tests **only inspect stderr** for tests
/// 2 and 3, and **capture stdout separately** for test 1.  A non-zero exit code is acceptable
/// — SwiftBruja may fail with a model-not-found error, but the `[bruja] SharedModels:` line
/// is emitted *before* the first heavy operation and must therefore appear regardless of
/// whether inference ultimately succeeds.
///
/// **Requirements:**
/// - The `bruja` binary must be built and available in the DerivedData products directory or
///   in `./bin/bruja` (relative to the test working directory).
///
/// Pre-existing failures in `BrujaModelManagerTests` and `InferenceIntegrationTest`
/// (group container permissions, model not pre-downloaded) are environmental and
/// are not affected by this test.
final class SharedModelsLoggingTest: XCTestCase {

  // MARK: - Constants

  /// The prefix that must (or must not) appear on stderr for the R5 self-diagnostic.
  private static let sharedModelsPrefix = "[bruja] SharedModels:"

  // MARK: - Setup

  var brujaBinaryPath: String!

  override func setUp() async throws {
    try await super.setUp()

    // Search for the bruja binary in well-known locations.
    // DerivedData products directory is checked first (preferred in CI),
    // then well-known fallback paths.
    var candidates: [String] = [
      "./bin/bruja",
      "../bin/bruja",
      "../../bin/bruja",
      "../../../bin/bruja",
      "/usr/local/bin/bruja",
    ]

    // Also check next to the test bundle in DerivedData (Debug products dir).
    if let bundlePath = Bundle(for: type(of: self)).bundlePath as String? {
      let productsDir = (bundlePath as NSString).deletingLastPathComponent
      candidates.insert(productsDir + "/bruja", at: 0)
    }

    brujaBinaryPath = candidates.first { path in
      FileManager.default.isExecutableFile(atPath: path)
    }

    try XCTSkipIf(
      brujaBinaryPath == nil,
      "bruja binary not found — skipping SharedModels logging smoke tests"
    )
  }

  // MARK: - R5 Smoke Tests

  /// R5 test 1: `bruja query "hi" --json` stdout must remain valid JSON.
  ///
  /// The `[bruja] SharedModels:` line goes to stderr; stdout must contain ONLY
  /// valid JSON (or be empty if the model is not downloaded — both are acceptable).
  func testQueryJsonStdoutRemainsValidJSON() async throws {
    let result = await runBrujaCapturingAll(
      ["query", "hi", "--json"],
      timeout: 30
    )

    // If stdout is empty (model not downloaded → early error), the test passes:
    // stdout was not polluted with the SharedModels line.
    let stdoutTrimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !stdoutTrimmed.isEmpty else {
      // Empty stdout is acceptable — stderr may carry an error, stdout is clean.
      return
    }

    // Non-empty stdout MUST be valid JSON.
    guard let data = stdoutTrimmed.data(using: .utf8) else {
      XCTFail("stdout is not valid UTF-8: \(stdoutTrimmed)")
      return
    }
    do {
      _ = try JSONSerialization.jsonObject(with: data)
    } catch {
      XCTFail(
        """
        stdout is not valid JSON (R5: [bruja] SharedModels line must go to stderr, not stdout).
        Parse error: \(error)
        stdout was:
        \(stdoutTrimmed)
        stderr was:
        \(result.stderr)
        """
      )
    }
  }

  /// R5 test 2: `bruja query "hi"` (no `--quiet`) must emit `[bruja] SharedModels:` on stderr.
  func testQueryEmitsSharedModelsLineOnStderr() async throws {
    let result = await runBrujaCapturingAll(
      ["query", "hi"],
      timeout: 30
    )

    XCTAssertTrue(
      result.stderr.contains(Self.sharedModelsPrefix),
      """
      Expected stderr to contain '\(Self.sharedModelsPrefix)' but it did not.
      stderr was:
      \(result.stderr)
      stdout was:
      \(result.stdout)
      exitCode: \(result.exitCode)
      """
    )
  }

  /// R5 test 3: `bruja query "hi" --quiet` must NOT emit `[bruja] SharedModels:` on stderr.
  func testQueryWithQuietSuppressesSharedModelsLine() async throws {
    let result = await runBrujaCapturingAll(
      ["query", "hi", "--quiet"],
      timeout: 30
    )

    XCTAssertFalse(
      result.stderr.contains(Self.sharedModelsPrefix),
      """
      Expected stderr NOT to contain '\(Self.sharedModelsPrefix)' under --quiet, but it did.
      stderr was:
      \(result.stderr)
      stdout was:
      \(result.stdout)
      exitCode: \(result.exitCode)
      """
    )
  }

  // MARK: - Helpers

  /// Result of running `bruja` as a subprocess, capturing both stdout and stderr.
  private struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
  }

  /// Runs the `bruja` binary with `arguments`, capturing stdout, stderr, and the exit code.
  ///
  /// Unlike the `runBruja` helper in `BrujaIntegrationTests`, this method does NOT throw
  /// on non-zero exit — which is required here because the model may not be downloaded.
  private func runBrujaCapturingAll(
    _ arguments: [String],
    timeout: TimeInterval = 30
  ) async -> ProcessResult {
    guard let binaryPath = brujaBinaryPath else {
      return ProcessResult(exitCode: -1, stdout: "", stderr: "binary not found")
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: binaryPath)
    process.arguments = arguments

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
      try process.run()
    } catch {
      return ProcessResult(exitCode: -1, stdout: "", stderr: "launch failed: \(error)")
    }

    // Wait with timeout.
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
      try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 s
    }

    if process.isRunning {
      process.terminate()
    }

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    return ProcessResult(
      exitCode: process.terminationStatus,
      stdout: String(data: stdoutData, encoding: .utf8) ?? "",
      stderr: String(data: stderrData, encoding: .utf8) ?? ""
    )
  }
}
