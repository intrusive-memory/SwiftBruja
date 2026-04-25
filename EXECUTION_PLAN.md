---
feature_name: OPERATION LIGHTHOUSE PLUMBING
starting_point_commit: cee9757a48b259fbaa6b6da66ac606e23756f094
mission_branch: mission/lighthouse-plumbing/01
iteration: 1
mission_started: 2026-04-25
---

# EXECUTION_PLAN.md — SwiftBruja Reference Implementation for SwiftAcervo 0.8

**Source:** `REQUIREMENTS.md` v2.0 (2026-04-24, updated 2026-04-25)
**SwiftAcervo version:** `≥ 0.8.1` (0.8.1 ships the `ACERVO_OFFLINE` gate required by Sortie 8)
**Canonical reference:** `../SwiftAcervo/USAGE.md`
**Refined:** 2026-04-24 (initial 4 passes); 2026-04-25 (re-refined post-OQ-3 resolution; OQ-7 collapsed under assumption that SwiftAcervo 0.8.1 ships the offline gate)

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

## Mission Overview

Close the gap between SwiftBruja's current code and the behavior `USAGE.md` advertises for the canonical reference consumer of SwiftAcervo 0.8. Eight requirements (R1–R8) detected; R1–R6 are in-scope for this mission, R7 is optional, R8 is deferred (explicitly "do not build until a caller exists").

### Non-Goals (from requirements, do NOT do)

- Do NOT pin file subsets (`files: [concrete list]`) — `USAGE.md` forbids
- Do NOT add custom retry loops — Acervo already resumes partial downloads
- Do NOT add `withLocalAccess` / LoRA flows — no caller exists
- Do NOT remove `BrujaDownloadManager.downloadModel` (Level 2 raw-repo path)
- Do NOT re-bake SHA-256 checksums into `BrujaComponents.swift`

---

## Shared Fixtures

> **Purpose**: Canonical model IDs referenced by multiple sorties. Sortie 1 validates all of these exist on the ACERVO CDN and ships them via `acervo` if missing.

| Fixture | Purpose | Canonical ID | Source |
|---------|---------|-------------|--------|
| `BRUJA_PRODUCTION_MODEL` | The registered Bruja component (sole entry in `BrujaComponents.swift`) | `mlx-community/Qwen3-Coder-Next-4bit` | `Sources/SwiftBruja/Core/BrujaComponents.swift` `qwen3CoderNext4bitDescriptor` |
| `SMALL_FIXTURE_MODEL` | Smoke-test download target for R3 tests and `make reference-check` step 2/3 (< 2 GB for CI budget) | `mlx-community/Qwen2.5-0.5B-Instruct-4bit` | Defined here; Sortie 1 verifies CDN availability and ships if missing |
| `MISSING_MODEL_ID` | R2 canonical error-mapping target (MUST NOT exist on CDN) | `mlx-community/does-not-exist` | Defined here |

All sorties that reference `<small-fixture-model>` MUST resolve to `SMALL_FIXTURE_MODEL` above. If either production or fixture ID changes, update this table, Sortie 1's manifest, and the R2/R3/reference-check tests in lockstep.

---

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| SwiftBruja | `.` | 9 | 0–2 | none |

Single project; all work lands on the current branch (`development`) via Makefile-driven build/test (`make build`, `make test`).

---

## Sortie 1: CDN availability validation & shipping (pre-flight infrastructure)

**Priority**: 20 — Pre-flight infrastructure; dep-depth 1 (blocks Sortie 8 `make reference-check`); foundation 1 (establishes CDN coverage for the mission); moderate risk (external CDN + `acervo` CLI). Runs BEFORE any CI tests that expect models on the CDN.
**Agent**: supervising agent (runs `acervo` CLI + may trigger uploads).
**Layer**: 0 (parallel-eligible with Sorties 2–6). **Must complete before Sortie 8 dispatches.**

**Entry criteria**:
- [ ] `acervo` CLI is installed and authenticated (Cloudflare R2 credentials present in env — see `../ACERVO_CDN_UPLOAD_PATTERN.md` § GitHub Organization Secrets for variable names).
- [ ] Read `Sources/SwiftBruja/Core/BrujaComponents.swift` to enumerate registered descriptors (currently: `qwen3-coder-next-4bit` / `mlx-community/Qwen3-Coder-Next-4bit`).

