// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "V2Dex",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "V2Dex", targets: ["V2DexApp"]),
        .executable(name: "v2dex-cli", targets: ["V2DexCLI"])
    ],
    dependencies: [
        .package(path: "native/V2DexCore")
    ],
    targets: [
        .executableTarget(
            name: "V2DexApp",
            dependencies: [
                .product(name: "V2DexCore", package: "V2DexCore")
            ],
            path: "Sources/V2DexApp"
        ),
        .executableTarget(
            name: "V2DexCLI",
            dependencies: [
                .product(name: "V2DexCore", package: "V2DexCore")
            ],
            path: "Sources/V2DexCLI"
        )
    ]
)
