# SwiftBruja - AI Assistant Instructions

## What is SwiftBruja?

**SwiftBruja** ("Swift Witch") is a Swift package for on-device LLM inference on Apple Silicon. It provides:

1. **`bruja` CLI** - Command-line tool for downloading models and running queries
2. **SwiftBruja library** - Swift API for programmatic access to the same functionality

## Quick Reference

### CLI Commands

```bash
# Download a model
bruja download --model "mlx-community/Phi-3-mini-4k-instruct-4bit"

# Query a model
bruja query "Your prompt here" --model ~/Models/Phi-3-mini-4k-instruct-4bit

# Query with JSON output
bruja query "Your prompt" --model <path> --json

# List downloaded models
bruja list
```

### Library API

```swift
import SwiftBruja

// Simple query
let response = try await Bruja.query("Your prompt", model: modelPath)

// Query with auto-download
let response = try await Bruja.query(
    "Your prompt",
    model: "mlx-community/Phi-3-mini-4k-instruct-4bit"
)

// Structured output
struct Result: Codable { let answer: String }
let result: Result = try await Bruja.query("...", as: Result.self, model: modelPath)

// Download model
try await Bruja.download(model: modelID, to: destinationURL)

// Check if model exists
let exists = Bruja.modelExists(at: modelPath)
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
│   │   ├── Bruja.swift       # Main entry point
│   │   ├── Core/
│   │   │   ├── BrujaModelManager.swift
│   │   │   ├── BrujaQuery.swift
│   │   │   └── BrujaError.swift
│   │   └── StructuredOutput/
│   │       └── ResponseParser.swift
│   └── bruja/                # CLI executable
│       └── main.swift
└── Tests/
```

## Dependencies

- `mlx-swift` - Core MLX framework
- `mlx-swift-lm` - LLM inference (MLXLLM, Hub)
- `swift-argument-parser` - CLI parsing

## Platform Requirements

- **macOS 26.0+** / **iOS 26.0+**
- **Apple Silicon only** (M1/M2/M3/M4)

## When to Use SwiftBruja

Use SwiftBruja when you need to:
- Run LLM queries locally without cloud APIs
- Download and manage HuggingFace models
- Get structured (typed) responses from an LLM
- Build CLI tools that use local LLMs

## Example: Generate PROJECT.md

```swift
import SwiftBruja

// Analyze a folder and generate PROJECT.md content
let folderContents = describeFolder(at: folderURL)
let prompt = """
Analyze this project folder and generate a PROJECT.md file with YAML frontmatter.
Folder contents: \(folderContents)
"""

struct ProjectMd: Codable {
    let title: String
    let description: String
    let author: String
    let tags: [String]
}

let result: ProjectMd = try await Bruja.query(prompt, as: ProjectMd.self, model: modelPath)
```

## Development Workflow

- **Branch**: `development` → PR → `main`
- **Platforms**: macOS 26+, iOS 26+ only
- **Never** add `@available` checks for older platforms
