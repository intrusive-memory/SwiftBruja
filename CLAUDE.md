# SwiftBruja - AI Assistant Instructions

## Project Overview

**SwiftBruja** ("Swift Witch") is a Swift package providing simple access to on-device LLM capabilities on Apple Silicon. It wraps MLX libraries for:

- **Model Management** - Download/cache models from HuggingFace
- **Structured Output** - Query models, get typed Swift results
- **Use-Case Modules** - Pre-built solutions (PROJECT.md generation, etc.)

**Platforms**: macOS 26.0+, iOS 26.0+ (Apple Silicon only)

## Key Design Principles

1. **Single Import** - `import SwiftBruja` gives access to everything
2. **Structured by Default** - Prefer typed results over raw strings
3. **Lazy Loading** - Models downloaded on-demand, not bundled
4. **Actor Isolation** - Thread-safe by design

## Architecture

```
SwiftBruja/
├── Sources/SwiftBruja/
│   ├── Bruja.swift                 # Main entry point
│   ├── Core/
│   │   ├── BrujaModelManager.swift # Model download/cache
│   │   ├── BrujaQuery.swift        # Structured queries
│   │   └── BrujaChatSession.swift  # Multi-turn chat
│   ├── StructuredOutput/
│   │   ├── JSONSchemaBuilder.swift # Build schema from Codable
│   │   └── ResponseParser.swift    # Parse LLM JSON responses
│   └── UseCases/
│       └── ProjectMdGenerator.swift # PROJECT.md generation
```

## Dependencies

- `mlx-swift` - Core MLX framework
- `mlx-swift-lm` - LLM inference (MLXLLM, MLXLMCommon, Hub)
- `SwiftProyecto` - PROJECT.md types (ProjectFrontMatter)

## Default Model

`mlx-community/Phi-3-mini-4k-instruct-4bit` (~2.15 GB)

Storage: `~/Library/Application Support/SwiftBruja/Models/`

## Code Patterns

### Structured Query
```swift
struct Result: Codable { let answer: String }
let result: Result = try await Bruja.query("...", as: Result.self)
```

### Model Management
```swift
if !await Bruja.isModelReady() {
    try await Bruja.downloadDefaultModel { print($0) }
}
```

### PROJECT.md Generation
```swift
let result = try await Bruja.generateProjectMd(for: folderURL)
try result.write(to: projectMdURL)
```

## Platform Version Enforcement

**iOS 26.0+ and macOS 26.0+ ONLY. Never add @available checks for older versions.**

## Development Workflow

See `.claude/WORKFLOW.md` for branch strategy (development → PR → main).

## Related Projects

- **Produciesta** - macOS/iOS app (has working MLX implementation to extract)
- **SwiftProyecto** - Project metadata management
- **SwiftCompartido** - Screenplay models and parsing
