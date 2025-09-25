import Foundation
import AgentCore

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
        let kernel = makeKernel(backend: backend)

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
