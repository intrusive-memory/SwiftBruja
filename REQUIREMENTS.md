# Requirements: CDN Model Distribution for SwiftBruja

## Goal

Ensure SwiftBruja's default LLM model (`mlx-community/Qwen3-Coder-Next-4bit`) is available on the intrusive-memory R2 CDN, so that `Acervo.ensureAvailable()` can download it without hitting HuggingFace directly. This mirrors the pattern already used by Vinetas for image generation models.

---

## Research Findings

### Model File Inventory: `mlx-community/Qwen3-Coder-Next-4bit`

| File | Size |
|------|------|
| `config.json` | 22 KB |
| `generation_config.json` | 214 B |
| `tokenizer.json` | 11.4 MB |
| `tokenizer_config.json` | 702 B |
| `chat_template.jinja` | 6 KB |
| `model.safetensors.index.json` | 173 KB |
| `model-00001-of-00009.safetensors` | 5.13 GB |
| `model-00002-of-00009.safetensors` | 5.26 GB |
| `model-00003-of-00009.safetensors` | 5.24 GB |
| `model-00004-of-00009.safetensors` | 5.26 GB |
| `model-00005-of-00009.safetensors` | 5.26 GB |
| `model-00006-of-00009.safetensors` | 5.24 GB |
| `model-00007-of-00009.safetensors` | 5.26 GB |
| `model-00008-of-00009.safetensors` | 5.26 GB |
| `model-00009-of-00009.safetensors` | 2.93 GB |

**Total model size: ~44.8 GB** (9 sharded safetensors). No `tokenizer.model` (SentencePiece) — uses `tokenizer.json` (HuggingFace Tokenizers format).

### SwiftAcervo: Empty Files = Download All

`Acervo.ensureAvailable(modelId, files: [])` downloads **ALL** files from the CDN manifest. From `AcervoDownloader.swift`:

```swift
if requestedFiles.isEmpty {
    // Download everything in the manifest
    filesToDownload = manifest.files
}
```

This eliminates the need for `LLMModelFiles` to know about shards at all.

### SwiftAcervo Already Documents SwiftBruja as Consumer

- `README.md`: Section "SwiftBruja (MLX Inference)" describes SwiftBruja as a consumer for quantized language models
- `AcervoMigration.swift`: Legacy migration includes `LLM` subdirectory for SwiftBruja/Produciesta

---

## Current State

| Component | Status |
|-----------|--------|
| **SwiftAcervo CDN downloads** | Working. Downloads from `https://pub-8e049ed02be340cbb18f921765fd24f3.r2.dev/models/{slug}/` |
| **BrujaDownloadManager** | Delegates to `Acervo.ensureAvailable()` — currently passes `LLMModelFiles.required` (broken for sharded models) |
| **CDN manifest format** | SwiftAcervo expects `CDNManifest` v1 with SHA-256 checksums |
| **Model on CDN** | **NOT YET UPLOADED** |
| **LLMModelFiles.required** | **BROKEN** — hardcodes `model.safetensors` but model has 9 shards |

### Manifest Format: Vinetas vs SwiftAcervo

The Vinetas workflow generates a simple manifest (`{name, size}`). SwiftAcervo requires CDNManifest v1 with SHA-256 checksums. The SwiftBruja workflow must generate the full format:

```json
{
  "manifestVersion": 1,
  "modelId": "mlx-community/Qwen3-Coder-Next-4bit",
  "slug": "mlx-community_Qwen3-Coder-Next-4bit",
  "updatedAt": "2026-03-25T00:00:00Z",
  "files": [
    {"path": "config.json", "sha256": "abc123...", "sizeBytes": 1234}
  ],
  "manifestChecksum": "sha256-of-sorted-concatenated-file-checksums"
}
```

---

## Requirements

### R1: GitHub Actions Workflow — `ensure-model-cdn.yml`

Create `.github/workflows/ensure-model-cdn.yml` that:

1. **Triggers on**:
   - `workflow_dispatch` (manual)
   - Push to `main` when the workflow file itself changes

2. **Checks CDN first**: Hits `{CDN_BASE}/models/{slug}/manifest.json` — skips upload if HTTP 200.

3. **Downloads from HuggingFace**: Uses HF API to discover and download all relevant files:
   - `*.json` (config, tokenizer configs, generation config, shard index)
   - `*.safetensors` (9 sharded weight files, ~5 GB each)
   - `*.jinja` (chat template)
   - Excludes: `.gitattributes`, `README.md`, `*.md`, `*.txt`, `*.py`, `.git*`

