---
type: mission-brief
state: completed
updated: 2026-10-04
mission: straitjacket-parrot-01
feature_name: OPERATION STRAITJACKET PARROT
iteration: 1
---

# Iteration 01 Brief — OPERATION STRAITJACKET PARROT

**Mission:** Give SwiftBruja what Personaje needs: schema-constrained JSON output (BR-P1), a thinking switch (BR-P2), lower peak memory on long prompts (BR-P3), and proof the default model runs through Bruja (BR-P4).
**Branch:** `mission/straitjacket-parrot/01`
**Starting Point Commit:** `7f902aac8cf5f8ef71b07c3275afec4fb6341762`
**Sorties Planned:** 16 (11 at the start; 5 added by replans)
**Sorties Completed:** 15
**Sorties Failed/Blocked:** 0 failed. 1 withdrawn by user decision (Sortie 8). 4 plan defects raised and resolved (Sorties 6, 6C, 6D, 8)
**Duration:** about 34 hours wall clock across two days, most of it halted for decisions; relative agent cost 380x (8 opus and 14 sonnet dispatches)
**Outcome:** Complete
**Verdict:** `KEEP` — every work unit finished with no retries, the constrained-output engine passes acceptance three runs in a row, and the one unmet acceptance item was waived by the user, not hidden.
**Tests pruned:** 0
**Tests flagged for review:** 0

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

## Acceptance against the requirements

| Acceptance | Result |
|------------|--------|
| 1. The nine prompts decode, JSON `null` for null, nothing after the closing brace | Met. Three consecutive full runs passed at `7a27e63`. |
| 2. Qwen3.5-9B answers inside the token budget with thinking off | Met on a one-line question through the plain query path. Not shown on a hard prompt, and not shown on the constrained path. |
| 3. A 15,000-token prompt peaks under 8 GB | **Waived, not met.** MLX peak active memory is 5.70 GB; process footprint is 20.70 GB. The user chose to leave the footprint and add no memory gate. Issue #48 stays open. |
| 4. One HUNTER query through the public API on the default model | Met. `testHunterQuery` calls `Bruja.query(_:schema:as:)`. |

---

## Section 1: Hard Discoveries

### 1. JSON validity does not make generation stop

**What happened:** The first engine (Sorties 3–5) masked every token that would break the schema and nothing else. A string or array could grow until `maxTokens` ran out. Four of eight nine-prompt runs threw `structuredOutputTruncated`; one string repeated "dismissive" 49 times.
**What was built to handle it:** `maxLength` on strings and `maxItems` on arrays, enforced by the acceptor and the logit processor during generation (Sortie 6A, `ddce774`). Personaje's bounds (500 / 200 / 8) live in its fixture schema.
**Should we have known this?** Yes. Any grammar-constrained decoder has this property; the plan specified the mask and never asked what guarantees the closing brace.
**Carry forward:** A constrained-output plan must name the termination guarantee before the first sortie. An unbounded schema can still truncate; the docs say so.

### 2. The model wants a space after the colon, and a compact-only mask turns that into `null`

**What happened:** Every output had `"age":null`, 43 of 43, including an excerpt that states the age. Measured logits at the first value: the model's top tokens were `" \""` (33.91) and `" "` (33.31). The compact-only acceptor masked both, and `null` (15.70) was the best token left. Whichever field came first went null; from the second value on the model copied the compact form it had already written.
**What was built to handle it:** One optional space after `:` and `,` (Sortie 6C, `01b0c36`). Output is no longer byte-compact.
**Should we have known this?** No. It took per-step logit measurement to see. The quality flag was raised at Sortie 5, before any criterion covered it.
**Carry forward:** A token mask must accept the surface form the model was trained to write, not only the minimal grammar. Criteria for constrained output must check content on a known-answer prompt, not only shape.

### 3. A repetition penalty on every token pushes fields to `null`

**What happened:** At 1.1 over a 64-token window, total null fields across the nine prompts went from 19 to 33. Whole fields flipped. The baseline, with bounds and the space fix in, showed no looping at all.
**What was built to handle it:** The parameter ships, default `nil` (Sortie 6D, `5656444`). The loop detectors (`maxWordRun` < 5, `duplicateItems` = 0) stay as assertions.
**Should we have known this?** Partly. The plan's own guard predicted harm at the closing quote; the harm came at the opening quote instead. The guard caught it, which is what it was for.
**Carry forward:** If loops return, penalise only inside string values and never a token containing a quote. Do not turn the blanket penalty on.

### 4. MLX's peak counter excludes the buffer cache, and the cache is the footprint

