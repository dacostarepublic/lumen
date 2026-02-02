// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "lumen",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "lumen", targets: ["lumen"]),
        .library(name: "LumenCore", targets: ["LumenCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "LumenCore",
            dependencies: [],
            path: "Sources/LumenCore"
        ),
        .executableTarget(
            name: "lumen",
            dependencies: [
                "LumenCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/lumen"
        ),
        .testTarget(
            name: "LumenTests",
            dependencies: ["LumenCore"],
            path: "Tests/LumenTests"
        )
    ]
)

