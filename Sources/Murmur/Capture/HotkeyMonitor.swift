import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let dictate = Self("dictate")
}

/// Global trigger for dictation. Fn/Globe via a CGEventTap on `flagsChanged`,
/// or a user-chosen shortcut via KeyboardShortcuts. Also swallows Escape while
/// a session is active so the host app never sees it.
@MainActor
final class HotkeyMonitor {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    var onEscape: () -> Void = {}
    /// Return true while a session is active so Escape gets consumed.
    var isActive: () -> Bool = { false }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fallbackMonitors: [Any] = []
    private var fnDown = false
    private var trigger: Prefs.Trigger = .fn

    func start() {
        stop()
        trigger = Prefs.trigger
        switch trigger {
        case .fn:
            if !installTap() { installFallbackMonitor() }
        case .custom:
            installCustomShortcut()
            // Still need Escape handling; tap for keyDown only if we can.
            if !installTap(keyDownOnly: true) { installFallbackMonitor() }
        }
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        runLoopSource = nil
        for m in fallbackMonitors { NSEvent.removeMonitor(m) }
        fallbackMonitors.removeAll()
        KeyboardShortcuts.disable(.dictate)
        fnDown = false
    }

    // MARK: Fn via CGEventTap

    private func installTap(keyDownOnly: Bool = false) -> Bool {
        var mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        if !keyDownOnly { mask |= 1 << CGEventType.flagsChanged.rawValue }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handle(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            Log.app.error("CGEventTap creation failed (Accessibility not granted?)")
            Log.d("event tap FAILED")
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.app.info("Event tap installed (\(keyDownOnly ? "keyDown" : "flagsChanged+keyDown"))")
        Log.d("event tap installed")
        return true
    }

    /// Runs on the main run loop (the tap source is scheduled there). Keep it tiny.
    nonisolated private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            MainActor.assumeIsolated {
                if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            }
            return Unmanaged.passUnretained(event)

        case .flagsChanged:
            let isFn = event.flags.contains(.maskSecondaryFn)
            MainActor.assumeIsolated { fnChanged(isDown: isFn) }
            return Unmanaged.passUnretained(event)

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == kVK_Escape {
                let consumed = MainActor.assumeIsolated { () -> Bool in
                    guard isActive() else { return false }
                    onEscape()
                    return true
                }
                if consumed { return nil }
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func fnChanged(isDown: Bool) {
        guard trigger == .fn, isDown != fnDown else { return }
        fnDown = isDown
        isDown ? onPress() : onRelease()
    }

    // MARK: Fallback (no tap): NSEvent global monitors, cannot swallow Escape.

    private func installFallbackMonitor() {
        Log.app.warning("Using NSEvent global monitors; Escape will reach the host app")
        if trigger == .fn {
            let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
                let down = e.modifierFlags.contains(.function)
                Task { @MainActor in self?.fnChanged(isDown: down) }
            }
            if let m { fallbackMonitors.append(m) }
        }
        let k = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.keyCode == UInt16(kVK_Escape) else { return }
            Task { @MainActor in
                guard let self, self.isActive() else { return }
                self.onEscape()
            }
        }
        if let k { fallbackMonitors.append(k) }
    }

    // MARK: Custom shortcut

    private func installCustomShortcut() {
        KeyboardShortcuts.enable(.dictate)
        KeyboardShortcuts.onKeyDown(for: .dictate) { [weak self] in self?.onPress() }
        KeyboardShortcuts.onKeyUp(for: .dictate) { [weak self] in self?.onRelease() }
    }
}
