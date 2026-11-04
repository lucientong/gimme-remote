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
    private var strings: NativeLocalization { model.strings }
    private var status: (text: String, color: Color) {
        if !model.running { return (strings.text(.starting), .secondary) }
        if !model.trusted { return (strings.text(.needsPermission), .orange) }
        if model.paused { return (strings.text(.paused), .secondary) }
        if model.locked { return (strings.text(.locked), .orange) }
        if model.connected > 0 { return (strings.connected(model.connected), .green) }
        return (strings.text(.waiting), .secondary)
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
                    Text(strings.text(.vaultWarning))
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    Button(strings.text(.retryVault)) { Task { await model.retryVault() } }.buttonStyle(.link).font(.caption)
                }
            }
            pairing
            address
            groups
            if let failure = model.failure {
                HStack(alignment: .top) {
                    Text(strings.text(failure.key, ["detail": failure.detail])).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(strings.text(.close)) { model.failure = nil }.buttonStyle(.link).font(.caption)
                }
            }
            HStack {
                Text("Gimme Remote \(version == "dev" ? version : "v\(version)")").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button(strings.text(.quit)) { NSApp.terminate(nil) }.controlSize(.small)
            }
        }
        .padding(16).frame(width: 340).fixedSize(horizontal: false, vertical: true)
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text("Gimme Remote").font(.headline)
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.text).font(.caption.weight(.medium)).foregroundStyle(status.color)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(status.color.opacity(0.15), in: Capsule())
                    Text(strings.paired(model.paired)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle(strings.text(.remote), isOn: Binding(get: { !model.paused }, set: { value in Task { await model.setPaused(!value) } }))
                .toggleStyle(.switch).labelsHidden().help(strings.text(model.paused ? .resume : .pause))
        }
    }
    private var accessibilityGuide: some View {
        card(tint: .orange) {
            Text(strings.text(.permissionTitle)).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text(strings.text(.permissionSteps)).font(.caption).fixedSize(horizontal: false, vertical: true)
            Button(strings.text(.grantPermission)) { AppInspector.requestAccessibility() }.buttonStyle(.borderedProminent)
            // An update changes the code signature; macOS may keep a stale entry switched on.
            Text(strings.text(.permissionRetry))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    @ViewBuilder private var pairing: some View {
        if !showPairing {
            Button { addingDevice = true; Task { await model.refreshCode() } } label: {
                Label(strings.text(.addDevice), systemImage: "plus.circle").frame(maxWidth: .infinity)
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
                Text(strings.text(.scan)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(strings.text(.refreshCode)) { Task { await model.refreshCode() } }
                    if model.paired > 0 { Button(strings.text(.collapse)) { addingDevice = false } }
                }.controlSize(.small)
            }.frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 8) {
                Text(strings.text(.expiredCode)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(strings.text(.refreshCode)) { Task { await model.refreshCode() } }
            }.frame(maxWidth: .infinity)
        }
    }
    private var address: some View {
        HStack(spacing: 6) {
            if model.addresses.count > 1 {
                Picker(strings.text(.address), selection: $model.url) {
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
                .buttonStyle(.borderless).help(strings.text(.copyAddress))
        }
    }
    private var groups: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox(strings.text(.remote)) {
                Toggle(isOn: $model.preventSleep) {
                    Text(strings.text(.preventSleep)).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox(strings.text(.general)) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(strings.text(.launchAtLogin), isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Picker(strings.text(.language), selection: $model.languageChoice) {
                        Text(strings.text(.automatic)).tag("auto")
                        ForEach(InterfaceLanguage.allCases, id: \.self) { language in
                            Text(language.name).tag(language.rawValue)
                        }
                    }.controlSize(.small)
                }
            }
            GroupBox(strings.text(.devices)) {
                // Revoking forces every phone to scan again, so it takes a second, explicit click.
                if confirmRevoke {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(strings.text(.revokeWarning)).font(.caption).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(strings.text(.cancel)) { confirmRevoke = false }
                            Button(strings.text(.revoke), role: .destructive) { confirmRevoke = false; Task { await model.revoke() } }
                                .tint(.red).buttonStyle(.borderedProminent)
                        }
                    }.controlSize(.small)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Button(strings.text(.disconnect)) { Task { await model.disconnect() } }
                        Button(strings.text(.revokeAll)) { confirmRevoke = true }.foregroundStyle(.red)
                    }.frame(maxWidth: .infinity, alignment: .leading).controlSize(.small)
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
