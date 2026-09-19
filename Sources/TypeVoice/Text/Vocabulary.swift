import Foundation

/// Fuzzy dictionary correction. For each user term, scan the transcript for a
/// run of words that sounds like it and replace it with the exact spelling.
enum Vocabulary {
    static func apply(_ terms: [String], to text: String) -> String {
        guard !terms.isEmpty, !text.isEmpty else { return text }
        var words = tokenize(text)
        for term in terms where !term.isEmpty {
            let key = normalize(term)
            let keyPhon = phonetic(key)
            let keySkel = skeleton(keyPhon)
            let termWordCount = max(1, term.split(separator: " ").count)
            var i = 0
            while i < words.count {
                for span in stride(from: min(termWordCount + 1, words.count - i), through: 1, by: -1) {
                    let slice = words[i..<(i + span)]
                    let candidate = slice.map(\.core).joined()
                    guard !candidate.isEmpty else { continue }
                    if candidate.caseInsensitiveCompare(key) == .orderedSame {
                        if candidate != term || span > 1 { words.replaceSubrange(i..<(i + span), with: [merge(slice, with: term)]) }
                        break
                    }
                    if matches(candidate: candidate, key: key, keyPhon: keyPhon, keySkel: keySkel) {
                        words.replaceSubrange(i..<(i + span), with: [merge(slice, with: term)])
                        break
                    }
                }
                i += 1
            }
        }
        return words.map { $0.lead + $0.core + $0.trail }.joined(separator: " ")
    }

    // MARK: Tokens

    struct Word {
        var lead: String   // opening quotes/brackets
        var core: String
        var trail: String  // punctuation after
    }

    private static func tokenize(_ s: String) -> [Word] {
        s.split(separator: " ", omittingEmptySubsequences: true).map { raw in
            var w = String(raw)
            var lead = "", trail = ""
            while let f = w.first, "\"'(“‘[".contains(f) { lead.append(f); w.removeFirst() }
            while let l = w.last, "\"'),.!?;:”’]…".contains(l) { trail.insert(l, at: trail.startIndex); w.removeLast() }
            return Word(lead: lead, core: w, trail: trail)
        }
    }

    private static func merge(_ slice: ArraySlice<Word>, with term: String) -> Word {
        Word(lead: slice.first?.lead ?? "", core: term, trail: slice.last?.trail ?? "")
    }

    // MARK: Similarity

    static func matches(candidate: String, key: String, keyPhon: String, keySkel: String) -> Bool {
        let cPhon = phonetic(candidate)
        guard !cPhon.isEmpty, !keyPhon.isEmpty, cPhon.first == keyPhon.first else { return false }
        let ratio = Double(cPhon.count) / Double(keyPhon.count)
        guard ratio > 0.6, ratio < 1.5 else { return false }
        let raw = similarity(cPhon, keyPhon)
        let threshold: Double = keyPhon.count <= 4 ? 0.9 : (keyPhon.count <= 7 ? 0.78 : 0.7)
        // A short name that only differs by its ending is usually a different name (Priya /
        // Priyam, Ram / Rama), not a mishearing; leave those alone.
        if cPhon != keyPhon, (keyPhon.hasPrefix(cPhon) || cPhon.hasPrefix(keyPhon)), min(cPhon.count, keyPhon.count) <= 5 { return false }
        if raw >= threshold { return true }
        // Vowels are what speech models get wrong most; allow a consonant-frame match
        // when the raw similarity is still reasonable and the frame is long enough to mean something.
        let cSkel = skeleton(cPhon)
        return keySkel.count >= 3 && raw >= 0.55 && similarity(cSkel, keySkel) >= 0.85
    }

    private static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
    }

    /// Cheap phonetic folding so "cuber netties" and "Kubernetes" look alike.
    static func phonetic(_ s: String) -> String {
        var t = s.lowercased().filter { $0.isLetter || $0.isNumber }
        for (a, b) in [("ph", "f"), ("gh", ""), ("ck", "k"), ("ch", "x"), ("sh", "x"), ("qu", "k"), ("q", "k"),
                       ("c", "k"), ("z", "s"), ("y", "i"), ("w", "v"), ("ee", "i"), ("ea", "i"), ("oo", "u")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        // Collapse doubles and drop a trailing silent e.
        var out = ""
        for c in t where out.last != c { out.append(c) }
        if out.count > 3, out.last == "e" { out.removeLast() }
        return out
    }

    private static func skeleton(_ s: String) -> String {
        let vowels = Set("aeiou")
        var out = ""
        for c in s where !vowels.contains(c) { if out.last != c { out.append(c) } }
        return out
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        let n = max(a.count, b.count)
        guard n > 0 else { return 1 }
        return 1 - Double(levenshtein(Array(a), Array(b))) / Double(n)
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    cur[j] = min(cur[j], prev[j - 1])   // transposition (approx.)
                }
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}
