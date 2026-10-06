# Graph Report - .  (2026-10-05)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 1249 nodes · 2464 edges · 61 communities (51 shown, 10 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 145 edges (avg confidence: 0.79)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `a06c7e31`
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

## Communities (61 total, 10 thin omitted)

### Community 0 - "Agent Backend Selection"
Cohesion: 0.05
Nodes (37): AsyncParsableCommand, BrujaCLI, ChatCommand, DownloadCommand, InfoCommand, ListCommand, QueryCommand, CLIError (+29 more)

### Community 1 - "Agent Command & Loop"
Cohesion: 0.06
Nodes (46): Acervo.isModelConfigPresent, Bruja.query(_:schema:as:), BrujaError.structuredOutputTruncated(tokenLimit:), PersonajeMemoryTests, BrujaQuery.cleanJSONResponse, BrujaQuery.query(as:), BrujaQuery.query(_:schema:as:), BrujaJSONLogitProcessor (+38 more)

### Community 2 - "Tokenizer Bridge"
Cohesion: 0.08
Nodes (8): BrujaJSONAcceptorTests, BrujaJSONAcceptor, BrujaJSONSchema, Character, Int, StaticString, String, UInt

### Community 3 - "IO Coordinator"
Cohesion: 0.05
Nodes (44): AcervoModel, BrujaModelInfo, Fixtures/Personaje/build-fixtures.py, Codable, BrujaQueryResult, BrujaThinking, modelDefault, off (+36 more)

### Community 4 - "Bruja CLI Commands"
Cohesion: 0.05
Nodes (27): AgentAllowlist, AgentBackend, foundation, mlx, AgentBackendSelector, BrujaError, FoundationModelsAvailabilityProvider, FoundationModelsUnavailableError (+19 more)

### Community 5 - "Mock Backend Dispatch Tests"
Cohesion: 0.07
Nodes (33): Bruja.queryWithMetadata, CanonFact, CodingKeys, age, appearance, arc, backstory, canonFacts (+25 more)

### Community 6 - "MLX Agent Loop & Generation"
Cohesion: 0.09
Nodes (28): AgentBackend, AgentToolHandling, Arguments, AgentCommand, AgentLoop, AnswerAccumulator, ConsentToolDispatcher, ConsentToolObserver (+20 more)

### Community 7 - "Bruja Core Types"
Cohesion: 0.16
Nodes (12): BrujaJSONLogitProcessor, Int32, BrujaJSONLogitProcessorTests, Any, BrujaJSONSchema, Float, Int, MLXArray (+4 more)

### Community 8 - "Bruja Static API Overview"
Cohesion: 0.08
Nodes (26): Configuration, MLXAgentLoop, BrujaGenerationEvent, info, text, toolCall, ChatInputBox, ContainerGenerationSource (+18 more)

### Community 9 - "Progress Renderer"
Cohesion: 0.08
Nodes (20): MLXAgentLoopTranscriptTests, BrujaGenerationEvent, BrujaModelManager, GenerationSource, MLXAgentLoop, MLXLMCommon, SharedMockGenerationSource, Bool (+12 more)

### Community 10 - "Bruja Integration Tests"
Cohesion: 0.11
Nodes (37): AgentBackendSelector, bruja agent command, swift-argument-parser, bruja agent CLI (REPL + one-shot), BrujaCLI, Built-in agent tool suite (7 tools), Queryable graphify codemap, EditFileTool (+29 more)

### Community 11 - "Tool Dispatch"
Cohesion: 0.14
Nodes (34): Gareth (character), Hunter Rhodes (character), Shared Personaje instruction block (14 fields, age never null), Joann Rhodes (character), Personaje prompt 01: HUNTER (major), Ray Rhodes (character), Cyrus (character), Kieran (character) (+26 more)

### Community 12 - "Tool Suite Tests"
Cohesion: 0.08
Nodes (22): BrujaIntegrationTests, IntegrationTestError, binaryNotFound, processFailure, timeout, BrujaError, agentStepLimitExceeded, contextWindowExceeded (+14 more)

### Community 13 - "MLX Agent Loop Transcript Tests"
Cohesion: 0.10
Nodes (42): Bruja Static API, BrujaError, BrujaJSONSchema, BrujaMemory, BrujaQuery, BrujaTypes, Makefile build/test targets (make install, test-ci, test-personaje...), mlx-swift (+34 more)

