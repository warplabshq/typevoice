import Foundation

/// Structure from speech: spoken commands ("new line", "bullet", "number two"), lists
/// said the natural way ("grocery list: milk, eggs, bread and butter"), and, from the
/// model's word timestamps, paragraph breaks at real pauses.
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

    // The model punctuates commands like any other words ("Bullet, milk." / "Bullet. Eggs"), so
    // every marker tolerates punctuation on both sides. Commas/colons before a command are
    // dropped; a period stays (it ends the sentence).
    private static let newParagraph = try! NSRegularExpression(pattern: #"(?i)[,:;]?\s*\b(?:(?:new|next)\s+paragraph|paragraph\s+break)\b[,.:;]?\s*"#)
    private static let newLine = try! NSRegularExpression(pattern: #"(?i)[,:;]?\s*\b(?:(?:new|next)\s+line|line\s+break)\b[,.:;]?\s*"#)
    private static let bullet = try! NSRegularExpression(pattern: #"(?i)[,:;]?\s*\b(?:bullet\s+point|bullet|dash\s+point|(?:new|next)\s+item)\b[,.:;]?\s*"#)
    private static let numbered = try! NSRegularExpression(pattern: #"(?i)[,:;]?\s*\b(?:number|point|step|item)\s+(one|two|three|four|five|six|seven|eight|nine|ten|\d{1,2})\b[,.:;]?\s*"#)
    /// "First, … Second, … Third, …" at the start of sentences.
    private static let ordinal = try! NSRegularExpression(pattern: #"(?i)(^|[.!?]\s+|\n)(first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)(?:ly)?\b[,.:;]?\s*"#)

    /// Applies spoken formatting commands and natural lists. Explicit lists only form when
    /// two or more markers appear, so "number one priority" in normal speech stays as it is.
    static func commands(_ text: String) -> String {
        var s = text
        s = newParagraph.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "\n\n")
        s = newLine.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "\n")

        let bullets = bullet.matches(in: s, range: NSRange(s.startIndex..., in: s))
        if bullets.count >= 2 {
            s = bullet.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "\n- ")
        } else if bullets.count == 1, let m = bullets.first, let r = Range(m.range, in: s) {
            // One "bullet" and then a run of items: "bullet milk, eggs, bread and butter".
            let head = String(s[..<r.lowerBound]), rest = String(s[r.upperBound...])
            if let items = series(rest, minimum: 2) {
                s = head + items.map { "\n- " + $0 }.joined()
            } else {
                s = head + "\n- " + rest
            }
        }
        let nums = numbered.matches(in: s, range: NSRange(s.startIndex..., in: s))
        if nums.count >= 2 {
            s = renumber(s, matches: nums)
        } else if !s.contains("\n- ") {
            let ords = ordinal.matches(in: s, range: NSRange(s.startIndex..., in: s))
            if ords.count >= 3 { s = renumber(s, matches: ords, keepGroup: 1) }
        }
        if !s.contains("\n- "), !s.contains("\n1. ") {
            s = naturalList(s) ?? s
        }
        return tidy(s)
    }

    /// Replaces each marker with "\n<n>. ", numbering in order.
    private static func renumber(_ s: String, matches: [NSTextCheckingResult], keepGroup: Int? = nil) -> String {
        var result = s
        for (idx, m) in matches.enumerated().reversed() {
            let r = Range(m.range, in: result)!
            let kept = keepGroup.flatMap { g in Range(m.range(at: g), in: result).map { String(result[$0]) } } ?? ""
            result.replaceSubrange(r, with: kept.trimmingCharacters(in: .whitespaces) + "\n\(idx + 1). ")
        }
        return result
    }

    // MARK: Natural lists

    /// Words that announce a list when they appear in the lead-in.
    private static let listCue = try! NSRegularExpression(pattern: #"(?i)\b(?:list|lists|listed|to[- ]?do|todo|checklist|groceries|grocery|shopping|ingredients|things to (?:buy|get|do|pack|bring|remember)|stuff to (?:buy|get|do)|reminders?|items?|errands|essentials|packing)\b"#)

    /// "Grocery list: milk, eggs, bread and butter." → a heading and bullets. Needs either a
    /// colon or a list cue in a short lead-in, and at least three short items.
    private static func naturalList(_ s: String) -> String? {
        guard !s.contains("\n") else { return nil }
        let head: String, rest: String
        if let colon = s.firstIndex(of: ":") {
            head = String(s[..<colon]); rest = String(s[s.index(after: colon)...])
        } else if let comma = s.firstIndex(of: ",") {
            head = String(s[..<comma]); rest = String(s[s.index(after: comma)...])
            guard listCue.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)) != nil else { return nil }
        } else {
            return nil
        }
        let headWords = head.split(separator: " ")
        guard (1...10).contains(headWords.count), !head.contains(where: { ".!?".contains($0) }),
              let items = series(rest, minimum: 3) else { return nil }
        return head.trimmingCharacters(in: .whitespaces) + ":" + items.map { "\n- " + $0 }.joined()
    }

    /// Splits "milk, eggs, bread and butter." into short items, or nil if it doesn't look like one.
    private static func series(_ text: String, minimum: Int) -> [String]? {
        var t = text.trimmingCharacters(in: .whitespaces)
        while let last = t.last, ".!?".contains(last) { t.removeLast() }
        guard !t.contains(where: { ".!?;:\n".contains($0) }) else { return nil }
        // "a, b, c and d" / "a, b, c, and d" / "a and b".
        var parts = t.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let last = parts.last {
            let split = last.components(separatedBy: " and ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if split.count == 2 { parts.removeLast(); parts.append(contentsOf: split) }
            else if let l = parts.last, l.lowercased().hasPrefix("and ") { parts[parts.count - 1] = String(l.dropFirst(4)) }
        }
        guard parts.count >= minimum, parts.allSatisfy({ (1...5).contains($0.split(separator: " ").count) }) else { return nil }
        return parts.map { item in
            guard let f = item.first, f.isLowercase else { return item }
            return f.uppercased() + item.dropFirst()
        }
    }

    // MARK: Tidy

    /// Capitalise items, give a short lead-in its colon, drop stray periods on short items,
    /// no blank first line, no runs of blank lines.
    private static func tidy(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: #"^\s*\n+"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        guard s.contains("\n- ") || s.range(of: #"\n\d+\. "#, options: .regularExpression) != nil else { return s }

        var lines = s.components(separatedBy: "\n")
        let itemRe = try! NSRegularExpression(pattern: #"^(- |\d+\. )(.*)$"#)
        var itemIdx: [Int] = []
        for (i, l) in lines.enumerated() where itemRe.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) != nil { itemIdx.append(i) }

        // Short items ("Milk", "Ship the build") carry no period; sentences keep theirs.
        let bodies = itemIdx.map { i -> String in
            let m = itemRe.firstMatch(in: lines[i], range: NSRange(lines[i].startIndex..., in: lines[i]))!
            return String(lines[i][Range(m.range(at: 2), in: lines[i])!])
        }
        let allShort = bodies.allSatisfy { b in
            b.split(separator: " ").count <= 6 && !b.dropLast().contains(where: { ".!?".contains($0) })
        }
        for i in itemIdx {
            let m = itemRe.firstMatch(in: lines[i], range: NSRange(lines[i].startIndex..., in: lines[i]))!
            let marker = String(lines[i][Range(m.range(at: 1), in: lines[i])!])
            var body = String(lines[i][Range(m.range(at: 2), in: lines[i])!]).trimmingCharacters(in: .whitespaces)
            if allShort, body.hasSuffix(".") { body.removeLast() }
            if let f = body.first, f.isLowercase { body = f.uppercased() + body.dropFirst() }
            lines[i] = marker + body
        }
        // A short lead-in right above the first item ends with a colon.
        if let first = itemIdx.first, first > 0 {
            var head = lines[first - 1].trimmingCharacters(in: .whitespaces)
            let words = head.split(separator: " ").count
            if !head.isEmpty, words <= 10 {
                if head.hasSuffix(".") || head.hasSuffix(",") { head.removeLast() }
                if !head.hasSuffix(":") && !head.hasSuffix("?") && !head.hasSuffix("!") { head += ":" }
                lines[first - 1] = head
            }
        }
        return lines.joined(separator: "\n")
    }
}
