# REQUIREMENTS_NEXT.md — SwiftBruja: Shed the Download Manager Wrapper

**Status:** DRAFT (not yet a mission). To launch: archive current `REQUIREMENTS.md` via `/mission-supervisor brief`, rename this file to `REQUIREMENTS.md`, then `/mission-supervisor breakdown`.

**Source observation:** `BrujaDownloadManager` in `Sources/SwiftBruja/Core/BrujaDownloadManager.swift` is mostly a thin pass-through over `Acervo.*` from SwiftAcervo 0.8. The wrapper is an artifact of the pre-Acervo-0.8 architecture (when SwiftBruja owned model lifecycle). Now that Acervo's component-aware API is the storage authority, the wrapper adds indirection without abstraction. OPERATION LIGHTHOUSE PLUMBING (iteration 1) deepened the artifact by adding `manifestFiles`/`estimatedSize` per the refined plan; this mission reverses that and finishes the deletion.

**Predecessor:** OPERATION LIGHTHOUSE PLUMBING (iteration 1) — codified the *behaviors* (R1 Level-3 delegation, R2 error mapping, R3 ProgressRenderer, R4 pre-flight UX, R5 SharedModels stderr, R6 docs). Those behaviors all survive this refactor — they live in CLI code and `Acervo.ensureComponentReady`, not in `BrujaDownloadManager`.

---

## Mission Overview

Make SwiftBruja a pure consumer of SwiftAcervo's storage. Delete or strip `BrujaDownloadManager`. Migrate every caller (CLI subcommands, tests, host-app entry points) to call `Acervo.*` directly. SwiftBruja's remaining domain is: component registry (`BrujaComponents.swift`), inference orchestration (`BrujaModelManager.loadModel`/`query`/`chat`), memory validation (`BrujaMemory`), and the `bruja` CLI UX.

This is a SemVer-major change to SwiftBruja's library API.

---

## Non-Goals

- Do NOT change SwiftAcervo's public API in this mission. The `force:`-on-`ensureComponentReady` overload (see Filed Upstream below) is a SEPARATE filed issue, not a deliverable here.
- Do NOT touch `BrujaModelManager.loadModel` / inference flow. That's domain code, not storage code.
- Do NOT alter component registration in `BrujaComponents.swift`. Bruja owns the canonical component registry; that's not pass-through.
- Do NOT alter App Group entitlement docs (R6, just landed) — they remain accurate post-refactor.
- Do NOT pin a new SwiftAcervo version unless the upstream `force:` overload lands during the mission window. If it lands, bump and use it.

---

## Filed Upstream (Not Mission Deliverables)

- **SwiftAcervo issue: add `force:` parameter to `ensureComponentReady`** — non-breaking addition. Signature: `public static func ensureComponentReady(_ componentId: String, force: Bool = false, progress: ...) async throws`. When `force: true`, deletes the model first (via existing `Acervo.deleteModel`) before ensuring. Lets Bruja stop owning the delete-then-ensure composite.
- **SwiftAcervo issue: add `async` overload of `withModelAccess`** — already-known gap from LIGHTHOUSE PLUMBING Sortie 6. Signature: `perform: @Sendable (URL) async throws -> T`. Once both upstream items land, R7 (`withModelAccess` wrapping `loadContainer`) becomes a one-line follow-up sortie.

These should be filed as GitHub issues against `intrusive-memory/SwiftAcervo` BEFORE this mission starts; the supervisor's startup protocol can verify the issues exist as advisory-only checks.

---

## Requirements

### R1 — Delete pure pass-through methods on `BrujaDownloadManager` (HIGH)

**Methods to delete:**
- `func listModels() throws -> [AcervoModel]` (line 89)
- `func modelInfo(_ modelId: String) throws -> AcervoModel` (line 94)
- `func deleteModel(_ modelId: String) throws` (line 99)
- `func findModels(matching query: String) throws -> [AcervoModel]` (line 104)
- `func manifestFiles(for modelOrComponentId: String) async throws -> [CDNManifestFile]` (added by S5 of LIGHTHOUSE; deepened the artifact)
- `func estimatedSize(for modelOrComponentId: String) async throws -> Int64` (added by S5 of LIGHTHOUSE)

**Migrate callers** (in `Sources/bruja/BrujaCLI.swift`) to call `Acervo.<same-name>` directly. The componentId→repoId dispatch logic from `manifestFiles(for:)` (registered component → `fetchManifest(forComponent:)`, raw → `fetchManifest(for:)`) moves to a free function or a small extension on `Acervo` (this repo, not upstream) — it's still pure dispatch, not state.

