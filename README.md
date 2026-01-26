# SwiftBruja 🧙‍♀️

On-device LLM for Apple Silicon. Simple CLI and Swift library for downloading models from HuggingFace and running queries locally.

## Requirements

- macOS 26.0+ or iOS 26.0+
- Apple Silicon (M1/M2/M3/M4)
- ~2-4 GB storage per model

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/intrusive-memory/SwiftBruja", from: "1.0.0")
]
```

### CLI

```bash
# Build and install
swift build -c release
cp .build/release/bruja /usr/local/bin/
```

## CLI Usage

### Download a Model

```bash
# Download to default location
bruja download --model "mlx-community/Phi-3-mini-4k-instruct-4bit"

# Download to specific location
bruja download --model "mlx-community/Phi-3-mini-4k-instruct-4bit" --destination ~/Models
```

### Query a Model

```bash
# Query with model path
bruja query "What is the capital of France?" --model ~/Models/Phi-3-mini-4k-instruct-4bit

# Query with auto-download (downloads if needed)
bruja query "Hello world" --model "mlx-community/Phi-3-mini-4k-instruct-4bit"

# JSON output
bruja query "Explain gravity" --model ~/Models/Phi-3-mini --json
```

### List Models

```bash
bruja list
bruja list --json
```

## Library Usage

### Basic Query

```swift
import SwiftBruja

// Query a local model
let response = try await Bruja.query(
    "What is the capital of France?",
    model: modelPath
)
print(response)  // "The capital of France is Paris."
```

### Download + Query

```swift
import SwiftBruja

// Download model if needed, then query
let response = try await Bruja.query(
    "Explain quantum computing",
    model: "mlx-community/Phi-3-mini-4k-instruct-4bit",
    downloadDestination: Bruja.defaultModelsDirectory
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
    model: modelPath
)
// result.sentiment == "positive"
// result.confidence == 0.95
```

### Model Management

```swift
import SwiftBruja

// Download with progress
try await Bruja.download(
    model: "mlx-community/Phi-3-mini-4k-instruct-4bit",
    to: destinationURL,
    progress: { print("\(Int($0 * 100))%") }
)

// Check if exists
let exists = Bruja.modelExists(at: modelPath)

// List models
let models = try Bruja.listModels(in: Bruja.defaultModelsDirectory)
```

## Default Model

`mlx-community/Phi-3-mini-4k-instruct-4bit` (~2.15 GB)

## Storage Location

Models are stored in: `~/Library/Application Support/SwiftBruja/Models/`

## License

MIT
