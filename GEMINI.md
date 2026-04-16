# GEMINI.md

**Read [AGENTS.md](AGENTS.md) first** for complete project documentation, architecture, API reference, and development guidelines.

This file contains instructions specific to Google Gemini agents.

## Gemini-Specific Build Preferences

- **MUST build with `make`** targets (`make build`, `make test`, `make install`, `make release`, `make dist`)
- `swift build` compiles but Metal shaders won't load at runtime — NEVER use it
- Use `xcodebuild` directly when `make` is not available

## Development Workflow

- **Branch**: `development` → PR → `main`
- **CI Required**: Code Quality + macOS Tests + Integration Tests must pass
- **Never** commit directly to `main`

## Gemini-Specific Critical Rules

1. ALWAYS use `make` targets instead of raw `xcodebuild` commands
2. NEVER use `swift build` or `swift test`
3. ALWAYS read files before editing
4. NEVER create files unless necessary — prefer editing existing files
5. Use standard CLI tools (no MCP access)
