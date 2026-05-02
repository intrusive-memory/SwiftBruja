// swift-tools-version: 6.2

import Foundation
import PackageDescription

// In CI we always pin to released remotes. Locally, prefer a sibling checkout
// at ../<name> if present so in-flight changes can be exercised end-to-end
// without publishing a release. Falls back to the remote pin if the sibling
// directory is missing, so fresh clones still build.
let useLocalSiblings = ProcessInfo.processInfo.environment["CI"] != "true"

func sibling(_ name: String, remote: String, from version: Version) -> Package.Dependency {
  let localPath = "../\(name)"
  if useLocalSiblings && FileManager.default.fileExists(atPath: localPath) {
    return .package(path: localPath)
  }
  return .package(url: remote, .upToNextMajor(from: version))
}

/// Branch-pinned sibling: prefer the local sibling checkout when present;
/// otherwise pin to a specific remote branch instead of a version range. Use
/// for in-flight upstream changes that have not yet shipped a tagged release.
func siblingBranch(_ name: String, remote: String, branch: String) -> Package.Dependency {
  let localPath = "../\(name)"
  if useLocalSiblings && FileManager.default.fileExists(atPath: localPath) {
    return .package(path: localPath)
  }
  return .package(url: remote, branch: branch)
}

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
    //
    // Temporarily pinned to branch `fix/app-group-env-resolution` (SwiftAcervo
    // PR #34) which removes `Acervo.customBaseDirectory` and exposes the new
    // `Acervo.appGroupEnvironmentVariable` constant. SwiftBruja's tests
    // migrated to the new env-var pattern in this same PR, so a version pin
    // would break compile until #34 ships. A follow-up will switch back to
    // `from: "0.8.5"` (or the actual released version) once #34 is tagged.
    siblingBranch(
      "SwiftAcervo",
      remote: "https://github.com/intrusive-memory/SwiftAcervo.git",
      branch: "fix/app-group-env-resolution"),

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
