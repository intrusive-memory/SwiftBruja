# Changelog

All notable changes to SwiftBruja will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

---

## [1.0.9] - 2026-01-29

### Added

- **Memory-Aware maxTokens** - `maxTokens` is now automatically tuned based on available unified memory when not explicitly set (≤8 GB → 512, 8–16 GB → 2048, 16–32 GB → 4096, >32 GB → 8192)
- **Pre-Load Memory Validation** - Models are checked against available memory before loading; throws `BrujaError.insufficientMemory` if the model exceeds 80% of available memory
- **BrujaMemory** - New `BrujaMemory` utility enum with `availableMemory()`, `recommendedMaxTokens(modelSizeBytes:)`, and `validateMemoryForModel(sizeBytes:)`
- **Query Info Logging** - Each query prints `[SwiftBruja] maxTokens set to N for this query` to stdout

### Changed

- `maxTokens` parameter on `Bruja.query`, `Bruja.queryWithMetadata`, and `Bruja.query(as:)` changed from `Int` with a fixed default to `Int?` defaulting to `nil` (auto-tuned). Passing an explicit value still works as before.

---

## [1.0.8] - 2026-01-27

### Changed

- **Shared Models Directory** - Moved model storage from `~/Library/Application Support/SwiftBruja/Models/` to `~/Library/Caches/intrusive-memory/Models/LLM/` for shared access across intrusive-memory tools

---

## [1.0.5] - 2026-01-26

### Fixed

- **Homebrew Metal Bundle Discovery** - Fixed MLX Metal shader bundle not found at runtime
  - Homebrew only symlinks files (not directories) from Cellar to `/opt/homebrew/bin/`
  - MLX resolves the Metal bundle via `NS::Bundle::mainBundle()` which pointed to the symlink directory where the `.bundle` was missing
  - Homebrew formula now installs binary and Metal bundle to `libexec/` with a wrapper script, keeping them colocated at the resolved binary path

---

## [1.0.4] - 2026-01-26

### Fixed

- **Homebrew Installation** - Release v1.0.3 was created before the workflow fix was merged
  - This release is built with the corrected workflow that includes `mlx-swift_Cmlx.bundle`
  - Fixes "Failed to load the default metallib" error when installed via Homebrew

---

## [1.0.3] - 2026-01-26

### Fixed

- **Homebrew Installation** - Fixed "Failed to load the default metallib" error
  - Release tarball now includes `mlx-swift_Cmlx.bundle` (Metal shader library)
  - Required for MLX GPU acceleration on Apple Silicon

---

## [1.0.2] - 2026-01-27

### Fixed

- **CLI Version** - Fixed `bruja --version` to display correct version number

---

## [1.0.1] - 2026-01-27

### Fixed

- **Release Workflow** - Fixed permissions for asset upload in GitHub releases
- **Homebrew Tap** - Fixed workflow permissions for automatic formula updates

---

## [1.0.0] - 2026-01-26

### Added

- **Bruja API** - Static methods for querying LLMs with minimal code
  - `Bruja.query("Your prompt")` - Simple query interface
  - `Bruja.query(as: MyType.self)` - Structured output with Codable types
  - `Bruja.queryWithMetadata()` - Query with timing and token metadata
  - `Bruja.download()` - Model download from HuggingFace
  - `Bruja.listModels()` - List installed models

- **bruja CLI** - Command-line tool for LLM queries
  - `bruja query "prompt"` - Run queries from terminal
  - `bruja download --model <id>` - Download models
  - `bruja list` - List installed models
  - `bruja info` - Model information

- **Auto-download** - Models download automatically from HuggingFace when needed

- **Metal GPU Acceleration** - Uses MLX for fast Apple Silicon inference

### Technical Details

- **Default Model**: `mlx-community/Phi-3-mini-4k-instruct-4bit`
- **Platforms**: macOS 26.0+, iOS 26.0+ (Apple Silicon only)
- **Swift**: 6.2+
- **Dependencies**: mlx-swift, mlx-swift-lm, swift-transformers

---

## Version History

SwiftBruja provides simple, privacy-first local LLM inference on Apple Silicon.
