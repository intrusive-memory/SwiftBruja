import XCTest

/// Smoke test for Sortie 3 (R2): Error reporting for unknown / missing CDN models.
///
/// This test runs the compiled `bruja` binary as a subprocess and asserts that
/// attempting to download a model that is deliberately absent from the CDN
/// (`mlx-community/does-not-exist`) produces:
///
/// - A **non-zero exit code** (1), and
/// - A **stderr line that exactly matches** the canonical R2 error message:
///   `Error: Model 'mlx-community/does-not-exist' is not published on the CDN.`
///
/// **Requirements:**
/// - The `bruja` binary must be built and available in `./bin/bruja`.
/// - Network access is needed so that SwiftAcervo can attempt (and fail) the CDN lookup.
///
/// Pre-existing failures in `BrujaModelManagerTests` and `InferenceIntegrationTest`
/// (group container permissions, model not pre-downloaded) are environmental and
/// are not affected by this test.
final class ErrorReportingSmokeTest: XCTestCase {

    // MARK: - Constants

    /// The model ID that is intentionally absent from the CDN (Shared Fixture: MISSING_MODEL_ID).
    private static let missingModelId = "mlx-community/does-not-exist"

    /// The exact error line that must appear on stderr for the missing-model case.
    private static let expectedStderrPrefix =
        "Error: Model 'mlx-community/does-not-exist' is not published on the CDN."

    // MARK: - Setup

    var brujaBinaryPath: String!

    override func setUp() async throws {
        try await super.setUp()

        // Search for the bruja binary in well-known locations.
        // When running via `make test` (xcodebuild), the working directory is
        // `.swiftpm/xcode/` inside the project root, so relative paths need to
        // walk up several levels. DerivedData is also checked for in-process builds.
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
            "bruja binary not found — skipping error-reporting smoke test"
        )
    }

    // MARK: - Smoke Test

    /// R2 smoke test: `bruja download -m mlx-community/does-not-exist` must exit
    /// non-zero and print the canonical error message to stderr.
    func testDownloadMissingModelExitsNonZeroWithCanonicalMessage() async throws {
        let result = await runBrujaCapturingAll(
            ["download", "-m", Self.missingModelId],
            timeout: 30
        )

        // 1. The process must exit non-zero.
        XCTAssertNotEqual(
            result.exitCode, 0,
            "Expected non-zero exit code when downloading a missing model; got 0.\nstderr: \(result.stderr)"
        )

        // 2. stderr must contain the canonical R2 error message verbatim on at least one line.
        let stderr = result.stderr
        XCTAssertTrue(
            stderr.split(separator: "\n").contains { $0.hasPrefix(Self.expectedStderrPrefix) },
            "expected stderr to contain a line starting with '\(Self.expectedStderrPrefix)' but got: \(stderr)"
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
    /// Unlike the `runBruja(_:timeout:)` helper in `BrujaIntegrationTests`, this method
    /// does **not** throw when the process exits non-zero — which is exactly what the
    /// error-reporting smoke test requires.
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
