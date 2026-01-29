import Foundation

/// Errors that can occur during SwiftBruja operations
public enum BrujaError: LocalizedError, Sendable {
    /// Model is not downloaded locally
    case modelNotDownloaded(String)

    /// Model directory or path not found
    case modelNotFound(String)

    /// Model failed to load into memory
    case modelLoadFailed(Error)

    /// Model download failed
    case downloadFailed(String)

    /// Query execution failed
    case queryFailed(String)

    /// Invalid response from the model
    case invalidResponse(String)

    /// JSON parsing failed for structured output
    case jsonParsingFailed(String)

    /// Invalid model path or identifier
    case invalidModelPath(String)

    /// Insufficient memory to load the model
    case insufficientMemory(available: UInt64, required: UInt64)

    public var errorDescription: String? {
        switch self {
        case .modelNotDownloaded(let modelId):
            return "Model '\(modelId)' is not downloaded. Use `bruja download` to download it first."
        case .modelNotFound(let path):
            return "Model not found at path: \(path)"
        case .modelLoadFailed(let error):
            return "Failed to load model: \(error.localizedDescription)"
        case .downloadFailed(let reason):
            return "Model download failed: \(reason)"
        case .queryFailed(let reason):
            return "Query failed: \(reason)"
        case .invalidResponse(let reason):
            return "Invalid response from model: \(reason)"
        case .jsonParsingFailed(let reason):
            return "Failed to parse JSON response: \(reason)"
        case .invalidModelPath(let path):
            return "Invalid model path: \(path)"
        case .insufficientMemory(let available, let required):
            let availMB = available / (1024 * 1024)
            let reqMB = required / (1024 * 1024)
            return "Insufficient memory: \(availMB) MB available, \(reqMB) MB required to load model"
        }
    }
}
