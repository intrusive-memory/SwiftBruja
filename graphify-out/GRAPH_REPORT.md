# Graph Report - .  (2026-11-21)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 1296 nodes · 2563 edges · 70 communities (60 shown, 10 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 155 edges (avg confidence: 0.79)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `6499c753`
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
- [[_COMMUNITY_Community 62|Community 62]]
- [[_COMMUNITY_Community 63|Community 63]]
- [[_COMMUNITY_Community 64|Community 64]]
- [[_COMMUNITY_Community 65|Community 65]]
- [[_COMMUNITY_Community 66|Community 66]]
- [[_COMMUNITY_Community 67|Community 67]]
- [[_COMMUNITY_Community 68|Community 68]]

## God Nodes (most connected - your core abstractions)
1. `BrujaJSONAcceptorTests` - 61 edges
2. `SwiftBruja AGENTS.md` - 45 edges
3. `BrujaJSONLogitProcessorTests` - 41 edges
4. `ToolSuiteTests` - 33 edges
5. `PersonajeAcceptanceTests` - 29 edges
6. `ProgressRenderer` - 28 edges
7. `BrujaJSONAcceptor` - 26 edges
8. `Phase` - 25 edges
9. `BrujaJSONLogitProcessor` - 24 edges
10. `RecordingOutputWriter` - 20 edges

## Surprising Connections (you probably didn't know these)
- `Discovery: tokenizer has no vocabulary-size property` --references--> `BrujaModelManager`  [EXTRACTED]
  docs/complete/straitjacket-parrot-01/OPERATION_STRAITJACKET_PARROT_01_BRIEF.md → Sources/SwiftBruja/Core/BrujaModelManager.swift
- `CHANGELOG` --semantically_similar_to--> `SwiftBruja AGENTS.md`  [INFERRED] [semantically similar]
  CHANGELOG.md → AGENTS.md
- `README` --semantically_similar_to--> `SwiftBruja AGENTS.md`  [INFERRED] [semantically similar]
  README.md → AGENTS.md
- `BrujaJSONAcceptor` --implements--> `Position-only acceptor state (mask cache key)`  [EXTRACTED]
  Sources/SwiftBruja/Core/BrujaJSONAcceptor.swift → docs/complete/straitjacket-parrot-01/EXECUTION_PLAN.md
- `Discovery: compact-only mask forces null (space after colon)` --references--> `BrujaJSONAcceptor`  [EXTRACTED]
  docs/complete/straitjacket-parrot-01/OPERATION_STRAITJACKET_PARROT_01_BRIEF.md → Sources/SwiftBruja/Core/BrujaJSONAcceptor.swift

## Import Cycles
- None detected.

## Communities (70 total, 10 thin omitted)

### Community 0 - "Agent Backend Selection"
Cohesion: 0.05
Nodes (39): AsyncParsableCommand, BrujaCLI, ChatCommand, DownloadCommand, InfoCommand, ListCommand, QueryCommand, CLIError (+31 more)

### Community 1 - "Agent Command & Loop"
Cohesion: 0.08
Nodes (8): BrujaJSONAcceptorTests, BrujaJSONAcceptor, BrujaJSONSchema, Character, Int, StaticString, String, UInt

### Community 2 - "Tokenizer Bridge"
Cohesion: 0.05
Nodes (25): AgentAllowlist, AgentBackend, foundation, mlx, AgentBackendSelector, BrujaError, FoundationModelsAvailabilityProvider, FoundationModelsUnavailableError (+17 more)

### Community 3 - "IO Coordinator"
Cohesion: 0.07
Nodes (27): AcervoModel, BrujaModelInfo, BrujaQueryResult, Codable, BrujaQueryResult, Date, Double, ModelContainer (+19 more)

### Community 4 - "Bruja CLI Commands"
Cohesion: 0.06
Nodes (33): Configuration, MLXAgentLoop, BrujaGenerationEvent, info, reasoning, rejectedToolCall, toolCall, ChatInputBox (+25 more)

### Community 5 - "Mock Backend Dispatch Tests"
Cohesion: 0.09
Nodes (43): AgentBackendSelector, bruja agent command, swift-argument-parser, bruja agent CLI command, bruja agent CLI (REPL + one-shot), BrujaCLI, Built-in agent tool suite (7 tools), Queryable graphify codemap (+35 more)

### Community 6 - "MLX Agent Loop & Generation"
Cohesion: 0.11
Nodes (25): AgentBackend, Arguments, AgentCommand, AgentLoop, AnswerAccumulator, ConsentToolDispatcher, ConsentToolObserver, ConsentToolWrapper (+17 more)

### Community 7 - "Bruja Core Types"
Cohesion: 0.16
Nodes (12): BrujaJSONLogitProcessor, Int32, BrujaJSONLogitProcessorTests, Any, BrujaJSONSchema, Float, Int, MLXArray (+4 more)