### Community 14 - "Path Guard Tests"
Cohesion: 0.13
Nodes (23): App Group sandbox limitation for real-inference tests, Breaking changes: BrujaDownloadManager and registry shim removed, Bruja Static API, bruja CLI, BrujaModelManager, #huggingFaceTokenizerLoader() macro (MLXHuggingFace), MLXHuggingFace, mlx-swift-lm (+15 more)

### Community 15 - "Path Guard"
Cohesion: 0.16
Nodes (16): BrujaJSONSchema, Kind, array, boolean, boundedString, integer, number, object (+8 more)

### Community 16 - "Edit File Tool & Registry"
Cohesion: 0.15
Nodes (8): MockBackendDispatchTests, ToolCallFlag, ToolDispatchHarness, Bool, String, T, Tool, URL

### Community 17 - "Grep Tool"
Cohesion: 0.13
Nodes (16): BrujaQueryResult, ModelContainer, Bool, BrujaJSONSchema, BrujaQueryResult, BrujaThinking, Float, Int (+8 more)

### Community 18 - "Preflight Manifest Test"
Cohesion: 0.14
Nodes (17): AgentToolHandling, AgentTurnEvent, assistantText, toolCallStarted, toolFinished, dispatchStringTool(), dispatchTool(), MLXToolEncoding (+9 more)

### Community 19 - "Run Shell Tool"
Cohesion: 0.14
Nodes (5): ToolSuiteTests, String, URL, GlobTool, ListDirTool

### Community 20 - "Shared Models Logging Test"
Cohesion: 0.09
Nodes (23): Phase, none, numberExponent, numberExponentDigits, numberExponentSign, numberFraction, numberInteger, numberMinus (+15 more)

### Community 21 - "List Directory Tool"
Cohesion: 0.21
Nodes (5): IOCoordinatorTests, RecordingOutputWriter, ScriptedLineReader, Int, String

### Community 22 - "Inference Integration Test"
Cohesion: 0.23
Nodes (7): IOCoordinator, LineReader, OutputWriter, StandardLineReader, StandardOutputWriter, Bool, String

### Community 23 - "Foundation Model Backend"
Cohesion: 0.30
Nodes (8): BrujaJSONAcceptor, Counters, State, Node, Phase, Bool, Character, Int

### Community 24 - "Write File Tool"
Cohesion: 0.25
Nodes (11): BrujaQuery, ConstrainedOutput, BrujaJSONSchema, BrujaQueryResult, BrujaThinking, Double, Float, Int (+3 more)

### Community 25 - "Agent Seam Spike Test"
Cohesion: 0.21
Nodes (3): PathGuardTests, String, URL

### Community 26 - "Error Reporting Smoke Test"
Cohesion: 0.16
Nodes (6): ReadFileToolTests, String, String, URL, Arguments, ReadFileTool

### Community 27 - "Project Execution Plans"
Cohesion: 0.14
Nodes (3): BrujaConcurrencyTests, BrujaPathResolutionTests, BrujaQueryResultTests

### Community 28 - "Bruja Memory Management"
Cohesion: 0.28
Nodes (7): Decision, allowed, denied, escapeRequested, PathGuard, Bool, String

### Community 29 - "Tool Result Type"
Cohesion: 0.18
Nodes (5): String, Tool, Arguments, EditFileTool, ToolRegistry

### Community 30 - "Foundation Backend Integration Test"
Cohesion: 0.23
Nodes (5): Bool, String, URL, Arguments, GrepTool

### Community 31 - "Acervo Component Readiness Tests"
Cohesion: 0.18
Nodes (5): FoundationBackendIntegrationTest, AcervoComponentReadyTests, Bool, URL, XCTestCase

### Community 32 - "Bruja Error Tests"
Cohesion: 0.26
Nodes (7): PreflightManifestTest, ProcessResult, Int32, Set, String, TimeInterval, URL

### Community 33 - "Bruja Memory Tests"
Cohesion: 0.22
Nodes (3): String, Arguments, RunShellTool

### Community 35 - "Model Path & Listing Tests"
Cohesion: 0.29
Nodes (5): ProcessResult, SharedModelsLoggingTest, Int32, String, TimeInterval

### Community 36 - "Agent REPL Test"
Cohesion: 0.22
Nodes (3): InferenceIntegrationTest, String, TimeInterval

### Community 37 - "Bruja Model Manager Tests"
Cohesion: 0.53
Nodes (3): Compiler, BrujaJSONSchema, String

