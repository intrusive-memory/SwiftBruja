import Foundation
import FoundationModels

/// `edit_file` — replace an exact string in a file with a new string.
///
/// Reads the file at the given path, performs a single string substitution
/// (replacing the first occurrence of `oldString` with `newString`), and writes
/// the result back. Returns a compact confirmation string on success.
///
/// The substitution is an exact, literal match — no regex. If `oldString` does not
/// appear in the file, the tool returns a typed error string so the model can retry
/// with a corrected match string.
///
/// Working-directory confinement (`PathGuard`) lands in Sortie 4.
@available(macOS 26.0, *)
public struct EditFileTool: Tool {

  /// Stable, model-facing tool name.
  public let name = "edit_file"

  /// Natural-language description the framework injects into the prompt.
  public let description =
    "Replace an exact string in a file with a new string. "
    + "Reads the file, substitutes the first occurrence of oldString with newString, "
    + "and writes the result back. Returns an error if oldString is not found."

  /// Arguments accepted by `edit_file`.
  @Generable
  public struct Arguments {
    /// Filesystem path to the file to edit. Tilde (`~`) is expanded.
    @Guide(description: "The filesystem path of the file to edit")
    public var path: String

    /// The exact string to search for (literal, not regex).
    @Guide(description: "The exact string to find and replace")
    public var oldString: String

    /// The replacement string.
    @Guide(description: "The string to substitute in place of oldString")
    public var newString: String
  }

  public init() {}

  /// Perform the edit and return a compact result string.
  public func call(arguments: Arguments) async throws -> String {
    let path = arguments.path
    let oldString = arguments.oldString
    let newString = arguments.newString

    let expanded = NSString(string: path).expandingTildeInPath
    let url = URL(fileURLWithPath: expanded)

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return ToolResult.error("file not found: \(path)")
    }
    if isDirectory.boolValue {
      return ToolResult.error("path is a directory, not a file: \(path)")
    }

    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      return ToolResult.error("could not read file '\(path)': \(error.localizedDescription)")
    }

    guard let original = String(data: data, encoding: .utf8) else {
      return ToolResult.error("file is not valid UTF-8 text: \(path)")
    }

    guard original.contains(oldString) else {
      return ToolResult.error(
        "oldString not found in '\(path)'; no edit performed — check your match string")
    }

    let edited = original.replacingOccurrences(of: oldString, with: newString, range: original.startIndex..<original.endIndex)

    do {
      try edited.write(to: url, atomically: true, encoding: .utf8)
    } catch {
      return ToolResult.error("could not write edited file '\(path)': \(error.localizedDescription)")
    }

    let delta = edited.count - original.count
    let sign = delta >= 0 ? "+" : ""
    return ToolResult.ok("edited '\(path)': replaced 1 occurrence (\(sign)\(delta) chars)")
  }
}
