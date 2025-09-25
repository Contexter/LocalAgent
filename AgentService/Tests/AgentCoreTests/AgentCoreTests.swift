import XCTest
@testable import AgentCore

final class AgentCoreTests: XCTestCase {
    func testHealthEndpoint() async throws {
        let kernel = makeKernel(backend: MockBackend())
        let req = HTTPRequest(method: "GET", path: "/health")
        let resp = try await kernel.handle(req)
        XCTAssertEqual(resp.status, 200)
        XCTAssertEqual(String(data: resp.body, encoding: .utf8), "ok")
    }

    func testFunctionCallAuto() async throws {
        let kernel = makeKernel(backend: MockBackend())
        let body = ChatRequest(
            model: "local-mock-1",
            messages: [ChatMessage(role: "user", content: "call schedule_meeting with {\"title\":\"Team sync\",\"time\":\"2025-01-01 10:00\"}")],
            functions: [FunctionDefinition(name: "schedule_meeting", description: "Schedule", parameters: .init(type: "object"))],
            function_call: .auto
        )
        let data = try JSONEncoder().encode(body)
        let req = HTTPRequest(method: "POST", path: "/chat", headers: ["Content-Type":"application/json"], body: data)
        let resp = try await kernel.handle(req)
        XCTAssertEqual(resp.status, 200)
        let chat = try JSONDecoder().decode(ChatResponse.self, from: resp.body)
        XCTAssertEqual(chat.choices.first?.finish_reason, "function_call")
        XCTAssertEqual(chat.choices.first?.message.function_call?.name, "schedule_meeting")
        XCTAssertTrue((chat.choices.first?.message.function_call?.arguments.contains("Team sync")) == true)
    }

    func testFunctionCallNoneForcesText() async throws {
        let kernel = makeKernel(backend: MockBackend())
        let body = ChatRequest(
            model: "local-mock-1",
            messages: [ChatMessage(role: "user", content: "please schedule a meeting")],
            functions: [FunctionDefinition(name: "schedule_meeting", description: "Schedule", parameters: .init(type: "object"))],
            function_call: .some(.none)
        )
        let data = try JSONEncoder().encode(body)
        let req = HTTPRequest(method: "POST", path: "/chat", headers: ["Content-Type":"application/json"], body: data)
        let resp = try await kernel.handle(req)
        XCTAssertEqual(resp.status, 200)
        let chat = try JSONDecoder().decode(ChatResponse.self, from: resp.body)
        XCTAssertEqual(chat.choices.first?.finish_reason, "stop")
        XCTAssertNil(chat.choices.first?.message.function_call)
        XCTAssertNotNil(chat.choices.first?.message.content)
    }

    func testNoFunctionsTextEcho() async throws {
        let kernel = makeKernel(backend: MockBackend())
        let body = ChatRequest(
            model: nil,
            messages: [ChatMessage(role: "user", content: "hello")],
            functions: nil,
            function_call: nil
        )
        let data = try JSONEncoder().encode(body)
        let req = HTTPRequest(method: "POST", path: "/chat", headers: ["Content-Type":"application/json"], body: data)
        let resp = try await kernel.handle(req)
        XCTAssertEqual(resp.status, 200)
        let chat = try JSONDecoder().decode(ChatResponse.self, from: resp.body)
        XCTAssertEqual(chat.choices.first?.finish_reason, "stop")
        XCTAssertEqual(chat.choices.first?.message.content, "Echo: hello")
    }

    func testSSEStreamMock() async throws {
        let kernel = makeKernel(backend: MockBackend())
        let body = ChatRequest(
            model: nil,
            messages: [ChatMessage(role: "user", content: "hello streaming friend")],
            functions: nil,
            function_call: nil
        )
        let data = try JSONEncoder().encode(body)
        let req = HTTPRequest(method: "POST", path: "/chat/stream", headers: ["Content-Type":"application/json"], body: data)
        let resp = try await kernel.handle(req)
        XCTAssertEqual(resp.status, 200)
        XCTAssertEqual(resp.headers["Content-Type"], "text/event-stream; charset=utf-8")
        XCTAssertEqual(resp.headers["X-Chunked-SSE"], "1")
        let s = String(data: resp.body, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("event: message"))
        XCTAssertTrue(s.contains("event: done"))
    }
}
