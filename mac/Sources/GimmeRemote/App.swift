import AppKit
import Combine
import SwiftUI
import ServiceManagement
import IOKit.pwr_mgt
import RemoteCore
import RemoteTransport

@main
struct GimmeRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { SettingsHint() }
    }
}

private struct SettingsHint: View {
    @AppStorage(NativeLocalization.preferenceKey) private var choice = "auto"
    var body: some View { Text(NativeLocalization(choice: choice).text(.openMenu)).padding() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private var model: AppModel?
    private var iconState = ""
    private var iconUpdates: AnyCancellable?
    private var terminating = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.lucientong.GimmeRemote").count > 1 {
            NSApp.terminate(nil); return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        let model = AppModel()
        self.model = model
        updateIcon()
        // objectWillChange fires before the value lands; the next run loop sees the new state.
        iconUpdates = model.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.updateIcon() }
        popover.behavior = .transient
        let host = NSHostingController(rootView: MenuPanel(model: model, maximumHeight: panelHeight))
        // The panel grows and shrinks with its content (e.g. the pairing QR code folding away).
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        model.start()
        if !AXIsProcessTrusted() { toggle() }
        Task { if await model.sessions.vaultUnreadable(), !popover.isShown { toggle() } }
    }
    /// Shows at a glance why the phone may not respond, without opening the panel.
    private func updateIcon() {
        guard let model, let button = statusItem.button else { return }
        let state = !model.trusted || model.vaultUnreadable ? "attention"
            : model.paused || model.locked ? "paused" : model.connected > 0 ? "connected" : "idle"
        let strings = model.strings
        let detail = state == "attention" ? strings.text(.attention)
            : state == "paused" ? strings.text(model.paused ? .paused : .locked)
            : state == "connected" ? strings.connected(model.connected) : ""
        button.toolTip = detail.isEmpty ? "Gimme Remote" : "Gimme Remote · \(detail)"
        button.setAccessibilityLabel(button.toolTip)
        button.image?.accessibilityDescription = button.toolTip
        guard state != iconState else { return }
        iconState = state
        button.image = Self.statusImage(state)
        button.image?.accessibilityDescription = button.toolTip
        button.appearsDisabled = state == "paused"
    }
    private static func statusImage(_ state: String) -> NSImage? {
        let base = NSImage(systemSymbolName: state == "connected" ? "appletvremote.gen1.fill" : "appletvremote.gen1", accessibilityDescription: "Gimme Remote")
            ?? NSImage(systemSymbolName: "appletvremote.gen1", accessibilityDescription: "Gimme Remote")
        guard state == "attention", let base, let badge = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil) else { return base }
        let size = base.size
        let image = NSImage(size: NSSize(width: size.width + 5, height: size.height), flipped: false) { rect in
            base.draw(in: NSRect(origin: .zero, size: size))
            let mark = NSRect(x: rect.width - 10, y: 0, width: 10, height: 10)
            // Cut a gap around the badge so it stays legible as a template image.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: mark.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            badge.draw(in: mark)
            return true
        }
        image.isTemplate = true
        return image
    }
    @objc private func toggle() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            // The menu bar may be on a different screen than the frontmost app.
            if let host = popover.contentViewController as? NSHostingController<MenuPanel>, let model {
                host.rootView = MenuPanel(model: model, maximumHeight: panelHeight)
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    /// Opening the App again from Finder or Launchpad lands here; show the panel instead of doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { toggle() }
        return false
    }
    private var panelHeight: CGFloat {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        return max(1, (screen?.visibleFrame.height ?? 800) - 64)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if !terminating {
            terminating = true
            Task {
                await model.shutdown()
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { model?.stop() }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var url = NetworkAddress.preferredURL()
    @Published var addresses = NetworkAddress.accessURLs()
    @Published var code = ""
    @Published var expires = Date.distantPast
    @Published var connected = 0
    @Published var paired = 0
    @Published var trusted = AXIsProcessTrusted()
    @Published var locked = false
    @Published var running = false
    @Published var failure: NativeNotice?
    @Published var languageChoice = NativeLocalization.savedChoice() {
        didSet { UserDefaults.standard.set(languageChoice, forKey: NativeLocalization.preferenceKey) }
    }
    var strings: NativeLocalization { NativeLocalization(choice: languageChoice) }
    @Published var vaultUnreadable = false
    @Published var paused = false
    @Published var preventSleep = UserDefaults.standard.bool(forKey: "preventSleep")
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    let sessions: Sessions
    private let controller = InputController()
    private var task: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var ipc: IPCServer?
    private var lockObservers: [NSObjectProtocol] = []
    private var assertion: IOPMAssertionID = 0
    private var assertionActive = false

    // A locked or denied Keychain must not stop the App; phones can pair again.
    init() { sessions = Sessions(recovering: KeychainVault()) }
    var pairURL: String { "\(url)/#code=\(code)" }
    func start() {
        for (name, value) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            lockObservers.append(DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    AppInspector.notifiedLocked = value
                    if value { BrowserPlayer.shared.clear(); self?.controller.release() }
                    // Unlocking usually unlocks the Keychain too; restore devices paired before.
                    else if let self { await self.retryVault() }
                }
            })
        }
        let server = RemoteServer(sessions: sessions,
                                  state: { [weak self] in AppInspector.state(paused: self?.paused ?? true) },
                                  input: { [weak self] message, id in
                                      guard let self else { throw ControlError("servicePaused") }
                                      try await self.controller.perform(message, session: id, state: AppInspector.state(paused: self.paused))
                                  },
                                  release: { [weak self] id in self?.controller.release(session: id) },
                                  ready: { [weak self] in self?.running = true })
        task = Task {
            do { try await server.run() }
            catch { if !Task.isCancelled { failure = NativeNotice(key: .serverFailure, detail: String(describing: error)); running = false } }
        }
        do {
            ipc = try IPCServer { [weak self] command in
                guard let self else { return "App unavailable" }
                switch command {
                case "player":
                    return await BrowserPlayer.shared.diagnostic()
                case "pair":
                    await self.refreshCode()
                    return "Pair: \(self.pairURL) (expires in 120 seconds)"
                case "stop":
                    await self.setPaused(true)
                    return "Remote input paused. Resume with `gimme resume` or from the menu bar."
                case "resume":
                    await self.setPaused(false)
                    return "Remote input resumed."
                default:
                    return "Gimme Remote: \(self.running ? "running" : "starting"), \(self.paused ? "paused" : "active"), devices: \(self.connected), accessibility: \(self.trusted) · \(self.url)"
                }
            }
        } catch { failure = NativeNotice(key: .cliFailure, detail: String(describing: error)) }
        ticker = Task {
            await refreshCode()
            while !Task.isCancelled {
                connected = await sessions.activeCount()
                paired = await sessions.pairedCount()
                vaultUnreadable = await sessions.vaultUnreadable()
                trusted = AXIsProcessTrusted()
                locked = AppInspector.isLocked
                addresses = NetworkAddress.accessURLs()
                if !addresses.contains(url) { url = addresses.first ?? NetworkAddress.preferredURL() }
                if let current = await sessions.currentCode() {
                    code = current.code; expires = current.expires
                } else { code = "" }
                if locked || !trusted || paused { controller.release() }
                if connected > 0 && !paused {
                    await BrowserPlayer.shared.refresh(application: NSWorkspace.shared.frontmostApplication)
                } else { BrowserPlayer.shared.clear() }
                updatePower()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    func refreshCode() async {
        do {
            let value = try await sessions.newCode()
            code = value.code; expires = value.expires
        } catch { failure = NativeNotice(key: .codeFailure) }
    }
    func retryVault() async {
        await sessions.retryVault()
        vaultUnreadable = await sessions.vaultUnreadable()
        paired = await sessions.pairedCount()
    }
    func setPaused(_ value: Bool) async {
        paused = value
        BrowserPlayer.shared.clear()
        controller.release()
        await sessions.stateChanged()
        updatePower()
    }
    func revoke() async {
        BrowserPlayer.shared.clear()
        do { try await sessions.revokeAll(); controller.release(); await refreshCode() }
        catch { failure = NativeNotice(key: .revokeFailure) }
    }
    func disconnect() async {
        BrowserPlayer.shared.clear()
        await sessions.disconnectAll()
        connected = 0
        controller.release()
        updatePower()
    }
    func setLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch { failure = NativeNotice(key: .loginFailure, detail: String(describing: error)); loginEnabled = SMAppService.mainApp.status == .enabled }
    }
    func updatePower() {
        UserDefaults.standard.set(preventSleep, forKey: "preventSleep")
        let shouldPrevent = preventSleep && connected > 0 && !paused && !locked
        if shouldPrevent && !assertionActive {
            assertionActive = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                         IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                         "Gimme Remote connected" as CFString, &assertion) == kIOReturnSuccess
        } else if !shouldPrevent && assertionActive {
            IOPMAssertionRelease(assertion); assertionActive = false
        }
    }
    func stop() {
        BrowserPlayer.shared.clear()
        task?.cancel(); ticker?.cancel(); controller.release()
        for observer in lockObservers { DistributedNotificationCenter.default().removeObserver(observer) }
        lockObservers.removeAll()
        if assertionActive { IOPMAssertionRelease(assertion); assertionActive = false }
    }
    func shutdown() async {
        await sessions.shutdown()
        stop()
        await task?.value
    }
}
