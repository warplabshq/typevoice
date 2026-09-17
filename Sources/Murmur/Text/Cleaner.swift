import Foundation

/// Deterministic, instant cleanup. Always runs; the LLM layer is optional on top.
enum Cleaner {
    /// What sits immediately before the caret in the target field, if known.
    struct Context: Sendable {
        var textBeforeCaret: String?
        static let unknown = Context(textBeforeCaret: nil)
    }

    private static let fillers: NSRegularExpression = {
        // Standalone hesitation sounds. Deliberately NOT "like" or "so" — too risky.
        let pattern = #"(?i)(?<![\w'])(?:u+m+|u+h+|uhm+|h+m+|m+hm+|er+m*|ah+|eh+)(?![\w'])[,.]?\s*"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let stutter: NSRegularExpression = {
        // Function words doubled are almost always stutters: "the the", "I I", "to to".
        // Content words ("very very", "no no", "really really") are left alone.
        let words = "the|a|an|i|to|of|in|it|is|and|that|this|we|you|they|he|she|was|were|on|at|for|with|my|our|your|so|but|if|as|be|are|have|has|had|do|did|can|will|would|just|not"
        return try! NSRegularExpression(pattern: #"(?i)\b("# + words + #")(?:[,\s]+\1\b)+"#)
    }()

    static func clean(_ raw: String, style: Style = .current) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }

        if style.removeFillers {
            s = fillers.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        if style.fixStutters {
            s = stutter.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1")
        }

        // Whitespace and punctuation hygiene.
        s = s.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([,.!?;:])(?=[A-Za-z])"#, with: "$1 ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^[,.;:\s]+"#, with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return "" }
        return s
    }

    /// Adjusts leading space and capitalisation so the text reads naturally
    /// where the caret is. With unknown context, capitalise the first letter.
    static func fit(_ text: String, to context: Context, style: Style = .current) -> String {
        var s = text
        let cap = style.casing == .sentence
        guard let before = context.textBeforeCaret else {
            return cap ? capitalizeFirst(s) : s
        }
        let trimmedBefore = before.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBefore.isEmpty {
            return cap ? capitalizeFirst(s) : s
        }
        let last = trimmedBefore.last!
        let endsSentence = ".!?\n".contains(last) || before.hasSuffix("\n")
        if endsSentence {
            if cap { s = capitalizeFirst(s) }
        } else if cap, !",;:(-—\"'“‘".contains(last) {
            // Mid-sentence: lowercase a leading capital unless it looks like a proper noun / "I".
            s = lowercaseFirstIfCommon(s)
        }
        // Leading space unless the caret already follows whitespace or an opener.
        let lastRaw = before.last!
        if !lastRaw.isWhitespace && !"(-—\"'“‘/[{".contains(lastRaw) {
            s = " " + s
        }
        return s
    }

    static func capitalizeFirst(_ s: String) -> String {
        guard let f = s.first, f.isLowercase else { return s }
        return f.uppercased() + s.dropFirst()
    }

    private static func lowercaseFirstIfCommon(_ s: String) -> String {
        guard let f = s.first, f.isUppercase else { return s }
        let firstWord = s.split(separator: " ", maxSplits: 1).first.map(String.init) ?? s
        let stripped = firstWord.trimmingCharacters(in: .punctuationCharacters)
        if stripped == "I" || stripped.hasPrefix("I'") { return s }
        // Two capitals in a row (acronym) or an internal capital → leave it.
        if stripped.count > 1, stripped.dropFirst().contains(where: { $0.isUppercase }) { return s }
        return f.lowercased() + s.dropFirst()
    }
}
