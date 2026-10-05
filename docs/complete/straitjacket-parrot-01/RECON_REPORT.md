---
type: recon-report
state: completed
updated: 2026-10-04
mission: straitjacket-parrot-01
requirements_file: REQUIREMENTS-personaje.md
requirements_sha256: 17954707a0a7180a8e83719249e572ad63148a9aa03412c84035f30b67128845
project_head: 7f902aac8cf5f8ef71b07c3275afec4fb6341762
search_root: ~/Projects
generated: 2026-10-03
verdict: CLEAR
---

# RECON_REPORT.md — SwiftBruja (Personaje requirements)

## Terminology

> **Mission** — A definable, testable scope of work.
> **Sortie** — An atomic, testable unit of work executed by a single agent in one dispatch.
> **Work Unit** — A grouping of sorties.

## Verdict

**CLEAR** — 12 assumptions checked, 8 confirmed, 0 blocking, 4 unverifiable.

Method note: the hub verified all claims inline (12 claims, 5 files) instead of
dispatching spokes. Every `CONFIRMED` below carries a `file:line` or a command
and its output.

## Assumption Findings

| ID | Kind | Claim | Locus | Verdict | Evidence |
|----|------|-------|-------|---------|----------|
| A-01 | A-API | `query(as:)` exists in `BrujaQuery.swift:89-114` | repo | CONFIRMED | `Sources/SwiftBruja/Core/BrujaQuery.swift:89-115` |
| A-02 | A-BEHAVIOR | `query(as:)` asks for JSON in the system prompt and parses whatever comes back (`:140-190`) | repo | CONFIRMED | prompt suffix `BrujaQuery.swift:98-104`; `parseJSON` `:147-162`; `cleanJSONResponse` `:165-193` (takes first `{` to last `}`) |
| A-03 | A-BEHAVIOR | The model must already be in Acervo's shared models directory (`:121-135`) | repo | CONFIRMED | `BrujaQuery.swift:133-137` (`Acervo.isModelConfigPresent`, else `modelNotFound`) |
| A-04 | A-FILE | Qwen2.5-7B-Instruct-4bit appears in source only as a historical comment (`AgentBackendSelector.swift:30`) | repo | CONFIRMED | `Sources/SwiftBruja/Agent/AgentBackendSelector.swift:30`; `grep -rn "Qwen2.5-7B" Sources Tests Makefile` returns that line only |
| A-05 | A-CONFIG | Package is macOS-only, `.macOS(.v26)` | repo | CONFIRMED | `Package.swift:52` |
| A-06 | A-API | `Bruja.query(as:)` is the public entry point | repo | CONFIRMED | `Sources/SwiftBruja/Bruja.swift:159-175` |
| A-07 | A-BEHAVIOR | Qwen3.5-9B has a thinking mode that can be switched off | data | CONFIRMED | `grep enable_thinking "<SharedModels>/mlx-community_Qwen3.5-9B-MLX-4bit/chat_template.jinja"` → `enable_thinking is defined and enable_thinking is false` |
| A-08 | A-DATA | Qwen2.5-7B-Instruct-4bit can be present in Acervo's shared models directory | data | CONFIRMED | `ls "<SharedModels>/mlx-community_Qwen2.5-7B-Instruct-4bit"` → `config.json`, `model.safetensors` (4,284,346,255 bytes), `.acervo-manifest.json`; `config.json:14` `"model_type": "qwen2"`, `:20` `"bits": 4`. CDN manifest list also carries it: `../acervo-manifests/models/mlx-community_Qwen2.5-7B-Instruct-4bit/manifest.json` (`6788c0d`, 2026-08-15) |
| A-09 | A-DATA | "The nine prompts" (Acceptance 1) exist as a rerunnable set | external | UNVERIFIABLE | Not in this repo. Not tracked in Personaje (`git -C ~/Projects/apps/Personaje ls-files` lists no prompt or output files). Only the prose result survives: `Personaje/docs/REQUIREMENTS-APP-UI.md:466-468` |
| A-10 | A-DATA | A "HUNTER query" (Acceptance 4; 14,944 tokens) exists as a prompt | external | UNVERIFIABLE | Same search as A-09. The source script exists at `~/Projects/podcasts/granville/granville-2026SEP08.highland`; the prompt built from it does not |
| A-11 | A-BEHAVIOR | Peak memory is 10 GB at 5,000 tokens and 25.7 GB at 28,000 tokens through Bruja | repo | UNVERIFIABLE | Needs a model run; recon runs none. How the figures were measured is not stated |
| A-12 | A-CONFIG | Issues #48, #49, #50 are open | external | UNVERIFIABLE | Offline pass. Does not change the plan |

