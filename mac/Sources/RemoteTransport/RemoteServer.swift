import Foundation
import Hummingbird
import HummingbirdWebSocket
import RemoteCore

public struct RemoteServer: Sendable {
    let sessions: Sessions
    let state: @MainActor @Sendable () -> RemoteState
    let input: @MainActor @Sendable (Message, UUID) throws -> Void
    let release: @MainActor @Sendable (UUID) -> Void
    let ready: @MainActor @Sendable () -> Void

    public init(sessions: Sessions,
                state: @escaping @MainActor @Sendable () -> RemoteState,
                input: @escaping @MainActor @Sendable (Message, UUID) throws -> Void,
                release: @escaping @MainActor @Sendable (UUID) -> Void,
                ready: @escaping @MainActor @Sendable () -> Void) {
        self.sessions = sessions; self.state = state; self.input = input; self.release = release; self.ready = ready
    }

    public func application(webRoot: String? = nil, port: Int = NetworkAddress.port) -> some ApplicationProtocol {
        let router = Router(context: BasicWebSocketRequestContext.self)
        let resources = webRoot ?? ProcessInfo.processInfo.environment["GIMME_WEB_ROOT"]
            ?? Bundle.main.resourceURL?.appendingPathComponent("Web").path
            ?? "web/dist"
        router.middlewares.add(FileMiddleware(resources, searchForIndexHtml: true))
        router.get("/health") { _, _ in "Gimme Remote v1" }
        router.ws("/ws", shouldUpgrade: { request, _ in
            let development = Set((ProcessInfo.processInfo.environment["GIMME_DEV_ORIGINS"] ?? "")
                .split(separator: ",").map(String.init))
            guard OriginPolicy.permits(origin: request.headers[.origin], host: request.head.authority,
                                       allowed: NetworkAddress.origins(port: port), development: development) else {
                return .dontUpgrade
            }
            return .upgrade()
        }) { inbound, outbound, _ in
            let id = UUID()
            let generation: Int
            do { generation = try await sessions.open(id) } catch { return }
            let (stream, continuation) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingOldest(64))
            func send(_ message: Message) { continuation.yield(message.json()) }
            let start = ProcessInfo.processInfo.systemUptime
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        defer { continuation.finish() }
                        var highFrequency = RateLimiter(capacity: 150, perSecond: 120)
                        var controls = RateLimiter(capacity: 30, perSecond: 20)
                        var authentication = RateLimiter(capacity: 5, perSecond: 0.2)
                        for try await message in inbound.messages(maxSize: 32_768) {
                            guard await sessions.isCurrent(generation) else { return }
                            await sessions.touch(id)
                            guard case .text(let text) = message else { throw ControlError("unsupportedMessage") }
                            var requestId: String?
                            do {
                                let request = try Message.decode(text)
                                requestId = request.requestId
                                if request.type == "session.authenticate" || request.type == "session.pair" {
                                    guard authentication.allow() else { throw ControlError("rateLimited") }
                                    if request.type == "session.pair" {
                                        var payload = Payload()
                                        payload.token = try await sessions.pair(id, code: request.payload.code!,
                                                                               name: request.payload.deviceName ?? "iPhone")
                                        send(.init(type: "session.paired", requestId: requestId, payload: payload))
                                    } else {
                                        try await sessions.authenticate(id, token: request.payload.token!)
                                        send(.init(type: "session.authenticated", requestId: requestId))
                                    }
                                    var payload = Payload(); payload.state = await state()
                                    send(.init(type: "state.updated", payload: payload))
                                    continue
                                }
                                guard await sessions.isAuthenticated(id) else { throw ControlError("unauthorized") }
                                let fast = ["input.pointer.move", "input.pointer.scroll"].contains(request.type)
                                guard fast ? highFrequency.allow() : controls.allow() else { throw ControlError("rateLimited") }
                                if request.type == "session.disconnect" { return }
                                if request.type == "session.heartbeat" {
                                    send(.init(type: "session.heartbeat", requestId: requestId))
                                } else {
                                    try await input(request, id)
                                    if requestId != nil { send(.init(type: "input.accepted", requestId: requestId)) }
                                }
                            } catch {
                                var payload = Payload(); payload.error = (error as? ControlError)?.code ?? "invalidPayload"
                                send(.init(type: "error.control", requestId: requestId, payload: payload))
                                // Keep an unauthenticated connection open long enough for
                                // the phone to receive the error and offer re-pairing.
                                if payload.error == "rateLimited" { return }
                            }
                        }
                    }
                    group.addTask {
                        var previous: RemoteState?
                        while !Task.isCancelled {
                            try await Task.sleep(for: .seconds(1))
                            guard await sessions.isCurrent(generation) else { return }
                            if await sessions.isAuthenticated(id) {
                                guard !(await sessions.isIdle(id)) else { return }
                                let value = await state()
                                if value.locked || !value.accessibility || value.paused { await release(id) }
                                // A heartbeat also keeps state fresh after Safari resumes.
                                var payload = Payload(); payload.state = value
                                send(.init(type: previous == value ? "state.heartbeat" : "state.updated", payload: payload))
                                previous = value
                            } else if ProcessInfo.processInfo.systemUptime - start > 30 { return }
                        }
                    }
                    group.addTask {
                        for await text in stream {
                            try Task.checkCancellation()
                            try await outbound.write(.text(text))
                        }
                    }
                    _ = try await group.next()
                    continuation.finish()
                    group.cancelAll()
                }
            } catch {
                // Closing a connection is expected; never log pairing codes or tokens.
            }
            continuation.finish()
            await sessions.close(id)
            await release(id)
        }
        let application = Application(
            router: router,
            server: .http1WebSocketUpgrade(webSocketRouter: router, configuration: .init(ws: .init(maxFrameSize: 32_768, autoPing: .enabled(timePeriod: .seconds(10))))),
            configuration: .init(address: .hostname("0.0.0.0", port: port)),
            onServerRunning: { _ in await ready() }
        )
        return application
    }

    public func run() async throws { try await application().run() }
}
