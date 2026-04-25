---
feature_name: OPERATION SNAKESKIN MOLT
mission_branch: mission/snakeskin-molt/01
starting_point_commit: dd32e95b97e50e880d960cb598bd0602d8ef9a4e
iteration: 1
brief_written: 2026-04-25
---

# Iteration 01 Brief — OPERATION SNAKESKIN MOLT

> **Terminology**: A *mission* is the definable scope of work. A *sortie* is an atomic agent task within that mission. A *brief* is the post-mission review that harvests lessons before the next iteration or the merge.

**Mission:** Make SwiftBruja a pure consumer of SwiftAcervo's storage by deleting `BrujaDownloadManager` (Shape A) and migrating all callers to `Acervo.*` directly.
**Branch:** `mission/snakeskin-molt/01`
**Starting Point Commit:** `dd32e95` (`chore(deps): bump SwiftAcervo floor to 0.8.2`)
**Sorties Planned:** 6 (5 mandatory + 1 optional)
**Sorties Completed:** 6 of 6
**Sorties Failed/Blocked:** 0
**Duration:** Single planning/execution session (no retries, no BACKOFF, no FATAL)
**Outcome:** Complete
**Verdict:** Keep the code. Merge `mission/snakeskin-molt/01` → `development` → `main` and tag SwiftBruja `2.0.0` per the SemVer-major impact.

---

## Section 1: Hard Discoveries

### 1. Test target compile graph forces test migration in deletion sorties

**What happened:** S2's plan said "delete the 6 pass-through methods, do NOT touch tests" and exit criterion required `make test` to exit 0. But two tests in `SwiftBrujaTests.swift` (`testEstimatedSizeForProductionModelIsNonZeroAndCreatesNoFiles`, `testManifestFilesForSmallFixtureModelReturnsNonEmptyArray`) directly referenced the deleted symbols. Leaving them un-migrated would break the test target's compile graph, making `make test` fail with NEW failures (compile errors) rather than the pre-existing roster. The S2 agent migrated those two tests to `fetchManifestForBrujaId(_:)` to satisfy the exit criterion. S3 then had to migrate three more (`testEnsureComponentReadyHydratesFiles`, `testEnsureComponentReadyThrowsForUnregisteredComponent`, `testDownloadModelLevel2PathWorksForUnregisteredRepoId`) for the same reason when the actor itself was deleted.
**What was built to handle it:** Both sorties migrated the forced tests in-place using the prescriptions S4 was originally going to apply. By the time S4 ran, all five test migrations were already done — S4 was reduced to renaming test classes (`BrujaDownloadManagerTests` → `AcervoComponentReadyTests`) and trimming one entry from the Makefile skip-list.
**Should we have known this?** Yes. The deletion target and the test references were both static and visible at refine time. A `grep -rn 'BrujaDownloadManager.shared.\(estimatedSize\|manifestFiles\|...\)' Tests/` during refinement would have surfaced this in 30 seconds. The "no test edits in S2/S3" boundary was a clean-separation aesthetic, not a structural reality.
**Carry forward:** When a sortie deletes a public symbol, the same sortie owns migrating every caller of that symbol — including test callers — because the compile graph spans both targets. Authoring a separate "migrate the tests later" sortie creates a forced expansion that the supervisor must accept ad-hoc. Make this explicit in future plans: deletion sorties have authorization to touch tests if and only if the test references the deleted symbol.

### 2. Pre-existing App Group entitlement env failures are stable, not regressions

