import Foundation
import KeyboardShortcuts
import SwiftUI

/// UserDefaults-backed settings. Views bind through `@AppStorage(Prefs.Key…)`,
/// controllers read through the static accessors so there is one source of truth.
enum Prefs {
    enum Key {
        static let trigger = "trigger"                 // "fn" | "custom"
        static let smartCleanup = "smartCleanup"       // Bool
        static let sounds = "sounds"                   // Bool
        static let haptics = "haptics"                 // Bool
        static let showMenuBarIcon = "showMenuBarIcon" // Bool
        static let hasOnboarded = "hasOnboarded"       // Bool
        static let insertion = "insertion"             // "auto" | "paste"
        static let casing = "style.casing"
        static let punctuation = "style.punctuation"
        static let tone = "style.tone"
        static let removeFillers = "style.removeFillers"
        static let fixStutters = "style.fixStutters"
        static let hudPosition = "hudPosition"         // HUDPosition
        static let accent = "accent"                   // Accent
        static let numbersAsDigits = "numbersAsDigits" // Bool
        static let showPreview = "showPreview"         // Bool: typed text in the indicator
    }

    enum HUDPosition: String, CaseIterable, Identifiable {
        case topLeft, topCenter, topRight, bottomLeft, bottomCenter, bottomRight
        var id: String { rawValue }
        var isTop: Bool { self == .topLeft || self == .topCenter || self == .topRight }
        var horizontal: Int { switch self { case .topLeft, .bottomLeft: return 0; case .topCenter, .bottomCenter: return 1; default: return 2 } }
        var label: String {
            switch self {
            case .topLeft: return "Top left"
            case .topCenter: return "Top centre"
            case .topRight: return "Top right"
            case .bottomLeft: return "Bottom left"
            case .bottomCenter: return "Bottom centre"
            case .bottomRight: return "Bottom right"
            }
        }
    }

    enum Accent: String, CaseIterable, Identifiable {
        case mono, system, blue, purple, pink, green, amber
        var id: String { rawValue }
        var label: String {
            switch self {
            case .mono: return "None"
            case .system: return "System"
            case .blue: return "Blue"
            case .purple: return "Purple"
            case .pink: return "Pink"
            case .green: return "Green"
            case .amber: return "Amber"
            }
        }
    }

    enum Trigger: String, CaseIterable, Identifiable {
        case fn, custom
        var id: String { rawValue }
    }

    enum Insertion: String, CaseIterable, Identifiable {
        case auto, paste
        var id: String { rawValue }
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.trigger: Trigger.fn.rawValue,
            Key.smartCleanup: true,
            Key.sounds: true,
            Key.haptics: true,
            Key.showMenuBarIcon: true,
            Key.hasOnboarded: false,
            Key.insertion: Insertion.auto.rawValue,
            Key.casing: Style.Casing.sentence.rawValue,
            Key.punctuation: Style.Punctuation.full.rawValue,
            Key.tone: Style.Tone.natural.rawValue,
            Key.removeFillers: true,
            Key.fixStutters: true,
            Key.hudPosition: HUDPosition.bottomCenter.rawValue,
            Key.accent: Accent.mono.rawValue,
            Key.numbersAsDigits: true,
            Key.showPreview: true,
        ])
    }

    private static var d: UserDefaults { .standard }

    static var trigger: Trigger { Trigger(rawValue: d.string(forKey: Key.trigger) ?? "") ?? .fn }
    static var smartCleanup: Bool { d.bool(forKey: Key.smartCleanup) }
    static var sounds: Bool { d.bool(forKey: Key.sounds) }
    static var haptics: Bool { d.bool(forKey: Key.haptics) }
    static var showMenuBarIcon: Bool { d.bool(forKey: Key.showMenuBarIcon) }
    static var hasOnboarded: Bool { d.bool(forKey: Key.hasOnboarded) }
    static var insertion: Insertion { Insertion(rawValue: d.string(forKey: Key.insertion) ?? "") ?? .auto }
    static var casing: Style.Casing { Style.Casing(rawValue: d.string(forKey: Key.casing) ?? "") ?? .sentence }
    static var punctuation: Style.Punctuation { Style.Punctuation(rawValue: d.string(forKey: Key.punctuation) ?? "") ?? .full }
    static var tone: Style.Tone { Style.Tone(rawValue: d.string(forKey: Key.tone) ?? "") ?? .natural }
    static var removeFillers: Bool { d.bool(forKey: Key.removeFillers) }
    static var fixStutters: Bool { d.bool(forKey: Key.fixStutters) }
    static var hudPosition: HUDPosition { HUDPosition(rawValue: d.string(forKey: Key.hudPosition) ?? "") ?? .bottomCenter }
    static var accent: Accent { Accent(rawValue: d.string(forKey: Key.accent) ?? "") ?? .mono }
    static var numbersAsDigits: Bool { d.bool(forKey: Key.numbersAsDigits) }
    static var showPreview: Bool { d.bool(forKey: Key.showPreview) }

    /// "🌐" or the custom shortcut, for UI copy.
    static var triggerLabel: String {
        if trigger == .custom, let sc = KeyboardShortcuts.getShortcut(for: .dictate) { return sc.description }
        return "🌐"
    }

    /// Wipes every preference. Used by "Delete everything".
    static func reset() {
        if let id = Bundle.main.bundleIdentifier { d.removePersistentDomain(forName: id) }
        registerDefaults()
    }
}