### Community 8 - "Bruja Static API Overview"
Cohesion: 0.08
Nodes (20): MLXAgentLoopTranscriptTests, BrujaGenerationEvent, BrujaModelManager, GenerationSource, MLXAgentLoop, MLXLMCommon, SharedMockGenerationSource, Bool (+12 more)

### Community 9 - "Progress Renderer"
Cohesion: 0.12
Nodes (18): text, ReasoningEventTests, ReasoningTraceCheck, TextCollector, BrujaQuery, ConstrainedOutput, GenerateParameters, BrujaJSONSchema (+10 more)

### Community 10 - "Bruja Integration Tests"
Cohesion: 0.14
Nodes (34): Gareth (character), Hunter Rhodes (character), Shared Personaje instruction block (14 fields, age never null), Joann Rhodes (character), Personaje prompt 01: HUNTER (major), Ray Rhodes (character), Cyrus (character), Kieran (character) (+26 more)

### Community 11 - "Tool Dispatch"
Cohesion: 0.11
Nodes (19): PersonajeMemoryTests, BrujaMemory, MLXLMCommon.LogitProcessor, MLXLMCommon.TokenIterator, Sortie 4: Token-mask logit processor, MLX GPU.cacheLimit / GPU.clearCache, MLX Memory.peakMemory, Discovery: MLX peak counter excludes buffer cache (+11 more)

### Community 12 - "Tool Suite Tests"
Cohesion: 0.08
Nodes (22): BrujaIntegrationTests, IntegrationTestError, binaryNotFound, processFailure, timeout, BrujaError, agentStepLimitExceeded, contextWindowExceeded (+14 more)

### Community 13 - "MLX Agent Loop Transcript Tests"
Cohesion: 0.14
Nodes (30): Breaking changes: BrujaDownloadManager and registry shim removed, Bruja Static API, Bruja Static API, bruja CLI, Bruja static API (query, queryWithMetadata, listModels), BrujaError, BrujaMemory, BrujaModelManager (+22 more)

### Community 14 - "Path Guard Tests"
Cohesion: 0.14
Nodes (26): BrujaJSONSchema, Makefile build/test targets (make install, test-ci, test-personaje...), mlx-swift dependency, PersonajeAcceptanceTests, PersonajeMemoryTests, Agent default model mlx-community/Qwen3.5-9B-MLX-4bit, BrujaJSONAcceptor, Issue #48: long-prompt memory footprint remains open (+18 more)

### Community 15 - "Path Guard"
Cohesion: 0.16
Nodes (16): BrujaJSONSchema, Kind, array, boolean, boundedString, integer, number, object (+8 more)

### Community 16 - "Edit File Tool & Registry"
Cohesion: 0.15
Nodes (8): MockBackendDispatchTests, ToolCallFlag, ToolDispatchHarness, Bool, String, T, Tool, URL

### Community 17 - "Grep Tool"
Cohesion: 0.14
Nodes (17): AgentToolHandling, AgentTurnEvent, assistantText, toolCallStarted, toolFinished, dispatchStringTool(), dispatchTool(), MLXToolEncoding (+9 more)

### Community 18 - "Preflight Manifest Test"
Cohesion: 0.14
Nodes (5): ToolSuiteTests, String, URL, GlobTool, ListDirTool

### Community 19 - "Run Shell Tool"
Cohesion: 0.17
Nodes (15): BrujaJSONLogitProcessor, MaskCache, DType, Position-only acceptor state (mask cache key), LogitProcessor, Discovery: blanket repetition penalty pushes fields to null, Discovery: compact-only mask forces null (space after colon), RepetitionContext (+7 more)

### Community 20 - "Shared Models Logging Test"
Cohesion: 0.09
Nodes (23): Phase, none, numberExponent, numberExponentDigits, numberExponentSign, numberFraction, numberInteger, numberMinus (+15 more)

### Community 21 - "List Directory Tool"
Cohesion: 0.21
Nodes (5): IOCoordinatorTests, RecordingOutputWriter, ScriptedLineReader, Int, String

### Community 22 - "Inference Integration Test"
Cohesion: 0.13
Nodes (22): App Group sandbox limitation for real-inference tests, CI Gating section (claims macos-26 runners), Fixtures/Personaje acceptance and memory tests, BrujaGenerationEvent.reasoning case, BrujaThinking switch, CI pipefail fix (tests could not fail), v1.11.0: schema-constrained output, thinking switch, unload API, v1.11.1: dependency floors, CI on xcode-27 (+14 more)

### Community 23 - "Foundation Model Backend"
Cohesion: 0.17
Nodes (8): Bruja.queryWithMetadata, PersonajeAcceptanceTests, Open Decision: age=./52 on unbounded two-field schema, Any, Bool, BrujaJSONSchema, StaticString, URL

