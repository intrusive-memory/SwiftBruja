import Foundation
import Hub
import MLXLLM
import MLXLMCommon

/// Manages downloading, caching, and loading LLM models from HuggingFace
public actor BrujaModelManager {

    /// Shared instance
    public static let shared = BrujaModelManager()

    /// Default model for general use
    public static let defaultModel = "mlx-community/Phi-3-mini-4k-instruct-4bit"

    /// Storage location for downloaded models
    public var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SwiftBruja/Models", isDirectory: true)
    }

    /// Loaded model containers (cached for reuse)
    private var loadedModels: [String: LLMModelContainer] = [:]

    private init() {}

    // MARK: - Model Availability

    /// Check if a model is downloaded and available locally
    public func isModelAvailable(_ modelId: String) -> Bool {
        let modelDir = modelsDirectory.appendingPathComponent(modelId.replacingOccurrences(of: "/", with: "_"))
        return FileManager.default.fileExists(atPath: modelDir.appendingPathComponent("config.json").path)
    }

    /// Ensure a model is available, downloading if necessary
    public func ensureModelAvailable(
        _ modelId: String,
        progress: ((Double) -> Void)? = nil
    ) async throws {
        if !isModelAvailable(modelId) {
            try await downloadModel(modelId, progress: progress ?? { _ in })
        }
    }

    // MARK: - Model Download

    /// Download a model from HuggingFace
    public func downloadModel(
        _ modelId: String,
        progress: @escaping (Double) -> Void
    ) async throws {
        // Create models directory if needed
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        // TODO: Implement actual download using Hub
        // This will be extracted from Produciesta's MLXModelDownloader
        fatalError("Not yet implemented - extract from Produciesta")
    }

    // MARK: - Model Loading

    /// Load a model into memory for inference
    public func loadModel(_ modelId: String) async throws -> LLMModelContainer {
        // Return cached model if already loaded
        if let cached = loadedModels[modelId] {
            return cached
        }

        // Ensure model is downloaded
        try await ensureModelAvailable(modelId)

        // TODO: Load model using LLMModelFactory
        // This will be extracted from Produciesta's MLXModelManager
        fatalError("Not yet implemented - extract from Produciesta")
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
