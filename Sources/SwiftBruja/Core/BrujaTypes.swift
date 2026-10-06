import Foundation
import SwiftAcervo

/// Whether a model reasons before it answers.
///
/// Models such as Qwen3.5 read `enable_thinking` in their chat template. `.off` sets it to
/// `false`, so the model does not generate the reasoning at all.
public enum BrujaThinking: Sendable {
  /// Leave the chat template as the model ships it. Nothing is passed to the template.
  case modelDefault
  /// Pass `enable_thinking: false` to the chat template.
  case off

  /// The additional context for the chat template; `nil` for `.modelDefault`.
  internal var additionalContext: [String: any Sendable]? {
    switch self {
    case .modelDefault: return nil
    case .off: return ["enable_thinking": false]
    }
  }
}

/// Result of a query operation with metadata
public struct BrujaQueryResult: Codable, Sendable {
  /// The model's text response.
  ///
  /// Settable so callers can post-process it (e.g. the `bruja` CLI strips `<think>` reasoning
  /// traces from thinking models unless `--verbose`) without rebuilding the whole struct.
  public var response: String

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

extension BrujaModelInfo {
  /// Bridge from AcervoModel
  public init(from acervo: AcervoModel) {
    self.init(
      id: acervo.id,
      path: acervo.path.path,
      sizeBytes: acervo.sizeBytes,
      downloadDate: acervo.downloadDate
    )
  }
}
