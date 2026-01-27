import ArgumentParser
import Foundation
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

            Models are automatically downloaded from HuggingFace and cached locally
            in ~/Library/Application Support/SwiftBruja/Models/

            Default model: \(SwiftBruja.Bruja.defaultModel)

            Examples:
              bruja "What is the capital of France?"     # Query with default model
              bruja query "Explain quantum computing"    # Explicit query command
              bruja download -m mlx-community/Llama-3-8B # Download specific model
              bruja list                                 # Show downloaded models
              bruja info -m ~/Models/Phi-3              # Show model details
            """,
        version: "1.0.3",
        subcommands: [DownloadCommand.self, QueryCommand.self, ListCommand.self, InfoCommand.self],
        defaultSubcommand: QueryCommand.self
    )
}

// MARK: - Download Command

struct DownloadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "download",
        abstract: "Download a model from HuggingFace",
        discussion: """
            Downloads an MLX-compatible model from HuggingFace for local inference.
            Models are stored in ~/Library/Application Support/SwiftBruja/Models/
            by default.

            MLX-optimized models from mlx-community are recommended for best
            performance on Apple Silicon.

            Popular models:
              mlx-community/Phi-3-mini-4k-instruct-4bit  (~2.15 GB, fast)
              mlx-community/Llama-3-8B-Instruct-4bit    (~4.5 GB, capable)
              mlx-community/Mistral-7B-Instruct-v0.3-4bit (~4 GB, balanced)

            Examples:
              bruja download -m mlx-community/Phi-3-mini-4k-instruct-4bit
              bruja download -m mlx-community/Llama-3-8B --destination ~/Models
              bruja download -m mlx-community/Phi-3-mini-4k-instruct-4bit --force
            """
    )

    @Option(name: [.short, .long], help: "HuggingFace model ID (e.g., mlx-community/Phi-3-mini-4k-instruct-4bit)")
    var model: String

    @Option(name: [.short, .long], help: "Download destination directory (default: ~/Library/Application Support/SwiftBruja/Models/)")
    var destination: String?

    @Flag(name: .long, help: "Force re-download even if model already exists locally")
    var force = false

    @Flag(name: .shortAndLong, help: "Suppress progress output")
    var quiet = false

    func run() async throws {
        let destURL = destination.map { URL(fileURLWithPath: $0) }
            ?? SwiftBruja.Bruja.defaultModelsDirectory

        let showProgress = !quiet

        if showProgress {
            print("Downloading \(model) to \(destURL.path)...")
        }

        try await SwiftBruja.Bruja.download(
            model: model,
            to: destURL,
            force: force
        ) { progress in
            if showProgress {
                print("\r\(Int(progress * 100))%", terminator: "")
                fflush(stdout)
            }
        }

        if showProgress {
            print("\nDownload complete.")
        }
    }
}

// MARK: - Query Command

struct QueryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Query a language model with a prompt",
        discussion: """
            Send a prompt to a local language model and receive a response.
            If the model is not downloaded, it will be fetched automatically.

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

    @Option(name: [.short, .long], help: "Model path or HuggingFace ID (default: \(SwiftBruja.Bruja.defaultModel))")
    var model: String = SwiftBruja.Bruja.defaultModel

    @Option(name: [.short, .long], help: "Download destination for HuggingFace models (default: ~/Library/Application Support/SwiftBruja/Models/)")
    var destination: String?

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
        let result = try await SwiftBruja.Bruja.queryWithMetadata(
            prompt,
            model: model,
            downloadDestination: destination.map { URL(fileURLWithPath: $0) },
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

// MARK: - List Command

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List downloaded models",
        discussion: """
            Shows all models that have been downloaded and cached locally.
            Models are stored in ~/Library/Application Support/SwiftBruja/Models/
            by default.

            Use --json for machine-readable output with full metadata including
            model ID, path, size, and download date.

            Examples:
              bruja list                          # List models in default directory
              bruja list --path ~/MyModels        # List models in custom directory
              bruja list --json                   # Output as JSON
            """
    )

    @Option(name: [.short, .long], help: "Models directory to scan (default: ~/Library/Application Support/SwiftBruja/Models/)")
    var path: String?

    @Flag(name: .long, help: "Output as JSON with full metadata")
    var json = false

    func run() async throws {
        let modelsDir = path.map { URL(fileURLWithPath: $0) }
            ?? SwiftBruja.Bruja.defaultModelsDirectory

        let models = try SwiftBruja.Bruja.listModels(in: modelsDir)

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(models)
            print(String(data: data, encoding: .utf8)!)
        } else {
            if models.isEmpty {
                print("No models found in \(modelsDir.path)")
            } else {
                print("Downloaded models in \(modelsDir.path):\n")
                for model in models {
                    print("• \(model.id) (\(formatBytes(model.sizeBytes)))")
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

            You can specify the model by its local path or HuggingFace ID
            (if already downloaded).

            Examples:
              bruja info -m mlx-community/Phi-3-mini-4k-instruct-4bit
              bruja info -m ~/Library/Application\\ Support/SwiftBruja/Models/Phi-3
              bruja info -m ~/MyModels/custom-model --json
            """
    )

    @Option(name: [.short, .long], help: "Model path or HuggingFace ID")
    var model: String

    @Flag(name: .long, help: "Output as JSON with full metadata")
    var json = false

    func run() async throws {
        let info = try await SwiftBruja.Bruja.modelInfo(at: model)

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

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
