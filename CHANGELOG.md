---
type: doc
updated: 2026-07-04
---

# Changelog

All notable changes to SwiftBruja will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.9.0] - 2026-07-04

### Changed
- **Tokenizer loading** — replaced the hand-written `TokenizerBridge` (~100 lines) with mlx-swift-lm's own `#huggingFaceTokenizerLoader()` macro from the `MLXHuggingFace` product. The macro expands to the identical offline `AutoTokenizer.from(modelFolder:)` load with `addGenerationPrompt: true`, verified behaviorally equivalent (plain generation + agentic tool-calling round-trips) before swapping. `swift-transformers` remains a required dependency — the macro generates the adapter, it does not vendor the tokenizer.
- **SwiftAcervo** — bumped from 0.20.0 to 0.23.0.

### Fixed
- **Non-interactive builds** — `Package.swift` regained the `import Foundation` its sibling helper needs (was silently breaking CI manifest resolution). The Makefile now passes `-skipMacroValidation` (for the `MLXHuggingFaceMacros` plugin) and `-skipPackagePluginValidation` (for mlx-swift's `CudaBuild` build-tool plugin) on every build/test invocation, so `make build`/`test`/`dist` and CI run without an interactive trust prompt.
- **`make test-ci`** — now forwards `ACERVO_CDN_BASE_URL` into the sandboxed xctest runner via xcodebuild's `TEST_RUNNER_` prefix, so the `--remote` manifest tests pass locally instead of trapping on an unset CDN URL.

---

## [1.8.1] - 2026-06-23

### Fixed
- **`Package.swift` manifest** — restored the `import Foundation` the sibling-dependency helper relies on, so the manifest evaluates cleanly on a fresh checkout instead of failing to resolve.

### Changed
- **Release hygiene** — `Package.swift` ships in remote-only shape (sibling scaffolding stripped, `SwiftAcervo` pinned to `.upToNextMajor(from: "0.20.0")`); docs and the queryable codemap refreshed for the release.

---

## [1.7.1] - 2026-05-23

### Changed
- **SwiftAcervo upgrade** — bumped from 0.14.0 to 0.16.0. Picks up the 0.14.1, 0.15.0, and 0.16.0 changes in a single hop.

### Removed
- **`BrujaModelManager.migrateIfNeeded()` and the `migrationAttempted` flag** — the underlying `Acervo.migrateFromLegacyPaths()` was removed in SwiftAcervo 0.14.1. The migration path was a one-shot from the pre-0.12 layout; anyone who has run any version ≥ 0.12 either already migrated or has nothing to migrate.

---

## [1.8.0] - 2026-06-21

### Added

- **`bruja agent` — local agentic CLI** — a real agent loop with a built-in file/shell tool suite (`ReadFileTool`, `WriteFileTool`, `RunShellTool`) routed through a `ToolRegistry`, scoped to the current working directory with path-guard enforcement. Two backends sit behind one seam: `--backend mlx` (default, any acervo model id, hand-rolled tool-call loop on `MLXLMCommon`) and `--backend foundation` (Apple's on-device Foundation Models system model). Backend selection is an explicit, typed full-stop on unavailability — no silent fallback.
- **Model preflight on the CDN** — `ModelPreflight` checks model existence on the CDN before attempting load/download, so missing-model failures surface early with a clear error instead of mid-inference.
- **`cli.entitlements`** — entitlements file for the signed CLI executable.

### Changed

- **Retargeted to macOS 26+** — the project is a macOS-first CLI; iOS is out of scope. The agent stack runs on macOS 26 APIs (`FoundationModels.Tool` + `@Generable` + `LanguageModelSession`, and `MLXLMCommon` generation with native tool-call parsing). The macOS-27-only custom-provider seam (`LanguageModel`/`LanguageModelExecutor`) was removed so the project builds and tests on the macOS 26 CI image.
- **Dependency set pared to the agentic-CLI essentials** — manifest reworked around mlx-swift / mlx-swift-lm 3.x, SwiftAcervo, swift-argument-parser, and huggingface/swift-transformers (concrete tokenizer bridged to `MLXLMCommon` via `TokenizerBridge.swift`).
- **Loosened model-presence gates to `config.json`** so the agent can load cache-less models.
- **Swift 6 language mode pinned explicitly** on all first-party targets.
- **`BrujaModelManager.migrateIfNeeded()` logs to stderr** instead of stdout, so `bruja query --json` output stays machine-parseable when a legacy migration runs.
- **CLI help wording**: "HuggingFace ID" → "model ID" / "model path or ID" across `download`, `query`, `chat`, and `info`. The CDN is the source of truth, not the HuggingFace Hub.

### Removed

- **`BrujaModelManager` component-registry shim** — the static `registeredComponents`, `isComponentRegistered`, and `component(for:)` helpers have been removed. Call `Acervo.registeredComponents(ofType:)`, `Acervo.component(_:)` directly.
- **`BrujaComponents.swift`** — the bundled `qwen3-coder-next-4bit` `ComponentDescriptor` registration is gone. The CLI accepts raw repo IDs only; consumers that want a curated catalog should register their own descriptors with `Acervo.register(_:)`.
- **`fetchManifestForBrujaId(_:)` (`ManifestDispatcher.swift`)** — replaced by direct `Acervo.fetchManifest(for:)` calls. The `bruja info --remote` command was rewired in place.

---

## [1.5.x] - 2026-04

Library matured around the SwiftAcervo 0.8.x manifest-driven hydration pattern. `BrujaDownloadManager` was deleted in favor of direct `Acervo.*` calls; the CLI gained `chat`, `info --remote`, and stderr-routed `[bruja] SharedModels:` startup diagnostics. Memory auto-tuning, structured-output query, and `MLXLMTokenizers`-based mlx-swift-lm 3.x integration all stabilized in this range.

---

## [1.0.10] - 2026-01-31

### Changed

- **Minimum 4K Token Context** - `recommendedMaxTokens` now enforces a floor of 4096 tokens regardless of available memory, ensuring a minimum context window for all queries

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
