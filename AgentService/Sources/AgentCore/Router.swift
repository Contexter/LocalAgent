import Foundation

public func makeKernel(backend: ModelBackend) -> HTTPKernel {
    HTTPKernel { req in
        // Health endpoint
        if req.method == "GET" && req.path == "/health" {
            return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data("ok".utf8))
        }
        // Chat endpoint (JSON)
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
        // Chat SSE endpoint
        if req.method == "POST" && (req.path == "/chat/stream" || req.path.hasPrefix("/chat?")) {
            // Simple query parse to detect .../chat?stream=1
            if req.path == "/chat/stream" || req.path.contains("stream=1") {
                do {
                    let chatReq = try JSONDecoder().decode(ChatRequest.self, from: req.body)
                    let (headers, body) = try await backend.generateSSE(for: chatReq)
                    return HTTPResponse(status: 200, headers: headers, body: Data(body.utf8))
                } catch {
                    let payload = ["event: message\ndata: {\"error\":\"\(String(describing: error))\"}\n\n",
                                   "event: done\ndata: {}\n\n"].joined()
                    let headers = [
                        "Content-Type": "text/event-stream; charset=utf-8",
                        "Cache-Control": "no-cache",
                        "X-Chunked-SSE": "1"
                    ]
                    return HTTPResponse(status: 200, headers: headers, body: Data(payload.utf8))
                }
            }
        }
        // Not found
        return HTTPResponse(status: 404, headers: ["Content-Type": "text/plain"], body: Data("Not Found".utf8))
    }
}
