import AppKit
import Combine
import SwiftUI

// Only services are stubbed. The view compiled alongside this file is the production MenuPanel.
@MainActor
final class AppModel: ObservableObject {
    @Published var url = "http://panel-check.local:9271"
    @Published var addresses = ["http://panel-check.local:9271"]
    @Published var code = "123456"
    @Published var connected = 0
    @Published var paired = 0
    @Published var trusted = true
    @Published var locked = false
    @Published var running = true
    @Published var failure: String?
    @Published var vaultUnreadable = false
    @Published var paused = false
    @Published var preventSleep = false
    @Published var loginEnabled = false
    var pairURL: String { "\(url)/#code=\(code)" }
    func refreshCode() async {}
    func retryVault() async {}
    func setPaused(_ value: Bool) async { paused = value }
    func revoke() async {}
    func disconnect() async {}
    func setLogin(_ value: Bool) {}
}

enum AppInspector {
    static func requestAccessibility() {}
}

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@MainActor
private final class PanelChecks: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let popover = NSPopover()
    private var anchor: NSWindow!
    private var host: NSHostingController<MenuPanel>!
    private let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["GIMME_PANEL_CHECK_OUTPUT"]!)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        anchor = NSWindow(contentRect: NSRect(x: screen.midX, y: screen.maxY - 24, width: 40, height: 22),
                          styleMask: .borderless, backing: .buffered, defer: false)
        anchor.level = .statusBar
        anchor.orderFrontRegardless()
        host = NSHostingController(rootView: MenuPanel(model: model, maximumHeight: 900))
        host.sizingOptions = .preferredContentSize
        popover.behavior = .applicationDefined
        popover.contentViewController = host
        show()
        // A missing GUI session or a layout deadlock must fail the check instead of hanging CI.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            print("FAIL: menu panel checks exceeded 30 seconds")
            exit(1)
        }
        Task {
            do {
                try await runChecks()
                print("Menu panel checks passed")
                exit(0)
            } catch {
                try? capture("failure")
                print("FAIL: \(error)")
                exit(1)
            }
        }
    }

    private func show() {
        popover.show(relativeTo: anchor.contentView!.bounds, of: anchor.contentView!, preferredEdge: .minY)
    }

    private func runChecks() async throws {
        print("System: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let expanded = try await check("pairing-expanded", height: 500...900)
        model.trusted = false
        let untrusted = try await check("permission-guide", height: (expanded + 80)...900)
        guard untrusted > expanded else { throw CheckFailure("Permission guide did not increase content height") }
        model.trusted = true
        model.paired = 1
        let collapsed = try await check("pairing-collapsed", height: 200...(expanded - 100))
        // Drive the observed state on the same host to catch stale or one-shot height measurements.
        model.paired = 0
        _ = try await check("pairing-expanded-again", height: (collapsed + 100)...900)
        model.code = ""
        _ = try await check("pairing-expired", height: 200...(expanded - 100))
        model.code = "123456"
        _ = try await check("pairing-renewed", height: (collapsed + 100)...900)
        model.paired = 1
        model.vaultUnreadable = true
        _ = try await check("keychain-warning", height: (collapsed + 50)...900)
        model.vaultUnreadable = false
        NSApp.appearance = NSAppearance(named: .darkAqua)
        _ = try await check("dark-collapsed", height: (collapsed - 2)...(collapsed + 2))
        NSApp.appearance = NSAppearance(named: .aqua)
        _ = try await check("light-collapsed", height: (collapsed - 2)...(collapsed + 2))

        host.rootView = MenuPanel(model: model, maximumHeight: 300)
        model.trusted = false
        model.paired = 0
        _ = try await check("height-limited", height: 299...301)
        try await checkScrolling()
        popover.performClose(nil)
        show()
        _ = try await check("reopened", height: 299...301)
    }

    private func check(_ name: String, height: ClosedRange<CGFloat>) async throws -> CGFloat {
        let deadline = Date().addingTimeInterval(5)
        var stable = 0
        var previous: CGFloat = -1
        while Date() < deadline {
            let size = popover.contentSize
            // The historical bug left a correctly sized popover shell with a zero-height SwiftUI container.
            let hasContent = host.view.subviews.contains { !$0.isHidden && $0.bounds.width > 0 && $0.bounds.height > 1 }
            if hasContent, abs(size.width - 340) < 2, height.contains(size.height), abs(size.height - previous) < 0.5 {
                stable += 1
            } else { stable = 0 }
            previous = size.height
            if stable >= 3 {
                try capture(name)
                print("PASS: \(name), \(size.width) x \(size.height)")
                return size.height
            }
            try await Task.sleep(for: .milliseconds(80))
        }
        throw CheckFailure("\(name): expected height \(height), got \(popover.contentSize); subviews: \(host.view.subviews.map { "\($0.frame)" })")
    }

    private func checkScrolling() async throws {
        func find(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            for child in view.subviews {
                if let scroll = find(child) { return scroll }
            }
            return nil
        }
        guard let scroll = find(host.view), let document = scroll.documentView,
              document.bounds.height > scroll.contentView.bounds.height else {
            throw CheckFailure("Limited panel has no overflowing scroll document")
        }
        let bottom = max(0, document.bounds.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(100))
        guard scroll.contentView.bounds.minY > 0 else { throw CheckFailure("Panel could not scroll to the bottom") }
        try capture("height-limited-bottom")
        print("PASS: height-limited scrolling, offset \(scroll.contentView.bounds.minY)")
    }

    private func capture(_ name: String) throws {
        let view = host.view
        guard view.bounds.width > 0, view.bounds.height > 0,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CheckFailure("Cannot capture \(name): empty hosting view \(view.bounds)")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CheckFailure("Cannot encode \(name) screenshot")
        }
        try png.write(to: output.appendingPathComponent("\(name).png"))
    }
}

@main
private struct Main {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = PanelChecks()
        app.delegate = delegate
        app.run()
    }
}
