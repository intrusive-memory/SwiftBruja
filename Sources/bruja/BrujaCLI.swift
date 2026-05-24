import ArgumentParser
import BrujaHelpers
import Foundation
import MLXLMCommon
import SwiftAcervo
import SwiftBruja

/// On-device LLM inference CLI for Apple Silicon using MLX.
@main
struct BrujaCLI: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "bruja",
    abstract: "On-device LLM inference for Apple Silicon using MLX",
    discussion: """
      Bruja provides fast, private, on-device language model inference using
      Apple's MLX framework. No cloud APIs, no API keys, no network latency.

      Models must be pre-downloaded to ~/Library/SharedModels/ before use.
      Use the 'download' command to fetch models from the CDN.

      Default model: \(SwiftBruja.Bruja.defaultModel)

      Examples:
        bruja "What is the capital of France?"     # Query with default model
        bruja query "Explain quantum computing"    # Explicit query command
        bruja download -m mlx-community/Llama-3-8B # Download specific model
        bruja list                                 # Show downloaded models
        bruja info -m ~/Models/Phi-3              # Show model details
      """,
    version: "1.7.1",
    subcommands: [
      DownloadCommand.self, QueryCommand.self, ChatCommand.self, ListCommand.self, InfoCommand.self,
    ],
    defaultSubcommand: QueryCommand.self
  )
}

// MARK: - Download Command

struct DownloadCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "download",
    abstract: "Download one or more models for local inference",
    discussion: """
      Downloads MLX-compatible models from the CDN for local inference.
      Models are stored in ~/Library/SharedModels/

      Pass `-m` once per model. With a single model, the SwiftAcervo Level 2
      API (`Acervo.ensureAvailable`) is used. With two or more, the Level 1
      batch API (`ModelDownloadManager.ensureModelsAvailable`) is used so
      progress is reported as a cumulative byte fraction across the whole batch.

      MLX-optimized models from mlx-community are recommended for best
      performance on Apple Silicon.

      Popular models:
        mlx-community/Llama-3.2-1B-Instruct-4bit  (~679 MB, lightweight, default)
        mlx-community/Llama-3.2-3B-Instruct-4bit  (~2.1 GB, good balance)
        mlx-community/Qwen2.5-3B-Instruct-4bit    (~1.7 GB, instruction following)

      Examples:
        bruja download -m mlx-community/Llama-3.2-1B-Instruct-4bit
        bruja download -m mlx-community/Llama-3.2-1B-Instruct-4bit --force
        bruja download -m mlx-community/Llama-3.2-1B-Instruct-4bit \\
                       -m mlx-community/Qwen2.5-3B-Instruct-4bit
      """
  )

  @Option(
    name: [.short, .long],
    parsing: .singleValue,
    help: "Model ID (repeatable, e.g., -m mlx-community/Phi-3-mini-4k-instruct-4bit)")
  var model: [String]

  @Flag(name: .long, help: "Force re-download even if model already exists locally")
  var force = false

  @Flag(name: .shortAndLong, help: "Suppress progress output")
  var quiet = false

  func validate() throws {
    guard !model.isEmpty else {
      throw ValidationError("At least one --model/-m is required.")
    }
  }

  func run() async throws {
    try await runCLI {
      let renderer = ProgressRenderer(quiet: quiet)
      await renderer.logStartup("[bruja] SharedModels: \(Acervo.sharedModelsDirectory.path)")

      if force {
        for modelId in model {
          try? Acervo.deleteModel(modelId)
        }
      }

      if model.count == 1 {
        try await runSingleModel(model[0], renderer: renderer)
      } else {
        try await runBatch(model, renderer: renderer)
      }
    }
  }

  private func runSingleModel(_ modelId: String, renderer: ProgressRenderer) async throws {
    if !quiet {
      print("Downloading \(modelId) from CDN to \(Acervo.sharedModelsDirectory.path)...")
    }

    let progressCallback = renderer.makeProgressCallback()
    do {
      try await Acervo.ensureAvailable(modelId, files: []) { acervoProgress in
        progressCallback(acervoProgress.overallProgress)
      }
    } catch AcervoError.manifestDownloadFailed(let statusCode) where statusCode == 404 {
      // The CDN returns 404 when a model has no manifest — treat as "not published".
      throw CLIError("Model '\(modelId)' is not published on the CDN.")
    }

    await renderer.reportCompletion(modelId: modelId)
  }

  private func runBatch(_ modelIds: [String], renderer: ProgressRenderer) async throws {
    if !quiet {
      print(
        "Downloading \(modelIds.count) models from CDN to \(Acervo.sharedModelsDirectory.path)...")
    }

    let progressCallback = renderer.makeProgressCallback()
    do {
      try await ModelDownloadManager.shared.ensureModelsAvailable(modelIds) { progress in
        progressCallback(progress.fraction)
      }
    } catch AcervoError.manifestDownloadFailed(let statusCode) where statusCode == 404 {
      throw CLIError("One of the requested models is not published on the CDN (HTTP 404).")
    }

    await renderer.reportCompletion(modelId: modelIds.joined(separator: ", "))
  }
}

