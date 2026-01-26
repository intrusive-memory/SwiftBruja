# SwiftBruja Requirements

## Vision

**SwiftBruja** ("Swift Witch") is a Swift package that provides simple, single-import access to on-device LLM capabilities on Apple Silicon. It wraps MLX libraries to enable:

1. **Model Management** - Download and cache models from HuggingFace
2. **Structured Output** - Query models and get typed Swift results
3. **Use-Case Modules** - Pre-built solutions for common tasks

**Philosophy**: One import, one line to get structured results from a local LLM.

```swift
import SwiftBruja

// Generate PROJECT.md for a podcast folder
let projectMd = try await Bruja.generateProjectMd(for: podcastURL)

// Or use the model directly for custom queries
let result: MyStruct = try await Bruja.query("Analyze this text...", as: MyStruct.self)
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         SwiftBruja                               │
├─────────────────────────────────────────────────────────────────┤
│  Use Cases                                                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ ProjectMd    │  │ Screenplay   │  │ Custom       │          │
│  │ Generator    │  │ Classifier   │  │ Queries      │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
├─────────────────────────────────────────────────────────────────┤
│  Core Services                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Model        │  │ Structured   │  │ Chat         │          │
│  │ Manager      │  │ Output       │  │ Session      │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
├─────────────────────────────────────────────────────────────────┤
│  Dependencies (MLX Ecosystem)                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ MLXLLM       │  │ MLXLMCommon  │  │ Hub          │          │
│  │ (mlx-swift-lm)│  │              │  │ (HuggingFace)│          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

---

## Core Components

### 1. Model Manager

Handles downloading, caching, and loading models from HuggingFace.

```swift
public actor BrujaModelManager {
    /// Shared instance
    public static let shared = BrujaModelManager()

    /// Default model for general use
    public static let defaultModel = "mlx-community/Phi-3-mini-4k-instruct-4bit"

    /// Check if model is downloaded
    public func isModelAvailable(_ modelId: String) -> Bool

    /// Download model from HuggingFace (with progress)
    public func downloadModel(
        _ modelId: String,
        progress: @escaping (Double) -> Void
    ) async throws

    /// Load model into memory
    public func loadModel(_ modelId: String) async throws -> BrujaModel

    /// Unload model to free memory
    public func unloadModel(_ modelId: String)

    /// Get storage location for models
    public var modelsDirectory: URL
}
```

**Storage Location**: `~/Library/Application Support/SwiftBruja/Models/`

**Supported Models** (initial):
- `mlx-community/Phi-3-mini-4k-instruct-4bit` (~2.15 GB) - Default
- `mlx-community/Mistral-7B-Instruct-v0.3-4bit` (~4 GB)
- `mlx-community/Llama-3.2-3B-Instruct-4bit` (~2 GB)

### 2. Structured Output

Query models and get typed Swift results using Codable.

```swift
public struct BrujaQuery {
    /// Query with structured output
    public static func query<T: Codable>(
        _ prompt: String,
        as type: T.Type,
        model: String = BrujaModelManager.defaultModel,
        temperature: Float = 0.3
    ) async throws -> T

    /// Query with raw string response
    public static func query(
        _ prompt: String,
        model: String = BrujaModelManager.defaultModel,
        temperature: Float = 0.7
    ) async throws -> String
}
```

**Structured Output Strategy**:
1. Include JSON schema in system prompt
2. Request JSON-only response
3. Parse response as JSON
4. Decode to Swift type
5. Retry with clarification if parsing fails

```swift
// Example usage
struct SentimentResult: Codable {
    let sentiment: String  // "positive", "negative", "neutral"
    let confidence: Double
    let reasoning: String
}

let result: SentimentResult = try await Bruja.query(
    "Analyze the sentiment of: 'I love this product!'",
    as: SentimentResult.self
)
// result.sentiment == "positive"
// result.confidence == 0.95
```

### 3. Chat Session

Maintain conversation context for multi-turn interactions.

```swift
public actor BrujaChatSession {
    /// Create session with system instructions
    public init(
        model: String = BrujaModelManager.defaultModel,
        systemPrompt: String? = nil
    )

    /// Send message and get response
    public func send(_ message: String) async throws -> String

    /// Send message and get structured response
    public func send<T: Codable>(_ message: String, as type: T.Type) async throws -> T

    /// Clear conversation history
    public func reset()
}
```

---

## Use Case: PROJECT.md Generator

Generate a PROJECT.md file by analyzing a podcast/project folder.

### API

```swift
public struct ProjectMdGenerator {
    /// Generate PROJECT.md for a folder
    public static func generate(
        for folderURL: URL,
        author: String? = nil,
        model: String = BrujaModelManager.defaultModel
    ) async throws -> ProjectMdResult

