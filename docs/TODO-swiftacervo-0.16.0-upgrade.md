# SwiftAcervo 0.14.0 → 0.16.0 Upgrade Audit

SwiftBruja currently resolves **SwiftAcervo 0.14.0** (`Package.resolved`). `Package.swift:88` declares `from: "0.14.0"` with `.upToNextMajor`, so this upgrade must also account for changes introduced in **0.14.1** and **0.15.0** in addition to 0.16.0.

Authoritative migration guide: `/Users/stovak/Projects/SwiftAcervo/UPGRADING.md` (sections "Upgrading to 0.14.1", "Upgrading to 0.15.0", "Upgrading to 0.16.0").

## Required code changes

### 1. Remove `Acervo.migrateFromLegacyPaths()` call (0.14.1 — REMOVED API)

- **File:** `Sources/SwiftBruja/Core/BrujaModelManager.swift:42-57` (function `migrateIfNeeded()`), call at `:46`.
- **Old pattern:** `let migrated = try Acervo.migrateFromLegacyPaths()` inside `migrateIfNeeded()`, gated by `migrationAttempted`.
- **New pattern:** The `AcervoMigration` utility was removed in 0.14.1. Delete the call. The migration path was a one-shot from the pre-0.12 layout; any user who has run any version >= 0.12 has either already migrated or has nothing to migrate.
- **Note:** Also delete the `migrationAttempted` flag (line 33), the `migrateIfNeeded()` function entirely, and its call site in `loadModel(_:)` at `Sources/SwiftBruja/Core/BrujaModelManager.swift:75`. This is a deletion, not a rename — no equivalent replacement exists in 0.16.0.

### 2. Bump SwiftAcervo dependency floor in `Package.swift`

- **File:** `Package.swift:85-88`.
- **Old pattern:** `sibling("SwiftAcervo", remote: "https://github.com/intrusive-memory/SwiftAcervo.git", from: "0.14.0")`.
- **New pattern:** Bump to `from: "0.16.0"`. `.upToNextMajor` is fine.
- **Note:** Also delete `Package.resolved` so SwiftPM re-resolves on next build, or run `swift package update SwiftAcervo`.

## Verification items (no change expected, just re-read the call site)

### 3. Confirm `Acervo.deleteModel(modelId)` is still sync `throws` (NOT async)

- **File:** `Sources/bruja/BrujaCLI.swift:94` — `try? Acervo.deleteModel(modelId)`.
- **0.16.0 status:** Repo-keyed `deleteModel(_:)` remained sync `throws`. The new slug-keyed `deleteModel(slug:url:)` is `async throws` (additive). No change required at this call site.
- **Note:** Verification only — confirm no compile error after bump.

### 4. Confirm `Acervo.ensureAvailable(_:, files:)` signature unchanged

- **Files:** `Sources/bruja/BrujaCLI.swift:113`, `Tests/SwiftBrujaTests/SwiftBrujaTests.swift:593`.
- **0.16.0 status:** Repo-keyed `ensureAvailable(_:files:progress:)` unchanged; new slug-keyed overload is additive. No change.

### 5. Confirm `Acervo.ensureComponentReady` unchanged

- **File:** `Tests/SwiftBrujaTests/SwiftBrujaTests.swift:484, 512`.
- **0.16.0 status:** Unchanged (lives in `Acervo+ComponentDownloads.swift`).

## Behavioral changes to verify after upgrade (no API rename, but semantics shifted)

### 6. `Acervo.listModels()` now filters by validity

- **File:** `Sources/SwiftBruja/Bruja.swift:78` — `try Acervo.listModels().map { BrujaModelInfo(from: $0) }`. Surfaced to CLI at `Sources/bruja/BrujaCLI.swift:366`.
- **Old behavior:** Returned all subdirectories of `sharedModelsDirectory`.
- **New behavior (0.16.0):** Skips directories without `config.json`. Orphan/empty dirs no longer appear.
- **Note:** Likely an improvement for `bruja list` output. If users have leftover empty model directories, they'll now silently disappear from the list. Consider whether to expose `Acervo.gcEmptyModelDirectories()` via a new CLI subcommand (e.g., `bruja gc`) — DESIGN DECISION required.

### 7. `Acervo.isModelAvailable(_:)` strict semantics already in effect since 0.14.0

- **Files:** `Sources/SwiftBruja/Bruja.swift:46`, `Sources/SwiftBruja/Core/BrujaModelManager.swift:63`, `Sources/SwiftBruja/Core/BrujaQuery.swift:129`.
- **Status:** These are all production gates on model load (the disposition recommended by UPGRADING.md Step 2a — "keep"). UPGRADING.md explicitly tags these sites at `Bruja.swift:46`, `BrujaModelManager.swift:63`, `BrujaQuery.swift:129` as **keep**.
- **Note:** No change. Already correct per the 0.14.0 migration. The two test sites at `SwiftBrujaTests.swift:31, 342` are negative assertions and remain safe.

## Design decisions (NOT mechanical renames)

### 8. Decide whether to adopt the new `ModelAvailability.partial` case

