import Foundation
import Hub
import MLX
import MLXLLM
import MLXLMCommon

/// Manages downloading, caching, and loading LLM models from HuggingFace
public actor BrujaModelManager {

    /// Shared instance
    public static let shared = BrujaModelManager()

    /// Default model for general use
    public static let defaultModel = "mlx-community/Phi-3-mini-4k-instruct-4bit"

    /// Base URL for HuggingFace model downloads
    private static let huggingFaceBaseURL = "https://huggingface.co"

    /// Storage location for downloaded models
    public nonisolated var modelsDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("intrusive-memory/Models/LLM", isDirectory: true)
    }

    /// Loaded model containers (cached for reuse)
    private var loadedModels: [String: ModelContainer] = [:]

    private init() {}

    // MARK: - Model Availability

    /// Check if a model is downloaded and available locally
    public nonisolated func isModelAvailable(_ modelId: String) -> Bool {
        let modelDir = modelDirectory(for: modelId)
        return FileManager.default.fileExists(atPath: modelDir.appendingPathComponent("config.json").path)
    }

    /// Get the local directory for a model
    public nonisolated func modelDirectory(for modelId: String) -> URL {
        modelsDirectory.appendingPathComponent(modelId.replacingOccurrences(of: "/", with: "_"))
    }

    /// Ensure a model is available, downloading if necessary
    public func ensureModelAvailable(
        _ modelId: String,
        to destination: URL? = nil,
        force: Bool = false,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        if !force && isModelAvailable(modelId) {
            return
        }
        try await downloadModel(modelId, to: destination, force: force, progress: progress ?? { _ in })
    }

    // MARK: - Model Download

    /// Download a model from HuggingFace
    public func downloadModel(
        _ modelId: String,
        to destination: URL? = nil,
        force: Bool = false,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {
        let modelDir = destination ?? modelDirectory(for: modelId)

        // Remove existing if force download
        if force && FileManager.default.fileExists(atPath: modelDir.path) {
            try FileManager.default.removeItem(at: modelDir)
        }

        // Skip if already downloaded
        if !force && FileManager.default.fileExists(atPath: modelDir.appendingPathComponent("config.json").path) {
            progress(1.0)
            return
        }

        // Create models directory if needed
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        // Build the base URL for this model
        let modelURL = URL(string: "\(Self.huggingFaceBaseURL)/\(modelId)/resolve/main/")!

        // Required model files (4-bit quantized models typically need these)
        let files = [
            "config.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "model.safetensors"
        ]

        for (index, file) in files.enumerated() {
            let fileURL = modelURL.appendingPathComponent(file)
            let destinationURL = modelDir.appendingPathComponent(file)

            // Skip if file already exists
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                progress(Double(index + 1) / Double(files.count))
                continue
            }

            let (localURL, response) = try await URLSession.shared.download(from: fileURL)

            // Check for HTTP errors
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                throw BrujaError.downloadFailed("HTTP \(httpResponse.statusCode) for \(file)")
            }

            try FileManager.default.moveItem(at: localURL, to: destinationURL)
            progress(Double(index + 1) / Double(files.count))
        }
    }

    // MARK: - Model Loading

    /// Load a model into memory for inference
    public func loadModel(_ modelId: String) async throws -> ModelContainer {
        // Return cached model if already loaded
        if let cached = loadedModels[modelId] {
            return cached
        }

        // Ensure model is downloaded
        guard isModelAvailable(modelId) else {
            throw BrujaError.modelNotDownloaded(modelId)
        }

        let modelDir = modelDirectory(for: modelId)

        // Validate memory before loading
        let modelSize = try calculateDirectorySize(modelDir)
        try BrujaMemory.validateMemoryForModel(sizeBytes: modelSize)

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
        guard FileManager.default.fileExists(atPath: path.appendingPathComponent("config.json").path) else {
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

    // MARK: - Model Info

    /// Get information about a downloaded model
    public nonisolated func modelInfo(_ modelId: String) throws -> BrujaModelInfo {
        let modelDir = modelDirectory(for: modelId)

        guard FileManager.default.fileExists(atPath: modelDir.path) else {
            throw BrujaError.modelNotFound(modelDir.path)
        }

        return try modelInfo(at: modelDir)
    }

    /// Get information about a model at a specific path
    public nonisolated func modelInfo(at path: URL) throws -> BrujaModelInfo {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw BrujaError.modelNotFound(path.path)
        }

        // Calculate total size
        let size = try calculateDirectorySize(path)

        // Get creation date
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        let creationDate = attributes[.creationDate] as? Date ?? Date()

        return BrujaModelInfo(
            id: path.lastPathComponent.replacingOccurrences(of: "_", with: "/"),
            path: path.path,
            sizeBytes: size,
            downloadDate: creationDate
        )
    }

    /// List all downloaded models
    public nonisolated func listModels() throws -> [BrujaModelInfo] {
        try listModels(in: modelsDirectory)
    }

    /// List models in a specific directory
    public nonisolated func listModels(in directory: URL) throws -> [BrujaModelInfo] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey]
        )

        return try contents.compactMap { url -> BrujaModelInfo? in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  FileManager.default.fileExists(atPath: url.appendingPathComponent("config.json").path) else {
                return nil
            }

            return try modelInfo(at: url)
        }
    }

    /// Delete a downloaded model
    public func deleteModel(_ modelId: String) throws {
        let modelDir = modelDirectory(for: modelId)

        // Unload from memory first
        unloadModel(modelId)

        // Delete from disk
        if FileManager.default.fileExists(atPath: modelDir.path) {
            try FileManager.default.removeItem(at: modelDir)
        }
    }

    // MARK: - Private Helpers

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