**Tasks**:
1. **Build the required-models list** from two sources:
   - Every `repoId` in `BrujaComponents.swift` descriptors (production models the library registers).
   - Every fixture ID in the Shared Fixtures table above except `MISSING_MODEL_ID` (which is intentionally absent).
   Current list: `mlx-community/Qwen3-Coder-Next-4bit`, `mlx-community/Qwen2.5-0.5B-Instruct-4bit`.
2. For each required model, call `Acervo.fetchManifest(for: slug)` from a one-off Swift snippet (or `acervo manifest check <slug>` if the CLI exposes it) to verify the CDN has a valid manifest. Use `CDNManifest`'s `.files: [CDNManifestFile]` to confirm the file list is non-empty.
3. If a manifest is **missing or invalid**, ship the model to the CDN using `acervo ship <slug>` (or `acervo upload` per `../ACERVO_CDN_UPLOAD_PATTERN.md`). Capture the upload log.
4. Re-verify each model's manifest after shipping; the sortie is not done until every required slug returns a valid non-empty manifest.
5. Produce a coverage report at `.mission/cdn-coverage.md` listing, for each slug: initial state (present/missing), action taken (none/shipped), final manifest file count, and total size bytes. This file is consumed by Sortie 8's reference-check entry criterion and is git-ignored (add `.mission/` to `.gitignore` if not present).
6. Do NOT register `MISSING_MODEL_ID` or attempt to ship it — Sortie 3 (R2) relies on its absence.

**Exit criteria**:
- [ ] `.mission/cdn-coverage.md` exists and contains one row per required slug, each with `final_state = present` and `files > 0`.
- [ ] For every slug in the Shared Fixtures table (except `MISSING_MODEL_ID`): a Swift snippet calling `try await Acervo.fetchManifest(for: slug)` completes without throwing, and `manifest.files.isEmpty == false`.
- [ ] `acervo` CLI exits 0 for a verification invocation against each slug (whatever form — `acervo manifest`, `acervo verify`, or equivalent — the agent MUST pick one consistent verb and document it in the coverage report).
- [ ] `grep -q '^.mission/' .gitignore` passes.
- [ ] No commits touching `Sources/` or `Tests/` from this sortie (this is infra-only).

---

## Sortie 2: ProgressRenderer helper (R3)

**Priority**: 22.5 — R3 High; dep-depth 3 (blocks Sorties 7, 8, 9 via Sortie 7); foundation score 1 (helper reused by R5); concurrency + TTY risk.
**Agent**: supervising agent (has `make build`).
**Layer**: 0.

**Entry criteria**:
- [ ] No prerequisites — runs in parallel with Sorties 1, 3, 4, 5, 6

**Tasks**:
1. Create `Sources/bruja/ProgressRenderer.swift` with a `ProgressRenderer` type that detects `isatty(fileno(stdout)) != 0` once at construction.
2. Implement TTY rendering path: preserve current `\r\u{1B}[K` redraw behavior from `DownloadCommand.run`.
3. Implement non-TTY rendering path: emit one `Download progress: N%` line per 10-percent increment (`0%, 10%, …, 100%`), newline-terminated, no ANSI escapes.
4. Honor `--quiet` by short-circuiting both paths.
5. Make the type Sendable-safe for `@Sendable` download callbacks — either declare it as an `actor`, or use `nonisolated(unsafe)` last-percent cache guarded by `OSAllocatedUnfairLock`.
6. Expose a `logStartup(_ message: String)` (or similarly named) method that writes to **stderr** honoring `--quiet`, so Sortie 7 (R5) can reuse this renderer for the `[bruja] SharedModels:` line.
7. Refactor `DownloadCommand.run` in `Sources/bruja/BrujaCLI.swift` to delegate progress output to the new renderer.
8. Add unit/integration tests covering TTY redraw, non-TTY line-oriented output, and `--quiet` suppression.

**Exit criteria**:
- [ ] `Sources/bruja/ProgressRenderer.swift` exists and compiles.
- [ ] `make build` succeeds.
- [ ] Test: `bruja download -m $SMALL_FIXTURE_MODEL > /tmp/log.txt` produces ≤ 11 lines and `! grep -q $'\x1b' /tmp/log.txt` passes (no ANSI bytes).
- [ ] Test: `bruja download -m $SMALL_FIXTURE_MODEL --quiet > /tmp/log.txt` produces zero progress lines.
- [ ] `ProgressRenderer` exposes a public stderr-logging method (for R5 reuse); signature committed to source.
- [ ] `make test` passes.

---

## Sortie 3: ErrorReporting helper (R2)

