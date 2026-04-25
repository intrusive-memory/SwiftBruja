import BrujaHelpers
import XCTest

// MARK: - ProgressRenderer Unit Tests

/// Tests for `ProgressRenderer` covering non-TTY line-oriented output,
/// TTY redraw output, quiet-mode suppression, and the public stderr-logging method.
///
/// These tests use `ProgressRenderer(quiet:isTTY:)` to exercise specific paths
/// deterministically, independent of whether xcodebuild attaches a pseudo-TTY
/// to the test runner's stdout.
final class ProgressRendererNonTTYTests: XCTestCase {

    // MARK: - Helpers

    /// Runs `body` while capturing everything written to `fd` (stdout = 1, stderr = 2).
    /// Returns the captured UTF-8 string.
    private func capture(fd: Int32, body: () async throws -> Void) async throws -> String {
        // Create a pipe and redirect the target fd into the write end.
        var pipeFDs: [Int32] = [0, 0]
        XCTAssertEqual(Darwin.pipe(&pipeFDs), 0, "pipe() failed")
        let readFD = pipeFDs[0]
        let writeFD = pipeFDs[1]

        // Save the original fd.
        let savedFD = Darwin.dup(fd)
        XCTAssertGreaterThanOrEqual(savedFD, 0, "dup() failed")

        // Redirect the fd to the write end of the pipe.
        XCTAssertGreaterThanOrEqual(Darwin.dup2(writeFD, fd), 0, "dup2(write,fd) failed")
        Darwin.close(writeFD)

        // Run the body.
        try await body()

        // Flush C-level stdio buffers before we close the write end.
        Darwin.fflush(nil)

        // Restore the original fd.
        XCTAssertGreaterThanOrEqual(Darwin.dup2(savedFD, fd), 0, "dup2(saved,fd) failed")
        Darwin.close(savedFD)

        // Read everything from the pipe's read end.
        var output = ""
        let bufSize = 65536
        var buf = [UInt8](repeating: 0, count: bufSize)
        while true {
            let n = Darwin.read(readFD, &buf, bufSize)
            if n <= 0 { break }
            output += String(bytes: buf[0..<n], encoding: .utf8) ?? ""
        }
        Darwin.close(readFD)
        return output
    }

    // MARK: - Non-TTY Output Tests

    /// In non-TTY mode, `reportProgress` emits exactly one line per 10-percent bucket.
    func testNonTTY_EmitsOneLinePerDecile() async throws {
        // Use isTTY: false to force the non-TTY code path regardless of the test runner.
        let renderer = ProgressRenderer(quiet: false, isTTY: false)
        let output = try await capture(fd: STDOUT_FILENO) {
            // Simulate 11 progress events from 0% to 100% in 10% steps.
            for i in 0...10 {
                await renderer.reportProgress(Double(i) / 10.0)
            }
        }

        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 11, "Expected 11 progress lines (0%–100%); got: \(lines)")

