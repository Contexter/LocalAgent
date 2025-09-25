# FountainKit Local Agent Runtime

**FountainKit Local Agent Runtime** provides a turnkey environment for running open‑source large‑language models (LLMs) on macOS and iOS devices and integrating them into the [FountainKit](https://github.com/Fountain-Coach/FountainKit) ecosystem.  Unlike one‑off demo apps, this project is designed for teams who **want to own the entire local‑inference stack**, including the Swift wrappers around the inference engine.  The runtime loads quantized GGUF models from [Hugging Face](https://huggingface.co/), exposes a simple chat API compatible with OpenAI’s function‑calling protocol and registers itself as a persona in the FountainKit gateway.  This allows you to build intelligent agents that run offline, protect user privacy and avoid cloud inference costs while maintaining full control over the code.

## Features

* **Offline and private** – Runs LLM inference entirely on the user’s device.  No data is sent to third‑party servers.  Works on Apple Silicon (M1/M2/M3) Macs and iPhones/iPads.
* **Function‑calling capable** – Supports models tuned for JSON‑structured function calls (e.g. Gorilla OpenFunctions v2, Hermes 2 Pro, FireFunction v1).  Accepts a list of function definitions and returns a function call or text response.
* **Hugging Face interoperability** – Easily download and manage models from Hugging Face.  Supports GGUF quantization for efficient inference via `llama.cpp`.  Model size can be reduced via Q4/Q5 quantization.
* **Native Apple tooling and custom wrappers** – Offers multiple backends: compile `llama.cpp` yourself and wrap it in Swift for full control, use Core ML for hardware‑accelerated inference, or leverage MLX for GPU‑accelerated models.  You’re *not* tied to third‑party wrappers—this repository includes examples and guidance for building your own, with Kuzco or LocalLLMClient serving only as references if you need inspiration.
* **Seamless FountainKit integration** – Provides configuration templates and persona definitions so your local agent can plug into the FountainKit gateway, planner and function‑caller services.
* **Extensible service layer** – Built on SwiftNIO, the chat service can be extended to support streaming responses, authentication, custom logging or additional endpoints.

## Prerequisites

* **Apple hardware** – A Mac with an M1 or later processor is recommended.  iOS and Mac Catalyst apps require iOS 15+/macOS 12+.
* **Xcode** – Install the latest Xcode to build Swift packages and run the sample app.
* **Model weights** – Download one or more function‑calling models from Hugging Face.  We recommend starting with:
  * [`gorilla-llm/gorilla-openfunctions-v2-gguf`](https://huggingface.co/gorilla-llm/gorilla-openfunctions-v2-gguf)
  * [`NousResearch/Hermes-2-Pro-Mistral-7B-GGUF`](https://huggingface.co/NousResearch/Hermes-2-Pro-Mistral-7B-GGUF)
  * [`fireworks-ai/firefunction-v1`](https://huggingface.co/fireworks-ai/firefunction-v1) (via Ollama)

Ensure that the model licences permit your intended use (many are Apache 2.0).  For FireFunction v1, use the Ollama “firefunction” model tag to download a quantized version.

## Getting Started

The repository contains two main components:

### 1. `AgentService`

`AgentService` is a Swift package that hosts a local LLM and exposes a `/chat` endpoint that adheres to the OpenAI chat completion and function‑calling schema.  The package demonstrates how to bridge a C inference engine into Swift using a `module.modulemap` and how to implement an async streaming API in pure Swift.  It intentionally avoids depending on third‑party Swift wrappers, so you own the wrapper layer and can adapt it to your needs.

* Add `AgentService` to your project via Swift Package Manager.
* Configure the service with the path to your GGUF or Core ML model in `agent-config.json`.  When using a GGUF model, the service links directly against your compiled `llama.cpp` library.  When using a Core ML model, it loads the `.mlmodel` via `MLModel(contentsOf:)`.
* Run the service using `swift run AgentService` and verify that `http://localhost:8080/chat` returns responses.
* Streaming is supported at `POST /chat/stream` (Server‑Sent Events).

### 2. `FountainKitIntegration`

This module contains a FountainKit persona and configuration templates.  It demonstrates how to register the local agent as a persona and route requests through FountainKit’s gateway.

* Copy `LocalAgentPersona.md` into your FountainKit repository’s `personas/` directory.
* Update the `gateway.yaml` to include the `LocalAgentPersona` plugin in the plugin chain.
* Start FountainKit’s gateway, planner, function‑caller and persistence services.
* Send a chat request through the gateway; the planner will delegate the function‑calling request to your local agent.

## Hugging Face Models and Quantization

Most function‑calling models require several gigabytes of memory in their native form.  To run them comfortably on consumer hardware, quantize them:

1. **Download** – Use `huggingface-cli` or `git lfs` to pull the model repository.  Alternatively, for FireFunction models, use `ollama pull joefamous/firefunction-v1:q4_0`.
2. **Quantize** – If the repository provides pre‑quantized GGUF files, download them directly.  Otherwise, convert the model using `llama.cpp`’s `convert.py` script and `quantize.py` (or the equivalent tools in other inference engines).
3. **Store** – Place the GGUF file in `Models/` and update your configuration.

Quantization levels (`q2`, `q3`, `q4`, `q5`, `q6`) represent a trade‑off between memory usage and accuracy.  Start with `q4` and adjust based on performance.

## Native Apple Tooling

The runtime supports multiple inference backends:

* **`llama.cpp` via custom Swift wrappers** – Compile `llama.cpp` yourself and create a Swift wrapper that exposes its C API.  This gives you full control over the code and eliminates reliance on third‑party packages.  Projects like [Kuzco](https://github.com/jaredcassoutt/Kuzco) demonstrate how to wrap `llama.cpp` in Swift; use them as references rather than dependencies.
* **Core ML** – Convert a PyTorch model to Core ML using the [coremltools](https://github.com/apple/coremltools) Python library.  Apple’s “On Device Llama 3.1 with Core ML” guide shows how to export Llama 3.1‑8B‑Instruct and achieve ~33 tokens/s on a Mac M1 Max.  After conversion, load the `.mlmodel` in Swift and call `prediction(from:)` to get outputs.
* **MLX** – Apple’s MLX framework offers GPU‑accelerated inference.  The [LocalLLMClient](https://github.com/tattn/LocalLLMClient) package includes an MLX backend.  Use it for models that have been ported to MLX (e.g. Gemma, Qwen 2.5) and when you require higher throughput than `llama.cpp`.

Choose the backend that best fits your hardware and model.

## Integration with FountainKit

FountainKit orchestrates requests through its gateway, planner, function‑caller and persistence services.  To integrate your local runtime:

1. **Implement a persona** – Create a persona definition in Markdown (see `LocalAgentPersona.md`) that instructs the gateway to forward certain requests (e.g. those requiring local inference) to your agent’s `/chat` endpoint.
2. **Add the persona to the gateway** – Edit `gateway.yaml` to include your persona plugin in the plugin chain.  You may also register the persona for specific triggers (e.g. project type or user role).
3. **Register functions** – Use the function‑caller service to register the functions your model can call.  For example, if your application can set timers, schedule meetings or fetch data, describe each function with a name, description and JSON schema.
4. **Test** – Run the FountainKit services and your local agent.  Send a high‑level objective (e.g. “schedule a meeting with my team next Tuesday at 3 PM”).  The planner will ask the agent to produce a function call, then the function‑caller will execute it, and the gateway will return the result.

## Development Notes

* **Service security** – Only expose the `/chat` API locally or behind authentication when deploying to production.  Validate and sanitize all user inputs.
* **Resource management** – Running large models on a laptop will consume CPU/GPU and memory.  Monitor system resources and choose appropriate quantization levels.
* **Model updates** – Keep track of new releases on Hugging Face; models are rapidly improving and may offer better function‑calling accuracy or smaller footprints.

## Contributing

Contributions are welcome!  If you find a bug or want to add support for another backend, please open an issue or submit a pull request.  When adding new models or examples, ensure that they comply with their respective licences and include attribution.

## License

This project is released under the MIT licence.  Third‑party models and libraries may have their own licences—please review them before use in production.

## Binaries

Prebuilt macOS arm64 binaries are published on tagged releases (`v*.*.*`).

- Artifact: `AgentService-macos-arm64.tar.gz` (contains the `AgentService` executable)
- Requirements when using llama backend:
  - `brew install llama.cpp` (ensures `libllama` is present at runtime)
  - Or build `llama.cpp` from source and make its `llama` library discoverable via `DYLD_LIBRARY_PATH` or install path
- Legal: This repository uses MIT‑licensed code. Model weights and `llama.cpp` carry their own licences; ensure compliance if redistributing.
