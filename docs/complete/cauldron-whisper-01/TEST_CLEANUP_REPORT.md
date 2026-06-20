---
state: completed
mission: cauldron-whisper-01
branch: mission/cauldron-whisper/01
date: 2026-06-20
---

# Test Cleanup Report — OPERATION CAULDRON WHISPER

## Summary

**Removed:** 0 tests  
**Flagged for review:** 4 items (3 integration tests + 1 borderline note)  
**Build verification:** skipped — relied on supervisor verification (integration tests require
unsandboxed host + locally cached fixture model; unit suite has not been modified)

---

## Removed

| File : Test | Reason | Confidence |
|-------------|--------|------------|
| *(none)* | All in-scope tests are either hermetic/mock-based unit tests (CI-safe) or intentionally-documented integration tests with proper `XCTSkip` guards | — |

No deletions were made. The conservative bias directed here is satisfied: every test either:
- Is fully hermetic (mock/injected dependencies, isolated temp directories, no network, no model), or
- Already has explicit `XCTSkip` guards with clear diagnostics for missing environmental prerequisites.

---

## Flagged for Review

| File : Test | Concern | Recommended Action |
|-------------|---------|-------------------|
| `Tests/BrujaIntegrationTests/AgentReplTest.swift` : `testAgentVerbRoundTripsReadFileAgainstFixtureModel` | Requires unsandboxed xctest host + locally cached `mlx-community/Qwen2.5-0.5B-Instruct-4bit` model in App Group container + signed `./bin/bruja` binary. Cannot run under sandboxed `xcodebuild test`. Has `XCTSkip` guards for both missing binary and missing model. Documented as intentional in AGENTS.md OQ-4 / CI-gating section; runs via `make test-agent-repl`. | **KEEP** — load-bearing integration proof (Sortie 7 exit criterion). Must not run in standard CI; run only from dedicated `make test-agent-repl` target on unsandboxed developer host. Ensure CI workflow does not include `BrujaIntegrationTests` target in standard `make test` invocation. |
| `Tests/BrujaIntegrationTests/AgentSeamSpikeTest.swift` : `testReadFileToolRoundTripsThroughMLXSession` | Requires unsandboxed xctest host + locally cached `mlx-community/Qwen2.5-0.5B-Instruct-4bit` model in App Group container. Has `XCTSkip` guard for missing model. Documented as intentional in AGENTS.md; runs via `make test-agent-seam`. | **KEEP** — load-bearing integration proof (Sortie 2 seam exit criterion). Must not run in standard CI; run only from dedicated `make test-agent-seam` target on unsandboxed developer host. |
| `Tests/BrujaIntegrationTests/FoundationBackendIntegrationTest.swift` : `testFoundationBackendRoundTripsOrFailsLoudly` | Requires unsandboxed xctest host + signed `./bin/bruja` binary. Has `XCTSkip` guard for missing binary. Correctly branches on FM availability (FM-available vs FM-unavailable host assertions). Documented as intentional; runs via `make test-agent-fm`. | **KEEP** — load-bearing integration proof (Sortie 9 exit criterion). Must not run in standard CI; run only from dedicated `make test-agent-fm` target on unsandboxed developer host. |
| `Tests/ProgressRendererTests/IOCoordinatorTests.swift` : `testPromptDuringStream_NoInterleaving`, `testMultipleTokensBufferedAndDrainedInOrder` | Both tests use `Task.sleep(nanoseconds: 5_000_000)` (5 ms) to give the prompt task a scheduling window to acquire the Swift actor before a concurrent `streamToken` call. This is a standard actor-scheduling idiom, not a wall-clock timing assertion. On a heavily loaded CI runner the 5 ms sleep might occasionally be insufficient to guarantee ordering, making the test transiently flaky. All other IOCoordinatorTests are fully hermetic with injected doubles. | **KEEP with monitoring** — the sleep is not an assertion on duration and the tests are otherwise fully hermetic. If flakiness appears in CI, the sleep can be replaced with a `withCheckedContinuation` handshake or the assertion can be softened to allow the prompt to land before or after token_C. Do not delete now. |

---

## CI-Safe Assessment of Remaining Files (No Action Needed)

| File | Assessment |
|------|-----------|
| `Tests/SwiftBrujaTests/Agent/BackendSelectionTests.swift` | Fully mock-based. No model, no network. CI-safe. |
| `Tests/SwiftBrujaTests/Agent/ExecutorTranscriptTests.swift` | Uses inline `MockGenerationSource`. No model, no network. CI-safe. |
| `Tests/SwiftBrujaTests/Agent/FoundationBackendTests.swift` | Error-mapping tests use no inference. `testFMPathConsumesTheSameToolRegistryArrayAsMLXPath` constructs a `LanguageModelSession` without running inference — session construction is expected to succeed regardless of Apple Intelligence availability on macOS 26+. CI-safe. |
| `Tests/SwiftBrujaTests/Agent/MockBackendDispatchTests.swift` | Uses injected temp directories + `SharedMockGenerationSource`. No model, no network. CI-safe. |
| `Tests/SwiftBrujaTests/Agent/Mocks/MockGenerationSource.swift` | Shared test infrastructure, not a test. Left untouched per instructions. |
| `Tests/SwiftBrujaTests/Agent/PathGuardTests.swift` | Uses isolated temp directories with proper setup/teardown. No model, no network. CI-safe. |
| `Tests/SwiftBrujaTests/Agent/ReadFileToolTests.swift` | Uses isolated temp directories. No model, no network. CI-safe. |
| `Tests/SwiftBrujaTests/Agent/ToolSuiteTests.swift` | Uses isolated temp directories. Shell commands (`echo`, `pwd`, `python3`) are standard CI toolchain. No model, no network. CI-safe. |

---

## Build Verification

Skipped — no test files were modified or deleted. Relied on supervisor's prior verification that
the unit suite compiled and passed, and that the integration tests have been verified to skip
cleanly under sandboxed `xcodebuild test` due to their `XCTSkip` guards.

The 3 integration tests (BrujaIntegrationTests target) require an unsandboxed xctest host and are
not run under standard `make test`. Standard CI must not include the `BrujaIntegrationTests` test
plan target in its `xcodebuild test` invocation.