        // Verify the exact line format.
        let expected = (0...10).map { "Download progress: \($0 * 10)%" }
        XCTAssertEqual(lines, expected, "Line content mismatch")
    }

    /// Rapid duplicate events within the same bucket should not produce extra lines.
    func testNonTTY_NoDuplicatesWithinBucket() async throws {
        let renderer = ProgressRenderer(quiet: false, isTTY: false)
        let output = try await capture(fd: STDOUT_FILENO) {
            // Fire many events all within 0%–9% (bucket 0).
            for i in 0..<20 {
                await renderer.reportProgress(Double(i) / 200.0)
            }
        }

        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 1, "Only one line expected for bucket 0; got: \(lines)")
        XCTAssertEqual(lines.first, "Download progress: 0%")
    }

    /// Non-TTY output must contain no ANSI escape bytes (0x1B).
    func testNonTTY_NoANSIEscapes() async throws {
        let renderer = ProgressRenderer(quiet: false, isTTY: false)
        let output = try await capture(fd: STDOUT_FILENO) {
            await renderer.reportProgress(0.5)
            await renderer.reportCompletion(modelId: "test/model")
        }

        XCTAssertFalse(
            output.contains("\u{1B}"),
            "Non-TTY output must not contain ANSI escape sequences; got: \(output.debugDescription)"
        )
    }

    /// `reportCompletion` emits a "Download complete:" line on the non-TTY path.
    func testNonTTY_CompletionLine() async throws {
        let renderer = ProgressRenderer(quiet: false, isTTY: false)
        let output = try await capture(fd: STDOUT_FILENO) {
            await renderer.reportProgress(1.0)
            await renderer.reportCompletion(modelId: "mlx-community/test-model")
        }

        XCTAssertTrue(
            output.contains("Download complete: mlx-community/test-model"),
            "Completion line missing from output: \(output.debugDescription)"
        )
    }

    /// `reportCompletion` emits 100% before the completion line if 100 was not yet emitted.
    func testNonTTY_CompletionEnsures100Percent() async throws {
        let renderer = ProgressRenderer(quiet: false, isTTY: false)
        let output = try await capture(fd: STDOUT_FILENO) {
            // No progress events — jump straight to completion.
            await renderer.reportCompletion(modelId: "test/model")
        }

        XCTAssertTrue(
            output.contains("Download progress: 100%"),
            "Expected 100% line before completion; got: \(output.debugDescription)"
        )
        XCTAssertTrue(
            output.contains("Download complete: test/model"),
            "Completion line missing; got: \(output.debugDescription)"
        )
    }

    // MARK: - TTY Output Tests

    /// In TTY mode, `reportProgress` uses the ANSI redraw sequence `\r\u{1B}[K`.
    func testTTY_UsesANSIRedrawSequence() async throws {
        let renderer = ProgressRenderer(quiet: false, isTTY: true)
        let output = try await capture(fd: STDOUT_FILENO) {
            await renderer.reportProgress(0.5)
        }

        XCTAssertTrue(
            output.contains("\r\u{1B}[K"),
            "TTY path must use \\r\\u{1B}[K redraw sequence; got: \(output.debugDescription)"
        )
        XCTAssertTrue(
            output.contains("Download progress: 50%"),
            "TTY output should contain the percentage; got: \(output.debugDescription)"
        )
    }

    /// In TTY mode, `reportCompletion` clears the line and writes the completion message.
    func testTTY_CompletionClearsLine() async throws {
        let renderer = ProgressRenderer(quiet: false, isTTY: true)
        let output = try await capture(fd: STDOUT_FILENO) {
            await renderer.reportCompletion(modelId: "test/model")
        }

        XCTAssertTrue(
            output.contains("\r\u{1B}[K"),
            "TTY completion must use \\r\\u{1B}[K; got: \(output.debugDescription)"
        )
        XCTAssertTrue(
            output.contains("Download complete: test/model"),
            "Completion line missing; got: \(output.debugDescription)"
        )
    }

    // MARK: - Quiet Mode Tests

    /// When `quiet: true`, no lines should be emitted to stdout.
    func testQuiet_SuppressesProgressOutput() async throws {
        let renderer = ProgressRenderer(quiet: true, isTTY: false)
        let output = try await capture(fd: STDOUT_FILENO) {
            await renderer.reportProgress(0.0)
            await renderer.reportProgress(0.5)
            await renderer.reportProgress(1.0)
            await renderer.reportCompletion(modelId: "test/model")
        }

        XCTAssertTrue(
            output.isEmpty,
            "Quiet mode must suppress all stdout output; got: \(output.debugDescription)"
        )
    }

    /// When `quiet: true`, `logStartup` must not write anything to stderr.
    func testQuiet_SuppressesLogStartup() async throws {
        let renderer = ProgressRenderer(quiet: true)
        let stderrOutput = try await capture(fd: STDERR_FILENO) {
            await renderer.logStartup("[bruja] SharedModels: /tmp/test")
        }

        XCTAssertTrue(
            stderrOutput.isEmpty,
            "Quiet mode must suppress logStartup output to stderr; got: \(stderrOutput.debugDescription)"
        )
    }

    // MARK: - logStartup Tests

    /// `logStartup` writes to stderr (not stdout) when not in quiet mode.
    func testLogStartup_WritesToStderr() async throws {
        let renderer = ProgressRenderer(quiet: false)

        // Capture stdout — logStartup should write nothing there.
        let stdoutOutput = try await capture(fd: STDOUT_FILENO) {
            await renderer.logStartup("[bruja] SharedModels: /tmp/test")
        }
        XCTAssertTrue(
            stdoutOutput.isEmpty,
            "logStartup must not write to stdout; got: \(stdoutOutput.debugDescription)"
        )

        // Capture stderr — logStartup should write the message there.
        let stderrOutput = try await capture(fd: STDERR_FILENO) {
            await renderer.logStartup("[bruja] SharedModels: /tmp/test")
        }
        XCTAssertTrue(
            stderrOutput.contains("[bruja] SharedModels: /tmp/test"),
            "logStartup must write to stderr; got: \(stderrOutput.debugDescription)"
        )
    }

    // MARK: - makeProgressCallback Tests

    /// `makeProgressCallback()` returns a callable `@Sendable` closure.
    func testMakeProgressCallback_IsCallable() async throws {
        let renderer = ProgressRenderer(quiet: true)
        let callback = await renderer.makeProgressCallback()

        // Should be callable without crashing.
        callback(0.5)

        // Give the internal Task a chance to complete.
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    /// The callback produced by `makeProgressCallback()` is `@Sendable` and safe for
    /// concurrent invocation. This is also a compile-time Sendable-conformance check.
    func testMakeProgressCallback_IsSendableAndConcurrentlySafe() async {
        let renderer = ProgressRenderer(quiet: true)
        let callback: @Sendable (Double) -> Void = await renderer.makeProgressCallback()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    callback(Double(i) / 20.0)
                }
            }
        }
        // If we reach here without crashing or data races (under TSan), the test passes.
    }
}
