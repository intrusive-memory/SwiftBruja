import Foundation

/// Errors that can occur during SwiftBruja operations
public enum BrujaError: LocalizedError, Sendable {
  /// Model directory or path not found
  case modelNotFound(String)

  /// Model failed to load into memory
  case modelLoadFailed(Error)

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

  /// A filesystem tool resolved to a path outside the working-directory subtree (R6.2).
  /// The argument is the resolved (canonicalized) path that escaped the cwd.
  case pathEscapesWorkingDirectory(String)

  /// A tool invoked by the agent loop failed while executing. Carries the tool name and the
  /// underlying reason so the agent can surface (or recover from) the failure instead of crashing.
  case toolExecutionFailed(tool: String, reason: String)

  /// The agent exceeded its configured per-conversation step/turn budget (R5.3). Carries the
  /// limit that was hit so the caller can report it precisely.
  case agentStepLimitExceeded(limit: Int)

  /// Generation hit the model's context window (prompt + history too large), or the underlying
  /// MLX generation reported a context-overflow condition. Mapped here instead of crashing
  /// (R2.4 spirit applied to MLX). `tokenCount`/`limit` are best-effort and may be 0 when the
  /// source cannot report exact counts.
  case contextWindowExceeded(tokenCount: Int, limit: Int)

  public var errorDescription: String? {
    switch self {
    case .modelNotFound(let path):
      return "Model not found: \(path)"
    case .modelLoadFailed(let error):
      return "Failed to load model: \(error.localizedDescription)"
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
    case .pathEscapesWorkingDirectory(let path):
      return "Path escapes the working directory subtree and requires explicit consent: \(path)"
    case .toolExecutionFailed(let tool, let reason):
      return "Tool '\(tool)' failed: \(reason)"
    case .agentStepLimitExceeded(let limit):
      return "Agent step limit exceeded: reached the configured maximum of \(limit) step(s) per turn"
    case .contextWindowExceeded(let tokenCount, let limit):
      if limit > 0 {
        return "Context window exceeded: \(tokenCount) tokens requested, \(limit) tokens available"
      }
      return "Context window exceeded: prompt and history are too large for the model"
    }
  }
}
