import Foundation

public struct Message: Codable, Sendable {
    public let version: Int
    public let type: String
    public let requestId: String?
    public let payload: Payload

    public init(type: String, requestId: String? = nil, payload: Payload = .init()) {
        self.version = 1
        self.type = type
        self.requestId = requestId
        self.payload = payload
    }

    public static func decode(_ text: String) throws -> Message {
        guard text.utf8.count <= 32_768 else { throw ControlError("messageTooLarge") }
        guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              Set(object.keys).isSubset(of: ["version", "type", "requestId", "payload"]),
              let payload = object["payload"] as? [String: Any],
              let type = object["type"] as? String else { throw ControlError("invalidPayload") }
        let allowedPayload: Set<String>
        switch type {
        case "session.pair": allowedPayload = ["code", "deviceName"]
        case "session.authenticate": allowedPayload = ["token"]
        case "input.pointer.move", "input.pointer.scroll": allowedPayload = ["dx", "dy"]
        case "input.pointer.click": allowedPayload = ["button"]
        case "input.pointer.drag": allowedPayload = ["phase"]
        case "input.text.insert": allowedPayload = ["text"]
        case "input.keyboard.shortcut", "media.command": allowedPayload = ["action"]
        default: allowedPayload = []
        }
        guard Set(payload.keys).isSubset(of: allowedPayload) else { throw ControlError("invalidPayload") }
        let message = try JSONDecoder().decode(Self.self, from: Data(text.utf8))
        guard message.version == 1 else { throw ControlError("protocolVersion") }
        guard (message.requestId?.utf8.count ?? 0) <= 128 else { throw ControlError("invalidPayload") }
        try message.validate()
        return message
    }

    public func json() -> String {
        // All server payloads contain finite, bounded values.
        String(decoding: try! JSONEncoder().encode(self), as: UTF8.self)
    }

    public func validate() throws {
        func bounded(_ value: Double?, _ limit: Double) -> Bool {
            guard let value else { return false }
            return value.isFinite && abs(value) <= limit
        }
        let valid: Bool
        switch type {
        case "session.pair":
            valid = payload.code?.utf8.count == 6 && payload.code?.utf8.allSatisfy { (48...57).contains($0) } == true
                && (payload.deviceName?.utf8.count ?? 0) <= 80
        case "session.authenticate":
            valid = payload.token?.utf8.count == 64 && payload.token?.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } == true
        case "session.heartbeat", "session.disconnect":
            valid = true
        case "input.pointer.move", "input.pointer.scroll":
            valid = bounded(payload.dx, 500) && bounded(payload.dy, 500)
        case "input.pointer.click":
            valid = ["left", "right"].contains(payload.button ?? "")
        case "input.pointer.drag":
            valid = ["start", "end"].contains(payload.phase ?? "")
        case "input.text.insert":
            valid = !(payload.text ?? "").isEmpty && (payload.text?.utf8.count ?? 0) <= 8_192
        case "input.keyboard.shortcut":
            valid = Self.shortcuts.contains(payload.action ?? "")
        case "media.command":
            valid = Self.mediaActions.contains(payload.action ?? "")
        default:
            throw ControlError("unsupportedMessage")
        }
        guard valid else { throw ControlError("invalidPayload") }
    }

    public static let shortcuts: Set<String> = [
        "escape", "back", "forward", "reload", "address", "nextTab", "previousTab", "switchApp", "enter",
    ]
    public static let mediaActions: Set<String> = [
        "playPause", "seekForward", "seekBackward", "volumeUp", "volumeDown", "mute", "fullscreen",
    ]
}

public struct Payload: Codable, Sendable {
    public var code: String?
    public var deviceName: String?
    public var token: String?
    public var dx: Double?
    public var dy: Double?
    public var button: String?
    public var phase: String?
    public var text: String?
    public var action: String?
    public var state: RemoteState?
    public var error: String?
    public var expiresAt: Double?
    public init() {}
}

public struct RemoteState: Codable, Sendable, Equatable {
    public var appName: String
    public var bundleId: String
    public var layout: String
    public var locked: Bool
    public var accessibility: Bool
    public var paused: Bool
    public var captureAvailable: Bool = false
    public init(appName: String, bundleId: String, layout: String, locked: Bool, accessibility: Bool, paused: Bool) {
        self.appName = appName
        self.bundleId = bundleId
        self.layout = layout
        self.locked = locked
        self.accessibility = accessibility
        self.paused = paused
    }
}

public struct ControlError: Error, Sendable {
    public let code: String
    public init(_ code: String) { self.code = code }
}

/// A monotonic-time token bucket; caller owns synchronization.
public struct RateLimiter: Sendable {
    private let capacity: Double
    private let refill: Double
    private var tokens: Double
    private var last: TimeInterval
    public init(capacity: Int, perSecond: Double, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.capacity = Double(capacity)
        self.refill = perSecond
        self.tokens = Double(capacity)
        self.last = now
    }
    public mutating func allow(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        tokens = min(capacity, tokens + max(0, now - last) * refill)
        last = max(last, now)
        guard tokens >= 1 else { return false }
        tokens -= 1
        return true
    }
}

public enum OriginPolicy {
    /// Never trust arbitrary Host headers: both Host and Origin must be allowlisted.
    public static func permits(origin: String?, host: String?, allowed: Set<String>, development: Set<String> = []) -> Bool {
        guard let host, allowed.contains("http://\(host.lowercased())"),
              let origin, let url = URLComponents(string: origin),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty, url.scheme == "http", url.host != nil else { return false }
        let normalized = origin.lowercased()
        return allowed.contains(normalized) || development.contains(normalized)
    }
}