### Community 24 - "Write File Tool"
Cohesion: 0.23
Nodes (7): IOCoordinator, LineReader, OutputWriter, StandardLineReader, StandardOutputWriter, Bool, String

### Community 25 - "Agent Seam Spike Test"
Cohesion: 0.30
Nodes (8): BrujaJSONAcceptor, Counters, State, Node, Phase, Bool, Character, Int

### Community 26 - "Error Reporting Smoke Test"
Cohesion: 0.21
Nodes (3): PathGuardTests, String, URL

### Community 27 - "Project Execution Plans"
Cohesion: 0.16
Nodes (6): ReadFileToolTests, String, String, URL, Arguments, ReadFileTool

### Community 28 - "Bruja Memory Management"
Cohesion: 0.12
Nodes (16): CodingKeys, age, appearance, arc, backstory, canonFacts, languages, logline (+8 more)

### Community 29 - "Tool Result Type"
Cohesion: 0.17
Nodes (15): BrujaThinking, modelDefault, off, WU1 Default Model Check (BR-P4), WU2 Schema-Constrained Output (BR-P1), WU3 Peak Memory (BR-P3), WU4 Thinking Switch (BR-P2), WU5 Documentation (+7 more)

### Community 30 - "Foundation Backend Integration Test"
Cohesion: 0.12
Nodes (3): AcervoComponentReadyTests, BrujaConcurrencyTests, BrujaErrorTests

### Community 31 - "Acervo Component Readiness Tests"
Cohesion: 0.19
Nodes (13): Acervo.isModelConfigPresent, Bruja.query(_:schema:as:), BrujaError.structuredOutputTruncated(tokenLimit:), BrujaQuery.cleanJSONResponse, BrujaQuery.query(as:), BrujaQuery.query(_:schema:as:), Replan of 2026-10-03 (Sorties 6A–6D), Sortie 5: query(_:schema:as:) on the constrained path (+5 more)

### Community 32 - "Bruja Error Tests"
Cohesion: 0.28
Nodes (7): Decision, allowed, denied, escapeRequested, PathGuard, Bool, String

### Community 33 - "Bruja Memory Tests"
Cohesion: 0.18
Nodes (5): String, Tool, Arguments, EditFileTool, ToolRegistry

### Community 34 - "Acervo Manifest Fetch Tests"
Cohesion: 0.23
Nodes (5): Bool, String, URL, Arguments, GrepTool

### Community 35 - "Model Path & Listing Tests"
Cohesion: 0.17
Nodes (4): AgentReplTest, BrujaModelManagerTests, URL, XCTestCase

### Community 36 - "Agent REPL Test"
Cohesion: 0.26
Nodes (7): PreflightManifestTest, ProcessResult, Int32, Set, String, TimeInterval, URL

### Community 37 - "Bruja Model Manager Tests"
Cohesion: 0.22
Nodes (3): String, Arguments, RunShellTool

### Community 38 - "Path Resolution Tests"
Cohesion: 0.29
Nodes (5): ProcessResult, SharedModelsLoggingTest, Int32, String, TimeInterval

### Community 39 - "Query Result Tests"
Cohesion: 0.22
Nodes (11): Fixtures/Personaje/build-fixtures.py, Sortie 2: Personaje prompt fixtures, Execution Plan — Operation Straitjacket Parrot 01, granville-2026SEP08.highland (source script), Discovery: long GPU test runs fragile under contention, Personaje (intrusive-memory app), A-09/A-10: nine prompts and HUNTER prompt not on disk, Recon Report — SwiftBruja (Personaje requirements) (+3 more)

### Community 40 - "Lighthouse & Snakeskin Docs"
Cohesion: 0.22
Nodes (3): InferenceIntegrationTest, String, TimeInterval

### Community 41 - "Swift Transformers Tokenizer"
Cohesion: 0.53
Nodes (3): Compiler, BrujaJSONSchema, String

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
Cohesion: 0.33
Nodes (5): ErrorReportingSmokeTest, ProcessResult, Int32, String, TimeInterval

### Community 47 - "Community 47"
Cohesion: 0.42
Nodes (7): CanonFact, PersonajeProfile, Relationship, Decodable, Decoder, Equatable, String

### Community 48 - "Community 48"
Cohesion: 0.39
Nodes (9): BrujaDownloadManager, SwiftAcervo / Acervo Storage API, Operation Cauldron Whisper — Execution Plan, Operation Manifest Airdrop — Execution Plan, Operation Cauldron Whisper — Iteration 01 Brief, Archived Documentation: Incomplete Tasks (README), CDN Model Distribution for SwiftBruja (Requirements), Snakeskin Molt 01 — Shed the Download Manager Wrapper (Requirements) (+1 more)

