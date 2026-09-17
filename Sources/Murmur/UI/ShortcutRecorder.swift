import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then press what you want to hold. A lone modifier (Right ⌘, Right ⌥,
/// Fn) or a key with modifiers (⌥Space, F13). Esc cancels.
struct ShortcutRecorder: View {
    @State private var recording = false
    @State private var current = Shortcut.stored
    @State private var monitor: Any?
    @State private var pendingModifier: UInt16?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                recording ? stop() : start()
            } label: {
                HStack(spacing: 6) {
                    if recording {
                        Circle().fill(.red).frame(width: 6, height: 6)
                        Text("Press a key or hold a modifier…")
                    } else {
                        Text(current?.description ?? "Record shortcut")
                            .font(.system(size: 13, weight: current == nil ? .regular : .semibold))
                    }
                }
                .frame(minWidth: 150)
            }
            .buttonStyle(.bordered)
            if current != nil, !recording {
                Button {
                    Shortcut.stored = nil
                    current = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        pendingModifier = nil
        NotificationCenter.default.post(name: .murmurPauseHotkey, object: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { e in
            handle(e) ? nil : e
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        NotificationCenter.default.post(name: .murmurPauseHotkey, object: false)
    }

    /// Returns true when the event was consumed.
    private func handle(_ e: NSEvent) -> Bool {
        guard recording else { return false }
        switch e.type {
        case .flagsChanged:
            let code = e.keyCode
            guard Shortcut.isModifierKey(code) else { return true }
            let flag = Shortcut.flag(forModifierKey: code)!
            let down = CGEventFlags(rawValue: UInt64(e.modifierFlags.rawValue)).contains(flag)
            if down {
                pendingModifier = code           // wait: maybe a key follows
            } else if pendingModifier == code {
                save(Shortcut(keyCode: code, modifiers: 0, isModifierOnly: true))   // released alone
            }
            return true
        case .keyDown:
            if e.keyCode == UInt16(kVK_Escape) { stop(); return true }
            let mods = CGEventFlags(rawValue: UInt64(e.modifierFlags.rawValue)).intersection(Shortcut.relevantFlags)
            let isFKey = (Int(e.keyCode) >= kVK_F1 && Int(e.keyCode) <= kVK_F12) || [kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20].contains(Int(e.keyCode))
            guard !mods.isEmpty || isFKey else { NSSound.beep(); return true }   // a bare letter would break typing
            save(Shortcut(keyCode: e.keyCode, modifiers: mods.rawValue, isModifierOnly: false))
            return true
        default:
            return false
        }
    }

    private func save(_ s: Shortcut) {
        Shortcut.stored = s
        current = s
        stop()
    }
}

extension Notification.Name {
    /// Object: Bool. True pauses the global trigger while the recorder listens.
    static let murmurPauseHotkey = Notification.Name("murmur.pauseHotkey")
}
