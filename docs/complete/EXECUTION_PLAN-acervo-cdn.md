# EXECUTION_PLAN: SwiftBruja CDN Model Integration

**Version**: 1.0  
**Date**: 2026-04-17  
**Status**: READY FOR EXECUTION  
**Requirements Source**: `REQUIREMENTS.md`

---

## Terminology

**Mission** — Distribute SwiftBruja's Qwen3-Coder-Next-4bit model (~44.8 GB) to CDN with SwiftAcervo manifest.

**Sortie** — Atomic task: create workflow, generate manifest, upload to CDN, update BrujaDownloadManager.

---

## Mission Overview

Ensure Qwen3-Coder-Next-4bit model is available on Cloudflare R2 CDN with SwiftAcervo-compatible manifest. This enables `BrujaDownloadManager` to download via CDN instead of HuggingFace directly.

**Success Criteria**:
- GitHub Actions workflow generates CDNManifest v1 with SHA-256 for all 9 shards + configs
- All files uploaded to `models/mlx-community_Qwen3-Coder-Next-4bit/` on R2
- `BrujaDownloadManager` uses `Acervo.ensureAvailable(modelId, files: [])` (download all)
- `LLMModelFiles.required` bug fixed (no longer hardcodes single `model.safetensors`)

---

## Work Units & Sorties

### WORK UNIT 1: GitHub Actions Workflow

#### Sortie 1.1: Create Workflow — CDN Upload for Qwen3

**Objective**: Implement `.github/workflows/ensure-model-cdn.yml` that generates SwiftAcervo CDNManifest and uploads to R2.

**Entry Criteria**:
- `.github/workflows/` directory exists
- Cloudflare R2 secrets available (verified via other workflows)
- HuggingFace model ID known: `mlx-community/Qwen3-Coder-Next-4bit`

**Exit Criteria**:
- ✅ Workflow downloads 9 safetensors shards + configs from HuggingFace
- ✅ Generates CDNManifest v1 with:
  - manifestVersion: 1
  - modelId, slug, updatedAt
  - files array with sha256, sizeBytes for each of 14 files
  - manifestChecksum (sorted SHA-256 concatenation)
- ✅ Uploads all files to `models/mlx-community_Qwen3-Coder-Next-4bit/` on R2
- ✅ Includes CDN existence check (skips if manifest.json HTTP 200)
- ✅ Includes verification: downloads and validates checksums
- ✅ Triggers: `workflow_dispatch` + push to main when workflow file changes

**Effort**: 2 hours | **Model**: Haiku

---

#### Sortie 1.2: Test Workflow & Verify Manifest

**Objective**: Manually trigger workflow, verify manifest validity and file checksums.

**Entry Criteria**:
- Sortie 1.1 complete (workflow created)
- GitHub Actions accessible

**Exit Criteria**:
- ✅ Workflow triggered via `workflow_dispatch` completes successfully
- ✅ Manifest.json valid and accessible on CDN
- ✅ All 14 files (9 shards + 5 configs) present on R2
- ✅ SHA-256 checksums in manifest match actual files
- ✅ ManifestChecksum computation verified

**Effort**: 1 hour | **Model**: Haiku

---

### WORK UNIT 2: SwiftAcervo Integration

#### Sortie 2.1: Fix LLMModelFiles Bug

**Objective**: Update `Sources/Bruja/Models/LLMModelFiles.swift` to handle sharded models correctly.

**Entry Criteria**:
- `LLMModelFiles.swift` accessible
- Qwen3 model has 9 shards (known)

**Exit Criteria**:
- ✅ `LLMModelFiles.required` no longer hardcodes single `model.safetensors`
- ✅ Uses empty array `[]` to signal "download all files from manifest"
- ✅ Project builds without errors

**Effort**: 0.5 hours | **Model**: Haiku

---

#### Sortie 2.2: Update BrujaDownloadManager

**Objective**: Modify `BrujaDownloadManager` to use `Acervo.ensureAvailable(modelId, files: [])`.

**Entry Criteria**:
- Sortie 2.1 complete (LLMModelFiles fixed)
- `BrujaDownloadManager.swift` accessible

**Exit Criteria**:
- ✅ `downloadModel()` calls `Acervo.ensureAvailable(modelId, files: [])`
- ✅ Progress callback shows download status
- ✅ Error handling for `AcervoError` cases
- ✅ Project builds and tests pass

**Effort**: 1 hour | **Model**: Haiku

---

### WORK UNIT 3: Testing

#### Sortie 3.1: Integration Test — CDN Download

**Objective**: Test `BrujaDownloadManager.downloadModel()` downloads from CDN.

**Entry Criteria**:
- Sortie 2.2 complete (BrujaDownloadManager updated)
- Test infrastructure ready

**Exit Criteria**:
- ✅ Integration test downloads Qwen3 model successfully
- ✅ All 14 files present in model directory
- ✅ SHA-256 verification passes
- ✅ Test passes

**Effort**: 1 hour | **Model**: Haiku

---

#### Sortie 3.2: Manual Verification

**Objective**: Manually test SwiftBruja inference with CDN-downloaded model.

**Entry Criteria**:
- Sortie 3.1 complete (test passes)
- Local machine ready for manual test

**Exit Criteria**:
- ✅ `bruja query` works with CDN-downloaded model
- ✅ Model inference produces expected output
- ✅ No performance degradation vs. cached model

**Effort**: 1 hour | **Model**: Haiku

---

### WORK UNIT 4: Documentation

#### Sortie 4.1: Update README & AGENTS.md

**Objective**: Document CDN model distribution and SwiftAcervo integration.

**Entry Criteria**:
- All prior sorties complete

**Exit Criteria**:
- ✅ README updated: explains CDN model download
- ✅ AGENTS.md updated: documents SwiftAcervo integration
- ✅ Links to master Acervo integration requirements

**Effort**: 1 hour | **Model**: Haiku

---

## Execution Timeline

| Phase | Sorties | Est. Hours | Notes |
|-------|---------|-----------|-------|
| Workflow | 1.1–1.2 | 3 | Sequential |
| Integration | 2.1–2.2 | 1.5 | Sequential |
| Testing | 3.1–3.2 | 2 | Sequential |
| Documentation | 4.1 | 1 | Final |
| **Total** | **8 sorties** | **~7.5** | Critical path: sequential |

---

**Status**: Ready for execution
