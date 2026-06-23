// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "SwiftBruja",
  platforms: [
    // macOS 26+ only. This is a macOS-first CLI; iOS is out of scope for now.
    // The agent stack runs entirely on macOS 26 APIs: `FoundationModels.Tool` +
    // `@Generable` + `LanguageModelSession` (system-model backend) and `MLXLMCommon`
    // generation with native tool-call parsing (MLX backend, hand-rolled loop). The
    // macOS-27-only custom-provider seam (`LanguageModel`/`LanguageModelExecutor`) was
    // removed so the project builds and tests on the macOS 26 CI image.
    .macOS(.v26)
  ],
  products: [
    // Library for programmatic access
    .library(
      name: "SwiftBruja",
      targets: ["SwiftBruja"]
    ),
    // CLI helper utilities (ProgressRenderer, etc.) — reusable by tests
    .library(
      name: "BrujaHelpers",
      targets: ["BrujaHelpers"]
    ),
    // CLI executable
    .executable(
      name: "bruja",
      targets: ["bruja"]
    ),
  ],
  // Dependency set pared back to what REQUIREMENTS.md justifies for the agentic-CLI rework.
  // The code is being reworked from scratch; this manifest is the forward-looking dep target,
  // not a guarantee that the current Sources still compile against it.
  dependencies: [
    // MLX backend (R3): on-device inference engine + LLM layer.
    .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMajor(from: "0.31.3")),
    .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.3")),

    // Model download / cache / discovery (R3.2, G1/G2).
    .package(
      url: "https://github.com/intrusive-memory/SwiftAcervo.git", .upToNextMajor(from: "0.20.0")),

    // CLI argument parsing (R5). Not named in REQUIREMENTS, but the agent CLI requires it.
    .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "1.7.1")),

    // Tokenizer (S2 / OQ-2). mlx-swift-lm 3.x ships only the `MLXLMCommon.Tokenizer`/
    // `TokenizerLoader` *protocols* — no concrete tokenizer. swift-transformers provides a
    // local-folder tokenizer loader (and bundles swift-jinja so `applyChatTemplate` works).
    // It is independent of mlx-swift-lm, so it does NOT collide with our ml-explore pin the way
    // the DePasqualeOrg swift-tokenizers-mlx fork would. We bridge it to the MLXLMCommon seam in
    // `Sources/SwiftBruja/Agent/TokenizerBridge.swift`.
    .package(
      url: "https://github.com/huggingface/swift-transformers", .upToNextMajor(from: "1.3.3")),

    // Deliberately removed: swift-tokenizers + swift-tokenizers-mlx. The adapter
    // (swift-tokenizers-mlx 0.3.0) does not compile against swift-tokenizers 0.7.x
    // (encode/decode became typed-throws and the bridge was never updated; no newer
    // adapter release exists). The tokenizer story is deferred to the rework's
    // "different dependency solution".
    //
    // FoundationModels (R2/R8.1) is a system framework — `import FoundationModels`,
    // no SPM dependency entry required.
  ],
  targets: [
    // Main library
    .target(
      name: "SwiftBruja",
      dependencies: [
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "MLXNN", package: "mlx-swift"),
        .product(name: "MLXFast", package: "mlx-swift"),
        .product(name: "MLXLLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        .product(name: "SwiftAcervo", package: "SwiftAcervo"),
        .product(name: "Tokenizers", package: "swift-transformers"),
      ],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),

    // CLI helper utilities (ProgressRenderer, etc.)
    .target(
      name: "BrujaHelpers",
      dependencies: [],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),

    // CLI executable
    .executableTarget(
      name: "bruja",
      dependencies: [
        "SwiftBruja",
        "BrujaHelpers",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        .product(name: "SwiftAcervo", package: "SwiftAcervo"),
      ],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),

    // Unit Tests
    .testTarget(
      name: "SwiftBrujaTests",
      dependencies: [
        "SwiftBruja",
        .product(name: "SwiftAcervo", package: "SwiftAcervo"),
      ],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),

    // Integration Tests (requires built binary and LLM model)
    .testTarget(
      name: "BrujaIntegrationTests",
      dependencies: [
        "SwiftBruja",
        .product(name: "SwiftAcervo", package: "SwiftAcervo"),
      ],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),

    // Unit tests for ProgressRenderer (no binary or model required)
    .testTarget(
      name: "ProgressRendererTests",
      dependencies: ["BrujaHelpers"],
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
  ]
)
