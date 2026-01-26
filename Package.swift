// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftBruja",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "SwiftBruja",
            targets: ["SwiftBruja"]
        )
    ],
    dependencies: [
        // MLX ecosystem for on-device inference
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.21.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),

        // PROJECT.md types and parsing
        .package(url: "https://github.com/intrusive-memory/SwiftProyecto", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "SwiftBruja",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Hub", package: "mlx-swift-lm"),
                .product(name: "SwiftProyecto", package: "SwiftProyecto"),
            ]
        ),
        .testTarget(
            name: "SwiftBrujaTests",
            dependencies: ["SwiftBruja"]
        )
    ]
)
