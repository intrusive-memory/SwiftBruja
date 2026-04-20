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

    // Extract model ID from component metadata (use repoId as the identifier)
    let modelId = component.repoId

    // Delete if force re-download requested
    if force {
      try? Acervo.deleteModel(modelId)
    }

    // Ensure model is available from CDN
    try await Acervo.ensureAvailable(
      modelId,
      files: []
    ) { acervoProgress in
      progress?(acervoProgress.overallProgress)
    }

    // Return the local path where model is stored
    return try Acervo.modelDirectory(for: modelId)
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
}
