---
type: execution-plan
state: completed
updated: 2026-10-04
mission: straitjacket-parrot-01
feature_name: OPERATION STRAITJACKET PARROT
starting_point_commit: 7f902aac8cf5f8ef71b07c3275afec4fb6341762
mission_branch: mission/straitjacket-parrot/01
iteration: 1
---

# EXECUTION_PLAN.md — SwiftBruja: what Personaje needs

Source: `REQUIREMENTS-personaje.md` (BR-P1 … BR-P4). Ground truth: `RECON_REPORT.md` (CLEAR).

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

## Conventions for every sortie

- Build and test with `make` targets only. Never `swift build` or `swift test`.
- `make test-ci` is the regression gate (model-free; this is what hosted CI runs).
- Model-backed tests cannot run in hosted CI or in the sandboxed `xcodebuild test`
  host. They live in `Tests/BrujaIntegrationTests/`, `XCTSkip` when their model
  or fixture is absent, and run through dedicated Makefile targets that use the
  unsandboxed `xcrun xctest` host — the existing `test-agent-seam` recipe
  (`Makefile:140-146`) is the pattern to copy.
- "Passed (not skipped)" in an exit criterion means the target's output contains
  the line `Test Case '-[BrujaIntegrationTests.<Class> <testName>]' passed`.
  A skipped test still exits 0, so the exit code alone does not prove it.
