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
  /// - Returns: The registered tools as an `[any Tool]`.
  public static func defaultTools() -> [any Tool] {
    [
      ReadFileTool()
      // S3 appends the remaining built-in tools here.
    ]
  }
}