**Priority**: 7.875 — R2 High; dep-depth 0; foundation score 1 (CLI-wide pattern); moderate risk (exhaustive enum).
**Agent**: supervising agent (has `make build`).
**Layer**: 0 (parallel-eligible with Sorties 1, 2, 4, 5, 6).

**Entry criteria**:
- [ ] No prerequisites — runs in parallel with Sorties 1, 2, 4, 5, 6

**Tasks**:
1. Create `Sources/bruja/ErrorReporting.swift` with `CLIError: Error, CustomStringConvertible` and a generic `runCLI<T>(_ body: () async throws -> T) async throws -> T` wrapper.
2. Implement `humanReadable(_ error: AcervoError) -> String` with a branch for every currently-shipping `AcervoError` case: `.modelNotFound`, `.manifestDownloadFailed`, `.manifestIntegrityFailed`, `.downloadFailed`, `.integrityCheckFailed`, `.downloadSizeMismatch`, `.fileNotInManifest`, `.componentNotRegistered`, plus `@unknown default`.
3. Wrap every subcommand body in `Sources/bruja/BrujaCLI.swift` (`DownloadCommand`, `InfoCommand`, `ListCommand`, `QueryCommand`, `ChatCommand`, and any others) with `try await runCLI { ... }`.
4. Add a smoke test asserting `bruja download -m mlx-community/does-not-exist` exits non-zero and stderr matches `Error: Model 'mlx-community/does-not-exist' is not published on the CDN.` verbatim.

**Exit criteria**:
- [ ] `Sources/bruja/ErrorReporting.swift` exists and compiles.
- [ ] `make build` succeeds.
- [ ] `grep -c 'try await runCLI' Sources/bruja/BrujaCLI.swift` returns at least 5 (one per subcommand).
- [ ] Smoke test for unknown model produces the canonical R2 message verbatim and exits non-zero.
- [ ] `make test` passes.

---

## Sortie 4: Level 3 delegation in `ensureComponentReady` (R1)

**Priority**: 4.5 — R1 High; dep-depth 0; foundation 0; moderate risk (file I/O + Acervo API).
**Agent**: supervising agent (has `make build`).
**Layer**: 0 (parallel-eligible with Sorties 1, 2, 3, 5, 6).

**Entry criteria**:
- [ ] No prerequisites — runs in parallel with Sorties 1, 2, 3, 5, 6

**Tasks**:
1. In `Sources/SwiftBruja/Core/BrujaDownloadManager.swift`, replace the `Acervo.ensureAvailable(modelId, files: [])` call inside `ensureComponentReady(_:force:progress:)` with `try await Acervo.ensureComponentReady(componentId) { acervoProgress in progress?(acervoProgress.overallProgress) }` followed by `return try Acervo.modelDirectory(for: component.repoId)`.
2. Preserve the `force` branch (`Acervo.deleteModel(component.repoId)` before the ensure call) and the component-registration guard (`BrujaModelManager.component(for: componentId) == nil` → `BrujaError.modelNotFound`).
3. Do NOT modify `downloadModel(_:force:progress:)` — the raw-repoId Level 2 path must keep working for unregistered repo IDs.
4. Add a unit test: register a bare `ComponentDescriptor` (no `files:`), call `BrujaDownloadManager.shared.ensureComponentReady(id)` against a fixture manifest, assert `Acervo.component(id)?.files.isEmpty == false` after the call.
5. Add/verify a regression test confirming `bruja download -m mlx-community/<repo>` still works against an unregistered repo ID (Level 2 path).

**Exit criteria**:
- [ ] `grep -q 'Acervo.ensureComponentReady' Sources/SwiftBruja/Core/BrujaDownloadManager.swift` passes.
- [ ] `! grep -q 'Acervo.ensureAvailable' Sources/SwiftBruja/Core/BrujaDownloadManager.swift` passes (old call removed).
- [ ] `git diff Sources/SwiftBruja/Core/BrujaDownloadManager.swift` shows NO changes to `downloadModel(_:force:progress:)` body.
- [ ] New hydration test passes (named e.g. `testEnsureComponentReadyHydratesFiles`).
- [ ] Existing Level 2 CLI test passes.
- [ ] `make build` and `make test` pass.

---

## Sortie 5: Pre-flight manifest API (R4)

**Priority**: 4.5 — R4 Medium; dep-depth 0; foundation 0; highest risk (new public API + external manifest fetch).
**Agent**: supervising agent (has `make build`).
**Layer**: 0 (parallel-eligible with Sorties 1, 2, 3, 4, 6).

**Entry criteria**:
- [ ] No prerequisites — runs in parallel with Sorties 1, 2, 3, 4, 6

