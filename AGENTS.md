# Agents

This document describes how to implement and configure **offline, function‑calling agents** that integrate with the [FountainKit](https://github.com/Fountain-Coach/FountainKit) platform.  These agents allow you to run large‑language‑model (LLM) workloads entirely on your macOS device using open‑source models from Hugging Face, while still benefiting from the robust orchestration provided by FountainKit.

## Overview

In FountainKit a *persona* plugs into the gateway and acts as an expert that can evaluate requests and decide whether to allow, deny or augment them.  When you want to build an agent that makes use of an on‑device model—for example, a local function‑calling LLM—you implement a new persona and back it by a local service.  **Owning the runtime infrastructure yourself means that you also own the Swift wrapper around the inference engine.**  Rather than relying on third‑party packages, you compile an inference engine (e.g. `llama.cpp` or a Core ML model), expose its C API to Swift, build your own concurrency‑safe wrapper, and package everything as a Swift module that can be reused across projects.  Your service then hosts the model, exposes a simple HTTP or gRPC API and understands the [OpenAI function‑calling schema](https://platform.openai.com/docs/guides/function-calling).  The persona forwards user instructions to the service and returns the function call or completion back through the normal FountainKit planner and function‑caller pipeline.

Local agents are useful when you:

* Need to run LLMs offline for privacy or cost reasons.
* Want to use open models (e.g. Gorilla OpenFunctions v2, FireFunction v1, Hermes 2 Pro, etc.) without relying on cloud APIs.
* Target Apple hardware; macOS and iOS devices equipped with M‑series chips can run quantized models at reasonable speeds.

This document covers the architecture of such an agent, how to configure it, and how to register it with FountainKit.

## Architecture

An offline agent consists of three main layers:

### 1. Model backend

The model backend is responsible for loading and executing the LLM.  We recommend using quantized GGUF versions of function‑calling models available on Hugging Face (e.g. `gorilla-llm/gorilla-openfunctions-v2-gguf`, `NousResearch/Hermes-2-Pro-Mistral-7B-GGUF`, or `fireworks-ai/firefunction-v1` through Ollama).  These quantized weights are compatible with [`llama.cpp`](https://github.com/ggerganov/llama.cpp), which offers efficient CPU/GPU inference on Apple silicon.

For developers working in Swift there are two main options for the **inference engine**:

* **`llama.cpp` C library with your own Swift wrapper** – Clone the [`llama.cpp`](https://github.com/ggerganov/llama.cpp) repository and compile it as a static library using the Apple toolchain.  Define a `module.modulemap` to expose its C functions (`llama_init_from_file`, `llama_eval`, etc.) to Swift.  Then write a Swift class or actor that wraps these functions, manages model context, performs token sampling and yields tokens asynchronously.  This gives you full ownership of the code and lets you tune performance, caching and memory management.  Existing projects like Kuzco or LocalLLMClient can serve as references, but you are not dependent on them.

* **Core ML** – Apple’s [Core ML Tools](https://github.com/apple/coremltools) can convert transformer models into Core ML format for hardware‑accelerated inference.  Apple’s “On Device Llama 3.1 with Core ML” guide demonstrates how to convert Meta’s Llama 3.1‑8B‑Instruct model, optimize it and run it at ~33 tokens/s on an M1 Max.  The same pipeline applies to other models.  Once converted, you load the `.mlmodel` via `MLModel(contentsOf:)` and write a Swift wrapper that feeds token sequences into the model and extracts logits.

Regardless of the backend, the agent must accept a list of function definitions and a user query, and return either a function call (as JSON) or a normal completion.  Following the OpenAI function‑calling schema ensures compatibility with FountainKit’s function‑caller service.  When building your own wrapper, implement this formatting and parsing logic in Swift so that your API remains consistent with FountainKit’s expectations.

### 2. Bridge layer

The bridge layer connects your Swift model wrapper to the rest of the FountainKit ecosystem.  It should implement a thin HTTP or gRPC server that:

1. Receives POST requests containing a chat history and a list of function definitions.
2. Calls the model backend to generate a response.
3. Returns the model’s structured output (either a function call JSON or a text reply).

You can implement the server using SwiftNIO, Vapor or any other networking framework.  Expose a single endpoint (e.g. `/chat`) that accepts messages and a `functions` array, similar to the OpenAI API.  The response should include a `name` and `arguments` when the model decides to call a function.

### 3. Persona definition

Inside FountainKit, create a new persona subclass (see `GatewayPersonaOrchestrator` for examples).  The persona’s `evaluate` method should:

1. Inspect the incoming gateway request; if the request’s persona requires local inference, forward the relevant parts (user messages and available functions) to your local service.
2. Wait for the response and parse the function call or text.
3. Return an `EvaluationResult.allow` with the transformed message so that the planner can continue.  You may also add hints such as `routingMode=local` in the response metadata to guide the planner.

Personas are configured via Markdown definitions in FountainKit.  In your definition file, reference your local service under the `agent` or `personality` section so the gateway knows which server to call.

## Setup

1. **Choose a model** – Select a function‑calling model from Hugging Face that meets your latency and accuracy requirements.  For offline use on Mac, 7–13 B models (e.g. Gorilla OpenFunctions v2 or Hermes 2 Pro) are reasonable; larger models like FireFunction v1 (~46 B) may require external GPU support.
2. **Download and quantize** – Use `huggingface-cli` to download the GGUF file, or follow the instructions in each model’s README.  Store the file in your project’s `Models/` directory.
3. **Integrate a Swift wrapper** – If you want to *own* the entire stack, write your own Swift wrapper around the inference engine.  Compile `llama.cpp` as a static library, expose its C API via a `module.modulemap`, and implement a Swift class or actor that loads the GGUF model, streams tokens and formats outputs in OpenAI’s function‑calling schema.  Alternatively, convert your model to Core ML and wrap it using Apple’s `MLModel` API.  Existing projects like Kuzco or LocalLLMClient can serve as inspiration, but they are not dependencies when you control the wrapper yourself.
4. **Implement the bridge server** – Write a small Swift server (using Vapor or SwiftNIO) that exposes the `/chat` API.  Use your model wrapper to process requests.
5. **Register a persona** – In FountainKit’s configuration, create a new persona that calls your server.  Update the gateway’s plugin list to include this persona.
6. **Test end‑to‑end** – Start your local agent, then send a request through FountainKit’s gateway.  The planner should route the request to your persona, call the local model, and return the function call or completion through the normal function‑calling pipeline.

## Hugging Face interoperability

Hugging Face is the canonical source for open LLM weights and makes it easy to download models programmatically.  When selecting a model, look for:

* **Function‑calling support** – Models like `gorilla-openfunctions-v2`, `Hermes-2-Pro-Mistral-7B-GGUF` and `firefunction-v1` are fine‑tuned specifically for function calling.  Their model cards document supported features and provide GGUF files for `llama.cpp`.
* **Licence** – Choose models with permissive licences (e.g. Apache 2.0) if you plan to embed them in a commercial application.
* **Model size** – Verify that the GGUF file will fit into memory on your target Mac.  Use quantization (`q4`, `q5` etc.) to reduce memory usage at the cost of some accuracy.

## Native Apple tooling

Besides `llama.cpp`, Apple provides native tools for running LLMs:

* **Core ML Tools** – Allows you to convert PyTorch or TensorFlow models to Core ML format.  Apple’s Llama 3.1 guide demonstrates how to export a mid‑sized model, optimize it and achieve ~33 tokens/s on an M1 Max.  Use Core ML when you need tight integration with Vision/Audio frameworks or when you want to leverage Apple’s neural engine.
* **MLX** – Apple’s new machine‑learning framework for GPU/CPU inference.  The `LocalLLMClient` package supports MLX as a backend alongside `llama.cpp`.  MLX currently offers faster performance but supports a narrower set of models.

When building a macOS runtime, you may choose to support both backends: start with `llama.cpp` for broad model coverage, then add a Core ML or MLX path for models that provide a Core ML export.

## Integration with FountainKit

Once your agent service and persona are in place, you can integrate it into FountainKit by:

1. **Configuring the gateway** – In the gateway’s YAML configuration, add your persona plugin to the chain.  Optionally set `tool-loading` parameters so that the planner knows your persona supports function calling.
2. **Registering functions** – Use the FountainKit function‑caller service to register the functions that your agent can call.  The functions should be described using the OpenAPI‑like schema (name, description and JSON schema for parameters).
3. **Enabling reflection/memory (optional)** – If you need the agent to remember past interactions, integrate FountainKit’s persistence service.  Store reflections and semantic arcs in a corpus and load them as context when invoking the local model.

## Security considerations

Running models locally improves privacy, but you should still:

* Validate inputs received by your bridge server to avoid injection attacks.
* Restrict the functions exposed to the model to a whitelisted set that your application controls.
* Monitor resource usage (CPU/GPU) to prevent runaway inference on client machines.

## License

This documentation is provided under the MIT licence.  Ensure that any model weights you download comply with their respective licences (many function‑calling models use Apache 2.0 or similar permissive terms).  If you distribute the compiled application, include copies of the model licences and attributions as required.
