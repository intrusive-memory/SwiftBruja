import Foundation
import FoundationModels

/// `glob` — match files by glob pattern under a base directory.
///
/// Walks a base directory recursively and returns all paths whose last path
/// component matches the given glob pattern (e.g. `*.swift`, `*.json`). The
/// match is applied only to the filename, not the full path.
///
/// Returns one absolute path per line, sorted alphabetically. Large results
/// are truncated per the shared policy in ``ToolResult``.
///
/// Working-directory confinement (`PathGuard`) lands in Sortie 4.
@available(macOS 26.0, *)
public struct GlobTool: Tool {

  /// Stable, model-facing tool name.
  public let name = "glob"

  /// Natural-language description the framework injects into the prompt.
  public let description =
    "Find files matching a glob pattern (e.g. '*.swift') under a base directory. "
    + "The pattern is matched against filenames only, not full paths. "
    + "Returns sorted absolute paths."

  /// Arguments accepted by `glob`.
  @Generable
  public struct Arguments {
    /// Glob pattern to match against filenames (e.g. `*.swift`).
    @Guide(description: "The glob pattern to match against filenames (e.g. '*.swift')")
    public var pattern: String

    /// Base directory to search recursively. Tilde (`~`) is expanded.
    @Guide(description: "The base directory to search recursively")
    public var basePath: String
  }

  public init() {}

  /// Find matching files and return a compact result string.
  public func call(arguments: Arguments) async throws -> String {
    let pattern = arguments.pattern
    let basePath = arguments.basePath

    // Working-directory confinement guard (R6.1/R6.2): classify BEFORE touching disk.
    switch PathGuard.classify(basePath) {
    case .allowed(let resolved):
      ToolResult.audit(operation: name, detail: resolved)
    case .escapeRequested(let resolved):
      return ToolResult.escapeRequested(operation: name, resolvedPath: resolved)
    case .denied(let reason):
      return ToolResult.error(reason)
    }

    let expanded = NSString(string: basePath).expandingTildeInPath
    let baseURL = URL(fileURLWithPath: expanded)

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: baseURL.path, isDirectory: &isDirectory) else {
      return ToolResult.error("base path not found: \(basePath)")
    }
    guard isDirectory.boolValue else {
      return ToolResult.error("base path is not a directory: \(basePath)")
    }

    guard
      let enumerator = FileManager.default.enumerator(
        at: baseURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return ToolResult.error("could not enumerate directory: \(basePath)")
    }

    // Collect all items eagerly via `allObjects` to avoid using the enumerator's
    // `makeIterator()`, which is unavailable from async contexts in Swift 6.
    let allItems = enumerator.allObjects.compactMap { $0 as? URL }

    var matches: [String] = []

    for fileURL in allItems {
      guard
        let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
        values.isRegularFile == true
      else { continue }

      let filename = fileURL.lastPathComponent
      if fnmatch(pattern, filename, 0) == 0 {
        matches.append(fileURL.path)
      }
    }

    matches.sort()

    if matches.isEmpty {
      return ToolResult.ok("no files matched '\(pattern)' under \(basePath)")
    }

    return ToolResult.ok(matches.joined(separator: "\n"))
  }
}
