import AppKit
import SwiftUI
import CoreImage.CIFilterBuiltins
import ServiceManagement
import IOKit.pwr_mgt
import RemoteCore
import RemoteTransport

@main
struct GimmeRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { Text("请从菜单栏打开 Gimme Remote").padding() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.lucientong.GimmeRemote").count > 1 {
            NSApp.terminate(nil); return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "appletvremote.gen1", accessibilityDescription: "Gimme Remote")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggle)
        do {
            let model = try AppModel()
            self.model = model
            popover.behavior = .transient
            popover.contentSize = NSSize(width: 340, height: 620)
            popover.contentViewController = NSHostingController(rootView: MenuPanel(model: model))
            model.start()
            if !AXIsProcessTrusted() { toggle() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Gimme Remote 无法启动"
            alert.informativeText = "无法读取 Keychain。请解锁钥匙串后重新打开 App。"
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
    @objc private func toggle() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); NSApp.activate(ignoringOtherApps: true) }
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
    @Published var failure: String?
    @Published var paused = false
    @Published var preventSleep = UserDefaults.standard.bool(forKey: "preventSleep")
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    let sessions: Sessions
    private let controller = InputController()
    private var task: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var ipc: IPCServer?
    private var bonjour: NetService?
    private var lockObservers: [NSObjectProtocol] = []
    private var assertion: IOPMAssertionID = 0
    private var assertionActive = false

    init() throws { sessions = try Sessions() }
    var pairURL: String { "\(url)/#code=\(code)" }
    func start() {
        for (name, value) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            lockObservers.append(DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    AppInspector.notifiedLocked = value
                    if value { self?.controller.release() }
                }
            })
        }
        let server = RemoteServer(sessions: sessions,
                                  state: { [weak self] in AppInspector.state(paused: self?.paused ?? true) },
                                  input: { [weak self] message, id in
                                      guard let self else { throw ControlError("servicePaused") }
                                      try self.controller.perform(message, session: id, state: AppInspector.state(paused: self.paused))
                                  },
                                  release: { [weak self] id in self?.controller.release(session: id) },
                                  ready: { [weak self] in
                                      self?.running = true
                                      self?.bonjour = NetService(domain: "local.", type: "_gimme._tcp.", name: "Gimme Remote", port: Int32(NetworkAddress.port))
                                      self?.bonjour?.publish()
                                  })
        task = Task {
            do { try await server.run() }
            catch { if !Task.isCancelled { failure = "服务启动失败：\(error)"; running = false } }
        }
        do {
            ipc = try IPCServer { [weak self] command in
                guard let self else { return "App unavailable" }
                switch command {
                case "pair":
                    await self.refreshCode()
                    return "Pair: \(self.pairURL) (expires in 120 seconds)"
                case "stop":
                    await self.setPaused(true)
                    return "Remote input paused. Resume from the menu bar."
                default:
                    return "Gimme Remote: \(self.running ? "running" : "starting"), \(self.paused ? "paused" : "active"), devices: \(self.connected), accessibility: \(self.trusted) · \(self.url)"
                }
            }
        } catch { failure = "CLI 服务不可用：\(error)" }
        ticker = Task {
            await refreshCode()
            while !Task.isCancelled {
                connected = await sessions.activeCount()
                paired = await sessions.pairedCount()
                trusted = AXIsProcessTrusted()
                locked = AppInspector.isLocked
                addresses = NetworkAddress.accessURLs()
                if !addresses.contains(url) { url = addresses.first ?? NetworkAddress.preferredURL() }
                if let current = await sessions.currentCode() {
                    code = current.code; expires = current.expires
                } else { code = "" }
                if locked || !trusted || paused { controller.release() }
                updatePower()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    func refreshCode() async {
        do {
            let value = try await sessions.newCode()
            code = value.code; expires = value.expires
        } catch { failure = "配对码生成失败" }
    }
    func setPaused(_ value: Bool) async {
        paused = value
        controller.release()
        if value { await sessions.disconnectAll() }
        updatePower()
    }
    func revoke() async {
        do { try await sessions.revokeAll(); controller.release(); await refreshCode() }
        catch { failure = "无法撤销设备：Keychain 写入失败" }
    }
    func disconnect() async { await sessions.disconnectAll(); controller.release() }
    func setLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch { failure = "登录启动设置失败：\(error)"; loginEnabled = SMAppService.mainApp.status == .enabled }
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
        task?.cancel(); ticker?.cancel(); controller.release(); bonjour?.stop()
        for observer in lockObservers { DistributedNotificationCenter.default().removeObserver(observer) }
        lockObservers.removeAll()
        if assertionActive { IOPMAssertionRelease(assertion); assertionActive = false }
    }
}

struct MenuPanel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gimme Remote").font(.title2.bold())
            Text(model.running ? "\(model.connected) 台已连接 · \(model.paired) 台已配对" : "服务正在启动…")
                .foregroundStyle(.secondary)
            if !model.trusted {
                Button("授权辅助功能，开始遥控") { AppInspector.requestAccessibility() }
                    .buttonStyle(.borderedProminent)
            }
            if model.locked { Text("Mac 已锁定").foregroundStyle(.orange) }
            if !model.code.isEmpty, let image = qr(model.pairURL) {
                HStack { Spacer(); Image(nsImage: image).interpolation(.none).resizable().frame(width: 176, height: 176); Spacer() }
                Text(model.code).font(.system(size: 26, weight: .semibold, design: .monospaced)).frame(maxWidth: .infinity)
                Text("扫码打开手机遥控器 · 配对码 2 分钟有效").font(.caption).foregroundStyle(.secondary)
            } else { Text("配对码已使用或过期").foregroundStyle(.secondary) }
            Text(model.url).font(.caption.monospaced()).textSelection(.enabled)
            if model.addresses.count > 1 {
                Picker("连接地址", selection: $model.url) {
                    ForEach(model.addresses, id: \.self) { address in Text(address).tag(address) }
                }
            }
            HStack {
                Button("更新配对码") { Task { await model.refreshCode() } }
                Button("复制地址") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.url, forType: .string) }
            }
            Divider()
            Toggle("暂停遥控", isOn: Binding(get: { model.paused }, set: { value in Task { await model.setPaused(value) } }))
            Toggle("登录时启动", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
            Toggle("连接期间阻止显示器休眠", isOn: $model.preventSleep)
            HStack {
                Button("断开全部设备") { Task { await model.disconnect() } }
                Button("撤销全部配对") { Task { await model.revoke() } }
            }
            if let failure = model.failure { Text(failure).font(.caption).foregroundStyle(.red) }
            Divider()
            Button("退出 Gimme Remote") { NSApp.terminate(nil) }
        }.padding(20).frame(width: 340)
        }.frame(width: 340, height: 620)
    }
    private func qr(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
                                                    from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8))) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: 176, height: 176))
    }
}
