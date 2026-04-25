import Darwin
import Foundation

// MARK: - ProgressRenderer

/// Renders download progress to stdout and startup messages to stderr.
///
/// Detects TTY once at construction:
/// - **TTY path**: redraws the current line using `\r\u{1B}[K` (preserving existing behavior).
/// - **Non-TTY path**: emits one `Download progress: N%` line per 10-percent increment,
///   newline-terminated, with no ANSI escape sequences (safe for log files and CI).
/// - **`--quiet` mode**: short-circuits both paths and suppresses all output.
///
/// The type is declared as an `actor` to satisfy Swift 6 `Sendable` requirements;
/// the download progress callback can safely `await` methods on the actor from
/// any concurrency context.
public actor ProgressRenderer {

    // MARK: - Properties

    /// Whether stdout is connected to a real terminal.
    private let isTTY: Bool

    /// Whether `--quiet` was requested; suppresses all progress output when true.
    private let quiet: Bool

    /// Last 10-percent bucket emitted on the non-TTY path.
    /// Prevents duplicate lines when progress events fire rapidly.
    private var lastEmittedBucket: Int = -1

    // MARK: - Initialisation

    /// Creates a renderer, auto-detecting whether stdout is a TTY.
    ///
    /// - Parameter quiet: Pass `true` to suppress all progress and startup output.
    public init(quiet: Bool = false) {
        self.quiet = quiet
        // Detect TTY once at construction time — never changes for the lifetime of the process.
        //
        // Implementation note: we use TIOCGWINSZ (get terminal window size ioctl) rather than
        // isatty(), fstat(S_IFCHR), or tcgetattr() because Apple-framework-linked binaries
        // (linked against Metal, AVFoundation, etc.) on macOS 26.x can cause those checks to
        // return incorrect results for redirected/piped file descriptors. TIOCGWINSZ only
        // succeeds (ws_col > 0) on real terminal windows; pipes, files, and GPU/audio char
        // devices all fail this check.
        var windowSize = winsize()
        let ioctlResult = ioctl(STDOUT_FILENO, TIOCGWINSZ, &windowSize)
        self.isTTY = (ioctlResult == 0 && windowSize.ws_col > 0)
    }

    /// Creates a renderer with an explicit TTY override.
    ///
    /// This initialiser is intended for **testing only** — it lets tests exercise
    /// the non-TTY code path regardless of whether the test runner has a pseudo-TTY
    /// attached to stdout (which xcodebuild / XCTest typically does).
    ///
    /// - Parameters:
    ///   - quiet: Pass `true` to suppress all progress and startup output.
    ///   - isTTY: Explicitly set whether to use the TTY (ANSI-redraw) path.
    public init(quiet: Bool = false, isTTY: Bool) {
        self.quiet = quiet
        self.isTTY = isTTY
    }

    // MARK: - Progress Rendering

    /// Reports download progress.
    ///
    /// - Parameter fraction: A value in `[0.0, 1.0]` representing overall progress.
    public func reportProgress(_ fraction: Double) {
        guard !quiet else { return }

        let clamped = max(0.0, min(1.0, fraction))
        let percentage = Int(clamped * 100)

        if isTTY {
            // Redraw the current line — preserve the exact byte sequence from the
            // original DownloadCommand.run so downstream tooling keeps working.
            print("\r\u{1B}[KDownload progress: \(percentage)%", terminator: "")
            fflush(stdout)
        } else {
            // Non-TTY: emit one line per 10-percent bucket, no ANSI escapes.
            let bucket = (percentage / 10) * 10  // 0, 10, 20, …, 100
            if bucket > lastEmittedBucket {
                lastEmittedBucket = bucket
                print("Download progress: \(bucket)%")
                fflush(stdout)
            }
        }
    }

    /// Emits the "download complete" message, clearing the TTY progress line first.
    ///
    /// - Parameter modelId: The model identifier, displayed in the completion message.
    public func reportCompletion(modelId: String) {
        guard !quiet else { return }

        if isTTY {
            // Clear the progress line before printing the final message.
            print("\r\u{1B}[KDownload complete: \(modelId)")
        } else {
            // On non-TTY, ensure 100% was emitted, then print completion.
            if lastEmittedBucket < 100 {
                lastEmittedBucket = 100
                print("Download progress: 100%")
            }
            print("Download complete: \(modelId)")
        }
        fflush(stdout)
    }

    /// Emits a startup/informational message to **stderr**, honoring `--quiet`.
    ///
    /// This method is intentionally written to **stderr** so that JSON stdout
    /// output (`--json` flag on `query`) remains machine-parseable. Sortie 7
    /// (R5) will call this from every subcommand to emit the
    /// `[bruja] SharedModels:` self-diagnostic line.
    ///
    /// - Parameter message: The message to emit.
    public func logStartup(_ message: String) {
        guard !quiet else { return }
        var standardError = StandardErrorOutputStream()
        print(message, to: &standardError)
    }
}

// MARK: - Sendable Closure Bridge

extension ProgressRenderer {
    /// Returns a `@Sendable` closure suitable for use as a progress callback in
    /// `Acervo.ensureAvailable(_:files:progress:)` and similar async APIs.
    ///
    /// The closure captures `self` (the actor) and schedules each update as an
    /// unstructured `Task` so it does not block the download engine's calling context.
    ///
    /// - Returns: A `@Sendable` closure that accepts a `Double` fraction `[0, 1]`.
    public nonisolated func makeProgressCallback() -> @Sendable (Double) -> Void {
        return { [weak self] fraction in
            guard let self else { return }
            Task {
                await self.reportProgress(fraction)
            }
        }
    }
}

// MARK: - StandardErrorOutputStream

/// A `TextOutputStream` that writes to file descriptor 2 (stderr).
struct StandardErrorOutputStream: TextOutputStream {
    mutating func write(_ string: String) {
        let stderr = FileHandle.standardError
        guard let data = string.data(using: .utf8) else { return }
        stderr.write(data)
    }
}
