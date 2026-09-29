import Foundation

/// Thinking out loud, taken out: "you know", "I mean", "like", "anyway" when they only fill
/// a gap, and the restarts a person makes while finding the sentence ("I'm waiting for, I'm
/// waiting for a…", "simply not simply not", "we can use re— we can use recent"). Only where
/// the words can't be carrying meaning: "Do you know the answer", "what I mean is", "I like it"
/// stay. Runs with Remove fillers; word lists and one pass over the tokens, microseconds.
enum Disfluency {
    private static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: "(?i)" + p) }
    private static let aside = #"(?:you know|i mean|like|anyway|anyways|i don't know|i dunno|you see)"#
    private static let rules: [(NSRegularExpression, String)] = [
        // "they can, you know, put it out": after a word that never takes a comma, both commas go.
        (re(#"\b(can|could|will|would|should|to|the|a|an|of|and|that|with|for|is|are|was|were|be|just|some|my|your|our|their|we|i|you|they|it|this|really|very)\s*,\s*"# + aside + #"\s*,\s*"#), "$1 "),
        // ", you know," / ", I don't know," in the middle: one comma is enough.
        (re(#",\s*"# + aside + #"\s*,"#), ","),
        // Trailing: "…a white background, I don't know." → "…a white background."
        (re(#",\s*(?:you know|i mean|anyway|anyways|i don't know|i dunno)\s*(?=[.?!]|$)"#), ""),
        // Opening a sentence: "Anyway, …", "I mean, …", "Like, …", "You know, …".
        (re(#"(^|[.?!]\s+|\n)(?:you know|i mean|like|anyway|anyways|so yeah|yeah so|so anyway|and yeah),\s*"#), "$1"),
        // "Also like maybe", "so like the": the like carries nothing.
        (re(#"\b(so|and|but|also|or|just)\s+like,?\s+(?=(?:maybe|you|i|we|it|the|a|if|when|now|that's|it's|this|there)\b)"#), "$1 "),
        (re(#",\s*,"#), ","),
        (re(#",\s*([.?!])"#), "$1"),
    ]

    static func apply(_ text: String) -> String {
        var s = text
        for (r, t) in rules { s = r.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: t) }
        return s.components(separatedBy: "\n").map(tokens).joined(separator: "\n")
    }

    /// "you know" with no commas, repeated phrases, and a cut-off start of a word.
    private static let keepBeforeYouKnow: Set<String> = ["do", "don't", "did", "didn't", "if", "as", "what", "would", "will", "can", "could", "let",
        "whether", "should", "may", "might", "where", "how", "who", "when", "why", "that", "because", "since", "unless", "than", "whom", "cause",
        "know", "knew", "think", "thought", "hope", "guess", "bet", "believe", "sure", "feel", "felt", "say", "said", "mean", "suppose", "assume", "wish", "trust", "see"]
    private static let startsClause: Set<String> = ["i", "i'm", "i've", "i'll", "i'd", "it", "it's", "we", "we're", "they", "they're", "the", "this", "that",
        "my", "a", "like", "he", "she", "you're", "there", "so", "and", "but", "just", "maybe", "some", "to", "in", "on", "for", "at"]
    private static let shortWords: Set<String> = ["a", "an", "in", "on", "at", "to", "is", "it", "as", "be", "do", "go", "no", "so", "we", "he", "me", "my",
        "up", "us", "or", "of", "by", "if", "am", "i", "the", "and", "for", "are", "but", "not", "you", "all", "can", "her", "was", "one", "our",
        "out", "day", "get", "has", "him", "his", "how", "man", "new", "now", "old", "see", "two", "way", "who", "did", "its", "let", "put", "say",
        "she", "too", "use", "any", "few", "got", "own", "try", "ask", "big", "bit", "end", "far", "yes", "yet", "off", "run", "set", "top", "why",
        "also", "just", "some", "will", "with", "that", "this", "have", "from", "they", "what", "when", "your", "more", "into", "over", "only", "back"]

    private static func norm(_ w: String) -> String {
        w.lowercased().replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: CharacterSet(charactersIn: ",;:\"“”()"))
    }
    private static func endsSentence(_ w: String) -> Bool { w.last.map { ".?!".contains($0) } ?? false }

    private static func tokens(_ line: String) -> String {
        var t = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard t.count >= 3 else { return line }
        var changed = true
        while changed {
            changed = false
            // "for you know I'm", "it kind of you know it": no commas, but only filling.
            var i = 0
            while i + 2 < t.count {
                if norm(t[i]) == "you", norm(t[i + 1]).trimmingCharacters(in: .punctuationCharacters) == "know", !endsSentence(t[i + 1]),
                   i == 0 || !keepBeforeYouKnow.contains(norm(t[i - 1])) || endsSentence(t[i - 1]),
                   startsClause.contains(norm(t[i + 2])) {
                    t.removeSubrange(i...(i + 1)); changed = true; continue
                }
                i += 1
            }
            // A phrase said twice in a row while finding the words: "simply not simply not".
            // Two words or more; a single doubled word is the stutter rule's business.
            outer: for n in stride(from: 6, through: 2, by: -1) where t.count >= 2 * n {
                for i in 0...(t.count - 2 * n) {
                    let a = t[i..<(i + n)], b = t[(i + n)..<(i + 2 * n)]
                    // "fully safe, as safe as possible" is emphasis, not a restart: no comma inside.
                    guard !a.contains(where: { endsSentence($0) || $0.hasSuffix(",") }) else { continue }
                    if zip(a, b).allSatisfy({ norm($0).trimmingCharacters(in: .punctuationCharacters) == norm($1).trimmingCharacters(in: .punctuationCharacters) }) {
                        if t[i].first?.isUppercase == true { t[i + n] = t[i + n].prefix(1).uppercased() + t[i + n].dropFirst() }
                        t.removeSubrange(i..<(i + n)); changed = true; break outer
                    }
                }
            }
            if changed { continue }
            // A restart around a cut-off word: "we can use re we can use recent".
            outer2: for n in stride(from: 5, through: 1, by: -1) where t.count >= 2 * n + 1 {
                for i in 0...(t.count - 2 * n - 1) {
                    let f = norm(t[i + n])
                    guard (1...4).contains(f.count), f.allSatisfy(\.isLetter), !shortWords.contains(f) else { continue }
                    let a = t[i..<(i + n)], b = t[(i + n + 1)..<(i + 2 * n + 1)]
                    guard !a.contains(where: endsSentence) else { continue }
                    // The middle word must really be cut off: the word after the restart begins with it
                    // ("re … recent"), or it isn't a word at all ("sh"). "as soon as", "the app the" are sentences.
                    let after = i + 2 * n + 1 < t.count ? norm(t[i + 2 * n + 1]) : ""
                    let cutOff = (after.count > f.count && after.hasPrefix(f)) || (f == f.lowercased() && t[i + n] == t[i + n].lowercased() && (f.count <= 2 || (f.count <= 3 && !English.isWord(f))))
                    guard cutOff else { continue }
                    if zip(a, b).allSatisfy({ norm($0) == norm($1) }) {
                        if t[i].first?.isUppercase == true { t[i + n + 1] = t[i + n + 1].prefix(1).uppercased() + t[i + n + 1].dropFirst() }
                        t.removeSubrange(i...(i + n)); changed = true; break outer2
                    }
                }
            }
            if changed { continue }
            // The start of a word, then the word: "mis mistakenly", "compa company".
            var k = 0
            while k + 1 < t.count {
                let f = norm(t[k]), next = norm(t[k + 1])
                // One letter only in lowercase ("o older"); "plan B backup" keeps its B.
                if (1...4).contains(f.count), f.allSatisfy(\.isLetter), !shortWords.contains(f), !endsSentence(t[k]),
                   f.count > 1 || t[k] == f,
                   next.count >= f.count + 3, next.hasPrefix(f), f.count == 1 || !English.isWord(f) {
                    t.remove(at: k); changed = true; continue
                }
                k += 1
            }
        }
        return t.joined(separator: " ")
    }
}
