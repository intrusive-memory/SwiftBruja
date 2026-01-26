/// SwiftBruja - On-device LLM for Apple Silicon
///
/// Simple, single-import access to local language models with structured output.
///
/// ## Quick Start
///
/// ```swift
/// import SwiftBruja
///
/// // Ensure model is ready
/// try await Bruja.ensureModelReady()
///
/// // Query with structured output
/// struct Result: Codable { let answer: String }
/// let result: Result = try await Bruja.query("...", as: Result.self)
///
/// // Generate PROJECT.md
/// let projectMd = try await Bruja.generateProjectMd(for: folderURL)
/// ```
public enum Bruja {

    // MARK: - Model Management

    /// Check if the default model is downloaded and ready
    public static func isModelReady() async -> Bool {
        await BrujaModelManager.shared.isModelAvailable(BrujaModelManager.defaultModel)
    }

    /// Download the default model if not already available
    public static func ensureModelReady(
        progress: ((Double) -> Void)? = nil
    ) async throws {
        try await BrujaModelManager.shared.ensureModelAvailable(
            BrujaModelManager.defaultModel,
            progress: progress
        )
    }

    /// Download the default model with progress tracking
    public static func downloadDefaultModel(
        progress: @escaping (Double) -> Void
    ) async throws {
        try await BrujaModelManager.shared.downloadModel(
            BrujaModelManager.defaultModel,
            progress: progress
        )
    }

    // MARK: - Queries

    /// Query the model and get a raw string response
    public static func query(
        _ prompt: String,
        model: String = BrujaModelManager.defaultModel,
        temperature: Float = 0.7
    ) async throws -> String {
        try await BrujaQuery.query(prompt, model: model, temperature: temperature)
    }

    /// Query the model and get a structured response
    public static func query<T: Codable>(
        _ prompt: String,
        as type: T.Type,
        model: String = BrujaModelManager.defaultModel,
        temperature: Float = 0.3
    ) async throws -> T {
        try await BrujaQuery.query(prompt, as: type, model: model, temperature: temperature)
    }

    // MARK: - Use Cases

    /// Generate a PROJECT.md file for a folder
    public static func generateProjectMd(
        for folderURL: URL,
        author: String? = nil,
        model: String = BrujaModelManager.defaultModel
    ) async throws -> ProjectMdGenerator.Result {
        try await ProjectMdGenerator.generate(
            for: folderURL,
            author: author,
            model: model
        )
    }
}
