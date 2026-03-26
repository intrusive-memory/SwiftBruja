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
  public func downloadModel(
    _ modelId: String,
    force: Bool = false,
    progress: (@Sendable (Double) -> Void)? = nil
  ) async throws {
    if force {
      try? Acervo.deleteModel(modelId)
    }
    try await Acervo.ensureAvailable(
      modelId,
      files: []
    ) { acervoProgress in
      progress?(acervoProgress.overallProgress)
    }
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