- Default model in this plan means `mlx-community/Qwen2.5-7B-Instruct-4bit`
  (Personaje's default). It is not `BrujaModelManager.defaultModel` and this
  mission does not change that constant.
- Models on disk on this machine: Qwen2.5-7B-Instruct-4bit and Qwen3.5-9B-MLX-4bit.
  The small fixture model `Qwen2.5-0.5B-Instruct-4bit` is **not** on disk, so no
  sortie in this plan depends on it and no sortie downloads a model.
- One build at a time: every sortie that runs a `make` build or test target runs
  in the build lane, in sortie order. Two `xcodebuild` runs against the same
  DerivedData collide.
- Status at the 2026-10-03 replan: Sorties 1–5 are complete (`9d315d5`, `54ac180`,
  `06eb726`, `e370670`, `f5ca486`) and are kept here as the record. Sortie 6 is
  part done at `32c3ff8`. Execution continues at Sortie 6A. Sortie numbers are
  not reused or shifted, because commits and `SUPERVISOR_STATE.md` refer to them.
- `make test-personaje` runs the nine prompts and takes 4–8 minutes. From Sortie
  6A on, `make test-personaje ONLY=<testName>` runs one test.
- Branch from `development`. No `@available` checks. Run `make lint` before finishing.
- New public API ships in our next minor release version.

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| WU1 Default model check (BR-P4) | `Tests/BrujaIntegrationTests/`, `Fixtures/`, `Makefile` | 2 | 0 | none |
| WU2 Schema-constrained output (BR-P1) | `Sources/SwiftBruja/Core/`, `Tests/`, `Fixtures/Personaje/` | 9 (3, 4, 5, 6A–6E, 6) | 1 | WU1 |
| WU3 Peak memory (BR-P3) | `Sources/SwiftBruja/Core/`, `Tests/` | 2 (7, 9; Sortie 8 withdrawn) | 2 | WU2 |
| WU4 Thinking switch (BR-P2) | `Sources/SwiftBruja/`, `Tests/` | 1 | 3 | WU3 |
| WU5 Documentation | repo root | 1 | 4 | WU2, WU3, WU4 |

WU2, WU3 and WU4 all edit `Sources/SwiftBruja/Core/BrujaQuery.swift` and
`Sources/SwiftBruja/Bruja.swift`, so they are layered in the order the
requirements give (BR-P1, BR-P3, BR-P2) rather than run side by side.

---

## WU1 — Default model check (BR-P4)

### Sortie 1: Personaje test harness and default-model smoke test

**Priority**: 31.5 — blocks every later build-lane sortie; sets up the test class and Makefile recipe that Sorties 5, 6, 7 and 10 reuse.

**Agent**: build lane.

**Entry criteria**:
- [ ] First sortie — no prerequisites
- [ ] Recon A-08: the default model is on disk at `~/Library/Group Containers/group.intrusive-memory.models/SharedModels/mlx-community_Qwen2.5-7B-Instruct-4bit` (no `acervo ship` needed on this machine)

**Tasks**:
1. Create `Tests/BrujaIntegrationTests/PersonajeAcceptanceTests.swift` with an `XCTestCase` that skips via `XCTSkipUnless(Acervo.isModelConfigPresent(modelId))`.
2. Add `testDefaultModelAnswersThroughBruja`: call `Bruja.queryWithMetadata("Reply with the single word: ready", model: "mlx-community/Qwen2.5-7B-Instruct-4bit", maxTokens: 16)`; assert no throw and a non-empty `response`.
3. Add a `test-personaje` Makefile target that runs the whole `PersonajeAcceptanceTests` class (`-XCTest PersonajeAcceptanceTests`) through the unsandboxed `xcrun xctest` host with `ACERVO_APP_GROUP_ID` set, copying the `test-agent-seam` recipe. Add it to `.PHONY` and to `make help`.
4. Add `-skip-testing:BrujaIntegrationTests/PersonajeAcceptanceTests` to `test-ci` (both places the skip list appears: `Makefile:117-128` and `:212-220`).
5. Sortie 2 runs at the same time in the same working tree and owns `Fixtures/Personaje/`. Do not touch or stage anything under `Fixtures/`.

**Exit criteria**:
- [ ] `make test-personaje` exits 0 and `testDefaultModelAnswersThroughBruja` passed (not skipped)
- [ ] `make test-ci` exits 0
- [ ] `grep -c "^test-personaje:" Makefile` = 1 and `make help | grep -c "test-personaje"` ≥ 1
- [ ] `grep -c "skip-testing:BrujaIntegrationTests/PersonajeAcceptanceTests" Makefile` = 2

### Sortie 2: Personaje prompt fixtures

**Priority**: 21 — blocks Sortie 6 and everything after it; depends on nothing in this repo.

**Agent**: sub-agent, **NO BUILD**. Runs alongside Sortie 1 (and Sortie 3 or 4 if still running).

**Entry criteria**:
- [ ] No prerequisite sortie
- [ ] Decision OQ-1: fixtures are committed to this repo under `Fixtures/Personaje/`
- [ ] Readable inputs (read-only, outside this repo): the script `/Users/stovak/Projects/podcasts/granville/granville-2026SEP08.highland` (a zip holding a Fountain text file) and the context rules in `/Users/stovak/Projects/apps/Personaje/docs/REQUIREMENTS-APP-UI.md` §11.2–§11.4 (lines 425–478)

**Tasks**:
1. Write `Fixtures/Personaje/build-fixtures.py` (Python 3, standard library only). It takes the `.highland` path as its one argument, reads the Fountain text out of the zip, and writes the nine prompt files. The prompts are produced by running this script, never typed by hand — the HUNTER prompt alone is about 15,000 tokens.
2. The script writes nine prompt files, one character each, named `NN-<CHARACTER>-<major|minor>.txt`. The original nine were not kept, so this set is: the five majors in this order (`01` HUNTER, `02` SHANE, `03` ARCHER, `04` CLARK, `05` KEVIN), then `06` TOBY and `07` IOLA as minors, then `08` and `09`: the two characters with the most dialogue blocks among those not already listed.
3. Major prompts hold every scene the character speaks in, complete. Minor prompts hold each of the character's lines with the 3 elements before and after it, clipped to the scene and merged where they overlap. Each element is labelled with its speaker.
4. Every prompt opens with the same instruction block — return one JSON object with the Personaje fields, and a field the excerpts say nothing about must be null — followed by a line reading exactly `=== EXCERPTS ===`, then the excerpts.
5. Add `Fixtures/Personaje/README.md` stating the source script and date, the two context rules, how to re-run `build-fixtures.py`, and that the files are test input for `PersonajeAcceptanceTests`.
6. Add `Fixtures/Personaje/schema.json` as the single source the tests build their `BrujaJSONSchema` from. Shape: a JSON Schema object with `properties` (the fourteen fields, every one nullable) and a `propertyOrder` array naming the fourteen keys in the order given in `REQUIREMENTS-personaje.md` § What Personaje sends. The item objects of `relationships` and `canonFacts` carry their own `properties` and `propertyOrder`. JSON object key order does not survive parsing in Swift, so the arrays are the order of record.
7. Sortie 1 runs at the same time in the same working tree and owns `Tests/` and `Makefile`. Do not touch or stage them; stage by path under `Fixtures/Personaje/` only.

**Exit criteria**:
- [ ] `ls Fixtures/Personaje/*.txt | wc -l` = 9, and `test -f Fixtures/Personaje/01-HUNTER-major.txt`
- [ ] `ls Fixtures/Personaje/*-major.txt | wc -l` = 5 and `ls Fixtures/Personaje/*-minor.txt | wc -l` = 4
- [ ] `python3 -c "import json;d=json.load(open('Fixtures/Personaje/schema.json'));assert len(d['properties'])==14 and len(d['propertyOrder'])==14 and set(d['propertyOrder'])==set(d['properties'])"` exits 0
- [ ] `for f in Fixtures/Personaje/*.txt; do sed '/^=== EXCERPTS ===$/q' "$f" | shasum; done | sort -u | wc -l` = 1 (shared instruction block, and every file has the marker)
- [ ] `wc -c < Fixtures/Personaje/01-HUNTER-major.txt` ≥ 30000 (a floor against a truncated excerpt; the original HUNTER prompt was 14,944 tokens)
- [ ] Re-running `python3 Fixtures/Personaje/build-fixtures.py <script path>` leaves `git status --porcelain Fixtures/Personaje/*.txt` empty once the files are committed (output is deterministic)
- [ ] `git diff --cached --name-only | grep -vc "^Fixtures/Personaje/"` = 0 at commit time (this sortie adds fixtures only)
- [ ] [judgment] In `01-HUNTER-major.txt`, every excerpted scene contains at least one HUNTER dialogue block and no scene is cut mid-way

---

## WU2 — Schema-constrained output (BR-P1)

Design fixed by the requirements: Personaje requests only the empty fields, so
the schema is a runtime value per call, not something derived from a `Codable`
type. The existing `query(as:)` keeps its signature and behaviour; the
constrained path is a new overload. The engine is a token-mask
`LogitProcessor` (decision OQ-2).

### Sortie 3: `BrujaJSONSchema` and a character-level acceptor

**Priority**: 29.25 — every constrained-output sortie rests on these two types; the state machine is the hardest pure logic in the mission.

**Agent**: build lane.

**Entry criteria**:
- [ ] Sortie 1 exit criteria met
- [ ] Decision OQ-2: the engine is a token-mask `LogitProcessor` driven by a JSON-schema state machine, limited to the shapes Personaje sends

**Tasks**:
1. Create `Sources/SwiftBruja/Core/BrujaJSONSchema.swift`: a public `Sendable` value type with public initialisers, describing an object with ordered properties, where a property is a string, integer, number, boolean, array of one item kind, or nested object, and each may be nullable. No MLX imports.
2. Create `Sources/SwiftBruja/Core/BrujaJSONAcceptor.swift`: a state machine built from a schema with `advance(_ character: Character) -> Bool`, `isComplete`, and a copyable `Hashable` state. Keys are emitted in schema order, compact form (no optional whitespace).
3. The state holds position only, never the text consumed. Two points inside the same string value that accept the same next characters have equal states. Sortie 4 caches a token mask per state; if the state grew with the text, that cache would never hit.
4. A nullable string property rejects the string values `"null"` and `""`; the only way to say "nothing" is JSON `null`. The rejection is at the closing quote, so `"nullable"` stays legal.
5. Once the top-level object closes, `isComplete` is true and every further character is rejected.
6. Create `Tests/SwiftBrujaTests/BrujaJSONAcceptorTests.swift` using the Personaje schema, declared inline in the test (`age`, `pronouns`, `occupation`, `languages`, `logline`, `sampleLine`, `appearance`, `wardrobe`, `personality`, `backstory`, `arc`, `relationships[{with, nature}]`, `voiceAndSpeech`, `canonFacts[{fact, quote}]`, all nullable).

**Exit criteria**:
- [ ] `make test-ci` exits 0 and its output shows `BrujaJSONAcceptorTests` ran
- [ ] Tests cover, each as its own test method: a full valid object accepted; an all-`null` object accepted; `"null"` as a string value rejected; `""` as a string value rejected; `"nullable"` as a string value accepted; a missing key rejected; an extra key rejected; a wrong shape (`relationships` as an object) rejected; any character after the closing brace rejected; escaped quotes and `\uXXXX` inside strings accepted
- [ ] A test asserts the state after `{"age":"abcde` equals the state after `{"age":"abcdefghij`
- [ ] `grep -L "import MLX" Sources/SwiftBruja/Core/BrujaJSONSchema.swift Sources/SwiftBruja/Core/BrujaJSONAcceptor.swift` lists both files

### Sortie 4: Token-mask logit processor

**Priority**: 25 — first contact with the unverified mlx-swift-lm API; a REPLAN here stops WU2 before the public API is written.

**Agent**: build lane.

**Entry criteria**:
- [ ] Sortie 3 exit criteria met
- [ ] Verify first, after `make resolve`: in `~/Library/Developer/Xcode/DerivedData/SwiftBruja-*/SourcePackages/checkouts/mlx-swift-lm`, `Libraries/MLXLMCommon/Evaluate.swift` declares `public protocol LogitProcessor` with `process(logits:)`, and a `TokenIterator.init` that takes `processor:` and `sampler:`. Recon saw both only in a stale copy. If either is missing, report REPLAN.

**Tasks**:
1. Create `Sources/SwiftBruja/Core/BrujaJSONLogitProcessor.swift` conforming to `MLXLMCommon.LogitProcessor`. It takes a `BrujaJSONAcceptor`, the vocabulary as `[tokenId: String]`, and the EOS token ids.
2. `process(logits:)` sets to `-inf` every token whose text the acceptor cannot consume from its current state. `didSample(token:)` advances the acceptor.
3. A token whose text is empty or contains U+FFFD (a partial UTF-8 sequence in a byte-level vocabulary) is always masked. Known limit, to be stated in the type's doc comment: a character the tokenizer can only spell as split-byte tokens cannot be generated on this path.
4. When the acceptor is complete, only EOS token ids stay unmasked.
5. Cache the allowed-token mask per acceptor state so the vocabulary is not rescanned on every step for a state already seen.
6. Create `Tests/SwiftBrujaTests/BrujaJSONLogitProcessorTests.swift` with a hand-built vocabulary of about 30 tokens, including multi-character tokens that span a structural boundary (for example `",`  and `":`) and one token containing U+FFFD. No model.

**Exit criteria**:
- [ ] `make test-ci` exits 0 and its output shows `BrujaJSONLogitProcessorTests` ran
- [ ] A test drives greedy selection over the fake vocabulary with uniform logits to completion and the decoded string passes `JSONSerialization.jsonObject(with:)`
- [ ] A test asserts that after completion the only finite logits are the EOS ids
- [ ] A test asserts a token that would write `"null"` as a string value is masked
- [ ] A test asserts the U+FFFD token is masked in a state inside a string value

### Sortie 5: `query(_:schema:as:)` on the constrained path

**Priority**: 24.5 — the public API that Sorties 6, 8, 10 and 11 all call; largest sortie in WU2.

**Agent**: build lane.

**Entry criteria**:
- [ ] Sortie 4 exit criteria met
- [ ] Recon A-01/A-06: existing overloads at `Sources/SwiftBruja/Core/BrujaQuery.swift:89-115` and `Sources/SwiftBruja/Bruja.swift:159-175`
- [ ] Verify first, in the resolved `swift-transformers` and `mlx-swift-lm` checkouts under DerivedData: the tokenizer the container exposes can give the text of a single token id and the size of the vocabulary. If the vocabulary cannot be enumerated, report REPLAN.

**Tasks**:
1. Add `BrujaQuery.query<T: Decodable>(_:schema:as:model:temperature:maxTokens:system:)`. It prepares input through the container's processor and generates with a `TokenIterator` built with a `BrujaJSONLogitProcessor`, inside one `container.perform` closure — the same shape as `ContainerGenerationSource.generate` (`Sources/SwiftBruja/Agent/MLXGeneration.swift:155-195`).
2. Build the vocabulary table (`[tokenId: String]`, each token decoded on its own) from the container's tokenizer once per model and cache it alongside the loaded container in `BrujaModelManager`.
3. Decode the output with `JSONDecoder` directly. Do not route through `cleanJSONResponse`. If generation ends on `maxTokens` before the acceptor completes, throw a new `BrujaError.structuredOutputTruncated(tokenLimit:)` with an `errorDescription`.
4. Add the matching public overload on `Bruja` with doc comments.
5. Leave the existing `query(as:)` overloads byte-for-byte unchanged.
6. Add `testConstrainedQueryOnDefaultModel` to `PersonajeAcceptanceTests.swift` against the default model with the full Personaje schema (declared inline), a 200-word invented excerpt, and `maxTokens: 2048`.
7. Add `testVocabularyTableRoundTrips` to the same class: tokenize a 50-word sentence with the default model's tokenizer, join the vocabulary-table text of each token id, and assert the result equals the tokenizer's own decode of the full id sequence.

**Exit criteria**:
- [ ] `make build` exits 0 and `make test-ci` exits 0
- [ ] `make test-personaje` exits 0 with `testConstrainedQueryOnDefaultModel` and `testVocabularyTableRoundTrips` passed (not skipped); the first asserts the raw output's last character is `}` and that it decodes
- [ ] `git diff development...HEAD -- Sources/SwiftBruja/Core/BrujaQuery.swift | grep -c "^-[^-]"` = 0 (this sortie only adds lines to that file)
- [ ] `grep -c "structuredOutputTruncated" Sources/SwiftBruja/Core/BrujaError.swift` ≥ 2 (the case and its description)
- [ ] `grep -c "schema: BrujaJSONSchema" Sources/SwiftBruja/Bruja.swift` = 1

### Replan of 2026-10-03 (Sorties 6A–6D)

Sortie 6 raised REPLAN at commit `32c3ff8`: the engine from Sorties 3–5 enforces
JSON validity only, so a string or an array can grow until `maxTokens` runs out
(4 of 8 runs of `testNinePromptsDecode` threw `structuredOutputTruncated`). The
same runs showed `"age":null` in 43 of 43 outputs. Sorties 6A–6D fix the
library; Sortie 6 then finishes as the acceptance gate. They run in the order
written, each in the build lane. None of them changes the plain `query`,
`queryWithMetadata` or `query(as:)` overloads.

### Sortie 6A: Length bounds in the schema, acceptor and logit processor

**Priority**: 32.25 — every remaining sortie waits on it; changes the three types the constrained path is built from.

**Agent**: build lane.

**Entry criteria**:
- [ ] Sortie 5 exit criteria met (commit `f5ca486`); tree clean at `32c3ff8` or later
- [ ] Decision OQ-5: termination is guaranteed by `maxLength` and `maxItems` bounds, enforced during generation

**Tasks**:
1. Give the `test-personaje` Makefile target an optional `ONLY=<testName>` variable: with it, the recipe passes `-XCTest PersonajeAcceptanceTests/<testName>`; without it, the whole class as today.
2. `BrujaJSONSchema`: an optional `maxLength` on any string and an optional `maxItems` on any array, including strings inside array item objects. Existing initialisers and factory methods called without a bound still compile and mean "unbounded". A bound below 1 is a precondition failure.
3. `maxLength` counts the characters of the JSON text between the quotes as written, so an escape such as `\n` counts 2 and `é` counts 6. State this in the doc comment.
4. `BrujaJSONAcceptor`: at `maxLength` the only character accepted is the closing quote; at `maxItems` the only character accepted after an item is `]`. The remaining-length and remaining-items counters live beside `State`, not inside it — `State` stays position only, so the three existing state tests (`testStateInsideStringDoesNotGrowWithText`, `testStateDoesNotGrowWithArrayLength`, `testStatesThatAcceptDifferentContinuationsDiffer`) pass unchanged.
5. `BrujaJSONLogitProcessor`: keep the mask cache keyed by `State`. Apply the bound as a second filter on top of the cached mask, and only when the remaining length is shorter than the longest vocabulary token. A token that would carry a string past its bound, or an array past its item count, is masked.
6. Model-free tests in `BrujaJSONAcceptorTests.swift` and `BrujaJSONLogitProcessorTests.swift` (see exit criteria).
7. In `testConstrainedQueryOnDefaultModel`, give the inline schema the OQ-6 bounds (500 on top-level strings, 200 on strings inside array items, 8 items per array). Its existing stats line already prints `tokensPerSecond`.

**Exit criteria**:
- [ ] `make test-ci` exits 0 with these passing, each its own test method: a string of exactly `maxLength` characters accepted; one character more rejected; an array of exactly `maxItems` items accepted; one item more rejected; a bounded string inside an array item enforced; a schema with no bounds accepts a 10,000-character string
- [ ] A logit-processor test drives selection that always prefers a one-letter filler token over the fake vocabulary, with a bounded schema, and asserts the output completes, passes `JSONSerialization.jsonObject(with:)`, and has no string longer than its bound and no array longer than its item count
- [ ] `git diff 32c3ff8 -- Tests/SwiftBrujaTests/BrujaJSONAcceptorTests.swift | grep -c "^-[^-]"` = 0 (existing acceptor tests untouched; new ones added)
- [ ] `make test-personaje ONLY=testConstrainedQueryOnDefaultModel` exits 0, the test passed (not skipped), and its stats line shows `tokensPerSecond` ≥ 12 (18.96 before bounds; a floor against rescanning the vocabulary on every token)
- [ ] `grep -c "maxLength" Sources/SwiftBruja/Core/BrujaJSONSchema.swift` ≥ 1 and `grep -c "maxItems" Sources/SwiftBruja/Core/BrujaJSONSchema.swift` ≥ 1

### Sortie 6B: Bounds in the Personaje fixture schema and test loader

**Priority**: 26.75 — Sorties 6D and 6 measure through the bounded fixture schema.

**Agent**: build lane.

**Entry criteria**:
- [ ] Sortie 6A exit criteria met
- [ ] Decision OQ-6: 500 characters for top-level strings, 200 for strings inside array items, 8 items per array, `maxTokens: 4096` in the acceptance tests

**Tasks**:
1. `Fixtures/Personaje/schema.json` (hand-written; `build-fixtures.py` does not produce it): add `"maxLength": 500` to the eleven top-level string properties, `"maxLength": 200` to `with`, `nature`, `fact` and `quote`, and `"maxItems": 8` to `relationships` and `canonFacts`.
2. `Fixtures/Personaje/README.md`: state the bounds and that they are Personaje's choice, not a library default.
3. The loader in `PersonajeAcceptanceTests.swift` (`objectSchema`, `kind(of:)`) reads `maxLength` and `maxItems` into the `BrujaJSONSchema` it builds.
4. `runPrompt` uses `maxTokens: 4096` and asserts, for the decoded output, every top-level string has at most 500 characters, every item string at most 200, and each array at most 8 items.
5. Test code and fixtures only. No change under `Sources/`.

**Exit criteria**:
- [ ] `python3 -c "import json;d=json.load(open('Fixtures/Personaje/schema.json'));p=d['properties'];a=['relationships','canonFacts'];assert all(p[k]['maxLength']==500 for k in p if k not in a);assert all(p[k]['maxItems']==8 for k in a);assert all(v['maxLength']==200 for k in a for v in p[k]['items']['properties'].values())"` exits 0
- [ ] `make test-personaje` exits 0 with `testNinePromptsDecode` and `testHunterQuery` passed (not skipped)
- [ ] `git diff <sortie start commit>..HEAD --name-only | grep -c "^Sources/"` = 0 (it touches nothing under `Sources/`)
- [ ] `make test-ci` exits 0

### Sortie 6C: Find and fix the always-null first field

**Priority**: 25.25 — the cause is not known; second-highest REPLAN risk in the mission.

**Agent**: build lane.

**Entry criteria**:
- [ ] Sortie 6B exit criteria met
- [ ] Decision OQ-8: `"age":null` on an excerpt that states the age is a defect this mission fixes
- [ ] First action: run `make test-personaje ONLY=testConstrainedQueryOnDefaultModel` on the unmodified tree and confirm the raw output starts `{"age":null`. The test runs at temperature 0 on an excerpt that reads "INES VALCARCE, 52". If the age is already not null, stop and report REPLAN (the premise is gone).

**Tasks**:
1. Measure: with a temporary diagnostic, print one line per generation step, up to and including the first token of the `age` value: `LOGITS step=<n> pre=[<token>:<logit> ×10] post=[<token>:<logit> ×10]` — the ten highest before the mask and the ten highest after it.
2. Test these candidate causes one at a time, one single-test run each, six runs at most counting the baseline: (a) the compact form — the acceptor rejects the space the model wants after `:` and `,`; allow one optional space after each; (b) the default system prompt (`constrainedDefaultSystem`) pushing toward null; (c) position — move `age` out of first place in the inline schema, as a diagnostic only.
3. If (a) or (b), alone or together, makes the age non-null, apply it. If the acceptor changes, `State` stays position only, nothing is accepted after the closing brace, and the unit tests in `BrujaJSONAcceptorTests.swift` cover the new form. If neither does, stop and report REPLAN with the `LOGITS` lines. Do not special-case any field name and do not reorder the caller's schema.
4. Make `testConstrainedQueryOnDefaultModel` assert the decoded `age` contains `52`.
5. Remove the temporary diagnostic before committing. Record the cause and the deciding `LOGITS` line in a comment at the fix site.

**Exit criteria**:
- [ ] `make test-personaje ONLY=testConstrainedQueryOnDefaultModel` exits 0 and the test passed (not skipped), with the `52` assertion in it: `grep -c '"52"' Tests/BrujaIntegrationTests/PersonajeAcceptanceTests.swift` ≥ 1
- [ ] `grep -l '"age"' Sources/SwiftBruja/Core/BrujaJSONAcceptor.swift Sources/SwiftBruja/Core/BrujaJSONLogitProcessor.swift Sources/SwiftBruja/Core/BrujaQuery.swift | wc -l` = 0 (no field is special-cased; `BrujaJSONSchema.swift` is left out because its doc-comment examples name `age`)
- [ ] `grep -rc "LOGITS step=" Sources/ | grep -vc ":0$"` = 0 (diagnostic removed)
- [ ] `make test-personaje` exits 0 and `make test-ci` exits 0
- [ ] [judgment] The comment at the fix site names one specific cause and quotes the measured logits that show it

### Amendment of 2026-10-04 (Sortie 6E)

Sortie 6C raised REPLAN on one exit criterion (fixed above) and showed that,
with the mask fixed, all nine fixture prompts still answer `"age": null`. That
is the prompt doing what it says: the excerpts state no age and the instruction
block says "Do not guess". Decision OQ-9 changes the rule for `age` only.
Sortie 6E runs after 6C and before 6D, so 6D's baseline is measured on the
final prompts. Its letter is out of running order because numbers are not reused.

### Sortie 6E: `age` is never null in the Personaje prompts

**Priority**: 23.5 — changes all nine prompts, so it must land before 6D takes its baseline.

**Agent**: build lane.

**Entry criteria**:
- [ ] Sortie 6C exit criteria met
- [ ] Decision OQ-9: `age` is never null. A stated age is given as stated; otherwise the model guesses from context, as exactly one of `child`, `adult`, `older adult`
- [ ] Readable input (read-only, outside this repo): `/Users/stovak/Projects/podcasts/granville/granville-2026SEP08.highland`. If it is missing, report REPLAN.

**Tasks**:
1. `Fixtures/Personaje/build-fixtures.py`: in `INSTRUCTIONS`, every field except `age` can be null and must be null when the excerpts say nothing about it. `age` is never null: give the age the excerpts state; if they state none, give a best guess from context as exactly one of `child`, `adult`, `older adult`. Keep "Do not guess or invent" for every other field.
2. Re-run `python3 Fixtures/Personaje/build-fixtures.py <script path>` to regenerate the nine prompts. Do not edit the `.txt` files by hand.
3. `Fixtures/Personaje/schema.json`: `age` becomes `"type": "string"` (not nullable), `maxLength` unchanged. Every other property stays nullable.
4. `Fixtures/Personaje/README.md`: state the rule and that it is Personaje's choice, carried by the prompt and the schema, not by the library.
5. `PersonajeAcceptanceTests.swift`: the per-prompt line `runPrompt` prints gains `age=<value>`. `testNinePromptsDecode` asserts, for each output, that `age` is not null and either contains a digit or, lowercased and trimmed, equals one of `child`, `adult`, `older adult`. The inline schema of `testConstrainedQueryOnDefaultModel` makes `age` non-nullable; its `52` assertion stays.
6. Test code and fixtures only. No change under `Sources/`: a non-nullable string property already exists in `BrujaJSONSchema`, and the library names no field.
7. If an output fails the task 5 assertion, revise the instruction wording once and re-run. If it fails again, stop and report REPLAN with the nine `age=` values from both runs.

**Exit criteria**:
- [ ] `python3 -c "import json;d=json.load(open('Fixtures/Personaje/schema.json'));p=d['properties'];assert p['age']['type']=='string';assert all('null' in p[k]['type'] for k in p if k!='age')"` exits 0
- [ ] `grep -c "older adult" Fixtures/Personaje/build-fixtures.py` ≥ 1 and `grep -l "older adult" Fixtures/Personaje/*.txt | wc -l` = 9
- [ ] `for f in Fixtures/Personaje/*.txt; do sed '/^=== EXCERPTS ===$/q' "$f" | shasum; done | sort -u | wc -l` = 1 (still one shared instruction block)
- [ ] Re-running `python3 Fixtures/Personaje/build-fixtures.py <script path>` after the commit leaves `git status --porcelain Fixtures/Personaje/*.txt` empty
- [ ] `make test-personaje` exits 0 with `testNinePromptsDecode`, `testHunterQuery` and `testConstrainedQueryOnDefaultModel` passed (not skipped), and its output has nine `age=` values, none of them `null`
- [ ] `git diff <sortie start commit>..HEAD --name-only | grep -c "^Sources/"` = 0
- [ ] `make test-ci` exits 0

### Amendment of 2026-10-04 (Sortie 6D, penalty off by default)

Sortie 6D raised REPLAN: at 1.1 the penalty took the nine-prompt total of null
fields from 19 to 33 (the guard allowed 28), and the baseline run showed no
looping (`maxWordRun` 1 and `duplicateItems` 0 on every line). OQ-7 is revised:
the parameter ships, off by default. The loop assertions stay as detectors. The
tasks and criteria below are the revised ones; the implementation of tasks 1–4
from the first attempt is saved at `.build/mission/sortie-6D-uncommitted.patch`.

### Sortie 6D: Repetition penalty on the constrained path

**Priority**: 22.25 — bounds make a looping answer decode; this stops the loop.

**Agent**: build lane.

**Entry criteria**:
- [ ] Sortie 6E exit criteria met
- [ ] Decision OQ-7 (revised 2026-10-04): the constrained path can apply a repetition penalty before the mask; it is off by default
- [ ] Confirmed in the resolved `mlx-swift-lm` (`bd4b7434`): `public struct RepetitionContext: LogitProcessor` with `init(repetitionPenalty:repetitionContextSize:)` at `Libraries/MLXLMCommon/Evaluate.swift:389-393`
- [ ] First action: extend the per-prompt line `runPrompt` prints with `maxWordRun=<n> duplicateItems=<n>`, then run `make test-personaje` once on the otherwise unmodified tree and keep the nine lines as the baseline. `maxWordRun` is the longest run of the same word in any string field (split on whitespace, lowercased, punctuation stripped). `duplicateItems` is the number of array items equal to an earlier item in the same array.

**Tasks**:
1. `BrujaJSONLogitProcessor` takes an optional `RepetitionContext`. `process(logits:)` applies the penalty first and the mask second, so a masked token stays at `-inf`. `prompt(_:)` and `didSample(token:)` are forwarded to it.
2. Add `repetitionPenalty: Float? = nil` to `query(_:schema:as:)` on `BrujaQuery` and `Bruja` (and to `generateConstrained`). `nil`, the default, applies no penalty. The context size is an internal constant, 64 tokens. The doc comment states that a penalty can push fields to `null` (measured: 19 to 33 null fields over nine prompts at 1.1).
3. Model-free tests in `BrujaJSONLogitProcessorTests.swift`: a masked token is still `-inf` with the penalty on; of two allowed tokens with equal logits, the one just sampled ends lower.
4. `testNinePromptsDecode` asserts, for each output, `maxWordRun` < 5 and `duplicateItems` = 0.
5. Run `make test-personaje` once with the default (no penalty). If an assertion from task 4 fails, stop and report REPLAN with the nine lines.

**Exit criteria**:
- [ ] `make test-ci` exits 0 with the two new processor tests passing
- [ ] `make test-personaje` exits 0 with `testNinePromptsDecode`, `testHunterQuery` and `testConstrainedQueryOnDefaultModel` passed (not skipped) — the last still finds `52`
- [ ] The nine per-prompt lines of the passing run are in the sortie report, each with `maxWordRun` < 5 and `duplicateItems` = 0
- [ ] `grep -c "repetitionPenalty: Float? = nil" Sources/SwiftBruja/Bruja.swift` = 1

### Sortie 6: Acceptance on the default model (Acceptance 1 and 4)

**Priority**: 17.75 — closes BR-P1 and BR-P4; nothing later builds on its code, only on it passing.

**Agent**: build lane.

**Already done at `32c3ff8`**: the fixture loader, `testNinePromptsDecode` and `testHunterQuery` exist, and `make build` prints no unhandled-resource warning. What follows is the remainder.

**Entry criteria**:
- [ ] Sortie 6D exit criteria met
- [ ] Sortie 2 exit criteria met: nine prompts and `schema.json` exist in `Fixtures/Personaje/`

**Tasks**:
1. `testHunterQuery` calls the public `Bruja.query(_:schema:as:)` (Acceptance 4 names the public entry point). `testNinePromptsDecode` keeps the internal `BrujaQuery.generateConstrained` + `decodeConstrained`, because it asserts on the raw text.
2. Run `make test-personaje` three times in a row. The tests run at temperature 0.3, so one pass proves little.
3. Test code only. If a run fails and no change to the test can fix it, report REPLAN with the failing output; do not edit `Sources/`.

**Exit criteria**:
- [ ] Three consecutive `make test-personaje` runs each exit 0 with `testNinePromptsDecode` and `testHunterQuery` passed (not skipped)
- [ ] `testNinePromptsDecode` asserts for each of the nine outputs: it decodes; the raw text ends with `}`; no string field equals `"null"`; the OQ-6 bounds hold; `age` is not null (OQ-9); `maxWordRun` < 5; `duplicateItems` = 0
- [ ] `awk '/func testHunterQuery/,/^  }/' Tests/BrujaIntegrationTests/PersonajeAcceptanceTests.swift | grep -c "Bruja.query("` ≥ 1
- [ ] `make build 2>&1 | grep -ci "unhandled"` = 0
- [ ] `make test-ci` exits 0

---

## WU3 — Peak memory (BR-P3)

The cause is not diagnosed, so this unit measures first. Sortie 8's fix cannot
be specified until Sortie 7 has numbers. If Sortie 8 finds the cause is inside
mlx-swift-lm or mlx-swift, the right outcome is REPLAN, not a workaround.

### Sortie 7: Peak-memory measurement harness

**Priority**: 18 — the harness Sorties 8 and 9 assert through; settles recon A-11, which nothing has measured through Bruja.

**Agent**: build lane.

**Entry criteria**:
- [ ] Sortie 6 exit criteria met
- [ ] Decision OQ-3: "peak" is MLX's `Memory.peakMemory`; the process physical footprint is printed beside it but never asserted on
- [ ] Verify first: `Memory.peakMemory` exists in the resolved `mlx-swift` under `DerivedData/SwiftBruja-*/SourcePackages/checkouts/mlx-swift/Source/MLX/Memory.swift`. Recon saw it only in a stale copy. If it is missing, report REPLAN.

**Tasks**:
1. Create `Tests/BrujaIntegrationTests/PersonajeMemoryTests.swift`, skipped unless the default model is present.
2. Add a helper that builds a synthetic prompt of a target token count (repeating plain English sentences, sized with the model's tokenizer to within 2% of the target). No fixture needed.
3. Add `testReportPeakMemory`: for 5,000 and 15,000 prompt tokens, reset the peak counter, run one `Bruja.queryWithMetadata` with `maxTokens: 256` on the default model, and print one line per run: `PEAK tokens=<n> mlx_bytes=<Memory.peakMemory> footprint_bytes=<task_vm_info phys_footprint>`. The model is loaded before the first reset, so both figures include the weights.
4. Add a `test-personaje-memory` Makefile target (unsandboxed host, same recipe, `-XCTest PersonajeMemoryTests`), its `.PHONY` entry and its help line; add the class to both `test-ci` skip lists.

**Exit criteria**:
- [ ] `make test-personaje-memory` exits 0 and `make test-personaje-memory 2>&1 | grep -c "^PEAK tokens="` = 2, each line with non-zero `mlx_bytes` and `footprint_bytes`
- [ ] `grep -c "XCTAssertLessThan\|XCTAssertLessThanOrEqual" Tests/BrujaIntegrationTests/PersonajeMemoryTests.swift` = 0 (this sortie only measures)
- [ ] `grep -c "skip-testing:BrujaIntegrationTests/PersonajeMemoryTests" Makefile` = 2
- [ ] `make test-ci` exits 0

### Amendment of 2026-10-04 (Sortie 8 withdrawn)

Sortie 7 measured, at 15,005 prompt tokens on the default model: MLX peak
active memory 5.70 GB, process footprint 20.70 GB, of which 16.29 GB is the MLX
buffer cache (5,001 tokens: 5.22 GB, 7.50 GB, 3.10 GB). The figure OQ-3 chose
already sits under 8 GB with no change, and the footprint is cache that Bruja
never limits or clears. The user's decision (OQ-3, revised): leave the footprint
as it is and add no memory gate. Sortie 8 is withdrawn and is not dispatched;
its text stays below as the record. Acceptance 3 is waived for this mission, and
issue #48 stays open. Sortie 9 follows Sortie 7 directly.

### Sortie 8 (WITHDRAWN — not dispatched): Peak under 8 GB at 15,000 tokens (Acceptance 3)

**Priority**: 13.5 — the one sortie whose fix is not known in advance; highest REPLAN risk in the mission.

**Agent**: build lane.

**Entry criteria**:
- [ ] Sortie 7 exit criteria met
- [ ] First action: run `make test-personaje-memory` on the unmodified tree and keep its two `PEAK` lines as the baseline
- [ ] Recon notes, to re-check in the resolved copy: `GenerateParameters.prefillStepSize` (default 512), `maxKVSize`, `kvBits`; `GPU.cacheLimit`; `GPU.clearCache()`. Today Bruja sets none of them (`BrujaQuery.swift:63-67`, `BrujaMemory.swift`).

**Tasks**:
1. Find where the peak comes from by varying one thing at a time under `test-personaje-memory`, one run each at 15,000 tokens: the MLX buffer cache limit, the prefill step size, the generation path (`ChatSession` versus `TokenIterator`). Four model runs at most, counting the baseline.
2. If one of the three, or a combination, brings the 15,000-token peak under 8 GB, apply it in `Sources/SwiftBruja/Core/` (`BrujaQuery.swift`, `BrujaMemory.swift`, `BrujaModelManager.swift`). Both the plain and the constrained query paths get it. If none does, stop and report REPLAN with the four `PEAK` lines; do not lower output quality (`kvBits`, `maxKVSize`) to reach the number.
3. Add `testFifteenThousandTokenPromptPeaksUnderEightGB` to `PersonajeMemoryTests.swift`, asserting `Memory.peakMemory` < 8 × 1024³ bytes on the default model, on both query paths (the constrained path uses the Personaje schema declared inline).
4. Record the cause and the before/after numbers in a code comment at the fix site.

**Exit criteria**:
- [ ] `make test-personaje-memory` exits 0 with `testFifteenThousandTokenPromptPeaksUnderEightGB` passed (not skipped)
- [ ] `make test-personaje` exits 0 (constrained output still decodes)
- [ ] `make test-ci` exits 0
- [ ] [judgment] The comment at the fix site names one specific cause and gives the measured before and after peaks; a reader can tell which change produced the drop

### Sortie 9: Unload releases memory

**Priority**: 9 — Personaje's job queue needs it; nothing but the thinking switch and the docs follow.

**Agent**: build lane.

**Entry criteria**:
- [ ] Sortie 7 exit criteria met (Sortie 8 is withdrawn)
- [ ] Decision OQ-4: clean unload means MLX active memory returns to within 256 MB of its pre-load value

**Tasks**:
1. Make `BrujaModelManager.unloadModel(_:)` and `unloadAllModels()` (`Sources/SwiftBruja/Core/BrujaModelManager.swift:101-108`) drop the container, drop the cached vocabulary table from Sortie 5, and clear the MLX buffer cache.
2. Add public `Bruja.unloadModel(_:)` and `Bruja.unloadAllModels()` so Personaje's job queue can call them without reaching into the manager.
3. Add `testUnloadReleasesMemory` to `PersonajeMemoryTests.swift`: call `unloadAllModels()` first (other tests in the class leave the model loaded), record MLX active memory as the starting value, load and query the default model, unload, assert active memory ≤ starting value + 256 × 1024² bytes.
4. Add `testReloadAfterUnloadAnswers`: load, query, unload, query again; assert a non-empty second response.

**Exit criteria**:
- [ ] `make test-personaje-memory` exits 0 with `testUnloadReleasesMemory` and `testReloadAfterUnloadAnswers` passed (not skipped)
- [ ] `grep -c "public static func unloadModel\|public static func unloadAllModels" Sources/SwiftBruja/Bruja.swift` = 2
- [ ] `make test-ci` exits 0 (the existing `unloadModel` unit tests at `Tests/SwiftBrujaTests/SwiftBrujaTests.swift:359-365` still pass)

---

## WU4 — Thinking switch (BR-P2)

Library switch only. A `bruja` CLI flag is not in the requirements and is not planned.

### Sortie 10: `thinking:` parameter on the query APIs (Acceptance 2)

**Priority**: 7.25 — only matters for retesting Qwen3.5-9B; the requirements put it last.

**Agent**: build lane.

**Entry criteria**:
- [ ] Sortie 9 exit criteria met
- [ ] Recon A-07: Qwen3.5-9B's `chat_template.jinja` reads `enable_thinking`; the model is on disk
- [ ] Verify first: in the resolved `mlx-swift-lm`, `ChatSession` accepts `additionalContext:` and `UserInput` carries `additionalContext` into the chat template. Recon saw this only in a stale copy. If the context does not reach the template, report REPLAN.

**Tasks**:
1. Add `public enum BrujaThinking: Sendable { case modelDefault, off }` to `Sources/SwiftBruja/Core/BrujaTypes.swift`.
2. Add a `thinking: BrujaThinking = .modelDefault` parameter to `query`, `queryWithMetadata`, `query(as:)` and `query(_:schema:as:)` in `BrujaQuery` and `Bruja`. `.off` passes `["enable_thinking": false]` as the template's additional context; `.modelDefault` passes nothing, so every existing call site behaves as before.
3. Add a model-free unit test, `Tests/SwiftBrujaTests/BrujaThinkingTests.swift`, for the mapping from `BrujaThinking` to the additional-context dictionary.
4. Add `testQwen35AnswersWithThinkingOff` to `PersonajeAcceptanceTests.swift`: on `mlx-community/Qwen3.5-9B-MLX-4bit`, `maxTokens: 512`, `thinking: .off`; assert the response is non-empty and contains neither `<think>` nor `</think>`. The test skips on its own model check, separate from the class-level one.

**Exit criteria**:
- [ ] `make build` exits 0 and `make test-ci` exits 0, its output showing `BrujaThinkingTests` ran
- [ ] `make test-personaje` exits 0 with `testQwen35AnswersWithThinkingOff` passed (not skipped)
- [ ] `grep -c "thinking: BrujaThinking" Sources/SwiftBruja/Bruja.swift` = 4

---

## WU5 — Documentation

### Sortie 11: Document the new API

**Priority**: 1.5 — blocks nothing; describes an API that must be final first.

**Agent**: build lane (edits a doc comment in `Sources/`, so it ends on `make build`).

**Entry criteria**:
- [ ] Sortie 10 exit criteria met

**Tasks**:
1. `AGENTS.md`: add `query(_:schema:as:)` with its `repetitionPenalty` parameter (off by default, and why), `BrujaJSONSchema` with its `maxLength` / `maxItems` bounds (and that an unbounded schema can still end in `structuredOutputTruncated`), `BrujaThinking`, `Bruja.unloadModel`, and the `test-personaje` / `test-personaje-memory` targets with their prerequisites (models on disk), the figures Sortie 7 measured (MLX peak, footprint and cache at 5,000 and 15,000 tokens) with a note that Bruja sets no MLX cache limit, and the `Fixtures/Personaje/` directory.
2. `README.md`: one usage example of a constrained query with a nullable field and `thinking: .off`.
3. `CHANGELOG.md`: a new top section for our next minor release version — the version the `-dev` marker on `development` names — in the file's existing `## [x.y.z] - date` format, listing BR-P1 (#49), BR-P2 (#50) and, for BR-P3 (#48), what shipped: the unload API and the `test-personaje-memory` measurement target. It states that #48 is not closed by this release: the long-prompt footprint is unchanged.
4. Update the doc comment on the old `query(as:)` (`Sources/SwiftBruja/Bruja.swift:145-158`) to point at the constrained overload.

**Exit criteria**:
- [ ] `grep -c "BrujaJSONSchema" AGENTS.md README.md CHANGELOG.md` shows ≥ 1 in each file
- [ ] `grep -c "maxLength" AGENTS.md` ≥ 1 and `grep -c "repetitionPenalty" AGENTS.md` ≥ 1
- [ ] `grep -c "#48" CHANGELOG.md`, `grep -c "#49" CHANGELOG.md` and `grep -c "#50" CHANGELOG.md` are each ≥ 1
- [ ] `make build` exits 0
- [ ] [judgment] The README example compiles as written against the API in `Sources/SwiftBruja/Bruja.swift` (argument labels and order match)

---

## Parallelism Structure

**Critical Path**: Sortie 1 → 3 → 4 → 5 → 6A → 6B → 6C → 6E → 6D → 6 → 7 → 9 → 10 → 11 (length: 14 sorties; Sortie 8 withdrawn; 3 remain after Sortie 7)

**Parallel Execution Groups**:
- **Group 1** (done):
  - WU1 Sortie 1 — build lane
  - WU1 Sortie 2 — sub-agent 1, **NO BUILD**
- **Group 2** (done; sequential, build lane): Sorties 3, 4, 5
- **Group 3** (sequential, build lane): Sorties 6A, 6B, 6C, 6E, 6D, 6
- **Group 4** (sequential, build lane): Sorties 7, 9, 10, 11 (Sortie 8 withdrawn)

Nothing that remains can run beside anything else. Sorties 6A–6D each need a
model-backed run to prove their exit criteria, and 6A, 6C and 6D edit the same
three files (`BrujaJSONAcceptor.swift`, `BrujaJSONLogitProcessor.swift`,
`BrujaQuery.swift`).

**Agent Constraints**:
- **Build lane**: one sortie at a time; every sortie except Sortie 2 runs a `make` build or test target.
- **Sub-agents**: one is used (Sortie 2). It runs no build and touches only `Fixtures/Personaje/`.
- Sorties 1 and 2 share a working tree: Sortie 1 owns `Tests/` and `Makefile`, Sortie 2 owns `Fixtures/Personaje/`, and each stages by path.

**Why not more**: Sorties 3–10 all compile, and Sorties 5, 8, 9 and 10 edit the same two files (`BrujaQuery.swift`, `Bruja.swift`). Sortie 7 could be written beside WU2, but it needs the build lane to prove anything.

## Local Dependency Map

<!-- Carried from RECON_REPORT.md. Sortie agents may read these paths; they may not edit them. -->

`Package.resolved` is gitignored, so CI resolves each range fresh.

| Dependency | Resolved version | Local checkout | Status |
|------------|------------------|----------------|--------|
| intrusive-memory/SwiftAcervo | local path (4 commits past `v0.25.0`, `13e2879b165d`) | `/Users/stovak/Projects/package-collection/pkg/SwiftAcervo` | SIBLING_ACTIVE |
| ml-explore/mlx-swift | `0.31.6` (`0bb916c67f4b`) | — | NO_LOCAL_CHECKOUT |
| ml-explore/mlx-swift-lm | `3.31.4` (`bd4b7434e6bd`) | — | NO_LOCAL_CHECKOUT |
| huggingface/swift-transformers | `1.3.3` (`2fa33e1f5e71`) | — | NO_LOCAL_CHECKOUT |
| apple/swift-argument-parser | `1.8.2` (`6a52f3251125`) | — | NO_LOCAL_CHECKOUT |

- `.build/checkouts/mlx-swift` and `.build/checkouts/mlx-swift-lm` are stale (not at the pinned revisions). Do not read them. After `make resolve`, read `~/Library/Developer/Xcode/DerivedData/SwiftBruja-*/SourcePackages/checkouts/<dep>` instead.
- SwiftAcervo builds from the sibling checkout here and from the released tag in CI. Use no Acervo API that is absent at `v0.25.0`.

## Open Questions

<!-- Consumed by Pass 1 of refine (`refine-blockers`). -->

_No blocking open questions remain. OQ-1 to OQ-4 were resolved by the user on 2026-10-03 before the start; OQ-5 to OQ-8 came out of the Sortie 6 REPLAN and were resolved the same day (recommendations accepted); OQ-9 came out of the Sortie 6C REPLAN and was decided by the user on 2026-10-04._

| ID | Question | Decision |
|----|----------|----------|
| OQ-1 | Where do the nine prompts and the HUNTER prompt come from? | Rebuild them from the Granville script and commit them to this repo in `Fixtures/Personaje/` (Sortie 2). The originals were not kept, so the set is a reconstruction. |
| OQ-2 | Which constraint engine? | Token-mask `LogitProcessor` driven by a JSON-schema state machine, limited to the shapes Personaje sends. No new dependency. |
| OQ-3 | What number is "peak under 8 GB"? | Revised 2026-10-04: none is asserted. Sortie 7's harness prints MLX `Memory.peakMemory` and the process physical footprint; the footprint (20.70 GB at 15,005 tokens, mostly MLX buffer cache) is left as it is and no memory gate is added. Sortie 8 withdrawn; Acceptance 3 waived. |
| OQ-4 | How much memory must come back after unload? | MLX active memory within 256 MB of its pre-load value. |
| OQ-5 | How does constrained output get a guaranteed end? | Optional `maxLength` and `maxItems` in `BrujaJSONSchema`, enforced by the acceptor and the logit processor (Sortie 6A). |
| OQ-6 | What are Personaje's bounds? | 500 characters for top-level strings, 200 for strings inside array items, 8 items per array; `maxTokens: 4096` in the acceptance tests (Sortie 6B). The bounds live in the fixture schema, not in the library. |
| OQ-7 | Is the repetition itself in scope? | Yes, as a detector and an optional control. The acceptance test asserts no duplicate array items and no word repeated five times running. A repetition penalty applied before the mask is available but off by default (revised 2026-10-04: at 1.1 it raised null fields from 19 to 33 over the nine prompts, and the baseline showed no loop) (Sortie 6D). |
| OQ-8 | Is `"age":null` on every output a defect this mission fixes? | Yes. Measure the logits first, then fix or REPLAN (Sortie 6C). |
| OQ-9 | What does `age` hold when the excerpts state none? | Never null. A guess from context, exactly one of `child`, `adult`, `older adult`; a stated age is given as stated. Carried by Personaje's prompt and schema (Sortie 6E), not by the library. |

## Open Questions & Missing Documentation

### Unresolved Items (must address before execution)

_None._

### Resolved during refine (2026-10-03)

| Sortie | Issue Type | Description | Resolution |
|--------|-----------|-------------|------------|
| 5 | Missing prerequisite | The test named the 0.5B fixture model, which is not on disk; "passed (not skipped)" could not be met without a download | Test moved to the default model; no sortie downloads a model |
| 2, 6 | Missing doc | `schema.json` had no way to carry property order, which `BrujaJSONSchema` needs and Swift JSON parsing drops | `propertyOrder` arrays added to the file's shape; the test loader reads them |
| 3, 4 | Missing spec | The per-state mask cache needs a `Hashable` state that does not grow with the text | Stated in Sortie 3 with a test |
| 4, 5 | Missing spec | Byte-level vocabularies hold partial-UTF-8 tokens that decode to U+FFFD | Always masked; limit documented; round-trip test added in Sortie 5 |
| 2 | Vague criterion | "First 400 bytes identical" depended on the block's length | Replaced by a marker line and a hash comparison |
| 2 | Vague criterion | `git status` check on `Sources Tests` fails while Sortie 1 edits `Tests/` in the same tree | Replaced by a staged-paths check |
| 5 | Vague criterion | "No removed lines inside the existing bodies" | Replaced by a removed-line count of 0 for the file |
| 5, 6 | Missing specific | No `maxTokens` on the constrained acceptance runs | Set to 2048 |
| 7 | Vague criterion | "Makes no threshold assertion" | Replaced by a grep count |
| 8 | Vague entry criterion | "PEAK lines are in the completion record" | Sortie 8 re-runs the baseline itself |
| 8 | Unbounded task | Diagnosis had no run limit and no stop rule | Four runs at most; REPLAN if none of the three levers reaches 8 GB |
| 9 | Vague criterion | Starting value for the unload test depended on test order | Unload first, then record |
| 11 | Missing specific | "An entry under our next minor release version" had no heading to go under | New top section in the file's existing format |

### Resolved during the replan refine (2026-10-03)

| Sortie | Issue Type | Description | Resolution |
|--------|-----------|-------------|------------|
| 6 | Plan defect (REPLAN) | Validity-only engine cannot guarantee the object closes inside `maxTokens` | Sorties 6A (bounds), 6B (fixture bounds), 6D (repetition penalty) |
| 5, 6 | Uncovered defect | `"age":null` in 43 of 43 outputs; no criterion looked at content | Sortie 6C, with an assertion on the stated age |
| 6 | Vague criterion | One passing run at temperature 0.3 was taken as proof | Three consecutive runs |
| 6 | Task/criterion mismatch | Tasks said `Bruja.query(_:schema:as:)`; the raw-text assertions need the internal call | `testHunterQuery` uses the public API; `testNinePromptsDecode` keeps the internal one |
| 6A | Missing spec | A length counter inside the cached state would defeat the mask cache | Counter kept beside `State`; throughput floor in the exit criteria |
| 6A–6D | Missing tool | No way to run one model-backed test | `ONLY=` variable on `test-personaje` |
| 11 | Coverage | Docs sortie did not know about bounds or the penalty | Added to its tasks and criteria |

### Resolved after the Sortie 6C REPLAN (2026-10-04)

| Sortie | Issue Type | Description | Resolution |
|--------|-----------|-------------|------------|
| 6C | Plan defect (REPLAN) | The no-special-casing grep covered `BrujaJSONSchema.swift`, whose doc comments name `age`, so it printed 1 before the sortie began | Grep scoped to the acceptor, logit processor and query files |
| 6C, 6 | Uncovered behaviour | With the mask fixed, all nine fixture prompts still return a null `age`: no excerpt states one and the prompt forbids guessing | OQ-9 and Sortie 6E |
| 6D | Plan defect (REPLAN) | A 1.1 penalty on every token pushed whole fields to `null` and failed the sortie's own guard; the baseline had no loop to stop | OQ-7 revised: parameter ships with default `nil`; guard and 1.2 retry removed; loop assertions kept |
| 8 | Plan defect (found by Sortie 7) | The asserted figure (MLX peak) is already under 8 GB; the footprint BR-P3 describes is MLX buffer cache | User decision: leave the footprint, no memory gate. Sortie 8 withdrawn; Sortie 9 follows Sortie 7; Sortie 11 documents the measured figures |

## Summary

| Metric | Value |
|--------|-------|
| Work units | 5 |
| Total sorties | 16 (12 complete, 1 withdrawn, 3 not started) |
| Open questions | 0 |
| Dependencies mapped | 5 |
| Dependency structure | layers (0 → 4); build lane sequential |
| Critical path | 14 sorties, 3 remaining |
| Agents | build lane only for what remains |
| Refined | 2026-10-03 (5 passes), and again the same day after the Sortie 6 REPLAN (5 passes). Amended 2026-10-04 after the Sortie 6C REPLAN (one criterion, Sortie 6E, OQ-9) and after the Sortie 6D REPLAN (OQ-7 revised), and after Sortie 7's measurements (OQ-3 revised, Sortie 8 withdrawn); not re-run through the five passes |