4. **Generates SwiftAcervo-compatible manifest** (`CDNManifest` v1):
   - `manifestVersion: 1`
   - `modelId`: `mlx-community/Qwen3-Coder-Next-4bit`
   - `slug`: `mlx-community_Qwen3-Coder-Next-4bit`
   - `updatedAt`: ISO-8601 UTC timestamp
   - `files[]`: each with `path` (string), `sha256` (lowercase hex 64-char), `sizeBytes` (int64)
   - `manifestChecksum`: SHA-256 of all file `sha256` values sorted lexicographically then concatenated

5. **Uploads to R2**: Uses `jakejarvis/s3-sync-action` to sync to `models/mlx-community_Qwen3-Coder-Next-4bit/` in the R2 bucket.

6. **Verifies**: After upload, fetches the manifest from CDN and validates file count.

#### Disk Space Concern

The model is ~44.8 GB. GitHub Actions `ubuntu-latest` runners have ~14 GB free disk. Options:
- **Use a larger runner** (`ubuntu-latest-xlarge` or self-hosted) with sufficient disk
- **Upload shards one at a time**: Download shard → compute SHA-256 → upload → delete → next shard. Build manifest incrementally. This avoids needing all files on disk at once but requires individual `aws s3 cp` calls instead of a bulk sync.
- **Use `actions/cache` or artifact storage** as intermediate staging

**Recommended**: Upload shards sequentially (download one, hash, upload, delete) to stay within standard runner limits. Generate the manifest incrementally.

#### Environment & Secrets

| Variable | Value |
|----------|-------|
| `R2_BUCKET` | `intrusive-memory-audio` |
| `R2_ENDPOINT` | `https://{CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com` |
| `CDN_BASE` | `https://pub-8e049ed02be340cbb18f921765fd24f3.r2.dev` |
| `MODEL_REPO` | `mlx-community/Qwen3-Coder-Next-4bit` |
| `MODEL_SLUG` | `mlx-community_Qwen3-Coder-Next-4bit` |

| Secret | Purpose |
|--------|---------|
| `CLOUDFLARE_ACCOUNT_ID` | R2 endpoint construction |
| `R2_ACCESS_KEY_ID` | R2 write access |
| `R2_SECRET_ACCESS_KEY` | R2 write access |
| `HF_TOKEN` | HuggingFace API access (for gated/rate-limited models) |

### R2: Pass Empty Files to Download All from Manifest

**Problem**: `LLMModelFiles.required` hardcodes `["config.json", "tokenizer.json", "tokenizer_config.json", "model.safetensors"]`. The default model has 9 sharded safetensors, not a single `model.safetensors`.

**Solution**: Pass an empty `files` array to `Acervo.ensureAvailable()`. Acervo will download all files listed in the CDN manifest. This:
- Eliminates the need to know shard names at compile time
- Works for any model regardless of sharding strategy
- Leverages Acervo's existing "download everything" behavior

**Changes**:
- `BrujaDownloadManager.downloadModel()`: Change `files: LLMModelFiles.required` → `files: []`
- `LLMModelFiles.swift`: Delete (no longer needed) or repurpose as validation-only

### R3: No Changes to CDN Download Path

`Acervo.ensureAvailable()` already handles:
1. Fetch manifest from CDN
2. Validate integrity (checksums, version)
3. Download files with per-file SHA-256 verification
4. `SecureDownloadSession` rejects non-CDN redirects

No changes needed to SwiftAcervo.

### R4: Workflow Must Be Idempotent

- Manifest exists on CDN → skip entirely (no re-download, no re-upload)
- Re-run after partial failure → re-download and re-upload cleanly
- Must not corrupt existing CDN state on partial upload

### R5: Default Model Constant as Single Source of Truth

The model repo ID is defined in:
- `BrujaModelManager.defaultModel` → `"mlx-community/Qwen3-Coder-Next-4bit"`
- Workflow `MODEL_REPO` env var

Add a comment in the workflow referencing the Swift constant to keep them in sync.

---

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `.github/workflows/ensure-model-cdn.yml` | **Create** | Workflow to upload model to R2 CDN with SwiftAcervo-compatible manifest |
| `Sources/SwiftBruja/Core/BrujaDownloadManager.swift` | **Modify** | Change `files: LLMModelFiles.required` → `files: []` |
| `Sources/SwiftBruja/Core/LLMModelFiles.swift` | **Delete** | No longer needed — Acervo downloads all files from manifest |

---

## Implementation Order

1. **Create the workflow** (R1) — get the model onto CDN with a valid manifest
2. **Update BrujaDownloadManager** (R2) — pass empty files to download all from manifest
3. **Delete LLMModelFiles.swift** (R2) — remove dead code
4. **Verify end-to-end** — confirm `bruja download --model mlx-community/Qwen3-Coder-Next-4bit` works against CDN
