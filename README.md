<p align="center">
  <img src="SwiftBruja.jpg" alt="SwiftBruja" width="200" height="200">
</p>

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

SwiftBruja includes a command-line tool (`bruja`) for quick queries and model management.

### Installation

```bash
# Build and install to ./bin (Metal shaders required)
make install

# Or for release build
make release
```

**Important:** Use the Makefile or `xcodebuild` for builds. Metal shaders required for MLX cannot be compiled with `swift build`.

### Commands

#### `bruja query` (default)

Send a prompt to a local language model.

```bash
# Simple query (uses default model, auto-downloads if needed)
bruja "What is the capital of France?"

# Explicit query command with specific model
bruja query "Explain quantum computing" -m mlx-community/Llama-3-8B

# Adjust generation parameters
bruja "Write a haiku" --temperature 0.9 --max-tokens 100

# Set system prompt for model behavior
bruja "Summarize this text" --system "You are a helpful assistant"

# JSON output with metadata (tokens, duration)
bruja "List 5 programming languages" --json
```

**Options:**
- `prompt` (argument): The prompt to send to the model
- `-m, --model`: Model path or HuggingFace ID (default: mlx-community/Phi-3-mini-4k-instruct-4bit)
- `-d, --destination`: Download destination for HuggingFace models
- `--temperature`: Sampling temperature 0.0-1.0 (default: 0.7)
- `--max-tokens`: Maximum tokens to generate (default: 512)
- `--system`: System prompt to set model behavior
- `--json`: Output as JSON with metadata
- `-q, --quiet`: Suppress non-response output

#### `bruja download`

Download a model from HuggingFace.

```bash
# Download specific model
bruja download -m mlx-community/Phi-3-mini-4k-instruct-4bit

# Download to custom location
bruja download -m mlx-community/Llama-3-8B -d ~/Models

# Force re-download
bruja download -m mlx-community/Phi-3-mini-4k-instruct-4bit --force
```

**Popular models:**
- `mlx-community/Phi-3-mini-4k-instruct-4bit` (~2.15 GB, fast)
- `mlx-community/Llama-3-8B-Instruct-4bit` (~4.5 GB, capable)
- `mlx-community/Mistral-7B-Instruct-v0.3-4bit` (~4 GB, balanced)

#### `bruja list`

List downloaded models.

```bash
bruja list                    # List models in default directory
bruja list --path ~/MyModels  # List models in custom directory
bruja list --json             # JSON output
```

#### `bruja info`

Show detailed information about a model.

```bash
bruja info -m mlx-community/Phi-3-mini-4k-instruct-4bit
bruja info -m ~/Models/custom-model --json
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
# Build and install CLI to ./bin (recommended)
make install

# Or release build
make release

# Manual xcodebuild (requires correct destination for macOS 26 Apple Silicon)
xcodebuild -scheme bruja -destination 'platform=macOS,arch=arm64' build

# Run tests
swift test
```

**Note:** Metal shaders require `xcodebuild` or `make install`. Using `swift build` alone will compile but shaders won't load at runtime.

## License

MIT
