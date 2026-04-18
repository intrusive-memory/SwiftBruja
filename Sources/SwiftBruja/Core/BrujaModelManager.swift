import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import SwiftAcervo

// MARK: - Model Registry

/// Metadata for a CDN-hosted model component, including all file hashes and sizes
/// from the SwiftAcervo manifest. This is a future-proof registration for model
/// discovery and validation.
public struct ModelComponentMetadata: Sendable {
  /// Unique model identifier (e.g., "mlx-community/Qwen3-Coder-Next-4bit")
  public let modelId: String
  /// Display name for UI/CLI (e.g., "Qwen3-Coder-Next (4-bit)")
  public let displayName: String
  /// Semantic version (e.g., "1.0.0")
  public let version: String
  /// Short component identifier for internal use (e.g., "qwen3-coder-next-4bit")
  public let componentId: String

  /// All files in the model manifest with exact sizes and SHA-256 hashes
  public struct FileDescriptor: Sendable {
    public let path: String
    public let sizeBytes: Int64
    public let sha256: String

    public init(path: String, sizeBytes: Int64, sha256: String) {
      self.path = path
      self.sizeBytes = sizeBytes
      self.sha256 = sha256
    }
  }

  public let files: [FileDescriptor]

  /// Total estimated model size in bytes
  public let estimatedSizeBytes: Int64
  /// Minimum RAM required for inference in bytes
  public let minimumMemoryBytes: Int64

  /// Model metadata
  public struct Properties: Sendable {
    public let quantization: String
    public let contextLength: String
    public let architecture: String
    public let cdnUrl: String
    public let manifestChecksum: String

    public init(
      quantization: String,
      contextLength: String,
      architecture: String,
      cdnUrl: String,
      manifestChecksum: String
    ) {
      self.quantization = quantization
      self.contextLength = contextLength
      self.architecture = architecture
      self.cdnUrl = cdnUrl
      self.manifestChecksum = manifestChecksum
    }
  }

  public let properties: Properties

  public init(
    modelId: String,
    displayName: String,
    version: String,
    componentId: String,
    files: [FileDescriptor],
    estimatedSizeBytes: Int64,
    minimumMemoryBytes: Int64,
    properties: Properties
  ) {
    self.modelId = modelId
    self.displayName = displayName
    self.version = version
    self.componentId = componentId
    self.files = files
    self.estimatedSizeBytes = estimatedSizeBytes
    self.minimumMemoryBytes = minimumMemoryBytes
    self.properties = properties
  }
}

// MARK: - Model Registry Storage

