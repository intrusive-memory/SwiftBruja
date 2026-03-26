# AGENTS.md

This file provides comprehensive documentation for AI agents working with the SwiftBruja codebase.

**Current Version**: 1.2.0 (March 2026)

---

## Project Overview

SwiftBruja makes local LLM queries as simple as possible. One import, one line of code, and you have on-device AI inference on Apple Silicon with automatic model downloading, GPU acceleration, and zero configuration.

**Design Philosophy**: Simplicity over flexibility. No cloud APIs, no API keys, no network latency - just fast, private, on-device AI.

## Project Structure

- `Sources/SwiftBruja/` -- Library target with static `Bruja` API
  - `Bruja.swift` -- Main entry point (static methods: `query`, `queryWithMetadata`, `download`, `listModels`)
  - `Core/BrujaModelManager.swift` -- Loads models into memory, validates memory
  - `Core/BrujaDownloadManager.swift` -- Thin SwiftAcervo wrapper for model download and discovery
  - `Core/BrujaQuery.swift` -- Query execution via MLX
  - `Core/BrujaMemory.swift` -- Memory validation and auto-tuned maxTokens
  - `Core/BrujaTypes.swift` -- `BrujaQueryResult`, `BrujaModelInfo`
  - `Core/BrujaError.swift` -- Error types
- `Sources/bruja/` -- CLI executable target
- `Tests/SwiftBrujaTests/` -- Unit tests

## Key Components

| File | Purpose |
|------|---------|
| `Bruja.swift` | Static API for queries: `query()`, `queryWithMetadata()`, `download()`, `listModels()`, `modelExists()` |
| `BrujaModelManager.swift` | Loads models into memory, validates memory |
| `BrujaDownloadManager.swift` | Thin SwiftAcervo wrapper for model download and discovery (passes `files: []` to download all manifest files) |
| `BrujaQuery.swift` | Executes LLM inference via MLX, handles tokenization and generation, supports structured output via `Decodable` |
| `BrujaMemory.swift` | Validates available memory before loading models (80% threshold), auto-tunes `maxTokens` based on memory (4096 or 8192) |
| `BrujaTypes.swift` | `BrujaQueryResult` (response + metadata), `BrujaModelInfo` (model details) |
| `BrujaError.swift` | `insufficientMemory`, `modelNotFound`, `downloadFailed`, `invalidModel`, `queryFailed` |

## CLI Commands

| Command | Purpose | Key Flags |
|---------|---------|-----------|
| `query` | Execute LLM query | `--model`, `--max-tokens`, `--temperature` |
| `download` | Download model from HuggingFace | `--model`, `--force` |
| `list` | List cached models | (none) |
| `info` | Show model metadata | `--model` |

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| mlx-swift | 0.21.0+ | Core MLX framework for Apple Silicon GPU |
| mlx-swift-lm | main | LLM inference (MLXLLM, MLXLMCommon) |
| SwiftAcervo | main | Shared model management (download, cache, discovery) |
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
- **Auto-download**: Pass HuggingFace model ID, downloads automatically if not cached
- **Structured output**: `Bruja.query(as: MyType.self)` returns typed responses via `Decodable`
- **Memory-aware**: Pre-load validation (80% threshold), auto-tuned `maxTokens` based on available memory
- **Shared cache**: All models stored in `~/Library/SharedModels/<namespace>_<repo>/`
- **Swift 6 concurrency**: Async/await throughout, `Sendable` types, actor isolation

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

- **Default model**: `mlx-community/Qwen3-Coder-Next-4bit`
- **Models directory**: `~/Library/SharedModels/`
- **Temperature**: 0.7
- **Max tokens**: Auto-tuned (4096 or 8192 based on memory)

## Shared Model Cache

All `intrusive-memory` projects share a flat model cache at `~/Library/SharedModels/` via SwiftAcervo:

| Project | Cache Path |
|---------|------------|
| **SwiftBruja** (LLM) | `~/Library/SharedModels/<namespace>_<repo>/` |
| **mlx-audio-swift** (Audio) | `~/Library/SharedModels/<namespace>_<repo>/` |

The `<namespace>_<repo>` directory name is the HuggingFace repo ID with `/` replaced by `_` (e.g., `mlx-community/Qwen3-Coder-Next-4bit` becomes `mlx-community_Qwen3-Coder-Next-4bit`). SwiftAcervo manages the canonical directory path. Legacy models from old cache paths are automatically migrated on first use.

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
| `BrujaError.modelNotFound` | Model path doesn't exist locally |
| `BrujaError.downloadFailed` | HuggingFace download failed |
| `BrujaError.invalidModel` | Model format is invalid or corrupt |
| `BrujaError.queryFailed` | Inference failed during generation |
