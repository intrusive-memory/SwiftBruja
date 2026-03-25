# SUPERVISOR_STATE.md

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

## Mission Metadata

- **Operation**: OPERATION MANIFEST AIRDROP
- **Starting point commit**: 6ece982a615ce54ba75f3e4d1cd43159b49ec133
- **Mission branch**: mission/manifest-airdrop/01
- **Iteration**: 1
- **Max retries**: 3

## Plan Summary

- Work units: 1
- Total sorties: 2
- Dependency structure: parallel (both sorties are Layer 1, independent)
- Dispatch mode: dynamic

## Work Units

| Name | Directory | Sorties | Dependencies |
|------|-----------|---------|-------------|
| SwiftBruja | `/Users/stovak/Projects/SwiftBruja` | 2 | none |

---

### SwiftBruja

- Work unit state: RUNNING
- Current sortie: 1 and 2 (parallel)
- Sortie 1 state: DISPATCHED
- Sortie 1 type: code
- Sortie 1 model: sonnet
- Sortie 1 complexity score: 11
- Sortie 1 attempt: 1 of 3
- Sortie 2 state: DISPATCHED
- Sortie 2 type: code
- Sortie 2 model: haiku
- Sortie 2 complexity score: 4
- Sortie 2 attempt: 1 of 3
- Last verified: N/A
- Notes: Both sorties dispatching in parallel

## Active Agents

| Work Unit | Sortie | Sortie State | Attempt | Model | Complexity Score | Task ID | Output File | Dispatched At |
|-----------|--------|-------------|---------|-------|-----------------|---------|-------------|---------------|
| SwiftBruja | 1 | DISPATCHED | 1/3 | sonnet | 11 | a9c512251779b7114 | /private/tmp/claude-501/-Users-stovak-Projects-SwiftBruja/b0312f73-e0f8-4399-a5ae-edc878c8e851/tasks/a9c512251779b7114.output | 2026-03-25T00:00:00Z |
| SwiftBruja | 2 | DISPATCHED | 1/3 | haiku | 4 | affc621ca7c0ec633 | /private/tmp/claude-501/-Users-stovak-Projects-SwiftBruja/b0312f73-e0f8-4399-a5ae-edc878c8e851/tasks/affc621ca7c0ec633.output | 2026-03-25T00:00:00Z |

## Decisions Log

| Timestamp | Work Unit | Sortie | Decision | Rationale |
|-----------|-----------|--------|----------|-----------|
| 2026-03-25T00:00:00Z | SwiftBruja | 1 | Model: sonnet | Complexity score 11 (external API patterns for HuggingFace + R2, YAML complexity) |
| 2026-03-25T00:00:00Z | SwiftBruja | 2 | Model: haiku | Complexity score 4 (simple edit + file deletion, all machine-verifiable exit criteria) |
