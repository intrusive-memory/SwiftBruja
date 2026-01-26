import Foundation

/// Result of a query operation with metadata
public struct BrujaQueryResult: Codable, Sendable {
    /// The model's text response
    public let response: String

    /// The model identifier used
    public let model: String

    /// Local path to the model
    public let modelPath: String

    /// Number of tokens generated
    public let tokensGenerated: Int

    /// Time taken to generate the response
    public let durationSeconds: Double

    public init(
        response: String,
        model: String,
        modelPath: String,
        tokensGenerated: Int,
        durationSeconds: Double
    ) {
        self.response = response
        self.model = model
        self.modelPath = modelPath
        self.tokensGenerated = tokensGenerated
        self.durationSeconds = durationSeconds
    }
}

/// Information about a downloaded model
public struct BrujaModelInfo: Codable, Sendable {
    /// The model identifier (e.g., "mlx-community/Phi-3-mini-4k-instruct-4bit")
    public let id: String

    /// Local file path to the model directory
    public let path: String

    /// Total size of the model in bytes
    public let sizeBytes: Int64

    /// When the model was downloaded
    public let downloadDate: Date

    public init(id: String, path: String, sizeBytes: Int64, downloadDate: Date) {
        self.id = id
        self.path = path
        self.sizeBytes = sizeBytes
        self.downloadDate = downloadDate
    }

    /// Human-readable size string
    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }
}
