import Foundation
import Darwin
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
    var stopped = false
    var state = RemoteState(appName: "Test Player", bundleId: "test", layout: "generic",
                            locked: false, accessibility: true, paused: false)
}

/// Exercises the real HTTP/WebSocket server, never AppKit input or the user's Keychain.
@main
struct TransportChecks {
    @MainActor
    static func main() async {
        do { try await checkTransport() }
        catch {
            FileHandle.standardError.write(Data("Transport checks failed: \(error)\n".utf8))
            exit(1)
        }
    }

    @MainActor
    static func checkTransport() async throws {
        let probe = Probe()
        let sessions = try Sessions(vault: MemoryVault())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("<title>Transport fixture</title>".utf8).write(to: folder.appendingPathComponent("index.html"))
        defer { try? FileManager.default.removeItem(at: folder) }
        let port = 19371
        let server = RemoteServer(sessions: sessions, state: { probe.state },
                                  input: { message, _ in
                                      guard !probe.state.paused else { throw ControlError("servicePaused") }
                                      probe.accepted.append(message.type)
                                  },
                                  release: { _ in probe.releases += 1 }, ready: { probe.ready = true })
        let serverTask = Task {
            defer { probe.stopped = true }
            try await server.application(webRoot: folder.path, port: port).run()
        }
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
            let watchdog = Task {
                try await Task.sleep(for: .seconds(2))
                socket.cancel(with: .goingAway, reason: nil)
            }
            defer { watchdog.cancel() }
            guard case .string(let text) = try await socket.receive(),
                  let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
                throw ControlError("Unexpected WebSocket response")
            }
            return object
        }
        func authenticate(_ socket: URLSessionWebSocketTask, token: String) async throws {
            var payload = Payload(); payload.token = token
            try await send(.init(type: "session.authenticate", payload: payload), to: socket)
            let response = try await receive(socket)
            precondition(response["type"] as? String == "session.authenticated")
            _ = try await receive(socket)
        }
        func expectClose(_ socket: URLSessionWebSocketTask, code: Int) async throws {
            let start = ProcessInfo.processInfo.systemUptime
            do {
                // Buffered heartbeats may precede the close frame.
                for _ in 0..<10 { _ = try await receive(socket) }
                throw ControlError("Socket stayed open")
            } catch let error as ControlError { throw error } catch {}
            guard socket.closeCode.rawValue == code else {
                throw ControlError("Expected close \(code), received \(socket.closeCode.rawValue)")
            }
            guard ProcessInfo.processInfo.systemUptime - start < 1 else {
                throw ControlError("Close notification took over a second")
            }
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
        // Motion beyond the high-frequency budget is dropped without closing the socket.
        payload = .init(); payload.dx = 1; payload.dy = 0
        for _ in 0..<400 { try await send(.init(type: "input.pointer.move", payload: payload), to: client) }
        payload = .init(); payload.text = "still connected"
        try await send(.init(type: "input.text.insert", requestId: "flood", payload: payload), to: client)
        accepted = false
        for _ in 0..<5 {
            let result = try await receive(client)
            if result["type"] as? String == "input.accepted" && result["requestId"] as? String == "flood" {
                accepted = true; break
            }
        }
        let moves = probe.accepted.filter { $0 == "input.pointer.move" }.count
        precondition(accepted && moves < 400 && probe.accepted.last == "input.text.insert")
        for action in ["nextEpisode", "nextEpisode", "previousEpisode"] {
            payload = .init(); payload.action = action
            let requestId = "episode-\(probe.accepted.count)"
            try await send(.init(type: "media.command", requestId: requestId, payload: payload), to: client)
            var acknowledged = false
            for _ in 0..<5 {
                let result = try await receive(client)
                if result["requestId"] as? String == requestId {
                    acknowledged = result["type"] as? String == "input.accepted"
                    break
                }
            }
            precondition(acknowledged && probe.accepted.last == "media.command")
        }
        // The phone must receive independent availability and lose it on a tab/player transition.
        probe.state.layout = "browser"
        probe.state.episodeControls = .init(previous: false, next: true)
        await sessions.stateChanged()
        var capabilitiesArrived = false
        for _ in 0..<5 {
            let result = try await receive(client)
            if let state = (result["payload"] as? [String: Any])?["state"] as? [String: Any],
               let controls = state["episodeControls"] as? [String: Bool],
               controls["previous"] == false, controls["next"] == true {
                capabilitiesArrived = true; break
            }
        }
        precondition(capabilitiesArrived)
        probe.state.episodeControls = nil
        probe.state.layout = "generic"
        await sessions.stateChanged()
        var capabilitiesRemoved = false
        for _ in 0..<5 {
            let result = try await receive(client)
            if let state = (result["payload"] as? [String: Any])?["state"] as? [String: Any],
               state["layout"] as? String == "generic", state["episodeControls"] == nil {
                capabilitiesRemoved = true; break
            }
        }
        precondition(capabilitiesRemoved)
        // Pause/resume is pushed immediately without clearing authentication or waiting for a ticker.
        probe.state.paused = true
        let pauseStart = ProcessInfo.processInfo.systemUptime
        await sessions.stateChanged()
        var paused = false
        for _ in 0..<5 {
            let result = try await receive(client)
            if let state = (result["payload"] as? [String: Any])?["state"] as? [String: Any],
               state["paused"] as? Bool == true { paused = true; break }
        }
        guard paused && ProcessInfo.processInfo.systemUptime - pauseStart < 0.5 else {
            throw ControlError("Pause notification was not immediate")
        }
        let pauseCount = await sessions.activeCount()
        precondition(pauseCount == 1)
        payload = .init(); payload.action = "playPause"
        try await send(.init(type: "media.command", requestId: "paused", payload: payload), to: client)
        var pauseDenied = false
        for _ in 0..<5 {
            let result = try await receive(client)
            if result["requestId"] as? String == "paused" {
                pauseDenied = (result["payload"] as? [String: String])?["error"] == "servicePaused"
                break
            }
        }
        precondition(pauseDenied)
        probe.state.paused = false
        await sessions.stateChanged()
        var resumed = false
        for _ in 0..<5 {
            let result = try await receive(client)
            if let state = (result["payload"] as? [String: Any])?["state"] as? [String: Any],
               state["paused"] as? Bool == false { resumed = true; break }
        }
        precondition(resumed)

        let idle = socket(origin: base)
        try await authenticate(idle, token: token!)
        let beforeDisconnect = probe.accepted.count, beforeRelease = probe.releases
        await sessions.disconnectAll()
        try await expectClose(client, code: 4000)
        try await expectClose(idle, code: 4000)
        let disconnectedCount = await sessions.activeCount(), pairedCount = await sessions.pairedCount()
        precondition(disconnectedCount == 0 && pairedCount == 1)
        for _ in 0..<20 {
            if probe.releases >= beforeRelease + 2 { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        precondition(probe.releases >= beforeRelease + 2 && probe.accepted.count == beforeDisconnect)
        let reconnected = socket(origin: base)
        try await authenticate(reconnected, token: token!)
        let beforeRevoke = probe.accepted.count
        try await sessions.revokeAll()
        try await expectClose(reconnected, code: 4000)
        payload = .init(); payload.action = "playPause"
        try? await send(.init(type: "media.command", payload: payload), to: reconnected)
        precondition(probe.accepted.count == beforeRevoke)
        let revokedClient = socket(origin: base)
        payload = .init(); payload.token = token!
        try await send(.init(type: "session.authenticate", payload: payload), to: revokedClient)
        let revokeDenied = try await receive(revokedClient)
        precondition((revokeDenied["payload"] as? [String: String])?["error"] == "unauthorized")
        revokedClient.cancel(with: .goingAway, reason: nil)

        // The App drains its sockets before cancelling the listener, including idle readers.
        let quittingClient = socket(origin: base)
        let quitCode = try await sessions.newCode()
        payload = .init(); payload.code = quitCode.code
        try await send(.init(type: "session.pair", payload: payload), to: quittingClient)
        _ = try await receive(quittingClient)
        _ = try await receive(quittingClient)
        let shutdownWatchdog = Task {
            try await Task.sleep(for: .seconds(3))
            FileHandle.standardError.write(Data("Transport checks failed: shutdown timed out\n".utf8))
            exit(1)
        }
        await sessions.shutdown()
        shutdownWatchdog.cancel()
        serverTask.cancel()
        try await expectClose(quittingClient, code: 1001)
        for _ in 0..<80 {
            if probe.stopped { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        guard probe.stopped else { throw ControlError("Server did not finish shutdown") }
        _ = try? await serverTask.value
        print("Transport checks passed: HTTP root, Origin, authentication, Unicode, maximum text, motion flood, repeated episode commands, immediate pause/resume, disconnect all (including idle sockets), retained pairing, revocation, graceful shutdown.")
    }
}
