import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import os

extension KeyboardShortcuts.Name {
    static let dictate = Self("dictate")
}

/// Global trigger for dictation. Fn/Globe via a CGEventTap on `flagsChanged`,
/// or a user-chosen shortcut via KeyboardShortcuts. Also swallows Escape while
/// a session is active so the host app never sees it.
///
/// The tap lives on its own thread with its own run loop, so a busy main
/// thread can never delay or drop a key press.
@MainActor
final class HotkeyMonitor {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    var onEscape: () -> Void = {}
    /// True after `start()` if the global event tap could be installed.
    private(set) var tapInstalled = false

    /// Mirrors "a session is active" for the tap thread (decides whether to eat Escape).
    private let activeFlag = OSAllocatedUnfairLock(initialState: false)
    func setActive(_ on: Bool) { activeFlag.withLock { $0 = on } }

    private var tap: CFMachPort?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
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
            if !installTap(keyDownOnly: true) { installFallbackMonitor() }
        }
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let rl = tapRunLoop { CFRunLoopStop(rl) }
        tap = nil
        tapRunLoop = nil
        tapThread = nil
        for m in fallbackMonitors { NSEvent.removeMonitor(m) }
        fallbackMonitors.removeAll()
        KeyboardShortcuts.disable(.dictate)
        fnDown = false
        tapInstalled = false
    }

    // MARK: Fn via CGEventTap on a dedicated thread

    private func installTap(keyDownOnly: Bool = false) -> Bool {
        var mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        if !keyDownOnly { mask |= 1 << CGEventType.flagsChanged.rawValue }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
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
        tapInstalled = true

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [tap] in
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            let rl = CFRunLoopGetCurrent()
            CFRunLoopAddSource(rl, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            DispatchQueue.main.async { [weak self] in self?.tapRunLoop = rl }
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "murmur.hotkey"
        thread.qualityOfService = .userInteractive
        thread.start()
        tapThread = thread
        _ = ready.wait(timeout: .now() + 1)
        Log.app.info("Event tap installed on its own thread (\(keyDownOnly ? "keyDown" : "flagsChanged+keyDown"))")
        Log.d("event tap installed")
        return true
    }

    /// Runs on the tap thread. Keep it tiny; anything UI-related hops to main.
    nonisolated private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            Task { @MainActor in if let tap = self.tap { CGEvent.tapEnable(tap: tap, enable: true) } }
            return Unmanaged.passUnretained(event)

        case .flagsChanged:
            let isFn = event.flags.contains(.maskSecondaryFn)
            Task { @MainActor in self.fnChanged(isDown: isFn) }
            return Unmanaged.passUnretained(event)

        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == kVK_Escape, activeFlag.withLock({ $0 }) {
                Task { @MainActor in self.onEscape() }
                return nil   // swallowed
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
                guard let self, self.activeFlag.withLock({ $0 }) else { return }
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
