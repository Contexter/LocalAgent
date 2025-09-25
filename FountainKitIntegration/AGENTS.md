# FountainKit Integration Agent

This document instructs an agent (and humans) how to integrate the LocalAgent runtime with the FountainKit gateway, planner and function‑caller services. Follow these steps when preparing a PR into FountainKit, or when running a local end‑to‑end test.

## Goals

- Register a persona that forwards chat+functions to the LocalAgent `/chat` API (and optional `/chat/stream`).
- Make the planner aware that function‑calling is supported by this persona.
- Validate end‑to‑end calls: planner → LocalAgent → function‑caller → gateway response.

## Prerequisites

- LocalAgent repository checked out and buildable.
- macOS arm64 (Apple Silicon) with Xcode / Swift toolchain.
- Choose a backend for LocalAgent:
  - mock (fastest to verify wiring)
  - llama (llama.cpp) – either static‑linked binary, Homebrew, or prebuilt xcframework
  - coreml – scaffold in place

## Start LocalAgent

- Copy config and run:
  - `cp AgentService/agent-config.json.example AgentService/agent-config.json`
  - Set one of: `mock`, `llama`, or `coreml` in `backend`.
  - Start server: `swift run --package-path AgentService AgentService`
  - Health check: `curl http://127.0.0.1:8080/health`

- Alternative (no Homebrew):
  - Static binary: `LLAMA_CPP_REF=b6550 ./scripts/build-llama-static.sh` (binary in SwiftPM release bin path)
  - Prebuilt xcframework: `LLAMA_CPP_REF=b6550 ./scripts/build-prebuilt-xcframework.sh` then wire `LlamaCppCBinary` per `AgentService/Docs/PrebuiltIntegration.md`.

## Register Persona in FountainKit

1) Copy persona file:
- From this repo: `FountainKitIntegration/LocalAgentPersona.md`
- Into FountainKit personas directory (usually `<FK root>/personas/`).

2) Gateway/planner config:
- Add `LocalAgentPersona` to the gateway persona chain so the planner can route requests. Example (pseudocode):

```
personas:
  - name: LocalAgentPersona
    file: personas/LocalAgentPersona.md
chain:
  - LocalAgentPersona
  - … other personas …
```

3) Ensure the persona’s agent definition points to your LocalAgent:
- base URL: `http://127.0.0.1:8080`
- endpoint: `/chat` (and optionally `/chat/stream` for SSE)
- protocol: `openai-chat`
- supports: `function_calling`, `text_completion`

4) Function registration:
- Use FountainKit’s function‑caller service to register functions (OpenAI‑style schema). Example minimal function object:

```
{
  "name": "schedule_meeting",
  "description": "Schedule a meeting",
  "parameters": {"type":"object","properties":{"title":{"type":"string"},"time":{"type":"string"}},"required":["title","time"]}
}
```

## Optional: Streaming

- For token‑like streaming responses, call `/chat/stream`.
- The server uses Server‑Sent Events (SSE) with headers:
  - `Content-Type: text/event-stream; charset=utf-8`
  - `X-Chunked-SSE: 1`
- The gateway can route streaming requests to this endpoint or pass a flag the persona interprets.

## Test End‑to‑End

- Direct API test:

```
curl -s http://127.0.0.1:8080/chat \
  -H 'content-type: application/json' \
  -d '{
        "model":"local-mock-1",
        "messages":[{"role":"user","content":"call schedule_meeting with {\"title\":\"Team sync\",\"time\":\"2025-01-01 10:00\"}"}],
        "functions":[{"name":"schedule_meeting","description":"Schedule a meeting","parameters":{"type":"object"}}]
      }'
```

- Through FountainKit gateway: send a normal user objective (e.g. “Schedule a meeting…”) and verify:
  - Planner forwards to LocalAgent persona
  - Persona returns a function_call
  - Function‑caller executes and gateway returns the result

## Deployment Notes

- Homebrew optional: Runtime can be static‑linked or use a prebuilt xcframework.
- Binaries: Tagged releases publish `AgentService-macos-arm64-plain.tar.gz` and `AgentService-macos-arm64-static.tar.gz`.
- Legal: Code is MIT; llama.cpp is MIT. Model weights are separately licensed.

## Troubleshooting

- 404 Not Found:
  - Ensure LocalAgent is running and endpoint paths are correct (/chat, /chat/stream)
- Connection refused:
  - Check host/port in `agent-config.json` matches persona base_url
- No function_call produced:
  - Verify `functions` and `function_call` fields are passed; mock backend heuristics require either explicit JSON in user text or auto mode
- Llama backend fails to load:
  - If using Homebrew, verify `brew install llama.cpp`
  - For static or xcframework builds, rebuild with the provided scripts and ensure the backend is set to `llama`

## Next Steps (for the integration agent)

- Open a PR in FountainKit that:
  - Adds `LocalAgentPersona.md` to `personas/`
  - Wires the persona into the gateway chain
  - Adds an example tool registration for testing (e.g. schedule_meeting)
- Optionally add a planner flag to select `/chat/stream` for streaming responses.
- Add an integration test that sends a function‑calling prompt through the gateway and asserts a `function_call` response.

