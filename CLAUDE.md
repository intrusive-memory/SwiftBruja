# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

For detailed project documentation, architecture, and development guidelines, see **[AGENTS.md](AGENTS.md)**.

## Quick Reference

**Project**: SwiftBruja - One-line local LLM queries on Apple Silicon

**Platforms**: iOS 26.0+, macOS 26.0+ (Apple Silicon only)

**Purpose**: Make local LLM queries as simple as possible. One import, one line, zero configuration.

**Key Components**:
- Static `Bruja` API for one-line queries with auto-download
- `bruja` CLI for model management
- Auto-tuned memory management (maxTokens based on available RAM)
- Structured output via `Codable`

**Important Notes**:
- **Apple Silicon only** - NO Intel support (requires Metal/MLX)
- ONLY supports iOS 26.0+ and macOS 26.0+ (NEVER add code for older platforms)
- MUST build with `xcodebuild` or `make` (Metal shaders required)
- `swift build` compiles but won't run queries (shaders missing)
- See [AGENTS.md](AGENTS.md) for complete API reference, memory management, workflow, and architecture
