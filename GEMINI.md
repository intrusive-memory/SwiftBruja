# Gemini-Specific Agent Instructions

**⚠️ Read [AGENTS.md](AGENTS.md) first** for universal project documentation, architecture, and development guidelines.

This file contains instructions specific to Google Gemini agents working on SwiftBruja.

## Gemini-Specific Build Configuration

- **MUST use `make` targets** for all builds (`make build`, `make test`, `make install`, `make release`, `make dist`)
  - `swift build` compiles but Metal shaders won't load at runtime — NEVER use it
  - Use `xcodebuild` directly when `make` is not available
- **Standard CLI tools only** (no MCP server access)
- See [AGENTS.md](AGENTS.md) for universal build and platform requirements

## Development Workflow

- **Branch**: `development` → PR → `main`
- **CI Required**: Code Quality + macOS Tests + Integration Tests must pass
- **Never** commit directly to `main`
- See [AGENTS.md](AGENTS.md) for full development workflow details

## App Group Configuration

See [AGENTS.md § App Group configuration (required)](./AGENTS.md#app-group-configuration-required) for the `ACERVO_APP_GROUP_ID` env var contract and entitlement setup.

## Gemini-Specific Critical Rules

1. ALWAYS use `make` targets instead of raw `xcodebuild` commands
2. NEVER use `swift build` or `swift test` directly (use `make test` or `xcodebuild test`)
3. Use standard CLI tools for all development tasks (no MCP server access)
4. ALWAYS read files before editing
5. NEVER create files unless necessary — prefer editing existing files
