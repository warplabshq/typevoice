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

    var unavailableReason: String? {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(let r):
            switch r {
            case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in System Settings."
            case .modelNotReady: return "Apple Intelligence is still downloading."
            case .deviceNotEligible: return "This Mac can't run Apple Intelligence."
            @unknown default: return "Apple Intelligence isn't available."
            }
        }
        #else
        return "Requires macOS 26."
        #endif
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
