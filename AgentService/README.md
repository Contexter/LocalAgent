# AgentService

AgentService hosts a local function-calling LLM behind a simple HTTP API
compatible with OpenAI's chat/function-calling schema.

This package currently ships with a `mock` backend for easy end-to-end testing
with FountainKit. Networking is implemented directly with SwiftNIO (no Vapor),
mirroring FountainKit’s lightweight `HTTPKernel` + `NIOHTTPServer` approach.
You can replace the mock with a real backend (e.g. llama.cpp or Core ML) by
implementing the `ModelBackend` protocol.

## Run

1. Copy `agent-config.json.example` to `agent-config.json` and adjust as needed.
2. Build and run:

   - `swift run AgentService` (requires network once to fetch SwiftNIO)

3. Test the API:

   ```bash
   curl -s http://127.0.0.1:8080/chat \
     -H 'content-type: application/json' \
     -d '{
           "model":"local-mock-1",
           "messages":[{"role":"user","content":"call schedule_meeting with {\"title\":\"Team sync\",\"time\":\"2025-01-01 10:00\"}"}],
           "functions":[{"name":"schedule_meeting","description":"Schedule a meeting","parameters":{"type":"object"}}]
         }' | jq
   ```

### Streaming (SSE)

The service supports a simple Server-Sent Events stream for token-like deltas.

```bash
curl -N http://127.0.0.1:8080/chat/stream \
  -H 'content-type: application/json' \
  -d '{
        "messages":[{"role":"user","content":"hello there friend"}]
      }'
```

Headers used for streaming:
- `Content-Type: text/event-stream`
- `X-Chunked-SSE: 1` (the server writes SSE chunks progressively)

You should see a `function_call` response.

## Integrating a real backend

Implement `ModelBackend` and wire it in `main.swift` based on `AgentConfig.backend`.
Follow AGENTS.md for guidance on bridging `llama.cpp` or Core ML to Swift.
Skeletons can be added behind conditional imports:

- Llama.cpp: `#if canImport(LlamaCppC)` provide `LlamaCppBackend`.
- Core ML: `#if canImport(CoreML)` provide `CoreMLBackend`.

### Llama.cpp via SwiftPM system library

This package includes an optional system library target `LlamaCppC` to expose the
llama.cpp C API (`llama.h`) to Swift.

- Target: `Sources/LlamaCppC` with `module.modulemap` + `shim.h` that includes `<llama.h>`
- Package.swift declares `.systemLibrary(name: "LlamaCppC", pkgConfig: "llama", providers: [.brew(["llama.cpp"])])`

Enable it in two ways:

1) Homebrew (recommended)
   - `brew install llama.cpp`
   - Ensure headers and lib are visible (brew usually handles this)
   - Build as usual; `canImport(LlamaCppC)` becomes true and `LlamaCppBackend` will be used when `backend` is set to `llama`.

2) Custom build
   - Build `llama.cpp` as `libllama.a` and install `llama.h`
   - Adjust search paths (e.g. via `PKG_CONFIG_PATH`) or place headers/libs in standard locations

Note: AgentCore does not depend on `LlamaCppC` by default. This avoids link
errors on machines without llama.cpp. The backend compiles conditionally.

### Core ML scaffolding

`CoreMLBackend` accepts a `Tokenizer` and `SamplerOptions` (see `Tokenization.swift`, `Sampling.swift`).
Integrate your tokenizer and use the sampler with model logits. The current
implementation returns a diagnostic until a real model is provided.
