---
feature_name: OPERATION MIGRATING ELEPHANTS
---

# EXECUTION_PLAN.md — SwiftBruja v1.1 (Acervo Migration)

## Work Units

| Work Unit | Directory | Sprints | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| SwiftBruja | . | 5 | 1 | none |

## Summary

| Metric | Value |
|--------|-------|
| Work units | 1 |
| Total sprints | 5 |
| Dependency structure | sequential |

## Parallelism Structure

**Critical Path**: Sprint 1 → Sprint 2 → Sprint 3 → Sprint 4 → Sprint 5 (5 sprints)

**Parallelism**: None — single work unit, strictly sequential. Each sprint modifies files that the next sprint depends on.

**Agent Constraints**: All sprints require `make build` — **supervising agent only**.

---

### Sprint 1: Package.swift + LLMModelFiles Enum

**Priority**: 17 — Foundation sprint; all subsequent sprints depend on this. Establishes SwiftAcervo dependency.

**Estimated turns**: 22

**Entry criteria**:
- [ ] On `development` branch: `git branch --show-current` outputs `development`
- [ ] Clean working tree: `git status --porcelain` outputs nothing

**Tasks**:
1. Update `Package.swift`:
   - Add SwiftAcervo dependency: `.package(url: "https://github.com/intrusive-memory/SwiftAcervo.git", branch: "main")`
   - Add `.product(name: "SwiftAcervo", package: "SwiftAcervo")` to `SwiftBruja` target dependencies
   - Add `.product(name: "SwiftAcervo", package: "SwiftAcervo")` to `bruja` target dependencies
   - Add `.product(name: "SwiftAcervo", package: "SwiftAcervo")` to `SwiftBrujaTests` target dependencies
   - Remove `.package(url: "https://github.com/huggingface/swift-transformers", from: "1.1.0")` from package dependencies
   - Remove `.product(name: "Hub", package: "swift-transformers")` from `SwiftBruja` target dependencies
2. Create `Sources/SwiftBruja/Core/LLMModelFiles.swift` with this exact content:
   ```swift
   /// Required files for LLM model downloads via Acervo
   enum LLMModelFiles {
       static let required: [String] = [
           "config.json",
           "tokenizer.json",
           "tokenizer_config.json",
           "model.safetensors",
       ]
   }
   ```
3. Remove `import Hub` from `Sources/SwiftBruja/Core/BrujaModelManager.swift` (line 2). No other changes to this file.
4. Remove `import Hub` from `Sources/SwiftBruja/Core/BrujaQuery.swift` (line 2). No other changes to this file.
5. Run `make build` to verify the package resolves and compiles.

**Exit criteria**:
- [ ] `make build` exits with code 0
- [ ] `grep -c "SwiftAcervo" Package.swift` returns 4 or more (package dep + 3 targets)
- [ ] `grep -c "swift-transformers" Package.swift` returns 0
- [ ] `test -f Sources/SwiftBruja/Core/LLMModelFiles.swift`
- [ ] `grep -rc "import Hub" Sources/SwiftBruja/` returns 0
- [ ] Git commit on `development` branch

---

### Sprint 2: Create BrujaDownloadManager

**Priority**: 12.5 — Foundation sprint; Sprint 3 depends on this actor existing.

**Estimated turns**: 13

**Entry criteria**:
- [ ] Sprint 1 exit criteria met
- [ ] `make build` exits with code 0

**Tasks**:
1. Create `Sources/SwiftBruja/Core/BrujaDownloadManager.swift` with this implementation:
   ```swift
   import Foundation
   import SwiftAcervo

   /// Thin wrapper around SwiftAcervo for model download and discovery.
   /// Does NOT load models — only ensures files are present at known paths.
   public actor BrujaDownloadManager {

       public static let shared = BrujaDownloadManager()

       private init() {}

       /// Shared models directory (~/Library/SharedModels/)
       public nonisolated var modelsDirectory: URL {
           Acervo.sharedModelsDirectory
       }

       /// Get local directory for a model ID
       public nonisolated func modelDirectory(for modelId: String) throws -> URL {
           try Acervo.modelDirectory(for: modelId)
       }

       /// Check if a model is available locally
       public nonisolated func isModelAvailable(_ modelId: String) -> Bool {
           Acervo.isModelAvailable(modelId)
       }

       /// Download a model if not already available
       public func downloadModel(
           _ modelId: String,
           force: Bool = false,
           progress: (@Sendable (Double) -> Void)? = nil
       ) async throws {
           if force {
               try? Acervo.deleteModel(modelId)
           }
           try await Acervo.ensureAvailable(
               modelId,
               files: LLMModelFiles.required
           ) { acervoProgress in
               progress?(acervoProgress.overallProgress)
           }
       }

       /// List all downloaded models
       public func listModels() throws -> [AcervoModel] {
           try Acervo.listModels()
       }

       /// Get info about a specific model
       public func modelInfo(_ modelId: String) throws -> AcervoModel {
           try Acervo.modelInfo(modelId)
       }

       /// Delete a model from disk
       public func deleteModel(_ modelId: String) throws {
           try Acervo.deleteModel(modelId)
       }

       /// Search for models by name
       public func findModels(matching query: String) throws -> [AcervoModel] {
           try Acervo.findModels(matching: query)
       }
   }
   ```
