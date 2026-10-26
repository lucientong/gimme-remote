import Foundation

public struct KeyStroke: Sendable, Equatable {
    public let key: UInt16
    public let command: Bool
    public let option: Bool
    public let shift: Bool
    public init(_ key: UInt16, command: Bool = false, option: Bool = false, shift: Bool = false) {
        self.key = key; self.command = command; self.option = option; self.shift = shift
    }
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
        case "nextTab": return .init(124, command: true, option: true)
        case "previousTab": return .init(123, command: true, option: true)
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