// MARK: - Query Command

struct QueryCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "query",
    abstract: "Query a language model with a prompt",
    discussion: """
      Send a prompt to a local language model and receive a response.
      The model must be pre-downloaded to ~/Library/SharedModels/.

      The default model (\(SwiftBruja.Bruja.defaultModel)) is optimized
      for instruction-following and general Q&A tasks.

      Parameters:
        --temperature: Controls randomness (0.0 = deterministic, 1.0 = creative)
        --max-tokens: Maximum response length in tokens
        --system: System prompt to set model behavior

      Examples:
        bruja "What is the capital of France?"
        bruja query "Explain quantum computing" -m mlx-community/Llama-3-8B
        bruja "Write a haiku" --temperature 0.9 --max-tokens 100
        bruja "Summarize this text" --system "You are a helpful assistant"
        bruja "List 5 programming languages" --json
      """
  )

  @Argument(help: "The prompt to send to the model")
  var prompt: String

  @Option(
    name: [.short, .long],
    help: "Model path or ID (default: \(SwiftBruja.Bruja.defaultModel))")
  var model: String = SwiftBruja.Bruja.defaultModel

  @Option(name: .long, help: "Sampling temperature (0.0-1.0, default: 0.7)")
  var temperature: Float = 0.7

  @Option(name: .long, help: "Maximum tokens to generate (default: 4096)")
  var maxTokens: Int = 4096

  @Option(name: .long, help: "System prompt to set model behavior/persona")
  var system: String?

  @Flag(name: .long, help: "Output response as JSON with metadata (model, tokens, duration)")
  var json = false

  @Flag(name: .shortAndLong, help: "Suppress non-response output")
  var quiet = false

  func run() async throws {
    try await runCLI {
      let renderer = ProgressRenderer(quiet: quiet)
      await renderer.logStartup("[bruja] SharedModels: \(Acervo.sharedModelsDirectory.path)")

      let result = try await SwiftBruja.Bruja.queryWithMetadata(
        prompt,
        model: model,
        temperature: temperature,
        maxTokens: maxTokens,
        system: system
      )

      if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(result)
        print(String(data: data, encoding: .utf8)!)
      } else {
        print(result.response)
      }
    }
  }
}

// MARK: - Chat Command

struct ChatCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "chat",
    abstract: "Interactive multi-turn chat with a language model",
    discussion: """
      Start an interactive chat session with a local language model.
      The model is loaded once and maintains context across turns.
      Responses are streamed token-by-token.

      Commands:
        /quit   — Exit the chat session
        /clear  — Reset conversation history (keeps model loaded)

      Examples:
        bruja chat
        bruja chat -m mlx-community/Llama-3.2-3B-Instruct-4bit
        bruja chat --system "You are a pirate" --temperature 0.9
      """
  )

  @Option(
    name: [.short, .long],
    help: "Model path or ID (default: \(SwiftBruja.Bruja.defaultModel))")
  var model: String = SwiftBruja.Bruja.defaultModel

  @Option(name: .long, help: "Sampling temperature (0.0-1.0, default: 0.7)")
  var temperature: Float = 0.7

  @Option(name: .long, help: "Maximum tokens per response (default: auto-tuned)")
  var maxTokens: Int?

  @Option(name: .long, help: "System prompt to set model behavior/persona")
  var system: String?

  @Flag(name: .shortAndLong, help: "Suppress startup and informational output")
  var quiet = false

  func run() async throws {
    try await runCLI {
      let renderer = ProgressRenderer(quiet: quiet)
      await renderer.logStartup("[bruja] SharedModels: \(Acervo.sharedModelsDirectory.path)")

      // Resolve maxTokens
      let resolvedMaxTokens: Int
      if let maxTokens {
        resolvedMaxTokens = maxTokens
      } else {
        let modelSize = (try? SwiftBruja.Bruja.modelInfo(at: model).sizeBytes) ?? 0
        resolvedMaxTokens = SwiftBruja.BrujaMemory.recommendedMaxTokens(modelSizeBytes: modelSize)
      }

      print("Loading model: \(model)...")
      let container = try await SwiftBruja.Bruja.loadModel(model)

      let instructions =
        system ?? "You are a helpful AI assistant. Be concise and direct in your responses."
      var session = ChatSession(
        container,
        instructions: instructions,
        generateParameters: GenerateParameters(
          maxTokens: resolvedMaxTokens, temperature: temperature)
      )

      let modelShort = model.components(separatedBy: "/").last ?? model
      print("Model loaded: \(modelShort) (maxTokens: \(resolvedMaxTokens))")
      print("Type /quit to exit, /clear to reset conversation.\n")

      while true {
        print("> ", terminator: "")
        fflush(stdout)

        guard let input = readLine() else {
          // EOF (Ctrl+D)
          print("")
          break
        }

        let trimmed = input.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
          continue
        }

        if trimmed.lowercased() == "/quit" {
          break
        }

        if trimmed.lowercased() == "/clear" {
          await session.clear()
          session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(
              maxTokens: resolvedMaxTokens, temperature: temperature)
          )
          print("[Conversation cleared]\n")
          continue
        }

        let stream = session.streamResponse(to: trimmed)
        do {
          for try await chunk in stream {
            print(chunk, terminator: "")
            fflush(stdout)
          }
          print("\n")
        } catch {
          print("\n[Error: \(error.localizedDescription)]\n")
        }
      }

      await session.synchronize()
    }
  }
}

