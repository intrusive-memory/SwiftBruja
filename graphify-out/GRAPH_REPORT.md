# Graph Report - .  (2026-11-22)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 1294 nodes · 2384 edges · 69 communities (59 shown, 10 thin omitted)
- Extraction: 93% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 154 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `126c203d`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Agent Backend Selection|Agent Backend Selection]]
- [[_COMMUNITY_Agent Command & Loop|Agent Command & Loop]]
- [[_COMMUNITY_Tokenizer Bridge|Tokenizer Bridge]]
- [[_COMMUNITY_IO Coordinator|IO Coordinator]]
- [[_COMMUNITY_Bruja CLI Commands|Bruja CLI Commands]]
- [[_COMMUNITY_Mock Backend Dispatch Tests|Mock Backend Dispatch Tests]]
- [[_COMMUNITY_MLX Agent Loop & Generation|MLX Agent Loop & Generation]]
- [[_COMMUNITY_Bruja Core Types|Bruja Core Types]]
- [[_COMMUNITY_Bruja Static API Overview|Bruja Static API Overview]]
- [[_COMMUNITY_Progress Renderer|Progress Renderer]]
- [[_COMMUNITY_Bruja Integration Tests|Bruja Integration Tests]]
- [[_COMMUNITY_Tool Dispatch|Tool Dispatch]]
- [[_COMMUNITY_Tool Suite Tests|Tool Suite Tests]]
- [[_COMMUNITY_MLX Agent Loop Transcript Tests|MLX Agent Loop Transcript Tests]]
- [[_COMMUNITY_Path Guard Tests|Path Guard Tests]]
- [[_COMMUNITY_Path Guard|Path Guard]]
- [[_COMMUNITY_Edit File Tool & Registry|Edit File Tool & Registry]]
- [[_COMMUNITY_Grep Tool|Grep Tool]]
- [[_COMMUNITY_Preflight Manifest Test|Preflight Manifest Test]]
- [[_COMMUNITY_Run Shell Tool|Run Shell Tool]]
- [[_COMMUNITY_Shared Models Logging Test|Shared Models Logging Test]]
- [[_COMMUNITY_List Directory Tool|List Directory Tool]]
- [[_COMMUNITY_Inference Integration Test|Inference Integration Test]]
- [[_COMMUNITY_Foundation Model Backend|Foundation Model Backend]]
- [[_COMMUNITY_Write File Tool|Write File Tool]]
- [[_COMMUNITY_Agent Seam Spike Test|Agent Seam Spike Test]]
- [[_COMMUNITY_Error Reporting Smoke Test|Error Reporting Smoke Test]]
- [[_COMMUNITY_Project Execution Plans|Project Execution Plans]]
- [[_COMMUNITY_Bruja Memory Management|Bruja Memory Management]]
- [[_COMMUNITY_Tool Result Type|Tool Result Type]]
- [[_COMMUNITY_Foundation Backend Integration Test|Foundation Backend Integration Test]]
- [[_COMMUNITY_Acervo Component Readiness Tests|Acervo Component Readiness Tests]]
- [[_COMMUNITY_Bruja Error Tests|Bruja Error Tests]]
- [[_COMMUNITY_Bruja Memory Tests|Bruja Memory Tests]]
- [[_COMMUNITY_Acervo Manifest Fetch Tests|Acervo Manifest Fetch Tests]]
- [[_COMMUNITY_Model Path & Listing Tests|Model Path & Listing Tests]]
- [[_COMMUNITY_Agent REPL Test|Agent REPL Test]]
- [[_COMMUNITY_Bruja Model Manager Tests|Bruja Model Manager Tests]]
- [[_COMMUNITY_Path Resolution Tests|Path Resolution Tests]]
- [[_COMMUNITY_Query Result Tests|Query Result Tests]]
- [[_COMMUNITY_Lighthouse & Snakeskin Docs|Lighthouse & Snakeskin Docs]]
- [[_COMMUNITY_Swift Transformers Tokenizer|Swift Transformers Tokenizer]]
- [[_COMMUNITY_Bruja Error|Bruja Error]]
- [[_COMMUNITY_Package Manifest|Package Manifest]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 48|Community 48]]
- [[_COMMUNITY_Community 49|Community 49]]
- [[_COMMUNITY_Community 50|Community 50]]
- [[_COMMUNITY_Community 51|Community 51]]
- [[_COMMUNITY_Community 52|Community 52]]
- [[_COMMUNITY_Community 53|Community 53]]
- [[_COMMUNITY_Community 54|Community 54]]
- [[_COMMUNITY_Community 55|Community 55]]
- [[_COMMUNITY_Community 56|Community 56]]
- [[_COMMUNITY_Community 57|Community 57]]
- [[_COMMUNITY_Community 58|Community 58]]
- [[_COMMUNITY_Community 59|Community 59]]
- [[_COMMUNITY_Community 60|Community 60]]
- [[_COMMUNITY_Community 61|Community 61]]
- [[_COMMUNITY_Community 63|Community 63]]
- [[_COMMUNITY_Community 64|Community 64]]
- [[_COMMUNITY_Community 65|Community 65]]
- [[_COMMUNITY_Community 66|Community 66]]
- [[_COMMUNITY_Community 67|Community 67]]
- [[_COMMUNITY_Community 68|Community 68]]

