import AppKit
import Combine
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
    private var iconState = ""
    private var iconUpdates: AnyCancellable?
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
        let host = NSHostingController(rootView: MenuPanel(model: model))
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
        button.toolTip = ["attention": "Gimme Remote：需要处理", "paused": model.paused ? "Gimme Remote：已暂停" : "Gimme Remote：Mac 已锁定",
                          "connected": "Gimme Remote：\(model.connected) 台已连接"][state] ?? "Gimme Remote"
        guard state != iconState else { return }
        iconState = state
        button.image = Self.statusImage(state)
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
        image.accessibilityDescription = "Gimme Remote：需要处理"
        return image
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
                    if value { self?.controller.release() }
                    // Unlocking usually unlocks the Keychain too; restore devices paired before.
                    else if let self { await self.retryVault() }
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
                                  ready: { [weak self] in self?.running = true })
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
                    return "Remote input paused. Resume with `gimme resume` or from the menu bar."
                case "resume":
                    await self.setPaused(false)
                    return "Remote input resumed."
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
                vaultUnreadable = await sessions.vaultUnreadable()
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
    func retryVault() async {
        await sessions.retryVault()
        vaultUnreadable = await sessions.vaultUnreadable()
        paired = await sessions.pairedCount()
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
        task?.cancel(); ticker?.cancel(); controller.release()
        for observer in lockObservers { DistributedNotificationCenter.default().removeObserver(observer) }
        lockObservers.removeAll()
        if assertionActive { IOPMAssertionRelease(assertion); assertionActive = false }
    }
}

struct MenuPanel: View {
    @ObservedObject var model: AppModel
    @State private var addingDevice = false
    @State private var confirmRevoke = false
    @State private var copied = false
    private let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    // With no paired phone the QR code is the next step; otherwise it waits behind "添加新设备".
    private var showPairing: Bool { model.paired == 0 || addingDevice }
    private var status: (text: String, color: Color) {
        if !model.running { return ("正在启动…", .secondary) }
        if !model.trusted { return ("需要授权", .orange) }
        if model.paused { return ("已暂停", .secondary) }
        if model.locked { return ("Mac 已锁定", .orange) }
        if model.connected > 0 { return ("\(model.connected) 台已连接", .green) }
        return ("等待手机连接", .secondary)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if !model.trusted { accessibilityGuide }
            if model.vaultUnreadable {
                card(tint: .orange) {
                    Text("无法读取钥匙串中的已配对设备，手机需要重新配对。可点“更新配对码”后重新扫码。")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    Button("重新读取钥匙串") { Task { await model.retryVault() } }.buttonStyle(.link).font(.caption)
                }
            }
            pairing
            address
            groups
            if let failure = model.failure {
                HStack(alignment: .top) {
                    Text(failure).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("关闭") { model.failure = nil }.buttonStyle(.link).font(.caption)
                }
            }
            HStack {
                Text("Gimme Remote v\(version)").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }.controlSize(.small)
            }
        }
        .padding(16).frame(width: 340).fixedSize(horizontal: false, vertical: true)
        .onChange(of: model.paired) { old, new in if new > old { addingDevice = false } }
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text("Gimme Remote").font(.headline)
                HStack(spacing: 6) {
                    Text(status.text).font(.caption.weight(.medium)).foregroundStyle(status.color)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(status.color.opacity(0.15), in: Capsule())
                    Text("\(model.paired) 台已配对").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("遥控", isOn: Binding(get: { !model.paused }, set: { value in Task { await model.setPaused(!value) } }))
                .toggleStyle(.switch).labelsHidden().help(model.paused ? "恢复遥控" : "暂停遥控")
        }
    }
    private var accessibilityGuide: some View {
        card(tint: .orange) {
            Text("需要辅助功能权限，手机才能控制这台 Mac").font(.callout.weight(.semibold))
            Text("① 点下面的按钮打开系统设置\n② 打开 Gimme Remote 的开关").font(.caption)
            Button("授权辅助功能") { AppInspector.requestAccessibility() }.buttonStyle(.borderedProminent)
            // An update changes the code signature; macOS may keep a stale entry switched on.
            Text("已经打开仍无效：在列表中选中它点“−”删除，再重新添加。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    @ViewBuilder private var pairing: some View {
        if !showPairing {
            Button { addingDevice = true; Task { await model.refreshCode() } } label: {
                Label("添加新设备", systemImage: "plus.circle").frame(maxWidth: .infinity)
            }.controlSize(.large)
        } else if !model.code.isEmpty, let image = qr(model.pairURL) {
            VStack(spacing: 8) {
                ZStack {
                    Image(nsImage: image).interpolation(.none).resizable().frame(width: 168, height: 168)
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
                        .padding(3).background(.white, in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                Text("\(model.code.prefix(3)) \(model.code.suffix(3))")
                    .font(.system(size: 26, weight: .semibold, design: .monospaced)).kerning(3)
                Text("用手机相机扫码 · 2 分钟内有效").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("更新配对码") { Task { await model.refreshCode() } }
                    if model.paired > 0 { Button("收起") { addingDevice = false } }
                }.controlSize(.small)
            }.frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 8) {
                Text("配对码已失效，点“更新配对码”重新生成").font(.callout).foregroundStyle(.secondary)
                Button("更新配对码") { Task { await model.refreshCode() } }
            }.frame(maxWidth: .infinity)
        }
    }
    private var address: some View {
        HStack(spacing: 6) {
            if model.addresses.count > 1 {
                Picker("连接地址", selection: $model.url) {
                    ForEach(model.addresses, id: \.self) { address in Text(address).tag(address) }
                }.labelsHidden().controlSize(.small)
            } else {
                Text(model.url).font(.caption.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            Button {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.url, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
            } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                .buttonStyle(.borderless).help("复制地址")
        }
    }
    private var groups: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox("遥控") {
                Toggle("手机连接时，不让显示器休眠", isOn: $model.preventSleep).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("通用") {
                Toggle("登录时启动", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("设备") {
                // Revoking forces every phone to scan again, so it takes a second, explicit click.
                if confirmRevoke {
                    HStack {
                        Text("所有手机都要重新配对").font(.caption)
                        Spacer()
                        Button("取消") { confirmRevoke = false }
                        Button("撤销全部", role: .destructive) { confirmRevoke = false; Task { await model.revoke() } }
                            .tint(.red).buttonStyle(.borderedProminent)
                    }.controlSize(.small)
                } else {
                    HStack {
                        Button("断开全部设备") { Task { await model.disconnect() } }
                        Button("撤销全部配对…") { confirmRevoke = true }.foregroundStyle(.red)
                        Spacer(minLength: 0)
                    }.controlSize(.small)
                }
            }
        }
    }
    private func card<Content: View>(tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.35)))
    }
    private func qr(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        // Quartile error correction leaves room for the icon over the center.
        filter.correctionLevel = "Q"
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
                                                    from: output.extent.applying(CGAffineTransform(scaleX: 8, y: 8))) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: 176, height: 176))
    }
}
