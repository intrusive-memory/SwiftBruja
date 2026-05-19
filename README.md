<p align="center">
  <img src="SwiftBruja.jpg" alt="SwiftBruja" width="200" height="200">
</p>

# SwiftBruja

**One import. One line. Local LLM queries on Apple Silicon.**

SwiftBruja wraps the complexity of MLX and inference into a single, simple API. Models are managed by SwiftAcervo, which handles downloading, caching, and storage. No cloud APIs, no API keys, no network latency - just fast, private, on-device AI.

```swift
import SwiftBruja

let response = try await Bruja.query("What is the capital of France?")
// "The capital of France is Paris."
```

## Why SwiftBruja?

- **Single Import**: One package gives you everything - inference on Apple Silicon
- **One-Line Queries**: `Bruja.query()` handles model loading, tokenization, and generation
- **Model Lifecycle Delegated**: SwiftAcervo handles model downloads, caching, and storage
- **Structured Output**: Get typed responses with `Bruja.query(as: MyType.self)`
- **Memory-Aware**: Automatically adjusts token limits based on available memory
- **No Cloud Required**: Runs entirely on-device using Apple Silicon GPU
- **Privacy First**: Your prompts never leave your device

## Requirements

- **macOS 26.0+** or **iOS 26.0+**
- **Apple Silicon only** (M1/M2/M3/M4) - NO Intel support
- **Swift 6.2+**
- ~2-4 GB storage per model

## Installation

### Homebrew (CLI)

```bash
brew install intrusive-memory/tap/bruja
```

### Swift Package Manager (Library)

```swift
dependencies: [
    .package(url: "https://github.com/intrusive-memory/SwiftBruja", from: "1.7.0")
]
```

## Quick Start

### Simplest Usage

```swift
import SwiftBruja

// Query with auto-download (downloads model if needed)
let response = try await Bruja.query(
    "Explain quantum computing in one sentence",
    model: "mlx-community/Llama-3.2-1B-Instruct-4bit"
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
    model: "mlx-community/Llama-3.2-1B-Instruct-4bit"
)
// result.sentiment == "positive"
// result.confidence == 0.95
```

### Query with Metadata

```swift
import SwiftBruja

let result = try await Bruja.queryWithMetadata(
    "What is 2+2?",
    model: "mlx-community/Llama-3.2-1B-Instruct-4bit"
)
print("Response: \(result.response)")
print("Duration: \(result.durationSeconds)s")
print("Tokens: \(result.tokensGenerated)")
```

## CLI Usage

SwiftBruja includes a command-line tool (`bruja`) for quick queries and model management.

### Installation

```bash
# Homebrew (recommended)
brew install intrusive-memory/tap/bruja

# Or build from source
make install    # Debug build → ./bin/bruja
make release    # Release build → ./bin/bruja
```

**Note:** Building from source requires `xcodebuild` or `make` - Metal shaders required for MLX cannot be compiled with `swift build`.

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
- `-m, --model`: Model path or HuggingFace ID (default: mlx-community/Llama-3.2-1B-Instruct-4bit)
- `--temperature`: Sampling temperature 0.0-1.0 (default: 0.7)
- `--max-tokens`: Maximum tokens to generate (auto-tuned by memory if omitted)
- `--system`: System prompt to set model behavior
- `--json`: Output as JSON with metadata
- `-q, --quiet`: Suppress non-response output

#### `bruja download`

Download a model from the CDN.

```bash
# Download specific model
bruja download -m mlx-community/Llama-3.2-1B-Instruct-4bit

# Force re-download
bruja download -m mlx-community/Llama-3.2-1B-Instruct-4bit --force
```

**Popular models:**
- `mlx-community/Llama-3.2-1B-Instruct-4bit` (~679 MB, fast)
- `mlx-community/Llama-3-8B-Instruct-4bit` (~4.5 GB, capable)
- `mlx-community/Mistral-7B-Instruct-v0.3-4bit` (~4 GB, balanced)

#### `bruja list`

List downloaded models.

```bash
bruja list                    # List downloaded models
bruja list --json             # JSON output
```

#### `bruja info`

Show detailed information about a model.

```bash
bruja info -m mlx-community/Llama-3.2-1B-Instruct-4bit
bruja info -m ~/Models/custom-model --json
```

## API Reference

### Core Methods

