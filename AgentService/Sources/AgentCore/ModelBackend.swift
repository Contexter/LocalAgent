import Foundation

public protocol ModelBackend {
    func generateResponse(for request: ChatRequest) async throws -> ChatResponse
}

public extension ModelBackend {
    /// Default SSE generator: encodes the full ChatResponse as a single event and signals done.
    func generateSSE(for request: ChatRequest) async throws -> (headers: [String: String], body: String) {
        let resp = try await generateResponse(for: request)
        let json = (try? String(data: JSONEncoder().encode(resp), encoding: .utf8)) ?? "{}"
        let sse = [
            "event: message\ndata: \(json)\n\n",
            "event: done\ndata: {}\n\n"
        ].joined()
        let headers = [
            "Content-Type": "text/event-stream; charset=utf-8",
            "Cache-Control": "no-cache",
            "X-Chunked-SSE": "1"
        ]
        return (headers, sse)
    }
}

public struct MockBackend: ModelBackend {
    public init() {}
    public func generateResponse(for request: ChatRequest) async throws -> ChatResponse {
        let ts = Int(Date().timeIntervalSince1970)
        let id = "chatcmpl-local-\(UUID().uuidString.prefix(8))"
        let model = request.model ?? "local-mock-1"

        // Last user message content
        let lastUser = request.messages.last(where: { $0.role == "user" })?.content ?? ""
        let (shouldCall, chosenFn) = selectFunction(tools: request.functions, lastUser: lastUser, option: request.function_call)

        if shouldCall, let fn = chosenFn {
            let args = extractJSONArguments(from: lastUser) ?? "{}"
            let assistant = AssistantMessage(role: "assistant",
                                             content: nil,
                                             function_call: FunctionCall(name: fn.name, arguments: args))
            let choice = ChatChoice(index: 0, message: assistant, finish_reason: "function_call")
            return ChatResponse(id: id, object: "chat.completion", created: ts, model: model, choices: [choice])
        } else {
            let reply = defaultTextReply(for: lastUser, functions: request.functions)
            let assistant = AssistantMessage(role: "assistant", content: reply, function_call: nil)
            let choice = ChatChoice(index: 0, message: assistant, finish_reason: "stop")
            return ChatResponse(id: id, object: "chat.completion", created: ts, model: model, choices: [choice])
        }
    }

    private func selectFunction(tools: [FunctionDefinition]?, lastUser: String, option: FunctionCallOption?) -> (Bool, FunctionDefinition?) {
        guard let tools, !tools.isEmpty else { return (false, nil) }

        // Respect explicit disable
        if case .none? = option { return (false, nil) }

        // If explicitly forced to a name
        if case .force(let name)? = option, let match = tools.first(where: { $0.name == name }) {
            return (true, match)
        }

        // Heuristic: if user mentions function name or says "call <name>"
        if let match = tools.first(where: { n in
            lastUser.localizedCaseInsensitiveContains("call \(n.name)") ||
            lastUser.localizedCaseInsensitiveContains("use \(n.name)") ||
            lastUser.localizedCaseInsensitiveContains("\(n.name)(") ||
            lastUser.localizedCaseInsensitiveContains("\(n.name) {") ||
            lastUser.localizedCaseInsensitiveContains("\(n.name) with")
        }) {
            return (true, match)
        }

        // Default: if functions provided and in auto mode, prefer function call
        return (true, tools.first)
    }

    private func extractJSONArguments(from text: String) -> String? {
        // Find the first {...} JSON object in the text (shallow heuristic)
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        let candidate = String(text[start...end])
        // Validate JSON
        if let data = candidate.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil {
            return candidate
        }
        return nil
    }

    private func defaultTextReply(for lastUser: String, functions: [FunctionDefinition]?) -> String {
        if let tools = functions, !tools.isEmpty {
            return "No explicit tool call detected. Provide arguments as JSON to trigger a function call, e.g. call \(tools[0].name) with { ... }."
        }
        return "Echo: \(lastUser)"
    }

    public func generateSSE(for request: ChatRequest) async throws -> (headers: [String : String], body: String) {
        let resp = try await generateResponse(for: request)
        var sse = ""
        if let fc = resp.choices.first?.message.function_call {
            // Stream function_call arguments progressively (JSON-encoded to avoid escaping issues)
            func asJSON(_ obj: Any) -> String {
                (try? String(data: JSONSerialization.data(withJSONObject: obj), encoding: .utf8)) ?? "{}"
            }
            var args = ""
            sse += "event: message\ndata: \(asJSON(["function_call": ["name": fc.name, "arguments": args]]))\n\n"
            for ch in fc.arguments {
                args.append(ch)
                sse += "event: message\ndata: \(asJSON(["function_call": ["name": fc.name, "arguments": args]]))\n\n"
            }
        } else if let text = resp.choices.first?.message.content {
            // Stream words as deltas
            func asJSON(_ obj: Any) -> String {
                (try? String(data: JSONSerialization.data(withJSONObject: obj), encoding: .utf8)) ?? "{}"
            }
            for word in text.split(separator: " ") {
                sse += "event: message\ndata: \(asJSON(["delta": String(word)]))\n\n"
            }
        }
        sse += "event: done\ndata: {}\n\n"
        let headers = [
            "Content-Type": "text/event-stream; charset=utf-8",
            "Cache-Control": "no-cache",
            "X-Chunked-SSE": "1"
        ]
        return (headers, sse)
    }
}