// MARK: - List Command

struct ListCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List downloaded models",
    discussion: """
      Shows all models that have been downloaded and cached locally.
      Models are stored in ~/Library/SharedModels/

      Use --json for machine-readable output with full metadata including
      model ID, path, size, and download date.

      Examples:
        bruja list                          # List models in default directory
        bruja list --json                   # Output as JSON
      """
  )

  @Flag(name: .long, help: "Output as JSON with full metadata")
  var json = false

  @Flag(name: .shortAndLong, help: "Suppress startup and informational output")
  var quiet = false

  func run() async throws {
    try await runCLI {
      let renderer = ProgressRenderer(quiet: quiet)
      await renderer.logStartup("[bruja] SharedModels: \(Acervo.sharedModelsDirectory.path)")

      let models = try SwiftBruja.Bruja.listModels()

      if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(models)
        print(String(data: data, encoding: .utf8)!)
      } else {
        if models.isEmpty {
          print("No models found in \(Acervo.sharedModelsDirectory.path)")
        } else {
          print("Downloaded models in \(Acervo.sharedModelsDirectory.path):\n")
          for model in models {
            print("• \(model.id) (\(formatBytes(model.sizeBytes)))")
          }
        }
      }
    }
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
}

// MARK: - Info Command

struct InfoCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "info",
    abstract: "Show detailed information about a model",
    discussion: """
      Displays metadata about a specific downloaded model including its
      ID, file path, size on disk, and download date.

      You can specify the model by its local path or model ID
      (if already downloaded).

      Examples:
        bruja info -m mlx-community/Llama-3.2-1B-Instruct-4bit
        bruja info -m ~/Library/SharedModels/mlx-community_Llama-3.2-1B-Instruct-4bit
        bruja info -m ~/MyModels/custom-model --json
      """
  )

  @Option(name: [.short, .long], help: "Model path or ID")
  var model: String

  @Flag(name: .long, help: "Output as JSON with full metadata")
  var json = false

  @Flag(name: .long, help: "Fetch manifest from CDN (no download); prints Remote/Files/Size")
  var remote: Bool = false

  @Flag(name: .shortAndLong, help: "Suppress startup and informational output")
  var quiet = false

  func run() async throws {
    try await runCLI {
      let renderer = ProgressRenderer(quiet: quiet)
      await renderer.logStartup("[bruja] SharedModels: \(Acervo.sharedModelsDirectory.path)")

      if remote {
        // --remote: fetch manifest from CDN without downloading any files
        let manifest = try await Acervo.fetchManifest(for: model)
        let files = manifest.files
        let totalBytes = files.reduce(Int64(0)) { $0 + $1.sizeBytes }
        print("Remote: \(model)")
        print("Files: \(files.count)")
        print("Size: \(formatBytes(totalBytes))")
      } else {
        let info = try SwiftBruja.Bruja.modelInfo(at: model)

        if json {
          let encoder = JSONEncoder()
          encoder.outputFormatting = [.prettyPrinted]
          encoder.dateEncodingStrategy = .iso8601
          let data = try encoder.encode(info)
          print(String(data: data, encoding: .utf8)!)
        } else {
          print("Model: \(info.id)")
          print("Path: \(info.path)")
          print("Size: \(formatBytes(info.sizeBytes))")
          print("Downloaded: \(info.downloadDate)")
        }
      }
    }
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
}
