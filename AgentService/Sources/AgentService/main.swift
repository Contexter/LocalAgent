import Foundation

@main
struct Main {
    static func main() async throws {
        // Load config; default to mock backend on 127.0.0.1:8080
        let config = try AgentConfig.load()
        let backend: ModelBackend
        switch config.backend.lowercased() {
        case "mock":
            backend = MockBackend()
        case "coreml":
            #if canImport(CoreML)
            backend = CoreMLBackend(modelPath: config.modelPath)
            #else
            print("[AgentService] CoreML not available. Falling back to 'mock'.")
            backend = MockBackend()
            #endif
        case "llama", "llama.cpp", "llamacpp":
            #if canImport(LlamaCppC)
            backend = try LlamaCppBackend(modelPath: config.modelPath)
            #else
            print("[AgentService] LlamaCppC module not available. Falling back to 'mock'.")
            backend = MockBackend()
            #endif
        default:
            print("[AgentService] Unknown backend \(config.backend). Falling back to 'mock'.")
            backend = MockBackend()
        }

        // Build HTTP kernel (router)
        let kernel = HTTPKernel { req in
            // Health endpoint
            if req.method == "GET" && req.path == "/health" {
                return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data("ok".utf8))
            }
            // Chat endpoint
            if req.method == "POST" && req.path == "/chat" {
                do {
                    let chatReq = try JSONDecoder().decode(ChatRequest.self, from: req.body)
                    let result = try await backend.generateResponse(for: chatReq)
                    let data = try JSONEncoder().encode(result)
                    return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
                } catch {
                    let payload = ["error": String(describing: error)]
                    let data = (try? JSONEncoder().encode(payload)) ?? Data()
                    return HTTPResponse(status: 400, headers: ["Content-Type": "application/json"], body: data)
                }
            }
            // Not found
            return HTTPResponse(status: 404, headers: ["Content-Type": "text/plain"], body: Data("Not Found".utf8))
        }

        // Start SwiftNIO HTTP server
        let server = NIOHTTPServer(kernel: kernel)
        let host = config.host ?? "127.0.0.1"
        let desiredPort = config.port ?? 8080
        let bound = try await server.start(host: host, port: desiredPort)
        print("[AgentService] listening on \(host):\(bound) using backend=\(config.backend)")

        // Keep running until SIGINT/SIGTERM
        withExtendedLifetime(server) {
            RunLoop.main.run()
        }
    }
}
