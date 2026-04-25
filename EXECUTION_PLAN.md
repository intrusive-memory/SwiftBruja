---
feature_name: OPERATION SNAKESKIN MOLT
mission_branch: mission/snakeskin-molt/01
starting_point_commit: dd32e95b97e50e880d960cb598bd0602d8ef9a4e
iteration: 1
mission_started: 2026-04-25
---

# EXECUTION_PLAN.md — SwiftBruja: Shed the Download Manager Wrapper

**Source:** `REQUIREMENTS_NEXT.md` (2026-04-25 draft)
**Predecessor:** OPERATION LIGHTHOUSE PLUMBING (iteration 1) — archived at `docs/complete/lighthouse-plumbing-01-execution-plan.md`
**SwiftAcervo version:** `≥ 0.8.2`
**SemVer impact:** **MAJOR** — deletes public APIs on `BrujaDownloadManager`. Next SwiftBruja release after this mission must be `2.0.0`.

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

## Mission Overview

Make SwiftBruja a pure consumer of SwiftAcervo's storage. Delete `BrujaDownloadManager` entirely (Shape A from REQUIREMENTS_NEXT.md). Migrate every caller (CLI subcommands, tests) to call `Acervo.*` directly. After this mission, SwiftBruja's domain is:

- **Component registry** — `Sources/SwiftBruja/Core/BrujaComponents.swift`
- **Inference orchestration** — `BrujaModelManager.loadModel`/`query`/`chat`
- **Memory validation** — `BrujaMemory`
- **CLI UX** — `Sources/bruja/`

LIGHTHOUSE PLUMBING's behavior contracts (R1 Level-3 delegation, R2 error mapping, R3 ProgressRenderer, R4 pre-flight, R5 SharedModels stderr, R6 docs) all survive — they live in CLI code and `Acervo.ensureComponentReady`, not in `BrujaDownloadManager`.

---

## Decisions Locked at Breakdown / Refine

The Open Questions in `REQUIREMENTS_NEXT.md` are decided here so sortie agents do not re-litigate them.

| Open Question | Decision | Rationale |
|---|---|---|
| **OQ-1** Shape A vs Shape B | **Shape A — delete `BrujaDownloadManager` entirely.** | Per REQUIREMENTS_NEXT.md recommendation. The `--force` composite (`try? Acervo.deleteModel(...)` then ensure) at each CLI call site is honest and SemVer-stable. When upstream `force:` lands, call sites collapse to one arg with no Bruja-side change. |
| **OQ-2** Dispatcher placement | **Free function inside SwiftBruja** at exact path `Sources/SwiftBruja/Core/ManifestDispatcher.swift`. | Avoids extending `Acervo` from a downstream package; SemVer-isolated; doesn't depend on upstream changes. |
| **OQ-3** Keep `bruja download` subcommand | **Yes, keep.** | Explicit pre-fetch UX is useful even when `query`/`chat` would auto-materialize. |
| **OQ-4** (refine) `--json` banner suppression strategy (Option A vs B in S5) | **Option A — route `[SwiftBruja] maxTokens …` print through `FileHandle.standardError` unconditionally.** | Simpler; addresses pollution at the source; no library API change; no flag plumbing; non-`--json` UX is a library-internal banner that legitimately belongs on stderr. |
| **OQ-5** (refine) S4 "pre-existing environmental failures" | Resolved via positive-list verification: confirm `make test` exits 0 with `BrujaIntegrationTests/ErrorReportingSmokeTest` running and passing (the LIGHTHOUSE skip is gone after S1). Any other environmental failures must be enumerated by name in the sortie completion notes — vague hand-waving is not acceptable. | Removes the loophole that "make test passes if it more or less passes." |

---

## Non-Goals

Inherited verbatim from `REQUIREMENTS_NEXT.md` § Non-Goals:

- Do NOT change SwiftAcervo's public API in this mission.
- Do NOT touch `BrujaModelManager.loadModel` / inference flow.
- Do NOT alter component registration in `BrujaComponents.swift`.
- Do NOT alter App Group entitlement docs (LIGHTHOUSE Sortie 9).
- Do NOT pin a new SwiftAcervo version unless the upstream `force:` overload lands during the mission window.

---

## Filed Upstream (Advisory)