### Community 49 - "Community 49"
Cohesion: 0.22
Nodes (9): Node, arrayAfterItem, arrayOpen, done, literal, number, optionalSpace, string (+1 more)

### Community 50 - "Community 50"
Cohesion: 0.42
Nodes (3): Int, String, ToolResult

### Community 51 - "Community 51"
Cohesion: 0.32
Nodes (8): #huggingFaceTokenizerLoader() macro (MLXHuggingFace), MLXHuggingFace, huggingface/swift-transformers, swift-transformers, TokenizerBridge, Release 1.9.0 (TokenizerBridge replaced by macro), TokenizerBridge.swift (removed), v1.9.0: TokenizerBridge replaced by macro

### Community 52 - "Community 52"
Cohesion: 0.32
Nodes (4): AgentTurnEvent, AgentSeamSpikeTest, EventLog, String

### Community 53 - "Community 53"
Cohesion: 0.32
Nodes (3): FoundationBackendIntegrationTest, Bool, URL

### Community 55 - "Community 55"
Cohesion: 0.33
Nodes (7): Decision OQ-5: termination via maxLength and maxItems, Sortie 1: Personaje test harness and default-model smoke test, Sortie 6A: Length bounds in schema, acceptor and logit processor, Makefile target test-personaje, mlx-community/Qwen2.5-7B-Instruct-4bit (default model), A-08: Qwen2.5-7B-Instruct-4bit present in SharedModels, BR-P4: Confirm default model runs through Bruja

### Community 56 - "Community 56"
Cohesion: 0.38
Nodes (4): AcervoManifestFetchTests, Set, String, URL

### Community 58 - "Community 58"
Cohesion: 0.47
Nodes (3): ReasoningTrace, Bool, String

### Community 59 - "Community 59"
Cohesion: 0.40
Nodes (3): Makefile target test-ci, BrujaThinkingTests, Test Cleanup Report — Straitjacket Parrot 01

### Community 63 - "Community 63"
Cohesion: 0.50
Nodes (4): Manifest Airdrop Brief, Manifest Airdrop Completion Log, Manifest Airdrop Execution Plan, Manifest Airdrop Supervisor State

### Community 64 - "Community 64"
Cohesion: 0.67
Nodes (4): Lighthouse Plumbing Execution Plan, Lighthouse Plumbing Requirements, Snakeskin Molt Brief, Snakeskin Molt Execution Plan

## Ambiguous Edges - Review These
- `Snakeskin Molt 01 — Shed the Download Manager Wrapper (Requirements)` → `CDN Model Distribution for SwiftBruja (Requirements)`  [AMBIGUOUS]
  docs/complete/snakeskin-molt-01-requirements.md · relation: conceptually_related_to
- `README.md` → `xcode-27 GitHub Actions runner`  [AMBIGUOUS]
  README.md · relation: conceptually_related_to
- `CI Gating section (claims macos-26 runners)` → `xcode-27 GitHub Actions runner`  [AMBIGUOUS]
  AGENTS.md · relation: conceptually_related_to
- `CI Gating section (claims macos-26 runners)` → `Tests workflow`  [AMBIGUOUS]
  AGENTS.md · relation: references
- `v1.8.0: bruja agent CLI, macOS 26 retarget` → `Models directory ~/Library/SharedModels`  [AMBIGUOUS]
  README.md · relation: conceptually_related_to

## Knowledge Gaps
- **202 isolated node(s):** `Double`, `Sendable`, `mlx`, `foundation`, `Set` (+197 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **10 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Snakeskin Molt 01 — Shed the Download Manager Wrapper (Requirements)` and `CDN Model Distribution for SwiftBruja (Requirements)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `README.md` and `xcode-27 GitHub Actions runner`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `CI Gating section (claims macos-26 runners)` and `xcode-27 GitHub Actions runner`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **What is the exact relationship between `CI Gating section (claims macos-26 runners)` and `Tests workflow`?**
  _Edge tagged AMBIGUOUS (relation: references) - confidence is low._
- **What is the exact relationship between `v1.8.0: bruja agent CLI, macOS 26 retarget` and `Models directory ~/Library/SharedModels`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `BrujaJSONAcceptorTests` connect `Agent Command & Loop` to `Community 67`, `Model Path & Listing Tests`, `Query Result Tests`, `Agent Seam Spike Test`, `Community 59`?**
  _High betweenness centrality (0.104) - this node is a cross-community bridge._
- **Why does `BrujaJSONAcceptor` connect `Agent Seam Spike Test` to `Agent Command & Loop`, `Community 67`, `Swift Transformers Tokenizer`, `Path Guard`, `Run Shell Tool`, `Community 55`?**
  _High betweenness centrality (0.091) - this node is a cross-community bridge._