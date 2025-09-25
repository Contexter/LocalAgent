// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AgentService",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AgentService", targets: ["AgentService"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.59.0")
    ],
    targets: [
        .executableTarget(
            name: "AgentService",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio")
            ],
            path: "Sources"
        )
    ]
)
