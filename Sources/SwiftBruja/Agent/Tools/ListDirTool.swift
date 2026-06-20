import Foundation
import FoundationModels

/// `list_dir` — list the contents of a directory.
///
/// Returns a newline-separated listing of the directory's immediate children
/// (not recursive). Each entry is suffixed with `/` if it is itself a directory.
/// Hidden files (names starting with `.`) are included.
///
/// Large listings are truncated per the shared policy in ``ToolResult``.
///
/// Working-directory confinement (`PathGuard`) lands in Sortie 4.
@available(macOS 26.0, *)
public struct ListDirTool: Tool {

  /// Stable, model-facing tool name.
  public let name = "list_dir"

  /// Natural-language description the framework injects into the prompt.
  public let description =
    "List the contents of a directory. Returns each entry on its own line, "
    + "with a trailing '/' for subdirectories. Hidden files are included."

  /// Arguments accepted by `list_dir`.
  @Generable
  public struct Arguments {
    /// Filesystem path of the directory to list. Tilde (`~`) is expanded.
    @Guide(description: "The filesystem path of the directory to list")
    public var path: String
  }

  public init() {}

  /// List the directory and return a compact result string.
  public func call(arguments: Arguments) async throws -> String {
    let path = arguments.path

    // Working-directory confinement guard (R6.1/R6.2): classify BEFORE touching disk.
    switch PathGuard.classify(path) {
    case .allowed(let resolved):
      ToolResult.audit(operation: name, detail: resolved)
    case .escapeRequested(let resolved):
      return ToolResult.escapeRequested(operation: name, resolvedPath: resolved)
    case .denied(let reason):
      return ToolResult.error(reason)
    }

    let expanded = NSString(string: path).expandingTildeInPath
    let url = URL(fileURLWithPath: expanded)

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return ToolResult.error("path not found: \(path)")
    }
    guard isDirectory.boolValue else {
      return ToolResult.error("path is a file, not a directory: \(path)")
    }

    let entries: [String]
    do {
      entries = try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    } catch {
      return ToolResult.error(
        "could not list directory '\(path)': \(error.localizedDescription)")
    }

    if entries.isEmpty {
      return ToolResult.ok("(empty directory)")
    }

    let lines: [String] = entries.map { entry in
      var isDir: ObjCBool = false
      let child = url.appendingPathComponent(entry).path
      FileManager.default.fileExists(atPath: child, isDirectory: &isDir)
      return isDir.boolValue ? "\(entry)/" : entry
    }

    return ToolResult.ok(lines.joined(separator: "\n"))
  }
}