**What happened:** S1 reported 5 pre-existing test failures with "App Group container permission denied"; S2's verification corrected the count to 7 (InferenceIntegrationTest has 3 sub-tests failing, not 2). All failures are environmental — the test process lacks the App Group entitlement to write to the shared container — not regressions caused by this mission. They pre-date OPERATION SNAKESKIN MOLT and survived intact through it.
**What was built to handle it:** OQ-5 was decided pre-execution: agents must enumerate failing test names with one-line cause attribution; vague "environmental failure" hand-waving is rejected. The Makefile `reference-check` target gates these via `-skip-testing` flags so the composite verification still exits 0. After S4's bonus skip-list trim (un-skipped `testEnsureComponentReadyHydratesFiles` because it now passes post-migration), the skip-list is 5 entries: 4 in `BrujaModelManagerTests/SwiftBrujaTests` + 1 whole class (`BrujaIntegrationTests/InferenceIntegrationTest`).
**Should we have known this?** Partially. LIGHTHOUSE PLUMBING knew about the environmental failures but never enumerated them, so this mission inherited an undocumented baseline. OQ-5's enumeration-or-reject rule is the carry-forward for that gap.
**Carry forward:** The 5 remaining `-skip-testing` entries in the Makefile are technical debt tied to App Group entitlements in the test process. They are not load-bearing on this mission's correctness, but the next mission that touches the test harness or entitlement docs should consider whether these can be unblocked (e.g., by configuring the test scheme's entitlements file).

### 3. CLI was already pre-migrated by LIGHTHOUSE Sortie 4

**What happened:** S3's plan included a Task 2 to inline-replace `BrujaDownloadManager.shared.ensureComponentReady(componentId, ...)` at the CLI component-path call site with the explicit `Acervo.ensureComponentReady` + `Acervo.modelDirectory` composite. When the agent ran the grep, the call was already gone — LIGHTHOUSE PLUMBING Sortie 4 had migrated it during the Level-3 delegation work. S3's component-path inline-replacement was a no-op.
**What was built to handle it:** Nothing. The agent noted the drift in its commit message and proceeded. The actor deletion (Task 3) and doc comment sweep (Task 4) were the actual S3 deliverables.
**Should we have known this?** Yes, by reading the LIGHTHOUSE archive (`docs/complete/lighthouse-plumbing-01-execution-plan.md`) for already-completed work that overlapped this mission's scope. The mission start records that no LIGHTHOUSE brief was generated, only the plan archive — meaning provenance of LIGHTHOUSE deliverables was inferred, not audited.
**Carry forward:** When a successor mission is planned without a predecessor brief, the breakdown step must do a code-state audit (grep for the targets the new mission claims to migrate) instead of trusting the predecessor plan to describe what landed. The plan describes intent; only the code describes reality.

---

## Section 2: Process Discoveries

### What the Agents Did Right

#### 1. Sonnet override on S2 (algorithm wanted opus, supervisor downgraded)

**What happened:** The complexity score for S2 came in at 15, which sits in the opus band (>12). The supervisor overrode to sonnet based on (a) LIGHTHOUSE's empirical baseline (4 code refactor sorties at sonnet, scores 10–12, 0 retries), (b) S2's fully explicit method-list and substitution table (no ambiguity), and (c) the BACKOFF→opus retry path as safety net.
**Right or wrong?** Right. S2 completed clean on first attempt with the only deviation being the compile-graph-forced test edits (Hard Discovery 1). Opus would have been a 3× cost overshoot on a sortie that was structurally low-ambiguity.
**Evidence:** S2 commit `63adecf` — single-pass, no retry, no FATAL. ManifestDispatcher.swift created exactly as locked in OQ-2 (free function, 23 lines).
**Carry forward:** When a sortie's complexity score is inflated by a high foundation_score (many dependents) but the work itself is mechanical (explicit substitution tables, fixed file paths, grep-verifiable exit criteria), the supervisor should downgrade by one band. Reserve opus for genuine ambiguity, not for high-leverage-but-mechanical work.

#### 2. S4 self-extended to bonus skip-list trim

**What happened:** S4's plan was rename-and-grep only (its prescribed test migrations had been pre-empted by S2/S3). The agent noticed that `testEnsureComponentReadyHydratesFiles` — previously skipped via the Makefile because it was failing — now passed post-S3 migration. Without being asked, the agent removed that one entry from the `-skip-testing` list, taking the skip count from 6 → 5.
**Right or wrong?** Right. The trim is a positive net: one more test now runs in `make reference-check`, the change is verifiable in one commit, and there's no scope drift (the skip-list belongs to the same Makefile the sortie was already touching adjacent territory in).
**Evidence:** Commit `5eb21c9`. Skip-list count reduced. `make reference-check` still exits 0.
**Carry forward:** When a sortie is reduced in scope by upstream changes, the agent should be empowered to absorb adjacent low-risk wins it discovers. This is the "right tool for the job, with eyes open" pattern. Note: this only works because S4 was haiku — a sonnet/opus agent would more likely over-extend. Bounded scope + cheap model = honest opportunism.

