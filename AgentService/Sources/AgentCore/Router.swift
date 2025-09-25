import Foundation

public func makeKernel(backend: ModelBackend) -> HTTPKernel {
    HTTPKernel { req in
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
}

