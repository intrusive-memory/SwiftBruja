# SwiftBruja v1.1 Requirements

## Goal

Migrate model management from SwiftBruja's internal `BrujaModelManager` to **SwiftAcervo**, the shared model management framework used across the intrusive-memory ecosystem. This follows the same integration pattern established by SwiftVoxAlta.

After this upgrade, SwiftBruja no longer owns model download, path resolution, availability checking, listing, or deletion. SwiftAcervo handles all of that. SwiftBruja focuses solely on LLM loading, inference, and memory management.

---

## What Changes

### 1. Add SwiftAcervo Dependency

- Add `SwiftAcervo` to `Package.swift` (branch: `main`, repo: `intrusive-memory/SwiftAcervo`)
- All three targets (`SwiftBruja`, `bruja`, `SwiftBrujaTests`) depend on `SwiftAcervo`
- Remove `swift-transformers` / `Hub` dependency (Acervo handles HuggingFace downloads)

### 2. Replace Model Path Convention

| Before | After |
|--------|-------|
| `~/Library/Caches/intrusive-memory/Models/LLM/{slug}/` | `~/Library/SharedModels/{slug}/` |

- All models share a single flat directory with every other intrusive-memory project
- No type subdirectories (LLM, TTS, Audio are peers)
- `config.json` presence marks a valid model

### 3. Refactor BrujaModelManager

Replace the current monolithic `BrujaModelManager` actor with two focused actors, following the SwiftVoxAlta pattern:

#### BrujaDownloadManager (new, thin wrapper)

Wraps SwiftAcervo for download and discovery. Delegates entirely:

- `modelsDirectory` -> `Acervo.sharedModelsDirectory`
- `modelDirectory(for:)` -> `Acervo.modelDirectory(for:)`
- `isModelAvailable(_:)` -> `Acervo.isModelAvailable(_:)`
- `downloadModel(_:progress:)` -> `Acervo.ensureAvailable(_:files:progress:)`
- `listModels()` -> `Acervo.listModels()`
- `deleteModel(_:)` -> `Acervo.deleteModel(_:)`
- `findModels(matching:)` -> `Acervo.findModels(matching:)`

#### BrujaModelManager (refactored, inference-only)

Keeps model loading, caching, and memory validation:

- `migrateIfNeeded()` - One-time call to `Acervo.migrateFromLegacyPaths()` at first load
- `isModelInAcervo(_:)` - Delegates to `Acervo.isModelAvailable(_:)`
- `loadModel(modelId:)` - Loads via `LLMModelFactory` from Acervo's path
- `unloadModel()` / `unloadAllModels()` - Memory cleanup with `MLX.GPU` sync
- In-memory model cache (`loadedModels`)
- Memory validation before loading (existing `BrujaMemory` logic)

### 4. Define LLM Required Files

Create an `LLMModelFiles` enum listing the files SwiftBruja needs downloaded:

```swift
enum LLMModelFiles {
    static let required: [String] = [
        "config.json",
        "tokenizer.json",
        "tokenizer_config.json",
        "model.safetensors",
    ]
}
```

This list is passed to `Acervo.ensureAvailable(_:files:)`. Different model types may need different files; this is SwiftBruja's responsibility to specify.

### 5. Update BrujaQuery Model Resolution

`BrujaQuery.resolveModel()` currently handles both path detection and HuggingFace download. Refactor to:

1. Check if input is a local path -> load directly
2. Otherwise treat as HuggingFace ID:
   - Call `BrujaDownloadManager.downloadModel(_:)` (delegates to Acervo)
   - Get path via `Acervo.modelDirectory(for:)`
   - Load via `BrujaModelManager.loadModel(modelId:)`

### 6. Update Bruja.swift Public API

The public API surface does not change. These methods continue to work identically:

- `Bruja.query(...)` - unchanged signature
- `Bruja.queryWithMetadata(...)` - unchanged
- `Bruja.query(..., as: T.self)` - unchanged
- `Bruja.download(...)` - now delegates to Acervo internally
- `Bruja.modelExists(...)` - now delegates to Acervo internally
- `Bruja.listModels(...)` - now delegates to Acervo internally
- `Bruja.modelInfo(...)` - returns `AcervoModel` or bridges to `BrujaModelInfo`

### 7. Update CLI Commands

All CLI commands (`download`, `query`, `chat`, `list`, `info`) use the new managers internally. No user-facing CLI changes.

- `bruja list` - Uses `Acervo.listModels()` instead of scanning `~/Library/Caches/...`
- `bruja download` - Uses `Acervo.ensureAvailable()` instead of custom download logic
- `bruja info` - Uses `Acervo.modelInfo()` instead of custom metadata
- `bruja query` / `bruja chat` - Model resolution uses Acervo paths

### 8. Add Legacy Path Migration

On first model load, call `Acervo.migrateFromLegacyPaths()` to move any models from the old `~/Library/Caches/intrusive-memory/Models/LLM/` location to `~/Library/SharedModels/`. This is:

- One-time per session (guard with `migrationAttempted` flag)
- Non-blocking (log warnings, don't throw)
- Idempotent (safe to run multiple times)

### 9. Update BrujaModelInfo

Decide whether to:
- **Option A**: Replace `BrujaModelInfo` with `AcervoModel` throughout
- **Option B**: Keep `BrujaModelInfo` and bridge from `AcervoModel`

Recommendation: **Option A** for the library, keep `BrujaModelInfo` only if needed for backward compatibility in the public API.

### 10. Version Bump

- Bump version to `1.1.0` in:
  - `BrujaCLI.swift` (version string)
  - Any other version references
- Update CLAUDE.md and AGENTS.md to reflect new model path and architecture

---

## What Does NOT Change

- **Public query API** (`Bruja.query()`, `Bruja.queryWithMetadata()`, structured output)
- **BrujaMemory** (memory validation, maxTokens auto-tuning)
- **BrujaError** (error cases - may add/rename but don't remove)
- **CLI command names and flags** (user-facing interface is stable)
- **Default model** (`mlx-community/Qwen3-Coder-Next-4bit`)
- **Temperature, maxTokens defaults**
- **Chat session** (`bruja chat` interactive REPL)
- **Build system** (`make build`, `make install`, `make dist`)

---

## Acceptance Criteria

1. `make build` succeeds with SwiftAcervo dependency
2. `make test` passes all existing tests
3. Models download to `~/Library/SharedModels/` (not `~/Library/Caches/...`)
4. Models downloaded by SwiftVoxAlta or other Acervo consumers are visible to `bruja list`
5. Models downloaded by `bruja download` are visible to other Acervo consumers
6. Legacy models in `~/Library/Caches/intrusive-memory/Models/LLM/` are migrated on first use
7. `bruja query "test"` works end-to-end with auto-download via Acervo
8. `bruja chat` works with Acervo-managed models
9. CI passes (Code Quality, macOS Tests, Integration Tests)
10. Version reads `1.1.0`
