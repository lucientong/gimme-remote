import Foundation

struct CheckVault: TokenVault {
    func load() throws -> [String: String] { [:] }
    func save(_ devices: [String: String]) throws {}
}
struct BrokenVault: TokenVault {
    func load() throws -> [String: String] { [:] }
    func save(_ devices: [String: String]) throws { throw ControlError("keychainUnavailable") }
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
        let failed = try Sessions(vault: BrokenVault())
        _ = try await failed.open(id)
        let fresh = try await failed.newCode()
        do { _ = try await failed.pair(id, code: fresh.code, name: "Phone"); throw ControlError("Persistence bypass") }
        catch let error as ControlError { precondition(error.code == "keychainUnavailable") }
        let bypassed = await failed.isAuthenticated(id)
        precondition(!bypassed)
        let address = try KeyMapping.shortcut("address")
        let volume = try KeyMapping.media("volumeUp", iina: true)
        precondition(address == .init(37, command: true))
        precondition(volume.key == 126)
        print("Core checks passed: protocol, Unicode, Origin, rate limit, one-time pairing, revocation, persistence failure, shortcuts.")
    }
}
