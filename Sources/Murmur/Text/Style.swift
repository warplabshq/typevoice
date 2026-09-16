import Foundation

/// How the user wants their text to read. Deterministic parts are applied by
/// `Cleaner`; the tone goes into the on-device model's instructions.
struct Style: Sendable, Equatable {
    enum Casing: String, CaseIterable, Identifiable, Sendable {
        case sentence, lowercase, asSpoken
        var id: String { rawValue }
        var label: String {
            switch self {
            case .sentence: return "Sentence case"
            case .lowercase: return "all lowercase"
            case .asSpoken: return "Leave as recognised"
            }
        }
    }

    enum Punctuation: String, CaseIterable, Identifiable, Sendable {
        case full, light, none
        var id: String { rawValue }
        var label: String {
            switch self {
            case .full: return "Full"
            case .light: return "Light"
            case .none: return "None"
            }
        }
        var detail: String {
            switch self {
            case .full: return "Commas, periods, question marks. Reads like writing."
            case .light: return "Punctuation inside the sentence, no period at the end. Reads like a message."
            case .none: return "No punctuation at all."
            }
        }
    }

    enum Tone: String, CaseIterable, Identifiable, Sendable {
        case natural, casual, formal
        var id: String { rawValue }
        var label: String {
            switch self {
            case .natural: return "As spoken"
            case .casual: return "Casual"
            case .formal: return "Formal"
            }
        }
        var detail: String {
            switch self {
            case .natural: return "Keeps your words. Only fixes what a careful typist would."
            case .casual: return "Contractions, relaxed phrasing, keeps the energy."
            case .formal: return "No contractions, complete sentences, tidy phrasing."
            }
        }
    }

    var casing: Casing = .sentence
    var punctuation: Punctuation = .full
    var tone: Tone = .natural
    var removeFillers = true

    static var current: Style {
        Style(casing: Prefs.casing, punctuation: Prefs.punctuation, tone: Prefs.tone, removeFillers: Prefs.removeFillers)
    }

    /// Deterministic finishing pass, applied last so the LLM cannot undo it.
    func finish(_ text: String) -> String {
        var s = text
        switch punctuation {
        case .full:
            break
        case .light:
            s = s.replacingOccurrences(of: #"[.]+\s*$"#, with: "", options: .regularExpression)
        case .none:
            s = s.replacingOccurrences(of: #"[,.!?;:…]"#, with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        }
        switch casing {
        case .lowercase:
            s = s.lowercased()
        case .sentence, .asSpoken:
            break
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Extra lines for the model's instructions.
    var instructionLines: [String] {
        var out: [String] = []
        switch tone {
        case .natural: out.append("Keep the speaker's own words and rhythm. Do not rephrase.")
        case .casual: out.append("Casual tone: use contractions, keep it relaxed and friendly, but do not add words.")
        case .formal: out.append("Formal tone: expand contractions, complete sentences, no slang, still no added content.")
        }
        switch punctuation {
        case .full: out.append("Use full punctuation: commas, periods, question marks.")
        case .light: out.append("Use light punctuation: commas where needed, no period at the very end.")
        case .none: out.append("Do not use any punctuation.")
        }
        if casing == .lowercase { out.append("Write everything in lowercase, including 'i' and names.") }
        if !removeFillers { out.append("Keep filler words like um and uh exactly as spoken.") }
        return out
    }
}
