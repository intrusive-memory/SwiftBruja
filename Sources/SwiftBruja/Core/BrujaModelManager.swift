import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import SwiftAcervo

/// Manages loading LLM models into memory for inference.
///
/// Download, list, info, and delete responsibilities are handled by
/// `BrujaDownloadManager` (which delegates to SwiftAcervo). This actor
/// is inference-only: it loads models into `ModelContainer` instances,
/// caches them, validates memory, and supports legacy path migration.
public actor BrujaModelManager {

  /// Shared instance
  public static let shared = BrujaModelManager()

  /// Default model for general use (Qwen3-Coder-Next for coding agent tasks)
  public static let defaultModel = "mlx-community/Qwen3-Coder-Next-4bit"

  /// Storage location for downloaded models (delegates to Acervo)
  public nonisolated var modelsDirectory: URL {
    Acervo.sharedModelsDirectory
  }

  /// Loaded model containers (cached for reuse)
  private var loadedModels: [String: ModelContainer] = [:]

  /// Whether legacy migration has been attempted this session
  private var migrationAttempted = false

  private init() {}

  // MARK: - Migration

  /// Migrate models from legacy cache paths to ~/Library/SharedModels/ (one-shot per session)
  func migrateIfNeeded() {
    guard !migrationAttempted else { return }
    migrationAttempted = true
    do {
      let migrated = try Acervo.migrateFromLegacyPaths()
      if !migrated.isEmpty {
        print("[SwiftBruja] Migrated \(migrated.count) model(s) to ~/Library/SharedModels/")
      }
    } catch {
      print("[SwiftBruja] Warning: legacy migration failed: \(error.localizedDescription)")
    }
  }

  // MARK: - Model Availability

  /// Check if a model is downloaded and available locally
  public nonisolated func isModelAvailable(_ modelId: String) -> Bool {
    Acervo.isModelAvailable(modelId)
  }

  /// Get the local directory for a model
  public nonisolated func modelDirectory(for modelId: String) throws -> URL {
    try Acervo.modelDirectory(for: modelId)
  }

  // MARK: - Model Loading

  /// Load a model into memory for inference
  public func loadModel(_ modelId: String) async throws -> ModelContainer {
    // Run one-shot migration on first load
    migrateIfNeeded()

    // Return cached model if already loaded
    if let cached = loadedModels[modelId] {
      return cached
    }

    // Ensure model is downloaded
    guard isModelAvailable(modelId) else {
      throw BrujaError.modelNotDownloaded(modelId)
    }

    let modelDir = try Acervo.modelDirectory(for: modelId)

    // Validate memory before loading
    let modelSize = (try? Acervo.modelInfo(modelId).sizeBytes) ?? 0
    if modelSize > 0 {
      try BrujaMemory.validateMemoryForModel(sizeBytes: modelSize)
    }

    // Load model using LLMModelFactory
    let modelConfig = ModelConfiguration(directory: modelDir)

    do {
      let container = try await LLMModelFactory.shared.loadContainer(
        configuration: modelConfig
      ) { _ in
        // Progress callback (not used for loading)
      }

      loadedModels[modelId] = container
      return container
    } catch {
      throw BrujaError.modelLoadFailed(error)
    }
  }

  /// Load a model from a specific path
  public func loadModel(from path: URL) async throws -> ModelContainer {
    let modelId = path.lastPathComponent

    // Return cached model if already loaded
    if let cached = loadedModels[modelId] {
      return cached
    }

    // Check model exists
    guard FileManager.default.fileExists(atPath: path.appendingPathComponent("config.json").path)
    else {
      throw BrujaError.modelNotFound(path.path)
    }

    // Validate memory before loading
    let modelSize = try calculateDirectorySize(path)
    try BrujaMemory.validateMemoryForModel(sizeBytes: modelSize)

    // Load model
    let modelConfig = ModelConfiguration(directory: path)

    do {
      let container = try await LLMModelFactory.shared.loadContainer(
        configuration: modelConfig
      ) { _ in }

      loadedModels[modelId] = container
      return container
    } catch {
      throw BrujaError.modelLoadFailed(error)
    }
  }

  /// Unload a model to free memory
  public func unloadModel(_ modelId: String) {
    loadedModels.removeValue(forKey: modelId)
  }

  /// Unload all models
  public func unloadAllModels() {
    loadedModels.removeAll()
  }

  // MARK: - Private Helpers

  /// Calculate directory size (used only for path-based loading where Acervo info is unavailable)
  private nonisolated func calculateDirectorySize(_ url: URL) throws -> Int64 {
    var totalSize: Int64 = 0

    let contents = try FileManager.default.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: [.fileSizeKey],
      options: .skipsHiddenFiles
    )

    for fileURL in contents {
      let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])

      if resourceValues.isDirectory == true {
        totalSize += try calculateDirectorySize(fileURL)
      } else if let fileSize = resourceValues.fileSize {
        totalSize += Int64(fileSize)
      }
    }

    return totalSize
  }
}
