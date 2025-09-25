import Foundation

#if canImport(CoreML)
import CoreML

public struct CoreMLBackend: ModelBackend {
    public let modelPath: String?
    public let tokenizer: Tokenizer
    public let options: SamplerOptions

    public init(modelPath: String?, tokenizer: Tokenizer = BasicWhitespaceTokenizer(), options: SamplerOptions = .init()) {
        self.modelPath = modelPath
        self.tokenizer = tokenizer
        self.options = options
    }

    public func generateResponse(for request: ChatRequest) async throws -> ChatResponse {
        // Placeholder implementation to keep the server functional until a real
        // Core ML wrapper is added. Provides a clear diagnostic message.
        let ts = Int(Date().timeIntervalSince1970)
        let id = "chatcmpl-coreml-\(UUID().uuidString.prefix(8))"
        let model = request.model ?? "local-coreml"
        let msg = "CoreML backend not yet configured. Set modelPath and implement inference/tokenizer."
        let assistant = AssistantMessage(role: "assistant", content: msg, function_call: nil)
        let choice = ChatChoice(index: 0, message: assistant, finish_reason: "stop")
        return ChatResponse(id: id, object: "chat.completion", created: ts, model: model, choices: [choice])
    }
}
#endif
