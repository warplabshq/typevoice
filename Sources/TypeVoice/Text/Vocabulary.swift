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
            let termHasDot = term.contains(".")
            var i = 0
            while i < words.count {
                // Shortest span first: "Hicksfield or" must not swallow the "or".
                for span in stride(from: 1, through: min(termWordCount + 1, words.count - i), by: 1) {
                    let slice = words[i..<(i + span)]
                    let candidate = slice.map(\.core).joined()
                    guard !candidate.isEmpty else { continue }
                    // A web address only meets a web address: "logo" is not "Logs.so", and
                    // "typevoice.ai" keeps its ".ai" rather than becoming "TypeVoice".
                    let heardDot = candidate.contains(".") || slice.dropLast().contains { $0.trail.hasPrefix(".") }
                    if termHasDot != heardDot { continue }
                    // Both halves of an address must line up: "logs. So" is Logs.so,
                    // "Logstart. So that…" is not.
                    if termHasDot, !addressAligns(slice, term: term) { continue }
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

    /// For a term like "Logs.so": the heard ending equals "so" exactly and the heard name
    /// sounds like "Logs" on its own.
    private static func addressAligns(_ slice: ArraySlice<Word>, term: String) -> Bool {
        guard let dot = term.lastIndex(of: ".") else { return true }
        let tHead = String(term[..<dot]), tTail = String(term[term.index(after: dot)...]).lowercased()
        let heard: String
        if slice.count == 1 { heard = slice.first!.core }
        else { heard = slice.map { $0.core + ($0.trail.hasPrefix(".") ? "." : "") }.joined() }
        guard let hDot = heard.lastIndex(of: ".") else { return false }
        let hHead = String(heard[..<hDot]), hTail = String(heard[heard.index(after: hDot)...]).lowercased()
        guard hTail == tTail else { return false }
        if hHead.caseInsensitiveCompare(tHead) == .orderedSame { return true }
        let kp = phonetic(normalize(tHead))
        return matches(candidate: normalize(hHead), key: normalize(tHead), keyPhon: kp, keySkel: skeleton(kp))
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
        matches(candidatePhon: phonetic(candidate), keyPhon: keyPhon, keySkel: keySkel)
    }

    /// The same test with the candidate's phonetic form already computed (the pack matcher
    /// compares one span against many terms, so it must not fold the string again per term).
    static func matches(candidatePhon cPhon: String, keyPhon: String, keySkel: String) -> Bool {
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

    static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
    }

    /// Cheap phonetic folding so "cuber netties" and "Kubernetes" look alike.
    static func phonetic(_ s: String) -> String {
        // One pass with a one-character lookahead; the same folding as the old chain of
        // replacements (ph→f, gh→∅, ck→k, ch/sh→x, qu/q/c→k, z→s, y→i, w→v, ee/ea→i, oo→u),
        // about twenty times faster, which matters when a span meets a whole pack.
        let t = Array(s.lowercased().unicodeScalars.filter { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) })
        var out = String.UnicodeScalarView()
        var i = 0
        func push(_ c: Unicode.Scalar) { if out.last != c { out.append(c) } }
        while i < t.count {
            let c = t[i], n: Unicode.Scalar? = i + 1 < t.count ? t[i + 1] : nil
            switch (c, n) {
            case ("p", "h"): push("f"); i += 2
            case ("g", "h"): i += 2
            case ("c", "k"): push("k"); i += 2
            case ("c", "h"), ("s", "h"): push("x"); i += 2
            case ("q", "u"): push("k"); i += 2
            case ("e", "e"), ("e", "a"): push("i"); i += 2
            case ("o", "o"): push("u"); i += 2
            case ("q", _), ("c", _): push("k"); i += 1
            case ("z", _): push("s"); i += 1
            case ("y", _): push("i"); i += 1
            case ("w", _): push("v"); i += 1
            default: push(c); i += 1
            }
        }
        var result = String(out)
        if result.count > 3, result.last == "e" { result.removeLast() }
        return result
    }

    static func skeleton(_ s: String) -> String {
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
