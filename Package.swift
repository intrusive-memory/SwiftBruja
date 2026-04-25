// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "SwiftBruja",
  platforms: [
    .macOS(.v26),
    .iOS(.v26),
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
  dependencies: [
    // MLX ecosystem for on-device inference
    .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMajor(from: "0.31.3")),
    .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.3")),

    // Tokenizer adapter for mlx-swift-lm 3.x (replaces bundled swift-transformers dep).
    // Explicit Swift trait avoids pulling the Rust backend (binary xcframework).
    .package(
      url: "https://github.com/DePasqualeOrg/swift-tokenizers-mlx",
      .upToNextMajor(from: "0.2.0"),
      traits: ["Swift"]),

    // Shared model management (download, cache, discovery).
    // Floor pinned at 0.8.1 — that release ships the ACERVO_OFFLINE env-var
    // gate required by `make reference-check`'s offline-load test
    // (REQUIREMENTS.md §"Offline-Mode Contract").
    .package(
      url: "https://github.com/intrusive-memory/SwiftAcervo.git", .upToNextMajor(from: "0.8.1")),

    // CLI argument parsing
    .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMajor(from: "1.7.1")),
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
        .product(name: "MLXLMTokenizers", package: "swift-tokenizers-mlx"),
        .product(name: "SwiftAcervo", package: "SwiftAcervo"),
      ]
    ),

    // CLI helper utilities (ProgressRenderer, etc.)
    .target(
      name: "BrujaHelpers",
      dependencies: []
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
      ]
    ),

    // Unit Tests
    .testTarget(
      name: "SwiftBrujaTests",
      dependencies: [
        "SwiftBruja",
        .product(name: "SwiftAcervo", package: "SwiftAcervo"),
      ]
    ),

    // Integration Tests (requires built binary and LLM model)
    .testTarget(
      name: "BrujaIntegrationTests",
      dependencies: [
        "SwiftBruja",
        .product(name: "SwiftAcervo", package: "SwiftAcervo"),
      ]
    ),

    // Unit tests for ProgressRenderer (no binary or model required)
    .testTarget(
      name: "ProgressRendererTests",
      dependencies: ["BrujaHelpers"]
    ),
  ]
)