## God Nodes (most connected - your core abstractions)
1. `BrujaJSONAcceptorTests` - 56 edges
2. `BrujaJSONLogitProcessorTests` - 37 edges
3. `ToolSuiteTests` - 33 edges
4. `ProgressRenderer` - 28 edges
5. `Phase` - 25 edges
6. `RecordingOutputWriter` - 20 edges
7. `BrujaJSONAcceptor` - 19 edges
8. `MLXLMCommon` - 19 edges
9. `PersonajeAcceptanceTests` - 19 edges
10. `ScriptedLineReader` - 19 edges

## Surprising Connections (you probably didn't know these)
- `1.13.0 swift-tokenizers switch` --semantically_similar_to--> `Why swift-tokenizers not swift-transformers`  [INFERRED] [semantically similar]
  CHANGELOG.md → AGENTS.md
- `Gemini-specific agent instructions` --semantically_similar_to--> `Claude-specific agent instructions`  [INFERRED] [semantically similar]
  GEMINI.md → CLAUDE.md
- `SwiftBruja README` --references--> `SwiftBruja logo: wooden mannequin in witch hat with wand, retro wallpaper`  [EXTRACTED]
  README.md → SwiftBruja.jpg
- `SwiftBruja small icon (logo thumbnail)` --semantically_similar_to--> `SwiftBruja logo: wooden mannequin in witch hat with wand, retro wallpaper`  [INFERRED] [semantically similar]
  icon-sm.png → SwiftBruja.jpg
- `Predecessor reality audit lesson` --semantically_similar_to--> `Shared worktree commit collision lesson`  [AMBIGUOUS] [semantically similar]
  docs/complete/snakeskin-molt-01-brief.md → docs/complete/manifest-airdrop-01-brief.md

## Import Cycles
- None detected.

## Communities (69 total, 10 thin omitted)

### Community 0 - "Agent Backend Selection"
Cohesion: 0.05
Nodes (38): AsyncParsableCommand, BrujaCLI, ChatCommand, DownloadCommand, InfoCommand, ListCommand, QueryCommand, CLIError (+30 more)

### Community 1 - "Agent Command & Loop"
Cohesion: 0.07
Nodes (46): BrujaJSONAcceptor, Compiler, Counters, Node, arrayAfterItem, arrayOpen, done, literal (+38 more)

### Community 2 - "Tokenizer Bridge"
Cohesion: 0.08
Nodes (8): BrujaJSONAcceptorTests, BrujaJSONAcceptor, BrujaJSONSchema, Character, Int, StaticString, String, UInt

### Community 3 - "IO Coordinator"
Cohesion: 0.05
Nodes (25): AgentAllowlist, AgentBackend, foundation, mlx, AgentBackendSelector, BrujaError, FoundationModelsAvailabilityProvider, FoundationModelsUnavailableError (+17 more)

### Community 4 - "Bruja CLI Commands"
Cohesion: 0.07
Nodes (31): CanonFact, CodingKeys, age, appearance, arc, backstory, canonFacts, languages (+23 more)

### Community 5 - "Mock Backend Dispatch Tests"
Cohesion: 0.07
Nodes (25): ErrorReportingSmokeTest, ProcessResult, FoundationBackendIntegrationTest, ProcessResult, SharedModelsLoggingTest, BrujaJSONLogitProcessor, MaskCache, DType (+17 more)