| Method | Description |
|--------|-------------|
| `Bruja.query(_:model:)` | Simple text query, returns String |
| `Bruja.query(_:as:model:)` | Structured query, returns Codable type |
| `Bruja.queryWithMetadata(_:model:)` | Query with timing and token info |
| `Bruja.download(model:)` | Ensure model is available via SwiftAcervo |
| `Bruja.listModels()` | List downloaded models |
| `Bruja.modelExists(at:)` | Check if model exists at path |
| `Bruja.modelExists(id:)` | Check if model exists by HuggingFace ID |

### Default Values

- **Default model**: `mlx-community/Llama-3.2-1B-Instruct-4bit` (679 MB)
- **Models directory**: `~/Library/SharedModels/` (shared via [SwiftAcervo](https://github.com/intrusive-memory/SwiftAcervo))
- **Temperature**: 0.7
- **Max tokens**: Auto-tuned based on available memory (pass explicitly to override)

## Memory Management

SwiftBruja automatically manages memory to prevent crashes and optimize performance:

- **Pre-load validation**: Before loading a model, SwiftBruja checks that the model fits within 80% of available memory, leaving headroom for KV-cache and the OS. If not, it throws `BrujaError.insufficientMemory` with details.
- **Auto-tuned maxTokens**: When you don't pass `maxTokens`, it is automatically set based on available memory after the model loads:

| Available Memory | maxTokens |
|-----------------|-----------|
| ≤ 8 GB | 512 |
| 8–16 GB | 2,048 |
| 16–32 GB | 4,096 |
| > 32 GB | 8,192 |

You can always override by passing `maxTokens` explicitly:

```swift
let response = try await Bruja.query("...", model: modelId, maxTokens: 2048)
```

## How It Works

SwiftBruja is a consumer of SwiftAcervo's storage, providing a simple inference API:

1. **Model Resolution**: Accepts local paths or HuggingFace model IDs (delegates to SwiftAcervo)
2. **Model Availability**: Ensures models are available via SwiftAcervo (which handles CDN downloads and integrity verification)
3. **Memory Validation**: Checks available memory before loading
4. **Model Caching**: Keeps loaded models in memory for fast subsequent queries
5. **Token Auto-Tuning**: Sets maxTokens based on remaining memory
6. **Inference**: Uses MLX for GPU-accelerated generation on Apple Silicon

## Building from Source

```bash
# Build and install CLI to ./bin (recommended)
make install

# Or release build
make release

# Manual xcodebuild (requires correct destination for macOS 26 Apple Silicon)
xcodebuild -scheme bruja -destination 'platform=macOS,arch=arm64' build

# Run tests (requires xcodebuild)
make test
```

**Note:** Metal shaders require `xcodebuild` or `make install`. Using `swift build` alone will compile but shaders won't load at runtime.

## App Group configuration (required)

SwiftBruja depends on [SwiftAcervo](https://github.com/intrusive-memory/SwiftAcervo) for shared model storage. SwiftAcervo v0.10.0 resolves its App Group ID in this order: `ACERVO_APP_GROUP_ID` env var → `com.apple.security.application-groups` entitlement (macOS only) → `fatalError`. There is **no silent fallback**.

SwiftBruja is the canonical reference consumer for this configuration across the `intrusive-memory` ecosystem.

### Signed UI apps (macOS / iOS)

Declare `com.apple.security.application-groups` with `group.intrusive-memory.models` in your `.entitlements` file:

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.intrusive-memory.models</string>
</array>
```

In Xcode: **Signing & Capabilities** → **+ Capability** → **App Groups** → enter `group.intrusive-memory.models`. Repeat for all targets that import SwiftBruja (main app target, any app extensions).

iOS apps additionally need `ACERVO_APP_GROUP_ID=group.intrusive-memory.models` in the launch environment.

### CLI tools, scripts, CI jobs, test runners

Export `ACERVO_APP_GROUP_ID` in the shell or job environment. The standard place is `~/.zprofile`:

```sh
export ACERVO_APP_GROUP_ID=group.intrusive-memory.models
```

CI workflows must set this variable before any `xcodebuild test` invocation that exercises SwiftAcervo paths.

### Troubleshooting

If you see `fatalError: SwiftAcervo: no App Group identifier configured`, export `ACERVO_APP_GROUP_ID` or add the entitlement.

For the full integration checklist and App Group setup guidance, see [SwiftAcervo USAGE.md](https://github.com/intrusive-memory/SwiftAcervo/blob/main/USAGE.md).

## License

MIT
