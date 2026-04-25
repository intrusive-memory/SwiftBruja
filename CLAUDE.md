# Claude-Specific Agent Instructions

**⚠️ Read [AGENTS.md](AGENTS.md) first** for universal project documentation, architecture, and development guidelines.

This file contains instructions specific to Claude Code agents working on SwiftBruja.

## Claude-Specific Build Preferences

- **MUST build with `make` targets** (`make build`, `make test`, `make install`, `make release`, `make dist`)
  - `swift build` compiles but Metal shaders won't load at runtime — NEVER use it
  - See `make help` for all available targets
- **XcodeBuildMCP available** for Xcode operations (build, test, simulator management)
- See [AGENTS.md](AGENTS.md) for universal build and platform requirements

## Development Workflow

Reference: [`.claude/WORKFLOW.md`](.claude/WORKFLOW.md) for complete Claude Code workflow.

- **Branch**: `development` → PR → `main`
- **CI Required**: Code Quality + macOS Tests + Integration Tests must pass
- **Never** commit directly to `main`
- **Never** add `@available` checks for older platforms

## Claude-Specific Critical Rules

1. ALWAYS use `make` targets instead of raw `xcodebuild` commands
2. NEVER use `swift build` or `swift test` directly (use XcodeBuildMCP tools instead)
3. Leverage XcodeBuildMCP for all Xcode operations when available
4. ALWAYS read files before editing
5. NEVER create files unless necessary — prefer editing existing files
6. Follow global `~/.claude/CLAUDE.md` patterns (communication, security, CI/CD)
