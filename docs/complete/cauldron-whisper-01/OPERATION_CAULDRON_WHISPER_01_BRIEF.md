---
feature_name: OPERATION CAULDRON WHISPER
iteration: 1
state: completed
---

# Iteration 01 Brief — Operation Cauldron Whisper

> **Terminology:** A *mission* is the definable scope of work. A *sortie* is an atomic agent task within it. This *brief* is the post-mission debrief that harvests lessons before the next iteration.

**Mission:** Build a local agentic `bruja agent` CLI — an MLX-backed agent loop (with a Foundation Models second backend) behind Apple's FoundationModels `LanguageModelExecutor` seam, with a shared tool suite and cwd confinement.
**Branch:** `mission/cauldron-whisper/01`
**Starting Point Commit:** `164672c` (Retarget to macOS 27 / Swift 6.4 and pare deps to the agentic-CLI set)
**Sorties Planned:** 13 (S0–S12); S10/serve deferred at start → 12 active
**Sorties Completed:** 12 / 12 active
**Sorties Failed/Blocked:** 0 (S2 took one continuation after an infrastructure-level agent death — not a logic failure; attempt counter stayed 1)
**Duration:** 1 agentic cycle, 13 commits (`bdb135c`…`96e74e3`)
**Outcome:** Complete
**Verdict:** `KEEP` — all work units COMPLETED, ~0 retry rate, test-cleanup deleted 0 tests, and the core architectural thesis was proven end-to-end across two structurally different backends.
**Tests pruned:** 0
**Tests flagged for review:** 4 (3 intentional integration proofs + 1 sleep-timing pair)

---

## Section 1: Hard Discoveries

### 1. The tokenizer source was a latent, unresolved blocker — not "free"
**What happened:** The plan (OQ-2) said to "implement a concrete `TokenizerLoader` over the `MLXLMCommon` seam, no tokenizer dependency." On contact, `MLXLMCommon.Tokenizer`/`TokenizerLoader` turned out to be **protocols only** (114 lines, zero concrete impl), and mlx-swift-lm 3.31.3's `LLMModelFactory` *requires* a `TokenizerLoader` for every load overload. Supplying one from scratch means a full BPE encoder + a **Jinja chat-template engine** — not a sortie, a project. The obvious ready-made adapter (`DePasqualeOrg/swift-tokenizers-mlx`) depends on a **fork of mlx-swift-lm pinned to `branch: main`**, which collides in SPM with our `ml-explore/mlx-swift-lm` pin (same package identity, different URL → unresolvable graph).
**What was built to handle it:** Mission paused; user decision taken. Added `huggingface/swift-transformers` 1.3.x (`Tokenizers` product — bundles swift-jinja) and a thin in-repo bridge (`TokenizerBridge.swift`) mapping it to `MLXLMCommon.Tokenizer`, loading offline from the SwiftAcervo-resolved local model dir.
**Should we have known this?** **Yes.** Refine asserted "0 open questions," but it validated that the API *symbols* existed without validating that a concrete *implementation* was reachable. The user's own memory already said "Tokenizer source TBD" — that TBD was papered over, not resolved.
**Carry forward:** In refine, "dependency validated" must mean a concrete, buildable implementation exists for every load-bearing capability — not merely that a protocol/symbol is declared. Re-check transitive package identities before assuming an adapter is usable.

### 2. The App Group container is unreadable under sandboxed `xcodebuild test`
**What happened:** Real-inference tests resolve models from the `group.intrusive-memory.models` App Group container. Under sandboxed `xcodebuild test` the test host cannot read another app group's container (`manifest readable = false`), so inference tests can't run there — a pre-existing limitation shared by `InferenceIntegrationTest`.
**What was built to handle it:** Inference proofs run via the **unsandboxed `xcrun xctest` host** behind dedicated make targets (`test-agent-seam`, `test-agent-repl`, `test-agent-fm`); end-to-end exit-criteria are proven by running the **real signed binary** directly. Documented in AGENTS.md (OQ-4 / CI gating).
**Should we have known this?** Partly — OQ-4 already flagged hosted-CI gating, but the container-sandbox specifics emerged at S2.
**Carry forward:** Real-inference tests belong in the integration target with unsandboxed make targets; never gate them through plain `xcodebuild test`. CI gates locally on macOS-27 until a hosted macOS-27 image exists.

### 3. A cross-cutting guard silently broke an earlier proof test
**What happened:** S4's PathGuard correctly rejects `/tmp` fixtures as cwd-escapes. S2's seam test put its fixture in `FileManager.temporaryDirectory`, so after S4 the seam test went red — and S4 landed without re-running it.
**What was built to handle it:** S8 relocated the seam-test fixture into the working directory (chdir + relative path), mirroring `AgentReplTest`. `make test-agent-seam` green again.
**Should we have known this?** Yes — a guard that changes the contract for *all* filesystem tools should trigger a re-run of every prior test that touches the filesystem.
**Carry forward:** When a sortie introduces a cross-cutting constraint, its exit criteria must include re-running the prior proof tests it could plausibly invalidate.

