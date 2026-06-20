import Foundation
import FoundationModels

/// The single source of truth for the agent's tool set.
///
/// `ToolRegistry` yields the one `[any Tool]` array that **both** backends consume — the MLX
/// `LanguageModelExecutor` path (Sortie 2+) and the Foundation Models path (Sortie 9) — so tools
/// are defined exactly once (R4.1). There is no second per-backend tool adapter.
///
/// For Sortie 1 the registry exposes only ``ReadFileTool``. Later sorties (S3) add the rest of the
/// suite (`run_shell`, `write_file`, `edit_file`, `list_dir`, `grep`, `glob`, …) by extending
/// ``defaultTools``.
///
/// Availability: gated to macOS 26.0+ because `Tool` is 26.0+. The 27.0+ executor seam that drives
/// these tools is established separately in Sortie 2.
@available(macOS 26.0, *)
public enum ToolRegistry {

  /// The complete set of tools exposed to a `LanguageModelSession`.
  ///
  /// Both backends call this to obtain their `tools:` array, guaranteeing identical tool surfaces.
  ///
  /// Registered tools (S1 + S3):
  /// - ``ReadFileTool`` (`read_file`) — read a file's text content
  /// - ``RunShellTool`` (`run_shell`) — run a shell command; return stdout/stderr/exit code
  /// - ``WriteFileTool`` (`write_file`) — write content to a path
  /// - ``EditFileTool`` (`edit_file`) — replace an old string with a new string in a file
  /// - ``ListDirTool`` (`list_dir`) — list a directory's immediate children
  /// - ``GrepTool`` (`grep`) — search file contents for a pattern
  /// - ``GlobTool`` (`glob`) — match files by glob pattern under a base directory
  ///
  /// - Returns: The registered tools as an `[any Tool]`.
  public static func defaultTools() -> [any Tool] {
    [
      ReadFileTool(),
      RunShellTool(),
      WriteFileTool(),
      EditFileTool(),
      ListDirTool(),
      GrepTool(),
      GlobTool(),
    ]
  }
}
