# AGENTS.md

This file provides comprehensive documentation for AI agents working with the SwiftBruja codebase.

**Current Version**: 1.4.0 (April 2026)

---

## Project Overview

SwiftBruja makes local LLM queries as simple as possible. One import, one line of code, and you have on-device AI inference on Apple Silicon with GPU acceleration.

**Design Philosophy**: Simplicity over inference. Models are pre-downloaded via SwiftAcervo. No cloud APIs, no API keys, no network latency - just fast, private, on-device AI.

## Project Structure

- `Sources/SwiftBruja/` -- Library target with static `Bruja` API
  - `Bruja.swift` -- Main entry point (static methods: `query`, `queryWithMetadata`, `listModels`)
  - `Core/BrujaModelManager.swift` -- Loads models into memory, validates memory
  - `Core/BrujaComponents.swift` -- Model component registry (SwiftAcervo manifest)
  - `Core/BrujaQuery.swift` -- Query execution via MLX, resolves models via SwiftAcervo
  - `Core/BrujaMemory.swift` -- Memory validation and auto-tuned maxTokens
  - `Core/BrujaTypes.swift` -- `BrujaQueryResult`, `BrujaModelInfo`
  - `Core/BrujaError.swift` -- Error types
- `Sources/bruja/` -- CLI executable target (uses SwiftAcervo for downloads)
- `Tests/SwiftBrujaTests/` -- Unit tests
- `Tests/BrujaIntegrationTests/` -- Integration tests (inference only, no downloads)

## Key Components

| File | Purpose |
|------|---------|
| `Bruja.swift` | Static API for queries: `query()`, `queryWithMetadata()`, `listModels()`, `modelExists()` |
| `BrujaModelManager.swift` | Loads models into memory, validates memory, resolves models via SwiftAcervo |
| `BrujaComponents.swift` | Model component registry with SwiftAcervo manifest (SHA-256 checksums, file metadata) |
| `BrujaQuery.swift` | Executes LLM inference via MLX, resolves models via SwiftAcervo, supports structured output via `Decodable` |
| `BrujaMemory.swift` | Validates available memory before loading models (80% threshold), auto-tunes `maxTokens` based on memory (4096 or 8192) |
| `BrujaTypes.swift` | `BrujaQueryResult` (response + metadata), `BrujaModelInfo` (model details) |
| `BrujaError.swift` | `insufficientMemory`, `modelNotFound`, `modelLoadFailed`, `queryFailed`, `jsonParsingFailed` |

## CLI Commands

| Command | Purpose | Key Flags |
|---------|---------|-----------|
| `query` | Execute LLM query with pre-downloaded model | `--model`, `--max-tokens`, `--temperature`, `--system` |
| `download` | Download model from SwiftAcervo CDN | `--model`, `--force` (delegates to SwiftAcervo) |
| `chat` | Interactive multi-turn chat session | `--model`, `--temperature` |
| `list` | List cached models | (none) |
| `info` | Show model metadata | `--model` |

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| mlx-swift | 0.21.0+ | Core MLX framework for Apple Silicon GPU |
| mlx-swift-lm | 2.30.6+ | LLM inference (MLXLLM, MLXLMCommon) |
| SwiftAcervo | 0.6.0+ | Shared model management (CDN download, cache, discovery) |
| swift-argument-parser | 1.3.0+ | CLI argument parsing |

## Build and Test

**CRITICAL**: This library must ONLY be built using `xcodebuild` or `make` for functional builds. `swift build` compiles but Metal shaders won't load at runtime.

```bash
# Functional builds (required for queries to work)
make install    # Debug build → ./bin/bruja
make release    # Release build → ./bin/bruja

# Unit tests (MUST use xcodebuild)
xcodebuild test -scheme SwiftBruja-Package -destination 'platform=macOS' -only-testing:SwiftBrujaTests

# All tests
xcodebuild test -scheme SwiftBruja-Package -destination 'platform=macOS'
```

## Platform Requirements

**CRITICAL: Apple Silicon Only**

- **macOS 26.0+** (M1/M2/M3/M4 only)
- **iOS 26.0+** (Apple Silicon only)
- **Swift 6.2+**
- **NO Intel support** - MLX requires Apple Silicon GPU
- **NEVER add `@available` checks for older platforms**

