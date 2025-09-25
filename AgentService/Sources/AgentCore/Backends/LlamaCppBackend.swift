import Foundation

#if canImport(LlamaCppC)
#if canImport(LlamaCppC)
import LlamaCppC
#elseif canImport(LlamaCppCBinary)
import LlamaCppCBinary
#endif

public final class LlamaCppBackend: ModelBackend {
    // MARK: - Configuration
    public struct Options {
        public var contextSize: Int32
        public var gpuLayers: Int32
        public var threads: Int32
        public var sampler: SamplerOptions
        public init(contextSize: Int32 = 4096, gpuLayers: Int32 = 35, threads: Int32 = Int32(max(1, ProcessInfo.processInfo.processorCount - 1)), sampler: SamplerOptions = .init()) {
            self.contextSize = contextSize
            self.gpuLayers = gpuLayers
            self.threads = threads
            self.sampler = sampler
        }
    }

    // MARK: - State
    public let modelPath: String
    public let options: Options
    public let tokenizer: Tokenizer

    // Pointers to llama.cpp objects (types depend on the installed header).
    // Use OpaquePointer to avoid tight coupling to specific header versions.
    private var model: UnsafeMutablePointer<llc_model>?
    private var ctx: UnsafeMutablePointer<llc_context>?

    // MARK: - Lifecycle
    public init(modelPath: String?, options: Options = Options(), tokenizer: Tokenizer = BasicWhitespaceTokenizer()) throws {
        guard let modelPath, !modelPath.isEmpty else {
            throw NSError(domain: "LlamaCppBackend", code: 1, userInfo: [NSLocalizedDescriptionKey: "modelPath is required for llama.cpp backend"])
        }
        self.modelPath = modelPath
        self.options = options
        self.tokenizer = tokenizer

        // Initialize llama backend and open model/context via wrappers
        llc_backend_init()
        self.model = llc_load_model(modelPath, options.gpuLayers)
        guard let model = self.model else {
            throw NSError(domain: "LlamaCppBackend", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to load model at \(modelPath)"])
        }
        self.ctx = llc_new_context(model, options.contextSize, options.threads)
        guard self.ctx != nil else {
            llc_free_model(model)
            throw NSError(domain: "LlamaCppBackend", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create context"])
        }
    }

    deinit {
        if let ctx { llc_free_context(ctx) }
        if let model { llc_free_model(model) }
        llc_backend_free()
    }

    // MARK: - Inference
    public func generateResponse(for request: ChatRequest) async throws -> ChatResponse {
        // TODO: Build prompt from messages + functions (OpenAI function-calling schema)
        // For function-calling, you typically format a system prompt that instructs
        // the model to output a JSON object with {"name": ..., "arguments": ...}.
        // Consider using a JSON grammar for stricter outputs.

        let prompt = buildPrompt(messages: request.messages, functions: request.functions, functionCall: request.function_call)

        // Tokenize prompt using llama tokenizer (two-pass)
        guard let model = self.model, let ctx = self.ctx else {
            throw NSError(domain: "LlamaCppBackend", code: 10, userInfo: [NSLocalizedDescriptionKey: "Backend not initialized"])
        }

        var count = llc_tokenize(model, prompt, true, nil, 0)
        if count <= 0 { count = 1 }
        var tokens = Array<llc_token>(repeating: 0, count: Int(count))
        let wrote = llc_tokenize(model, prompt, true, &tokens, count)
        let n_input = max(0, min(count, wrote))

        // Prefill context
        _ = llc_eval(ctx, tokens, n_input, 0, options.threads)
        var nPast: Int32 = n_input

        // Decode loop
        let vocab = Int(llc_n_vocab(model))
        var sseChunks: [String] = []
        var stop = false
        let eos = llc_eos_token(model)
        let maxNew: Int = 128
        for _ in 0..<maxNew {
            guard let logitsPtr = llc_get_logits(ctx) else { break }
            // Copy logits into Swift array (vocab length)
            let logits = Array(UnsafeBufferPointer(start: logitsPtr, count: vocab))
            let nextId = Sampling.sample(from: logits, options: options.sampler)
            let piece = tokenToString(model: model, token: Int32(nextId))
            let stepJSON = jsonString(obj: ["delta": piece])
            sseChunks.append("event: message\ndata: \(stepJSON)\n\n")
            var t: [llc_token] = [llc_token(nextId)]
            _ = llc_eval(ctx, &t, 1, nPast, options.threads)
            nPast += 1
            if Int32(nextId) == eos { stop = true; break }
        }
        sseChunks.append("event: done\ndata: {}\n\n")
        // Convert SSE chunks into a ChatResponse summary (non-streaming compatibility)
        let ts = Int(Date().timeIntervalSince1970)
        let id = "chatcmpl-llama-\(UUID().uuidString.prefix(8))"
        let modelName = request.model ?? "local-llama"
        let content = sseChunks.joined()
        let assistant = AssistantMessage(role: "assistant", content: content, function_call: nil)
        let choice = ChatChoice(index: 0, message: assistant, finish_reason: stop ? "stop" : "length")
        return ChatResponse(id: id, object: "chat.completion", created: ts, model: modelName, choices: [choice])
    }

    // Streaming generation using SSE-style event concatenation.
    public func generateSSE(for request: ChatRequest) async throws -> (headers: [String : String], body: String) {
        let headers = [
            "Content-Type": "text/event-stream; charset=utf-8",
            "Cache-Control": "no-cache",
            "X-Chunked-SSE": "1"
        ]

        // Build prompt and tokenize
        let prompt = buildPrompt(messages: request.messages, functions: request.functions, functionCall: request.function_call)
        var sse = ""
        // TODO: Use llama_tokenize(model, prompt, ...) to obtain tokens
        // let tokens: [llama_token] = tokenize(prompt)
        // TODO: Feed tokens (prefill) via llama_decode or llama_eval
        // _ = decode(tokens)
        // TODO: Iteratively sample next tokens using logits and options.sampler
        // Example pseudo-loop (replace with real llama.cpp calls):
        // var generated = 0
        // while generated < 64 {
        //   let logits = getLogits() // [Float] of size n_vocab
        //   let id = Sampling.sample(from: logits, options: options.sampler)
        //   let piece = tokenToString(id)
        //   sse += "event: message\ndata: {\"delta\":\"\(piece)\"}\n\n"
        //   if id == eos { break }
        //   _ = decode([id])
        //   generated += 1
        // }
        // Signal end
        sse += "event: done\ndata: {}\n\n"
        return (headers, sse)
    }

    // MARK: - llama.cpp helpers (to implement against your installed headers)
    // private func tokenize(_ text: String) -> [Int32] { ... } // llama_tokenize
    // private func decode(_ tokens: [Int32]) -> Bool { ... }   // llama_decode/llama_eval
    // private func getLogits() -> [Float] { ... }              // llama_get_logits
    // private func tokenToString(_ id: Int) -> String { ... }  // llama_token_to_piece / llama_token_to_str

    // MARK: - Prompt building
    private func buildPrompt(messages: [ChatMessage], functions: [FunctionDefinition]?, functionCall: FunctionCallOption?) -> String {
        var sb: [String] = []
        // Basic chat format; adapt to your model’s expected formatting (e.g. ChatML, Llama-2, Mistral Instruct).
        sb.append("System: You are a helpful assistant capable of calling functions by returning a JSON object with keys 'name' and 'arguments'.")
        if let functions, !functions.isEmpty {
            sb.append("Tools: The following functions are available. Describe parameters using JSON schema.")
            for fn in functions {
                let params = fn.parameters?.properties != nil ? "(schema present)" : "(no schema)"
                sb.append("- \(fn.name): \(fn.description ?? "") \(params)")
            }
            switch functionCall {
            case .some(.none):
                sb.append("Directive: Do NOT call any function. Provide a plain text answer.")
            case .some(.force(let name)):
                sb.append("Directive: You MUST call function named '\(name)'.")
            default:
                sb.append("Directive: Call a function when appropriate; otherwise, reply with text.")
            }
        }
        for m in messages {
            let role = m.role.capitalized
            sb.append("\(role): \(m.content ?? "")")
        }
        sb.append("Assistant:")
        return sb.joined(separator: "\n")
    }

    private func tokenToString(model: UnsafeMutablePointer<llc_model>, token: Int32) -> String {
        var buf = Array<CChar>(repeating: 0, count: 512)
        let n = llc_token_to_piece(model, token, &buf, Int32(buf.count))
        if n <= 0 { return "" }
        return String(cString: buf)
    }

    private func jsonString(obj: Any) -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: obj), encoding: .utf8)) ?? "{}"
    }
}
#endif
