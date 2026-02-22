import ArgumentParser
import Foundation
import MLXLMCommon
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
            in ~/Library/Caches/intrusive-memory/Models/LLM/

            Default model: \(SwiftBruja.Bruja.defaultModel)

            Examples:
              bruja "What is the capital of France?"     # Query with default model
              bruja query "Explain quantum computing"    # Explicit query command
              bruja download -m mlx-community/Llama-3-8B # Download specific model
              bruja list                                 # Show downloaded models
              bruja info -m ~/Models/Phi-3              # Show model details
            """,
        version: "1.1.0",
        subcommands: [DownloadCommand.self, QueryCommand.self, ChatCommand.self, ListCommand.self, InfoCommand.self],
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
            Models are stored in ~/Library/Caches/intrusive-memory/Models/LLM/
            by default.

            MLX-optimized models from mlx-community are recommended for best
            performance on Apple Silicon.

            Popular models:
              mlx-community/Qwen3-Coder-Next-4bit       (80B/3B active, coding agent, default)
              mlx-community/Qwen2.5-7B-Instruct-4bit    (~4.4 GB, general purpose)
              mlx-community/Llama-3.2-3B-Instruct-4bit  (~2.1 GB, good balance)

            Examples:
              bruja download -m mlx-community/Qwen3-Coder-Next-4bit
              bruja download -m mlx-community/Llama-3.2-3B-Instruct-4bit --destination ~/Models
              bruja download -m mlx-community/Qwen3-Coder-Next-4bit --force
            """
    )

    @Option(name: [.short, .long], help: "HuggingFace model ID (e.g., mlx-community/Phi-3-mini-4k-instruct-4bit)")
    var model: String

    @Option(name: [.short, .long], help: "Download destination directory (default: ~/Library/Caches/intrusive-memory/Models/LLM/)")
    var destination: String?

    @Flag(name: .long, help: "Force re-download even if model already exists locally")
    var force = false

    @Flag(name: .shortAndLong, help: "Suppress progress output")
    var quiet = false

    func run() async throws {
        let showProgress = !quiet

        if showProgress {
            print("Downloading \(model) to \(SwiftBruja.Bruja.defaultModelsDirectory.path)...")
        }

        try await SwiftBruja.Bruja.download(
            model: model,
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

    @Option(name: [.short, .long], help: "Download destination for HuggingFace models (default: ~/Library/Caches/intrusive-memory/Models/LLM/)")
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

    @Option(name: [.short, .long], help: "Model path or HuggingFace ID (default: \(SwiftBruja.Bruja.defaultModel))")
    var model: String = SwiftBruja.Bruja.defaultModel

    @Option(name: [.short, .long], help: "Download destination for HuggingFace models")
    var destination: String?

    @Option(name: .long, help: "Sampling temperature (0.0-1.0, default: 0.7)")
    var temperature: Float = 0.7

    @Option(name: .long, help: "Maximum tokens per response (default: auto-tuned)")
    var maxTokens: Int?

    @Option(name: .long, help: "System prompt to set model behavior/persona")
    var system: String?

    func run() async throws {
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

        let instructions = system ?? "You are a helpful AI assistant. Be concise and direct in your responses."
        var session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(maxTokens: resolvedMaxTokens, temperature: temperature)
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
                    generateParameters: GenerateParameters(maxTokens: resolvedMaxTokens, temperature: temperature)
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

// MARK: - List Command

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List downloaded models",
        discussion: """
            Shows all models that have been downloaded and cached locally.
            Models are stored in ~/Library/Caches/intrusive-memory/Models/LLM/
            by default.

            Use --json for machine-readable output with full metadata including
            model ID, path, size, and download date.

            Examples:
              bruja list                          # List models in default directory
              bruja list --path ~/MyModels        # List models in custom directory
              bruja list --json                   # Output as JSON
            """
    )

    @Option(name: [.short, .long], help: "Models directory to scan (default: ~/Library/Caches/intrusive-memory/Models/LLM/)")
    var path: String?

    @Flag(name: .long, help: "Output as JSON with full metadata")
    var json = false

    func run() async throws {
        let modelsDir = SwiftBruja.Bruja.defaultModelsDirectory

        let models = try SwiftBruja.Bruja.listModels()

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
              bruja info -m mlx-community/Qwen3-Coder-Next-4bit
              bruja info -m ~/Library/Caches/intrusive-memory/Models/LLM/Qwen3-Coder-Next
              bruja info -m ~/MyModels/custom-model --json
            """
    )

    @Option(name: [.short, .long], help: "Model path or HuggingFace ID")
    var model: String

    @Flag(name: .long, help: "Output as JSON with full metadata")
    var json = false

    func run() async throws {
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

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
