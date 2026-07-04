# Graph Report - .  (2026-07-04)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 791 nodes · 1346 edges · 46 communities (37 shown, 9 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 106 edges (avg confidence: 0.78)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `054f8c1c`
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

## God Nodes (most connected - your core abstractions)
1. `ToolSuiteTests` - 33 edges
2. `ProgressRenderer` - 28 edges
3. `RecordingOutputWriter` - 20 edges
4. `ScriptedLineReader` - 19 edges
5. `ConsentToolObserver` - 18 edges
6. `BrujaModelInfo` - 17 edges
7. `MockBackendDispatchTests` - 17 edges
8. `String` - 16 edges
9. `BrujaError` - 15 edges
10. `IOCoordinatorTests` - 15 edges

## Surprising Connections (you probably didn't know these)
- `SwiftBruja Logo (wooden mannequin wizard meditating)` --references--> `SwiftBruja README`  [EXTRACTED]
  SwiftBruja.jpg → README.md
- `SwiftBruja Icon (small mannequin wizard)` --semantically_similar_to--> `SwiftBruja Logo (wooden mannequin wizard meditating)`  [INFERRED] [semantically similar]
  icon-sm.png → SwiftBruja.jpg
- `Release Binary Workflow` --conceptually_related_to--> `SwiftBruja AGENTS.md`  [INFERRED]
  .github/workflows/release.yml → AGENTS.md
- `Tests Workflow` --conceptually_related_to--> `SwiftBruja AGENTS.md`  [INFERRED]
  .github/workflows/tests.yml → AGENTS.md
- `RecordingOutputWriter` --inherits--> `OutputWriter`  [EXTRACTED]
  Tests/ProgressRendererTests/IOCoordinatorTests.swift → Sources/BrujaHelpers/IOCoordinator.swift

## Import Cycles
- None detected.

## Communities (46 total, 9 thin omitted)

### Community 0 - "Agent Backend Selection"
Cohesion: 0.05
Nodes (38): AsyncParsableCommand, BrujaCLI, ChatCommand, DownloadCommand, InfoCommand, ListCommand, QueryCommand, CLIError (+30 more)

### Community 1 - "Agent Command & Loop"
Cohesion: 0.06
Nodes (51): AgentBackendSelector, bruja agent command, swift-argument-parser, Bruja Static API, Bruja Static API, bruja CLI, BrujaCLI, BrujaError (+43 more)

### Community 2 - "Tokenizer Bridge"
Cohesion: 0.05
Nodes (26): AgentAllowlist, AgentBackend, foundation, mlx, AgentBackendSelector, BrujaError, FoundationModelsAvailabilityProvider, FoundationModelsUnavailableError (+18 more)

### Community 3 - "IO Coordinator"
Cohesion: 0.06
Nodes (33): Configuration, MLXAgentLoop, BrujaGenerationEvent, info, text, toolCall, ChatInputBox, ContainerGenerationSource (+25 more)

### Community 4 - "Bruja CLI Commands"
Cohesion: 0.09
Nodes (28): AgentBackend, AgentToolHandling, Arguments, AgentCommand, AgentLoop, AnswerAccumulator, ConsentToolDispatcher, ConsentToolObserver (+20 more)

### Community 5 - "Mock Backend Dispatch Tests"
Cohesion: 0.08
Nodes (14): MockBackendDispatchTests, ToolCallFlag, ToolDispatchHarness, ReadFileToolTests, String, Bool, String, T (+6 more)

### Community 6 - "MLX Agent Loop & Generation"
Cohesion: 0.08
Nodes (19): MLXAgentLoopTranscriptTests, BrujaGenerationEvent, BrujaModelManager, GenerationSource, MLXAgentLoop, MLXLMCommon, SharedMockGenerationSource, Bool (+11 more)

### Community 7 - "Bruja Core Types"
Cohesion: 0.09
Nodes (21): BrujaIntegrationTests, IntegrationTestError, binaryNotFound, processFailure, timeout, BrujaError, agentStepLimitExceeded, contextWindowExceeded (+13 more)

### Community 8 - "Bruja Static API Overview"
Cohesion: 0.14
Nodes (17): AgentToolHandling, AgentTurnEvent, assistantText, toolCallStarted, toolFinished, dispatchStringTool(), dispatchTool(), MLXToolEncoding (+9 more)

### Community 9 - "Progress Renderer"
Cohesion: 0.20
Nodes (6): IOCoordinatorTests, RecordingOutputWriter, ScriptedLineReader, Sendable, Int, String

### Community 10 - "Bruja Integration Tests"
Cohesion: 0.15
Nodes (11): AcervoModel, BrujaModelInfo, Codable, BrujaQueryResult, Date, Double, Double, Int (+3 more)

### Community 11 - "Tool Dispatch"
Cohesion: 0.14
Nodes (6): ToolSuiteTests, String, String, URL, Arguments, GlobTool

### Community 12 - "Tool Suite Tests"
Cohesion: 0.23
Nodes (7): IOCoordinator, LineReader, OutputWriter, StandardLineReader, StandardOutputWriter, Bool, String

### Community 13 - "MLX Agent Loop Transcript Tests"
Cohesion: 0.16
Nodes (14): BrujaQueryResult, ModelContainer, Bool, BrujaQueryResult, Float, Int, Int64, ModelContainer (+6 more)

### Community 14 - "Path Guard Tests"
Cohesion: 0.21
Nodes (3): PathGuardTests, String, URL

### Community 15 - "Path Guard"
Cohesion: 0.25
Nodes (8): Decision, allowed, denied, escapeRequested, PathGuard, Equatable, Bool, String

