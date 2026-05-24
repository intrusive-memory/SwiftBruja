import ArgumentParser
import Foundation
import SwiftAcervo

// MARK: - CLIError

/// A CLI-layer error that carries a pre-formatted, human-readable message.
///
/// `CLIError` is the exit vehicle for errors that have already been translated
/// into user-facing prose. Throwing one from a subcommand's `run()` method
/// causes `runCLI` to print the message to stderr and exit non-zero, without
/// ArgumentParser appending its own (often cryptic) diagnostic text.
public struct CLIError: Error, CustomStringConvertible {
  /// The user-facing message, ready for display on stderr.
  public let message: String

  public init(_ message: String) {
    self.message = message
  }

  public var description: String { message }
}

// MARK: - runCLI wrapper

/// Executes `body` and translates any thrown `AcervoError` (or other `Error`)
/// into a user-readable stderr line followed by a non-zero exit.
///
/// Usage:
/// ```swift
/// func run() async throws {
///     try await runCLI {
///         // ... subcommand logic ...
///     }
/// }
/// ```
///
/// - Parameter body: The async throwing closure that contains the subcommand logic.
/// - Throws: `ExitCode.failure` (after printing to stderr) when an error is caught,
///           or rethrows any error that is already an `ExitCode` or `CLIError`.
@discardableResult
public func runCLI<T>(_ body: () async throws -> T) async throws -> T {
  do {
    return try await body()
  } catch let exitCode as ExitCode {
    // Already an ArgumentParser exit — let it propagate unchanged.
    throw exitCode
  } catch let cliError as CLIError {
    // Already formatted — print and exit.
    printStderr("Error: \(cliError.message)")
    throw ExitCode.failure
  } catch let acervoError as AcervoError {
    printStderr(humanReadable(acervoError))
    throw ExitCode.failure
  } catch {
    printStderr("Error: \(error.localizedDescription)")
    throw ExitCode.failure
  }
}

// MARK: - humanReadable

/// Returns a user-facing error string for every currently-shipping `AcervoError` case.
///
/// The messages are deliberately concise and actionable. The `@unknown default` branch
/// guards against future cases added to `AcervoError` without requiring a recompile.
public func humanReadable(_ error: AcervoError) -> String {
  switch error {
  case .modelNotFound(let modelId):
    return "Error: Model '\(modelId)' is not published on the CDN."

  case .manifestDownloadFailed(let statusCode):
    return
      "Error: Failed to download the CDN manifest (HTTP \(statusCode)). Check your network connection and try again."

  case .manifestIntegrityFailed(let expected, let actual):
    return
      "Error: CDN manifest integrity check failed (expected '\(expected)', got '\(actual)'). The manifest may be corrupted; try again."

  case .downloadFailed(let fileName, let statusCode):
    return
      "Error: Download failed for '\(fileName)' (HTTP \(statusCode)). Check your network connection and try again."

  case .integrityCheckFailed(let file, let expected, let actual):
    return
      "Error: Integrity check failed for '\(file)' (expected SHA-256 '\(expected)', got '\(actual)'). The file may be corrupted; try re-downloading."

  case .downloadSizeMismatch(let fileName, let expected, let actual):
    return
      "Error: Downloaded file '\(fileName)' has unexpected size (expected \(expected) bytes, got \(actual) bytes). Try re-downloading."

  case .fileNotInManifest(let fileName, let modelId):
    return "Error: File '\(fileName)' is not listed in the CDN manifest for '\(modelId)'."

  case .componentNotRegistered(let componentId):
    return
      "Error: Component '\(componentId)' is not registered. Use 'bruja list' to see available components."

  case .directoryCreationFailed(let path):
    return "Error: Failed to create directory at '\(path)'. Check permissions and try again."

  case .networkError(let underlying):
    return "Error: Network error: \(underlying.localizedDescription)"

  case .modelAlreadyExists(let modelId):
    return "Error: Model '\(modelId)' already exists locally. Use --force to re-download."

  case .invalidModelId(let modelId):
    return
      "Error: Invalid model ID '\(modelId)'. Expected format: 'org/repo' (e.g., mlx-community/Llama-3.2-1B-Instruct-4bit)."

  case .componentNotDownloaded(let componentId):
    return
      "Error: Component '\(componentId)' has not been downloaded. Run 'bruja download -m \(componentId)' first."

  case .componentFileNotFound(let component, let file):
    return
      "Error: File '\(file)' not found in component '\(component)'. Try re-downloading the model."

  case .manifestDecodingFailed(let underlying):
    return "Error: Failed to decode CDN manifest: \(underlying.localizedDescription)"

  case .manifestVersionUnsupported(let version):
    return
      "Error: CDN manifest version \(version) is not supported by this version of bruja. Please update bruja."

  case .manifestModelIdMismatch(let expected, let actual):
    return
      "Error: CDN manifest model ID mismatch (expected '\(expected)', got '\(actual)'). The manifest may be for a different model."

  case .localPathNotFound(let url):
    return "Error: Local path not found: '\(url.path)'."

  @unknown default:
    return "Error: Unexpected error: \(error)"
  }
}

// MARK: - Private helpers

/// Writes `message` to stderr, followed by a newline.
private func printStderr(_ message: String) {
  var stderr = StandardErrorWriter()
  print(message, to: &stderr)
}

/// A `TextOutputStream` that writes directly to file descriptor 2 (stderr).
private struct StandardErrorWriter: TextOutputStream {
  mutating func write(_ string: String) {
    guard let data = string.data(using: .utf8) else { return }
    FileHandle.standardError.write(data)
  }
}
