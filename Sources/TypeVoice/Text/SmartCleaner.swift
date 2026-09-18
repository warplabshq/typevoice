import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model as a dictation editor. Bounded by a hard deadline so
/// it can never make insertion feel slow; on any doubt we return nil and the
/// caller ships the deterministic result.
@MainActor
final class SmartCleaner {
    static let deadline: Duration = .milliseconds(1200)

    private static func instructions(style: Style, dictionary: [String]) -> String {
        var lines = [
            "You are a dictation editor. The user dictated text with their voice; make it read as if they had typed it.",
            "Rules:",
            "- Remove hesitations (um, uh, you know, I mean) and false starts." ,
            "- If the speaker corrects themselves, keep only the correction. \"Tuesday, no wait, Wednesday\" becomes \"Wednesday\".",
            "- Fix punctuation and capitalisation.",
            "- Keep every fact, name, number and word choice. Never add, summarise, translate or answer anything.",
            "- Spoken formatting words become symbols: \"new line\" → a line break, \"comma\" → \",\", \"period\" → \".\".",
            "- Output only the edited text. No quotes, no preamble, no explanation.",
        ]
        lines += style.instructionLines.map { "- " + $0 }
        if !dictionary.isEmpty {
            let list = dictionary.prefix(60).joined(separator: ", ")
            lines.append("- These names are spelled exactly like this, fix anything that sounds like them: " + list)
        }
        return lines.joined(separator: "\n")
    }

    /// The instructions the current session was built with; a change forces a new session.
    private var sessionKey = ""
    var style: Style = .current
    var dictionary: [String] = []

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?
    #endif

    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    /// The definite answer, in the OS's own words, for the Settings indicator.
    enum Status: Equatable {
        case ready, off, downloading, notEligible, other(String)
        var isReady: Bool { self == .ready }
        var title: String {
            switch self {
            case .ready: "Apple Intelligence is ready"
            case .off: "Apple Intelligence is off"
            case .downloading: "Apple Intelligence hasn't finished downloading"
            case .notEligible: "This Mac can't run Apple Intelligence"
            case .other: "Apple Intelligence isn't available"
            }
        }
        var detail: String {
            switch self {
            case .ready: "Sentences are tidied by Apple's on-device model. Nothing is sent anywhere."
            case .off: "Turn it on in System Settings › Siri (the pane is called Apple Intelligence & Siri on some Macs). Until then, cleanup uses the built-in rules."
            case .downloading: "macOS downloads the model only once Apple Intelligence is switched on, while the Mac is on power and Wi-Fi. If the Siri pane shows no Apple Intelligence switch at all, set Siri › Language to the same language as the Mac (both English (United States), say): Apple requires them to match. This turns green by itself when it's done; until then, cleanup uses the built-in rules."
            case .notEligible: "Cleanup uses the built-in rules, which do most of the work."
            case .other(let r): "\(r). Cleanup uses the built-in rules meanwhile."
            }
        }
        var canOpenSettings: Bool { self == .off || self == .downloading }
    }

    static var status: Status {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return .ready
        case .unavailable(let r):
            switch r {
            case .appleIntelligenceNotEnabled: return .off
            case .modelNotReady: return .downloading
            case .deviceNotEligible: return .notEligible
            @unknown default: return .other(String(describing: r))
            }
        }
        #else
        return .other("Requires macOS 26")
        #endif
    }

    var unavailableReason: String? {
        let s = Self.status
        return s.isReady ? nil : s.title
    }


    /// Creates and prewarms a fresh single-use session.
    func prewarm() {
        #if canImport(FoundationModels)
        guard isAvailable else { return }
        let text = Self.instructions(style: style, dictionary: dictionary)
        sessionKey = text
        let s = LanguageModelSession(instructions: text)
        s.prewarm()
        session = s
        #endif
    }

    /// Returns the cleaned text, or nil if the model is unavailable, times out,
    /// or produces something that does not look like an edit of the input.
    func clean(_ text: String) async -> String? {
        #if canImport(FoundationModels)
        guard isAvailable else { return nil }
        let words = text.split(separator: " ").count
        guard words >= 3 else { return nil }              // nothing to fix
        if session == nil || sessionKey != Self.instructions(style: style, dictionary: dictionary) { prewarm() }
        guard let s = session else { return nil }
        session = nil                                     // sessions are one-shot here
        defer { prewarm() }                               // next one warms in the background

        let t0 = ContinuousClock.now
        let options = GenerationOptions(
            sampling: .greedy,
            maximumResponseTokens: max(64, Int(Double(text.count) / 2.5) + 32)
        )
        let work = Task { try await s.respond(to: text, options: options).content }
        let timer = Task { try await Task.sleep(for: Self.deadline); work.cancel() }
        defer { timer.cancel() }

        guard let out = try? await work.value else {
            Log.asr.info("smart cleanup skipped (timeout/cancel/error)")
            return nil
        }
        Log.timing("smart.clean", since: t0)
        return Self.validate(input: text, output: out)
        #else
        return nil
        #endif
    }

    /// Reject outputs that are empty, wrapped in quotes, or wildly different in length.
    static func validate(input: String, output: String) -> String? {
        var o = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if o.hasPrefix("\"") && o.hasSuffix("\"") && o.count > 2 { o = String(o.dropFirst().dropLast()) }
        guard !o.isEmpty else { return nil }
        let ratio = Double(o.count) / Double(max(input.count, 1))
        guard ratio > 0.4 && ratio < 1.5 else { return nil }
        let lower = o.lowercased()
        for bad in ["here is", "here's the", "cleaned text", "sure,", "as an ai"] where lower.hasPrefix(bad) {
            return nil
        }
        return o
    }
}
