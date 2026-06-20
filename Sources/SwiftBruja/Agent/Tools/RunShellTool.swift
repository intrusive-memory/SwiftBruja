import Foundation
import FoundationModels

/// `run_shell` — execute a shell command and return stdout / stderr / exit code.
///
/// Runs the given command string through `/bin/zsh -c` and returns a compact result
/// string containing the exit code, stdout, and stderr so the model can reason about
/// the output. Both stdout and stderr are captured separately and appended to the result.
///
/// Large outputs are truncated per the shared policy in ``ToolResult``.
///
/// **Security note**: this tool executes arbitrary shell commands. Working-directory
/// confinement (`PathGuard`) for the shell path is best-effort and lands in Sortie 4.
@available(macOS 26.0, *)
public struct RunShellTool: Tool {

  /// Stable, model-facing tool name.
  public let name = "run_shell"

  /// Natural-language description the framework injects into the prompt.
  public let description =
    "Run a shell command and return its exit code, stdout, and stderr as text. "
    + "Use for build commands, test runners, git operations, or any executable action."

  /// Arguments accepted by `run_shell`.
  @Generable
  public struct Arguments {
    /// The shell command to execute (passed to `/bin/zsh -c`).
    @Guide(description: "The shell command string to execute")
    public var command: String

    /// Optional working directory for the command. Tilde (`~`) is expanded.
    @Guide(description: "Optional working directory path; defaults to the process current directory")
    public var workingDirectory: String?
  }

  public init() {}

  /// Execute the command and return a compact result string with exit code + output.
  public func call(arguments: Arguments) async throws -> String {
    // Copy needed fields out of the non-Sendable Arguments before crossing any
    // isolation boundary (matches the S2 pattern for Sendable correctness).
    let command = arguments.command
    let workingDirectory = arguments.workingDirectory

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-c", command]

    if let wd = workingDirectory {
      let expanded = NSString(string: wd).expandingTildeInPath
      process.currentDirectoryURL = URL(fileURLWithPath: expanded)
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
      try process.run()
    } catch {
      return ToolResult.error("could not launch command '\(command)': \(error.localizedDescription)")
    }

    process.waitUntilExit()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
    let stderr = String(data: stderrData, encoding: .utf8) ?? ""
    let exitCode = process.terminationStatus

    var parts: [String] = ["exit_code: \(exitCode)"]
    if !stdout.isEmpty {
      parts.append("stdout:\n\(stdout)")
    }
    if !stderr.isEmpty {
      parts.append("stderr:\n\(stderr)")
    }

    let combined = parts.joined(separator: "\n")
    return ToolResult.ok(combined)
  }
}