**Tasks**:
1. Add `public nonisolated func estimatedSize(for modelOrComponentId: String) async throws -> Int64` to `BrujaDownloadManager`, implemented as `manifestFiles(for:).reduce(0) { $0 + $1.sizeBytes }`.
2. Add `public nonisolated func manifestFiles(for modelOrComponentId: String) async throws -> [CDNManifestFile]` that dispatches to `Acervo.fetchManifest(forComponent:)` for registered components and `Acervo.fetchManifest(for:)` for raw IDs, selected via `BrujaModelManager.component(for:) != nil`. Both call sites return `CDNManifest`; map `.files` through. (SwiftAcervo 0.8 uses `CDNManifest` / `CDNManifestFile` as the public types — confirmed in `../SwiftAcervo/Sources/SwiftAcervo/CDNManifest.swift`.)
3. Extend `InfoCommand` in `Sources/bruja/BrujaCLI.swift` with a `--remote` flag.
4. When `--remote` is set, call `estimatedSize` and `manifestFiles` (NOT `Acervo.modelInfo`) and print `Remote: <modelId>` / `Files: <N>` / `Size: <formatted bytes>`. Without `--remote`, behavior is unchanged.
5. Add a library test: `estimatedSize(for:)` returns a non-zero value for `$BRUJA_PRODUCTION_MODEL` (guaranteed on CDN by Sortie 1) and produces no files on disk under `Acervo.sharedModelsDirectory`.
6. Add an integration test: `bruja info -m $SMALL_FIXTURE_MODEL --remote` succeeds on a machine where the model is not downloaded and creates no files under `Acervo.sharedModelsDirectory`.

**Exit criteria**:
- [ ] `estimatedSize(for:)` and `manifestFiles(for:)` compile and are declared `public nonisolated`.
- [ ] `grep -q 'struct InfoCommand' Sources/bruja/BrujaCLI.swift` confirms `--remote` flag is wired (via `@Flag`).
- [ ] `bruja info -m $SMALL_FIXTURE_MODEL --remote` prints the three-line format: `Remote: ...`, `Files: <N>`, `Size: <bytes>`.
- [ ] Library and integration tests both pass with zero new files created under `Acervo.sharedModelsDirectory` (verified via `find` before/after snapshot).
- [ ] `make build` and `make test` pass.

---

## Sortie 6: `withModelAccess` wrapping `loadContainer` (R7)

**Priority**: 1.375 — R7 Low (explicitly optional in REQUIREMENTS.md); dep-depth 0; foundation 0; moderate risk (concurrency).
**Agent**: supervising agent (has `make build`).
**Layer**: 0 (parallel-eligible with Sorties 1, 2, 3, 4, 5). **Optional** — mission may ship without this sortie; dispatch last within Layer 0.

**Entry criteria**:
- [ ] No prerequisites — runs in parallel with Sorties 1, 2, 3, 4, 5

**Tasks**:
1. In `Sources/SwiftBruja/Core/BrujaModelManager.swift`, replace the direct `Acervo.modelDirectory(for:)` + `LLMModelFactory.shared.loadContainer(from:)` sequence inside `loadModel(_:)` with `let container = try await AcervoManager.shared.withModelAccess(modelId) { dir in try await LLMModelFactory.shared.loadContainer(from: dir) }`.
2. Keep `BrujaMemory.validateMemoryForModel` outside the closure — it uses the size from `Acervo.modelInfo` and does not need the URL.
3. Add a concurrent test: `loadModel` + `deleteModel` of the same ID must serialize (one waits on the other) rather than race.

**Exit criteria**:
- [ ] `! grep -q 'Acervo.modelDirectory(for:' Sources/SwiftBruja/Core/BrujaModelManager.swift` inside the `loadModel` function body (verify with focused grep or AST check).
- [ ] `grep -q 'AcervoManager.shared.withModelAccess' Sources/SwiftBruja/Core/BrujaModelManager.swift` passes.
- [ ] Existing query/chat tests pass unchanged.
- [ ] New concurrent `loadModel`+`deleteModel` test passes (named e.g. `testLoadAndDeleteSerialized`).
- [ ] `make build` and `make test` pass.

---

## Sortie 7: SharedModels stderr logging across all CLI subcommands (R5)

**Priority**: 8 — R5 Medium; dep-depth 2 (blocks Sorties 8 and 9); foundation 0; low risk.
**Agent**: supervising agent (has `make build`).
**Layer**: 1 (depends on Sortie 2).

