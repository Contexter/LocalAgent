@preconcurrency import NIO
@preconcurrency import NIOHTTP1
import Foundation

public final class NIOHTTPServer: @unchecked Sendable {
    let kernel: HTTPKernel
    let group: EventLoopGroup
    var channel: Channel?

    public init(kernel: HTTPKernel, group: EventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)) {
        self.kernel = kernel
        self.group = group
    }

    @discardableResult
    public func start(host: String = "127.0.0.1", port: Int) async throws -> Int {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPHandler(kernel: self.kernel))
                }
            }
        self.channel = try await bootstrap.bind(host: host, port: port).get()
        return self.channel?.localAddress?.port ?? port
    }

    public func stop() async throws {
        try await channel?.close().get()
        try await group.shutdownGracefully()
    }

    final class HTTPHandler: ChannelInboundHandler {
        typealias InboundIn = HTTPServerRequestPart
        typealias OutboundOut = HTTPServerResponsePart

        let kernel: HTTPKernel
        var head: HTTPRequestHead?
        var body: ByteBuffer?

        init(kernel: HTTPKernel) { self.kernel = kernel }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            switch unwrapInboundIn(data) {
            case .head(let h):
                head = h
                body = context.channel.allocator.buffer(capacity: 0)
            case .body(var part):
                body?.writeBuffer(&part)
            case .end:
                guard let head else { return }
                let req = HTTPRequest(
                    method: head.method.rawValue,
                    path: head.uri,
                    headers: Dictionary(uniqueKeysWithValues: head.headers.map { ($0.name, $0.value) }),
                    body: Data(body?.readableBytesView ?? [])
                )
                Task {
                    let resp = try await self.kernel.handle(req)
                    context.eventLoop.execute {
                        var headers = HTTPHeaders()
                        for (k, v) in resp.headers { headers.add(name: k, value: v) }

                        let isSSE = headers["Content-Type"].first?.lowercased().contains("text/event-stream") == true
                        let chunkedSSE = isSSE && headers["X-Chunked-SSE"].first == "1"

                        var responseHead = HTTPResponseHead(version: head.version, status: .init(statusCode: resp.status))
                        if chunkedSSE {
                            headers.remove(name: "Content-Length")
                            headers.replaceOrAdd(name: "Transfer-Encoding", value: "chunked")
                        } else if headers["Content-Length"].isEmpty {
                            headers.add(name: "Content-Length", value: String(resp.body.count))
                        }
                        responseHead.headers = headers
                        context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)

                        if chunkedSSE {
                            let text = String(data: resp.body, encoding: .utf8) ?? ""
                            let parts = text.components(separatedBy: "\n\n").map { $0 + "\n\n" }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                            self.writeSSEChunks(parts, on: context, index: 0)
                        } else {
                            let buffer = context.channel.allocator.buffer(bytes: resp.body)
                            context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
                        }
                    }
                }
                self.head = nil
                self.body = nil
            }
        }

        private func writeSSEChunks(_ chunks: [String], on context: ChannelHandlerContext, index: Int) {
            if index >= chunks.count {
                context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
                return
            }
            let data = Data(chunks[index].utf8)
            let buf = context.channel.allocator.buffer(bytes: data)
            context.write(self.wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
            context.flush()
            context.eventLoop.scheduleTask(in: .milliseconds(40)) { [weak self] in
                guard let self else { return }
                self.writeSSEChunks(chunks, on: context, index: index + 1)
            }
        }
    }
}

extension NIOHTTPServer.HTTPHandler: @unchecked Sendable {}
extension ChannelHandlerContext: @unchecked @retroactive Sendable {}