These are tracked separately in `intrusive-memory/SwiftAcervo` and are NOT mission deliverables here:

- Add `force:` parameter to `Acervo.ensureComponentReady`
- Add `async` overload of `Acervo.withModelAccess`

If either lands during the mission, fold the integration into the relevant sortie via `/mission-supervisor refine`.

---

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| SwiftBruja | `.` | 6 | 0 | none |

Single-project mission; all sorties land on the mission branch via the supervisor.

---

## Parallelism Structure

**Critical Path**: S1 → S2 → S3 → S4 (length: 4 sorties). S5 (optional) tail-appends after S3 if scoped in. S6 parallels S4.

**Parallel Execution Groups**:
- **Group 1** (sequential): S1 — supervising agent (runs `make test`, `make reference-check`).
- **Group 2** (sequential, after S1): S2 — supervising agent (runs `make build`, `make test`).
- **Group 3** (sequential, after S2): S3 — supervising agent (runs `make build` + 7 CLI smoke invocations against CDN).
- **Group 4** (parallel, after S3):
  - S4 — **supervising agent only** (runs `make test`).
  - S6 — **sub-agent eligible** (pure docs editing; verification is `grep` only, no build).
- **Group 5** (sequential, after S3, optional): S5 — supervising agent (runs `bruja query` smoke checks).

**Agent Constraints**:
- **Supervising agent**: handles every sortie that runs `make build`, `make test`, `make reference-check`, or `bruja` CLI invocations (S1, S2, S3, S4, S5).
- **Sub-agents (max 4)**: only S6 qualifies — its exit criteria are grep-only and require no build artifacts. The supervisor may dispatch S6 in parallel with S4 to shave wall-clock time.

**Parallelism metrics**:
- Critical path length: 4 sorties (5 with S5).
- Maximum concurrency: 2 agents (1 supervising + 1 sub-agent during Group 4).
- Missed-opportunity audit: S5 was originally gated only on S1 — could in principle parallelize with S2/S3, but its verification depends on the post-S3 binary surface (no `BrujaDownloadManager` in CLI), so deferring to Group 5 avoids re-running checks on a transitional binary.

---

### Sortie 1: Fix `ErrorReportingSmokeTest` regression and remove Makefile skip (R4)

**Priority**: 18.5 — critical-path foundation. Unblocks 5 downstream sorties; the test suite must be green before any deletion-heavy work begins. Risk is low; complexity is low; foundation score 1 (test gating).

**Entry criteria**:
- [ ] First sortie — no prerequisites.

**Tasks**:
1. In `Tests/BrujaIntegrationTests/ErrorReportingSmokeTest.swift::testDownloadMissingModelExitsNonZeroWithCanonicalMessage`, replace the `stderrTrimmed.hasPrefix(Self.expectedStderrPrefix)` assertion (around line 84-85) with a line-by-line scan: `XCTAssertTrue(stderr.split(separator: "\n").contains { $0.hasPrefix(Self.expectedStderrPrefix) }, ...)`. Reason: LIGHTHOUSE Sortie 7 prepended `[bruja] SharedModels:` so the canonical R2 message is no longer the first line.
2. In `Makefile` `reference-check` target (Step 1, around line 115), remove `-skip-testing:BrujaIntegrationTests/ErrorReportingSmokeTest` from the xcodebuild test invocation.
3. Run `make test` to confirm `ErrorReportingSmokeTest` passes without the skip.
4. Run `make reference-check` end-to-end without the skip.

**Exit criteria**:
- [ ] `! grep -F 'skip-testing:BrujaIntegrationTests/ErrorReportingSmokeTest' Makefile` matches zero.
- [ ] `make test` exits 0 with `ErrorReportingSmokeTest` running and passing.
- [ ] `make reference-check` exits 0.

---

### Sortie 2: Delete `BrujaDownloadManager` pass-throughs and migrate CLI to `Acervo.*` (R1)

**Priority**: 14.0 — high dependency-depth (3 downstream); introduces the `ManifestDispatcher` free function that becomes the canonical componentId→repoId hop; foundation score 1.