- **File scope:** Currently no `switch` over `ModelAvailability` exists anywhere in SwiftBruja (verified by `grep`). The `availability(_:)` API is unused.
- **0.16.0 implication:** No switch-exhaustiveness break to fix mechanically.
- **DECISION:** Either (a) leave alone — `isModelAvailable` is the only check SwiftBruja makes, and `.partial` will simply be reported as `false` by that bool; or (b) adopt `availability(_:)` in `BrujaCLI` (e.g., `bruja info --remote` or a new `bruja status` subcommand) to surface `.partial` as a "repair available" state, calling `ensureAvailable(modelId, files: [])` to refill missing shards. Option (b) gives users a recovery path for partial downloads; option (a) keeps the surface minimal.
- **Recommendation:** Option (a) for the upgrade itself; file option (b) as a follow-up enhancement.

### 9. CDN manifest fields `primaryRepo` / `components` (test fixture review)

- **File:** `Tests/SwiftBrujaTests/SwiftBrujaTests.swift:582-589` — builds a `CDNManifest` via the memberwise initializer omitting `primaryRepo` and `components`.
- **0.16.0 status:** In-memory `CDNManifest.init(...)` still defaults `primaryRepo = modelId` and `components = [modelId]`. The strict-decode requirement applies only to **wire** JSON. This fixture builds the manifest in memory then writes it via `AcervoDownloader.persistManifest`, which serializes the full struct including the defaulted fields, so re-reads will decode cleanly.
- **Note:** Verification only — no code change required, but worth running this test once after the bump to confirm.

## Caveats / risky usages flagged but not covered by UPGRADING.md

### 10. `BrujaModelInfo(from:)` mapping over `Acervo.listModels()` and `Acervo.modelInfo(_:)`

- **Files:** `Sources/SwiftBruja/Bruja.swift:72, 78`; `Sources/SwiftBruja/Core/BrujaTypes.swift` (defines the mapping).
- **Risk:** If `Acervo.modelInfo`'s return-type shape changed any of its fields' names or types in 0.16.0, the mapping breaks. UPGRADING.md does not mention `modelInfo` as changed; the move to `Acervo+Discovery.swift` is documented as symbol-preserving. Verify `BrujaTypes.swift` field mapping still compiles.
- **Note:** Verification only.

### 11. `BrujaModelManager.loadModel` calls `Acervo.modelInfo(modelId).sizeBytes`

- **File:** `Sources/SwiftBruja/Core/BrujaModelManager.swift:93`; also `Sources/SwiftBruja/Core/BrujaQuery.swift:51`.
- **Risk:** Same as #10 — depends on `modelInfo` return shape exposing `sizeBytes`. Not called out in UPGRADING.md. Verify after bump.

### 12. `AcervoDownloader.persistManifest(_:in:)` — internal API

- **File:** `Tests/SwiftBrujaTests/SwiftBrujaTests.swift:590`.
- **Risk:** UPGRADING.md cites this in the 0.14.0 fixture pattern with `@testable import SwiftAcervo`, which SwiftBruja already does (`SwiftBrujaTests.swift:4`). Internal-symbol stability is not guaranteed across minor versions. If this fails to resolve after the bump, switch to a public-API path.
- **Note:** Verification.

### 13. `bruja info --remote` uses `Acervo.fetchManifest(for: model)`

- **File:** `Sources/bruja/BrujaCLI.swift:432`.
- **Status:** `fetchManifest(for:)` lives in `Acervo+ManifestAccess.swift` in 0.16.0, public surface unchanged. No change needed.
- **Note:** Verification.

## Doc/comment refreshes (cosmetic, low priority)

### 14. Comments referencing pre-0.16 file layout

- **File:** `Sources/SwiftBruja/Core/BrujaModelManager.swift:13`, `:71-72` — references to `Acervo.ensureAvailable` and `Acervo.ensureComponentReady`. Still accurate; no change.
- **File:** `Tests/SwiftBrujaTests/SwiftBrujaTests.swift:565` — comment cites "0.14.0 strict semantics". Update to "0.14.0+ strict semantics" since the test still seeds the same way.
- **File:** `Sources/BrujaHelpers/ProgressRenderer.swift:131` — docstring references `Acervo.ensureAvailable(_:files:progress:)`. Still accurate.

## Summary checklist

- [ ] Delete `migrateIfNeeded()` and `migrationAttempted` from `BrujaModelManager.swift` (item 1)
- [ ] Bump `Package.swift` SwiftAcervo dep to `from: "0.16.0"` (item 2)
- [ ] Re-resolve `Package.resolved` (or `swift package update`)
- [ ] Build + run full test suite to surface any unforeseen compile/runtime breaks (items 3-7, 9-13)
- [ ] DECISION: adopt `availability(_:)` and `.partial` UI state? (item 8)
- [ ] DECISION: expose `Acervo.gcEmptyModelDirectories()` via CLI? (item 6)
- [ ] Refresh stale comment at `SwiftBrujaTests.swift:565` (item 14)
