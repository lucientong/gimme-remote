import Foundation
import RemoteCore
import RemoteTransport

private struct MemoryVault: TokenVault {
    func load() throws -> [String: String] { [:] }
    func save(_ devices: [String: String]) throws {}
}

@MainActor
private final class Probe {
    var ready = false
    var accepted: [String] = []
    var releases = 0
    let state = RemoteState(appName: "Test Player", bundleId: "test", layout: "generic",
                            locked: false, accessibility: true, paused: false)
}

/// Exercises the real HTTP/WebSocket server, never AppKit input or the user's Keychain.
@main
struct TransportChecks {
    @MainActor
    static func main() async throws {
        let probe = Probe()
        let sessions = try Sessions(vault: MemoryVault())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("<title>Transport fixture</title>".utf8).write(to: folder.appendingPathComponent("index.html"))
        defer { try? FileManager.default.removeItem(at: folder) }
        let port = 19371
        let server = RemoteServer(sessions: sessions, state: { probe.state },
                                  input: { message, _ in probe.accepted.append(message.type) },
                                  release: { _ in probe.releases += 1 }, ready: { probe.ready = true })
        let serverTask = Task { try await server.application(webRoot: folder.path, port: port).run() }
        defer { serverTask.cancel() }
        for _ in 0..<100 {
            if probe.ready { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard probe.ready else { throw ControlError("Server did not start") }
        let base = "http://127.0.0.1:\(port)"
        let (body, response) = try await URLSession.shared.data(from: URL(string: base)!)
        precondition((response as? HTTPURLResponse)?.statusCode == 200)
        precondition(String(decoding: body, as: UTF8.self).contains("Transport fixture"))

        func socket(origin: String) -> URLSessionWebSocketTask {
            var request = URLRequest(url: URL(string: "ws://127.0.0.1:\(port)/ws")!)
            request.setValue(origin, forHTTPHeaderField: "Origin")
            let task = URLSession.shared.webSocketTask(with: request)
            task.resume()
            return task
        }
        func send(_ message: Message, to socket: URLSessionWebSocketTask) async throws {
            try await socket.send(.string(message.json()))
        }
        func receive(_ socket: URLSessionWebSocketTask) async throws -> [String: Any] {
            guard case .string(let text) = try await socket.receive(),
                  let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
                throw ControlError("Unexpected WebSocket response")
            }
            return object
        }
        let wrongOrigin = socket(origin: "http://untrusted.example")
        do {
            try await send(.init(type: "session.heartbeat"), to: wrongOrigin)
            _ = try await receive(wrongOrigin)
            throw ControlError("Wrong Origin accepted")
        } catch let error as ControlError { throw error } catch {}
        wrongOrigin.cancel(with: .goingAway, reason: nil)

        let unauthenticated = socket(origin: base)
        var payload = Payload(); payload.action = "playPause"
        try await send(.init(type: "media.command", requestId: "denied", payload: payload), to: unauthenticated)
        let denied = try await receive(unauthenticated)
        precondition((denied["payload"] as? [String: String])?["error"] == "unauthorized")
        precondition(probe.accepted.isEmpty)
        unauthenticated.cancel(with: .goingAway, reason: nil)

        let client = socket(origin: base)
        let code = try await sessions.newCode()
        payload = .init(); payload.code = code.code; payload.deviceName = "Check"
        try await send(.init(type: "session.pair", requestId: "pair", payload: payload), to: client)
        let paired = try await receive(client)
        precondition(paired["type"] as? String == "session.paired")
        let token = (paired["payload"] as? [String: String])?["token"]
        precondition(token?.count == 64)
        _ = try await receive(client) // Initial state.
        payload = .init(); payload.text = "流浪地球 🌏"
        try await send(.init(type: "input.text.insert", requestId: "text", payload: payload), to: client)
        var accepted = false
        for _ in 0..<5 {
            let result = try await receive(client)
            if result["type"] as? String == "input.accepted" && result["requestId"] as? String == "text" {
                accepted = true; break
            }
        }
        precondition(accepted && probe.accepted == ["input.text.insert"])
        payload = .init(); payload.text = String(repeating: "\n", count: 8192)
        try await send(.init(type: "input.text.insert", requestId: "boundary", payload: payload), to: client)
        accepted = false
        for _ in 0..<5 {
            let result = try await receive(client)
            if result["type"] as? String == "input.accepted" && result["requestId"] as? String == "boundary" {
                accepted = true; break
            }
        }
        precondition(accepted && probe.accepted.count == 2)
        try await sessions.revokeAll()
        payload = .init(); payload.action = "playPause"
        try? await send(.init(type: "media.command", payload: payload), to: client)
        try await Task.sleep(for: .milliseconds(150))
        precondition(probe.accepted.count == 2)
        client.cancel(with: .goingAway, reason: nil)
        serverTask.cancel()
        _ = try? await serverTask.value
        print("Transport checks passed: HTTP root, real WebSocket Origin rejection, unpaired input rejection, pairing, Unicode acknowledgement, maximum text frame, revocation.")
    }
}
