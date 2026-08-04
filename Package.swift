// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Kokosuki",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", exact: "2.29.1")
    ],
    targets: [
        .executableTarget(
            name: "Kokosuki",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
            ],
            path: "Sources/Kokosuki"
        ),
        .executableTarget(
            name: "kokosuki-cli",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
            ],
            path: "Sources/KokosukiCLI"
        ),
    ]
)
