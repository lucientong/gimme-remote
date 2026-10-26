import AppKit
import ApplicationServices
import RemoteCore

@MainActor
final class InputController {
    private var movement = CGVector.zero
    private var timer: Timer?
    private var dragOwner: UUID?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.flushMovement() }
        }
    }

    func perform(_ message: Message, session: UUID, state: RemoteState) throws {
        guard !state.paused else { throw ControlError("servicePaused") }
        guard !state.locked else { throw ControlError("macLocked") }
        guard state.accessibility else { throw ControlError("accessibilityRequired") }
        let p = message.payload
        switch message.type {
        case "input.pointer.move":
            guard dragOwner == nil || dragOwner == session else { throw ControlError("pointerBusy") }
            movement.dx = max(-1000, min(1000, movement.dx + p.dx!))
            movement.dy = max(-1000, min(1000, movement.dy + p.dy!))
        case "input.pointer.scroll":
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                      wheel1: Int32(-p.dy!), wheel2: Int32(-p.dx!), wheel3: 0) else {
                throw ControlError("inputFailed")
            }
            event.post(tap: .cghidEventTap)
        case "input.pointer.click":
            guard dragOwner == nil else { throw ControlError("pointerBusy") }
            flushMovement()
            let right = p.button == "right"
            try mouse(right ? .rightMouseDown : .leftMouseDown, button: right ? .right : .left)
            try mouse(right ? .rightMouseUp : .leftMouseUp, button: right ? .right : .left)
        case "input.pointer.drag":
            flushMovement()
            if p.phase == "start" {
                guard dragOwner == nil || dragOwner == session else { throw ControlError("pointerBusy") }
                if dragOwner == nil { try mouse(.leftMouseDown); dragOwner = session }
            } else { release(session: session) }
        case "input.text.insert":
            try insertText(p.text!)
        case "input.keyboard.shortcut":
            try key(KeyMapping.shortcut(p.action!))
        case "media.command":
            let iina = state.layout == "iina"
            let pid = iina ? NSRunningApplication.runningApplications(withBundleIdentifier: "com.colliderli.iina").first?.processIdentifier : nil
            try key(KeyMapping.media(p.action!, iina: iina), pid: pid)
        default: throw ControlError("unsupportedMessage")
        }
    }

    func release(session: UUID? = nil) {
        guard session == nil || dragOwner == nil || dragOwner == session else { return }
        if dragOwner != nil { try? mouse(.leftMouseUp) }
        dragOwner = nil
        movement = .zero
    }

    private func flushMovement() {
        guard movement != .zero else { return }
        defer { movement = .zero }
        guard AXIsProcessTrusted(), !AppInspector.isLocked else { release(); return }
        let current = CGEvent(source: nil)?.location ?? .zero
        var point = CGPoint(x: current.x + movement.dx, y: current.y + movement.dy)
        // Clamp to a real display (Quartz coordinates); gaps cannot swallow the cursor.
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        CGGetActiveDisplayList(32, &displays, &count)
        let bounds = displays.prefix(Int(count)).map { CGDisplayBounds($0) }
        if !bounds.contains(where: { $0.contains(point) }) {
            point = bounds.map { rect in
                CGPoint(x: max(rect.minX, min(rect.maxX - 1, point.x)),
                        y: max(rect.minY, min(rect.maxY - 1, point.y)))
            }.min { hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y) } ?? current
        }
        CGEvent(mouseEventSource: nil, mouseType: dragOwner == nil ? .mouseMoved : .leftMouseDragged,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private func mouse(_ type: CGEventType, button: CGMouseButton = .left) throws {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: CGEvent(source: nil)?.location ?? .zero, mouseButton: button) else {
            throw ControlError("inputFailed")
        }
        event.post(tap: .cghidEventTap)
    }
    private func key(_ stroke: KeyStroke, pid: pid_t? = nil) throws {
        var flags: CGEventFlags = []
        if stroke.command { flags.insert(.maskCommand) }
        if stroke.option { flags.insert(.maskAlternate) }
        if stroke.shift { flags.insert(.maskShift) }
        let appSwitch = stroke.command && stroke.key == 48
        if appSwitch {
            let command = CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: true)
            command?.flags = .maskCommand
            command?.post(tap: .cghidEventTap)
        }
        defer {
            if appSwitch {
                // Releasing Command commits the switch and closes the app switcher.
                let command = CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: false)
                command?.flags = []
                command?.post(tap: .cghidEventTap)
            }
        }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: stroke.key, keyDown: down) else {
                throw ControlError("inputFailed")
            }
            event.flags = flags
            if let pid { event.postToPid(pid) } else { event.post(tap: .cghidEventTap) }
        }
    }
    private func insertText(_ text: String) throws {
        // Quartz accepts at most 20 UTF-16 units per Unicode keyboard event.
        // Split on Unicode scalar boundaries; never touch the clipboard or IME.
        var chunk: [UniChar] = []
        func emit() throws {
            guard !chunk.isEmpty else { return }
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else {
                    throw ControlError("inputFailed")
                }
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                event.post(tap: .cghidEventTap)
            }
            chunk.removeAll(keepingCapacity: true)
        }
        for scalar in text.unicodeScalars {
            let units = Array(String(scalar).utf16)
            if chunk.count + units.count > 20 { try emit() }
            chunk.append(contentsOf: units)
        }
        try emit()
    }
}
