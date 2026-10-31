import Foundation
import CoreGraphics

public struct KeyStroke: Sendable, Equatable {
    public let key: UInt16
    public let command: Bool
    public let option: Bool
    public let shift: Bool
    public let control: Bool
    public init(_ key: UInt16, command: Bool = false, option: Bool = false, shift: Bool = false, control: Bool = false) {
        self.key = key; self.command = command; self.option = option; self.shift = shift; self.control = control
    }
}

/// Counts rapid clicks near one spot so synthetic taps can double-click.
public struct ClickCounter: Sendable {
    private var button = ""
    private var time = -Double.infinity
    private var location = CGPoint.zero
    private var count = 0
    public init() {}
    public mutating func register(button: String, at location: CGPoint, time: TimeInterval,
                                  interval: TimeInterval, tolerance: Double = 16) -> Int {
        let nearby = hypot(location.x - self.location.x, location.y - self.location.y) <= tolerance
        count = button == self.button && time - self.time <= interval && nearby ? count + 1 : 1
        self.button = button; self.time = time; self.location = location
        return count
    }
    public mutating func reset() { count = 0; time = -.infinity }
}

/// Keeps sub-pixel scroll remainders so slow two-finger scrolling is not truncated to zero.
public struct ScrollAccumulator: Sendable {
    private var x = 0.0
    private var y = 0.0
    public init() {}
    public mutating func add(dx: Double, dy: Double) -> (dx: Int32, dy: Int32) {
        x += dx; y += dy
        let wholeX = x.rounded(.towardZero), wholeY = y.rounded(.towardZero)
        x -= wholeX; y -= wholeY
        return (Int32(wholeX), Int32(wholeY))
    }
    public mutating func reset() { x = 0; y = 0 }
}

public enum KeyMapping {
    public static func media(_ action: String, iina: Bool) throws -> KeyStroke {
        switch action {
        case "playPause": return .init(49)
        case "seekForward": return .init(124)
        case "seekBackward": return .init(123)
        case "volumeUp": return .init(126)
        case "volumeDown": return .init(125)
        case "mute": return .init(46)
        // IINA's default fullscreen shortcut is F; browsers commonly use F too.
        case "fullscreen": return .init(3)
        default: throw ControlError("unsupportedMessage")
        }
    }
    public static func shortcut(_ action: String) throws -> KeyStroke {
        switch action {
        case "escape": return .init(53)
        case "enter": return .init(36)
        case "back": return .init(33, command: true)
        case "forward": return .init(30, command: true)
        case "reload": return .init(15, command: true)
        case "address": return .init(37, command: true)
        // Control-Tab works in Safari, Chrome, Firefox, Edge and Arc.
        case "nextTab": return .init(48, control: true)
        case "previousTab": return .init(48, shift: true, control: true)
        case "switchApp": return .init(48, command: true)
        default: throw ControlError("unsupportedMessage")
        }
    }
    public static func layout(bundleId: String) -> String {
        if bundleId == "com.colliderli.iina" { return "iina" }
        if ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.edgemac", "company.thebrowser.Browser"].contains(bundleId) {
            return "browser"
        }
        return "generic"
    }
}