**Entry criteria**:
- [ ] Sortie 2 complete — `ProgressRenderer` exposes a public stderr-logging method that honors `--quiet`

**Tasks**:
1. Before the first line of user-facing output in every subcommand (`DownloadCommand`, `InfoCommand`, `ListCommand`, `QueryCommand`, `ChatCommand`), emit `[bruja] SharedModels: <Acervo.sharedModelsDirectory.path>` to **stderr** (never stdout, to keep `--json` parseable).
2. Route the stderr line through the `ProgressRenderer` stderr-logging method from Sortie 2 so `--quiet` suppresses it uniformly.
3. Add a test: `bruja query "hi" --json 2>/dev/null | jq .` exits 0 (still parses as JSON).
4. Add a test: `bruja query "hi" 2>&1 >/dev/null | grep -q '\[bruja\] SharedModels:'` exits 0 on a default install.
5. Add a test: `bruja query "hi" --quiet 2>&1 >/dev/null | grep -q '\[bruja\] SharedModels:'` exits NON-zero (no match).

**Exit criteria**:
- [ ] Every subcommand `run()` in `BrujaCLI.swift` invokes the ProgressRenderer stderr-logging method before any stdout output (verified: `grep -c 'logStartup\|logSharedModels' Sources/bruja/BrujaCLI.swift` ≥ 5).
- [ ] `--json` output on stdout remains machine-parseable (`bruja query "hi" --json 2>/dev/null | jq .` exits 0).
- [ ] All three R5 grep tests behave as specified above.
- [ ] `make build` and `make test` pass.

---

## Sortie 8: `make reference-check` verification target

**Priority**: 3 — infra; dep-depth 0; foundation 0; moderate risk (composes R1–R5 tests).
**Agent**: supervising agent (has `make build`).
**Layer**: 2 (depends on Sorties 1 and 7; transitively 2–5).

**Entry criteria**:
- [ ] Sorties 2, 3, 4, 5, 7 complete (target composes tests created by R1–R5)
- [ ] Sortie 1 complete — `.mission/cdn-coverage.md` confirms `$SMALL_FIXTURE_MODEL` is on the CDN
- [ ] `Package.swift` pins SwiftAcervo at `≥ 0.8.1` and `make build` resolves the dependency cleanly. Verifiable via `grep -E '"0\\.8\\.1"|from: "0\\.8\\.1"' Package.swift` plus `make build` exit 0. (0.8.1 is the version that ships the `ACERVO_OFFLINE` env-var gate.)

**Tasks**:
1. Add a `reference-check` target to the `Makefile` that sequences the five verification steps in order and fails fast on the first non-zero exit.
2. Step 1: run the existing unit + integration suite via the project's existing `make test` entry point (reuse, do not duplicate).
3. Step 2: offline-load test — first invocation `bruja download -m $SMALL_FIXTURE_MODEL` (network on); second invocation `ACERVO_OFFLINE=1 bruja query "hi" -m $SMALL_FIXTURE_MODEL` and assert exit 0. Per REQUIREMENTS.md §"Offline-Mode Contract" (honored by SwiftAcervo ≥ 0.8.1), `ACERVO_OFFLINE=1` makes SwiftAcervo refuse new HTTP fetches and serve only from `sharedModelsDirectory`; the cached query path must succeed, and any regression that reintroduces a fetch in the query path will surface as a non-zero exit.
4. Step 3: TTY guard test — run `script -q /dev/null bruja download -m $SMALL_FIXTURE_MODEL` (TTY path) and `bruja download -m $SMALL_FIXTURE_MODEL > log.txt` (non-TTY path); assert the output shapes specified in R3 (≤11 lines on redirect, no `0x1B` bytes on redirect, redraw on TTY).
5. Step 4: error-mapping smoke test — `bruja download -m mlx-community/__nope__` exits non-zero and stderr matches the exact R2 canonical message.
6. Step 5: pre-flight smoke test — `bruja info -m <undownloaded-fixture> --remote` prints a non-zero size and produces no new files under `Acervo.sharedModelsDirectory`.

**Exit criteria**:
- [ ] `grep -q '^reference-check:' Makefile` passes.
- [ ] `make help` lists `reference-check` (or `grep -q 'reference-check' Makefile` in the help block).
- [ ] All five verification steps invoke commands traceable to `REQUIREMENTS.md` §"Verification Plan".
- [ ] `make reference-check` exits 0 on a clean checkout with all preceding sorties complete.

---

## Sortie 9: App Group documentation (R6)

