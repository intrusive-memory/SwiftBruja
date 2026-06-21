# SwiftBruja → Local Agentic CLI — REQUIREMENTS (Gap Analysis)

> Draft for review. Target: transform SwiftBruja from a one-shot query/chat tool into a
> **local agentic CLI** (an agentic loop running tools on the user's Mac), with **two
> interchangeable model backends**:
> 1. **Apple Foundation Models** (`FoundationModels`, on-device system model)
> 2. **A model downloaded via SwiftAcervo + run through MLX** (current Bruja path)
>
> Inspired by WWDC2026-232 ("Build local agentic workflows with MLX"). See "Divergence
> from the video" below — we are building the agent *in-process in Swift*, not running an
> external agent against an OpenAI-compatible server.

---

## 0. Scope decisions (locked)

These framings are decided and constrain everything below:

- **This is a POC.** Optimize for proving the agentic loop works end-to-end on two
  backends — not for production hardening. Don't gold-plate.
- **The 80% use case is interactive CLI.** A `bruja agent` REPL (model → tool → observe →
  repeat, live in the terminal) is the primary deliverable. One-shot `bruja agent "<task>"`
  is a thin wrapper on the same loop. (Resolves **O5**.)
- **`bruja serve` (OpenAI-compatible endpoint) is an explicit add-on, not core.** It may be
  built, but it must be fenced off as an optional feature — its own command, its own files,
  zero entanglement with the core agent loop. Serve is *not* the 80% case and must never be
  treated as such. (Resolves **O4** — yes, but strictly secondary.)
- **GUI / app-building is out of scope for now.** Get the CLI agent correct first. Any
  Xcode/app integration is a later, separate concern.
- **Foundation Models being a weak agent is acceptable.** For a POC, FM is included to prove
  the backend abstraction handles two structurally different tool systems. If FM mis-calls
  tools or refuses, that's a known limitation we accept — not a blocker. Invest minimally:
  enough to demonstrate the adapter, not to make FM a great agent. (Tempers **R2**/risks.)

**Priority order (build sequence — revised after validation):**
1. **Spike R3+R4 first, concretely:** wire MLX `ChatSession` + `toolDispatch` to **one** real
   tool (`read_file`) end-to-end so a tool call actually round-trips. *Do not design the R1
   abstraction in the abstract* — extract it from working code.
2. **Then R1:** lift `AgentBackend` / `AgentEvent` out of the working MLX spike.
3. **Then R4 (rest of tools) + R5 (interactive loop) + R6 (cwd guard).**
4. **Then R2:** add Foundation Models as the *second* conformer — this is what proves the
   abstraction is real (two structurally different tool systems behind one seam).
5. **Then optionally** serve.

> Rationale: an abstraction designed before a single tool call has round-tripped tends to be
> wrong. One working backend first, abstraction second, second backend as the proof.

---

## 1. Where we are today

| Capability | Status |
|---|---|
| On-device inference (MLX) | ✅ `Bruja.query` / `queryWithMetadata` / `chat` via MLX `ChatSession` |
| Model download/cache/list/info | ✅ delegated to SwiftAcervo (`ensureAvailable`, `listModels`, `modelInfo`) |
| Streaming chat (multi-turn) | ✅ `bruja chat` streams tokens, keeps context |
| Structured output (Codable) | ✅ `Bruja.query(as:)` (prompt-coerced JSON, best-effort) |
| **Agentic loop** (model → tool → observe → repeat) | ❌ none |
| **Tools** (shell, file read/write/edit, etc.) | ❌ none |
| **Foundation Models backend** | ❌ none (MLX is the only path) |
| **Backend abstraction** | ❌ none — call sites bind directly to MLX `ChatSession` |
| Tool-calling plumbing | ⚠️ *available but unused* — MLX `ChatSession` already accepts `tools:` + `toolDispatch:` |
| Permissions / sandboxing for tool actions | ❌ none |

CLI verbs today: `query` (default), `download`, `chat`, `list`, `info`.

## 2. Target state

A `bruja agent` (or `bruja` default) experience where:
- The user gives a task in natural language.
- An **agent loop** lets the model call **tools** (run shell command, read/write/edit files, list dir, fetch URL, …), observe results, and continue until the task is done.
- The **same agent** runs against **either** backend, selected by a flag/config:
  - `--backend foundation` → Apple Foundation Models
  - `--backend mlx --model <id>` → SwiftAcervo-cached model via MLX
- Output streams live; tool calls are surfaced and (by policy) confirmed.

## 3. Two key technical findings (these de-risk the work)

1. **MLX already does the tool loop for us.** `MLXLMCommon.ChatSession` exposes
   `tools: [ToolSpec]?` and `toolDispatch: (@Sendable (ToolCall) async throws -> String)?`
   and runs tool dispatch *internally* during generation. We supply JSON-schema tool
   specs + a dispatcher closure; we do **not** hand-parse tool-call tokens.
   (`Tool<Input,Output>` + `ToolParameter` build the schema for us.)
2. **Foundation Models has its own native agentic session.** `LanguageModelSession(tools:instructions:)`
   with the `Tool` protocol (typed `@Generable` arguments + `call(arguments:)`) — it
   also loops internally. So both backends are "give me tools, I'll call them"; the work
   is a **unifying adapter**, not two hand-rolled loops.

⚠️ **But the two tool systems are structurally different** (MLX = JSON-schema dict +
untyped closure; FoundationModels = typed Swift protocol with `@Generable`). The core
design problem is **one tool definition feeding both**. See R4.

### 3a. The central mechanism (validated): emit AgentEvents from *inside* the tool handler

Both backends run the tool loop internally and, on the string-streaming path, surface **only
assistant text** — not discrete tool-call events. (MLX docs: *"toolDispatch ... required for
toolcalls if streaming strings rather than details."*) So `AgentBackend.streamTurn`'s
`.toolCall`/`.toolResult` events are produced by **us, from the one place we control**:
- **MLX:** inside the `toolDispatch` closure — we know the tool name + decoded args on entry
  and the result on exit, so we publish `.toolCall` then `.toolResult` into the
  `AsyncThrowingStream` there, around invoking the shared handler.
- **FoundationModels:** inside each `Tool.call(arguments:)` — same pattern, same place.

This is the load-bearing design insight: the unified tool handler is also the event source.
It makes R5 rendering and R6 path-prompting fall out naturally (both happen *in* the handler),
and it's symmetric across both backends. Verified types: MLX `ToolCall.function.name: String`,
`arguments: [String: JSONValue]`, `ToolSpec = [String: any Sendable]`, `Tool<Input,Output>`,
`ToolParameter`; FM `Tool` protocol + `Generable` `Arguments` + `call(arguments:)`.

## 4. Gaps SwiftAcervo cannot close for us (must own ourselves)

SwiftAcervo is **model-type-agnostic** (confirmed): no notion of LLM-vs-audio, no context
window, **no tool-calling capability flag** in `CDNManifest` or `ComponentDescriptor`.
Consequences:
- **G1 — Tool-capability detection.** For the MLX backend we must decide whether a given
  cached model can actually tool-call. Options: (a) inspect `config.json` / chat template
  for tool-call tokens, (b) a curated allowlist of known-good model IDs, (c) just try and
  degrade gracefully. The **1B default model is not viable for agentic tool use** — see R7.
- **G2 — Model selection UX.** Acervo gives us `listModels()`, `availability()`,
  `findModels(matching:)`, fuzzy match. We layer "is this agent-capable?" on top.

---

## 5. Requirements

### R1 — Backend abstraction (foundation of the whole effort)
- **R1.1** Define a protocol, e.g. `AgentBackend`, that both backends conform to. Minimum surface:
  - create a session given (system/instructions, tool set, generation params)
  - `streamTurn(prompt) -> AsyncThrowingStream<AgentEvent>` where `AgentEvent` ∈
    `.token(String)`, `.toolCall(name, args)`, `.toolResult(...)`, `.finished`
  - report capabilities (supportsTools, supportsStreaming, contextWindow?)
- **R1.2** A `BackendKind` enum (`.foundation`, `.mlx`) + a factory that builds the right
  backend from CLI flags / config.
- **R1.3** Refactor existing `BrujaQuery` / `chat` to route through the abstraction (the
  MLX backend becomes one conformer; non-agentic `query` can keep a thin fast path).

### R2 — Foundation Models backend
- **R2.1** New target/module depending on `FoundationModels`. Gate the whole backend behind
  availability: `SystemLanguageModel.default.availability` (`.available` vs
  `.unavailable(reason)`), surfaced as a clean CLI error when the OS/device/Apple-Intelligence
  setting makes it unavailable.
- **R2.2** Map our unified tool definitions to FoundationModels `Tool` (typed `@Generable`
  arguments). See R4 for the adapter strategy.
- **R2.3** Stream via `session.streamResponse(to:)`; translate to `AgentEvent`s.
- **R2.4** Respect FM constraints: context window limits, content-guardrail refusals, and
  any rate/throttle behavior — turn these into typed `BrujaError`s, not crashes.

### R3 — MLX / SwiftAcervo backend (evolve existing)
- **R3.1** Wrap `ChatSession` behind `AgentBackend`, wiring `tools` + `toolDispatch` from
  the unified tool registry.
- **R3.2** Ensure-available flow: before an agent run, verify the chosen model is present
  (`Acervo.isModelAvailable` / `availability`), offering to `ensureAvailable` if not.
- **R3.3** Tool-capability gate (G1): **POC choice = (c) try-and-degrade + a tiny curated
  allowlist for the default model only.** Do *not* build `config.json`/chat-template
  introspection now. If a non-allowlisted model is chosen, print a one-line "may not tool-call
  reliably" warning and proceed. Pick a known-good tool-capable default (R7.2).

### R4 — Unified tool system (the hard part)
- **R4.1** Define tools **once** in a backend-neutral form: name, description, a parameter
  schema, and an async handler `(decodedArgs) -> String/Codable`.
- **R4.2** Adapter A → MLX: emit `MLXLMCommon.Tool`/`ToolSpec` + a `toolDispatch` closure
  that decodes args and invokes the shared handler.
- **R4.3** Adapter B → FoundationModels: bridge to the `Tool` protocol with `@Generable`
  argument structs. (Open question O3: how much can be code-generated vs. hand-written per
  tool, given `@Generable` is a macro on concrete types.)
- **R4.4** Initial built-in tool set (scope TBD with you):
  - `run_shell(command)` — execute a shell command, capture stdout/stderr/exit
  - `read_file(path)`, `write_file(path, contents)`, `edit_file(path, old, new)`
  - `list_dir(path)`, `glob/grep`
  - (stretch) `fetch_url(url)`
- **R4.5** Each tool returns a compact, model-friendly result string (truncation policy for
  large outputs).

### R5 — Agent orchestration / CLI loop
- **R5.1** **Decided:** add an explicit **`bruja agent`** verb (no args → interactive REPL; with
  a task string → one-shot wrapper on the same loop). **Keep `query` as the bare-prompt default**
  for the POC — do *not* repurpose `bruja "<prompt>"` to mean agent yet (that would silently
  change existing behavior, the reference-check suite, and user muscle memory). Revisit later.
- **R5.2** Render the loop: stream assistant text, show each tool call + result, iterate.
  Reuse `BrujaHelpers.ProgressRenderer` patterns.
- **R5.3** Turn/step cap + graceful stop (max iterations, Ctrl-C, `/quit`).
- **R5.4** Session transcript (in-memory; optional persistence later).

### R6 — Safety: working-directory confinement (the guard model)
**Decided:** the safety boundary is the **current working directory subtree**, not
per-action prompting. Tools run freely *inside* the cwd; escaping it needs consent.
- **R6.1** Within `cwd` and below: the full tool suite (shell, read/write/edit, list/grep)
  runs **without per-action confirmation**. The POC favors flow over chattiness here.
- **R6.2** **Path-escape guard (the one hard gate):** any tool invocation that resolves to a
  path **outside the cwd subtree** — including via `..`, absolute paths, or symlinks — must
  **prompt the user for explicit permission**. This covers `read_file`/`write_file`/`edit_file`/
  `list_dir` paths *and* a best-effort check on `run_shell` commands that reference outside paths.
  Resolve/canonicalize paths before the check; deny-by-default if it can't be resolved safely.
- **R6.3** Clear, auditable echo of every command/edit as it runs (even when not prompting),
  so the transcript shows exactly what the agent did.
- **R6.4** (POC note) `run_shell` confinement is inherently best-effort — a shell command can
  still `cd` elsewhere. Document this limit honestly; the cwd guard is a guardrail, not a sandbox.
- **R6.5** **Concurrency wrinkle (validated, needs design in the spec):** the path-escape prompt
  fires *inside the tool handler*, which runs *inside the backend's internal generation loop*,
  while assistant tokens may be streaming to the same terminal. The REPL must coordinate:
  pause/﻿flush token rendering, prompt the user (blocking `readLine` on the main interaction
  channel), then resume. Because the handler is the single event source (§3a), this is tractable
  — but the loop, the renderer, and the prompt must share one input/output coordinator, not race
  for stdin/stdout. Spec must define that coordinator.

### R7 — Model selection & defaults
- **R7.1** **Backend is inferred from the selected model/config (decided):**
  - The model is **configurable** (CLI flag + config file).
  - Selecting the **Foundation Models** backend when FM is unavailable is a **full-stop error**
    — no silent fallback to MLX, no degraded mode. The gate is the **runtime availability API**
    (`SystemLanguageModel.default.availability` → `.available` vs `.unavailable(reason)`), *not*
    an OS-version check. ⚠️ **Correction:** the `FoundationModels` framework has shipped since
    **macOS 26** (WWDC2025), not 27 — our deployment target (macOS 26) already covers it, so no
    `@available` gymnastics are needed. "macOS 27" in earlier notes was imprecise; the real gate
    is whether Apple Intelligence + the on-device model are available on *this* machine, which the
    availability API reports. Fail loudly with the `.unavailable` reason mapped to a clean error.
  - **Every open-source model managed by SwiftAcervo routes to the MLX backend** automatically.
    So the user picks a *model* (or `foundation`); the backend follows from that choice.
- **R7.2** **Change the agentic default model.** The current default
  `Llama-3.2-1B-Instruct-4bit` is fine for chat but **too weak for reliable tool calling**.
  Recommend a tool-capable default for the MLX agent path (e.g. a Qwen2.5-Instruct 7B-class
  4-bit, or Llama-3.1-8B-Instruct). Keep the 1B default for plain `query`/`chat`.
- **R7.3** `bruja models` / extend `list` to flag which cached models are agent-capable.

### R8 — Build, deps, testing, distribution
- **R8.1** New `FoundationModels` dependency is a system framework (no SPM dep); just
  `import`. Confirm it links under the Makefile/xcodebuild flow.
- **R8.2** Preserve the **swift-tokenizers `exact: 0.5.0`** pin and the Metal-bundle
  colocation constraint (`make release`/`make dist` must still pass).
- **R8.3** Tests: unit-test the tool adapters and agent loop with a **mock backend** (no
  model/network). Keep integration tests inference-only.
- **R8.4** Homebrew formula + `mlx-swift_Cmlx.bundle` colocation unaffected; update docs.

### R9 — Docs
- **R9.1** Update AGENTS.md / README for the new agent commands, backends, tools, and the
  permission model.

---

## 6. Candid risks & things I'd push back on

- **Small-model tool calling is unreliable.** Foundation Models' on-device model (~3B-class)
  and small MLX models will mis-call tools, hallucinate args, or loop. Agentic UX quality is
  gated by model quality. Set expectations; default to a stronger MLX model for real agent work.
- **An agentic CLI that runs shell commands is genuinely dangerous.** We've chosen cwd
  confinement (R6) over per-action prompts as the guard. That's a reasonable POC trade-off, but
  be honest about its limit: `run_shell` confinement is best-effort — a shell command can `cd`
  out, hit the network, or `rm -rf` within the cwd. The cwd guard is a guardrail, **not a
  sandbox**. For anything beyond a POC, revisit (true sandboxing / per-action prompts for shell).
- **Foundation Models is gated & opaque.** Availability depends on device + Apple Intelligence
  being enabled; guardrails can refuse; you can't pick the weights. It's the convenient default
  but the *less controllable* backend.
- **Divergence from the video (be explicit):** WWDC2026-232's stack is *MLX-LM Server*
  (OpenAI-compatible HTTP) + an *external* agent (OpenCode/Xcode). We're building the agent
  **in-process in Swift** with two native backends instead. That's a legitimate and arguably
  cleaner single-binary design — but it means we *don't* get OpenCode/Xcode-as-client for free.
  **Optional alternative/addition (O4):** also expose an OpenAI-compatible local server so
  existing agents (Xcode's "Locally Hosted provider", OpenCode) can point at bruja — this is
  literally what the video demos. Could be a separate `bruja serve` verb.

## 7. Open questions

### Resolved (see §0)
- **O4 — `bruja serve`?** ✅ Yes, but strictly as a fenced-off add-on. Not core, not the 80% case.
- **O5 — Interaction model?** ✅ Interactive REPL is primary (the 80% case); one-shot
  `bruja agent "<task>"` is a thin wrapper on the same loop.

### Resolved decisions
- **O1 — Backend selection.** ✅ Backend is **inferred from the configurable model choice**.
  SwiftAcervo open-source models → MLX. Choosing Foundation Models on a non-macOS-27-FM machine
  is a **full-stop error** (no fallback). See R7.1.
- **O2 — Tool scope.** ✅ **Full suite from day one** (shell + read/write/edit/list/grep). No
  per-action guards — confinement is enforced by the cwd boundary instead (R6).
- **O3 — Tool-definition ergonomics.** ✅ **Hand-write each tool per backend** (MLX schema +
  FM `@Generable` struct). No codegen/macro for the POC.
- **O6 — Permission model.** ✅ **Working-directory confinement.** Free inside the cwd subtree;
  any path escape requires explicit user permission. See R6.