### Community 6 - "MLX Agent Loop & Generation"
Cohesion: 0.07
Nodes (25): AcervoModel, BrujaModelInfo, Codable, BrujaQueryResult, BrujaThinking, modelDefault, off, Date (+17 more)

### Community 7 - "Bruja Core Types"
Cohesion: 0.10
Nodes (25): AgentBackend, AgentToolHandling, Arguments, AgentCommand, AgentLoop, AnswerAccumulator, ConsentToolDispatcher, ConsentToolObserver (+17 more)

### Community 8 - "Bruja Static API Overview"
Cohesion: 0.16
Nodes (11): BrujaJSONLogitProcessor, BrujaJSONLogitProcessorTests, Any, BrujaJSONSchema, Float, Int, MLXArray, Set (+3 more)

### Community 9 - "Progress Renderer"
Cohesion: 0.09
Nodes (18): BrujaModelManager, SwiftTokenizersLoader, TokenizerAdapter, Bool, Int, MLXLMCommon, ModelContainer, String (+10 more)

### Community 10 - "Bruja Integration Tests"
Cohesion: 0.08
Nodes (23): MLXAgentLoopTranscriptTests, text, ReasoningEventTests, ReasoningTraceCheck, TextCollector, BrujaGenerationEvent, ReasoningTrace, GenerationSource (+15 more)

### Community 11 - "Tool Dispatch"
Cohesion: 0.07
Nodes (27): Configuration, MLXAgentLoop, BrujaGenerationEvent, info, reasoning, rejectedToolCall, toolCall, ChatInputBox (+19 more)

### Community 12 - "Tool Suite Tests"
Cohesion: 0.08
Nodes (22): BrujaIntegrationTests, IntegrationTestError, binaryNotFound, processFailure, timeout, BrujaError, agentStepLimitExceeded, contextWindowExceeded (+14 more)

### Community 13 - "MLX Agent Loop Transcript Tests"
Cohesion: 0.15
Nodes (8): MockBackendDispatchTests, ToolCallFlag, ToolDispatchHarness, Bool, String, T, Tool, URL

### Community 14 - "Path Guard Tests"
Cohesion: 0.13
Nodes (5): ToolSuiteTests, String, URL, GlobTool, RunShellTool

### Community 15 - "Path Guard"
Cohesion: 0.14
Nodes (17): AgentToolHandling, AgentTurnEvent, assistantText, toolCallStarted, toolFinished, dispatchStringTool(), dispatchTool(), MLXToolEncoding (+9 more)

### Community 16 - "Edit File Tool & Registry"
Cohesion: 0.17
Nodes (14): BrujaJSONSchema, Kind, array, boolean, boundedString, integer, number, object (+6 more)

### Community 17 - "Grep Tool"
Cohesion: 0.21
Nodes (5): IOCoordinatorTests, RecordingOutputWriter, ScriptedLineReader, Int, String

### Community 18 - "Preflight Manifest Test"
Cohesion: 0.23
Nodes (7): IOCoordinator, LineReader, OutputWriter, StandardLineReader, StandardOutputWriter, Bool, String

### Community 19 - "Run Shell Tool"
Cohesion: 0.15
Nodes (18): MLXLMCommon ChatSession (tools + toolDispatch), AgentBackend protocol (R1), AgentEvent stream (.token/.toolCall/.toolResult/.finished), BackendKind enum (.foundation/.mlx), bruja serve OpenAI-compatible endpoint (optional add-on), Divergence from WWDC video: in-process Swift agent, SwiftBruja Local Agentic CLI Requirements (Gap Analysis), Foundation Models backend (R2) (+10 more)

### Community 20 - "Shared Models Logging Test"
Cohesion: 0.24
Nodes (11): BrujaQuery, ConstrainedOutput, BrujaJSONSchema, BrujaQueryResult, BrujaThinking, Double, Float, Int (+3 more)

### Community 21 - "List Directory Tool"
Cohesion: 0.15
Nodes (17): Bruja static API, BrujaError, BrujaMemory, BrujaModelManager, BrujaQuery, BrujaTypes (BrujaQueryResult, BrujaModelInfo, BrujaThinking), SwiftAcervo, SwiftBruja (AGENTS.md) (+9 more)

### Community 22 - "Inference Integration Test"
Cohesion: 0.21
Nodes (3): PathGuardTests, String, URL