**Priority**: 1.75 — R6 Medium; dep-depth 0; foundation 0; docs only.
**Agent**: **sub-agent eligible** (no build step — the only pure-docs sortie in the plan).
**Layer**: 2 (depends on Sortie 7).

**Entry criteria**:
- [ ] Sortie 7 complete — the self-diagnostic stderr line exists and can be referenced

**Tasks**:
1. Add an `## App Group Entitlement` section to `README.md` naming `group.intrusive-memory.models` verbatim and linking to `../SwiftAcervo/USAGE.md` (or the canonical upstream URL) for the full integration checklist.
2. Document the Xcode capability steps ("Signing & Capabilities → + Capability → App Groups → add `group.intrusive-memory.models`") and provide an equivalent `.entitlements` snippet.
3. Reference the R5 stderr line as the self-diagnostic: "If `[bruja] SharedModels:` shows a path under `Application Support/SwiftAcervo/SharedModels`, the capability is missing from the host target."
4. Call out that the `bruja` CLI binary itself is unsigned and legitimately uses the fallback path — not a bug.
5. Add a one-liner to `AGENTS.md` pointing future agents at the new README section.

**Exit criteria**:
- [ ] `grep -F 'group.intrusive-memory.models' README.md` matches.
- [ ] `README.md` contains a link to `USAGE.md` (or canonical upstream URL) in the new section (`grep -F 'USAGE.md' README.md` matches in App Group section).
- [ ] `grep -F '[bruja] SharedModels:' README.md` matches (self-diagnostic reference).
- [ ] `grep -F 'unsigned' README.md` matches in App Group section (unsigned-CLI-binary note).
- [ ] `grep -F 'App Group' AGENTS.md` matches (cross-reference).

---

## Parallelism Structure

**Critical Path**: Sortie 2 → Sortie 7 → Sortie 8 (length: 3 sorties). Sortie 2 → Sortie 7 → Sortie 9 is an alternate path of equal length. Sortie 1 (CDN validation) must complete before Sortie 8 but runs parallel with Sorties 2–6.

**Parallel Execution Groups**:

- **Group 1 — Layer 0 (all parallel-eligible)**:
  - Sortie 1 (CDN validation & shipping) — **SUPERVISING AGENT ONLY** (runs `acervo` CLI + uploads; gates Sortie 8)
  - Sortie 2 (R3 ProgressRenderer) — **SUPERVISING AGENT ONLY** (build step; foundational for Sortie 7)
  - Sortie 3 (R2 ErrorReporting) — **SUPERVISING AGENT ONLY** (build step)
  - Sortie 4 (R1 Level 3 delegation) — **SUPERVISING AGENT ONLY** (build step)
  - Sortie 5 (R4 pre-flight manifest) — **SUPERVISING AGENT ONLY** (build step)
  - Sortie 6 (R7 withModelAccess, optional) — **SUPERVISING AGENT ONLY** (build step)

- **Group 2 — Layer 1 (depends on Sortie 2)**:
  - Sortie 7 (R5 SharedModels logging) — **SUPERVISING AGENT ONLY** (build step)

- **Group 3 — Layer 2 (depends on Sortie 7; Sortie 8 also depends on Sortie 1)**:
  - Sortie 8 (`make reference-check`) — **SUPERVISING AGENT ONLY** (build step; composes R1–R5 tests; needs CDN coverage from Sortie 1)
  - Sortie 9 (R6 App Group docs) — **SUB-AGENT ELIGIBLE** (no build; README + AGENTS.md only)

**Agent Constraints**:

- **Supervising agent**: 8 of 9 sorties (7 with `make build`; Sortie 1 runs `acervo` CLI / uploads).
- **Sub-agents**: 1 of 9 sorties eligible (Sortie 9, pure docs). Sub-agent budget (4 max) is under-utilized because this plan is build-heavy by nature; this is expected for a Swift refactor mission.
- **Practical parallelism**: Group 1 can dispatch 6 agents concurrently, but their `make build` / `acervo` calls serialize through the supervising agent for verification. Real wall-clock speedup comes from: (a) dispatching Sortie 9 as a sub-agent in parallel with Sortie 8, and (b) dispatching Layer 0 sorties to separate agent contexts even if their builds serialize.

**Missed Opportunities**: None — all parallelism the dependency graph admits has been surfaced. The build-heavy nature is a hard constraint of Swift/Makefile projects.

---

## Open Questions & Missing Documentation

