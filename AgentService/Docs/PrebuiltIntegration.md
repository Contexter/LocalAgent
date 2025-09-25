# Using the Prebuilt LlamaCppC Binary Target

You can avoid Homebrew and still build the llama.cpp backend by using a locally
prebuilt `.xcframework` as a SwiftPM binary target.

## Build the xcframework

```bash
# Optionally pin to a llama.cpp tag/commit (default: b6550)
LLAMA_CPP_REF=b6550 ./scripts/build-prebuilt-xcframework.sh
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

## Static-linked binary build

To build a self-contained AgentService with a statically linked llama library:

```bash
# Optionally pin to a llama.cpp tag/commit (default: b6550)
LLAMA_CPP_REF=b6550 ./scripts/build-llama-static.sh
```

The resulting binary is placed in the SwiftPM release bin path; use `swift build -c release --package-path AgentService --show-bin-path` to locate it.