**Verification:**
- `! grep -nE 'BrujaDownloadManager\.shared\.(listModels|modelInfo|deleteModel|findModels|manifestFiles|estimatedSize)' Sources/ Tests/` returns zero matches.
- `make build` and `make test` pass.

### R2 — Strip or delete `downloadModel` and `ensureComponentReady` (HIGH)

Two acceptable shapes — pick one in the breakdown:

**Shape A (delete entirely):** Remove both methods. CLI subcommands call `Acervo.ensureAvailable` (Level 2) and `Acervo.ensureComponentReady` (Level 3) directly. The `--force` composite (`try? Acervo.deleteModel(...)` then ensure) lives at the CLI call site (in `DownloadCommand.run`) — duplicated once across raw/component branches, but explicit.

**Shape B (strip to thin façade):** Keep `BrujaDownloadManager` as a tiny `enum` namespace (or a stateless helper) exposing only:
1. `static func ensure(_ id: String, force: Bool, progress: ...) async throws -> URL` — the composite (`--force` delete + dispatch to component or raw + return URL). One method, well-defined value-add (the composite).
2. Nothing else.

Shape A is simpler and aligns with the user's intent ("let Acervo deal with the details"). Shape B retains a single Bruja-side convenience for the `--force` composite *until* the upstream `force:` parameter lands; once it does, the façade becomes a one-line wrapper and a Shape-A follow-up deletes it.

**Recommendation:** Shape A. The duplication of `try? Acervo.deleteModel(...)` + `try await Acervo.ensureComponentReady(...)` at the call site is honest and SemVer-stable. If/when upstream lands `force:`, the call site collapses to a one-arg call with no Bruja-side change needed.

**Verification:**
- `! grep -q 'class BrujaDownloadManager\|actor BrujaDownloadManager' Sources/SwiftBruja/Core/` (Shape A) OR `BrujaDownloadManager.swift` is ≤ 30 lines (Shape B).
- All `bruja download`, `bruja download --force`, `bruja info --remote`, `bruja query`, `bruja chat`, `bruja list`, `bruja info` invocations exit 0 against the `SMALL_FIXTURE_MODEL` from CDN.

### R3 — Migrate tests to address Acervo directly (MEDIUM)

Tests in `Tests/SwiftBrujaTests/SwiftBrujaTests.swift` that target `BrujaDownloadManager.shared.<method>` migrate to `Acervo.<method>`. This includes the three S4-era tests (`testEnsureComponentReadyHydratesFiles`, `testEnsureComponentReadyThrowsForUnregisteredComponent`, `testDownloadModelLevel2PathWorksForUnregisteredRepoId`) and the two S5-era tests (`testEstimatedSizeForProductionModelIsNonZeroAndCreatesNoFiles`, `testManifestFilesForSmallFixtureModelReturnsNonEmptyArray`).

Tests still owned by Bruja: anything exercising `BrujaModelManager.loadModel`/`query`/`chat`, `BrujaMemory`, `BrujaComponents` registration. These don't move.

**Verification:**
- `! grep -rE 'BrujaDownloadManager\.shared' Tests/` returns zero matches.
- `make test` passes (excluding the same pre-existing environmental failures known from LIGHTHOUSE).

### R4 — Fix LIGHTHOUSE-era regressions in tests (MEDIUM)

LIGHTHOUSE Sortie 8 worked around a real regression by skipping a test in the Makefile. Fix it properly:

- `Tests/BrujaIntegrationTests/ErrorReportingSmokeTest.swift::testDownloadMissingModelExitsNonZeroWithCanonicalMessage`: replace `stderrTrimmed.hasPrefix(Self.expectedStderrPrefix)` (line 84-85) with line-by-line scanning — `XCTAssertTrue(stderr.split(separator: "\n").contains { $0.hasPrefix(Self.expectedStderrPrefix) }, ...)`. Reason: S7 prepended `[bruja] SharedModels:` to stderr, so the canonical R2 message is no longer the first line.
- Remove `-skip-testing:BrujaIntegrationTests/ErrorReportingSmokeTest` from `Makefile` `reference-check` Step 1 (line ~115).
- Re-run `make reference-check` end-to-end without the skip.

**Verification:**
- `! grep -F 'skip-testing:BrujaIntegrationTests/ErrorReportingSmokeTest' Makefile` matches zero.
- `make test` runs `ErrorReportingSmokeTest` and it passes.

### R5 — Suppress library-side stdout banners under `--json` (LOW, OPTIONAL)

