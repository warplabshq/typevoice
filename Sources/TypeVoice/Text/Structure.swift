import Foundation

/// Structure from speech: spoken commands ("new line", "bullet", "number two")
/// and, from the model's word timestamps, paragraph breaks at real pauses.
enum Structure {
    /// A word with when it was spoken. `gapBefore` is the silence before it.
    struct Word { var text: String; var gapBefore: TimeInterval }

    /// Turns a transcript into words with the pause before each, using token timings.
    /// Sub-word tokens are merged: a token that starts with the SentencePiece word
    /// boundary (▁) or a space starts a new word.
    static func words(text: String, tokens: [(token: String, start: TimeInterval, end: TimeInterval)]) -> [Word] {
        guard !tokens.isEmpty else {
            return text.split(separator: " ").map { Word(text: String($0), gapBefore: 0) }
        }
        var out: [Word] = []
        var lastEnd: TimeInterval = 0
        var current = ""
        var currentGap: TimeInterval = 0
        func flush() { if !current.isEmpty { out.append(Word(text: current, gapBefore: currentGap)); current = "" } }
        for t in tokens {
            let raw = t.token
            let startsWord = raw.hasPrefix("▁") || raw.hasPrefix(" ") || current.isEmpty
            let piece = raw.replacingOccurrences(of: "▁", with: "").trimmingCharacters(in: .whitespaces)
            if startsWord {
                flush()
                currentGap = max(0, t.start - lastEnd)
            }
            current += piece
            lastEnd = max(lastEnd, t.end)
        }
        flush()
        // If timings don't line up with the text (e.g. normalisation changed it), fall back.
        let joined = out.map(\.text).joined(separator: " ")
        if joined.count < text.count / 2 { return text.split(separator: " ").map { Word(text: String($0), gapBefore: 0) } }
        return out
    }

    /// Paragraph breaks: a pause of at least `pause` seconds after a sentence end.
    static func paragraphs(_ words: [Word], pause: TimeInterval) -> String {
        var s = ""
        for (i, w) in words.enumerated() {
            if i > 0 {
                let prev = words[i - 1].text
                let endsSentence = prev.last.map { ".!?".contains($0) } ?? false
                s += (endsSentence && w.gapBefore >= pause) ? "\n\n" : " "
            }
            s += w.text
        }
        return s
    }

    // MARK: Spoken commands

    // Commas/colons before a command are dropped; a period stays (it ends the sentence).
    private static let newParagraph = try! NSRegularExpression(pattern: #"(?i)[,:;]?\s*\b(?:new|next)\s+paragraph\b[,.:]?\s*"#)
    private static let newLine = try! NSRegularExpression(pattern: #"(?i)[,:;]?\s*\b(?:new|next)\s+line\b[,.:]?\s*"#)
    private static let bullet = try! NSRegularExpression(pattern: #"(?i)[,:;]?\s*\b(?:bullet\s+point|bullet|dash\s+point)\b[,.:]?\s*"#)
    private static let numbered = try! NSRegularExpression(pattern: #"(?i)[,:;]?\s*\b(?:number|point|step|item)\s+(one|two|three|four|five|six|seven|eight|nine|ten|\d{1,2})\b[,.:]?\s*"#)

    /// Applies spoken formatting commands. Lists only form when two or more markers appear,
    /// so "number one priority" in normal speech stays as it is.
    static func commands(_ text: String) -> String {
        var s = text
        s = newParagraph.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "\n\n")
        s = newLine.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "\n")

        let bullets = bullet.matches(in: s, range: NSRange(s.startIndex..., in: s))
        if bullets.count >= 2 {
            s = bullet.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "\n- ")
        }
        let nums = numbered.matches(in: s, range: NSRange(s.startIndex..., in: s))
        if nums.count >= 2 {
            // Replace from the end so ranges stay valid; renumber sequentially.
            var result = s
            for (idx, m) in nums.enumerated().reversed() {
                let r = Range(m.range, in: result)!
                result.replaceSubrange(r, with: "\n\(idx + 1). ")
            }
            s = result
        }
        // Tidy: capitalise list items, no blank first line, collapse runs of blank lines.
        s = capitalizeListItems(s)
        s = s.replacingOccurrences(of: #"^\s*\n+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        return s
    }

    private static func capitalizeListItems(_ s: String) -> String {
        let re = try! NSRegularExpression(pattern: #"(\n(?:- |\d+\. ))(\p{Ll})"#)
        let ns = s as NSString
        var out = s
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let letter = ns.substring(with: m.range(at: 2)).uppercased()
            out = (out as NSString).replacingCharacters(in: m.range(at: 2), with: letter)
        }
        return out
    }
}
