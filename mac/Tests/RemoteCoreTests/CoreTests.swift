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
    #expect(limiter.allow(now: 10))
    #expect(limiter.allow(now: 10))
    #expect(!limiter.allow(now: 10))
    #expect(limiter.allow(now: 11))
    #expect(!limiter.allow(now: 10))
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

@Test func adaptersUsePlayerVolumeAndBrowserNavigation() throws {
    #expect(try KeyMapping.media("volumeUp", iina: true).key == 126)
    #expect(try KeyMapping.shortcut("address") == KeyStroke(37, command: true))
    #expect(KeyMapping.layout(bundleId: "com.colliderli.iina") == "iina")
    #expect(KeyMapping.layout(bundleId: "com.apple.Safari") == "browser")
}
