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
    .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMajor(from: "0.33.0")),
    .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.33.0")),

    // Model download / cache / discovery (R3.2, G1/G2).
    .package(
      url: "https://github.com/intrusive-memory/SwiftAcervo.git", .upToNextMajor(from: "0.25.0")),

    // CLI argument parsing (R5). Not named in REQUIREMENTS, but the agent CLI requires it.
    .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "1.7.1")),

    // Tokenizer. mlx-swift-lm 3.x ships only the `MLXLMCommon.Tokenizer`/`TokenizerLoader`
    // protocols; `SwiftTokenizersLoader` adapts DePasqualeOrg/swift-tokenizers (the Rust
    // `tokenizers` crate, with Jinja chat templates) to them. swift-tokenizers is the
    // tokenizer the image stack uses (SwiftTuberia, flux-2-swift-mlx, SwiftVinetas,
    // mlx-audio-swift); swift-transformers, used before 1.13.0, defines a module of the same
    // name (`Tokenizers`), so an app could not link SwiftBruja beside them.
    // upToNextMinor: swift-tokenizers is 0.x and changed API between minors.
    .package(
      url: "https://github.com/DePasqualeOrg/swift-tokenizers.git", .upToNextMinor(from: "0.7.5")),

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
        .product(name: "Tokenizers", package: "swift-tokenizers"),
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
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
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