### Community 16 - "Edit File Tool & Registry"
Cohesion: 0.18
Nodes (5): String, Tool, Arguments, EditFileTool, ToolRegistry

### Community 17 - "Grep Tool"
Cohesion: 0.23
Nodes (5): Bool, String, URL, Arguments, GrepTool

### Community 18 - "Preflight Manifest Test"
Cohesion: 0.26
Nodes (7): PreflightManifestTest, ProcessResult, Int32, Set, String, TimeInterval, URL

### Community 19 - "Run Shell Tool"
Cohesion: 0.22
Nodes (3): String, Arguments, RunShellTool

### Community 20 - "Shared Models Logging Test"
Cohesion: 0.29
Nodes (5): ProcessResult, SharedModelsLoggingTest, Int32, String, TimeInterval

### Community 21 - "List Directory Tool"
Cohesion: 0.24
Nodes (3): String, Arguments, ListDirTool

### Community 22 - "Inference Integration Test"
Cohesion: 0.22
Nodes (3): InferenceIntegrationTest, String, TimeInterval

### Community 24 - "Write File Tool"
Cohesion: 0.22
Nodes (6): FoundationModelBackend, LanguageModelSession, BrujaError, Error, String, Tool

### Community 25 - "Agent Seam Spike Test"
Cohesion: 0.28
Nodes (4): String, Tool, Arguments, WriteFileTool

### Community 26 - "Error Reporting Smoke Test"
Cohesion: 0.33
Nodes (5): ErrorReportingSmokeTest, ProcessResult, Int32, String, TimeInterval

### Community 27 - "Project Execution Plans"
Cohesion: 0.39
Nodes (9): BrujaDownloadManager, SwiftAcervo / Acervo Storage API, Operation Cauldron Whisper — Execution Plan, Operation Manifest Airdrop — Execution Plan, Operation Cauldron Whisper — Iteration 01 Brief, Archived Documentation: Incomplete Tasks (README), CDN Model Distribution for SwiftBruja (Requirements), Snakeskin Molt 01 — Shed the Download Manager Wrapper (Requirements) (+1 more)

### Community 28 - "Bruja Memory Management"
Cohesion: 0.44
Nodes (4): BrujaMemory, Int, Int64, UInt64

### Community 29 - "Tool Result Type"
Cohesion: 0.42
Nodes (3): Int, String, ToolResult

### Community 30 - "Foundation Backend Integration Test"
Cohesion: 0.25
Nodes (3): AcervoComponentReadyTests, BrujaConcurrencyTests, XCTestCase

### Community 31 - "Acervo Component Readiness Tests"
Cohesion: 0.32
Nodes (4): AgentTurnEvent, AgentSeamSpikeTest, EventLog, String

### Community 32 - "Bruja Error Tests"
Cohesion: 0.32
Nodes (3): FoundationBackendIntegrationTest, Bool, URL

### Community 35 - "Model Path & Listing Tests"
Cohesion: 0.38
Nodes (4): AcervoManifestFetchTests, Set, String, URL

### Community 37 - "Bruja Model Manager Tests"
Cohesion: 0.47
Nodes (3): ReasoningTrace, Bool, String

### Community 42 - "Bruja Error"
Cohesion: 0.50
Nodes (4): Manifest Airdrop Brief, Manifest Airdrop Completion Log, Manifest Airdrop Execution Plan, Manifest Airdrop Supervisor State

### Community 43 - "Package Manifest"
Cohesion: 0.67
Nodes (4): Lighthouse Plumbing Execution Plan, Lighthouse Plumbing Requirements, Snakeskin Molt Brief, Snakeskin Molt Execution Plan

## Ambiguous Edges - Review These
- `Snakeskin Molt 01 — Shed the Download Manager Wrapper (Requirements)` → `CDN Model Distribution for SwiftBruja (Requirements)`  [AMBIGUOUS]
  docs/complete/snakeskin-molt-01-requirements.md · relation: conceptually_related_to

## Knowledge Gaps
- **131 isolated node(s):** `Double`, `Sendable`, `mlx`, `foundation`, `Set` (+126 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **9 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What is the exact relationship between `Snakeskin Molt 01 — Shed the Download Manager Wrapper (Requirements)` and `CDN Model Distribution for SwiftBruja (Requirements)`?**
  _Edge tagged AMBIGUOUS (relation: conceptually_related_to) - confidence is low._
- **Why does `ToolSuiteTests` connect `Tool Dispatch` to `Edit File Tool & Registry`, `Grep Tool`, `Run Shell Tool`, `List Directory Tool`, `Agent Seam Spike Test`, `Foundation Backend Integration Test`?**
  _High betweenness centrality (0.085) - this node is a cross-community bridge._
- **Why does `ProgressRenderer` connect `Agent Backend Selection` to `Bruja CLI Commands`?**
  _High betweenness centrality (0.081) - this node is a cross-community bridge._
- **Why does `ProgressRendererNonTTYTests` connect `Agent Backend Selection` to `Foundation Backend Integration Test`?**
  _High betweenness centrality (0.079) - this node is a cross-community bridge._
- **Are the 13 inferred relationships involving `ProgressRenderer` (e.g. with `.run()` and `.testLogStartup_WritesToStderr()`) actually correct?**
  _`ProgressRenderer` has 13 INFERRED edges - model-reasoned connections that need verification._
- **What connects `Double`, `Sendable`, `mlx` to the rest of the system?**
  _131 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Agent Backend Selection` be split into smaller, more focused modules?**
  _Cohesion score 0.05257312106627175 - nodes in this community are weakly interconnected._