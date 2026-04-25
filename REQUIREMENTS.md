---
title: "SwiftBruja Reference-Implementation Requirements for SwiftAcervo 0.8"
date: 2026-04-24
source: "ACERVO_AUDIT.md (2026-04-23), ../SwiftAcervo/USAGE.md"
supersedes: "REQUIREMENTS.md v1.0 (2026-04-18, pre-0.8 API)"
version: "2.0"
status: "READY FOR EXECUTION"
---

# SwiftBruja Reference-Implementation Requirements

**SwiftAcervo version:** `≥ 0.8.1` (the offline-mode contract in this document requires the `ACERVO_OFFLINE` env-var gate, first shipped in SwiftAcervo 0.8.1)
**Canonical reference:** `../SwiftAcervo/USAGE.md`

`USAGE.md` §"Real-World Examples" names SwiftBruja as the canonical consumer
("Reference implementation: SwiftBruja (MLX + Tokenizers)"). This document is
the implementation spec that closes the gap between today's code and the
behavior `USAGE.md` advertises. Every requirement traces back to a specific
finding in the prior call-site audit; nothing below is aspirational.

> **Note on supersession.** The previous `REQUIREMENTS.md` (v1.0, 2026-04-18)
> targeted a pre-0.8 Acervo API with baked-in SHA-256 checksums,
> `Acervo.register()` on concrete file lists, and a `withComponentAccess`
> closure. Current 0.8 `USAGE.md` explicitly **reverses** that model: the CDN
> manifest is authoritative, descriptors are bare, and file lists are
> hydrated at runtime. The branch that produced this document already
> completed that reversal for `BrujaComponents.swift`. Track A work items
> A1–A4 from v1.0 are obsolete and are **not** repeated here.

---

## Overarching Contract (Non-Negotiable)

1. **Manifest is authoritative.** Every download path in SwiftBruja passes
   `files: []`. No code path hard-codes file lists or checksums.
2. **Components are bare.** `ComponentDescriptor` registration omits both
   `files:` and `estimatedSizeBytes`; hydration fills them in at first use.
3. **No HuggingFace fallback.** All downloads go through Acervo → R2 CDN.
4. **Load path matches `USAGE.md` §"Real-World Pattern (SwiftBruja
   Reference)"** — guard with `isModelAvailable`, resolve with
   `modelDirectory(for:)`, load with `LLMModelFactory.shared.loadContainer`.

These hold today. The requirements below build on them; they do not relax
them.

---

## R1 — Delegate Level 3 downloads to `Acervo.ensureComponentReady`

**Priority:** High
**Audit reference:** §3.3, Level 3
**Files:** `Sources/SwiftBruja/Core/BrujaDownloadManager.swift`

`BrujaDownloadManager.ensureComponentReady(_:force:progress:)` currently
re-implements Level 3 by looking up the component, extracting `repoId`, and
calling the Level 2 API (`Acervo.ensureAvailable`). The reference expects the
purpose-built Level 3 entry point so the descriptor is hydrated as a side
effect (`Acervo.component(id)?.files` populates from the manifest after the
call).

**Implementation**

Replace the `ensureAvailable(modelId, files: [])` call inside
`ensureComponentReady` with:

```swift
try await Acervo.ensureComponentReady(componentId) { acervoProgress in
    progress?(acervoProgress.overallProgress)
}
return try Acervo.modelDirectory(for: component.repoId)
```

The `force` branch stays (`Acervo.deleteModel(component.repoId)` still runs
before the ensure call). The component-registration guard
(`BrujaModelManager.component(for: componentId) == nil` →
`BrujaError.modelNotFound`) stays.

`downloadModel(_:force:progress:)` — the raw-repoId Level 2 path — is **not**
touched. `bruja download -m mlx-community/<repo>` must keep working for
unregistered repo IDs.

**Acceptance**

- Unit test: register a bare descriptor (no `files:`), call
  `BrujaDownloadManager.shared.ensureComponentReady(id)` against a fixture
  manifest, assert `Acervo.component(id)?.files.isEmpty == false` after the
  call.
- Existing `bruja download -m <repo-id>` CLI path still passes its tests
  (regression guard for the untouched Level 2 path).

---

## R2 — Typed `AcervoError` handling at the CLI boundary