Pass 4 surfaced 6 issues across two refinement rounds (2026-04-24 initial, 2026-04-25 re-refine). **All blocking issues resolved.** OQ-3 closed via REQUIREMENTS.md §"Offline-Mode Contract" (option b: `ACERVO_OFFLINE=1` env var honored by SwiftAcervo). OQ-7 collapsed: per user assumption (2026-04-25), SwiftAcervo 0.8.1 will ship the offline gate before Sortie 8 dispatches, so the `xfail` hedge is removed and Sortie 8 simply requires the 0.8.1 pin.

| # | Sortie | Issue Type | Description | Resolution | Status |
|---|--------|-----------|-------------|------------|--------|
| OQ-1 | 1, 2, 8 | Vague reference | `<small-fixture-model>` used in R3 tests and `make reference-check` step 2/3 without a concrete ID. | **Resolved** by Sortie 1 (new pre-flight): `SMALL_FIXTURE_MODEL = mlx-community/Qwen2.5-0.5B-Instruct-4bit` is defined in Shared Fixtures table; Sortie 1 validates its CDN presence and ships it via `acervo` if missing. No separate user action required — CDN coverage is now a sortie deliverable. | **RESOLVED** |
| OQ-2 | 5 | Open question | Sortie 5 tasks referenced `[AcervoManifestFile]` — "confirm the concrete type name from SwiftAcervo 0.8". | **Resolved**: SwiftAcervo 0.8 uses `CDNManifest` / `CDNManifestFile` (verified in `../SwiftAcervo/Sources/SwiftAcervo/CDNManifest.swift:59`). Substituted in Sortie 5 Task 2. | **RESOLVED** |
| OQ-3 | 8 | Missing doc / vague | `make reference-check` step 2 references an "existing offline harness" — no such harness is documented in the repo. | **Resolved (2026-04-25, user)**: option (b) chosen. SwiftAcervo `ACERVO_OFFLINE=1` env var refuses outbound HTTP and serves from `sharedModelsDirectory`. Codified in REQUIREMENTS.md §"Offline-Mode Contract" and Sortie 8 Task 3. Cross-repo dep tracked as OQ-7. | **RESOLVED** |
| OQ-4 | 2 | Auto-fixable | Original plan left the ProgressRenderer's reuse pattern for R5 implicit. | **Auto-fixed**: Sortie 2 now explicitly requires a public stderr-logging method (Task 6, new Exit criterion); Sortie 7 (R5) now requires routing through it (Task 2). | **RESOLVED** |
| OQ-5 | — | External dependency check | Plan relies on `SwiftAcervo 0.8` public API surface. | Non-blocking if user confirms SwiftAcervo 0.8 is actually pinned in `Package.swift` (currently modified per `git status` — note at start of this file). Supervisor to verify during Startup Protocol. | **ADVISORY** |
| OQ-6 | 1 | External dependency check | Sortie 1 requires `acervo` CLI with Cloudflare R2 credentials. | Entry criterion added to Sortie 1. If `acervo ship` needs credentials not present in current env, Sortie 1 will fail and need user intervention before retry. | **ADVISORY** |
| OQ-7 | 8 | Cross-repo dependency | OQ-3's resolution depends on SwiftAcervo honoring `ACERVO_OFFLINE=1`. SwiftBruja does not implement the gate. | **Resolved (2026-04-25, user assumption)**: SwiftAcervo 0.8.1 ships the offline gate. SwiftBruja's responsibility is reduced to (a) bumping `Package.swift` to pin `≥ 0.8.1` before Sortie 8 dispatches, (b) setting the env var in `make reference-check` step 2. Sortie 8's `xfail` hedge is removed; entry criterion now requires the 0.8.1 pin. The SwiftAcervo PR is in flight at the time of this re-refine; mission start should not block on it but Sortie 8 specifically must wait. | **RESOLVED** |
| OQ-8 | 8 | External dependency check | `Package.swift` must pin SwiftAcervo ≥ 0.8.1 before Sortie 8 dispatches (currently `M Package.swift` per `git status` — pin state unknown). | Entry criterion on Sortie 8 verifies the pin via grep + `make build`. If the SwiftAcervo 0.8.1 release has not landed when Sortie 8 is scheduled, Sortie 8 stays PENDING (not FATAL — deferred-sortie rule applies). User should confirm 0.8.1 is tagged on `../SwiftAcervo` `main` and bump `Package.swift` accordingly before dispatching Sortie 8. | **ADVISORY** |

**BLOCKED**: 0 issues. Plan is ready to execute.

