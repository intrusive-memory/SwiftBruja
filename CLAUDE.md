# SwiftBruja - Claude Code Instructions

## Purpose

**SwiftBruja exists for one reason: to make local LLM queries as simple as possible.**

```swift
import SwiftBruja

let response = try await Bruja.query("Your question here")
```

That's it. One import, one line. SwiftBruja handles:
- Model downloading from HuggingFace
- Model loading and caching
- Tokenization and inference
- GPU acceleration via Metal/MLX

**No cloud APIs. No API keys. No network latency. Just fast, private, on-device AI.**

## What SwiftBruja Provides

1. **`Bruja` API** - Static methods for querying LLMs with minimal code
2. **`bruja` CLI** - Command-line tool for queries and model management
3. **Auto-download** - Pass a HuggingFace model ID, it downloads automatically
4. **Structured output** - Get typed responses with `Bruja.query(as: MyType.self)`

## Platform Requirements

**CRITICAL: Apple Silicon Only**

- **macOS 26.0+** (Apple Silicon M1/M2/M3/M4 only)
- **iOS 26.0+** (Apple Silicon only)
- **Swift 6.2+**
- **NO Intel support** - MLX requires Apple Silicon GPU

**Build Requirements:**
- Use `xcodebuild` for functional builds (Metal shaders must be compiled)
- `swift build` compiles but Metal shaders won't load at runtime
- Never add `@available` checks for older platforms

## Quick Reference

### Library API

```swift
import SwiftBruja

// Simple query (uses default model)
let response = try await Bruja.query("Your prompt")

// Query specific model (auto-downloads if needed)
let response = try await Bruja.query(
    "Your prompt",
    model: "mlx-community/Phi-3-mini-4k-instruct-4bit"
)

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

### CLI Commands

```bash
bruja query "Your prompt" --model "mlx-community/Phi-3-mini-4k-instruct-4bit"
bruja download --model "mlx-community/Phi-3-mini-4k-instruct-4bit"
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
```

## Default Values

- **Default model**: `mlx-community/Phi-3-mini-4k-instruct-4bit`
- **Models directory**: `~/Library/Application Support/SwiftBruja/Models/`
- **Temperature**: 0.7
- **Max tokens**: 512

## Package Structure

```
SwiftBruja/
├── Sources/
│   ├── SwiftBruja/           # Library
│   │   ├── Bruja.swift       # Main entry point (static API)
│   │   └── Core/
│   │       ├── BrujaModelManager.swift  # Download & load models
│   │       ├── BrujaQuery.swift         # Query execution
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
# For development/testing (Metal shaders won't work)
swift build

# For fully functional builds (required for running queries)
xcodebuild -scheme bruja -destination 'platform=OS X' build

# Run tests
swift test
```

## Development Workflow

**See [`.claude/WORKFLOW.md`](.claude/WORKFLOW.md) for complete workflow.**

- **Branch**: `development` → PR → `main`
- **CI Required**: Code Quality + macOS Tests must pass
- **Platforms**: macOS 26+, iOS 26+ (Apple Silicon only)
- **Never** add `@available` checks for older platforms
- **Never** commit directly to `main`

## Design Principles

1. **Simplicity over flexibility**: One import, one line to query
2. **Sensible defaults**: Works out of the box with default model
3. **Progressive disclosure**: Simple API for simple use cases, more options available when needed
4. **Privacy first**: Everything runs on-device, no cloud required
5. **Swift-native**: Async/await, Codable, Sendable - follows modern Swift patterns