    /// Result containing generated content
    public struct ProjectMdResult {
        /// Generated PROJECT.md content (YAML frontmatter + markdown body)
        public let content: String

        /// Parsed frontmatter (for programmatic access)
        public let frontMatter: ProjectFrontMatter

        /// Write to file
        public func write(to url: URL) throws
    }
}

// Convenience accessor
extension Bruja {
    public static func generateProjectMd(
        for folderURL: URL,
        author: String? = nil
    ) async throws -> ProjectMdGenerator.ProjectMdResult
}
```

### Generation Process

```
1. Scan folder structure
   - Count files by extension
   - Identify episode files (*.fountain, *.fdx, etc.)
   - Find existing README.md, descriptions, etc.

2. Analyze content samples
   - Read first few episode files
   - Extract themes, topics, characters
   - Identify genre/style

3. Query LLM with context
   - Folder structure summary
   - Content samples
   - Request: Generate PROJECT.md frontmatter + description

4. Parse and validate response
   - Extract YAML frontmatter
   - Validate required fields
   - Return structured result
```

### Example Output

```yaml
---
type: project
title: Daily Dao - Tao De Jing Podcast
author: Tom Stovall
created: 2026-01-26T10:00:00Z
description: A contemplative journey through the 81 chapters of the Tao De Jing, offering daily readings and reflections on ancient Chinese wisdom.
season: 1
episodes: 81
genre: Philosophy
tags: [taoism, philosophy, meditation, spirituality, wisdom]

# Generation config (inferred from folder structure)
episodesDir: episodes
audioDir: audio
filePattern: "*.fountain"
---

# Daily Dao - Tao De Jing Podcast

A contemplative journey through the 81 chapters of the Tao De Jing.

## About

This podcast presents daily readings from the Tao De Jing (Dao De Jing),
the foundational text of Taoist philosophy attributed to the sage Laozi...

## Episode Format

Each episode includes:
- A poetic rendering of one chapter
- Contemplative commentary
- Traditional translation reference

## Production Notes

Generated with SwiftBruja from folder analysis.
```

---

## Package Structure

```
SwiftBruja/
├── Package.swift
├── REQUIREMENTS.md
├── README.md
├── CLAUDE.md
├── Sources/
│   └── SwiftBruja/
│       ├── Bruja.swift                    # Main entry point
│       ├── Core/
│       │   ├── BrujaModelManager.swift    # Model download/cache
│       │   ├── BrujaQuery.swift           # Structured queries
│       │   ├── BrujaChatSession.swift     # Multi-turn chat
│       │   └── BrujaError.swift           # Error types
│       ├── StructuredOutput/
│       │   ├── JSONSchemaBuilder.swift    # Build schema from Codable
│       │   ├── ResponseParser.swift       # Parse LLM JSON responses
│       │   └── RetryStrategy.swift        # Handle parse failures
│       └── UseCases/
│           ├── ProjectMdGenerator.swift   # PROJECT.md generation
│           └── FolderAnalyzer.swift       # Scan folder structure
└── Tests/
    └── SwiftBrujaTests/
        ├── ModelManagerTests.swift
        ├── StructuredOutputTests.swift
        └── ProjectMdGeneratorTests.swift