#### 3. Zero retries across the entire mission

**What happened:** All 6 sorties hit COMPLETED on attempt 1/3. No BACKOFF transitions, no FATAL escalations.
**Right or wrong?** Right — with a caveat. This is partially the result of good planning (explicit exit criteria, grep-verifiable, OQ-5's enumeration rule) and partially the result of a small, well-bounded mission (single work unit, linear chain, deletion-shaped work). Don't read this as "the supervisor methodology is bulletproof"; read it as "small, well-scoped missions with grep-verifiable exits work."
**Evidence:** SUPERVISOR_STATE.md attempt column shows 1/3 across all six rows.
**Carry forward:** The combination that worked here — locked decisions in a "Decisions Locked" table, grep-verifiable exit criteria, enumerated pre-existing failure roster, mechanical substitution tables — is the template for low-risk refactor missions. Replicate.

### What the Agents Did Wrong

Nothing meaningful. No commits were reverted. No files were created and then deleted. No agent over-scoped or over-engineered. The S2/S3 "deviations" were forced by the compile graph, not agent error — that's a planner failure (see below).

### What the Planner Did Wrong

#### 1. Misallocated the test migration work between S2/S3 and S4

**What happened:** The plan allocated all 5 test migrations to S4 ("Migrate tests off `BrujaDownloadManager`"). In execution, the test target's compile graph forced 2 migrations into S2 and 3 into S4's-precursor-S3. By the time S4 ran, the prescribed task was done — S4 became class-renaming + Makefile skip-list maintenance, both haiku-trivial.
**Right or wrong?** Wrong. S4 should have been folded into S6 (both ended up as low-complexity haiku-eligible cleanup), or the plan should have explicitly authorized the necessary test edits in S2/S3. Either way, having a "phantom S4" in the dependency chain added one supervisor turn for a sortie that did almost nothing.
**Evidence:** S4 changeset is 21 lines across 2 files (rename + comment update + 1 Makefile line removed). Sortie type degraded from "code (test migration)" to "code (rename)".
**Carry forward:** During refinement, run a `grep -rn '<symbol-being-deleted>'` for every public symbol slated for deletion and assign every caller's migration to the same sortie that owns the deletion. Don't allocate "migrate the tests" as a separate downstream sortie — Swift's compile graph won't let you defer it.

#### 2. Did not audit predecessor's actual landed code before breakdown

**What happened:** S3's component-path inline-replacement (Task 2) was specified in detail but turned out to be a no-op because LIGHTHOUSE Sortie 4 had already migrated that call site. The plan was written from REQUIREMENTS_NEXT.md and the LIGHTHOUSE plan archive, not from a fresh `grep BrujaDownloadManager Sources/`. (See Hard Discovery 3.)
**Right or wrong?** Wrong, but low-cost. The agent absorbed the no-op and continued. If the same blind spot had aligned with a deleted-but-actually-still-referenced symbol, the verification would have failed instead of becoming a no-op.
**Evidence:** S3 commit `4c84ec2` — only the raw-repoId path required the explicit `if force { try? Acervo.deleteModel(...) }` composite at the call site; the component path was already migrated.
**Carry forward:** Add a "predecessor reality audit" step to `breakdown` when no predecessor brief exists: grep for every symbol the new mission claims to delete or migrate, and pin the *current* set of references in the plan. Treat the predecessor plan as intent, not state.

#### 3. Wave 4 parallelism structure was over-constrained on paper

**What happened:** The plan called for {S4 ∥ S6} parallel and a separate Group 5 for S5 (sequential after S3). The supervisor instead ran {S4 ∥ S5 ∥ S6} all parallel after S3, recorded as a deliberate decision in SUPERVISOR_STATE.md ("S3 stabilized the binary surface so the rationale for sequentialization no longer applied"). This worked — all three completed clean.
**Right or wrong?** Right execution, wrong plan. The plan's Group 5 sequentialization was a hedge against S5's CLI smoke depending on a transitional binary, but S3's exit criterion already required the binary to be stable. Hedging twice for the same property is over-planning.
**Evidence:** Wave 4 ran 3 agents in parallel (S4 + S5 + S6) instead of the planned 2; no conflicts, all clean.
**Carry forward:** Parallelism passes during refinement should look for redundant gating: if exit criteria of the prerequisite already guarantee the property the dependent is waiting on, the dependent doesn't need a separate sequential group.

---

## Section 3: Open Decisions

### 1. SwiftAcervo `force:` upstream parameter — wait or accept?

**Why it matters:** Both `DownloadCommand.run` paths now carry the explicit `if force { try? Acervo.deleteModel(modelId) }` + `try await Acervo.ensureAvailable/ensureComponentReady(...)` composite at the CLI call site. This is honest and SemVer-stable, but if upstream `Acervo.ensureComponentReady(_:force:progress:)` lands, both call sites collapse to one argument.
**Options:**
- **A.** Tag `2.0.0` now, plan a follow-up `2.1.0` micro-mission to collapse the composite when upstream lands.
- **B.** Hold tagging until upstream lands, ship one combined `2.0.0`.
- **C.** Accept the duplication permanently — file the upstream issue as "won't do" and treat the explicit composite as the canonical Bruja-side pattern.
**Recommendation:** A. The composite is correct as-is and the SemVer-major bump (`BrujaDownloadManager` removed) is the actually-breaking change downstream consumers care about. Holding `2.0.0` for an upstream cosmetic improvement compounds risk. Ship.

### 2. Should the App Group entitlement skip-list be tackled?

**Why it matters:** The Makefile `reference-check` target carries 5 `-skip-testing` entries to mask environmental failures (App Group container permission denied in the test process). These are not regressions and are gated behind `reference-check`, but they hide real test coverage. Of the 5: 4 are in `SwiftBrujaTests/BrujaModelManagerTests/SwiftBrujaTests` and 1 is the entire `BrujaIntegrationTests/InferenceIntegrationTest` class.
**Options:**
- **A.** Investigate adding the App Group entitlement to the test target's entitlements file, unskip whatever passes.
- **B.** Convert the affected tests to use a temp-dir mock instead of the real shared container.
- **C.** Leave as-is; document explicitly that these 5 skips are environmental tech debt, not regressions.
**Recommendation:** Defer to a separate mission. Out of scope for SNAKESKIN MOLT, but worth its own mission name. Until then, document option C in `AGENTS.md` so the next mission planner sees the floor.

### 3. Should `bruja download` subcommand be deleted?

**Why it matters:** OQ-3 was decided pre-execution as "Yes, keep" (explicit pre-fetch UX is useful). Mission did not revisit. If post-mission UX testing shows nobody invokes `bruja download` separately from `query`/`chat`, the subcommand becomes dead code.
**Options:**
- **A.** Keep, as decided. Revisit only if usage telemetry contradicts.
- **B.** Mark deprecated in `2.0.0`, remove in `3.0.0`.
**Recommendation:** A. No action needed. Revisit if user feedback after `2.0.0` ship suggests otherwise.

---

## Section 4: Sortie Accuracy

A sortie is *accurate* if its output survived into the final state without rework.

| Sortie | Task | Model | Attempts | Accurate? | Notes |
|--------|------|-------|----------|-----------|-------|
| S1 | Fix `ErrorReportingSmokeTest` regression + remove Makefile skip (R4) | sonnet | 1/3 | Yes | Clean fix; line-by-line stderr scan survived. 5 enumerated env failures accepted per OQ-5. |
| S2 | Delete pass-throughs + create `ManifestDispatcher` (R1) | sonnet (override from opus) | 1/3 | Yes | Plan-spec'd zero test edits but compile graph forced 2 migrations. Migrations match S4's prescription exactly. Sonnet override saved a band. |
| S3 | Delete `BrujaDownloadManager` actor entirely + CLI composite (R2/Shape A) | sonnet | 1/3 | Yes (with no-op task absorbed) | Component-path inline-replacement was a no-op (LIGHTHOUSE S4 had already migrated it). Forced 3 more S4 test migrations. Doc comments + actor deletion clean. |
| S4 | Migrate tests off `BrujaDownloadManager` (R3) | haiku | 1/3 | Partially | Prescribed work pre-empted by S2/S3; sortie reduced to class renames + bonus skip-list trim. Could have been folded into S6 with no loss. |
| S5 | Suppress `[SwiftBruja]` stdout banner under `--json` (R5, optional) | haiku | 1/3 | Yes | One-line replacement at `BrujaQuery.swift:56` exactly per OQ-4 (Option A unconditional stderr). All 3 smoke checks pass. |
| S6 | README + AGENTS.md SemVer-major note (R6) | haiku | 1/3 | Yes | Found README already had no `BrujaDownloadManager.shared` examples; reframed prose, added breaking-change note to AGENTS.md. |

**Aggregate**: 5 of 6 sorties fully accurate. S4 was reduced to scaffolding work because of the planner mistake described in Process Discovery (planner) §1; this is a planning accuracy issue, not an agent accuracy issue.

---

## Section 5: Harvest Summary

What we now know that we didn't before: **deletion-shaped sorties cannot honor a "no test edits" boundary because the test target's compile graph spans the same symbol space as the source target**. Five test migrations the planner allocated to S4 were forced into S2 and S3 by the linker. The next refactor-shaped mission must group every caller of a deleted symbol — production and test — into the deletion sortie, not into a downstream cleanup sortie. The single most important thing that changes: refinement passes must run `grep -rn '<symbol>' Sources/ Tests/` for every deletion target and assign all callers to the same sortie. Otherwise the planner is shipping a dependency the compiler will refuse to honor.

Secondary lesson: when no predecessor brief exists, run a fresh `grep` audit at breakdown time. Don't trust the predecessor's plan to describe what actually landed.

---

## Section 6: Files

**Preserve (read-only reference for next iteration):**

| File | Branch | Why |
|------|--------|-----|
| `OPERATION_SNAKESKIN_MOLT_01_BRIEF.md` (this file, archived to `Docs/complete/snakeskin-molt-01-brief.md`) | `mission/snakeskin-molt/01` and merged forward | Lessons for next refactor mission. Compile-graph rule is reusable. |
| `Docs/complete/lighthouse-plumbing-01-execution-plan.md` | already merged | Predecessor plan; needed if a future mission audits LIGHTHOUSE provenance. |
| `EXECUTION_PLAN.md` (will be archived to `Docs/complete/snakeskin-molt-01-execution-plan.md`) | `mission/snakeskin-molt/01` | Mission-of-record; references the brief's lessons. |
| `REQUIREMENTS_NEXT.md` | `mission/snakeskin-molt/01` | Source document for this mission. Optionally rename to `REQUIREMENTS.md` if the project's pattern requires it; otherwise leave as-is. |

**Discard (will not exist after rollback):**

Not applicable. **The verdict is "keep the code"** — there is no rollback. All files produced by this mission are merged forward.

If the verdict were "discard and iterate" (it is not), the discardable files would be: the new `ManifestDispatcher.swift`, the deletions of `BrujaDownloadManager.swift`, and the test migrations — but again, **none of this is being discarded**. This section is included for completeness only.

---

## Section 7: Iteration Metadata

**Starting point commit:** `dd32e95` (`chore(deps): bump SwiftAcervo floor to 0.8.2`)
**Mission branch:** `mission/snakeskin-molt/01`
**Final commit on mission branch:** `7cc9d8a` (`fix(query): route library-internal maxTokens banner to stderr unconditionally (R5/Option A)`)
**Rollback target:** N/A — verdict is keep the code, merge forward.
**Next iteration branch:** N/A — no iteration 02 planned. The next SwiftBruja mission will start from `main` after `2.0.0` is tagged.

**Recommended next steps for the user (verdict-aligned):**
1. Merge `mission/snakeskin-molt/01` → `development`.
2. Merge `development` → `main` once CI is green.
3. Tag SwiftBruja `2.0.0` (SemVer-major: `BrujaDownloadManager` public API removed).
4. File or revisit upstream SwiftAcervo `force:` parameter issue; plan a `2.1.0` micro-mission to collapse the call-site composite when it lands.
5. Consider a separate mission to address the App Group entitlement skip-list (Open Decision 2).