**Entry criteria**:
- [ ] Sortie 1 complete (test suite is green again — needed to validate this sortie doesn't regress anything).
- [ ] Decisions locked: Shape A; dispatcher as free function in SwiftBruja at `Sources/SwiftBruja/Core/ManifestDispatcher.swift`.

**Tasks**:
1. Create new file at exact path `Sources/SwiftBruja/Core/ManifestDispatcher.swift` containing a free function: `public func fetchManifestForBrujaId(_ id: String) async throws -> CDNManifest`. Behavior: if `BrujaComponents.component(for: id)` returns a registered descriptor, call `Acervo.fetchManifest(forComponent: id)`; otherwise call `Acervo.fetchManifest(for: id)`. Pure dispatch, no state, no actor, no class.
2. Delete the following methods from `Sources/SwiftBruja/Core/BrujaDownloadManager.swift` (do NOT delete the actor in this sortie — that's Sortie 3):
   - `func listModels() throws -> [AcervoModel]`
   - `func modelInfo(_ modelId: String) throws -> AcervoModel`
   - `func deleteModel(_ modelId: String) throws`
   - `func findModels(matching query: String) throws -> [AcervoModel]`
   - `func manifestFiles(for modelOrComponentId: String) async throws -> [CDNManifestFile]`
   - `func estimatedSize(for modelOrComponentId: String) async throws -> Int64`
3. In `Sources/bruja/BrujaCLI.swift`, migrate every call to those six methods:
   - `BrujaDownloadManager.shared.listModels()` → `Acervo.listModels()`
   - `BrujaDownloadManager.shared.modelInfo(...)` → `Acervo.modelInfo(...)`
   - `BrujaDownloadManager.shared.deleteModel(...)` → `Acervo.deleteModel(...)`
   - `BrujaDownloadManager.shared.findModels(matching:)` → `Acervo.findModels(matching:)`
   - `BrujaDownloadManager.shared.manifestFiles(for:)` and `estimatedSize(for:)` → derive from `fetchManifestForBrujaId(_:)` introduced in task 1.
4. Run `make build` to verify no broken references in CLI or library.

**Exit criteria**:
- [ ] `test -f Sources/SwiftBruja/Core/ManifestDispatcher.swift` exits 0.
- [ ] `! grep -nE 'BrujaDownloadManager\.shared\.(listModels|modelInfo|deleteModel|findModels|manifestFiles|estimatedSize)' -r Sources/ Tests/` returns zero matches.
- [ ] `make build` exits 0.
- [ ] `make test` exits 0.

---

### Sortie 3: Strip `downloadModel`/`ensureComponentReady` and delete `BrujaDownloadManager` entirely (R2 — Shape A)

**Priority**: 11.0 — final deletion of the actor unblocks the parallel tail (S4 + S6). Risk 2 (deletion + 7-invocation CLI smoke test against CDN).

**Entry criteria**:
- [ ] Sortie 2 complete (pass-throughs deleted; CLI uses `Acervo.*` directly).
- [ ] Decision locked: Shape A (delete entire actor).

**Tasks**:
1. In `Sources/bruja/BrujaCLI.swift::DownloadCommand.run` (raw repoId path), replace `BrujaDownloadManager.shared.downloadModel(modelId, force: force, progress: ...)` with the explicit composite at the call site:
   ```swift
   if force { try? Acervo.deleteModel(modelId) }
   try await Acervo.ensureAvailable(modelId, files: []) { acervoProgress in
     progress(acervoProgress.overallProgress)
   }
   ```
2. In `Sources/bruja/BrujaCLI.swift` (component path), replace `BrujaDownloadManager.shared.ensureComponentReady(componentId, force: force, progress: ...)` with the inline equivalent:
   ```swift
   if force { try? Acervo.deleteModel(componentRepoId) }
   try await Acervo.ensureComponentReady(componentId) { acervoProgress in
     progress(acervoProgress.overallProgress)
   }
   let url = try Acervo.modelDirectory(for: componentRepoId)
   ```
3. Delete the entire file `Sources/SwiftBruja/Core/BrujaDownloadManager.swift`.
4. Sweep all remaining `BrujaDownloadManager` references in `Sources/`: run `grep -rn 'BrujaDownloadManager' Sources/` and update each hit. Known live references at refine time: `Sources/SwiftBruja/Core/BrujaModelManager.swift` lines 25 and 77 (doc comments). Update doc comments to reference `Acervo` directly. Also inspect `Sources/SwiftBruja/Bruja.swift` for re-exports or symbol references.
5. Run `make build` to verify the package still compiles.

**Exit criteria**:
- [ ] `! test -f Sources/SwiftBruja/Core/BrujaDownloadManager.swift`.
- [ ] `! grep -rE 'BrujaDownloadManager' Sources/` matches zero.
- [ ] `make build` exits 0.
- [ ] Each of these CLI invocations exits 0 against the `SMALL_FIXTURE_MODEL` (`mlx-community/Qwen2.5-0.5B-Instruct-4bit`) on the CDN: `bruja download`, `bruja download --force`, `bruja info --remote`, `bruja query`, `bruja chat`, `bruja list`, `bruja info`. (Network/CDN-dependent — surface as a single sortie note if CDN is unreachable; do not silently skip.)

---

### Sortie 4: Migrate tests off `BrujaDownloadManager` (R3)

**Priority**: 1.5 — pure tail work; no downstream dependencies. Eligible for the Group 4 parallel slot.

**Entry criteria**:
- [ ] Sortie 3 complete (`BrujaDownloadManager` deleted).

**Tasks**:
1. In `Tests/SwiftBrujaTests/SwiftBrujaTests.swift`, migrate the five existing `BrujaDownloadManager.shared.*` tests to `Acervo.*`:
   - `testEnsureComponentReadyHydratesFiles` → `Acervo.ensureComponentReady`
   - `testEnsureComponentReadyThrowsForUnregisteredComponent` → `Acervo.ensureComponentReady`
   - `testDownloadModelLevel2PathWorksForUnregisteredRepoId` → `Acervo.ensureAvailable`
   - `testEstimatedSizeForProductionModelIsNonZeroAndCreatesNoFiles` → `fetchManifestForBrujaId(_:)` (free function from Sortie 2)
   - `testManifestFilesForSmallFixtureModelReturnsNonEmptyArray` → `fetchManifestForBrujaId(_:)`
2. Confirm Bruja-owned tests (`BrujaModelManager.loadModel`/`query`/`chat`, `BrujaMemory`, `BrujaComponents` registration) still compile and pass — these are NOT migrated.

**Exit criteria**:
- [ ] `! grep -rE 'BrujaDownloadManager' Tests/` returns zero matches.
- [ ] `make test` exits 0.
- [ ] `BrujaIntegrationTests/ErrorReportingSmokeTest` runs and passes (no Makefile skip — verifies S1 still holds).
- [ ] If any test fails, the failing test name(s) MUST be enumerated in the sortie completion notes with a one-line cause attribution. "Pre-existing environmental failure" is not an acceptable hand-wave; name the test.

---

### Sortie 5 (optional): Suppress `[SwiftBruja]` stdout banner under `--json` (R5)

**Priority**: 2.5 — optional polish; orthogonal to the deletion chain. Defer if mission scope is constrained.

**Entry criteria**:
- [ ] Sortie 3 complete (binary surface stable; verification runs against the post-deletion CLI).
- [ ] **Optional** — may be deferred; nothing else depends on it.

**Tasks**:
1. Locate the emit site (pinned at refine time): `Sources/SwiftBruja/Core/BrujaQuery.swift:56` — `print("[SwiftBruja] maxTokens set to \(resolvedMaxTokens) for this query")`.
2. Implement **Option A** (decided in OQ-4): replace the `print(...)` call with an unconditional stderr emit, e.g.:
   ```swift
   FileHandle.standardError.write(Data("[SwiftBruja] maxTokens set to \(resolvedMaxTokens) for this query\n".utf8))
   ```
   Do NOT plumb a `quiet`/`json` flag through the library API. Do NOT add a configuration knob. The banner is library-internal diagnostic output and belongs on stderr in all modes.
3. Verify `bruja query "hi" --json 2>/dev/null | jq .` exits 0.
4. Verify `bruja query "hi" 2>/dev/null` (no `--json`) no longer emits the banner on stdout (banner is stderr-only now — this is the intentional UX shift).

**Exit criteria**:
- [ ] `! grep -nF 'print("[SwiftBruja] maxTokens' Sources/SwiftBruja/Core/BrujaQuery.swift` matches zero (the `print(...)` line is replaced).
- [ ] `grep -nF 'FileHandle.standardError.write' Sources/SwiftBruja/Core/BrujaQuery.swift` matches at least once near line 56.
- [ ] `bruja query "hi" --json 2>/dev/null | jq .` exits 0 (assumes the model is loadable in the test env — if it isn't, document the env gap in the sortie notes; do not silently skip).
- [ ] `make build` exits 0.

---

### Sortie 6: README + AGENTS.md SemVer-major note (R6)

**Priority**: 1.5 — pure docs; no build dependency. **Sub-agent eligible** — runs in parallel with S4.

**Entry criteria**:
- [ ] Sortie 3 complete (`BrujaDownloadManager` deletion finalized — code surface stable for documentation).

**Tasks**:
1. Update `README.md` to describe SwiftBruja as a "consumer of SwiftAcervo". Remove every `BrujaDownloadManager.shared.<method>` example; replace with the equivalent `Acervo.<method>` call.
2. In `AGENTS.md`, add a one-line breaking-change note in the migration / version section flagging the SemVer-major bump for host-app integrators (e.g. "**Breaking change in 2.0.0**: `BrujaDownloadManager` removed — call `Acervo.*` directly. See `REQUIREMENTS_NEXT.md` for migration mapping.").
3. Leave the App Group entitlement section (LIGHTHOUSE Sortie 9) untouched — still accurate.

**Exit criteria**:
- [ ] `! grep -F 'BrujaDownloadManager.shared' README.md` matches zero.
- [ ] `grep -iF 'breaking change' AGENTS.md` matches at least once.
- [ ] `grep -F 'BrujaDownloadManager' AGENTS.md` is allowed (the breaking-change note must name the deleted symbol).

---

## Composite Verification — `make reference-check`

After this mission, all five LIGHTHOUSE reference-check steps must still pass with no Makefile skips:

1. **Step 1 (full suite):** All tests including `ErrorReportingSmokeTest`. No `-skip-testing` flag.
2. **Step 2 (offline-load):** `bruja download` then `ACERVO_OFFLINE=1 bruja query`. CLI now calls `Acervo.*` directly.
3. **Step 3 (TTY guard):** ProgressRenderer behavior unchanged (LIGHTHOUSE Sortie 2 not touched).
4. **Step 4 (R2 error mapping):** `runCLI` + `humanReadable` mapping intact (LIGHTHOUSE Sortie 3 not touched).
5. **Step 5 (pre-flight):** `bruja info --remote` calls `Acervo.fetchManifest(...)` via the free dispatcher introduced in Sortie 2 instead of `BrujaDownloadManager.estimatedSize`. Exit shape unchanged.

---

## Open Questions & Missing Documentation

All open questions raised during refinement are resolved in the **Decisions Locked** table above. No items require manual review before execution.

| Sortie | Issue Type | Description | Resolution |
|--------|-----------|-------------|------------|
| S5 | Open question | Option A vs Option B for `--json` banner suppression | Auto-resolved as OQ-4: Option A (stderr unconditional). |
| S4 | Vague criterion | "excluding pre-existing environmental failures inherited from LIGHTHOUSE" | Auto-resolved as OQ-5: failing test names must be enumerated; no hand-waving. |
| S2 | Vague phrasing | "suggested file: ManifestDispatcher.swift" | Auto-resolved: definitive exact path locked in OQ-2 and Task 1. |
| S3 | Open-ended scope | "any other library entry points" | Auto-resolved: Task 4 made grep-driven with refine-time known references pinned (`BrujaModelManager.swift:25,77`). |
| S5 | Imprecise locator | "likely Sources/SwiftBruja/Core/BrujaModelManager.swift or BrujaQuery.swift" | Auto-resolved: pinned at refine time to `Sources/SwiftBruja/Core/BrujaQuery.swift:56`. |

---

## Summary

| Metric | Value |
|--------|-------|
| Work units | 1 |
| Total sorties | 6 (5 mandatory + 1 optional) |
| Dependency structure | S1 → S2 → S3 → {S4 ∥ S6}; S5 optional, after S3 |
| Critical path length | 4 sorties (5 with optional S5) |
| Max concurrency | 2 (1 supervising + 1 sub-agent during Group 4) |
| Sub-agent-eligible sorties | S6 only (docs grep, no build) |
| SemVer impact | MAJOR — `BrujaDownloadManager` public API removed |
