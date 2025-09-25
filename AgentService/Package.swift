// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AgentService",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "AgentCore", targets: ["AgentCore"]),
        .executable(name: "AgentService", targets: ["AgentService"]),
        // Optional system library to expose llama.cpp C API as `LlamaCppC`.
        .library(name: "LlamaCppC", targets: ["LlamaCppC"]) // consumers opt-in
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.59.0")
    ],
    targets: [
        // System library target for llama.cpp C API (opt-in, not a default dep).
        .systemLibrary(
            name: "LlamaCppC",
            path: "Sources/LlamaCppC",
            pkgConfig: "llama",
            providers: [
                .brew(["llama.cpp"]),
                .apt(["llama"])
            ]
        ),
        .target(
            name: "AgentCore",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio")
            ],
            path: "Sources/AgentCore"
        ),
        .executableTarget(
            name: "AgentService",
            dependencies: [
                "AgentCore"
            ],
            path: "Sources/AgentService"
        ),
        .testTarget(
            name: "AgentCoreTests",
            dependencies: ["AgentCore"],
            path: "Tests/AgentCoreTests"
        )
    ]
)
