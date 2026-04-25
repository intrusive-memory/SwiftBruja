import XCTest
import SwiftAcervo

/// Sortie 5 integration test (R4): Pre-flight manifest API via `bruja info --remote`.
///
/// Verifies that `bruja info -m <model> --remote`:
///
/// 1. Exits 0 (success).
/// 2. Prints three lines to stdout: `Remote: <modelId>`, `Files: <N>`, `Size: <formatted>`.
/// 3. Creates **no new files** under `Acervo.sharedModelsDirectory` (pure CDN read).
///
/// The small fixture model (`mlx-community/Qwen2.5-0.5B-Instruct-4bit`) is used because
/// it is guaranteed to exist on the CDN by Sortie 1 and is small enough that an accidental
/// download would be detected quickly.
///
/// **Requirements:**
/// - The `bruja` binary must be built and available in the DerivedData products directory
///   or in `./bin/bruja` (relative to the test working directory).
/// - Network access is required so the CDN manifest can be fetched.
///
/// Pre-existing failures in `BrujaModelManagerTests` and `InferenceIntegrationTest`
/// (group container permissions, model not pre-downloaded) are environmental and are not
/// affected by this test.
final class PreflightManifestTest: XCTestCase {

    // MARK: - Constants

    /// The small fixture model guaranteed on the CDN by Sortie 1.
    private static let smallFixtureModelId = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"

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
            "bruja binary not found — skipping pre-flight manifest integration test"
        )
    }

    // MARK: - Integration Test

    /// R4 integration test: `bruja info -m <small-fixture> --remote` exits 0,
    /// prints the three-line format, and creates no files under sharedModelsDirectory.
    func testInfoRemotePrintsThreeLinesAndCreatesNoFiles() async throws {
        let sharedModelsDir = Acervo.sharedModelsDirectory

        // Snapshot before: collect all paths present before the command runs.
        let before = snapshotDirectory(sharedModelsDir)

        // Run the command
        let result = await runBrujaCapturingAll(
            ["info", "-m", Self.smallFixtureModelId, "--remote"],
            timeout: 60  // CDN manifest fetch may take a few seconds
        )

        // 1. Must exit 0.
        XCTAssertEqual(
            result.exitCode, 0,
            """
            Expected exit code 0 for `bruja info -m \(Self.smallFixtureModelId) --remote`
            stdout: \(result.stdout)
            stderr: \(result.stderr)
            """
        )

        // 2. Stdout must contain the three required lines.
        let stdoutLines = result.stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let remoteLine = stdoutLines.first { $0.hasPrefix("Remote:") }
        let filesLine = stdoutLines.first { $0.hasPrefix("Files:") }
        let sizeLine = stdoutLines.first { $0.hasPrefix("Size:") }

        XCTAssertNotNil(
            remoteLine,
            "stdout must contain a 'Remote: ...' line.\nstdout: \(result.stdout)"
        )
        XCTAssertNotNil(
            filesLine,
            "stdout must contain a 'Files: ...' line.\nstdout: \(result.stdout)"
        )
        XCTAssertNotNil(
            sizeLine,
            "stdout must contain a 'Size: ...' line.\nstdout: \(result.stdout)"
        )

        // Validate the Remote line contains the model ID
        if let remoteLine {
            XCTAssertTrue(
                remoteLine.contains(Self.smallFixtureModelId),
                "Remote line should contain the model ID '\(Self.smallFixtureModelId)'; got: \(remoteLine)"
            )
        }

        // Validate Files count is a positive integer
        if let filesLine {
            let countStr = filesLine
                .replacingOccurrences(of: "Files:", with: "")
                .trimmingCharacters(in: .whitespaces)
            let count = Int(countStr) ?? -1
            XCTAssertGreaterThan(
                count, 0,
                "Files count must be > 0; got '\(countStr)' from line: \(filesLine)"
            )
        }

        // 3. Snapshot after: no new files should exist.
        let after = snapshotDirectory(sharedModelsDir)
        XCTAssertEqual(
            before, after,
            """
            `bruja info --remote` must not write files to sharedModelsDirectory.
            New paths: \(after.subtracting(before).sorted().joined(separator: "\n"))
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
    /// Does NOT throw when the process exits non-zero — the integration test checks the
    /// exit code itself.
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

    /// Returns a sorted set of all file paths under `directory`, for before/after comparison.
    private func snapshotDirectory(_ directory: URL) -> Set<String> {
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }
        var paths = Set<String>()
        for case let url as URL in enumerator {
            paths.insert(url.path)
        }
        return paths
    }
}