**Priority:** High
**Audit reference:** §3.7
**Files:** `Sources/bruja/BrujaCLI.swift`, new `Sources/bruja/ErrorReporting.swift`

CLI subcommands let `AcervoError` propagate through `AsyncParsableCommand`'s
default printer, producing output like:

> Error: The operation couldn't be completed. (SwiftAcervo.AcervoError error 3.)

`USAGE.md` §"Error Handling" prescribes an exhaustive `catch let error as
AcervoError` at the application boundary with human-readable mapping.

**Implementation**

Add a mapping helper used by every subcommand's `run()`:

```swift
// Sources/bruja/ErrorReporting.swift (new file)
import Foundation
import SwiftAcervo

struct CLIError: Error, CustomStringConvertible {
    let description: String
}

func runCLI<T>(_ body: () async throws -> T) async throws -> T {
    do {
        return try await body()
    } catch let error as AcervoError {
        throw CLIError(description: humanReadable(error))
    }
}

private func humanReadable(_ error: AcervoError) -> String {
    switch error {
    case .modelNotFound(let id):
        return "Model '\(id)' is not published on the CDN."
    case .manifestDownloadFailed(let status):
        return "Could not fetch manifest (HTTP \(status))."
    case .manifestIntegrityFailed:
        return "Manifest is corrupt; aborting."
    case .downloadFailed(let file, let status):
        return "Download failed for '\(file)' (HTTP \(status))."
    case .integrityCheckFailed(let file, _, _):
        return "File '\(file)' failed SHA-256 verification; delete and retry."
    case .downloadSizeMismatch(let file, let expected, let actual):
        return "File '\(file)' size mismatch (\(actual) vs \(expected) bytes)."
    case .fileNotInManifest(let file, let modelId):
        return "Model '\(modelId)' does not include '\(file)' — developer error."
    case .componentNotRegistered(let id):
        return "Unknown component '\(id)'."
    @unknown default:
        return error.localizedDescription
    }
}
```

Each subcommand body is wrapped: `try await runCLI { ... }`.

**Acceptance**