LIGHTHOUSE Sortie 7 surfaced a pre-existing pollution: `bruja query "hi" --json` produces a leading `[SwiftBruja] maxTokens set to 4096 for this query` line on stdout, breaking `jq` parseability. Source: SwiftBruja library code (NOT the `[bruja]` CLI prefix).

Find the emit site (likely `BrujaModelManager` or related), route it through stderr OR suppress under `--json`. If the call site needs a flag passed in, plumb a `quiet`/`json` bool to the library API. Optional because it's a pre-existing issue and doesn't block LIGHTHOUSE's deliverables; including here so the next mission ships a clean `--json` story.

**Verification:**
- `bruja query "hi" --json 2>/dev/null | jq .` exits 0 (assumes the model is loadable in the test env).
- `bruja query "hi" 2>/dev/null` (no `--json`) still emits the human-readable banner if applicable — pollution is `--json`-conditional only.

### R6 — Update README + AGENTS.md to reflect simplified surface (LOW)

- Update README to describe SwiftBruja as a "consumer of SwiftAcervo" and remove any references to `BrujaDownloadManager.shared.<method>` from code examples.
- Add a one-line breaking-change note to `AGENTS.md` flagging the SemVer major bump for any agent working on host-app integration.
- App Group section (LIGHTHOUSE Sortie 9) already correct — no changes needed there.

**Verification:**
- `! grep -F 'BrujaDownloadManager.shared' README.md` matches zero.
- `grep -F 'breaking change' AGENTS.md` matches.

---

## Verification Plan (composite — what `make reference-check` should still pass)

The five LIGHTHOUSE reference-check steps remain intact. After this mission:

1. **Step 1 (full suite):** Runs ALL tests including `ErrorReportingSmokeTest` (no `-skip-testing` needed).
2. **Step 2 (offline-load):** Unchanged — `bruja download` then `ACERVO_OFFLINE=1 bruja query`. CLI now calls `Acervo` directly under the hood.
3. **Step 3 (TTY guard):** Unchanged — ProgressRenderer behavior intact (S2 deliverable not touched).
4. **Step 4 (R2 error mapping):** Unchanged — runCLI + humanReadable wrapping intact (S3 deliverable not touched).
5. **Step 5 (pre-flight):** `bruja info --remote` calls `Acervo.fetchManifest(...)` directly via the dispatcher (Acervo extension or free function) instead of `BrujaDownloadManager.estimatedSize`. Exit shape unchanged.

---

## Sortie Suggestions (informational; the breakdown command will refine)

Approximately 4–6 sorties of varying size:

- **S1 (Test fix):** R4 — fix `ErrorReportingSmokeTest` and remove the `-skip-testing` Makefile workaround. Tiny, do first to unbreak the test suite. (haiku-eligible)
- **S2 (Migrate CLI):** R1 + R2 — delete pass-through methods, migrate `BrujaCLI.swift` callers to `Acervo.*`. Medium-sized. (sonnet)
- **S3 (Migrate tests):** R3 — same migration in tests. Could parallel S2. (sonnet)
- **S4 (Library cleanup):** Verify `BrujaDownloadManager` is fully deleted (Shape A) or stripped (Shape B). Likely a one-commit confirmation sortie. (haiku)
- **S5 (Optional --json polish):** R5 — find and silence library banner under `--json`. (sonnet)
- **S6 (Docs):** R6 — README + AGENTS update. (haiku)

Critical path: S1 → S2 → S4. S3 parallelizes with S2 (different files). S5 + S6 finish.

---

## Dependencies

- SwiftAcervo ≥ 0.8.1 (same as LIGHTHOUSE; no upstream version bump required).
- If upstream `force:` overload on `ensureComponentReady` lands during the mission, the breakdown should fold it into R2 (replace per-call-site `try? deleteModel + ensureComponentReady` with `Acervo.ensureComponentReady(id, force: true)`).

---

## Open Questions

- **OQ-1:** Shape A (delete entirely) vs Shape B (thin façade) — recommendation is Shape A; user confirms in breakdown.
- **OQ-2:** Should the `componentId → repoId` dispatcher live as an extension on `Acervo` or as a free function in SwiftBruja? Free function inside SwiftBruja is more SemVer-isolated; extension on `Acervo` requires either a) defining the extension in SwiftBruja (fine, just placement) or b) upstreaming it (out of scope per Non-Goals).
- **OQ-3:** Should we delete `bruja download` as a CLI subcommand entirely, given that its only user-visible job is to materialize a model that any subsequent `bruja query`/`bruja chat` would materialize anyway? (Answer: probably no — `bruja download` is a useful explicit pre-fetch UX. Keeping it is fine. But worth confirming during breakdown.)
