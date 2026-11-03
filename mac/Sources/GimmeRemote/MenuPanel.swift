import AppKit
import SwiftUI
import CoreImage.CIFilterBuiltins

struct MenuPanel: View {
    @ObservedObject var model: AppModel
    var maximumHeight: CGFloat
    @State private var addingDevice = false
    @State private var confirmRevoke = false
    @State private var copied = false
    // Starts near the smallest panel so the first open grows into place instead of shrinking.
    @State private var contentHeight: CGFloat = 360
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
        ScrollView {
            // A GeometryReader preference reports 0 here on macOS 26 and collapses the panel to a blank sheet.
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if $0 > 0 { contentHeight = $0 } }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 340, height: min(contentHeight, maximumHeight))
        .onChange(of: model.paired) { old, new in if new > old { addingDevice = false } }
    }
    private var content: some View {
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
                Text("Gimme Remote \(version == "dev" ? version : "v\(version)")").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }.controlSize(.small)
            }
        }
        .padding(16).frame(width: 340).fixedSize(horizontal: false, vertical: true)
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