### Community 23 - "Foundation Model Backend"
Cohesion: 0.16
Nodes (6): ReadFileToolTests, String, String, URL, Arguments, ReadFileTool

### Community 24 - "Write File Tool"
Cohesion: 0.15
Nodes (16): AgentBackendSelector, MLXAgentLoop, MLXGeneration (GenerationSource, TurnState), mlx-swift-lm, Agent default model Qwen3.5-9B-MLX-4bit, swift-tokenizers (DePasqualeOrg), SwiftTokenizersLoader, Why swift-tokenizers not swift-transformers (+8 more)

### Community 25 - "Agent Seam Spike Test"
Cohesion: 0.16
Nodes (14): WU1 Default model check (BR-P4), WU2 Schema-constrained output (BR-P1), WU3 Peak memory (BR-P3), WU4 Thinking switch (BR-P2), Memory.cacheLimit (proposed fix for #48), MLX buffer cache dominates process footprint, PersonajeMemoryTests, Memory.peakMemory (+6 more)

### Community 26 - "Error Reporting Smoke Test"
Cohesion: 0.28
Nodes (7): Decision, allowed, denied, escapeRequested, PathGuard, Bool, String

### Community 27 - "Project Execution Plans"
Cohesion: 0.18
Nodes (5): String, Tool, Arguments, EditFileTool, ToolRegistry

### Community 28 - "Bruja Memory Management"
Cohesion: 0.23
Nodes (5): Bool, String, URL, Arguments, GrepTool

### Community 29 - "Tool Result Type"
Cohesion: 0.29
Nodes (5): PersonajeMemoryTests, Int, String, UInt64, Tokenizer

### Community 30 - "Foundation Backend Integration Test"
Cohesion: 0.16
Nodes (17): BrujaCLI (bruja executable), BrujaModelManager, ProgressRenderer helper, SwiftAcervo, AgentCommand (bruja agent), IOCoordinator actor, SwiftBruja Reference-Implementation Requirements for SwiftAcervo 0.8, ACERVO_OFFLINE offline-mode contract (+9 more)

### Community 31 - "Acervo Component Readiness Tests"
Cohesion: 0.19
Nodes (13): EXECUTION_PLAN — OPERATION MANIFEST AIRDROP, Sortie 1: Create CDN Upload Workflow, Sortie 2: Download all manifest files, Archived Documentation: Incomplete Tasks, Acervo.ensureAvailable, BrujaDownloadManager.downloadModel, CDNManifest v1 format, ensure-model-cdn.yml workflow (+5 more)

### Community 32 - "Bruja Error Tests"
Cohesion: 0.26
Nodes (7): PreflightManifestTest, ProcessResult, Int32, Set, String, TimeInterval, URL

### Community 33 - "Bruja Memory Tests"
Cohesion: 0.27
Nodes (10): SMALL_FIXTURE_MODEL Qwen2.5-0.5B-Instruct-4bit, PathGuard, App Group group.intrusive-memory.models entitlement (R6), App Group container unreadable under sandboxed xcodebuild test, ConsentToolObserver / ConsentToolWrapper placement, Operation Cauldron Whisper Iteration 01 Brief, Working-directory confinement guard (R6), Shared I/O coordinator concurrency wrinkle (R6.5) (+2 more)

### Community 34 - "Acervo Manifest Fetch Tests"
Cohesion: 0.20
Nodes (4): AgentReplTest, BrujaThinkingTests, URL, XCTestCase

### Community 35 - "Model Path & Listing Tests"
Cohesion: 0.20
Nodes (14): BrujaDownloadManager, ErrorReportingSmokeTest, mlx-community/Qwen3-Coder-Next-4bit model, Operation Lighthouse Plumbing Execution Plan, Pre-flight size via fetchManifest (R4), make reference-check verification target, Deletion sorties own test-caller migration (compile graph rule), Operation Snakeskin Molt Iteration 01 Brief (+6 more)

### Community 36 - "Agent REPL Test"
Cohesion: 0.20
Nodes (11): BrujaModelManager (vocabulary table cache), BrujaQuery.query(as:) (existing), BrujaQuery.query(_:schema:as:), ContainerGenerationSource.generate, BrujaError.structuredOutputTruncated, Open decision: age=./52 malformed output, Repetition penalty (ships default nil), JSON validity does not guarantee termination (+3 more)

### Community 37 - "Bruja Model Manager Tests"
Cohesion: 0.29
Nodes (10): Personaje prompt: HUNTER (major), Personaje prompt: SHANE (major), Personaje prompt: ARCHER (major), Personaje prompt: CLARK (major), Personaje prompt: KEVIN (major), Personaje prompt: TOBY (minor), Personaje prompt: IOLA (minor), Personaje prompt: DUKE (minor) (+2 more)

### Community 38 - "Path Resolution Tests"
Cohesion: 0.24
Nodes (3): String, Arguments, ListDirTool

### Community 39 - "Query Result Tests"
Cohesion: 0.22
Nodes (10): AgentCommand (bruja agent), BrujaCLI, Built-in agent tools (read_file, write_file, edit_file, list_dir, grep, glob, run_shell), FoundationModelBackend, FoundationModels framework, IOCoordinator, PathGuard, ProgressRenderer (+2 more)

### Community 40 - "Lighthouse & Snakeskin Docs"
Cohesion: 0.22
Nodes (3): InferenceIntegrationTest, String, TimeInterval

### Community 41 - "Swift Transformers Tokenizer"
Cohesion: 0.29
Nodes (10): BrujaJSONAcceptor, BrujaJSONLogitProcessor, BrujaJSONSchema, maxLength / maxItems bounds (OQ-5), make test-ci target, Position-only acceptor state (mask cache key), Decision OQ-2: token-mask LogitProcessor engine, Optional space after ':' and ',' (always-null first field fix) (+2 more)

### Community 42 - "Bruja Error"
Cohesion: 0.40
Nodes (9): fmt(), fmt_scene_header(), main(), major_excerpt(), minor_excerpt(), parse(), Return a list of scenes; each scene is {heading, elements:[(speaker, text)]}., read_fountain() (+1 more)

### Community 44 - "Community 44"
Cohesion: 0.22
Nodes (6): FoundationModelBackend, LanguageModelSession, BrujaError, Error, String, Tool

### Community 45 - "Community 45"
Cohesion: 0.28
Nodes (4): String, Tool, Arguments, WriteFileTool

### Community 46 - "Community 46"
Cohesion: 0.36
Nodes (8): BrujaJSONSchema + character-level acceptor, query(_:schema:as:) constrained path, Operation Straitjacket Parrot Completion Log, BrujaJSONLogitProcessor token mask, Peak-memory harness / Acceptance 3 waived (issue #48), Personaje test harness and fixtures, Repetition penalty (off by default), thinking: BrujaThinking parameter

### Community 47 - "Community 47"
Cohesion: 0.33
Nodes (6): FoundationModels LanguageModelSession, BrujaError agent cases, FoundationModels LanguageModelExecutor seam, MLXLanguageModel, MLXLanguageModelExecutor, Tokenizer source blocker / TokenizerBridge via swift-transformers

### Community 48 - "Community 48"
Cohesion: 0.31
Nodes (9): CDNManifest v1, .github/workflows/ensure-model-cdn.yml, LLMModelFiles (deleted), EXECUTION_PLAN: SwiftBruja CDN Model Integration, Operation Manifest Airdrop Iteration 01 Brief, Shared worktree commit collision lesson, Manifest Airdrop Completion Log, Manifest Airdrop Execution Plan (+1 more)

### Community 49 - "Community 49"
Cohesion: 0.44
Nodes (4): BrujaMemory, Int, Int64, UInt64

### Community 50 - "Community 50"
Cohesion: 0.20
Nodes (11): MLXLMCommon.LogitProcessor protocol, EXECUTION_PLAN — OPERATION STRAITJACKET PARROT, TokenIterator (mlx-swift-lm), OPERATION STRAITJACKET PARROT Iteration 01 Brief, Rollback verdict KEEP, AgentBackendSelector.swift, mlx-swift-lm dependency, RECON_REPORT — SwiftBruja (Personaje requirements) (+3 more)

### Community 51 - "Community 51"
Cohesion: 0.42
Nodes (3): Int, String, ToolResult

### Community 52 - "Community 52"
Cohesion: 0.36
Nodes (8): App Group sandbox limitation (ACERVO_APP_GROUP_ID), Release Binary workflow, Code Quality job, Draft PR CI gate, Integration Tests job, macOS Tests job, Tests workflow, Development workflow (development → main)

### Community 53 - "Community 53"
Cohesion: 0.32
Nodes (4): AgentTurnEvent, AgentSeamSpikeTest, EventLog, String

### Community 57 - "Community 57"
Cohesion: 0.48
Nodes (7): BrujaJSONSchema, Personaje acceptance & memory tests, BrujaJSONAcceptor, 1.11.0 schema-constrained output, thinking, unload API, The age rule (never null), Personaje prompt fixtures, Personaje schema.json

### Community 58 - "Community 58"
Cohesion: 0.18
Nodes (11): Bruja.query(_:schema:as:) public overload, build-fixtures.py, Fixtures/Personaje/schema.json, Fixtures/Personaje prompt fixtures, granville-2026SEP08.highland script, make test-agent-seam recipe, make test-personaje target, PersonajeAcceptanceTests (+3 more)

### Community 59 - "Community 59"
Cohesion: 0.38
Nodes (4): AcervoManifestFetchTests, Set, String, URL

### Community 61 - "Community 61"
Cohesion: 0.29
Nodes (7): Mission/Sortie/Work Unit supervisor process, Operation Cauldron Whisper Execution Plan, Qwen2.5-7B-Instruct-4bit agentic default, ReadFileTool, Built-in tool suite (run_shell, write/edit_file, list_dir, grep/glob), ToolRegistry, Model selection & agentic default (R7)

### Community 64 - "Community 64"
Cohesion: 0.50
Nodes (5): thinking: .off parameter, enable_thinking in Qwen3.5 chat_template.jinja, BR-P2 Thinking mode switch (#50), Qwen3.5-9B-MLX-4bit, BrujaThinkingTests

## Ambiguous Edges - Review These
- `SwiftBruja Local Agentic CLI Requirements (Gap Analysis)` → `SwiftAcervo 0.14.0 → 0.16.0 Upgrade Audit`  [AMBIGUOUS]
  docs/REQUIREMENTS.md · relation: conceptually_related_to
- `BrujaModelManager` → `BrujaJSONSchema + character-level acceptor`  [AMBIGUOUS]
  docs/complete/straitjacket-parrot-01/COMPLETE_SwiftBruja.md · relation: conceptually_related_to
- `Shared worktree commit collision lesson` → `Predecessor reality audit lesson`  [AMBIGUOUS]
  docs/complete/snakeskin-molt-01-brief.md · relation: semantically_similar_to
- `BrujaQuery.query(_:schema:as:)` → `Open decision: age=./52 malformed output`  [AMBIGUOUS]
  docs/complete/straitjacket-parrot-01/OPERATION_STRAITJACKET_PARROT_01_BRIEF.md · relation: references
- `Qwen2.5-7B-Instruct-4bit (Personaje default model)` → `Qwen3-Coder-Next-4bit (default model)`  [AMBIGUOUS]
  docs/incomplete/REQUIREMENTS_CDN_WORKFLOW.md · relation: conceptually_related_to

## Knowledge Gaps
- **212 isolated node(s):** `Double`, `Sendable`, `Bool`, `mlx`, `foundation` (+207 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **10 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `SwiftBruja Local Agentic CLI Requirements (Gap Analysis)` and `SwiftAcervo 0.14.0 → 0.16.0 Upgrade Audit`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `BrujaModelManager` and `BrujaJSONSchema + character-level acceptor`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `Shared worktree commit collision lesson` and `Predecessor reality audit lesson`?**
  _Edge tagged AMBIGUOUS (relation: semantically_similar_to) - confidence is low._
- **What is the exact relationship between `BrujaQuery.query(_:schema:as:)` and `Open decision: age=./52 malformed output`?**
  _Edge tagged AMBIGUOUS (relation: references) - confidence is low._
- **What is the exact relationship between `Qwen2.5-7B-Instruct-4bit (Personaje default model)` and `Qwen3-Coder-Next-4bit (default model)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `MLXLMCommon` connect `Progress Renderer` to `Agent Backend Selection`, `Mock Backend Dispatch Tests`, `MLX Agent Loop & Generation`, `Bruja Core Types`, `Bruja Integration Tests`, `Tool Dispatch`, `Path Guard`, `Shared Models Logging Test`?**
  _High betweenness centrality (0.158) - this node is a cross-community bridge._
- **Why does `BrujaJSONAcceptorTests` connect `Tokenizer Bridge` to `Acervo Manifest Fetch Tests`?**
  _High betweenness centrality (0.069) - this node is a cross-community bridge._