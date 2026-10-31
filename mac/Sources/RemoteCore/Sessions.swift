import Foundation
import Security

public protocol TokenVault: Sendable {
    func load() throws -> [String: String]
    func save(_ devices: [String: String]) throws
}

public struct KeychainVault: TokenVault {
    public init() {}
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.lucientong.GimmeRemote.devices",
         kSecAttrAccount as String: "paired-devices"]
    }
    public func load() throws -> [String: String] {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess, let data = result as? Data else { throw ControlError("keychainUnavailable") }
        return try JSONDecoder().decode([String: String].self, from: data)
    }
    public func save(_ devices: [String: String]) throws {
        let data = try JSONEncoder().encode(devices)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw ControlError("keychainUnavailable") }
        } else if status != errSecSuccess {
            throw ControlError("keychainUnavailable")
        }
    }
}

public struct PairingCode: Sendable {
    public let code: String
    public let expires: Date
}

public actor Sessions {
    private let vault: any TokenVault
    private var devices: [String: String]
    private var pairing: PairingCode?
    private var connections: Set<UUID> = []
    private var authenticated: [UUID: String] = [:]
    private var activity: [UUID: TimeInterval] = [:]
    private var pairLimit = RateLimiter(capacity: 5, perSecond: 1.0 / 12)
    private var connectLimit = RateLimiter(capacity: 20, perSecond: 2)
    private var epoch = 0
    private var unreadable = false

    public init(vault: any TokenVault = KeychainVault()) throws {
        self.vault = vault
        self.devices = try vault.load()
    }

    /// Starts without paired devices when the vault cannot be read (locked or denied Keychain),
    /// so the App stays usable and phones can pair again instead of the App quitting.
    public init(recovering vault: any TokenVault) {
        self.vault = vault
        do { self.devices = try vault.load() } catch { self.devices = [:]; self.unreadable = true }
    }

    public func vaultUnreadable() -> Bool { unreadable }

    /// Re-reads an unreadable vault, e.g. after the Keychain is unlocked. Callers should only
    /// retry on user presence, because a denied Keychain may prompt again on every read.
    @discardableResult
    public func retryVault() -> Bool {
        guard unreadable, let stored = try? vault.load() else { return false }
        devices = stored
        unreadable = false
        return true
    }

    public func newCode(now: Date = Date()) throws -> PairingCode {
        let random = try Self.randomBytes(count: 4)
        let number = random.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } % 1_000_000
        let code = PairingCode(code: String(format: "%06u", number), expires: now.addingTimeInterval(120))
        pairing = code
        return code
    }

    public func currentCode(now: Date = Date()) -> PairingCode? {
        guard let pairing, pairing.expires > now else { return nil }
        return pairing
    }

    public func open(_ id: UUID) throws -> Int {
        guard connections.count < 16, connectLimit.allow() else { throw ControlError("rateLimited") }
        connections.insert(id)
        activity[id] = ProcessInfo.processInfo.systemUptime
        return epoch
    }

    public func close(_ id: UUID) {
        connections.remove(id)
        authenticated[id] = nil
        activity[id] = nil
    }

    public func touch(_ id: UUID) { activity[id] = ProcessInfo.processInfo.systemUptime }
    public func isIdle(_ id: UUID, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard let last = activity[id] else { return true }
        return now - last > 12
    }

    public func pair(_ id: UUID, code: String, name: String, now: Date = Date()) throws -> String {
        guard connections.contains(id) else { throw ControlError("unauthorized") }
        guard pairLimit.allow() else { throw ControlError("rateLimited") }
        guard let pairing, pairing.expires > now, pairing.code == code else { throw ControlError("invalidPairingCode") }
        guard devices.count < 32 else { throw ControlError("deviceLimit") }
        // Pairing is deliberate, so retry an unreadable vault here rather than on every reconnect.
        retryVault()
        let token = try Self.randomBytes(count: 32).map { String(format: "%02x", $0) }.joined()
        var next = devices
        next[token] = name.isEmpty ? "iPhone" : name
        try vault.save(next)
        devices = next
        unreadable = false
        self.pairing = nil
        authenticated[id] = token
        return token
    }

    public func authenticate(_ id: UUID, token: String) throws {
        guard connections.contains(id), devices[token] != nil else { throw ControlError("unauthorized") }
        authenticated[id] = token
    }

    public func isAuthenticated(_ id: UUID) -> Bool {
        guard let token = authenticated[id] else { return false }
        return devices[token] != nil
    }
    public func isCurrent(_ generation: Int) -> Bool { generation == epoch }
    public func activeCount() -> Int { authenticated.count }
    public func pairedCount() -> Int { devices.count }

    public func disconnectAll() { epoch += 1; authenticated.removeAll() }
    public func revokeAll() throws {
        try vault.save([:])
        devices = [:]
        unreadable = false
        pairing = nil
        disconnectAll()
    }

    private static func randomBytes(count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw ControlError("randomUnavailable") }
        return bytes
    }
}
