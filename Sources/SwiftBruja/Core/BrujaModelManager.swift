import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXLMTokenizers
import SwiftAcervo

// MARK: - BrujaModelManager

/// Manages loading LLM models into memory for inference.
///
/// Download, list, info, and delete responsibilities are handled by
/// `Acervo` (SwiftAcervo) directly. This actor is inference-only: it
/// loads models into `ModelContainer` instances, caches them, validates
/// memory, and supports legacy path migration.
public actor BrujaModelManager {

  /// Shared instance
  public static let shared = BrujaModelManager()

  /// Default model for general use (Llama 3.2 1B for lightweight instruction following)
  public static let defaultModel = "mlx-community/Llama-3.2-1B-Instruct-4bit"

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

  /// Migrate models from legacy cache paths to ~/Library/SharedModels/ (one-shot per session).
  ///
  /// Status messages go to stderr so they don't corrupt `--json` stdout from `bruja query`.
  func migrateIfNeeded() {
    guard !migrationAttempted else { return }
    migrationAttempted = true
    do {
      let migrated = try Acervo.migrateFromLegacyPaths()
      if !migrated.isEmpty {
        FileHandle.standardError.write(
          Data("[SwiftBruja] Migrated \(migrated.count) model(s) to ~/Library/SharedModels/\n".utf8)
        )
      }
    } catch {
      FileHandle.standardError.write(
        Data("[SwiftBruja] Warning: legacy migration failed: \(error.localizedDescription)\n".utf8)
      )
    }
  }

  // MARK: - Model Availability

  /// Check if a model is downloaded and available locally
  public nonisolated func isModelAvailable(_ modelId: String) -> Bool {
    Acervo.isModelAvailable(modelId)
  }

  // MARK: - Model Loading

  /// Load a model into memory for inference.
  ///
  /// Loads the specified model from its downloaded location and caches the
  /// container for reuse. Models must be downloaded first via `Acervo.ensureAvailable`
  /// or `Acervo.ensureComponentReady`.
  public func loadModel(_ modelId: String) async throws -> ModelContainer {
    // Run one-shot migration on first load
    migrateIfNeeded()

    // Return cached model if already loaded
    if let cached = loadedModels[modelId] {
      return cached
    }

    // Verify model is available locally
    guard isModelAvailable(modelId) else {
      throw BrujaError.modelNotFound(
        "Model '\(modelId)' not found at \(Acervo.sharedModelsDirectory.path). Ensure it is pre-downloaded."
      )
    }

    // Get model directory and load
    let modelDir = try Acervo.modelDirectory(for: modelId)

    // Validate memory before loading
    let modelSize = (try? Acervo.modelInfo(modelId).sizeBytes) ?? 0
    if modelSize > 0 {
      try BrujaMemory.validateMemoryForModel(sizeBytes: modelSize)
    }

    // Load model from local directory using LLMModelFactory (mlx-swift-lm 3.x API).
    // TokenizersLoader is supplied via MLXLMTokenizers convenience overload.
    do {
      let container = try await LLMModelFactory.shared.loadContainer(from: modelDir)

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
}
