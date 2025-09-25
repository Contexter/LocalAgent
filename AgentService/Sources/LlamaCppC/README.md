# LlamaCppC System Library Target

This SwiftPM system library target exposes the `llama.cpp` C API (`llama.h`) to
Swift under the module name `LlamaCppC`. It lets `AgentCore` conditionally
compile a llama.cpp backend without forcing all users to install llama.cpp.

Two ways to provide headers and libs:

1) Homebrew (recommended on macOS)

- Install llama.cpp:
  - `brew install llama.cpp`
- Verify pkg-config is available and configured:
  - `pkg-config --cflags --libs llama`
    - Example output: `-I/opt/homebrew/include -L/opt/homebrew/lib -llama`
- Build the package; `canImport(LlamaCppC)` will be true and the llama.cpp
  backend will be enabled when `backend` is set to `llama`.

2) Build from source (custom install)

- Clone and build llama.cpp:
  - `git clone https://github.com/ggerganov/llama.cpp`
  - `cd llama.cpp`
  - For Apple Silicon with Metal: `LLAMA_METAL=1 make -j` (or use CMake)
    - CMake example:
      - `cmake -B build -DGGML_METAL=ON -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF`
      - `cmake --build build -j`
- Install headers and library to a known prefix (or point pkg-config to them):
  - Headers: `llama.h` (and related) under `<prefix>/include`
  - Library: `libllama.a` or `libllama.dylib` under `<prefix>/lib`
- Provide a `llama.pc` file for pkg-config or set SwiftPM flags:
  - pkg-config file (llama.pc) example:
    ```
    prefix=/usr/local
    exec_prefix=${prefix}
    libdir=${exec_prefix}/lib
    includedir=${prefix}/include
    Name: llama
    Description: llama.cpp C API
    Version: 1.0
    Libs: -L${libdir} -llama
    Cflags: -I${includedir}
    ```
  - Export `PKG_CONFIG_PATH` so SwiftPM can find it:
    - `export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH`
  - Or build with explicit flags (not needed if pkg-config is set):
    - `swift build -Xcc -I/usr/local/include -Xlinker -L/usr/local/lib -Xlinker -llama`

How it works

- `module.modulemap` declares a system module `LlamaCppC` with `shim.h` that includes `<llama.h>` and links `llama`.
- Package.swift declares a systemLibrary target with `pkgConfig: "llama"` and platform providers (Homebrew/Apt).
- Code in `AgentCore` uses `#if canImport(LlamaCppC)` to only build the llama.cpp backend when the module is present.

Prebuilt option (no Homebrew)

- Use the provided script to create a local prebuilt `.xcframework` that bundles
  the C shim with a static `libllama.a`:

  ```bash
  ./scripts/build-prebuilt-xcframework.sh
  ```

- This produces `Vendor/LlamaCppCBinary.xcframework`. The package already declares
  a `.binaryTarget(name: "LlamaCppCBinary", path: "Vendor/LlamaCppCBinary.xcframework")`.

- To enable it for build, add `LlamaCppCBinary` to the AgentCore target dependencies
  in `AgentService/Package.swift`. The backend contains `#elseif canImport(LlamaCppCBinary)`
  so it will compile against the prebuilt module without requiring Homebrew.

Static-linking the AgentService binary

- Build a release binary with a statically linked llama library (no runtime dylib):

  ```bash
  ./scripts/build-llama-static.sh
  ```

- The script clones/updates llama.cpp, builds `libllama.a`, builds the shim wrapper,
  and links `AgentService` against it. The resulting binary lives under the SwiftPM
  release bin path.

Troubleshooting

- "No such module 'LlamaCppC'": ensure pkg-config can find `llama` or headers/libs are on default paths.
- Undefined symbols for `llama_*`: ensure the correct library is linked (static vs dynamic) and architectures match (arm64 for Apple Silicon).
- API mismatch: llama.cpp C API evolves. Compare your installed `llama.h` with the backend stub and update calls accordingly.