**Auto-fixed / resolved**: 6 issues (OQ-1 absorbed into Sortie 1, OQ-2 resolved via SwiftAcervo source inspection, OQ-3 resolved 2026-04-25 via REQUIREMENTS.md §"Offline-Mode Contract", OQ-4 auto-fixed in Pass 1, OQ-7 collapsed under SwiftAcervo 0.8.1 assumption; OQ-5/OQ-6/OQ-8 advisory only).

---

## Summary

| Metric | Value |
|--------|-------|
| Work units | 1 |
| Total sorties | 9 (8 required, 1 optional [Sortie 6 / R7]) |
| Dependency structure | 3 layers (6 parallel → 1 → 2) |
| Critical path length | 3 sorties |
| In-scope requirements | R1, R2, R3, R4, R5, R6 (High + Medium) + CDN pre-flight infra |
| Optional requirements | R7 (Low, Sortie 6) |
| Deferred requirements | R8 (do not build until a caller exists) |
| Sub-agent eligible | 1 of 9 (Sortie 9, docs only) |
| Blocking open questions | 0 (OQ-3 + OQ-7 resolved 2026-04-25; OQ-8 tracks Package.swift pin as advisory) |

### Dependency graph (post-refine numbering)

```
Layer 0 (parallel):                       Layer 1:                    Layer 2:
  Sortie 1 (CDN validation) ─────────┐                                ┌─► Sortie 8 (make reference-check)
  Sortie 2 (R3 ProgressRenderer) ──► Sortie 7 (R5 SharedModels) ─────┤
  Sortie 3 (R2 ErrorReporting)         ▲                              └─► Sortie 9 (R6 docs)
  Sortie 4 (R1 Level 3)                │
  Sortie 5 (R4 pre-flight)             │
  Sortie 6 (R7 withModelAccess) [opt]  │
                                       │
         Sortie 1 also gates Sortie 8 ─┘  (CDN coverage required for reference-check)
```

### Refinement Pass Results

#### Round 1 — 2026-04-24 (initial)

| Pass | Status | Changes |
|------|--------|---------|
| 1. Atomicity & Testability | PASS | 0 splits, 0 merges on feature sorties; 1 new pre-flight sortie added per user guidance; all sorties right-sized (14–28 estimated turns); exit criteria tightened with grep-based checks |
| 2. Prioritization | PASS | Priority scores added to every sortie; renumbered after inserting Sortie 1 (CDN validation) at Layer 0 head; all cross-references updated |
| 3. Parallelism | PASS | 3 layers identified; 1 sortie marked sub-agent eligible; critical path = 3 sorties |
| 4. Open Questions & Vague Criteria | BLOCKED → PASS (post-OQ-3 resolution) | 7 issues evaluated; OQ-3 resolved on 2026-04-25 via offline-mode env-var contract |

#### Round 2 — 2026-04-25 (re-refine under SwiftAcervo 0.8.1 assumption)

| Pass | Status | Changes |
|------|--------|---------|
| 1. Atomicity & Testability | PASS | No sortie size changes. Sortie 8 added a one-line entry criterion (Package.swift pin check); still right-sized at ~22 estimated turns. |
| 2. Prioritization | PASS | Sortie 8 risk reassessed (xfail hedge removed under 0.8.1 assumption); composite priority unchanged in rank order. No reordering. |
| 3. Parallelism | PASS | No structural change. 3 layers, critical path = 3 sorties (Sortie 2 → Sortie 7 → Sortie 8). |
| 4. Open Questions & Vague Criteria | PASS | OQ-7 collapsed to RESOLVED under user assumption (SwiftAcervo 0.8.1 ships offline gate). OQ-8 added as a new advisory tracking the `Package.swift` pin bump (one-line edit, must precede Sortie 8 dispatch). 0 blocking. |

### Verdict

✓ **Plan is READY to execute.** All blocking open questions resolved across both refinement rounds. `/mission-supervisor start` may proceed.

**Advisory items** (will be verified during Startup Protocol, not blocking):
- OQ-5: Confirm SwiftAcervo is pinned in `Package.swift` at the version specified in this plan's header.
- OQ-6: Confirm `acervo` CLI is installed and R2 credentials are present in env for Sortie 1. If not, Sortie 1 will fail fast and report back.
- OQ-8: Confirm SwiftAcervo 0.8.1 is tagged on `../SwiftAcervo` `main` AND `Package.swift` pins `≥ 0.8.1` before Sortie 8 dispatches. If 0.8.1 has not yet landed when Sortie 8 is scheduled, leave Sortie 8 PENDING (deferred-sortie rule — do NOT escalate to FATAL just because the upstream tag isn't ready). The SwiftAcervo PR is in flight at the time of this re-refine.
