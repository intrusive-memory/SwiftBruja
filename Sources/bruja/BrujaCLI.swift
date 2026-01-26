import ArgumentParser
import Foundation
import SwiftBruja

@main
struct Bruja: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bruja",
        abstract: "On-device LLM for Apple Silicon",
        version: "1.0.0",
        subcommands: [Download.self, Query.self, List.self, Info.self],
        defaultSubcommand: Query.self
    )
}

// MARK: - Download Command

struct Download: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Download a model from HuggingFace"
    )

    @Option(name: [.short, .long], help: "HuggingFace model ID")
    var model: String

    @Option(name: [.short, .long], help: "Download destination")
    var destination: String?

    @Flag(help: "Re-download even if model exists")
    var force = false

    @Flag(help: "Suppress progress output")
    var quiet = false

    func run() async throws {
        let destURL = destination.map { URL(fileURLWithPath: $0) }
            ?? SwiftBruja.Bruja.defaultModelsDirectory

        if !quiet {
            print("Downloading \(model) to \(destURL.path)...")
        }

        try await SwiftBruja.Bruja.download(
            model: model,
            to: destURL,
            force: force
        ) { progress in
            if !quiet {
                print("\r\(Int(progress * 100))%", terminator: "")
                fflush(stdout)
            }
        }

        if !quiet {
            print("\nDownload complete.")
        }
    }
}

// MARK: - Query Command

struct Query: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Query a model"
    )

    @Argument(help: "The prompt to send to the model")
    var prompt: String

    @Option(name: [.short, .long], help: "Model path or HuggingFace ID")
    var model: String

    @Option(name: [.short, .long], help: "Download destination for HuggingFace models")
    var destination: String?

    @Option(help: "Sampling temperature")
    var temperature: Float = 0.7

    @Option(help: "Maximum tokens to generate")
    var maxTokens: Int = 512

    @Option(help: "System prompt")
    var system: String?

    @Flag(help: "Output as JSON")
    var json = false

    @Flag(help: "Suppress non-response output")
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

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List downloaded models"
    )

    @Option(name: [.short, .long], help: "Models directory")
    var path: String?

    @Flag(help: "Output as JSON")
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

struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show model information"
    )

    @Option(name: [.short, .long], help: "Model path or HuggingFace ID")
    var model: String

    @Flag(help: "Output as JSON")
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
