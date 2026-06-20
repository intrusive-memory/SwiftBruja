import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import SwiftAcervo

/// Handles query execution against loaded models
public enum BrujaQuery {

  // MARK: - Simple Query

  /// Execute a query and return the text response
  public static func query(
    _ prompt: String,
    model: String,
    temperature: Float = 0.7,
    maxTokens: Int? = nil,
    system: String? = nil
  ) async throws -> String {
    let result = try await queryWithMetadata(
      prompt,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
      system: system
    )
    return result.response
  }

  // MARK: - Query with Metadata

  /// Execute a query and return full result with metadata
  public static func queryWithMetadata(
    _ prompt: String,
    model: String,
    temperature: Float = 0.7,
    maxTokens: Int? = nil,
    system: String? = nil
  ) async throws -> BrujaQueryResult {
    let startTime = Date()

    // Determine model path and container
    let (container, modelPath, modelId) = try await resolveModel(model)

    // Resolve maxTokens: use caller's value if provided, otherwise auto-tune based on memory
    let resolvedMaxTokens: Int
    if let maxTokens {
      resolvedMaxTokens = maxTokens
    } else {
      // Use Acervo to get model size from downloaded model metadata
      let modelSize = (try? Acervo.modelInfo(model).sizeBytes) ?? 0
      resolvedMaxTokens = BrujaMemory.recommendedMaxTokens(modelSizeBytes: modelSize)
    }

    // Log the resolved maxTokens for user awareness
    FileHandle.standardError.write(
      Data("[SwiftBruja] maxTokens set to \(resolvedMaxTokens) for this query\n".utf8))

    // Create chat session with optional system prompt
    let instructions =
      system ?? "You are a helpful AI assistant. Be concise and direct in your responses."

    let session = ChatSession(
      container,
      instructions: instructions,
      generateParameters: GenerateParameters(maxTokens: resolvedMaxTokens, temperature: temperature)
    )

    // Execute query
    let response = try await session.respond(to: prompt)

    let duration = Date().timeIntervalSince(startTime)

    // Estimate tokens (rough approximation: ~4 chars per token)
    let tokensGenerated = response.count / 4

    return BrujaQueryResult(
      response: response,
      model: modelId,
      modelPath: modelPath,
      tokensGenerated: tokensGenerated,
      durationSeconds: duration
    )
  }

  // MARK: - Structured Query

  /// Execute a query and parse the response as a Codable type
  public static func query<T: Codable>(
    _ prompt: String,
    as type: T.Type,
    model: String,
    temperature: Float = 0.3,
    maxTokens: Int? = nil,
    system: String? = nil
  ) async throws -> T {
    // Build a system prompt that encourages JSON output
    let jsonSystem =
      (system ?? "") + """

        IMPORTANT: You must respond ONLY with valid JSON that matches the requested structure.
        Do not include any explanatory text, markdown code blocks, or other content.
        Your entire response should be parseable as JSON.
        """

    let result = try await queryWithMetadata(
      prompt,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
      system: jsonSystem
    )

    return try parseJSON(result.response, as: type)
  }

  // MARK: - Private Helpers

  /// Resolve a model identifier to a loaded container
  ///
  /// Assumes the model is already present on the filesystem via SwiftAcervo.
  /// Does not download — model must exist at the Acervo location.
  internal static func resolveModel(
    _ model: String
  ) async throws -> (ModelContainer, String, String) {
    let manager = BrujaModelManager.shared

    // Verify the model directory is present via Acervo — assumes it was
    // downloaded externally. Loose check (config.json present), not the strict
    // manifest-cache check: a fully-downloaded model without the cache file is
    // still loadable. `loadModel` re-checks and the MLX loader reports any
    // genuinely-missing file.
    guard Acervo.isModelConfigPresent(model) else {
      throw BrujaError.modelNotFound(
        "Model '\(model)' not found. Ensure it is pre-downloaded to \(Acervo.sharedModelsDirectory.path)"
      )
    }

    // Load the model
    let container = try await manager.loadModel(model)
    let modelDir = try Acervo.modelDirectory(for: model)

    return (container, modelDir.path, model)
  }

  /// Parse a JSON string into a Codable type
  private static func parseJSON<T: Codable>(_ jsonString: String, as type: T.Type) throws -> T {
    // Try to extract JSON from the response (handle markdown code blocks)
    let cleaned = cleanJSONResponse(jsonString)

    guard let data = cleaned.data(using: .utf8) else {
      throw BrujaError.jsonParsingFailed("Failed to convert response to data")
    }

    do {
      let decoder = JSONDecoder()
      return try decoder.decode(type, from: data)
    } catch {
      throw BrujaError.jsonParsingFailed(
        "Decoding failed: \(error.localizedDescription). Response was: \(cleaned.prefix(200))...")
    }
  }

  /// Clean up a JSON response that may contain markdown or extra text
  private static func cleanJSONResponse(_ response: String) -> String {
    var text = response.trimmingCharacters(in: .whitespacesAndNewlines)

    // Remove markdown code blocks
    if text.hasPrefix("```json") {
      text = String(text.dropFirst(7))
    } else if text.hasPrefix("```") {
      text = String(text.dropFirst(3))
    }

    if text.hasSuffix("```") {
      text = String(text.dropLast(3))
    }

    text = text.trimmingCharacters(in: .whitespacesAndNewlines)

    // Try to find JSON object or array
    if let startBrace = text.firstIndex(of: "{"),
      let endBrace = text.lastIndex(of: "}")
    {
      text = String(text[startBrace...endBrace])
    } else if let startBracket = text.firstIndex(of: "["),
      let endBracket = text.lastIndex(of: "]")
    {
      text = String(text[startBracket...endBracket])
    }

    return text
  }
}