**What happened:** At 15,005 prompt tokens MLX peak active memory is 5.70 GB while the process footprint is 20.70 GB; 16.29 GB of that is MLX buffer cache. The cache limit defaults to MLX's memory limit. Bruja sets no cache limit and never clears the cache during generation. The pinned mlx-swift-lm does not either.
**What was built to handle it:** A measurement harness (Sortie 7, `0cc2013`) and cache clearing on unload only (Sortie 9, `3a2ffdc`). The footprint during generation was left alone by user decision.
**Should we have known this?** Yes. Decision OQ-3 chose `Memory.peakMemory` as "peak" without checking what it counts. The requirement's own figures (10 GB, 25.7 GB) were footprint-sized.
**Carry forward:** The likely fix is one line (`Memory.cacheLimit`). It refuses nothing and checks nothing, so it is not a memory gate. Sortie 8's text is kept in the plan and can be reinstated.

### 5. Long GPU test runs are fragile when anything else uses the GPU

**What happened:** The nine-prompt run takes 7–10 minutes on a free GPU and 25–30 minutes when other work shares it. The macOS GPU watchdog aborted the test process twice (`[METAL] Command buffer execution failed: Impacting Interactivity`). Throughput on one fixed test read anywhere from 2.5 to 16.7 tokens per second. The competitors were other projects' test runs and, later, a Vinetas image-generation process.
**What was built to handle it:** Nothing in the code. Orders allowed one re-run after a watchdog abort; Sortie 6's three-run criterion happened to land in a quiet window.
**Should we have known this?** No, but the supervisor was slow to find it: its "idle machine" checks looked only for test processes and missed the image generator for hours.
**Carry forward:** This is Personaje's real deployment (a job queue sharing a machine with an image engine). Throughput and peak-memory claims need a run with the GPU otherwise free, checked by more than a process-name grep.

### 6. The tokenizer has no vocabulary-size property

**What happened:** The plan asked for the vocabulary to be enumerated. The tokenizer exposes no count.
**What was built to handle it:** The table is built by probing token ids upward until decoding stops (151,665 entries for Qwen2.5-7B, no gaps), cached per model beside the container (Sortie 5).
**Should we have known this?** No; recon had only a stale checkout of the dependency.
**Carry forward:** A vocabulary with gaps in its id range would silently truncate this table.

---

## Section 2: Process Discoveries

### What the Agents Did Right

### 1. Stopping with REPLAN instead of forcing a pass

**What happened:** Sortie 6's agent found the truncation was library behaviour and stopped. Sortie 6C's stopped on a grep criterion that was already false before it began. Sortie 6D's stopped when its own guard failed, without trying the 1.2 retry the plan did not allow in that case.
**Right or wrong?** Right every time.
**Evidence:** Each REPLAN came with a saved patch and logs. Two were landed afterwards by a sonnet agent in one dispatch each.
**Carry forward:** Keep the "save uncommitted work as a patch" line in REPLAN orders. It turned two opus diagnoses into cheap follow-ups.

### 2. Measuring before fixing

**What happened:** Sortie 6C printed the top ten logits before and after the mask at each step and tested three candidate causes one run each. Sortie 7 measured memory and asserted nothing.
**Right or wrong?** Right. Both produced a finding that changed the plan.
**Evidence:** The always-null fix is 57 lines in one file with the deciding numbers in a comment. Sortie 7 took 3.5 minutes and withdrew a whole sortie.
**Carry forward:** For unknown-cause sorties, keep the pattern: a diagnostic, a run budget, a stop rule.

### What the Agents Did Wrong

### 3. Ending a turn while a test run was still in the background

**What happened:** Both Sortie 6C agents backgrounded a long run and ended their turn "waiting". The first never woke up when the run finished.
**Right or wrong?** Wrong; later orders forbade it explicitly and it stopped.
**Evidence:** One watchdog strike and a manual nudge at Sortie 6C; about 20 minutes lost.
**Carry forward:** Put "run tests in the foreground and wait" in every order that includes a model-backed run.

### 4. API wider than the plan asked for

**What happened:** Sortie 6A added a public `Counters` type and three public members on the acceptor; restoring a position now needs two values.
**Right or wrong?** Defensible, not reviewed. It ships as public API unless trimmed.
**Evidence:** `BrujaJSONAcceptor.swift` at `ddce774`.
**Carry forward:** Review the acceptor's public surface before the release.

### What the Planner Did Wrong

### 5. Criteria that checked shape and not content

**What happened:** Sorties 5 and 6 as first written would have passed with every `age` null.
**Right or wrong?** Wrong.
**Evidence:** 43 of 43 outputs null on a field the excerpt stated; no criterion looked.
**Carry forward:** One known-answer assertion per constrained-output criterion.

### 6. Three exit criteria that could not do their job

**What happened:** A no-special-casing grep that matched doc comments written by an earlier sortie (6C). A memory assertion on a counter that was already under the target (8). A changelog heading tied to a `-dev` marker that names an already-released version (11).
**Right or wrong?** Wrong. All three were written without running the command or reading the value on the tree the sortie would start from.
**Evidence:** One REPLAN, one withdrawn sortie, one override in the orders.
**Carry forward:** In refine, run each grep-style criterion against the current tree and record what it prints today.

