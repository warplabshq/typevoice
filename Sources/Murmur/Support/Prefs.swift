import Foundation
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
        static let hudPosition = "hudPosition"         // "bottom" | "top"
    }

    enum HUDPosition: String, CaseIterable, Identifiable {
        case bottom, top
        var id: String { rawValue }
        var label: String { self == .bottom ? "Bottom of screen" : "Top of screen" }
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
            Key.hudPosition: HUDPosition.bottom.rawValue,
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
    static var hudPosition: HUDPosition { HUDPosition(rawValue: d.string(forKey: Key.hudPosition) ?? "") ?? .bottom }

    /// Wipes every preference. Used by "Delete everything".
    static func reset() {
        if let id = Bundle.main.bundleIdentifier { d.removePersistentDomain(forName: id) }
        registerDefaults()
    }
}
