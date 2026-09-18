import AppKit
import Carbon.HIToolbox

/// A hold-to-dictate trigger: a lone modifier key (Right ⌘, Fn, …), a chord of
/// modifiers held together (⌥⌘), or a key with modifiers (⌥Space, ⌃⇧D, F13).
struct Shortcut: Codable, Equatable, Sendable {
    /// For modifier-only triggers this is one of the chord's keys (the one pressed last
    /// when recorded); `modifiers` then holds the flags of the *other* keys in the chord.
    var keyCode: UInt16
    /// CGEventFlags raw value, masked to ⌘⌥⌃⇧ and Fn.
    var modifiers: UInt64
    var isModifierOnly: Bool

    /// Every flag a modifier-only trigger needs held at once.
    var chordFlags: CGEventFlags {
        var f = CGEventFlags(rawValue: modifiers)
        if let own = Shortcut.flag(forModifierKey: keyCode) { f.insert(own) }
        return f
    }

    /// Whether a flagsChanged event for `code` concerns this modifier-only trigger.
    func involves(modifierKey code: UInt16) -> Bool {
        guard isModifierOnly else { return false }
        if code == keyCode { return true }
        guard let f = Shortcut.flag(forModifierKey: code) else { return false }
        return CGEventFlags(rawValue: modifiers).contains(f)
    }

    static let fn = Shortcut(keyCode: UInt16(kVK_Function), modifiers: 0, isModifierOnly: true)
    static let relevantFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]

    /// The flag a modifier key toggles, for modifier-only shortcuts.
    static func flag(forModifierKey code: UInt16) -> CGEventFlags? {
        switch Int(code) {
        case kVK_Command, kVK_RightCommand: return .maskCommand
        case kVK_Option, kVK_RightOption: return .maskAlternate
        case kVK_Control, kVK_RightControl: return .maskControl
        case kVK_Shift, kVK_RightShift: return .maskShift
        case kVK_Function: return .maskSecondaryFn
        default: return nil
        }
    }

    static func isModifierKey(_ code: UInt16) -> Bool { flag(forModifierKey: code) != nil }

    var description: String {
        if isModifierOnly {
            let others = Shortcut.symbols(CGEventFlags(rawValue: modifiers))
            return others.isEmpty ? Shortcut.modifierKeyName(keyCode) : others + " + " + Shortcut.modifierKeyName(keyCode)
        }
        return Shortcut.symbols(CGEventFlags(rawValue: modifiers)) + Shortcut.keyName(keyCode)
    }

    static func symbols(_ f: CGEventFlags) -> String {
        var s = ""
        if f.contains(.maskSecondaryFn) { s += "🌐" }
        if f.contains(.maskControl) { s += "⌃" }
        if f.contains(.maskAlternate) { s += "⌥" }
        if f.contains(.maskShift) { s += "⇧" }
        if f.contains(.maskCommand) { s += "⌘" }
        return s
    }

    static func modifierKeyName(_ code: UInt16) -> String {
        switch Int(code) {
        case kVK_Command: return "Left ⌘"
        case kVK_RightCommand: return "Right ⌘"
        case kVK_Option: return "Left ⌥"
        case kVK_RightOption: return "Right ⌥"
        case kVK_Control: return "Left ⌃"
        case kVK_RightControl: return "Right ⌃"
        case kVK_Shift: return "Left ⇧"
        case kVK_RightShift: return "Right ⇧"
        case kVK_Function: return "🌐"
        default: return "Key \(code)"
        }
    }

    static func keyName(_ code: UInt16) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_Help: "?⃝",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
            kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13",
            kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
            kVK_ANSI_KeypadEnter: "⌤", kVK_ANSI_KeypadClear: "⌧",
        ]
        if let s = special[Int(code)] { return s }
        // Printable keys via the current keyboard layout.
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return "Key \(code)" }
        let data = unsafeBitCast(ptr, to: CFData.self) as Data
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        var dead: UInt32 = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
            return UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  UInt32(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "Key \(code)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    // MARK: Persistence

    static var stored: Shortcut? {
        get {
            guard let data = UserDefaults.standard.data(forKey: Prefs.Key.customShortcut) else { return nil }
            return try? JSONDecoder().decode(Shortcut.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Prefs.Key.customShortcut)
            } else {
                UserDefaults.standard.removeObject(forKey: Prefs.Key.customShortcut)
            }
            NotificationCenter.default.post(name: .typevoiceTriggerChanged, object: nil)
        }
    }
}