2. Run `make build` to verify it compiles. `BrujaDownloadManager` is not wired into callers yet.

**Exit criteria**:
- [ ] `test -f Sources/SwiftBruja/Core/BrujaDownloadManager.swift`
- [ ] `grep -c "import SwiftAcervo" Sources/SwiftBruja/Core/BrujaDownloadManager.swift` returns 1
- [ ] `grep -c "Acervo\." Sources/SwiftBruja/Core/BrujaDownloadManager.swift` returns 7 or more (delegates to Acervo)
- [ ] `make build` exits with code 0
- [ ] Git commit on `development` branch

---

### Sprint 3: Refactor Library Layer (BrujaModelManager + BrujaQuery + Bruja.swift + BrujaTypes)

**Priority**: 9.5 — Core migration sprint. Wires all library code to use Acervo/BrujaDownloadManager.

**Estimated turns**: 29

**Entry criteria**:
- [ ] Sprint 2 exit criteria met
- [ ] `BrujaDownloadManager.swift` exists and `make build` exits with code 0

**Tasks**:

#### 3a. Refactor `Sources/SwiftBruja/Core/BrujaModelManager.swift`

Strip to inference-only. Remove all download, list, info, and delete responsibilities:

- Add `import SwiftAcervo` at the top
- Remove `huggingFaceBaseURL` constant (line 17)
- Replace `modelsDirectory` computed property body → `Acervo.sharedModelsDirectory`
- Replace `isModelAvailable(_:)` body → `Acervo.isModelAvailable(modelId)`
- Replace `modelDirectory(for:)` body → `try Acervo.modelDirectory(for: modelId)` (signature changes: now `throws`)
- **Remove** these methods entirely:
  - `downloadModel(_:to:force:progress:)` (lines 59-112)
  - `ensureModelAvailable(_:to:force:progress:)` (lines 44-54)
  - `modelInfo(_:)` (lines 197-205)
  - `modelInfo(at:)` (lines 208-226)
  - `listModels()` (lines 229-230)
  - `listModels(in:)` (lines 234-253)
  - `deleteModel(_:)` (lines 257-267)
  - `calculateDirectorySize(_:)` (lines 271-291)
- Add migration support:
  ```swift
  private var migrationAttempted = false

  func migrateIfNeeded() {
      guard !migrationAttempted else { return }
      migrationAttempted = true
      do {
          let migrated = try Acervo.migrateFromLegacyPaths()
          if !migrated.isEmpty {
              print("[SwiftBruja] Migrated \(migrated.count) model(s) to ~/Library/SharedModels/")
          }
      } catch {
          print("[SwiftBruja] Warning: legacy migration failed: \(error.localizedDescription)")
      }
  }
  ```
- Update `loadModel(_ modelId:)`:
  - Call `migrateIfNeeded()` at entry
  - Guard check: `Acervo.isModelAvailable(modelId)`
  - Path: `let modelDir = try Acervo.modelDirectory(for: modelId)`
  - Memory validation: get size via `try Acervo.modelInfo(modelId).sizeBytes` (replaces `calculateDirectorySize`)
  - Keep `LLMModelFactory` loading logic unchanged
- Keep `loadModel(from path:)` — but update memory validation to use `calculateDirectorySize` (keep a private copy for path-based loading only) OR use file system attributes
- Keep `unloadModel(_:)` and `unloadAllModels()` unchanged

#### 3b. Update `Sources/SwiftBruja/Core/BrujaQuery.swift`

- Add `import SwiftAcervo` at the top
- Update `resolveModel()`:
  - Local path logic: unchanged (load via `BrujaModelManager.shared.loadModel(from:)`)
  - HuggingFace ID path: call `await BrujaDownloadManager.shared.downloadModel(model)`, then `let modelDir = try Acervo.modelDirectory(for: model)`, then `try await BrujaModelManager.shared.loadModel(model)`
- Update `maxTokens` auto-tuning in `queryWithMetadata()`:
  - Replace `manager.modelInfo(at: modelDir).sizeBytes` with `try Acervo.modelInfo(model).sizeBytes`
  - Simplify: for HuggingFace IDs, use `Acervo.modelInfo(model).sizeBytes`; for local paths, use the path-based size calculation

