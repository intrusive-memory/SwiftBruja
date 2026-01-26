# SwiftBruja

**One import. One line. Local LLM queries on Apple Silicon.**

SwiftBruja wraps the complexity of MLX, model downloading, and inference into a single, simple API. No cloud APIs, no API keys, no network latency - just fast, private, on-device AI.

```swift
import SwiftBruja

let response = try await Bruja.query("What is the capital of France?")
// "The capital of France is Paris."
```

## Why SwiftBruja?

- **Single Import**: One package gives you everything - model management, downloading, and inference
- **One-Line Queries**: `Bruja.query()` handles model loading, tokenization, and generation
- **Auto-Download**: Pass a HuggingFace model ID and it downloads automatically
- **Structured Output**: Get typed responses with `Bruja.query(as: MyType.self)`
- **No Cloud Required**: Runs entirely on-device using Apple Silicon GPU
- **Privacy First**: Your prompts never leave your device

## Requirements

- **macOS 26.0+** or **iOS 26.0+**
- **Apple Silicon only** (M1/M2/M3/M4) - NO Intel support
- **Swift 6.2+**
- ~2-4 GB storage per model

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/intrusive-memory/SwiftBruja", from: "1.0.0-beta")
]
```

## Quick Start

### Simplest Usage

```swift
import SwiftBruja

// Query with auto-download (downloads model if needed)
let response = try await Bruja.query(
    "Explain quantum computing in one sentence",
    model: "mlx-community/Phi-3-mini-4k-instruct-4bit"
)
```

### Structured Output

```swift
import SwiftBruja

struct Analysis: Codable {
    let sentiment: String
    let confidence: Double
    let keywords: [String]
}

let result: Analysis = try await Bruja.query(
    "Analyze: 'I love this product!'",
    as: Analysis.self,
    model: "mlx-community/Phi-3-mini-4k-instruct-4bit"
)
// result.sentiment == "positive"
// result.confidence == 0.95
```

### Query with Metadata

```swift
import SwiftBruja

let result = try await Bruja.queryWithMetadata(
    "What is 2+2?",
    model: "mlx-community/Phi-3-mini-4k-instruct-4bit"
)
print("Response: \(result.response)")
print("Duration: \(result.durationSeconds)s")
print("Tokens: \(result.tokensGenerated)")
```

## CLI Usage

SwiftBruja also includes a command-line tool for quick queries and model management.

**Important:** Use `xcodebuild` for builds. Metal shaders required for MLX cannot be compiled with `swift build`.

```bash
xcodebuild -scheme bruja -destination 'platform=OS X' build
```

### Commands

```bash
# Query (auto-downloads model if needed)
bruja query "What is the capital of France?" --model "mlx-community/Phi-3-mini-4k-instruct-4bit"

# Download a model
bruja download --model "mlx-community/Phi-3-mini-4k-instruct-4bit"

# List downloaded models
bruja list

# Model info
bruja info --model ~/Library/Application\ Support/SwiftBruja/Models/Phi-3-mini-4k-instruct-4bit
```

## API Reference

### Core Methods

| Method | Description |
|--------|-------------|
| `Bruja.query(_:model:)` | Simple text query, returns String |
| `Bruja.query(_:as:model:)` | Structured query, returns Codable type |
| `Bruja.queryWithMetadata(_:model:)` | Query with timing and token info |
| `Bruja.download(model:to:)` | Download model from HuggingFace |
| `Bruja.listModels()` | List downloaded models |
| `Bruja.modelExists(at:)` | Check if model exists locally |

### Default Values

- **Default model**: `mlx-community/Phi-3-mini-4k-instruct-4bit` (~2.15 GB)
- **Models directory**: `~/Library/Application Support/SwiftBruja/Models/`
- **Temperature**: 0.7
- **Max tokens**: 512

## How It Works

SwiftBruja wraps the MLX ecosystem into a simple API:

1. **Model Resolution**: Accepts local paths or HuggingFace model IDs
2. **Auto-Download**: Downloads missing models from HuggingFace Hub
3. **Model Caching**: Keeps loaded models in memory for fast subsequent queries
4. **Inference**: Uses MLX for GPU-accelerated generation on Apple Silicon

## Building from Source

```bash
# Build CLI (required for Metal shaders)
xcodebuild -scheme bruja -destination 'platform=OS X' build

# Run tests
swift test
```

## License

MIT
