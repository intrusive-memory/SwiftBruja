# Changelog

All notable changes to SwiftBruja will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

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
