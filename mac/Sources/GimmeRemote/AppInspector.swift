import AppKit
@preconcurrency import ApplicationServices
import RemoteCore

@MainActor
enum AppInspector {
    static var notifiedLocked = false
    static var isLocked: Bool {
        if notifiedLocked { return true }
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return true }
        return (session["CGSSessionScreenIsLocked"] as? Bool == true)
            || (session[kCGSessionOnConsoleKey as String] as? Bool == false)
            || NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.loginwindow"
    }
    static func state(paused: Bool) -> RemoteState {
        let app = NSWorkspace.shared.frontmostApplication
        let id = app?.bundleIdentifier ?? ""
        return .init(appName: app?.localizedName ?? "Mac", bundleId: id,
                     layout: KeyMapping.layout(bundleId: id), locked: isLocked,
                     accessibility: AXIsProcessTrusted(), paused: paused)
    }
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