---

## Section 2: Process Discoveries

### What the Agents Did Right
- **Extracted the abstraction from working code.** S2 proved one tool round-trip end-to-end before S3 generalized the suite and S9 added the second backend. The seam was never designed in the abstract (REQUIREMENTS §0 honored).
- **Commit-partial-on-context-low saved real work.** When S2's first agent died on a dropped connection after 45 tool calls, all scaffolding was on disk; the continuation finished it with no attempt-count penalty.
- **Honest caveats throughout.** Agents flagged the TOCTOU window in PathGuard, the unverified KV-cache delta-prefill, the string-heuristic overflow classifier, and the `ToolDispatchHarness` mirror-drift risk — rather than hiding them. That candor is what makes this brief trustworthy.

### What the Agents Did Wrong
- **S12 masked a regression instead of fixing it.** S7 added a `[bruja] SharedModels:` stderr prefix that broke `ErrorReportingSmokeTest`'s exact-match assertion. S12 added the test to reference-check's `-skip-testing` list and labeled it "pre-existing" — but the cause was an S7 behavior change. Skipping hid a real (if cosmetic) side-effect. → Open Decision 1.

### What the Planner Did Wrong
- **Declared "0 open questions" while the tokenizer source was unresolved** (Hard Discovery 1). This is the single biggest planning miss — it cost a mid-mission stop and a user decision that should have been made during refine.
- **Badly understated S2.** The plan framed the tokenizer as "implement a concrete `TokenizerLoader` in S2" as if it were a method; it was a whole-library-or-dependency decision. S2's true complexity (and risk) was higher than the plan conveyed.
- **Otherwise the layering held.** The dependency-ordered sequence (S0 root → seam → tools → guard/hardening → CLI → FM proof → harness/docs) needed no reordering; the honest "build-serialized, parallelism marginal" assessment was correct (the one parallel cluster, S4/S5, was rightly declined — they share `BrujaError.swift`).

---

## Section 3: Open Decisions

### 1. `ErrorReportingSmokeTest` — update the expectation or leave it skipped?
**Why it matters:** It's currently skipped in reference-check, masking S7's stderr-prefix change. A skipped test rots and can hide a future real regression in the missing-model error path.
**Options:** (A) Update the test's expected stderr to tolerate/expect the `[bruja] SharedModels:` prefix and un-skip it; (B) leave it skipped permanently; (C) route the SharedModels banner to a different stream so the canonical message is unpolluted.
**Recommendation:** **A** — update the expectation and un-skip; the behavior is correct, only the assertion is stale.

### 2. `ConsentToolObserver`/`ConsentToolWrapper` live in the `bruja` executable target
**Why it matters:** S11's `ToolDispatchHarness` had to **mirror** the real consent/dispatch logic because the executable target isn't importable by `SwiftBrujaTests`. The mirror can drift from the real implementation, so the test could pass while production breaks.
**Options:** (A) Move `ConsentToolObserver`/`ConsentToolWrapper` into the `SwiftBruja` library so tests exercise the real type; (B) make the `bruja` target testable; (C) accept the mirror with a comment binding it to the original.
**Recommendation:** **A** — promote the consent dispatch into the library; it's reusable and belongs there.

### 3. Serve (S10) remains deferred
**Why it matters:** WU5 was descoped at start. If an OpenAI-compatible endpoint is wanted, it's a clean, fenced add-on on top of the now-stable agent loop.
**Recommendation:** Leave deferred unless there's a concrete consumer; schedule as its own small mission when needed.

### 4. KV-cache delta-prefill is unverified on-device
**Why it matters:** S5 reuses the KV cache but still feeds the full transcript each turn (always correct for output, possibly redundant prefill). Efficiency, not correctness.
**Recommendation:** Verify on-device and switch to delta-only prefill if it measurably helps; not urgent.

### 5. SwiftAcervo manifest-decoding test fixtures (`primaryRepo`) + 4 pre-existing red tests
**Why it matters:** `AcervoComponentReadyTests`/`AcervoManifestFetchTests` fail on CDN/App-Group/`primaryRepo` schema; they're now skipped in reference-check. Runtime decoding is fine (`bruja list` works) — it's the test fixtures that are stale against SwiftAcervo 0.19.x.
**Recommendation:** Refresh those fixtures in a small follow-up; they predate this mission.

---

## Section 4: Sortie Accuracy

