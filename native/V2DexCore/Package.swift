// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "V2DexCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "V2DexCore",
            targets: ["V2DexCore"]
        )
    ],
    targets: [
        .target(
            name: "V2DexCore",
            path: "Sources"
        ),
        .testTarget(
            name: "V2DexCoreTests",
            dependencies: ["V2DexCore"],
            path: "Tests"
        )
    ]
)