```

---

## Dependencies

```swift
// Package.swift
let package = Package(
    name: "SwiftBruja",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(name: "SwiftBruja", targets: ["SwiftBruja"])
    ],
    dependencies: [
        // MLX ecosystem
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.21.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),

        // Optional: SwiftProyecto for PROJECT.md types
        .package(url: "https://github.com/intrusive-memory/SwiftProyecto", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "SwiftBruja",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Hub", package: "mlx-swift-lm"),
                .product(name: "SwiftProyecto", package: "SwiftProyecto"),
            ]
        ),
        .testTarget(
            name: "SwiftBrujaTests",
            dependencies: ["SwiftBruja"]
        )
    ]
)
```

---

## Implementation Phases

### Phase 1: Core Infrastructure

- [ ] Create package structure
- [ ] Implement `BrujaModelManager`
  - Model download from HuggingFace
  - Progress tracking
  - Local caching
  - Model loading/unloading
- [ ] Implement basic `BrujaQuery`
  - Raw string queries
  - Temperature/token control

### Phase 2: Structured Output

- [ ] Implement `JSONSchemaBuilder`
  - Generate JSON schema from Codable types
  - Handle nested types, arrays, optionals
- [ ] Implement `ResponseParser`
  - Extract JSON from LLM response
  - Handle markdown code blocks
  - Decode to Swift types
- [ ] Implement retry logic
  - Clarification prompts on parse failure
  - Max retry limit

### Phase 3: Chat Sessions

- [ ] Implement `BrujaChatSession`
  - Conversation history
  - System prompt support
  - Context window management
- [ ] Memory management
  - Truncate old messages
  - Summarization for long conversations

### Phase 4: PROJECT.md Generator

- [ ] Implement `FolderAnalyzer`
  - Scan directory structure
  - Identify file types
  - Sample content extraction
- [ ] Implement `ProjectMdGenerator`
  - Context building
  - LLM query with schema
  - Response parsing
  - Validation
- [ ] Integration with SwiftProyecto
  - Use `ProjectFrontMatter` type
  - Use `ProjectMarkdownParser` for output

### Phase 5: Documentation & Polish

- [ ] Write README.md with examples
- [ ] Write CLAUDE.md for AI assistants
- [ ] Add comprehensive tests
- [ ] Performance optimization
- [ ] Error handling refinement

---

## Usage Examples

### Simple Query

```swift
import SwiftBruja

// Ensure model is available
if !await Bruja.isModelReady() {
    try await Bruja.downloadDefaultModel { progress in
        print("Downloading: \(Int(progress * 100))%")
    }
}

// Simple query
let response = try await Bruja.query("Explain quantum computing in one sentence")
print(response)
```

### Structured Output

```swift
import SwiftBruja

struct BookSummary: Codable {
    let title: String
    let author: String
    let themes: [String]
    let targetAudience: String
}

let summary: BookSummary = try await Bruja.query(
    "Summarize '1984' by George Orwell",
    as: BookSummary.self
)

print(summary.themes)  // ["totalitarianism", "surveillance", "freedom"]
```

### PROJECT.md Generation

```swift
import SwiftBruja

let podcastURL = URL(fileURLWithPath: "/path/to/podcast-project")
let result = try await Bruja.generateProjectMd(for: podcastURL, author: "Tom Stovall")

// Write to file
try result.write(to: podcastURL.appendingPathComponent("PROJECT.md"))

// Or access programmatically
print(result.frontMatter.title)     // "Daily Dao - Tao De Jing Podcast"
print(result.frontMatter.episodes)  // 81
```

### Chat Session

```swift
import SwiftBruja

let session = BrujaChatSession(
    systemPrompt: "You are a helpful writing assistant specializing in screenplays."
)

let response1 = try await session.send("I'm writing a noir detective story")
let response2 = try await session.send("Suggest a compelling opening scene")
let response3 = try await session.send("Now write the first page of dialogue")
```

---

## Future Use Cases

Once the core is built, additional use cases can be added:

1. **Screenplay Classifier** (extract from Produciesta)
   - Classify screenplay elements
   - Character analysis

2. **Content Summarizer**
   - Summarize documents
   - Extract key points

3. **Code Analyzer**
   - Explain code
   - Suggest improvements

4. **Translation**
   - Translate text between languages
   - Preserve tone/style

---

## Platform Requirements

- **macOS 26.0+** / **iOS 26.0+**
- **Apple Silicon required** (M1/M2/M3/M4)
- **~2-4 GB storage** for default model
- **~4-8 GB RAM** for inference

---

## Open Questions

1. **Model selection strategy?**
   - Single default model vs. task-specific models
   - Allow user to specify preferred model

2. **Offline-first or download-on-demand?**
   - Require model download before first use
   - Or bundle a small model with the package

3. **SwiftProyecto dependency?**
   - Hard dependency for PROJECT.md types
   - Or copy types to keep SwiftBruja standalone

4. **Error recovery?**
   - What happens if LLM gives invalid JSON repeatedly
   - Fallback to raw response? Throw error?
