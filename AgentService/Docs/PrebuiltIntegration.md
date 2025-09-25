# Using the Prebuilt LlamaCppC Binary Target

You can avoid Homebrew and still build the llama.cpp backend by using a locally
prebuilt `.xcframework` as a SwiftPM binary target.

## Build the xcframework

```bash
./scripts/build-prebuilt-xcframework.sh
```

This produces `Vendor/LlamaCppCBinary.xcframework` (static archive + headers).

## Wire it into Package.swift

Edit `AgentService/Package.swift` to add the binary target and depend on it from
`AgentCore`:

```swift
// 1) Add the binary target (near other targets)
.binaryTarget(name: "LlamaCppCBinary", path: "Vendor/LlamaCppCBinary.xcframework"),

// 2) Add to AgentCore dependencies
.target(
  name: "AgentCore",
  dependencies: [
    .product(name: "NIO", package: "swift-nio"),
    .product(name: "NIOHTTP1", package: "swift-nio"),
    "LlamaCppCBinary"
  ],
  path: "Sources/AgentCore"
),
```

The backend already includes:

```swift
#if canImport(LlamaCppC)
import LlamaCppC
#elseif canImport(LlamaCppCBinary)
import LlamaCppCBinary
#endif
```

so it will compile against the prebuilt module without requiring Homebrew.

