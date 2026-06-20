import Foundation
import FoundationModels

/// `read_file` — the first agent tool, conforming to `FoundationModels.Tool`.
///
/// Reads a file from disk and returns its contents as a compact result string. This is
/// the proof that a single `@Generable`-argument tool definition (`Arguments`) feeds the
/// `FoundationModels` tool-calling seam consumed by both backends (MLX + Foundation Models).
///
/// A missing or unreadable file returns a **typed error string** (see ``ToolResult/error(_:)``)
/// rather than throwing an uncaught error or crashing — the model can recover from a bad path.
///
/// Working-directory confinement (`PathGuard`) is intentionally **not** wired here; it lands in
/// Sortie 4 and will be inserted before the disk read. For S1 the tool reads any readable path.
///
/// Availability: the `Tool` protocol and `@Generable` are macOS 26.0+. The executor seam that
/// drives MLX behind this tool is the macOS 27.0+ part (Sortie 2); this tool itself only needs 26.0.
@available(macOS 26.0, *)
public struct ReadFileTool: Tool {

  /// Stable, model-facing tool name. snake_case to match the tool-suite naming convention.
  public let name = "read_file"

  /// Natural-language description the framework injects into the prompt so the model
  /// knows when to call this tool.
  public let description =
    "Read the contents of a file at the given path and return it as text. "
    + "Use this to inspect source files, configuration, or any readable text file."

  /// Arguments accepted by `read_file`.
  @Generable
  public struct Arguments {
    /// Filesystem path to the file to read. Tilde (`~`) is expanded.
    @Guide(description: "The filesystem path of the file to read")
    public var path: String
  }

  public init() {}

  /// Read the file and return a compact result string.
  ///
  /// - Returns: The file's contents on success (truncated per the shared policy), or a
  ///   typed error string when the file is missing, is a directory, or cannot be decoded.
  public func call(arguments: Arguments) async throws -> String {
    // Working-directory confinement guard (R6.1/R6.2): classify BEFORE touching disk.
    switch PathGuard.classify(arguments.path) {
    case .allowed(let resolved):
      ToolResult.audit(operation: name, detail: resolved)
    case .escapeRequested(let resolved):
      return ToolResult.escapeRequested(operation: name, resolvedPath: resolved)
    case .denied(let reason):
      return ToolResult.error(reason)
    }

    let expanded = NSString(string: arguments.path).expandingTildeInPath
    let url = URL(fileURLWithPath: expanded)

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return ToolResult.error("file not found: \(arguments.path)")
    }
    if isDirectory.boolValue {
      return ToolResult.error("path is a directory, not a file: \(arguments.path)")
    }

    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      return ToolResult.error("could not read file '\(arguments.path)': \(error.localizedDescription)")
    }

    guard let contents = String(data: data, encoding: .utf8) else {
      return ToolResult.error("file is not valid UTF-8 text: \(arguments.path)")
    }

    return ToolResult.ok(contents)
  }
}