#### 3c. Update `Sources/SwiftBruja/Bruja.swift`

- Add `import SwiftAcervo` at the top
- `defaultModelsDirectory` → return `Acervo.sharedModelsDirectory`
- `modelExists(id:)` → return `Acervo.isModelAvailable(id)`
- `download(model:to:force:progress:)` → remove the `to:` parameter. New signature:
  ```swift
  public static func download(
      model: String,
      force: Bool = false,
      progress: (@Sendable (Double) -> Void)? = nil
  ) async throws
  ```
  Body delegates to `await BrujaDownloadManager.shared.downloadModel(model, force: force, progress: progress)`
- `modelInfo(at:)` → delegate to `Acervo.modelInfo(path)` and bridge to `BrujaModelInfo`
- `listModels(in:)` → remove the `in:` parameter. New signature:
  ```swift
  public static func listModels() throws -> [BrujaModelInfo]
  ```
  Body: `try Acervo.listModels().map { BrujaModelInfo(from: $0) }`

#### 3d. Update `Sources/SwiftBruja/Core/BrujaTypes.swift`

Keep `BrujaModelInfo` as a concrete struct (NOT a typealias — `AcervoModel.path` is `URL` while `BrujaModelInfo.path` is `String`, so a typealias would be source-breaking). Add a bridging initializer:

```swift
extension BrujaModelInfo {
    /// Bridge from AcervoModel
    public init(from acervo: AcervoModel) {
        self.init(
            id: acervo.id,
            path: acervo.path.path,
            sizeBytes: acervo.sizeBytes,
            downloadDate: acervo.downloadDate
        )
    }
}
```

Add `import SwiftAcervo` to the file.

#### 3e. Verify

Run `make build` to verify all library code compiles.

**Exit criteria**:
- [ ] `make build` exits with code 0
- [ ] `grep -c "downloadModel" Sources/SwiftBruja/Core/BrujaModelManager.swift` returns 0
- [ ] `grep -c "ensureModelAvailable" Sources/SwiftBruja/Core/BrujaModelManager.swift` returns 0
- [ ] `grep -c "migrateIfNeeded" Sources/SwiftBruja/Core/BrujaModelManager.swift` returns 2 or more (declaration + call)
- [ ] `grep -c "import SwiftAcervo" Sources/SwiftBruja/Core/BrujaQuery.swift` returns 1
- [ ] `grep -c "import SwiftAcervo" Sources/SwiftBruja/Bruja.swift` returns 1
- [ ] `grep -c "BrujaDownloadManager" Sources/SwiftBruja/Core/BrujaQuery.swift` returns 1 or more
- [ ] `grep -c "init(from acervo:" Sources/SwiftBruja/Core/BrujaTypes.swift` returns 1
- [ ] No `import Hub` in any file: `grep -rc "import Hub" Sources/SwiftBruja/` returns 0
- [ ] Git commit on `development` branch

---

### Sprint 4: Update CLI Commands + Version Bump

**Priority**: 5 — Leaf sprint; only Sprint 5 depends on this.

**Estimated turns**: 16

**Entry criteria**:
- [ ] Sprint 3 exit criteria met
- [ ] Library layer fully migrated: `make build` exits with code 0

**Tasks**:
1. Update `Sources/bruja/BrujaCLI.swift`:
   - Add `import SwiftAcervo` at the top
   - Change version string from `"1.0.11"` to `"1.1.0"` (line 28)
   - Update `discussion` string in `BrujaCLI.configuration`: change `~/Library/Caches/intrusive-memory/Models/LLM/` to `~/Library/SharedModels/`

2. Update `DownloadCommand`:
   - Remove `@Option ... var destination: String?`
   - Remove `--destination` from help text / discussion
   - Update `run()`: remove `destURL` computation, call `SwiftBruja.Bruja.download(model: model, force: force) { progress in ... }`
   - Update print statement to show `Acervo.sharedModelsDirectory.path` instead of old path

3. Update `QueryCommand`:
   - Remove `@Option ... var destination: String?`
   - Remove `downloadDestination:` argument from the `Bruja.queryWithMetadata()` call
   - Update help text that references old cache path

4. Update `ChatCommand`:
   - Remove `@Option ... var destination: String?`
   - Remove `destURL` and `downloadDestination:` usage
   - Update help text

5. Update `ListCommand`:
   - Remove `@Option ... var path: String?`
   - Update `run()`: call `SwiftBruja.Bruja.listModels()` (no directory parameter)
   - Update display: `model.id` and `model.formattedSize` work on `BrujaModelInfo`
   - Update the "No models found" message to show `Acervo.sharedModelsDirectory.path`

6. Update `InfoCommand`:
   - Update `run()` to use `BrujaModelInfo` properties (`.path` is still a `String`, no change needed)

