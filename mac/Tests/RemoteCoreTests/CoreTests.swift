import Testing
import Foundation
@testable import RemoteCore

struct MemoryVault: TokenVault {
    func load() throws -> [String: String] { [:] }
    func save(_ devices: [String: String]) throws {}
}
struct FailingVault: TokenVault {
    func load() throws -> [String: String] { [:] }
    func save(_ devices: [String: String]) throws { throw ControlError("keychainUnavailable") }
}
struct UnreadableVault: TokenVault {
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

@Test func protocolRejectsUnsafeInput() throws {
    for text in [
        #"{"version":2,"type":"session.heartbeat","payload":{}}"#,
        #"{"version":1,"type":"shell.exec","payload":{"text":"whoami"}}"#,
        #"{"version":1,"type":"input.pointer.move","payload":{"dx":999999,"dy":0}}"#,
        #"{"version":1,"type":"input.keyboard.shortcut","payload":{"action":"arbitrary"}}"#,
        #"{"version":1,"type":"input.text.insert","payload":{"text":""}}"#,
    ] {
        #expect(throws: (any Error).self) { try Message.decode(text) }
    }
    let text = try Message.decode(#"{"version":1,"type":"input.text.insert","requestId":"a","payload":{"text":"流浪地球 🌏"}}"#)
    #expect(text.payload.text == "流浪地球 🌏")
    #expect(throws: (any Error).self) { try Message.decode(String(repeating: "a", count: 33_000)) }
}

@Test func originRequiresKnownHostAndOrigin() {
    let allowed: Set<String> = ["http://mac.local:9271", "http://192.168.1.2:9271"]
    #expect(OriginPolicy.permits(origin: "http://mac.local:9271", host: "mac.local:9271", allowed: allowed))
    #expect(!OriginPolicy.permits(origin: "http://evil.local", host: "mac.local:9271", allowed: allowed))
    #expect(!OriginPolicy.permits(origin: "http://evil.local:9271", host: "evil.local:9271", allowed: allowed))
    #expect(!OriginPolicy.permits(origin: nil, host: "mac.local:9271", allowed: allowed))
    #expect(!OriginPolicy.permits(origin: "null", host: "mac.local:9271", allowed: allowed))
    #expect(!OriginPolicy.permits(origin: "http://user@mac.local:9271", host: "mac.local:9271", allowed: allowed))
}

@Test func rateLimitRefillsWithoutClockRollback() {
    var limiter = RateLimiter(capacity: 2, perSecond: 1, now: 10)
    let first = limiter.allow(now: 10)
    let second = limiter.allow(now: 10)
    let exhausted = limiter.allow(now: 10)
    let refilled = limiter.allow(now: 11)
    let rolledBack = limiter.allow(now: 10)
    #expect(first)
    #expect(second)
    #expect(!exhausted)
    #expect(refilled)
    #expect(!rolledBack)
}

@Test func pairingIsOneTimeAndRevocable() async throws {
    let sessions = try Sessions(vault: MemoryVault())
    let id = UUID()
    let generation = try await sessions.open(id)
    let code = try await sessions.newCode()
    #expect(throws: (any Error).self) { try Message.decode(#"{"version":1,"type":"session.pair","payload":{"code":"oops"}}"#) }
    let token = try await sessions.pair(id, code: code.code, name: "iPhone")
    #expect(token.count == 64)
    #expect(await sessions.isAuthenticated(id))
    do { _ = try await sessions.pair(id, code: code.code, name: "again"); Issue.record("Code reused") } catch {}
    await sessions.close(id)
    let next = UUID()
    _ = try await sessions.open(next)
    try await sessions.authenticate(next, token: token)
    #expect(await sessions.isAuthenticated(next))
    try await sessions.revokeAll()
    #expect(!(await sessions.isAuthenticated(next)))
    #expect(!(await sessions.isCurrent(generation)))
    do { try await sessions.authenticate(next, token: token); Issue.record("Revoked token accepted") } catch {}
}

@Test func expiredPairingAndFailedPersistenceCannotAuthenticate() async throws {
    let sessions = try Sessions(vault: MemoryVault())
    let id = UUID()
    _ = try await sessions.open(id)
    let time = Date(timeIntervalSince1970: 1000)
    let code = try await sessions.newCode(now: time)
    do { _ = try await sessions.pair(id, code: code.code, name: "phone", now: time.addingTimeInterval(121)); Issue.record("Expired code accepted") } catch {}
    #expect(!(await sessions.isAuthenticated(id)))
    let failing = try Sessions(vault: FailingVault())
    _ = try await failing.open(id)
    let fresh = try await failing.newCode()
    do { _ = try await failing.pair(id, code: fresh.code, name: "phone"); Issue.record("Failed persistence accepted") } catch {}
    #expect(!(await failing.isAuthenticated(id)))
}

@Test func unreadableVaultStartsEmptyAndCanPairAgain() async throws {
    #expect(throws: (any Error).self) { try Sessions(vault: UnreadableVault()) }
    let sessions = Sessions(recovering: UnreadableVault())
    #expect(await sessions.vaultUnreadable())
    #expect(await sessions.pairedCount() == 0)
    let id = UUID()
    _ = try await sessions.open(id)
    let code = try await sessions.newCode()
    _ = try await sessions.pair(id, code: code.code, name: "iPhone")
    #expect(await sessions.isAuthenticated(id))
    #expect(!(await sessions.vaultUnreadable()))
}

@Test func unlockedVaultRestoresDevicesPairedBefore() async throws {
    let vault = UnlockingVault()
    let sessions = Sessions(recovering: vault)
    #expect(!(await sessions.retryVault()))
    vault.locked = false
    #expect(await sessions.retryVault())
    #expect(await sessions.pairedCount() == 1)
    #expect(!(await sessions.vaultUnreadable()))
    let id = UUID()
    _ = try await sessions.open(id)
    try await sessions.authenticate(id, token: "old-token")
    #expect(await sessions.isAuthenticated(id))
}

@Test func adaptersUsePlayerVolumeAndBrowserNavigation() throws {
    #expect(try KeyMapping.media("volumeUp", iina: true).key == 126)
    #expect(try KeyMapping.shortcut("address") == KeyStroke(37, command: true))
    #expect(try KeyMapping.shortcut("nextTab") == KeyStroke(48, control: true))
    #expect(try KeyMapping.shortcut("previousTab") == KeyStroke(48, shift: true, control: true))
    #expect(KeyMapping.layout(bundleId: "com.colliderli.iina") == "iina")
    #expect(KeyMapping.layout(bundleId: "com.apple.Safari") == "browser")
}

@Test func consecutiveNearbyTapsBecomeDoubleClicks() {
    var clicks = ClickCounter()
    let first = clicks.register(button: "left", at: .zero, time: 1, interval: 0.5)
    let second = clicks.register(button: "left", at: CGPoint(x: 3, y: 2), time: 1.3, interval: 0.5)
    let slow = clicks.register(button: "left", at: CGPoint(x: 3, y: 2), time: 2, interval: 0.5)
    let moved = clicks.register(button: "left", at: CGPoint(x: 300, y: 2), time: 2.1, interval: 0.5)
    let other = clicks.register(button: "right", at: CGPoint(x: 300, y: 2), time: 2.2, interval: 0.5)
    #expect([first, second, slow, moved, other] == [1, 2, 1, 1, 1])
}

@Test func slowScrollKeepsFractionalRemainder() {
    var scroll = ScrollAccumulator()
    var total: Int32 = 0
    for _ in 0..<10 { total += scroll.add(dx: 0, dy: -0.25).dy }
    #expect(total == -2)
    let whole = scroll.add(dx: 2.5, dy: 0)
    #expect(whole.dx == 2)
}
