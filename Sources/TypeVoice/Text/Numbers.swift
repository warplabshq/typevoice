import FluidAudio
import Foundation

/// Spoken numbers → digits, using NVIDIA NeMo's inverse text normalization
/// (bundled with FluidAudio), with guards so it never eats real words.
enum Numbers {
    static func apply(_ text: String) -> String {
        guard containsNumberWord(text) else { return restoreOrdinals(text) }
        var s = text

        // NeMo's grammar treats "and one" as a number continuation, so it would drop
        // the "and" in "two cats and one dog". Hide every "and" that is not part
        // of a big number before normalising.
        s = s.replacingOccurrences(
            of: #"(?i)(?<!\bhundred|\bthousand|\bmillion|\bbillion|\bdollars|\bdollar|\bpounds|\beuros|\bcents|\bbucks)\s+(and)\s+"#,
            with: " \u{2038}$1 ", options: .regularExpression)

        // Digit-by-digit strings (phone numbers, codes): join them before the grammar
        // can mistake "one zero" for a time.
        s = joinDigitRuns(s)

        s = TextNormalizer.shared.normalizeSentence(s)
        // Two or three plain digit words ("one three", "one two three") were glued so the grammar
        // couldn't read them as a clock time ("1:03"); they stay as said.
        s = s.replacingOccurrences(of: "\u{2039}", with: " ")
        // "first" → "1st" is right in a date ("the 5th of March", "March 1st"), not in a sentence.
        s = restoreOrdinals(s)

        // The hidden word comes back exactly as it was said ("… of Matt. And I think").
        s = s.replacingOccurrences(of: "\u{2038}", with: "")
        // "24 h" → "24 hours", "30 min" → "30 minutes" (NeMo abbreviates measures).
        s = s.replacingOccurrences(of: #"(\d)\s?h\b(?![:.])"#, with: "$1 hours", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d)\s?min\b"#, with: "$1 minutes", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d)\s?sec\b"#, with: "$1 seconds", options: .regularExpression)
        // "2 X speed", "10 x faster" → "2x speed", "10x faster".
        s = s.replacingOccurrences(of: #"\b(\d+(?:\.\d+)?) ?[xX]\b(?![-.]\w)"#, with: "$1x", options: .regularExpression)
        // "02:30 p.m." → "2:30 pm"
        s = s.replacingOccurrences(of: #"\b0(\d:\d\d)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\b([ap])\.m\."#, with: "$1m", options: .regularExpression)
        // Standalone 0–9 read better as words ("two cats", but "2%", "2:30", "22", "5 March").
        s = restoreSmallNumbers(s)
        // Sentence-mode lowercases a leading "I" sometimes; put it back.
        s = s.replacingOccurrences(of: #"(^|[.!?]\s+)i\b"#, with: "$1I", options: .regularExpression)
        return s
    }

    private static let smallWords = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
    private static let digitWord: [String: String] = [
        "zero": "0", "oh": "0", "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
    ]

    /// Four or more consecutive digit words become one digit string ("nine eight seven six" → 9876).
    /// Two or three plain ones ("one three", "one two three") are glued with a marker so the grammar
    /// can't read them as a clock time; the marker becomes a space again afterwards.
    private static func joinDigitRuns(_ s: String) -> String {
        let words = s.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        var run: [(core: String, word: String, trail: String)] = []
        func flush() {
            if run.count >= 4 { out.append(run.map { digitWord[$0.core]! }.joined() + run.last!.trail) }
            else if run.count >= 2, run.allSatisfy({ $0.core != "zero" && $0.core != "oh" }) { out.append(run.map(\.word).joined(separator: "\u{2039}")) }
            else { out += run.map(\.word) }
            run.removeAll()
        }
        for w in words {
            let lower = w.lowercased()
            let core = lower.trimmingCharacters(in: .punctuationCharacters)
            let trail = String(w.drop(while: { !$0.isPunctuation }))
            guard digitWord[core] != nil, lower.hasPrefix(core) else { flush(); out.append(w); continue }
            if !run.isEmpty, run.last!.trail.isEmpty == false { flush() }
            run.append((core, w, trail))
            if !trail.isEmpty { flush() }
        }
        flush()
        return out.joined(separator: " ")
    }

    private static let ordinalWords = ["", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth"]
    private static let monthAlt = "january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec"
    private static let ordinalRE = try! NSRegularExpression(pattern: #"(?i)\b([1-9])(st|nd|rd|th)\b"#)
    private static let dateAfter = try! NSRegularExpression(pattern: #"(?i)^\s+(of\s+)?("# + monthAlt + #")\b"#)
    private static let dateBefore = try! NSRegularExpression(pattern: #"(?i)\b("# + monthAlt + #")\s+$"#)

    private static func restoreOrdinals(_ s: String) -> String {
        let ns = s as NSString
        var out = s
        for m in ordinalRE.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let after = ns.substring(from: m.range.location + m.range.length), before = ns.substring(to: m.range.location)
            if dateAfter.firstMatch(in: after, range: NSRange(location: 0, length: (after as NSString).length)) != nil { continue }
            if dateBefore.firstMatch(in: before, range: NSRange(location: 0, length: (before as NSString).length)) != nil { continue }
            var word = ordinalWords[Int(ns.substring(with: m.range(at: 1)))!]
            let trimmed = before.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || ".!?\n".contains(trimmed.last!) { word = word.prefix(1).uppercased() + word.dropFirst() }
            out = (out as NSString).replacingCharacters(in: m.range, with: word)
        }
        return out
    }

    private static func restoreSmallNumbers(_ s: String) -> String {
        let months = "january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec"
        let re = try! NSRegularExpression(
            pattern: #"(?i)(?<![\d$€£.:/\-#])(?<!(?:"# + months + #")\s)\b(\d)\b(?![\d%:.,/\-]|\s?(?:[ap]\.\s?m\.|am|pm|percent|hours|minutes|seconds|x|"# + months + #")(?:\b|(?<=\.)))"#)
        let ns = s as NSString
        var out = s
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let d = Int(ns.substring(with: m.range(at: 1)))!
            out = (out as NSString).replacingCharacters(in: m.range, with: smallWords[d])
        }
        return out
    }

    private static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
        "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
        "hundred", "thousand", "million", "billion", "half", "quarter", "percent", "dollars", "cents",
        "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
        "twentieth", "thirtieth", "oh", "point",
    ]

    static func containsNumberWord(_ s: String) -> Bool {
        for w in s.lowercased().split(whereSeparator: { !$0.isLetter }) where numberWords.contains(String(w)) { return true }
        return false
    }
}
