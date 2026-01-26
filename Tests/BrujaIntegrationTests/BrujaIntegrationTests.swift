import XCTest
@testable import SwiftBruja

/// Integration tests for the `bruja` CLI tool.
///
/// These tests verify end-to-end functionality by:
/// 1. Running the compiled `bruja` binary
/// 2. Downloading an LLM model (if needed)
/// 3. Executing queries and verifying responses
///
/// **Requirements:**
/// - The `bruja` binary must be built and available in `./bin/bruja`
/// - Network access for model downloads
/// - Apple Silicon Mac (M1/M2/M3/M4)
///
/// **CI Setup:**
/// These tests run in a separate CI job that:
/// 1. Builds the bruja binary with `make release`
/// 2. Downloads the default LLM model
/// 3. Runs these integration tests
final class BrujaIntegrationTests: XCTestCase {

    var brujaBinaryPath: String!

    override func setUp() async throws {
        try await super.setUp()

        // Find bruja binary - check multiple locations
        let possiblePaths = [
            "./bin/bruja",
            "../bin/bruja",
            "../../bin/bruja",
            "/usr/local/bin/bruja"
        ]

        brujaBinaryPath = possiblePaths.first { path in
            FileManager.default.isExecutableFile(atPath: path)
        }

        // Skip if binary not found (allows unit tests to run without binary)
        try XCTSkipIf(brujaBinaryPath == nil, "bruja binary not found - skipping integration tests")
    }

    // MARK: - Integration Tests

    /// Tests that `bruja --version` returns version information.
    func testVersionCommand() async throws {
        let output = try await runBruja(["--version"])

        // Should contain version info
        XCTAssertFalse(output.isEmpty, "Version output should not be empty")
        print("Version output: \(output)")
    }

    /// Tests that `bruja list` works (even with no models downloaded).
    func testListCommand() async throws {
        let output = try await runBruja(["list"])

        // Should return something (either models or "no models" message)
        // This test just verifies the command runs without error
        print("List output: \(output)")
    }

    /// Tests that `bruja query` can execute a simple prompt and return a response.
    /// This is the core end-to-end test that validates LLM inference works.
    func testSimpleQuery() async throws {
        // Use a simple, deterministic prompt
        let prompt = "What is 2 + 2? Answer with just the number."

        let output = try await runBruja([
            "query", prompt,
            "--max-tokens", "50",
            "--quiet"
        ], timeout: 120) // Allow up to 2 minutes for model loading + inference

        XCTAssertFalse(output.isEmpty, "Query should return a response")

        // The response should contain "4" somewhere
        XCTAssertTrue(
            output.contains("4"),
            "Response should contain '4' for '2+2'. Got: \(output)"
        )

        print("✅ Query response: \(output)")
    }

    /// Tests that `bruja query --json` returns valid JSON with metadata.
    func testQueryWithJSONOutput() async throws {
        let prompt = "Say hello"

        let output = try await runBruja([
            "query", prompt,
            "--max-tokens", "20",
            "--json",
            "--quiet"
        ], timeout: 120)

        // Should be valid JSON
        guard let data = output.data(using: .utf8) else {
            XCTFail("Output is not valid UTF-8")
            return
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            XCTAssertNotNil(json, "Output should be a JSON object")

            // Check for expected fields
            XCTAssertNotNil(json?["response"], "JSON should contain 'response' field")
            XCTAssertNotNil(json?["model"], "JSON should contain 'model' field")

            print("✅ JSON output validated: \(json?["response"] ?? "nil")")
        } catch {
            XCTFail("Failed to parse JSON output: \(error). Output was: \(output)")
        }
    }

    /// Tests a more complex query to ensure the model can handle real prompts.
    func testComplexQuery() async throws {
        let prompt = "List three primary colors, separated by commas."

        let output = try await runBruja([
            "query", prompt,
            "--max-tokens", "50",
            "--quiet"
        ], timeout: 120)

        XCTAssertFalse(output.isEmpty, "Query should return a response")

        // Response should mention at least one primary color
        let colors = ["red", "blue", "yellow"]
        let outputLower = output.lowercased()
        let hasColor = colors.contains { outputLower.contains($0) }

        XCTAssertTrue(
            hasColor,
            "Response should contain at least one primary color. Got: \(output)"
        )

        print("✅ Complex query response: \(output)")
    }

    // MARK: - Helpers

    /// Runs the bruja binary with the given arguments and returns stdout.
    private func runBruja(_ arguments: [String], timeout: TimeInterval = 30) async throws -> String {
        guard let binaryPath = brujaBinaryPath else {
            throw IntegrationTestError.binaryNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Wait with timeout
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
        }

        if process.isRunning {
            process.terminate()
            throw IntegrationTestError.timeout(seconds: timeout)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw IntegrationTestError.processFailure(
                exitCode: process.terminationStatus,
                stdout: stdout,
                stderr: stderr
            )
        }

        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Errors

    enum IntegrationTestError: LocalizedError {
        case binaryNotFound
        case timeout(seconds: TimeInterval)
        case processFailure(exitCode: Int32, stdout: String, stderr: String)

        var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                return "bruja binary not found"
            case .timeout(let seconds):
                return "Process timed out after \(seconds) seconds"
            case .processFailure(let exitCode, let stdout, let stderr):
                return "Process failed with exit code \(exitCode)\nstdout: \(stdout)\nstderr: \(stderr)"
            }
        }
    }
}