## Design Patterns

- **Static API**: `Bruja.query()` provides a simple entry point without instantiation
- **Pre-downloaded models**: Models must exist locally via SwiftAcervo; Bruja verifies and loads them
- **Structured output**: `Bruja.query(as: MyType.self)` returns typed responses via `Decodable`
- **Memory-aware**: Pre-load validation (80% threshold), auto-tuned `maxTokens` based on available memory
- **Shared cache**: All models stored in `~/Library/SharedModels/<namespace>_<repo>/` via SwiftAcervo
- **Swift 6 concurrency**: Async/await throughout, `Sendable` types, actor isolation
- **Model distribution delegated**: SwiftAcervo handles CDN downloads, manifest validation, caching

## API Usage

### Simple Query

```swift
import SwiftBruja

let response = try await Bruja.query("What is the capital of France?")
// "The capital of France is Paris."
```

### Query with Model Selection

```swift
let response = try await Bruja.query(
    "Explain quantum computing in one sentence",
    model: "mlx-community/Phi-3-mini-4k-instruct-4bit"
)
```

### Structured Output

```swift
struct Analysis: Codable {
    let sentiment: String
    let confidence: Double
}

let result: Analysis = try await Bruja.query(
    "Analyze: 'I love this!'",
    as: Analysis.self
)
```

### Query with Metadata

```swift
let result = try await Bruja.queryWithMetadata("Your prompt")
print("Duration: \(result.durationSeconds)s")
print("Tokens: \(result.tokensGenerated)")
```

## Memory Management

SwiftBruja automatically manages memory to prevent out-of-memory errors:

1. **Pre-load validation**: Before loading a model, checks that model size doesn't exceed 80% of available memory. Throws `BrujaError.insufficientMemory` if it does.
2. **Auto-tuned maxTokens**: When `maxTokens` is not explicitly passed:
   - **≤ 32 GB available**: 4096 tokens
   - **> 32 GB**: 8192 tokens
3. **Info logging**: Resolved `maxTokens` value printed to stdout: `[SwiftBruja] maxTokens set to N for this query`
4. Callers can override by passing explicit `maxTokens` value

## Default Values

- **Default model**: `mlx-community/Llama-3.2-1B-Instruct-4bit` (679 MB)
- **Models directory**: `~/Library/SharedModels/`
- **Temperature**: 0.7
- **Max tokens**: Auto-tuned (4096 or 8192 based on memory)

## Shared Model Cache

All `intrusive-memory` projects share a flat model cache at `~/Library/SharedModels/` via SwiftAcervo:

| Project | Cache Path |
|---------|------------|
| **SwiftBruja** (LLM) | `~/Library/SharedModels/<namespace>_<repo>/` |
| **mlx-audio-swift** (Audio) | `~/Library/SharedModels/<namespace>_<repo>/` |

The `<namespace>_<repo>` directory name is the HuggingFace repo ID with `/` replaced by `_` (e.g., `mlx-community/Llama-3.2-1B-Instruct-4bit` becomes `mlx-community_Llama-3.2-1B-Instruct-4bit`). SwiftAcervo manages the canonical directory path. Legacy models from old cache paths are automatically migrated on first use.

## Homebrew Distribution

Distributed via `brew tap intrusive-memory/tap && brew install bruja`.

Formula location: `intrusive-memory/homebrew-tap/Formula/bruja.rb`

**CRITICAL**: The `mlx-swift_Cmlx.bundle` must be colocated with the binary (installed to libexec).

## Development Workflow

- **Branch**: `development` → PR → `main`
- **CI Required**: Code Quality + macOS Tests + Integration Tests must pass
- **Never commit directly to `main`**
- **Integration Tests**: Build CLI via `make release`, verify `--version` and `--help`

### Required Status Checks

```
Code Quality
macOS Tests
Integration Tests
```

## Error Handling

| Error | When |
|-------|------|
| `BrujaError.insufficientMemory` | Model size exceeds 80% of available memory |
| `BrujaError.modelNotFound` | Model not found in SwiftAcervo cache (must be pre-downloaded) |
| `BrujaError.modelLoadFailed` | Model failed to load into memory |
| `BrujaError.queryFailed` | Inference failed during generation |
| `BrujaError.jsonParsingFailed` | Structured output parsing failed |
