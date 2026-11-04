import Foundation

struct CheckVault: TokenVault {
    func load() throws -> [String: String] { [:] }
    func save(_ devices: [String: String]) throws {}
}
struct BrokenVault: TokenVault {
    func load() throws -> [String: String] { [:] }
    func save(_ devices: [String: String]) throws { throw ControlError("keychainUnavailable") }
}
struct LockedVault: TokenVault {
    func load() throws -> [String: String] { throw ControlError("keychainUnavailable") }
    func save(_ devices: [String: String]) throws {}
}

/// Locked at launch, unlocked later with a device paired before.
final class UnlockingVault: TokenVault, @unchecked Sendable {
    var locked = true
    func load() throws -> [String: String] {
        if locked { throw ControlError("keychainUnavailable") }
        return ["old-token": "iPhone"]
    }
    func save(_ devices: [String: String]) throws {}
}

@main
struct CoreChecks {
    static func reject(_ body: () throws -> Void) throws {
        do { try body() } catch { return }
        throw ControlError("Expected validation to fail")
    }
    static func main() async throws {
        for text in [
            #"{"version":2,"type":"session.heartbeat","payload":{}}"#,
            #"{"version":1,"type":"shell.exec","payload":{}}"#,
            #"{"version":1,"type":"input.pointer.move","payload":{"dx":501,"dy":0}}"#,
            #"{"version":1,"type":"input.keyboard.shortcut","payload":{"action":"shell"}}"#,
        ] { try reject { _ = try Message.decode(text) } }
        let text = try Message.decode(#"{"version":1,"type":"input.text.insert","payload":{"text":"流浪地球 🌏"}}"#)
        precondition(text.payload.text == "流浪地球 🌏")
        let allowed: Set<String> = ["http://mac.local:9271"]
        precondition(OriginPolicy.permits(origin: "http://mac.local:9271", host: "mac.local:9271", allowed: allowed))
        precondition(!OriginPolicy.permits(origin: "http://evil.local", host: "mac.local:9271", allowed: allowed))
        precondition(!OriginPolicy.permits(origin: nil, host: "mac.local:9271", allowed: allowed))
        var limiter = RateLimiter(capacity: 2, perSecond: 1, now: 0)
        precondition(limiter.allow(now: 0) && limiter.allow(now: 0) && !limiter.allow(now: 0))
        precondition(limiter.allow(now: 1))
        let sessions = try Sessions(vault: CheckVault()), id = UUID()
        let generation = try await sessions.open(id)
        let code = try await sessions.newCode()
        let token = try await sessions.pair(id, code: code.code, name: "Phone")
        precondition(token.count == 64)
        let authenticated = await sessions.isAuthenticated(id)
        precondition(authenticated)
        do { _ = try await sessions.pair(id, code: code.code, name: "Phone"); throw ControlError("Code reused") }
        catch let error as ControlError { precondition(error.code == "invalidPairingCode") }
        try await sessions.revokeAll()
        let revoked = await sessions.isAuthenticated(id), current = await sessions.isCurrent(generation)
        precondition(!revoked && !current)
        let idle = UUID(), settingUp = UUID()
        let idleGeneration = try await sessions.open(idle)
        _ = try await sessions.open(settingUp)
        let events = await sessions.events(for: idle, generation: idleGeneration)
        await sessions.stateChanged()
        await sessions.disconnectAll()
        var iterator = events.makeAsyncIterator()
        guard case .disconnected? = await iterator.next() else { throw ControlError("Disconnect event lost") }
        let finished = await iterator.next()
        precondition(finished == nil)
        let lateEvents = await sessions.events(for: settingUp, generation: idleGeneration)
        var late = lateEvents.makeAsyncIterator()
        guard case .disconnected? = await late.next() else { throw ControlError("Setup disconnect race lost") }
        let lateFinished = await late.next()
        precondition(lateFinished == nil)
        for _ in 0..<16 { _ = try await sessions.open(UUID()) }
        let failed = try Sessions(vault: BrokenVault())
        _ = try await failed.open(id)
        let fresh = try await failed.newCode()
        do { _ = try await failed.pair(id, code: fresh.code, name: "Phone"); throw ControlError("Persistence bypass") }
        catch let error as ControlError { precondition(error.code == "keychainUnavailable") }
        let bypassed = await failed.isAuthenticated(id)
        precondition(!bypassed)
        let recovering = Sessions(recovering: LockedVault())
        let unreadable = await recovering.vaultUnreadable(), empty = await recovering.pairedCount() == 0
        precondition(unreadable && empty)
        _ = try await recovering.open(id)
        let retry = try await recovering.newCode()
        _ = try await recovering.pair(id, code: retry.code, name: "Phone")
        let recovered = await recovering.isAuthenticated(id)
        precondition(recovered)
        let unlocking = UnlockingVault(), restoring = Sessions(recovering: unlocking)
        let stillLocked = await restoring.retryVault()
        unlocking.locked = false
        let restored = await restoring.retryVault(), oldDevice = await restoring.pairedCount() == 1
        let readable = !(await restoring.vaultUnreadable())
        precondition(!stillLocked && restored && oldDevice && readable)
        let address = try KeyMapping.shortcut("address")
        let volume = try KeyMapping.media("volumeUp", iina: true)
        let nextTab = try KeyMapping.shortcut("nextTab"), previousTab = try KeyMapping.shortcut("previousTab")
        precondition(address == .init(37, command: true))
        precondition(volume.key == 126)
        precondition(nextTab == .init(48, control: true) && previousTab == .init(48, shift: true, control: true))
        let historyForward = try KeyMapping.shortcut("forward"), historyBack = try KeyMapping.shortcut("back")
        let seekForward = try KeyMapping.media("seekForward", iina: false)
        let seekBackward = try KeyMapping.media("seekBackward", iina: false)
        precondition(historyForward == .init(30, command: true) && historyBack == .init(33, command: true))
        precondition(seekForward == .init(124) && seekBackward == .init(123))
        for action in ["previousEpisode", "nextEpisode"] {
            try reject { _ = try KeyMapping.media(action, iina: true) }
            try reject { _ = try KeyMapping.media(action, iina: false) }
            var payload = Payload(); payload.action = action
            let decoded = try Message.decode(Message(type: "media.command", payload: payload).json())
            precondition(decoded.payload.action == action)
        }
        checkBrowserPlayers()
        precondition(KeyMapping.layout(bundleId: "com.google.Chrome.canary") == "browser"
            && KeyMapping.layout(bundleId: "com.brave.Browser") == "browser"
            && KeyMapping.layout(bundleId: "com.apple.finder") == "generic")
        var clicks = ClickCounter()
        precondition(clicks.register(button: "left", at: .zero, time: 1, interval: 0.5) == 1)
        precondition(clicks.register(button: "left", at: CGPoint(x: 2, y: 2), time: 1.3, interval: 0.5) == 2)
        precondition(clicks.register(button: "left", at: CGPoint(x: 2, y: 2), time: 2, interval: 0.5) == 1)
        var scroll = ScrollAccumulator(), scrolled: Int32 = 0
        for _ in 0..<10 { scrolled += scroll.add(dx: 0, dy: -0.25).dy }
        precondition(scrolled == -2)
        print("Core checks passed: protocol, Unicode, Origin, rate limit, one-time pairing, revocation, persistence failure, unreadable Keychain recovery, Keychain unlock restore, shortcuts, layouts, double-click, slow scroll.")
    }
}

private func checkBrowserPlayers() {
    func button(_ label: String, x: Double, parent: Int = 1, enabled: Bool = true) -> PlayerNode {
        .init(parent: parent, role: "AXButton", labels: [label],
              frame: CGRect(x: x, y: 500, width: 36, height: 24), enabled: enabled, pressable: true)
    }
    let root = PlayerNode(parent: nil, role: "AXWebArea")
    let group = PlayerNode(parent: 0)
    let single = [root, group, button("播放/暂停", x: 100), button("全屏", x: 700)]
    precondition(BrowserPlayerDetection.select(single) == nil)
    let series = single + [button("上一个", x: 64, enabled: false), button("下一个", x: 136)]
    precondition(BrowserPlayerDetection.select(series)?.controls(in: series) == .init(previous: false, next: true))
    let onlyNext = single + [button("Next video (Shift+N)", x: 136)]
    precondition(BrowserPlayerDetection.select(onlyNext)?.controls(in: onlyNext) == .init(next: true))
    var hidden = onlyNext
    hidden[4].visible = false
    precondition(BrowserPlayerDetection.select(hidden) == nil)
    var footer = onlyNext
    footer[4].parent = 0
    precondition(BrowserPlayerDetection.select(footer) == nil)
    var distant = onlyNext
    distant[4].frame.origin.y = 1000
    precondition(BrowserPlayerDetection.select(distant) == nil)
    var unlabelled = onlyNext
    unlabelled[4].labels = []
    precondition(BrowserPlayerDetection.select(unlabelled) == nil)
    let seeking = single + [button("Seek forward", x: 136), button("Back", x: 64)]
    precondition(BrowserPlayerDetection.select(seeking) == nil)
    let ambiguous = series + [button("下一集", x: 172)]
    precondition(BrowserPlayerDetection.select(ambiguous) == nil)
    let multiple = series + [PlayerNode(parent: 0), button("Play", x: 100, parent: 6),
                             button("Fullscreen", x: 700, parent: 6), button("Next", x: 136, parent: 6)]
    precondition(BrowserPlayerDetection.select(multiple) == nil)
    let flat = [root, button("Play", x: 100, parent: 0), button("Fullscreen", x: 700, parent: 0),
                button("Volume", x: 500, parent: 0), button("Next", x: 136, parent: 0)]
    precondition(BrowserPlayerDetection.select(flat)?.controls(in: flat) == .init(next: true))
    var fakeFlat = flat
    fakeFlat[3].frame.origin.y = 1000
    precondition(BrowserPlayerDetection.select(fakeFlat) == nil)
    for (previous, next, play, supporting) in [
        ("Previous episode", "Next episode", "Pause", "Mute"),
        ("前の動画", "次の動画", "再生", "フルスクリーン"),
        ("이전", "다음", "재생", "음소거"),
    ] {
        let nodes = [root, group, button(play, x: 100), button(supporting, x: 700),
                     button(previous, x: 64), button(next, x: 136)]
        precondition(BrowserPlayerDetection.select(nodes)?.controls(in: nodes) == .init(previous: true, next: true))
    }
    // Added capabilities are optional on the wire, so old Mac state remains decodable.
    let legacy = #"{"appName":"Chrome","bundleId":"com.google.Chrome","layout":"browser","locked":false,"accessibility":true,"paused":false,"captureAvailable":false}"#
    let state = try! JSONDecoder().decode(RemoteState.self, from: Data(legacy.utf8))
    precondition(state.episodeControls == nil)
    print("Browser player checks passed: single/series, boundaries, one-sided, hidden, pagination, seeking, ambiguity, four languages, legacy state.")
}
