import Foundation

/// SwiftBruja - On-device LLM for Apple Silicon
///
/// Simple, single-import access to local language models with structured output.
///
/// ## Quick Start
///
/// ```swift
/// import SwiftBruja
///
/// // Simple query
/// let response = try await Bruja.query("What is 2+2?", model: modelPath)
///
/// // Query with auto-download from HuggingFace
/// let response = try await Bruja.query(
///     "Explain Swift concurrency",
///     model: "mlx-community/Phi-3-mini-4k-instruct-4bit"
/// )
///
/// // Structured output
/// struct Answer: Codable { let result: Int }
/// let answer: Answer = try await Bruja.query("What is 2+2?", as: Answer.self, model: modelPath)
///
/// // Download a model
/// try await Bruja.download(model: "mlx-community/Phi-3-mini-4k-instruct-4bit")
/// ```
public enum Bruja {

    /// Default model for general use
    public static let defaultModel = BrujaModelManager.defaultModel

    /// Default models directory
    public static var defaultModelsDirectory: URL {
        BrujaModelManager.shared.modelsDirectory
    }

    // MARK: - Model Management

    /// Check if a model is downloaded and ready
    public static func modelExists(at path: String) -> Bool {
        let url = resolvePath(path)
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("config.json").path)
    }

    /// Check if a model ID is downloaded
    public static func modelExists(id: String) -> Bool {
        BrujaModelManager.shared.isModelAvailable(id)
    }

    /// Download a model from HuggingFace
    public static func download(
        model: String,
        to destination: URL? = nil,
        force: Bool = false,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        try await BrujaModelManager.shared.downloadModel(
            model,
            to: destination,
            force: force,
            progress: progress ?? { _ in }
        )
    }

    /// Get information about a model
    public static func modelInfo(at path: String) async throws -> BrujaModelInfo {
        let url = resolvePath(path)

        // Check if it's a local path
        if FileManager.default.fileExists(atPath: url.path) {
            return try BrujaModelManager.shared.modelInfo(at: url)
        }

        // Treat as model ID
        return try BrujaModelManager.shared.modelInfo(path)
    }

    /// List all downloaded models
    public static func listModels(in directory: URL? = nil) throws -> [BrujaModelInfo] {
        let dir = directory ?? defaultModelsDirectory
        return try BrujaModelManager.shared.listModels(in: dir)
    }

    // MARK: - Queries

    /// Query a model and get a text response
    ///
    /// - Parameters:
    ///   - prompt: The prompt to send to the model
    ///   - model: Model path or HuggingFace ID (will auto-download if needed)
    ///   - downloadDestination: Where to download the model if not found locally
    ///   - temperature: Sampling temperature (0.0-1.0, higher = more creative)
    ///   - maxTokens: Maximum tokens to generate
    ///   - system: Optional system prompt
    /// - Returns: The model's text response
    public static func query(
        _ prompt: String,
        model: String,
        downloadDestination: URL? = nil,
        temperature: Float = 0.7,
        maxTokens: Int? = nil,
        system: String? = nil
    ) async throws -> String {
        try await BrujaQuery.query(
            prompt,
            model: model,
            downloadDestination: downloadDestination,
            temperature: temperature,
            maxTokens: maxTokens,
            system: system
        )
    }

    /// Query a model and get a result with metadata
    public static func queryWithMetadata(
        _ prompt: String,
        model: String,
        downloadDestination: URL? = nil,
        temperature: Float = 0.7,
        maxTokens: Int? = nil,
        system: String? = nil
    ) async throws -> BrujaQueryResult {
        try await BrujaQuery.queryWithMetadata(
            prompt,
            model: model,
            downloadDestination: downloadDestination,
            temperature: temperature,
            maxTokens: maxTokens,
            system: system
        )
    }

    /// Query a model and get a structured (typed) response
    ///
    /// The model will be instructed to return JSON that matches the expected type.
    ///
    /// - Parameters:
    ///   - prompt: The prompt to send to the model
    ///   - type: The Codable type to decode the response into
    ///   - model: Model path or HuggingFace ID
    ///   - downloadDestination: Where to download the model if not found locally
    ///   - temperature: Sampling temperature (lower is better for structured output)
    ///   - maxTokens: Maximum tokens to generate
    ///   - system: Optional additional system prompt
    /// - Returns: The decoded response
    public static func query<T: Codable>(
        _ prompt: String,
        as type: T.Type,
        model: String,
        downloadDestination: URL? = nil,
        temperature: Float = 0.3,
        maxTokens: Int? = nil,
        system: String? = nil
    ) async throws -> T {
        try await BrujaQuery.query(
            prompt,
            as: type,
            model: model,
            downloadDestination: downloadDestination,
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
}
