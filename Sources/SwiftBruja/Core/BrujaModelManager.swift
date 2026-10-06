import Foundation
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import SwiftAcervo
import Tokenizers

// MARK: - BrujaModelManager

/// Manages loading LLM models into memory for inference.
///
/// Download, list, info, and delete responsibilities are handled by
/// `Acervo` (SwiftAcervo) directly. This actor is inference-only: it
/// loads models into `ModelContainer` instances, caches them, and
/// validates memory.
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

  /// Vocabulary tables of the loaded models (token id to the text of that token decoded on its
  /// own). Built on first use by ``vocabularyTable(for:)`` and dropped with the container.
  private var vocabularyTables: [String: [Int: String]] = [:]

  private init() {}

  // MARK: - Model Availability

  /// Check if a model is downloaded and available locally
  public nonisolated func isModelAvailable(_ modelId: String) -> Bool {
    Acervo.isModelAvailable(modelId)
  }

  // MARK: - Model Loading

  /// Load a model into memory for inference.
  ///
  /// Loads the specified model from its downloaded location and caches the
  /// container for reuse. Models must be downloaded first via `Acervo.ensureAvailable`
  /// or `Acervo.ensureComponentReady`.
  public func loadModel(_ modelId: String) async throws -> ModelContainer {
    // Return cached model if already loaded
    if let cached = loadedModels[modelId] {
      return cached
    }

    // Verify the model directory is present locally. Use the LOOSE check
    // (config.json present) rather than the strict `isModelAvailable`, which
    // additionally requires the byte-equal manifest *cache* file. A model whose
    // weights/tokenizer/config are all on disk but which lacks that cache (e.g.
    // downloaded by an older flow) is still fully loadable — gating the load on
    // the cache would reject it. If a declared file is genuinely missing, the
    // MLX loader below surfaces a specific error.
    guard Acervo.isModelConfigPresent(modelId) else {
      throw BrujaError.modelNotFound(
        "Model '\(modelId)' not found at \(Acervo.sharedModelsDirectory.path). Ensure it is pre-downloaded."
      )
    }

    // Get model directory and load
    let modelDir = try Acervo.modelDirectory(for: modelId)

    // Validate memory before loading
    let modelSize = (try? Acervo.modelInfo(modelId).sizeBytes) ?? 0
    if modelSize > 0 {
      try BrujaMemory.validateMemoryForModel(sizeBytes: modelSize)
    }

    // Load model from local directory using LLMModelFactory (mlx-swift-lm 3.x API).
    //
    // S2: every `loadContainer(from:using:)` overload requires a concrete
    // `MLXLMCommon.TokenizerLoader`. mlx-swift-lm ships the protocol only, so we
    // supply one via its own `#huggingFaceTokenizerLoader()` macro (OQ-2), which
    // expands to `AutoTokenizer.from(modelFolder:)` — reading the tokenizer from the
    // local model directory offline via swift-transformers. The load is fully local —
    // `Acervo` already placed every file in `modelDir`. (Requires `import Tokenizers`
    // and `import MLXHuggingFace` above for the macro expansion to resolve.)
    let container: ModelContainer
    do {
      container = try await LLMModelFactory.shared.loadContainer(
        from: modelDir,
        using: #huggingFaceTokenizerLoader()
      )
    } catch {
      throw BrujaError.modelLoadFailed(error)
    }

    loadedModels[modelId] = container
    return container
  }

  /// Unload a model to free memory.
  ///
  /// Drops the container, drops the cached vocabulary table, then clears the MLX buffer cache
  /// so the freed buffers go back to the system. The cache is cleared here only, never during
  /// or after a query.
  public func unloadModel(_ modelId: String) {
    loadedModels.removeValue(forKey: modelId)
    vocabularyTables.removeValue(forKey: modelId)
    Memory.clearCache()
  }

  /// Unload all models.
  ///
  /// Drops every container and vocabulary table, then clears the MLX buffer cache.
  public func unloadAllModels() {
    loadedModels.removeAll()
    vocabularyTables.removeAll()
    Memory.clearCache()
  }

  // MARK: - Vocabulary Table

  /// The vocabulary table of a model: token id to the text of that token decoded on its own.
  ///
  /// Loads the model if it is not loaded yet. The table is built once per loaded model and
  /// cached next to its container; schema-constrained generation reads it on every call.
  func vocabularyTable(for modelId: String) async throws -> [Int: String] {
    if let cached = vocabularyTables[modelId] {
      return cached
    }
    let container = try await loadModel(modelId)
    let tokenizer = await container.tokenizer
    let table = Self.makeVocabularyTable(tokenizer: tokenizer)
    // The model can have been unloaded while the table was being built.
    if loadedModels[modelId] != nil {
      vocabularyTables[modelId] = table
    }
    return table
  }

  /// How many consecutive ids with no token end the scan in ``makeVocabularyTable(tokenizer:)``.
  private static let vocabularyGapLimit = 4096

  /// Upper bound on the ids scanned, in case a tokenizer never reports a missing id.
  private static let vocabularyScanLimit = 2_000_000

  /// Builds the vocabulary table by asking the tokenizer for every id in turn.
  ///
  /// `MLXLMCommon.Tokenizer` has no vocabulary-size property, so the ids are found by probing
  /// `convertIdToToken(_:)` upward from 0. An id counts as present when it has a token and that
  /// token maps back to the same id (a tokenizer that answers an unknown id with its unknown
  /// token fails the second test). The scan ends after ``vocabularyGapLimit`` misses in a row.
  ///
  /// The text of an id is `decode(tokenIds: [id])` with special tokens kept, which is the text
  /// the token contributes to a decoded sequence. The exceptions are a token that holds part of
  /// a multi-byte character (it decodes alone to U+FFFD) and a tokenizer that cleans up spaces
  /// across token boundaries.
  nonisolated static func makeVocabularyTable(tokenizer: any MLXLMCommon.Tokenizer) -> [Int: String]
  {
    var table: [Int: String] = [:]
    var misses = 0
    var id = 0
    while misses < vocabularyGapLimit, id < vocabularyScanLimit {
      if let token = tokenizer.convertIdToToken(id), tokenizer.convertTokenToId(token) == id {
        table[id] = tokenizer.decode(tokenIds: [id], skipSpecialTokens: false)
        misses = 0
      } else {
        misses += 1
      }
      id += 1
    }
    return table
  }
}
