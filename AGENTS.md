---
type: reference
updated: 2026-06-23
---

# AGENTS.md

This file provides comprehensive documentation for AI agents working with the SwiftBruja codebase.

**Current Version**: 1.8.1

---

## Project Overview

SwiftBruja makes local LLM queries as simple as possible. One import, one line of code, and you have on-device AI inference on Apple Silicon with GPU acceleration.

**Design Philosophy**: Simplicity over inference. Models are pre-downloaded via SwiftAcervo. No cloud APIs, no API keys, no network latency - just fast, private, on-device AI.

## Breaking Changes

**`BrujaDownloadManager` has been removed** — call `Acervo.*` directly for model lifecycle operations (download, list, info, delete, manifest fetch). The component-registry shim in `BrujaModelManager` (static `registeredComponents` / `isComponentRegistered` / `component(for:)`) and the `fetchManifestForBrujaId` dispatcher have also been removed; use `Acervo.registeredComponents(ofType:)`, `Acervo.component(_:)`, and `Acervo.fetchManifest(for:)` directly.

## Queryable Codemap

A prebuilt [graphify](https://pypi.org/project/graphifyy/) knowledge graph of this
codebase lives in [`graphify-out/`](graphify-out/) (762 nodes · 1296 edges). **Prefer
querying it before grepping** for architecture or "what connects to what" questions:

```bash
graphify query "How does X flow through the system?"
graphify path "TypeA" "TypeB"      # shortest path between two nodes
graphify explain "SomeType"        # plain-language node explanation
```

Human-readable summary: [`graphify-out/GRAPH_REPORT.md`](graphify-out/GRAPH_REPORT.md).
Refresh after significant changes with `/codemap` (or
`graphify . --backend claude-cli`).

## Project Structure

- `Sources/SwiftBruja/` -- Library target with static `Bruja` API
  - `Bruja.swift` -- Main entry point (static methods: `query`, `queryWithMetadata`, `listModels`)
  - `Core/BrujaModelManager.swift` -- Loads models into memory, validates memory
  - `Core/BrujaQuery.swift` -- Query execution via MLX, resolves models via SwiftAcervo
  - `Core/BrujaMemory.swift` -- Memory validation and auto-tuned maxTokens
  - `Core/BrujaTypes.swift` -- `BrujaQueryResult`, `BrujaModelInfo`
  - `Core/BrujaError.swift` -- Error types (includes agent errors: `toolExecutionFailed`, `agentStepLimitExceeded`, `contextWindowExceeded`)
  - `Agent/MLXAgentLoop.swift` -- the hand-rolled macOS-26 MLX agent loop (owns the tool round-trip)
  - `Agent/MLXGeneration.swift` -- MLX generation seam (`GenerationSource`, `ContainerGenerationSource`, `TurnState` KV-cache reuse + step cap)
  - `Agent/ToolDispatch.swift` -- JSON→tool dispatch, `MLXToolEncoding` (Tool→ToolSpec), `AgentToolHandling`/`RegistryToolHandler`
  - `Agent/FoundationModelBackend.swift` -- Foundation Models backend (uses `SystemLanguageModel.default` via `LanguageModelSession`)
  - `Agent/AgentBackendSelector.swift` -- Backend resolution from `--backend`/`--model` flags
  - `Agent/PathGuard.swift` -- Working-directory confinement guard (classify / escape-consent)
  - `Agent/TokenizerBridge.swift` -- Bridges huggingface/swift-transformers to `MLXLMCommon.Tokenizer` seam
  - `Agent/Tools/` -- 7 built-in tools (ReadFileTool, WriteFileTool, EditFileTool, ListDirTool, GrepTool, GlobTool, RunShellTool)
  - `Agent/Tools/ToolRegistry.swift` -- Single `[any Tool]` array consumed by both backends
  - `Agent/Tools/ToolResult.swift` -- Compact result string convention + truncation policy
- `Sources/BrujaHelpers/` -- CLI helper utilities
  - `IOCoordinator.swift` -- Serialized terminal I/O actor (token streaming, consent prompts)
  - `ProgressRenderer.swift` -- TTY/non-TTY progress rendering
- `Sources/bruja/` -- CLI executable target
  - `BrujaCLI.swift` -- Root command + subcommand registration
  - `AgentCommand.swift` -- `bruja agent` verb + AgentLoop + ConsentToolObserver + ConsentToolWrapper
  - `ErrorReporting.swift` -- Typed CLI error mapping
- `Tests/SwiftBrujaTests/` -- Unit tests (agent tools, PathGuard, backend selection, mock harness)
- `Tests/BrujaIntegrationTests/` -- Integration tests (AgentSeamSpikeTest, AgentReplTest, FoundationBackendIntegrationTest)
- `Tests/ProgressRendererTests/` -- IOCoordinator + ProgressRenderer unit tests

## Key Components

| File | Purpose |
|------|---------|
| `Bruja.swift` | Static API for queries: `query()`, `queryWithMetadata()`, `listModels()`, `modelExists()` |
| `BrujaModelManager.swift` | Loads models into memory, validates memory, resolves models via SwiftAcervo |
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
| `list` | List cached models; flags agent-capable models | (none) |
| `info` | Show model metadata | `--model`, `--remote` |
| `agent` | Run the on-device agent loop with a full tool suite | `--backend`, `--model`, `--temperature`, `--max-tokens`, `--quiet` |

### `bruja agent` — Agentic CLI (Sorties 7–9)

`bruja agent` runs an autonomous agent loop that can inspect and modify files in the current working directory via a built-in tool suite, then answer using the results. It exposes two surfaces over the same loop:

- **Interactive REPL** (no positional argument): reads a line, runs one agent turn, repeats until `/quit` or Ctrl-D.
- **One-shot** (`bruja agent "<task>"`): runs exactly one turn on the same loop and exits.

```bash
# Interactive REPL
bruja agent

# One-shot
bruja agent "Read ./README.md and summarize the first paragraph"

# One-shot with Foundation Models backend
bruja agent --backend foundation "What files are in this directory?"

# MLX with explicit model override
bruja agent --backend mlx --model mlx-community/Qwen2.5-7B-Instruct-4bit "List all Swift files"
```

#### Backends

| Backend | Flag | Model source | Notes |
|---------|------|-------------|-------|
| MLX (default) | `--backend mlx` (or omit) | Any SwiftAcervo model id | Default model: `mlx-community/Qwen2.5-7B-Instruct-4bit` (4.3 GB, CDN-verified) |
| Foundation Models | `--backend foundation` | `SystemLanguageModel.default` (on-device) | Requires macOS 26+; selecting when unavailable is a full-stop typed error — no silent fallback |

The two backends use the **same** `ToolRegistry.defaultTools()` array and the **same** `LanguageModelSession(model:tools:instructions:)` seam — there is no second tool adapter. This is the architectural proof of the `FoundationModels.LanguageModelExecutor` abstraction.

The agentic default model (`mlx-community/Qwen2.5-7B-Instruct-4bit`) is deliberately distinct from the `query`/`chat` default (`mlx-community/Llama-3.2-1B-Instruct-4bit`). The agent path requires a larger, tool-capable instruct model; `Qwen2.5-7B-Instruct-4bit` is CDN-verified present (4.3 GB, 10 files). Do NOT substitute `Qwen2.5-Coder-7B-Instruct-4bit` — it returns HTTP 404 on the CDN.

#### Built-in tool suite

The agent has 7 built-in tools, each defined as a `FoundationModels.Tool` with a `@Generable` `Arguments` struct:

| Tool name | Purpose |
|-----------|---------|
| `read_file` | Read a file's text content |
| `write_file` | Write content to a path |
| `edit_file` | Replace an exact old string with a new string in a file |
| `list_dir` | List a directory's immediate children |
| `grep` | Search file contents for a pattern |
| `glob` | Match files by glob pattern under a base directory |
| `run_shell` | Run a shell command; return stdout/stderr/exit code |

All tools enforce large-output truncation at a shared threshold to keep model context within bounds.

#### Working-directory confinement (PathGuard)

All filesystem tools (`read_file`, `write_file`, `edit_file`, `list_dir`, `grep`, `glob`) are confined to the current working directory via `PathGuard` (`Sources/SwiftBruja/Agent/PathGuard.swift`):

- **In-cwd paths** proceed without confirmation (R6.1).
- **Escaping paths** (absolute, `..`-traversal, or symlinks resolving outside cwd) trigger a blocking consent prompt in the REPL before any disk access occurs (R6.2/R6.5).
- **Unresolvable paths** are denied by default.

`run_shell` performs a best-effort scan of the command string for outside-cwd path tokens (R6.4). This is a guardrail, not a sandbox — variable expansion and command substitution are beyond static analysis.

**TOCTOU caveat**: PathGuard is a check-then-use guard, not an O_NOFOLLOW-based sandbox. A symlink swap in the window between classification and tool execution is theoretically possible. This is documented in `PathGuard.swift` and is acceptable for this POC.

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| mlx-swift | 0.31.3+ | Core MLX framework for Apple Silicon GPU |
| mlx-swift-lm | 3.31.3+ | LLM inference (MLXLLM, MLXLMCommon); 3.x ships Tokenizer/TokenizerLoader as protocols only |
| SwiftAcervo | 0.19.2+ | Shared model management (CDN download, cache, discovery, manifest-driven hydration) |
| swift-argument-parser | 1.7.1+ | CLI argument parsing |
| swift-transformers (huggingface) | 1.3.3+ | Concrete tokenizer implementation (AutoTokenizer, Jinja chat templates); bridged to MLXLMCommon via `TokenizerBridge.swift` |
| FoundationModels | system framework | Apple's on-device LLM seam (macOS 26+/27+); **no SPM entry required** — `import FoundationModels` suffices |

### Tokenizer: huggingface/swift-transformers via in-repo bridge

mlx-swift-lm 3.x ships `MLXLMCommon.Tokenizer` and `MLXLMCommon.TokenizerLoader` as **protocols only** — there is no concrete tokenizer in the MLX dependency tree. **There is no `MLXLMTokenizers` product** in mlx-swift-lm 3.31.3.

The concrete tokenizer is provided by [huggingface/swift-transformers](https://github.com/huggingface/swift-transformers) (the `Tokenizers` product), bridged to the `MLXLMCommon` seam in `Sources/SwiftBruja/Agent/TokenizerBridge.swift`:

- `SwiftTransformersTokenizer` — implements `MLXLMCommon.Tokenizer` backed by a `Tokenizers.Tokenizer` from swift-transformers.
- `SwiftTransformersTokenizerLoader` — implements `MLXLMCommon.TokenizerLoader`; calls `AutoTokenizer.from(modelFolder:)` to load `tokenizer.json`/`tokenizer_config.json` from the SwiftAcervo-resolved model directory, fully offline.

**Do NOT re-add** `swift-tokenizers`, `swift-tokenizers-mlx`, or `MLXLMTokenizers` — they are removed and the bridge replaces them. The old `swift-tokenizers exact: 0.5.0` pin is permanently struck.

### swift-tokenizers and swift-tokenizers-mlx are REMOVED

These packages are **no longer dependencies** of SwiftBruja. The old `swift-tokenizers exact: "0.5.0"` pin and the `swift-tokenizers-mlx` adapter (which provided the `MLXLMTokenizers` product) have been struck from `Package.swift`. The `swift-tokenizers-mlx 0.3.0` adapter never compiled against `swift-tokenizers 0.7.x` (encode/decode became typed-throws and the bridge was never updated), and mlx-swift-lm 3.x replaced the bundled tokenizer with a **protocol-only seam** (`MLXLMCommon.TokenizerLoader`). The concrete implementation now lives in the in-repo bridge (see above). **Do not re-add** a `swift-tokenizers` pin.

## Build and Test

**CRITICAL**: This library must ONLY be built using `xcodebuild` or `make` for functional builds. `swift build` compiles but Metal shaders won't load at runtime.

```bash
# Functional builds (required for queries to work)
make install    # Debug build → ./bin/bruja
make release    # Release build → ./bin/bruja
make dist       # Release build + distributable tarball in ./dist/ (binary + mlx-swift_Cmlx.bundle)

# Unit tests (MUST use xcodebuild)
xcodebuild test -scheme SwiftBruja-Package -destination 'platform=macOS' -only-testing:SwiftBrujaTests

# All tests
xcodebuild test -scheme SwiftBruja-Package -destination 'platform=macOS'

# End-to-end reference verification (R1–R5: offline load, TTY guard, error mapping, preflight)
make reference-check

# Unsandboxed agent integration tests (require fixture model + code-signed binary)
make install codesign-cli
make test-agent-seam    # S2 read_file round-trip spike
make test-agent-repl    # S7 agent REPL end-to-end
make test-agent-fm      # S9 Foundation Models backend integration
```

### Real-inference tests: App Group sandbox limitation

`xcodebuild test` runs in a sandboxed host process that cannot reach the `group.intrusive-memory.models` App Group container. All tests that drive real MLX inference or read from the shared models directory will `XCTSkip` under `xcodebuild test`. To run them:

1. Build + code-sign the binary: `make install codesign-cli`
2. Download the fixture model: `./bin/bruja download -m mlx-community/Qwen2.5-0.5B-Instruct-4bit`
3. Use the unsandboxed targets: `make test-agent-seam` / `make test-agent-repl` / `make test-agent-fm`

These targets use `xcrun xctest` (unsandboxed) with `ACERVO_APP_GROUP_ID` set, which can access the App Group container via plain POSIX (same-user, mode 700).

### CI Gating

The `Package.swift` manifest (`swift-tools-version: 6.2`, `.macOS(.v26)`) builds on the hosted `macos-26` image with its default Xcode 26. `tests.yml` (Code Quality + macOS Tests + Integration Tests) and `release.yml` all `runs-on: macos-26` and gate normally — no `continue-on-error` and no Xcode-27 selection.

The agent stack is intentionally macOS-26-only: the macOS-27 FoundationModels custom-provider seam (`LanguageModel`/`LanguageModelExecutor`) was removed, and the MLX backend uses the hand-rolled `MLXAgentLoop` (driven by `MLXLMCommon` native tool-call parsing). Local note: a macOS-27 / Xcode 27 host still builds correctly because the `.macOS(.v26)` deployment target makes the compiler's availability checker flag any stray macOS-27 symbol as an error — so a local `make build` is a faithful proxy for the macOS-26 CI compile.

### Known pre-existing test failures (not regressions)

The following tests fail under `xcodebuild test` due to environmental constraints that pre-date this mission:

| Test | Reason |
|------|--------|
| `AcervoComponentReadyTests/testDownloadModelLevel2PathWorksForUnregisteredRepoId` | Requires live CDN network + App Group container access |
| `AcervoComponentReadyTests/testEnsureComponentReadyHydratesFiles` | Requires App Group container access (sandboxed host) |
| `AcervoManifestFetchTests/testEstimatedSizeForProductionModelIsNonZeroAndCreatesNoFiles` | Requires live CDN network access |
| `ErrorReportingSmokeTest/testDownloadMissingModelExitsNonZeroWithCanonicalMessage` | S7 added the SharedModels stderr prefix; the underlying verb works (covered by `make reference-check` Step 4) |
| `BrujaModelManagerTests/*` (3 tests) | Require App Group container access (sandboxed host) |
| `SwiftBrujaTests/testListModels_ReturnsArray` | Requires App Group container access (sandboxed host) |

`make reference-check` (local) and `make test-ci` (hosted CI) skip these via `-skip-testing` flags and gate the remaining suite for real. `make test` runs everything, including these environmental tests, for local full runs where the App Group container is present.

## Platform Requirements

**CRITICAL: Apple Silicon Only**

- **macOS 26.0+** (M1/M2/M3/M4 only) — the agent stack uses only macOS-26 APIs
- **Swift 6.2+** (`swift-tools-version: 6.2`)
- **NO Intel support** — MLX requires Apple Silicon GPU
- **NEVER add `@available` checks for platforms older than the macOS 26 deployment target**

The agent stack is built entirely on macOS-26 APIs: `FoundationModels` base APIs (`SystemLanguageModel`, `Tool`, `@Generable`, `LanguageModelSession`) plus `MLXLMCommon` generation (which parses tool calls natively). The macOS-27 custom-provider `LanguageModelExecutor` seam was **removed** — the MLX backend now owns its own tool round-trip via `MLXAgentLoop`. The `.macOS(.v26)` target in `Package.swift` is intentional and correct.

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

## App Group configuration (required)

SwiftBruja depends on [SwiftAcervo](https://github.com/intrusive-memory/SwiftAcervo) for shared model storage. SwiftAcervo v0.10.0 resolves its App Group ID in this order: `ACERVO_APP_GROUP_ID` env var → `com.apple.security.application-groups` entitlement (macOS only) → `fatalError`. There is **no silent fallback**.

- **Signed UI apps (macOS / iOS)**: declare `com.apple.security.application-groups` with `group.intrusive-memory.models` in your `.entitlements` file. iOS apps additionally need `ACERVO_APP_GROUP_ID=group.intrusive-memory.models` in the launch environment.
- **CLI tools, scripts, CI jobs, test runners**: export `ACERVO_APP_GROUP_ID=group.intrusive-memory.models` in the shell or job environment. The standard place is `~/.zprofile`:

    ```sh
    export ACERVO_APP_GROUP_ID=group.intrusive-memory.models
    ```

Without this, `Acervo.sharedModelsDirectory` traps with `fatalError`. See [SwiftAcervo's USAGE.md](https://github.com/intrusive-memory/SwiftAcervo/blob/main/USAGE.md) for full details.

For host-app Xcode setup and entitlements file snippet, see [README.md § App Group configuration](README.md#app-group-configuration-required).

## Related Documentation

- For host-app App Group setup, see [README.md § App Group configuration (required)](README.md#app-group-configuration-required)