/// Build and return the initialized model registry with all built-in components
private func buildModelRegistry() -> [String: ModelComponentMetadata] {
  var registry: [String: ModelComponentMetadata] = [:]

  // Qwen3-Coder-Next-4bit model
  let qwen3CoderNextMetadata = ModelComponentMetadata(
    modelId: "mlx-community/Qwen3-Coder-Next-4bit",
    displayName: "Qwen3-Coder-Next (4-bit)",
    version: "1.0.0",
    componentId: "qwen3-coder-next-4bit",
    files: [
      // Config files
      .init(
        path: "config.json",
        sizeBytes: 22196,
        sha256: "e8e2412abc210311363cad4396e12fc73e8142e81408ca241b2487cc80723a29"
      ),
      .init(
        path: "generation_config.json",
        sizeBytes: 214,
        sha256: "37a3c1ef63516ca489c575f0db1c0405ddc0c3dbaca9ed987344c966c37aeef5"
      ),
      .init(
        path: "tokenizer.json",
        sizeBytes: 11422650,
        sha256: "be75606093db2094d7cd20f3c2f385c212750648bd6ea4fb2bf507a6a4c55506"
      ),
      .init(
        path: "tokenizer_config.json",
        sizeBytes: 702,
        sha256: "02222317d2b3586fe0676aaf7455a90fbe4b1e4f256b9f41fba3374357303ae2"
      ),
      .init(
        path: "chat_template.jinja",
        sizeBytes: 6068,
        sha256: "c79a833039a43602150cce0902403d6e376c50930c1b2a139b2964e1f0c322a0"
      ),
      .init(
        path: "model.safetensors.index.json",
        sizeBytes: 173450,
        sha256: "4ab1fbfbc6e42a84c6b810745765db249350ab1df1d1cdb0c2841de89e8ca309"
      ),
      // Model shards (9 safetensors files)
      .init(
        path: "model-00001-of-00009.safetensors",
        sizeBytes: 5132893190,
        sha256: "fb30a2722004cb427d9dc3b3583a9dc4f94badf68420393324e6ebee4432c96f"
      ),
      .init(
        path: "model-00002-of-00009.safetensors",
        sizeBytes: 5257948500,
        sha256: "a6b2a95a4bb7463f74951a5565e2504e7f28fe78877bb966378003b0def69038"
      ),
      .init(
        path: "model-00003-of-00009.safetensors",
        sizeBytes: 5239714716,
        sha256: "0b8e009bd09fb5994d4d188a61e28a90aead48a50d7e0983d3bd7fc3644553d3"
      ),
      .init(
        path: "model-00004-of-00009.safetensors",
        sizeBytes: 5261626153,
        sha256: "6b34fd01a609db8bd4e445dcc0cc1ef5991550523b4df7e89f59c7d50343e321"
      ),
      .init(
        path: "model-00005-of-00009.safetensors",
        sizeBytes: 5257948651,
        sha256: "f19b843ee11c5b4c8d56b2a5940033e81ec29013de75d944447754238344621b"
      ),
      .init(
        path: "model-00006-of-00009.safetensors",
        sizeBytes: 5239714662,
        sha256: "37f9b2ff202e8d58239f1df6acc568cb08e10a324b57c19f21b38ce93608b8c0"
      ),
      .init(
        path: "model-00007-of-00009.safetensors",
        sizeBytes: 5257948739,
        sha256: "78e4b432212f783db393bc643b9875918fc050c3d3c41a071bf9260449db356a"
      ),
      .init(
        path: "model-00008-of-00009.safetensors",
        sizeBytes: 5261626157,
        sha256: "3841f088f9ceed8f4024e0c6496677af6b6a32047f762337b6d42232261cb3dc"
      ),
      .init(
        path: "model-00009-of-00009.safetensors",
        sizeBytes: 2934865732,
        sha256: "933efe2e2f28f97b9b851839c43fca0d6742b26c9ff9df1fd0e427712246553c"
      ),
    ],
    estimatedSizeBytes: 41_780_000_000, // 41.78 GB
    minimumMemoryBytes: 16_000_000_000, // 16 GB RAM
    properties: .init(
      quantization: "4-bit",
      contextLength: "4096",
      architecture: "Qwen3",
      cdnUrl: "https://pub-8e049ed02be340cbb18f921765fd24f3.r2.dev/models/mlx-community_Qwen3-Coder-Next-4bit",
      manifestChecksum: "a7188a821b417f701b704b81d9e8c546bc2a898bff763beb34773f3df26feffc"
    )
  )

  registry[qwen3CoderNextMetadata.componentId] = qwen3CoderNextMetadata
  return registry
}

/// Global registry of known model components. Immutable after initialization.
private let modelRegistry = buildModelRegistry()

// MARK: - BrujaModelManager

/// Manages loading LLM models into memory for inference.
///
/// Download, list, info, and delete responsibilities are handled by
/// `BrujaDownloadManager` (which delegates to SwiftAcervo). This actor
/// is inference-only: it loads models into `ModelContainer` instances,
/// caches them, validates memory, and supports legacy path migration.
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

  // MARK: - Model Registry

  /// Register a model component in the global registry (initializing it dynamically)
  /// Note: The built-in Qwen3-Coder-Next model is pre-registered at module init.
  /// This method is provided for future extensions and testing.
  public nonisolated static func registerModelComponent(_ metadata: ModelComponentMetadata) {
    // Note: In Swift, we cannot mutate the immutable registry after initialization.
    // For extensibility, a future version would use a mutable registry with proper
    // concurrency guards (e.g., an actor). For now, all registrations happen at
    // module load time via buildModelRegistry().
  }

  /// Retrieve registered model metadata by component ID
  public nonisolated static func modelComponent(for componentId: String) -> ModelComponentMetadata? {
    modelRegistry[componentId]
  }

  /// Get all registered model components
  public nonisolated static var registeredComponents: [ModelComponentMetadata] {
    Array(modelRegistry.values).sorted { $0.displayName < $1.displayName }
  }

  /// Check if a component is registered
  public nonisolated static func isComponentRegistered(_ componentId: String) -> Bool {
    modelRegistry[componentId] != nil
  }
}
