import AppKit
import Carbon.HIToolbox
import os

/// Global trigger for dictation. One CGEventTap on a dedicated thread watches
/// modifier changes and key presses, matching either a lone modifier key
/// (🌐, Right ⌘, …) or a key combo (⌥Space, F13). It also swallows Escape while
/// a session is active so the host app never sees it.
@MainActor
final class HotkeyMonitor {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    var onEscape: () -> Void = {}
    /// A key was pressed while a lone-modifier trigger is held: it's a shortcut, not dictation.
    var onChord: () -> Void = {}
    /// True after `start()` if the global event tap could be installed.
    private(set) var tapInstalled = false

    /// State shared with the tap thread.
    private struct Shared {
        var active = false            // a session is running (eat Escape)
        var paused = false            // the recorder is listening; ignore everything
        var shortcut: Shortcut = .fn
        var isDown = false
        /// Whether the trigger's own key (say Left ⌘) is physically down, tracked from its
        /// flagsChanged events; flags alone can't tell Left ⌘ from Right ⌘.
        var primaryDown = false
    }
    private let shared = OSAllocatedUnfairLock(initialState: Shared())
    func setActive(_ on: Bool) { shared.withLock { $0.active = on } }
    func setPaused(_ on: Bool) { shared.withLock { $0.paused = on; if on { $0.isDown = false } } }

    private var tap: CFMachPort?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var fallbackMonitors: [Any] = []

    var currentShortcut: Shortcut { Prefs.trigger == .custom ? (Shortcut.stored ?? .fn) : .fn }

    func start() {
        stop()
        let sc = currentShortcut
        shared.withLock { $0.shortcut = sc; $0.isDown = false; $0.primaryDown = false }
        if !installTap() { installFallbackMonitor() }
        Log.d("hotkey: \(sc.description)")
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let rl = tapRunLoop { CFRunLoopStop(rl) }
        tap = nil
        tapRunLoop = nil
        tapThread = nil
        for m in fallbackMonitors { NSEvent.removeMonitor(m) }
        fallbackMonitors.removeAll()
        tapInstalled = false
    }

    // MARK: CGEventTap on a dedicated thread

    private func installTap() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
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
        thread.name = "typevoice.hotkey"
        thread.qualityOfService = .userInteractive
        thread.start()
        tapThread = thread
        _ = ready.wait(timeout: .now() + 1)
        Log.d("event tap installed")
        return true
    }

    /// Runs on the tap thread. Keep it tiny; anything UI-related hops to main.
    nonisolated private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            Task { @MainActor in if let tap = self.tap { CGEvent.tapEnable(tap: tap, enable: true) } }
            return pass

        case .flagsChanged:
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            let action: Bool? = shared.withLock { s -> Bool? in
                // Only events for one of the chord's own keys count, so a plain ⌘ press
                // never wakes an ⌥⌘ trigger and Left/Right stay distinct.
                guard !s.paused, s.shortcut.involves(modifierKey: code) else { return nil }
                if code == s.shortcut.keyCode, let own = Shortcut.flag(forModifierKey: code) { s.primaryDown = flags.contains(own) }
                let down = s.primaryDown && flags.contains(CGEventFlags(rawValue: s.shortcut.modifiers))
                guard down != s.isDown else { return nil }
                s.isDown = down
                return down
            }
            if let down = action { Task { @MainActor in down ? self.onPress() : self.onRelease() } }
            return pass

        case .keyDown:
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let repeatKey = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let mods = event.flags.intersection(Shortcut.relevantFlags).rawValue
            let chord: Bool = shared.withLock { s in
                guard !s.paused, s.shortcut.isModifierOnly, s.isDown, code != UInt16(kVK_Escape),
                      !Shortcut.isModifierKey(code) else { return false }   // a modifier's own key-down is not a chord
                s.isDown = false          // the eventual modifier release must not finish a session
                return true
            }
            if chord { Task { @MainActor in self.onChord() }; return pass }
            let (isEscape, matched): (Bool, Bool) = shared.withLock { s in
                if s.paused { return (false, false) }
                if code == UInt16(kVK_Escape), s.active { return (true, false) }
                guard !s.shortcut.isModifierOnly, code == s.shortcut.keyCode, mods == s.shortcut.modifiers else { return (false, false) }
                if repeatKey || s.isDown { return (false, true) }   // swallow repeats, no new press
                s.isDown = true
                return (false, true)
            }
            if isEscape { Task { @MainActor in self.onEscape() }; return nil }
            if matched {
                if !repeatKey { Task { @MainActor in self.onPress() } }
                return nil   // the host app never sees the combo
            }
            return pass

        case .keyUp:
            let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let matched: Bool = shared.withLock { s in
                guard !s.paused, !s.shortcut.isModifierOnly, code == s.shortcut.keyCode, s.isDown else { return false }
                s.isDown = false
                return true
            }
            if matched { Task { @MainActor in self.onRelease() }; return nil }
            return pass

        default:
            return pass
        }
    }

    // MARK: Fallback (no tap): NSEvent global monitors. Cannot swallow keys.

    private func installFallbackMonitor() {
        Log.app.warning("Using NSEvent global monitors; Escape and combos will reach the host app")
        let f = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            guard let self else { return }
            let sc = self.shared.withLock { $0.shortcut }
            guard sc.involves(modifierKey: e.keyCode) else { return }
            let flags = CGEventFlags(rawValue: UInt64(e.modifierFlags.rawValue))
            let changed: Bool = self.shared.withLock { s in
                if e.keyCode == sc.keyCode, let own = Shortcut.flag(forModifierKey: e.keyCode) { s.primaryDown = flags.contains(own) }
                let down = s.primaryDown && flags.contains(CGEventFlags(rawValue: sc.modifiers))
                if s.paused || s.isDown == down { return false }
                s.isDown = down; return true
            }
            let down = self.shared.withLock { $0.isDown }
            if changed { Task { @MainActor in down ? self.onPress() : self.onRelease() } }
        }
        if let f { fallbackMonitors.append(f) }
        let k = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] e in
            guard let self else { return }
            let sc = self.shared.withLock { $0.shortcut }
            if e.type == .keyDown, e.keyCode == UInt16(kVK_Escape), self.shared.withLock({ $0.active }) {
                Task { @MainActor in self.onEscape() }; return
            }
            guard !sc.isModifierOnly, e.keyCode == sc.keyCode else { return }
            let mods = UInt64(e.modifierFlags.rawValue) & Shortcut.relevantFlags.rawValue
            if e.type == .keyDown {
                guard !e.isARepeat, mods == sc.modifiers else { return }
                Task { @MainActor in self.onPress() }
            } else {
                Task { @MainActor in self.onRelease() }
            }
        }
        if let k { fallbackMonitors.append(k) }
    }
}