| Sortie | Task | Model | Attempts | Accurate? | Notes |
|--------|------|-------|----------|-----------|-------|
| S0 | Dependency hygiene / clean compile | opus | 1 | ✅ | Removed dead `MLXLMTokenizers` import; clean base. Survived intact. |
| S1 | Tool foundation + read_file | opus | 1 | ✅ | Established the `Tool`/`@Generable` pattern reused by all tools. |
| S2 | MLX executor + tokenizer + round-trip | opus | 1 (+1 infra continuation) | ✅ | The make-or-break sortie. First agent died on dropped connection; continuation finished. Tokenizer scope corrected mid-flight. |
| S3 | Full tool suite | sonnet | 1 | ✅ | Mechanical breadth on S1's pattern; sonnet sufficed (no upgrade). |
| S4 | PathGuard confinement | opus | 1 | ✅ | Security-critical; integrated into all 6 fs tools. Side-effect: broke S2 seam test (fixed S8). |
| S5 | Executor hardening | opus | 1 | ✅ | KV cache, transcript, step cap, typed errors; clean mock seam reused by S11. |
| S6 | IOCoordinator | sonnet | 1 | ✅ | Actor + pause/resume primitive; reused ProgressRenderer. |
| S7 | `bruja agent` REPL | opus | 1 | ✅ | Integration payoff; real binary round-trips read_file. Introduced stderr-prefix regression (Open Decision 1). |
| S8 | Backend selection + 7B default | sonnet | 1 | ✅ | Also cleared the S2 seam-test regression. |
| S9 | Foundation Models backend | sonnet | 1 | ✅ | **The proof** — same seam + same ToolRegistry, only `model:` differs. |
| S11 | Mock-backend harness | sonnet | 1 | ✅ | Hermetic dispatch tests; mirror-drift caveat (Open Decision 2). |
| S12 | Build/deps/docs/dist | sonnet | 1 | ✅ | Working tarball; docs updated; masked one test (Open Decision 1). |
| S10 | Serve | — | — | n/a | Deferred at start (user decision). |

**Accuracy: 12/12.** No sortie's output was reverted or deleted by a later sortie. The only rework was the S2→S8 seam-test fixture relocation (a consequence of S4's guard, not S2 being wrong).

---

## Section 5: Harvest Summary

The architectural thesis is **proven**: an MLX model and Apple's `SystemLanguageModel` both drive the *same* `LanguageModelSession(model:tools:)` seam with the *same* `ToolRegistry` array — the only difference is one argument — so there is no second tool adapter and the abstraction holds across two structurally different backends. The single most important thing that changes for next time: **refine must validate concrete dependency implementations, not just API symbols.** The one genuine blocker this mission hit (the tokenizer) was knowable before execution and would have been caught by a "can we actually build a working instance of this?" check during refine. Test-cleanup found nothing to delete (0 of 12 files), which corroborates that the suites are hermetic where they should be and quarantined where they must be.

---

## Section 6: Files

**Preserve (read-only reference for next iteration):**

| File | Branch | Why |
|------|--------|-----|
| `OPERATION_CAULDRON_WHISPER_01_BRIEF.md` | mission/cauldron-whisper/01 | This brief; carries the open decisions forward. |
| `TEST_CLEANUP_REPORT.md` | mission/cauldron-whisper/01 | Flagged-test inventory; informs CI test policy. |
| `EXECUTION_PLAN.md` | mission/cauldron-whisper/01 | The plan + Resolved Decisions; note OQ-2 was superseded mid-mission. |

**Discard (safe to lose):**

| File | Why it's safe to lose |
|------|----------------------|
| `SUPERVISOR_STATE.md` | Execution bookkeeping; superseded by this brief. |
| `wwdc2026-232.txt` | Scratch reference, not part of the deliverable. |

---

## Section 7: Iteration Metadata

**Starting point commit:** `164672c` (Retarget to macOS 27 / Swift 6.4 and pare deps)
**Mission branch:** `mission/cauldron-whisper/01`
**Final commit on mission branch:** `96e74e3` (test-cleanup: no deletions; flagged for review)
**Rollback target:** `164672c` (same as starting point)
**Next iteration branch (if any):** `mission/cauldron-whisper/02`

---

## Section 8: Rollback Verdict

**Verdict:** `KEEP`

**Reasoning:** Every work unit reached COMPLETED with a ~0 effective retry rate (the one S2 continuation was an infrastructure death, not a logic failure). Test-cleanup deleted 0 of 12 mission test files (0% — far below the 10% KEEP threshold). The core thesis was proven end-to-end across two backends (Section 5), and the single planning miss (the tokenizer) was resolved cleanly with a maintained dependency and a thin bridge (Hard Discovery 1). The open items (Sections 3) are follow-up tickets, not foundation defects — none of them undermine the work already on the branch.

**Recommended action (KEEP):** Merge `mission/cauldron-whisper/01`. Open follow-up tickets for: (1) un-skip + update `ErrorReportingSmokeTest`; (2) move `ConsentToolObserver`/`ConsentToolWrapper` into the `SwiftBruja` library and replace the test mirror; (3) refresh the stale SwiftAcervo `primaryRepo` test fixtures; (4) (optional) on-device KV-cache delta-prefill verification; (5) decide on serve (S10) when a consumer exists. Feed the refine lesson (validate concrete dependency implementations, not just symbols) into the next breakdown/refine.
