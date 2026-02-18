# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

For detailed project documentation, architecture, and development guidelines, see **[AGENTS.md](AGENTS.md)**.

## Quick Reference

**Project**: SwiftBruja - One-line local LLM queries on Apple Silicon

**Platforms**: iOS 26.0+, macOS 26.0+ (Apple Silicon only)

**Purpose**: Make local LLM queries as simple as possible. One import, one line, zero configuration.

**Key Components**:
- Static `Bruja` API for one-line queries with auto-download
- `bruja` CLI for model management
- Auto-tuned memory management (maxTokens based on available RAM)
- Structured output via `Codable`

**Important Notes**:
- **Apple Silicon only** - NO Intel support (requires Metal/MLX)
- ONLY supports iOS 26.0+ and macOS 26.0+ (NEVER add code for older platforms)
- MUST build with `xcodebuild` or `make` (Metal shaders required)
- `swift build` compiles but won't run queries (shaders missing)
- See [AGENTS.md](AGENTS.md) for complete API reference, memory management, workflow, and architecture

// Override maxTokens explicitly
let response = try await Bruja.query("Your prompt", model: modelId, maxTokens: 2048)

// Structured output
struct Result: Codable { let answer: String }
let result: Result = try await Bruja.query("...", as: Result.self)

// Query with metadata (timing, tokens)
let result = try await Bruja.queryWithMetadata("Your prompt")
print("Duration: \(result.durationSeconds)s")

// Model management
try await Bruja.download(model: modelID, to: destinationURL)
let exists = Bruja.modelExists(at: modelPath)
let models = try Bruja.listModels()
```

### CLI Installation

```bash
# Homebrew (recommended)
brew install intrusive-memory/tap/bruja

# Or build from source
make install    # Debug build → ./bin/bruja
make release    # Release build → ./bin/bruja
make dist       # Release build + distributable tarball → ./dist/
```

### CLI Commands

```bash
bruja query "Your prompt" --model "mlx-community/Qwen3-Coder-Next-4bit"
bruja chat                                # Interactive multi-turn REPL
bruja chat --system "You are a pirate"    # Chat with custom persona
bruja download --model "mlx-community/Qwen3-Coder-Next-4bit"
bruja list
bruja info --model <path>
```

## Key Types

```swift
/// Query result with metadata
public struct BrujaQueryResult: Codable, Sendable {
    public let response: String
    public let model: String
    public let modelPath: String
    public let tokensGenerated: Int
    public let durationSeconds: Double
}

/// Model information
public struct BrujaModelInfo: Codable, Sendable {
    public let id: String
    public let path: String
    public let sizeBytes: Int64
    public let downloadDate: Date
}

/// Memory utilities
public enum BrujaMemory {
    static func availableMemory() -> UInt64
    static func recommendedMaxTokens(modelSizeBytes: Int64) -> Int
    static func validateMemoryForModel(sizeBytes: Int64) throws  // throws BrujaError.insufficientMemory
}
```

## Default Values

- **Default model**: `mlx-community/Qwen3-Coder-Next-4bit`
- **Models directory**: `~/Library/Caches/intrusive-memory/Models/LLM/` (see **Shared Model Cache** below)
- **Temperature**: 0.7
- **Max tokens**: Auto-tuned based on available memory (see below). Pass explicitly to override.

## Memory Management

SwiftBruja automatically manages memory via `BrujaMemory`:

- **Pre-load validation**: Before loading a model, checks that the model size doesn't exceed 80% of available memory. Throws `BrujaError.insufficientMemory` if it does.
- **Auto-tuned maxTokens**: When `maxTokens` is not explicitly passed (defaults to `nil`), it is automatically set based on available memory after accounting for model size:
  - **≤ 32 GB available**: 4096 tokens (minimum floor)
  - **> 32 GB**: 8192 tokens
- **Info logging**: The resolved `maxTokens` value is printed to stdout for each query: `[SwiftBruja] maxTokens set to N for this query`
- Callers can always override by passing an explicit `maxTokens` value.

## Package Structure

```
SwiftBruja/
├── Sources/
│   ├── SwiftBruja/           # Library
│   │   ├── Bruja.swift       # Main entry point (static API)
│   │   └── Core/
│   │       ├── BrujaModelManager.swift  # Download & load models
│   │       ├── BrujaQuery.swift         # Query execution
│   │       ├── BrujaMemory.swift        # Memory checks & maxTokens auto-tuning
│   │       ├── BrujaTypes.swift         # Result types
│   │       └── BrujaError.swift         # Error handling
│   └── bruja/                # CLI executable
│       └── BrujaCLI.swift
└── Tests/
    └── SwiftBrujaTests/
```

## Dependencies

- `mlx-swift` - Core MLX framework for Apple Silicon
- `mlx-swift-lm` - LLM inference (MLXLLM, MLXLMCommon)
- `swift-transformers` - HuggingFace Hub API
- `swift-argument-parser` - CLI parsing

## Building

```bash
# For fully functional builds (required for running queries)
make build      # Debug build with xcodebuild (includes Metal shaders)
make install    # Debug build + copy to ./bin/bruja
make release    # Release build + copy to ./bin/bruja
make dist       # Release build + distributable tarball → ./dist/
make test       # Run tests with xcodebuild

# NEVER use swift build or swift test — Metal shaders require xcodebuild
```

## Development Workflow

**See [`.claude/WORKFLOW.md`](.claude/WORKFLOW.md) for complete workflow.**

- **Branch**: `development` → PR → `main`
- **CI Required**: Code Quality + macOS Tests + Integration Tests must pass
- **Integration Tests**: Build CLI via `make dist`, verify binary and Metal bundle
- **Platforms**: macOS 26+, iOS 26+ (Apple Silicon only)
- **Never** add `@available` checks for older platforms
- **Never** commit directly to `main`

### Branch Protection (Required Status Checks)

```
Code Quality
macOS Tests
Integration Tests
```

## Shared Model Cache

All `intrusive-memory` projects share a common model cache hierarchy under `~/Library/Caches/intrusive-memory/Models/`. Each project stores its models in a type-specific subdirectory:

| Project | Cache path |
|---------|-----------|
| **SwiftBruja** (LLM) | `~/Library/Caches/intrusive-memory/Models/LLM/<namespace>_<repo>/` |
| **mlx-audio-swift** (Audio) | `~/Library/Caches/intrusive-memory/Models/Audio/<namespace>_<repo>/` |

The `<namespace>_<repo>` directory name is the HuggingFace repo ID with `/` replaced by `_` (e.g., `mlx-community/Phi-3-mini-4k-instruct-4bit` becomes `mlx-community_Phi-3-mini-4k-instruct-4bit`).

If you add a new model cache path, always use the `intrusive-memory/Models/` hierarchy. The implementation is in `BrujaModelManager.modelsDirectory`.

## Design Principles

1. **Simplicity over flexibility**: One import, one line to query
2. **Sensible defaults**: Works out of the box with default model
3. **Progressive disclosure**: Simple API for simple use cases, more options available when needed
4. **Privacy first**: Everything runs on-device, no cloud required
5. **Swift-native**: Async/await, Codable, Sendable - follows modern Swift patterns