### 7. The supervisor edited the plan itself, three times

**What happened:** After each user decision (OQ-9, OQ-7 revised, OQ-3 revised) the supervisor wrote the amendment into `EXECUTION_PLAN.md` and resumed, without re-running the five refine passes.
**Right or wrong?** It kept the mission moving and each edit followed a decision the user had just stated. It is still against the rule that the plan changes only by human edit or `refine`.
**Evidence:** Three `.build/mission/EXECUTION_PLAN.before-*.md` copies; the plan's own summary line says the amendments were not refined.
**Carry forward:** Decide whether the supervisor may write a decision into the plan. If yes, say so in the skill; if no, this needs `refine`.

### 8. Every sortie paid for the full nine-prompt run twice

**What happened:** From 6B on, each WU2 sortie's criteria included the whole acceptance class, run once by the agent and once by the supervisor.
**Right or wrong?** It caught the variance that one run hides. It also cost most of the mission's wall time.
**Evidence:** The four longest dispatches were 41–43 minutes, mostly test time.
**Carry forward:** A two-prompt smoke target for per-sortie checks; the full run only at the acceptance sortie.

---

## Section 3: Open Decisions

### 1. Does issue #48 get a cache limit after all?

**Why it matters:** On a 16 GB Mac, MLX's default lets the cache grow to roughly all of physical RAM. On this 32 GB machine one test process accounted for about 15 GB of swap. The requirement's reason for the 8 GB target was that Mac.
**Options:** (A) leave it, as decided. (B) Set `Memory.cacheLimit` in Bruja; no gate, likely one line, needs a throughput check. (C) Raise it upstream in mlx-swift-lm and wait.
**Recommendation:** B, before Personaje's local client ships. Nobody has measured a 16 GB machine.

### 2. What is the real throughput of the constrained path?

**Why it matters:** The trend on one fixed test was 18.96 (before bounds) → 16.67 → 13–15 → 15.4 at Sortie 6, with later readings of 10.3 and 2.9 while other work used the GPU. No reading exists for the final commit with the GPU free, so a slowdown from Sorties 7, 9 or 10 is not ruled out.
**Options:** One run of `make test-personaje ONLY=testConstrainedQueryOnDefaultModel` with Vinetas and every other GPU user closed.
**Recommendation:** Do it before merging. About 15 tokens per second means the code is fine.

### 3. Is `age=./52` a bug?

**Why it matters:** `testConstrainedQueryThroughPublicAPI` (an unbounded two-field schema) returns a malformed age in every run. The test only checks that the value contains `52`. The bounded fourteen-field schema returns `"52"` cleanly.
**Options:** Investigate; or tighten the test; or accept.
**Recommendation:** Investigate. It is the only known wrong content the engine produces.

### 4. Does the README example work?

**Why it matters:** It pairs the constrained path with `thinking: .off` on Qwen3.5-9B. That combination compiles and is wired by code reading only; no test runs it.
**Options:** Run it once; or change the example to the default model.
**Recommendation:** Add it as a test. It is also the gap in Acceptance 2.

### 5. Should a forced age guess be marked as a guess?

**Why it matters:** `"adult"` in the output does not say whether the script stated it or the model guessed. The guess varies run to run (one character flips between `adult` and `older adult`). Null counts on the other fields also fell after the wording change, which may mean the model guesses there too.
**Options:** Leave it; add a companion field; or post-check in Personaje.
**Recommendation:** Personaje's call. Also note the rule lives in the prompt and schema Personaje sends; this repo only proves it on fixtures.

### 6. Version marker and changelog

**Why it matters:** `Bruja.version` reads as a `-dev` build of a version that is already tagged, and CHANGELOG.md has no section for that tagged version. The new section is headed with the next minor after the highest tag.
**Options:** Fix both in the release.
**Recommendation:** Fix before running the release skill.

---

## Section 4: Sortie Accuracy