- Every currently-shipping `AcervoError` case has a branch (the `@unknown
  default` ensures new cases surface on upgrade but don't break the build).
- Manual test: `bruja download -m mlx-community/does-not-exist` prints
  exactly `Error: Model 'mlx-community/does-not-exist' is not published on
  the CDN.`, not the generic `AcervoError error N` form.

---

## R3 — TTY-guarded progress rendering in the CLI

**Priority:** High
**Audit reference:** §3.11, §3.10 #3
**Files:** `Sources/bruja/BrujaCLI.swift` (`DownloadCommand`), new
`Sources/bruja/ProgressRenderer.swift`

`DownloadCommand.run` unconditionally prints ANSI carriage-return lines:

```swift
print("\r\u{1B}[KDownload progress: \(percentage)%", terminator: "")
fflush(stdout)
```

Redirected stdout (`bruja download ... > log.txt`, GitHub Actions logs) fills
with escape-sequence soup. `USAGE.md` §"CLI Progress Bars" prescribes a TTY
guard and a line-oriented fallback.

**Implementation**

Extract progress rendering into a `ProgressRenderer` helper that:

1. Detects `isatty(fileno(stdout)) != 0` once at construction.
2. On a TTY: current `\r\u{1B}[K` bar behavior.
3. Not a TTY: emit one `Download progress: N%` line per 10-percent
   increment (`0%, 10%, …, 100%`), no ANSI escapes, newline-terminated.
4. Honors `--quiet` by short-circuiting both paths.

The download callback is `@Sendable`; the renderer either is an actor or
uses a `nonisolated(unsafe)` last-percent cache guarded by
`OSAllocatedUnfairLock`.

**Acceptance**

- `bruja download -m <small-fixture-model> > /tmp/log.txt` produces ≤ 11
  lines (`0%…100%`) and contains no `0x1B` byte
  (`! grep -q $'\x1b' /tmp/log.txt`).
- Interactive `bruja download -m <small-fixture-model>` still redraws on a
  single line.
- `bruja download -m <small-fixture-model> --quiet > /tmp/log.txt`
  produces zero progress lines (errors on stderr only).

---

## R4 — Pre-flight size via `fetchManifest(forComponent:)`

**Priority:** Medium
**Audit reference:** §3.4, §3.10 #2
**Files:** `Sources/SwiftBruja/Core/BrujaDownloadManager.swift`,
`Sources/bruja/BrujaCLI.swift` (`InfoCommand`)

`bruja info -m <id>` today only works for already-downloaded models because
it calls `Acervo.modelInfo`, which reads local state. Users cannot answer
"how big is this model before I pull 40 GB?" — which is the exact use case
`Acervo.fetchManifest` was added for.

**Implementation — library**

Add to `BrujaDownloadManager`:

```swift
/// Total download size in bytes per the published manifest.
/// Fetches the manifest only; no model files touched.
public nonisolated func estimatedSize(for modelOrComponentId: String) async throws -> Int64 {
    let files = try await manifestFiles(for: modelOrComponentId)
    return files.reduce(0) { $0 + $1.sizeBytes }
}

/// Manifest file list without downloading.
public nonisolated func manifestFiles(for modelOrComponentId: String) async throws -> [AcervoManifestFile] {
    if BrujaModelManager.component(for: modelOrComponentId) != nil {
        return try await Acervo.fetchManifest(forComponent: modelOrComponentId).files
    }
    return try await Acervo.fetchManifest(for: modelOrComponentId).files
}
```

(Confirm the concrete type name from `SwiftAcervo` 0.8 — if it's not
`AcervoManifestFile`, substitute whatever `Acervo.fetchManifest` returns.)

**Implementation — CLI**

Extend `InfoCommand` with a `--remote` flag. When set, the command calls
`estimatedSize` and `manifestFiles` instead of `Acervo.modelInfo`, and prints:

```
Remote: <modelId>
Files: <N>
Size:  <formatted bytes>
```

Without `--remote`, behavior is unchanged (local info).

**Acceptance**

- `bruja info -m mlx-community/Qwen2.5-3B-Instruct-4bit --remote` succeeds
  on a machine where the model is **not** downloaded, and does not create
  any file under `Acervo.sharedModelsDirectory`.
- Library test: `estimatedSize(for:)` returns a non-zero value for a
  known-published model ID without producing files on disk.

---

## R5 — Log `Acervo.sharedModelsDirectory` on every CLI invocation

**Priority:** Medium
**Audit reference:** §3.2
**Files:** `Sources/bruja/BrujaCLI.swift`

`list` and `info` already print the directory. `download` prints it only in
the opening banner. `query` and `chat` never print it — so App Group
misconfiguration in embedded-host-app scenarios is invisible.

**Implementation**

Before the first line of user-facing output in every subcommand (including
`query` and `chat`), emit to **stderr** (unless `--quiet`):

```
[bruja] SharedModels: <Acervo.sharedModelsDirectory.path>
```

Stderr so `--json` output on stdout stays machine-parseable. Routed through
the same `ProgressRenderer` helper from R3 so `--quiet` suppresses it.

**Acceptance**

- `bruja query "hi" --json 2>/dev/null | jq .` still parses as JSON.
- `bruja query "hi" 2>&1 >/dev/null | grep SharedModels` matches on a
  default install.
- `bruja query "hi" --quiet 2>&1 >/dev/null | grep SharedModels` does **not**
  match.

---

## R6 — Document the App Group requirement

**Priority:** Medium
**Audit reference:** §3.2
**Files:** `README.md` (new section), `AGENTS.md` (cross-reference)

SwiftBruja ships as a library; the `group.intrusive-memory.models`
entitlement must be set by the **host app** or cross-app sharing silently
degrades to per-app `Application Support/` copies. `USAGE.md` step 2 is
mandatory for consumer apps, but the requirement is invisible to anyone who
only reads SwiftBruja's docs.

**Implementation**

Add an `## App Group Entitlement` section to `README.md` that:

1. Names `group.intrusive-memory.models` verbatim and links to `USAGE.md`.
2. Shows the Xcode capability steps and an equivalent `.entitlements`
   snippet.
3. Points to the R5 stderr line as the self-diagnostic:
   > If `[bruja] SharedModels:` shows a path under
   > `Application Support/SwiftAcervo/SharedModels`, the capability is
   > missing from the host target.
4. Calls out that the `bruja` CLI binary itself is unsigned and legitimately
   uses the fallback path — not a bug.

Add a one-liner to `AGENTS.md` pointing future agents at the README section.

**Acceptance**

- `README.md` contains `group.intrusive-memory.models` verbatim.
- `README.md` links to `../SwiftAcervo/USAGE.md` (or the canonical upstream
  URL) for the full integration checklist.

---

## R7 — `withModelAccess` around `loadContainer(from:)`

**Priority:** Low
**Audit reference:** §3.8
**Files:** `Sources/SwiftBruja/Core/BrujaModelManager.swift`

There is a window between `Acervo.modelDirectory(for:)` and
`LLMModelFactory.shared.loadContainer(from:)` where another process on the
shared App Group container could delete or overwrite files. The actor
boundary around `BrujaModelManager` protects in-process but not
cross-process races.

**Implementation**

In `BrujaModelManager.loadModel(_:)`, replace the direct
`modelDirectory(for:)` + `loadContainer(from:)` sequence with:

```swift
let container = try await AcervoManager.shared.withModelAccess(modelId) { dir in
    try await LLMModelFactory.shared.loadContainer(from: dir)
}
```

The memory-validation step (`BrujaMemory.validateMemoryForModel`) stays
outside the closure (uses the size from `Acervo.modelInfo`, no URL needed).

**Acceptance**

- `BrujaModelManager.loadModel(_:)` no longer calls
  `Acervo.modelDirectory(for:)` directly.
- Existing query/chat tests pass unchanged.
- Concurrent `loadModel` + `deleteModel` of the same ID in a new test
  serialize (one waits on the other) rather than race.

---

## R8 — Batch warm-up via `ModelDownloadManager.ensureModelsAvailable`

**Priority:** Low (deferred)
**Audit reference:** §3.3 Level 1
**Files:** `Sources/SwiftBruja/Core/BrujaDownloadManager.swift`,
`Sources/bruja/BrujaCLI.swift`

SwiftBruja is single-model-at-a-time. `USAGE.md` Level 1 is the preferred
consumer default. When a concrete caller needs multiple models in one
await — e.g., LLM + tokenizer + codec for a chat UX — the Level 1 API is the
right surface.

**Implementation (deferred until a caller exists)**

```swift
public func ensureModelsAvailable(
    _ modelIds: [String],
    progress: (@Sendable (Double, String) -> Void)? = nil
) async throws {
    try await ModelDownloadManager.shared.ensureModelsAvailable(modelIds) { p in
        progress?(p.fraction, p.model)
    }
}
```

Expose via CLI as `bruja download -m <id> -m <id> -m <id>` (repeated `-m`).

**Acceptance (when implemented)**

- Batch progress callback fires with cumulative `fraction` across the list,
  not per-model.
- CLI test: downloading two small fixture models shows `fraction` that only
  increases.

Do **not** build this until a concrete caller exists. Listed here only so
future work can skip the "should we?" step.

---

## Non-Goals

- **Pinned file subsets (`files: [concrete list]`).** `USAGE.md` calls this
  an escape hatch; SwiftBruja has no use case for it and the audit confirmed
  every call site passes `files: []`. Keep it that way.
- **Custom retry loops.** Acervo already resumes partial downloads; a
  wrapper would interfere.
- **`withLocalAccess` / LoRA flows.** No LoRA surface in SwiftBruja yet.
  Open a separate requirements doc when one lands.
- **Removing `BrujaDownloadManager.downloadModel` (Level 2 path).** CLI raw
  repo-ID downloads (`bruja download -m mlx-community/...`) have no
  registered component and must continue to work via Level 2.
- **Re-baking SHA-256 checksums into `BrujaComponents.swift`.** This was
  requested by the v1.0 REQUIREMENTS.md; 0.8 `USAGE.md` forbids it. Do not
  reintroduce.

---

## Offline-Mode Contract

The Verification Plan's offline-load test (§"Verification Plan" step 2)
relies on an environment-variable contract honored by SwiftAcervo:

| Env var | Set value | Required SwiftAcervo behavior |
| --- | --- | --- |
| `ACERVO_OFFLINE` | `1` | Refuse every outbound HTTP fetch (manifest pull, file download, HEAD probe) with a typed `AcervoError.offlineModeActive` (or equivalent). Continue to serve already-resolved files from `Acervo.sharedModelsDirectory` and continue to honor `isModelAvailable` / `modelDirectory(for:)`. |

This is a **prerequisite on SwiftAcervo 0.8**, not a SwiftBruja
implementation requirement. SwiftBruja does not gate or re-implement
network access; it only sets the env var in the verification harness and
asserts that an already-cached model can still be queried. If SwiftAcervo
0.8.x ships without this gate, the offline-load test cannot prove the
property and the verification step must be parked until SwiftAcervo
publishes the contract. Track this dependency as **OQ-7** in the execution
plan.

The query path (`BrujaModelManager.loadModel` → `Acervo.modelDirectory(for:)`
→ `LLMModelFactory.shared.loadContainer`) is already network-free for
cached models; the env var exists to fail loudly on regressions, not to
add a new code path to SwiftBruja.

---

## Verification Plan

A single make target proves the reference-implementation claim:

```
make reference-check
```

Composed of:

1. `swift_package_test` via XcodeBuildMCP (unit + integration).
2. **Offline-load test.** Download a small fixture model, then re-run the
   query path with `ACERVO_OFFLINE=1` set in the environment and assert
   `bruja query "hi" -m <fixture>` still succeeds. The env var is a
   SwiftAcervo contract (see §"Offline-Mode Contract" below): when set,
   SwiftAcervo MUST refuse any new HTTP fetch with a typed error and serve
   exclusively from `Acervo.sharedModelsDirectory`. A regression that
   reintroduces a fetch in the query path will surface as a non-zero exit
   instead of silently passing.
3. **TTY guard test.**
   - `script -q /dev/null bruja download -m <fixture>` (TTY path)
   - `bruja download -m <fixture> > log.txt` (non-TTY path)
   - Assert the output shapes described in R3.
4. **Error-mapping smoke test.** `bruja download -m mlx-community/__nope__`
   exits non-zero and stderr matches the R2 canonical message.
5. **Pre-flight test.** `bruja info -m <undownloaded-fixture> --remote`
   prints a non-zero size with no filesystem side-effects under
   `Acervo.sharedModelsDirectory`.

Every requirement **R1–R6** must pass before SwiftBruja can be described in
`USAGE.md` as the canonical reference without caveats. R7 and R8 are
post-milestone.

---

## Sequencing

R1–R5 are independent and can land in any order. R6 follows R5 (its
verification text references the R5 stderr line). R7 has no ordering
constraint but should not block R1–R6. R8 is deferred.

Suggested landing order for reviewability:

```
R3 (ProgressRenderer helper)  ──┐
                                 ├──► R5 (reuses helper for startup line)
R2 (ErrorReporting helper)  ────┘           │
                                              ▼
R1 (Level 3 delegation)                     R6 (README section)
R4 (pre-flight manifest API)
R7 (withModelAccess)           [optional, any time]
R8 (batch)                     [deferred]
```

---

## Mapping Back to the Audit

| Audit finding | Requirement |
| --- | --- |
| §3.2 App Group entitlement unverified at runtime | **R5, R6** |
| §3.3 Level 3 re-implemented via Level 2 | **R1** |
| §3.3 Level 1 batch API unused | **R8** (deferred) |
| §3.4 `fetchManifest` / pre-download size unused | **R4** |
| §3.7 Generic error handling at CLI boundary | **R2** |
| §3.8 `withModelAccess` not used around load | **R7** |
| §3.10 #2 `validateCanDownload` not called | Folded into **R4** (pre-flight) |
| §3.10 #3 Aggregate progress / `fraction` | **R8** (deferred with batch) |
| §3.11 Missing TTY guard in progress output | **R3** |

Audit sections that reported ✅ (§3.1 manifest-first compliance, §3.5
contract/validation, §3.6 no file-list pinning, §3.9 load pattern already
matches reference, §3.10 #1/#4/#5) require no work and are not repeated.

---

## Success Criteria

- ✅ Level 3 component downloads go through `Acervo.ensureComponentReady`.
- ✅ Every CLI subcommand maps `AcervoError` to a human-readable message.
- ✅ CLI progress output is TTY-aware; redirected logs contain no ANSI
  escapes.
- ✅ `BrujaDownloadManager.estimatedSize(for:)` returns manifest totals
  without touching local files.
- ✅ Every CLI invocation logs the resolved `SharedModels` path to stderr
  unless `--quiet`.
- ✅ README documents the App Group requirement and the stderr
  self-diagnostic.
- ✅ `make reference-check` passes on a clean checkout.
