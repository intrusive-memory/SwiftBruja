import Foundation
import FoundationModels

/// `grep` — search file contents for a pattern.
///
/// Searches a single file (or recursively under a directory) for lines matching
/// the given pattern. The pattern is treated as a literal string by default;
/// pass `isRegex: true` to enable basic regular expression matching (via
/// `NSRegularExpression`).
///
/// Returns matching lines prefixed with their 1-based line number and (when
/// searching recursively) their file path. Large outputs are truncated per
/// the shared policy in ``ToolResult``.
///
/// Working-directory confinement (`PathGuard`) lands in Sortie 4.
@available(macOS 26.0, *)
public struct GrepTool: Tool {

  /// Stable, model-facing tool name.
  public let name = "grep"

  /// Natural-language description the framework injects into the prompt.
  public let description =
    "Search file contents for lines matching a pattern. "
    + "Provide a path to a file or directory (recursive). "
    + "Set isRegex to true to interpret the pattern as a regular expression."

  /// Arguments accepted by `grep`.
  @Generable
  public struct Arguments {
    /// The search pattern (literal string or regex if `isRegex` is true).
    @Guide(description: "The search pattern to look for in file contents")
    public var pattern: String

    /// Filesystem path to search — file or directory. Tilde (`~`) is expanded.
    @Guide(description: "The file or directory path to search")
    public var path: String

    /// When `true`, treat `pattern` as a basic regular expression.
    @Guide(description: "Whether to interpret the pattern as a regular expression (default: false)")
    public var isRegex: Bool?
  }

  public init() {}

  /// Search and return a compact result string of matching lines.
  public func call(arguments: Arguments) async throws -> String {
    let pattern = arguments.pattern
    let path = arguments.path
    let useRegex = arguments.isRegex ?? false

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

    guard FileManager.default.fileExists(atPath: url.path) else {
      return ToolResult.error("path not found: \(path)")
    }

    var isDirectory: ObjCBool = false
    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

    var filesToSearch: [URL] = []
    if isDirectory.boolValue {
      filesToSearch = collectTextFiles(under: url)
    } else {
      filesToSearch = [url]
    }

    var allMatches: [String] = []

    for fileURL in filesToSearch {
      guard let fileContent = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
      let lines = fileContent.components(separatedBy: "\n")
      let showPath = isDirectory.boolValue

      for (index, line) in lines.enumerated() {
        let matched: Bool
        if useRegex {
          matched = matchesRegex(pattern: pattern, in: line)
        } else {
          matched = line.contains(pattern)
        }
        if matched {
          let lineNum = index + 1
          if showPath {
            allMatches.append("\(fileURL.path):\(lineNum):\(line)")
          } else {
            allMatches.append("\(lineNum):\(line)")
          }
        }
      }
    }

    if allMatches.isEmpty {
      return ToolResult.ok("no matches found for '\(pattern)' in \(path)")
    }

    return ToolResult.ok(allMatches.joined(separator: "\n"))
  }

  // MARK: - Private helpers

  private func collectTextFiles(under directory: URL) -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else { return [] }

    // Use `allObjects` to avoid makeIterator() which is unavailable in async contexts.
    let allItems = enumerator.allObjects.compactMap { $0 as? URL }
    return allItems.filter { fileURL in
      let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
      return values?.isRegularFile == true
    }.sorted { $0.path < $1.path }
  }

  private func matchesRegex(pattern: String, in line: String) -> Bool {
    guard
      let regex = try? NSRegularExpression(pattern: pattern, options: [])
    else { return false }
    let range = NSRange(line.startIndex..., in: line)
    return regex.firstMatch(in: line, options: [], range: range) != nil
  }
}