| Sortie | Task | Model | Attempts | Accurate? | Notes |
|--------|------|-------|----------|-----------|-------|
| 1 | Test harness, smoke test | opus | 1 | Yes | Target and class reused by every later model-backed sortie |
| 2 | Prompt fixtures | sonnet | 1 | Mostly | Instruction block rewritten in 6E; schema gained bounds in 6B and a non-null `age` in 6E |
| 3 | Schema and acceptor | opus | 1 | Mostly | Compact-only form was wrong (6C); two of its tests were rewritten. State design survived bounds and the space unchanged |
| 4 | Logit processor | opus | 1 | Yes | Mask cache keyed by state held through 6A, 6C and 6D |
| 5 | `query(_:schema:as:)` | opus | 1 | Yes | Raised the null-age flag before any criterion covered it |
| 6A | Length bounds | opus | 1 | Yes | Wider public API than planned |
| 6B | Fixture bounds | sonnet | 1 | Yes | — |
| 6C | Always-null first field | opus, then sonnet | 1 | Yes | One REPLAN on a bad criterion; fix landed unchanged |
| 6E | Age never null | sonnet | 1 | Yes | Passed without rewording |
| 6D | Repetition penalty | opus, then sonnet | 1 | Partly | The feature as first planned was harmful; it ships switched off |
| 6 | Acceptance | sonnet | 1 | Yes | First dispatch ended in the REPLAN that reshaped WU2 |
| 7 | Memory harness | opus | 1 | Yes | Over-modelled: sonnet would have done |
| 8 | Peak under 8 GB | — | 0 | Moot | Withdrawn before dispatch |
| 9 | Unload | sonnet | 1 | Yes | 4.29 GB back to 9.5 KB |
| 10 | Thinking switch | sonnet | 1 | Yes | Constrained path wired but untested |
| 11 | Docs | sonnet | 1 | Yes | Example uses an untested combination |

---

## Section 5: Harvest Summary

The plan treated constrained JSON as a masking problem and it is three problems: the mask, the guarantee that generation ends, and the surface form the model was trained to write. Getting the second and third right took five added sorties and three plan defects, and each was found by measurement, not by the criteria as first written. The single most important change for a next iteration is that criteria check content on a known-answer prompt and are run against the starting tree before they go in the plan. On memory, the mission established the cause (an unbounded MLX buffer cache) and the user chose not to act on it; that choice should be revisited before a 16 GB Mac runs this. Test cleanup pruned nothing and flagged nothing: the three CI-run test files are model-free and self-contained, and the two model-backed classes are excluded from CI by name and skip when their model is absent. The cleanup agent did not flag the run-to-run variance of the acceptance assertions at temperature 0.3, though it was asked to; this brief records it instead.

---

## Section 6: Files

**Preserve (read-only reference for next iteration):**

| File | Branch | Why |
|------|--------|-----|
| `Sources/SwiftBruja/Core/BrujaJSONSchema.swift`, `BrujaJSONAcceptor.swift`, `BrujaJSONLogitProcessor.swift` | `mission/straitjacket-parrot/01` | The constrained-output engine |
| `Sources/SwiftBruja/Core/BrujaQuery.swift`, `Bruja.swift`, `BrujaTypes.swift`, `BrujaModelManager.swift` | same | Public API: constrained query, `thinking:`, unload |
| `Tests/BrujaIntegrationTests/PersonajeAcceptanceTests.swift`, `PersonajeMemoryTests.swift` | same | Acceptance and measurement harness |
| `Fixtures/Personaje/` | same | Nine prompts, schema, generator |
| `.build/mission/` (gitignored, local only) | — | Run logs, the two REPLAN patches, three pre-amendment copies of the plan |

**Discard (will not exist after rollback):**

Not applicable. The verdict is `KEEP`.

---

## Iteration Metadata

**Starting point commit:** `7f902aac8cf5f8ef71b07c3275afec4fb6341762` (`docs: requirements from Personaje`)
**Mission branch:** `mission/straitjacket-parrot/01`
**Final commit on mission branch:** `36b8ef7`
**Rollback target:** `7f902aac8cf5f8ef71b07c3275afec4fb6341762` (same as starting point commit)
**Next iteration branch:** `mission/straitjacket-parrot/02` (only if follow-up work is run as a mission)

---

## Rollback Verdict

**Verdict:** `KEEP`

**Reasoning:** All five work units completed and no sortie needed a retry. The constrained-output engine passed its acceptance class three times in a row and its design (position-only state, per-state mask cache) held through three later changes without rework. Test cleanup removed nothing. Six hard discoveries is more than the `KEEP` guideline expects for a first iteration, but each one was absorbed into the code on this branch, so rolling back would throw away the fixes along with the mistakes.

**Recommended action:** Merge the mission branch through the usual `development` pull request. Before merging:

- Take one throughput reading with the GPU free (Open Decision 2).

Follow-up tickets:

- A cache limit for issue #48, with a 16 GB measurement (Open Decision 1).
- The `age=./52` output on the unbounded two-field schema (Open Decision 3).
- A test for the constrained path with `thinking: .off` on Qwen3.5-9B, and a hard-prompt check for Acceptance 2 (Open Decision 4).
- Review the acceptor's public `Counters` surface.
- Fix the `-dev` version marker and the missing changelog section before the release (Open Decision 6).
- Rename the README example's `Character` struct, which shadows `Swift.Character`.
- Personaje must copy the "age is never null" wording and the non-nullable `age` into its own prompt and schema; this repo only tests them on fixtures.
