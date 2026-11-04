import AppKit
@preconcurrency import ApplicationServices
import RemoteCore

/// AX calls can block on another process; keep them off the input/UI actor.
private actor BrowserAccessibility {
    private struct Snapshot {
        var nodes: [PlayerNode] = []
        var elements: [AXUIElement] = []
        var window: AXUIElement
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func snapshot(pid: pid_t) -> Snapshot? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        guard let rawWindow = attribute(app, kAXFocusedWindowAttribute),
              CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else { return nil }
        let window = unsafeDowncast(rawWindow, to: AXUIElement.self)
        let names = [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute,
                     kAXEnabledAttribute, kAXHiddenAttribute, kAXPositionAttribute, kAXSizeAttribute,
                     kAXChildrenAttribute]
        var result = Snapshot(window: window)
        var pending: [(AXUIElement, Int?, Bool, Bool, Bool)] = [(window, nil, false, true, true)]
        let deadline = ProcessInfo.processInfo.systemUptime + 0.3
        while let (element, parent, inPage, parentVisible, parentEnabled) = pending.popLast() {
            guard result.nodes.count < 2500, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            var raw: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &raw) == .success,
                  let values = raw as? [Any], values.count == names.count else {
                // A tab transition or an AX timeout must not produce a partial player match.
                if inPage { return nil }
                continue
            }
            let role = values[0] as? String ?? ""
            let page = inPage || role == "AXWebArea"
            let visible = parentVisible && (values[5] as? Bool != true)
            let enabled = parentEnabled && (values[4] as? Bool != false)
            guard visible else { continue }
            var point = CGPoint.zero, size = CGSize.zero
            if CFGetTypeID(values[6] as CFTypeRef) == AXValueGetTypeID() {
                AXValueGetValue(unsafeBitCast(values[6] as CFTypeRef, to: AXValue.self), .cgPoint, &point)
            }
            if CFGetTypeID(values[7] as CFTypeRef) == AXValueGetTypeID() {
                AXValueGetValue(unsafeBitCast(values[7] as CFTypeRef, to: AXValue.self), .cgSize, &size)
            }
            let frame = CGRect(origin: point, size: size)
            if page, !frame.isEmpty, let windowFrame = result.nodes.first?.frame,
               !windowFrame.isEmpty, !frame.intersects(windowFrame) { continue }
            var actions: CFArray?
            if page && role == kAXButtonRole {
                _ = AXUIElementCopyActionNames(element, &actions)
            }
            let index = result.nodes.count
            result.nodes.append(.init(parent: parent, role: role,
                                      labels: values[1...3].compactMap { $0 as? String },
                                      frame: frame, visible: visible, enabled: enabled,
                                      pressable: (actions as? [String])?.contains(kAXPressAction) == true))
            result.elements.append(element)
            if let children = values[8] as? [AXUIElement] {
                for child in children.reversed() {
                    pending.append((child, index, page, visible, enabled))
                }
            }
        }
        return result
    }

    func controls(pid: pid_t) -> EpisodeControls? {
        guard let tree = snapshot(pid: pid),
              let selection = BrowserPlayerDetection.select(tree.nodes) else { return nil }
        return selection.controls(in: tree.nodes)
    }

    func press(_ action: String, pid: pid_t) throws {
        // Re-read the focused window and active tab for every action. Never retain old button handles.
        guard let tree = snapshot(pid: pid), let selection = BrowserPlayerDetection.select(tree.nodes),
              let index = action == "previousEpisode" ? selection.previous : selection.next,
              tree.nodes[index].enabled else { throw ControlError("episodeUnavailable") }
        // A focus change during discovery must not press a button in the previous window/app.
        let system = AXUIElementCreateSystemWide()
        try Task.checkCancellation()
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        guard session?["CGSSessionScreenIsLocked"] as? Bool != true,
              session?[kCGSessionOnConsoleKey as String] as? Bool != false else {
            throw ControlError("macLocked")
        }
        guard let focusedApp = attribute(system, kAXFocusedApplicationAttribute),
              CFGetTypeID(focusedApp) == AXUIElementGetTypeID() else { throw ControlError("episodeUnavailable") }
        let app = unsafeDowncast(focusedApp, to: AXUIElement.self)
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(app, &focusedPID) == .success, focusedPID == pid,
              let window = attribute(app, kAXFocusedWindowAttribute), CFEqual(window, tree.window),
              attribute(tree.elements[index], kAXEnabledAttribute) as? Bool != false,
              attribute(tree.elements[index], kAXHiddenAttribute) as? Bool != true else {
            throw ControlError("episodeUnavailable")
        }
        // Browsers may keep the previous tab's AX objects alive. Check that the target is
        // still a descendant of the current window, rather than merely a valid old handle.
        var current = index
        while let parent = tree.nodes[current].parent {
            try Task.checkCancellation()
            guard let children = attribute(tree.elements[parent], kAXChildrenAttribute) as? [AXUIElement],
                  children.contains(where: { CFEqual($0, tree.elements[current]) }) else {
                throw ControlError("episodeUnavailable")
            }
            current = parent
        }
        try Task.checkCancellation()
        guard AXUIElementPerformAction(tree.elements[index], kAXPressAction as CFString) == .success else {
            throw ControlError("episodeUnavailable")
        }
    }
}

@MainActor
final class BrowserPlayer {
    static let shared = BrowserPlayer()
    private let accessibility = BrowserAccessibility()
    private var pid: pid_t?
    private var sampledAt = -Double.infinity
    private var controls: EpisodeControls?
    private var generation = 0
    private var pending: Task<Void, Error>?

    func current(for application: NSRunningApplication?) -> EpisodeControls? {
        guard application?.processIdentifier == pid,
              ProcessInfo.processInfo.systemUptime - sampledAt < 2 else { return nil }
        return controls
    }

    func refresh(application: NSRunningApplication?) async {
        guard let application, KeyMapping.layout(bundleId: application.bundleIdentifier ?? "") == "browser",
              AXIsProcessTrusted(), !AppInspector.isLocked else { clear(); return }
        let target = application.processIdentifier
        let epoch = generation
        let value = await accessibility.controls(pid: target)
        guard epoch == generation, !Task.isCancelled else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target else { clear(); return }
        pid = target; controls = value; sampledAt = ProcessInfo.processInfo.systemUptime
    }

    func clear() {
        generation += 1
        pending?.cancel(); pending = nil
        pid = nil; controls = nil; sampledAt = -.infinity
    }

    func perform(_ action: String) async throws {
        guard let app = NSWorkspace.shared.frontmostApplication,
              KeyMapping.layout(bundleId: app.bundleIdentifier ?? "") == "browser",
              !AppInspector.isLocked else { throw ControlError("episodeUnavailable") }
        clear()
        let operation = Task { try await accessibility.press(action, pid: app.processIdentifier) }
        pending = operation
        let epoch = generation
        defer { if epoch == generation { pending = nil } }
        try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: { operation.cancel() }
    }
}
