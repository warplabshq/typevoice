import Foundation

/// Fuzzy dictionary correction. For each user term, scan the transcript for a
/// run of words that sounds like it and replace it with the exact spelling.
enum Vocabulary {
    static func apply(_ terms: [String], to text: String) -> String {
        guard !terms.isEmpty, !text.isEmpty else { return text }
        // Line by line, so a name next to a paragraph break ("cuber netties\n\nThen") is still seen.
        if text.contains("\n") { return text.components(separatedBy: "\n").map { apply(terms, to: $0) }.joined(separator: "\n") }
        var words = tokenize(text)
        for term in terms where !term.isEmpty {
            let key = normalize(term)
            let keyPhon = phonetic(key)
            let keySkel = skeleton(keyPhon)
            let termWordCount = max(1, term.split(separator: " ").count)
            let termHasDot = term.contains(".")
            let termHasDigit = term.contains(where: \.isNumber)
            var i = 0
            while i < words.count {
                // Shortest span first: "Hicksfield or" must not swallow the "or".
                for span in stride(from: 1, through: min(termWordCount + 1, words.count - i), by: 1) {
                    let slice = words[i..<(i + span)]
                    // Digits the number step made ("11 labs") are read as the words that were said,
                    // for a name spelled without digits (ElevenLabs).
                    let heardCore = slice.map(\.core).joined()
                    let candidate = !termHasDigit && heardCore.contains(where: \.isNumber) ? spellDigits(heardCore) : heardCore
                    guard !candidate.isEmpty else { continue }
                    // A web address only meets a web address: "logo" is not "Logs.so", and
                    // "typevoice.ai" keeps its ".ai" rather than becoming "TypeVoice".
                    let heardDot = candidate.contains(".") || slice.dropLast().contains { $0.trail.hasPrefix(".") }
                    if termHasDot != heardDot { continue }
                    // Both halves of an address must line up: "logs. So" is Logs.so,
                    // "Logstart. So that…" is not.
                    if termHasDot, !addressAligns(slice, term: term) { continue }
                    // "the voice" is not TypeVoice: a phrase with a small everyday word in it becomes a
                    // name only when it's spelled exactly like it ("type voice", "warp labs").
                    if span > 1, slice.contains(where: { smallWords.contains($0.core.lowercased()) }),
                       Self.letters(candidate) != Self.letters(key) { continue }
                    if candidate.caseInsensitiveCompare(key) == .orderedSame {
                        if candidate != term || span > 1 { words.replaceSubrange(i..<(i + span), with: [merge(slice, with: term)]) }
                        break
                    }
                    // Read from digits: only a near-exact match ("11 labs" is ElevenLabs, "11 days" is not).
                    if candidate != heardCore, phonetic(candidate) != keyPhon { continue }
                    if matches(candidate: candidate, key: key, keyPhon: keyPhon, keySkel: keySkel)
                        || (span == 1 && !termHasDot && looseMatch(candidate, keyPhon: keyPhon, keySkel: keySkel)) {
                        words.replaceSubrange(i..<(i + span), with: [merge(slice, with: term)])
                        break
                    }
                }
                i += 1
            }
        }
        // Half of a two-word name said on its own ("Gobind" for "Harsh Govind"): the part must be a
        // name, not an English word, and so must what was heard — "harsh" or "whisper" never move.
        for term in terms where term.contains(" ") && !term.contains(".") {
            for part in term.split(separator: " ").map(String.init) where part.count >= 5 && !English.isWord(part) {
                let pPhon = phonetic(part), pSkel = skeleton(pPhon)
                for k in words.indices where !words[k].core.contains(" ") && words[k].core.count >= 4 {
                    let c = words[k].core
                    guard c.caseInsensitiveCompare(part) != .orderedSame, c.first?.isUppercase == true, !English.isWord(c) else { continue }
                    if matches(candidate: c, key: part, keyPhon: pPhon, keySkel: pSkel) || looseMatch(c, keyPhon: pPhon, keySkel: pSkel) { words[k].core = part }
                }
            }
        }
        return words.map { $0.lead + $0.core + $0.trail }.joined(separator: " ")
    }

    /// "11labs" → "elevenlabs", "3d" → "threed": digit runs (up to 999) as the words they came from.
    static func spellDigits(_ s: String) -> String {
        let ones = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
                    "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
        let tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
        func words(_ n: Int) -> String {
            if n < 20 { return ones[n] }
            if n < 100 { return tens[n / 10] + (n % 10 == 0 ? "" : ones[n % 10]) }
            return ones[n / 100] + "hundred" + (n % 100 == 0 ? "" : words(n % 100))
        }
        var out = "", digits = ""
        func flush() { if let n = Int(digits), n < 1000 { out += words(n) } else { out += digits }; digits = "" }
        for c in s { if c.isNumber { digits.append(c) } else { if !digits.isEmpty { flush() }; out.append(c) } }
        if !digits.isEmpty { flush() }
        return out
    }

    private static let smallWords: Set<String> = ["the", "a", "an", "to", "of", "in", "on", "at", "for", "with", "and", "or", "but", "is", "it",
        "my", "your", "our", "his", "her", "this", "that", "so", "as", "be", "by", "we", "i", "you", "he", "she", "they", "me", "us", "no", "not"]
    private static func letters(_ s: String) -> String { String(s.lowercased().filter { $0.isLetter || $0.isNumber }) }

    /// Two mishearings the phonetic match can't see, tried only on words that are not English:
    /// B for V at any point ("Bidai" → VidAI, "Gobind" → Govind), and a name the model spelled as
    /// letters ("VDI" → VidAI: the same consonants, and a vowel the name has).
    private static func looseMatch(_ candidate: String, keyPhon: String, keySkel: String) -> Bool {
        guard candidate.count >= 2, !English.isWord(candidate) else { return false }
        let letters = candidate.filter(\.isLetter)
        if letters.count == candidate.count, (2...5).contains(letters.count), letters.allSatisfy(\.isUppercase) {
            let low = letters.lowercased()
            if keySkel.count >= 2, skeleton(low) == keySkel, low.contains(where: { "aeiou".contains($0) && keyPhon.contains($0) }) { return true }
        }
        func bv(_ s: String) -> String { s.replacingOccurrences(of: "v", with: "b") }
        let cPhon = bv(phonetic(candidate)), kPhon = bv(keyPhon)
        guard cPhon != phonetic(candidate) || kPhon != keyPhon else { return false }   // no B/V in either: nothing new to try
        return matches(candidatePhon: cPhon, keyPhon: kPhon, keySkel: skeleton(kPhon))
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