`<SharedModels>` = `~/Library/Group Containers/group.intrusive-memory.models/SharedModels`.

### Blocking findings

None.

## Local Dependency Map

`Package.resolved` is gitignored (`.gitignore:25`), so CI resolves every range
fresh. The "Resolved" column is this machine's `Package.resolved` (2026-08-01).

| Dependency | Declared | Resolved | Local checkout | Local HEAD | Status |
|------------|----------|----------|----------------|-----------|--------|
| intrusive-memory/SwiftAcervo | `sibling(from: 0.25.0)` | local path `../SwiftAcervo` | `~/Projects/package-collection/pkg/SwiftAcervo` | `13e2879b165d` (`development`, 4 commits past `v0.25.0`, 1 untracked file) | SIBLING_ACTIVE |
| ml-explore/mlx-swift | `from: 0.31.3` | `0.31.6` (`0bb916c67f4b`) | — | — | NO_LOCAL_CHECKOUT |
| ml-explore/mlx-swift-lm | `from: 3.31.3` | `3.31.4` (`bd4b7434e6bd`) | — | — | NO_LOCAL_CHECKOUT |
| huggingface/swift-transformers | `from: 1.3.3` | `1.3.3` (`2fa33e1f5e71`) | — (resolved copy `.build/checkouts/swift-transformers` matches pin) | — | NO_LOCAL_CHECKOUT |
| apple/swift-argument-parser | `from: 1.7.1` | `1.8.2` (`6a52f3251125`) | — (resolved copy `.build/checkouts/swift-argument-parser` matches pin) | — | NO_LOCAL_CHECKOUT |

### Drift and ambiguity notes

- **SwiftAcervo is SIBLING_ACTIVE and 4 commits ahead of `v0.25.0`.** This
  machine builds different Acervo source than CI. The two Acervo symbols the
  requirements rest on exist at the tag: `isModelConfigPresent`
  (`v0.25.0:Sources/SwiftAcervo/Acervo+Availability.swift:133`) and
  `sharedModelsDirectory` (`v0.25.0:Sources/SwiftAcervo/Acervo+PathResolution.swift:153`).
  No finding rests on local-only Acervo code.
- **`.build/checkouts` is stale for the MLX packages.** `mlx-swift` is at
  `61b9e011e09a` and `mlx-swift-lm` at `1c05248bb089`; neither equals its pin,
  and their git alternates point at a path that no longer exists
  (`/Users/stovak/Projects/SwiftBruja/.build/repositories/…`). There is no
  `DerivedData/SwiftBruja-*/SourcePackages` on this machine. So there is no
  trustworthy copy of mlx-swift-lm 3.31.4 on disk.
- **The requirements make no claim about mlx-swift-lm.** The plan will, though.
  What the stale copy shows, to be re-checked by the first sortie that uses it
  (after `make resolve` produces a current copy):
  - `LogitProcessor` protocol with `process(logits:)` — `Libraries/MLXLMCommon/Evaluate.swift:34`
  - `TokenIterator.init(input:model:cache:processor:sampler:prefillStepSize:)` — `Evaluate.swift:616-618`
  - `GenerateParameters.prefillStepSize`, `maxKVSize`, `kvBits` — `Evaluate.swift:57-67`
  - `ChatSession.additionalContext` — `Libraries/MLXLMCommon/ChatSession.swift:34`
  - No grammar or JSON-schema constraint engine anywhere in `Libraries/`
  - `Memory.peakMemory`, `GPU.clearCache()`, `GPU.cacheLimit` — `mlx-swift/Source/MLX/Memory.swift:134`, `GPU+Metal.swift:76,170`

## Unverifiable

| ID | Claim | Why | What would settle it |
|----|-------|-----|----------------------|
| A-09 | The nine prompts exist | Not on disk in either repo | The path to the prompts and outputs, or a decision to rebuild them from the Granville script |
| A-10 | The HUNTER prompt exists | Same | Same |
| A-11 | 10 GB / 25.7 GB peaks through Bruja | Needs a model run; metric unstated | A baseline measurement sortie, and the metric Personaje used |
| A-12 | Issues #48–#50 are open | Offline pass | `gh issue view 48 49 50` |

## Handoff to breakdown

- `CONFIRMED` facts are safe as sortie entry criteria without re-checking.
- A-09 and A-10 become an Open Question (they decide what the acceptance sorties run).
- A-11 becomes the first memory sortie's job (measure the baseline) plus an Open Question on the metric.
- A-12 is not carried; it changes nothing.
- The mlx-swift-lm notes above become explicit verification steps in the entry
  criteria of the sorties that depend on them.
