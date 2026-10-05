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
    system: String? = nil,
    thinking: BrujaThinking = .modelDefault
  ) async throws -> String {
    let result = try await queryWithMetadata(
      prompt,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
      system: system,
      thinking: thinking
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
    system: String? = nil,
    thinking: BrujaThinking = .modelDefault
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
      generateParameters: GenerateParameters(
        maxTokens: resolvedMaxTokens, temperature: temperature),
      additionalContext: thinking.additionalContext
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
    system: String? = nil,
    thinking: BrujaThinking = .modelDefault
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
      system: jsonSystem,
      thinking: thinking
    )

    return try parseJSON(result.response, as: type)
  }

  // MARK: - Schema-Constrained Query

  /// Execute a query whose output is constrained, token by token, to a JSON schema, and decode it.
  ///
  /// Unlike ``query(_:as:model:temperature:maxTokens:system:)`` this does not ask the model for
  /// JSON and then repair the answer: every token that would leave the schema is masked before
  /// sampling, so the output is always one JSON object with the schema's keys in order. The model
  /// may write one space after a `:` or a `,`; no other whitespace appears outside strings.
  /// The output is decoded with `JSONDecoder` as it is.
  ///
  /// `thinking: .off` turns the model's thinking mode off through the chat template.
  ///
  /// `repetitionPenalty` is applied to the logits before the mask, over the last
  /// ``constrainedRepetitionContextSize`` tokens, to keep a string from repeating one word and an
  /// array from repeating one item. `nil`, the default, applies no penalty. A penalty can push
  /// fields to `null` (measured: 19 to 33 null fields over nine prompts at 1.1), which is why it
  /// is off by default.
  ///
  /// - Throws: `BrujaError.structuredOutputTruncated` if `maxTokens` is reached before the object
  ///   closes; `BrujaError.jsonParsingFailed` if the object does not decode as `T`.
  public static func query<T: Decodable>(
    _ prompt: String,
    schema: BrujaJSONSchema,
    as type: T.Type,
    model: String,
    temperature: Float = 0.3,
    maxTokens: Int? = nil,
    system: String? = nil,
    repetitionPenalty: Float? = nil,
    thinking: BrujaThinking = .modelDefault
  ) async throws -> T {
    let output = try await generateConstrained(
      prompt,
      schema: schema,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
      system: system,
      repetitionPenalty: repetitionPenalty,
      thinking: thinking
    )
    return try decodeConstrained(output.text, as: type)
  }

  /// What one schema-constrained generation produced.
  internal struct ConstrainedOutput: Sendable {
    /// The JSON text, exactly as generated.
    var text: String
    /// Tokens in the prepared prompt.
    var promptTokens: Int
    /// Tokens generated.
    var generatedTokens: Int
    /// Seconds spent building (or fetching) the vocabulary table.
    var vocabularySeconds: Double
    /// Seconds from the start of prompt preparation to the last token.
    var generationSeconds: Double
  }

  /// The system prompt of a schema-constrained query when the caller gives none.
  internal static let constrainedDefaultSystem =
    "You are a careful assistant. Answer with one JSON object and nothing else. "
    + "Use null for any value the prompt does not give."

  /// How many of the most recent tokens the repetition penalty of a schema-constrained query
  /// looks at.
  internal static let constrainedRepetitionContextSize = 64

  /// Runs schema-constrained generation and returns the raw JSON text with its counters.
  internal static func generateConstrained(
    _ prompt: String,
    schema: BrujaJSONSchema,
    model: String,
    temperature: Float,
    maxTokens: Int?,
    system: String?,
    repetitionPenalty: Float? = nil,
    thinking: BrujaThinking = .modelDefault
  ) async throws -> ConstrainedOutput {
    let (container, _, _) = try await resolveModel(model)

    let tokenLimit: Int
    if let maxTokens {
      tokenLimit = maxTokens
    } else {
      let modelSize = (try? Acervo.modelInfo(model).sizeBytes) ?? 0
      tokenLimit = BrujaMemory.recommendedMaxTokens(modelSizeBytes: modelSize)
    }

    let vocabularyStart = Date()
    let vocabulary = try await BrujaModelManager.shared.vocabularyTable(for: model)
    let vocabularySeconds = Date().timeIntervalSince(vocabularyStart)

    let instructions = system ?? constrainedDefaultSystem

    let result:
      (text: String, promptTokens: Int, generatedTokens: Int, seconds: Double, done: Bool) =
        try await container.perform { (context: ModelContext) in
          let start = Date()
          let userInput = UserInput(
            chat: [.system(instructions), .user(prompt)],
            additionalContext: thinking.additionalContext)
          let input = try await context.processor.prepare(input: userInput)

          // Every id that ends generation for this model. The processor masks them until the
          // object has closed.
          var eosTokenIds = context.configuration.eosTokenIds
          if let id = context.tokenizer.eosTokenId {
            eosTokenIds.insert(id)
          }
          for token in context.configuration.extraEOSTokens {
            if let id = context.tokenizer.convertTokenToId(token) {
              eosTokenIds.insert(id)
            }
          }

          let processor = BrujaJSONLogitProcessor(
            acceptor: BrujaJSONAcceptor(schema: schema),
            vocabulary: vocabulary,
            eosTokenIds: eosTokenIds,
            repetitionContext: repetitionPenalty.map {
              RepetitionContext(
                repetitionPenalty: $0, repetitionContextSize: constrainedRepetitionContextSize)
            }
          )
          var iterator = try TokenIterator(
            input: input,
            model: context.model,
            cache: nil,
            processor: processor,
            sampler: GenerateParameters(temperature: temperature).sampler(),
            maxTokens: tokenLimit
          )

          // The iterator keeps its own copy of the processor, so follow the output with a second
          // acceptor. Generation is over as soon as that one sees the object close.
          var follower = BrujaJSONAcceptor(schema: schema)
          var text = ""
          var generated = 0
          while !follower.isComplete, let token = iterator.next() {
            if eosTokenIds.contains(token) { break }
            generated += 1
            guard let piece = vocabulary[token] else { continue }
            text += piece
            for character in piece {
              _ = follower.advance(character)
            }
          }

          // The iterator evaluates one token ahead; let that settle before the lock is released.
          Stream().synchronize()

          return (
            text, input.text.tokens.size, generated, Date().timeIntervalSince(start),
            follower.isComplete
          )
        }

    guard result.done else {
      throw BrujaError.structuredOutputTruncated(tokenLimit: tokenLimit)
    }

    return ConstrainedOutput(
      text: result.text,
      promptTokens: result.promptTokens,
      generatedTokens: result.generatedTokens,
      vocabularySeconds: vocabularySeconds,
      generationSeconds: result.seconds
    )
  }

  /// Decodes schema-constrained output. The text is decoded as it is, with no clean-up.
  internal static func decodeConstrained<T: Decodable>(_ text: String, as type: T.Type) throws -> T
  {
    do {
      return try JSONDecoder().decode(type, from: Data(text.utf8))
    } catch {
      throw BrujaError.jsonParsingFailed(
        "Decoding failed: \(error.localizedDescription). Response was: \(text.prefix(200))...")
    }
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
