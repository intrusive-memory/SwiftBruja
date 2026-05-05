import Foundation
import MLXLMCommon
import SwiftAcervo

/// SwiftBruja - On-device LLM for Apple Silicon
///
/// Simple, single-import access to local language models with structured output.
///
/// ## Quick Start
///
/// ```swift
/// import SwiftBruja
///
/// // Simple query (model must be pre-downloaded via SwiftAcervo)
/// let response = try await Bruja.query("What is 2+2?", model: "mlx-community/Qwen3-Coder-Next-4bit")
///
/// // Structured output
/// struct Answer: Codable { let result: Int }
/// let answer: Answer = try await Bruja.query("What is 2+2?", as: Answer.self, model: "mlx-community/Qwen3-Coder-Next-4bit")
///
/// // Model management delegated to SwiftAcervo — use Acervo.download() or other download tools
/// ```
public enum Bruja {

  /// Library version
  public static let version = "1.6.2-dev"

  /// Default model for general use
  public static let defaultModel = BrujaModelManager.defaultModel

  /// Default models directory (~/Library/SharedModels/)
  public static var defaultModelsDirectory: URL {
    Acervo.sharedModelsDirectory
  }

  // MARK: - Model Management

  /// Check if a model is downloaded and ready
  public static func modelExists(at path: String) -> Bool {
    let url = resolvePath(path)
    return FileManager.default.fileExists(atPath: url.appendingPathComponent("config.json").path)
  }

  /// Check if a model ID is downloaded
  public static func modelExists(id: String) -> Bool {
    Acervo.isModelAvailable(id)
  }

  /// Get information about a model
  public static func modelInfo(at path: String) throws -> BrujaModelInfo {
    let url = resolvePath(path)

    // Check if it's a local path that exists on disk
    if FileManager.default.fileExists(atPath: url.path) {
      // Calculate size from path
      let size = try calculateDirectorySize(url)
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      let creationDate = attributes[.creationDate] as? Date ?? Date()
      // NOTE: Best-effort reverse of the SwiftAcervo `org_repo` slug for local
      // paths Acervo did not download (e.g. user-supplied directories on disk).
      // Underscores in repo names will misparse — the canonical lookup is
      // `Acervo.modelInfo(_:)` with a model ID, used in the fallthrough below.
      return BrujaModelInfo(
        id: url.lastPathComponent.replacingOccurrences(of: "_", with: "/"),
        path: url.path,
        sizeBytes: size,
        downloadDate: creationDate
      )
    }

    // Treat as model ID — delegate to Acervo
    let acervoModel = try Acervo.modelInfo(path)
    return BrujaModelInfo(from: acervoModel)
  }

  /// List all downloaded models
  public static func listModels() throws -> [BrujaModelInfo] {
    try Acervo.listModels().map { BrujaModelInfo(from: $0) }
  }

  // MARK: - Model Loading

  /// Load a model and return its container for use with ChatSession or other APIs
  ///
  /// Model must be pre-downloaded via SwiftAcervo to the shared models directory.
  ///
  /// - Parameters:
  ///   - model: Model ID (e.g., "mlx-community/Qwen3-Coder-Next-4bit")
  /// - Returns: A loaded `ModelContainer` ready for use
  /// - Throws: `BrujaError.modelNotFound` if model is not available locally
  public static func loadModel(
    _ model: String
  ) async throws -> ModelContainer {
    let (container, _, _) = try await BrujaQuery.resolveModel(model)
    return container
  }

  // MARK: - Queries

  /// Query a model and get a text response
  ///
  /// Model must be pre-downloaded via SwiftAcervo to the shared models directory.
  ///
  /// - Parameters:
  ///   - prompt: The prompt to send to the model
  ///   - model: Model ID (e.g., "mlx-community/Qwen3-Coder-Next-4bit")
  ///   - temperature: Sampling temperature (0.0-1.0, higher = more creative)
  ///   - maxTokens: Maximum tokens to generate
  ///   - system: Optional system prompt
  /// - Returns: The model's text response
  /// - Throws: `BrujaError.modelNotFound` if model is not available locally
  public static func query(
    _ prompt: String,
    model: String,
    temperature: Float = 0.7,
    maxTokens: Int? = nil,
    system: String? = nil
  ) async throws -> String {
    try await BrujaQuery.query(
      prompt,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
      system: system
    )
  }

  /// Query a model and get a result with metadata
  public static func queryWithMetadata(
    _ prompt: String,
    model: String,
    temperature: Float = 0.7,
    maxTokens: Int? = nil,
    system: String? = nil
  ) async throws -> BrujaQueryResult {
    try await BrujaQuery.queryWithMetadata(
      prompt,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
      system: system
    )
  }

  /// Query a model and get a structured (typed) response
  ///
  /// The model will be instructed to return JSON that matches the expected type.
  /// Model must be pre-downloaded via SwiftAcervo to the shared models directory.
  ///
  /// - Parameters:
  ///   - prompt: The prompt to send to the model
  ///   - type: The Codable type to decode the response into
  ///   - model: Model ID (e.g., "mlx-community/Qwen3-Coder-Next-4bit")
  ///   - temperature: Sampling temperature (lower is better for structured output)
  ///   - maxTokens: Maximum tokens to generate
  ///   - system: Optional additional system prompt
  /// - Returns: The decoded response
  /// - Throws: `BrujaError.modelNotFound` if model is not available locally
  public static func query<T: Codable>(
    _ prompt: String,
    as type: T.Type,
    model: String,
    temperature: Float = 0.3,
    maxTokens: Int? = nil,
    system: String? = nil
  ) async throws -> T {
    try await BrujaQuery.query(
      prompt,
      as: type,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
      system: system
    )
  }

  // MARK: - Private Helpers

  private static func resolvePath(_ path: String) -> URL {
    if path.hasPrefix("~") {
      return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
    }
    return URL(fileURLWithPath: path)
  }

  private static func calculateDirectorySize(_ url: URL) throws -> Int64 {
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
