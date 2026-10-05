---
type: test-cleanup-report
state: completed
updated: 2026-10-04
mission: straitjacket-parrot-01
---

## Terminology

A **mission** is the scope of work; a **sortie** is one agent's task within it.

This report covers OPERATION STRAITJACKET PARROT (BR-P1 through BR-P4), which introduced schema-constrained JSON generation, thinking control, model unloading, and peak-memory measurement for the Personaje project. Five test files were added or modified:

- `Tests/BrujaIntegrationTests/PersonajeAcceptanceTests.swift` (protected, model-backed)
- `Tests/BrujaIntegrationTests/PersonajeMemoryTests.swift` (protected, model-backed)
- `Tests/SwiftBrujaTests/BrujaJSONAcceptorTests.swift` (CI-enabled)
- `Tests/SwiftBrujaTests/BrujaJSONLogitProcessorTests.swift` (CI-enabled)
- `Tests/SwiftBrujaTests/BrujaThinkingTests.swift` (CI-enabled)

## Removed

No tests removed.

All tests added during OPERATION STRAITJACKET PARROT pass CI verification without CI-unsafe patterns. The three `Tests/SwiftBrujaTests/*` files contain 45+ unit tests covering:

- JSON schema validation and character-level acceptance (BrujaJSONAcceptorTests)
- Logit processor token masking and bounds enforcement (BrujaJSONLogitProcessorTests)
- BrujaThinking API surface (BrujaThinkingTests)

No individual test method exceeds 200 lines. No hardcoded filesystem paths, network calls, timing assertions under 100ms, or unseeded randomness were found.

The two model-backed integration test classes (PersonajeAcceptanceTests, PersonajeMemoryTests) are protected by design: they are skipped in CI via `make test-ci` (which passes `-skip-testing:BrujaIntegrationTests/Personaje*`), and each test calls `XCTSkipUnless(Acervo.isModelConfigPresent(...))` as a guard.

## Flagged for Review

No tests flagged.

## Build Verification

```
make test-ci
Test session results: ... TEST SUCCEEDED **
```

Exit code: **0**  
Tests executed: 45 tests, 8 skipped, 0 failures

---

**Summary:** 0 tests removed, 0 tests flagged. All CI tests pass.