7. Run `make build` to verify.

**Exit criteria**:
- [ ] `make build` exits with code 0
- [ ] `grep -c '"1.1.0"' Sources/bruja/BrujaCLI.swift` returns 1
- [ ] `grep -c "Caches/intrusive-memory" Sources/bruja/BrujaCLI.swift` returns 0
- [ ] `grep -c "destination" Sources/bruja/BrujaCLI.swift` returns 0
- [ ] `grep -c -- "--path" Sources/bruja/BrujaCLI.swift` returns 0
- [ ] Git commit on `development` branch

---

### Sprint 5: Tests + Docs + Final Verification

**Priority**: 2 — Final sprint; no dependents.

**Estimated turns**: 26

**Entry criteria**:
- [ ] Sprint 4 exit criteria met
- [ ] `make build` exits with code 0

**Tasks**:
1. Update `Tests/SwiftBrujaTests/SwiftBrujaTests.swift`:
   - Add `import SwiftAcervo` if needed
   - Update any references to old model paths (`~/Library/Caches/intrusive-memory/Models/LLM/`)
   - Update any usage of `BrujaModelInfo` if constructors changed
   - Ensure all tests compile

2. Update `Tests/BrujaIntegrationTests/BrujaIntegrationTests.swift`:
   - Same updates as unit tests
   - Verify integration test references correct paths

3. Run `make test` — all tests must pass.

4. Update `CLAUDE.md`:
   - Change "Models directory" default from `~/Library/Caches/intrusive-memory/Models/LLM/` to `~/Library/SharedModels/`
   - Replace all references to the old cache path with `~/Library/SharedModels/`
   - Update "Dependencies" section: replace `swift-transformers` with `SwiftAcervo`
   - Update "Shared Model Cache" section to describe the new flat `~/Library/SharedModels/` structure
   - Update default model if it changed (currently `mlx-community/Qwen3-Coder-Next-4bit` — keep as-is)

5. Update `AGENTS.md`:
   - Update version from `1.0.10` to `1.1.0`
   - Update `BrujaModelManager.swift` description: remove "Downloads models from HuggingFace Hub", add "Loads models into memory, validates memory"
   - Add `Core/BrujaDownloadManager.swift` to project structure: "Thin SwiftAcervo wrapper for model download and discovery"
   - Add `Core/LLMModelFiles.swift` to project structure: "Required file list for LLM model downloads"
   - Update Dependencies table: replace `swift-transformers | 1.1.0+ | HuggingFace Hub API` with `SwiftAcervo | main | Shared model management (download, cache, discovery)`
   - Update "Shared cache" line from `~/Library/Caches/intrusive-memory/Models/LLM/` to `~/Library/SharedModels/`
   - Update "Shared Model Cache" section to describe the Acervo flat structure

6. Run `make build` and `make test` one final time.

**Exit criteria**:
- [ ] `make test` exits with code 0
- [ ] `make build` exits with code 0
- [ ] `grep -c "Caches/intrusive-memory" CLAUDE.md` returns 0
- [ ] `grep -c "SharedModels" CLAUDE.md` returns 1 or more
- [ ] `grep -c "SwiftAcervo" CLAUDE.md` returns 1 or more
- [ ] `grep -c "Caches/intrusive-memory" AGENTS.md` returns 0
- [ ] `grep -c "SharedModels" AGENTS.md` returns 1 or more
- [ ] `grep -c "1.1.0" AGENTS.md` returns 1
- [ ] `grep -rc "Caches/intrusive-memory" Sources/` returns 0
- [ ] Git commit on `development` branch
- [ ] All commits on `development`, ready for PR to `main`

---

## Resolved Design Decisions

These decisions were made during refinement to eliminate ambiguity for sprint agents:

| Decision | Resolution | Rationale |
|----------|-----------|-----------|
| **BrujaModelInfo vs AcervoModel** | Keep `BrujaModelInfo` as concrete struct, add `init(from: AcervoModel)` bridge | `AcervoModel.path` is `URL`, `BrujaModelInfo.path` is `String` — typealias would be source-breaking |
| **Remove `to:`/`downloadDestination:` params?** | Yes, remove from all public API methods | Acervo owns the path; destination params are meaningless. v1.1.0 minor bump allows API changes. |
| **calculateDirectorySize in BrujaModelManager** | Replace with `Acervo.modelInfo(modelId).sizeBytes` for ID-based loads. Keep private helper only for `loadModel(from path:)` | Acervo already computes size; avoid duplication |
| **Remove `--destination` CLI flag?** | Yes, remove from download/query/chat commands | Acervo has one canonical directory; user-specified destinations are no longer supported |
| **Remove `--path` from list command?** | Yes, remove | Acervo scans `~/Library/SharedModels/` only |
