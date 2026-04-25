import Foundation
import SwiftAcervo

/// Thin wrapper around SwiftAcervo for model download and discovery.
/// Does NOT load models — only ensures files are present at known paths.
public actor BrujaDownloadManager {

  public static let shared = BrujaDownloadManager()

  private init() {}

  /// Shared models directory (~/Library/SharedModels/)
  public nonisolated var modelsDirectory: URL {
    Acervo.sharedModelsDirectory
  }

  /// Get local directory for a model ID
  public nonisolated func modelDirectory(for modelId: String) throws -> URL {
    try Acervo.modelDirectory(for: modelId)
  }

  /// Check if a model is available locally
  public nonisolated func isModelAvailable(_ modelId: String) -> Bool {
    Acervo.isModelAvailable(modelId)
  }

  /// Download a model if not already available
  ///
  /// Downloads models from the CDN using SwiftAcervo. Progress is reported as a value
  /// between 0.0 and 1.0, suitable for displaying percentage (progress * 100).
  ///
  /// - Parameters:
  ///   - modelId: The HuggingFace model ID or component ID to download
  ///   - force: If true, delete and re-download even if model already exists
  ///   - progress: Closure called with download progress (0.0-1.0)
  public func downloadModel(
    _ modelId: String,
    force: Bool = false,
    progress: (@Sendable (Double) -> Void)? = nil
  ) async throws {
    if force {
      try? Acervo.deleteModel(modelId)
    }

    // Ensure model is available via CDN, with progress callback
    try await Acervo.ensureAvailable(
      modelId,
      files: []
    ) { acervoProgress in
      progress?(acervoProgress.overallProgress)
    }
  }

  /// Download a model by component ID (e.g., "qwen3-coder-next-4bit")
  ///
  /// This method provides component-based downloading using registered model metadata.
  /// It ensures all files for the component are downloaded and validated.
  ///
  /// - Parameters:
  ///   - componentId: The registered component ID (e.g., "qwen3-coder-next-4bit")
  ///   - force: If true, delete and re-download even if component already exists
  ///   - progress: Closure called with download progress (0.0-1.0)
  /// - Returns: The local path where model is stored
  public func ensureComponentReady(
    _ componentId: String,
    force: Bool = false,
    progress: (@Sendable (Double) -> Void)? = nil
  ) async throws -> URL {
    // Look up component metadata
    guard let component = BrujaModelManager.component(for: componentId) else {
      throw BrujaError.modelNotFound("Component '\(componentId)' not registered")
    }

    // Delete if force re-download requested
    if force {
      try? Acervo.deleteModel(component.repoId)
    }

    // Ensure component is ready via component-aware CDN path (Level 3)
    try await Acervo.ensureComponentReady(componentId) { acervoProgress in
      progress?(acervoProgress.overallProgress)
    }

    // Return the local path where model is stored
    return try Acervo.modelDirectory(for: component.repoId)
  }

  /// List all downloaded models
  public func listModels() throws -> [AcervoModel] {
    try Acervo.listModels()
  }

  /// Get info about a specific model
  public func modelInfo(_ modelId: String) throws -> AcervoModel {
    try Acervo.modelInfo(modelId)
  }

  /// Delete a model from disk
  public func deleteModel(_ modelId: String) throws {
    try Acervo.deleteModel(modelId)
  }

  /// Search for models by name
  public func findModels(matching query: String) throws -> [AcervoModel] {
    try Acervo.findModels(matching: query)
  }

  // MARK: - Pre-flight Manifest API (R4)

  /// Returns the list of CDN manifest files for the given model or component ID.
  ///
  /// Dispatches to the component-aware overload (`Acervo.fetchManifest(forComponent:)`)
  /// when `modelOrComponentId` is a registered component, and falls back to the raw-repoId
  /// overload (`Acervo.fetchManifest(for:)`) for unregistered IDs.
  ///
  /// This method is purely a CDN read — it does NOT download any model files.
  ///
  /// - Parameter modelOrComponentId: Either a registered component ID (e.g.,
  ///   `"qwen3-coder-next-4bit"`) or a raw HuggingFace model ID
  ///   (e.g., `"mlx-community/Qwen2.5-0.5B-Instruct-4bit"`).
  /// - Returns: The array of `CDNManifestFile` entries for the model.
  /// - Throws: `AcervoError` for network, decoding, or integrity failures.
  public nonisolated func manifestFiles(for modelOrComponentId: String) async throws -> [CDNManifestFile] {
    if BrujaModelManager.component(for: modelOrComponentId) != nil {
      // Registered component — use the component-aware overload (looks up repoId internally)
      let manifest = try await Acervo.fetchManifest(forComponent: modelOrComponentId)
      return manifest.files
    } else {
      // Raw model ID — fetch manifest directly by model ID
      let manifest = try await Acervo.fetchManifest(for: modelOrComponentId)
      return manifest.files
    }
  }

  /// Returns the total download size (in bytes) for all files in the CDN manifest of the
  /// given model or component ID.
  ///
  /// Fetches the manifest via `manifestFiles(for:)` and sums `sizeBytes` across all entries.
  /// This method is purely a CDN read — it does NOT download any model files.
  ///
  /// - Parameter modelOrComponentId: Either a registered component ID or a raw
  ///   HuggingFace model ID.
  /// - Returns: The total size in bytes reported by the CDN manifest, or 0 if the
  ///   manifest has no file entries.
  /// - Throws: `AcervoError` for network, decoding, or integrity failures.
  public nonisolated func estimatedSize(for modelOrComponentId: String) async throws -> Int64 {
    try await manifestFiles(for: modelOrComponentId).reduce(0) { $0 + $1.sizeBytes }
  }
}
