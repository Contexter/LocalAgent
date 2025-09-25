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

You should see a `function_call` response.

## Integrating a real backend

Implement `ModelBackend` and wire it in `main.swift` based on `AgentConfig.backend`.
Follow AGENTS.md for guidance on bridging `llama.cpp` or Core ML to Swift.
Skeletons can be added behind conditional imports:

- Llama.cpp: `#if canImport(LlamaCppC)` provide `LlamaCppBackend`.
- Core ML: `#if canImport(CoreML)` provide `CoreMLBackend`.
