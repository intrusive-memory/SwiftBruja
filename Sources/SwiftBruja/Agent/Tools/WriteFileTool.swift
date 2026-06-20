import Foundation
import FoundationModels

/// `write_file` — write text content to a path on disk.
///
/// Creates or overwrites the file at the given path with the supplied content.
/// Intermediate directories are NOT created automatically; the parent directory
/// must already exist. Returns a compact confirmation string on success.
///
/// Working-directory confinement (`PathGuard`) lands in Sortie 4.
@available(macOS 26.0, *)
public struct WriteFileTool: Tool {

  /// Stable, model-facing tool name.
  public let name = "write_file"

  /// Natural-language description the framework injects into the prompt.
  public let description =
    "Write text content to a file at the given path, creating it or overwriting it. "
    + "The parent directory must already exist."

  /// Arguments accepted by `write_file`.
  @Generable
  public struct Arguments {
    /// Filesystem path to write. Tilde (`~`) is expanded.
    @Guide(description: "The filesystem path of the file to write or overwrite")
    public var path: String

    /// Text content to write.
    @Guide(description: "The text content to write to the file")
    public var content: String
  }

  public init() {}

  /// Write the file and return a compact result string.
  public func call(arguments: Arguments) async throws -> String {
    let path = arguments.path
    let content = arguments.content

    let expanded = NSString(string: path).expandingTildeInPath
    let url = URL(fileURLWithPath: expanded)

    do {
      try content.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      return ToolResult.error(
        "could not write file '\(path)': \(error.localizedDescription)")
    }

    return ToolResult.ok("written \(content.count) characters to \(path)")
  }
}
