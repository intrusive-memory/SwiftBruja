---
type: requirements
state: draft
updated: 2026-10-03
origin: intrusive-memory/Personaje @ 74721c3 (docs/REQUIREMENTS-APP-UI.md UD11, UD13, UD18, §11; RECON_REPORT.md)
sequence: 1 — independent; only needed for Personaje's last build step (Auto-generate, local client)
---

# SwiftBruja — what Personaje needs

SwiftBruja is Personaje's on-device LLM client. Each call asks for one JSON
object in a fixed schema (the Profile tab's fields) and nothing else. Three
open issues stand between today's `query(as:)` and that.

## Requirements

| ID | Issue | Requirement | Evidence |
|----|-------|-------------|----------|
| BR-P1 | [#49](https://github.com/intrusive-memory/SwiftBruja/issues/49) | **Schema-constrained output that stops at the end of the object.** Today `query(as:)` asks for JSON and parses what comes back (`BrujaQuery.swift:89-114,140-190`). | 4 of 9 test outputs were unusable: the text "null" for null, a wrong shape, text after the closing brace. |
| BR-P2 | [#50](https://github.com/intrusive-memory/SwiftBruja/issues/50) | **A switch to turn a model's thinking mode off.** | Qwen3.5-9B spends the whole token budget reasoning and returns no answer. |
| BR-P3 | [#48](https://github.com/intrusive-memory/SwiftBruja/issues/48) | **Lower peak memory on long prompts.** Cause not diagnosed. | 5,000-token prompt: 10 GB here, 5 GB in Python MLX. 28,000 tokens: 25.7 GB here, 7.4 GB there. |
| BR-P4 | — | **Confirm the default model runs through Bruja.** Qwen2.5-7B-Instruct 4-bit must be present in Acervo's shared models directory (`BrujaQuery.swift:121-135`). In source it's only a historical comment (`AgentBackendSelector.swift:30`); Personaje's measurements used Python MLX, not Bruja. | RECON U-03 |

All three issues were open on 2026-10-03.

## What Personaje sends

- One query per character; the whole script is never one prompt.
- Major characters: 6,100–13,200 tokens. Minor: 170–2,400 tokens.
- Schema: `age`, `pronouns`, `occupation`, `languages`, `logline`,
  `sampleLine`, `appearance`, `wardrobe`, `personality`, `backstory`, `arc`,
  `relationships[{with, nature}]`, `voiceAndSpeech`, `canonFacts[{fact, quote}]`.
  Every field nullable; only the empty ones are requested.
- Runs are jobs in a per-machine queue shared with the image engine, so the
  model must load and unload cleanly between jobs.

## Acceptance

1. With BR-P1, the nine prompts that produced unusable output all decode, with
   JSON `null` for null and nothing after the closing brace.
2. With BR-P2, Qwen3.5-9B returns an answer inside the token budget.
3. BR-P3: a 15,000-token prompt on Qwen2.5-7B 4-bit peaks under 8 GB. (Target
   chosen so the local client works on a 16 GB Mac; Python MLX measured 5.4 GB.)
4. BR-P4: one HUNTER query through `Bruja.query(as:)` on the default model.

## Order within this repo

BR-P4 first (it's a check, and may show the default model has to be shipped to
the CDN). Then BR-P1, which Personaje can't work without. BR-P3 decides the
minimum Mac. BR-P2 only matters for retesting Qwen3.5-9B.

## Depends on

Nothing. (If BR-P4 finds the model missing, an `acervo ship` precedes it.)

## Blocks

- **Personaje Auto-generate, local client** (APP-UI §1 step 5). The Claude API
  client doesn't need any of this, so Auto-generate can ship on that client
  alone first.

## Platform

SwiftBruja is macOS-only (`.macOS(.v26)`). Personaje v1 is macOS only.
