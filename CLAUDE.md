# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Read [AGENTS.md](AGENTS.md) first** for complete project documentation, architecture, API reference, and development guidelines.

## Claude-Specific Build Preferences

- **MUST build with `make`** targets (`make build`, `make test`, `make install`, `make release`, `make dist`)
- `swift build` compiles but Metal shaders won't load at runtime — NEVER use it
- See `make help` or `grep '^[a-z].*:' Makefile` for all available targets
- See [AGENTS.md](AGENTS.md) for build commands and platform requirements

## Development Workflow

See [`.claude/WORKFLOW.md`](.claude/WORKFLOW.md) for the complete Claude Code workflow.

- **Branch**: `development` → PR → `main`
- **CI Required**: Code Quality + macOS Tests + Integration Tests must pass
- **Never** commit directly to `main`
- **Never** add `@available` checks for older platforms

## Claude-Specific Critical Rules

1. ALWAYS use `make` targets instead of raw `xcodebuild` commands
2. NEVER use `swift build` or `swift test`
3. ALWAYS read files before editing
4. NEVER create files unless necessary — prefer editing existing files
5. Follow global `~/.claude/CLAUDE.md` patterns (communication, security, CI/CD)