### Community 38 - "Path Resolution Tests"
Cohesion: 0.40
Nodes (9): fmt(), fmt_scene_header(), main(), major_excerpt(), minor_excerpt(), parse(), Return a list of scenes; each scene is {heading, elements:[(speaker, text)]}., read_fountain() (+1 more)

### Community 40 - "Lighthouse & Snakeskin Docs"
Cohesion: 0.22
Nodes (6): FoundationModelBackend, LanguageModelSession, BrujaError, Error, String, Tool

### Community 41 - "Swift Transformers Tokenizer"
Cohesion: 0.28
Nodes (4): String, Tool, Arguments, WriteFileTool

### Community 42 - "Bruja Error"
Cohesion: 0.33
Nodes (5): ErrorReportingSmokeTest, ProcessResult, Int32, String, TimeInterval

### Community 43 - "Package Manifest"
Cohesion: 0.39
Nodes (9): BrujaDownloadManager, SwiftAcervo / Acervo Storage API, Operation Cauldron Whisper — Execution Plan, Operation Manifest Airdrop — Execution Plan, Operation Cauldron Whisper — Iteration 01 Brief, Archived Documentation: Incomplete Tasks (README), CDN Model Distribution for SwiftBruja (Requirements), Snakeskin Molt 01 — Shed the Download Manager Wrapper (Requirements) (+1 more)

### Community 44 - "Community 44"
Cohesion: 0.22
Nodes (9): Node, arrayAfterItem, arrayOpen, done, literal, number, optionalSpace, string (+1 more)

### Community 45 - "Community 45"
Cohesion: 0.44
Nodes (4): BrujaMemory, Int, Int64, UInt64

### Community 46 - "Community 46"
Cohesion: 0.42
Nodes (3): Int, String, ToolResult

### Community 47 - "Community 47"
Cohesion: 0.32
Nodes (4): AgentTurnEvent, AgentSeamSpikeTest, EventLog, String

### Community 50 - "Community 50"
Cohesion: 0.38
Nodes (4): AcervoManifestFetchTests, Set, String, URL

### Community 52 - "Community 52"
Cohesion: 0.47
Nodes (3): ReasoningTrace, Bool, String

### Community 55 - "Community 55"
Cohesion: 0.50
Nodes (4): Manifest Airdrop Brief, Manifest Airdrop Completion Log, Manifest Airdrop Execution Plan, Manifest Airdrop Supervisor State

### Community 56 - "Community 56"
Cohesion: 0.67
Nodes (4): Lighthouse Plumbing Execution Plan, Lighthouse Plumbing Requirements, Snakeskin Molt Brief, Snakeskin Molt Execution Plan

## Ambiguous Edges - Review These
- `Snakeskin Molt 01 — Shed the Download Manager Wrapper (Requirements)` → `CDN Model Distribution for SwiftBruja (Requirements)`  [AMBIGUOUS]
  docs/complete/snakeskin-molt-01-requirements.md · relation: conceptually_related_to

## Knowledge Gaps
- **195 isolated node(s):** `Double`, `Sendable`, `mlx`, `foundation`, `Set` (+190 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **10 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Snakeskin Molt 01 — Shed the Download Manager Wrapper (Requirements)` and `CDN Model Distribution for SwiftBruja (Requirements)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `BrujaJSONAcceptorTests` connect `Tokenizer Bridge` to `IO Coordinator`, `Community 59`, `Acervo Component Readiness Tests`, `Foundation Model Backend`?**
  _High betweenness centrality (0.115) - this node is a cross-community bridge._
- **Why does `BrujaJSONAcceptor` connect `Foundation Model Backend` to `Agent Command & Loop`, `Tokenizer Bridge`, `Bruja Model Manager Tests`, `Path Guard`, `Community 59`?**
  _High betweenness centrality (0.097) - this node is a cross-community bridge._
- **Why does `PersonajeAcceptanceTests` connect `Mock Backend Dispatch Tests` to `Agent Command & Loop`, `IO Coordinator`, `Acervo Component Readiness Tests`?**
  _High betweenness centrality (0.066) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `SwiftBruja AGENTS.md` (e.g. with `CHANGELOG` and `README`) actually correct?**
  _`SwiftBruja AGENTS.md` has 4 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Double`, `Sendable`, `mlx` to the rest of the system?**
  _202 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Agent Backend Selection` be split into smaller, more focused modules?**
  _Cohesion score 0.05365296803652968 - nodes in this community are weakly interconnected._