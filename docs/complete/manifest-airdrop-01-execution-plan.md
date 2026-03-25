---
feature_name: OPERATION MANIFEST AIRDROP
starting_point_commit: 6ece982a615ce54ba75f3e4d1cd43159b49ec133
mission_branch: mission/manifest-airdrop/01
iteration: 1
---

# EXECUTION_PLAN.md — SwiftBruja CDN Model Distribution

## Terminology

> **Mission** — A definable, testable scope of work. Defines scope, acceptance criteria, and dependency structure.

> **Sortie** — An atomic, testable unit of work executed by a single autonomous AI agent in one dispatch. One aircraft, one mission, one return.

> **Work Unit** — A grouping of sorties (package, component, phase).

---

## Source Requirements

- **Document**: `REQUIREMENTS.md`
- **R1**: GitHub Actions workflow to upload model to R2 CDN with SwiftAcervo-compatible manifest
- **R2**: Pass empty `files` array to `Acervo.ensureAvailable()` so all manifest files are downloaded
- **R3**: No changes to SwiftAcervo (confirmed — download path already works)
- **R4**: Workflow must be idempotent (skip if manifest exists; clean re-run on partial failure)
- **R5**: Default model constant as single source of truth (comment in workflow referencing Swift constant)

---

## Work Units

| Work Unit | Directory | Sorties | Layer | Dependencies |
|-----------|-----------|---------|-------|-------------|
| SwiftBruja | `/Users/stovak/Projects/SwiftBruja` | 2 | 1 | none |

---

## Sortie Definitions

### Sortie 1: Create CDN Upload Workflow

**Priority**: 2.84 — Higher risk (external API patterns for HuggingFace + R2, YAML complexity), but independent

**Agent allocation**: Sub-agent (sonnet) — no build step required

**Estimated effort**: 18 turns (36% of 50-turn budget)

**Entry criteria**:
- [ ] First sortie — no prerequisites

**Tasks**:
1. Create `.github/workflows/ensure-model-cdn.yml` with `workflow_dispatch` and `push` (on self-change to `main`) triggers
2. Add CDN idempotency check step: HTTP GET `{CDN_BASE}/models/{slug}/manifest.json` — if HTTP 200, skip remaining steps (R4)
3. Implement sequential shard processing: for each file, download from HuggingFace API → compute SHA-256 → upload to R2 via `aws s3 cp` → delete local copy (stays within ~14 GB runner disk limit)
4. Generate `manifest.json` in SwiftAcervo `CDNManifest` v1 format: `manifestVersion`, `modelId`, `slug`, `updatedAt`, `files[]` (path, sha256, sizeBytes), `manifestChecksum` (SHA-256 of sorted concatenated file checksums)
5. Upload `manifest.json` to R2 at `models/mlx-community_Qwen3-Coder-Next-4bit/manifest.json`
6. Add post-upload verification step: fetch manifest from CDN, validate file count matches expected
7. Add comment in workflow `env:` block referencing `BrujaModelManager.defaultModel` as the source of truth for the model ID (R5)

**Exit criteria**:
- [ ] File `.github/workflows/ensure-model-cdn.yml` exists
- [ ] Workflow YAML is syntactically valid (parseable by `python3 -c "import yaml; yaml.safe_load(open(...))"` or equivalent)
- [ ] Workflow contains `workflow_dispatch` trigger
- [ ] Workflow contains CDN existence check before any download/upload steps
- [ ] Workflow generates `manifest.json` with `manifestVersion: 1` format
- [ ] Workflow processes files sequentially (download → hash → upload → delete) to fit standard runner disk limits
- [ ] Workflow env block contains comment referencing Swift constant

---

### Sortie 2: Update Swift Code to Download All Manifest Files

**Priority**: 1.75 — Low risk (simple edit + file deletion), straightforward

**Agent allocation**: Supervising agent — has `make build` verification step

**Estimated effort**: 14 turns (28% of 50-turn budget)

**Entry criteria**:
- [ ] First sortie — no prerequisites (independent of Sortie 1)

**Tasks**:
1. In `Sources/SwiftBruja/Core/BrujaDownloadManager.swift`: change `files: LLMModelFiles.required` to `files: []` in the `downloadModel()` method (line 38)
2. Delete `Sources/SwiftBruja/Core/LLMModelFiles.swift` entirely
3. Search codebase for any remaining references to `LLMModelFiles` and remove them
4. Verify the project builds successfully with `make build`

**Exit criteria**:
- [ ] `BrujaDownloadManager.downloadModel()` passes `files: []` to `Acervo.ensureAvailable()`
- [ ] `Sources/SwiftBruja/Core/LLMModelFiles.swift` does not exist
- [ ] `grep -r "LLMModelFiles" Sources/ Tests/` returns no matches
- [ ] `make build` succeeds with exit code 0

---

## Parallelism Structure

**Critical Path**: 1 sortie (both sorties are parallel — the longer one determines total time)

**Parallel Execution Groups**:
- **Group 1** (runs in parallel):
  - Sortie 1: Create CDN Upload Workflow (Sub-agent — sonnet) — **NO BUILD**
  - Sortie 2: Update Swift Code (Supervising agent) — **SUPERVISING AGENT ONLY** (has `make build` step)

**Agent Constraints**:
- **Supervising agent**: Handles Sortie 2 (has build/compile step)
- **Sub-agent 1 (sonnet)**: Handles Sortie 1 (workflow file creation, no build)

---

## Open Questions & Missing Documentation

No blocking issues found.

**External dependency (non-blocking)**: GitHub repo secrets (`R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `HF_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`) must exist in the repository before running the workflow. These are pre-existing infrastructure — the sortie agent only references them in YAML.

---

## Summary

| Metric | Value |
|--------|-------|
| Work units | 1 |
| Total sorties | 2 |
| Dependency structure | parallel (both sorties are Layer 1, independent) |
| Critical path length | 1 sortie |
| Agent allocation | 1 supervising + 1 sub-agent (sonnet) |
| Average sortie size | 16 turns (budget: 50) |
