import Foundation

/// Structure from speech: spoken commands ("new line", "bullet", "number two"), lists
/// said the natural way ("grocery list: milk, eggs, bread and butter"), and, from the
/// model's word timestamps, paragraph breaks at real pauses.
enum Structure {
    /// A word with when it was spoken. `gapBefore` is the silence before it.
    struct Word { var text: String; var gapBefore: TimeInterval; var confidence: Float = 1 }

    /// Turns a transcript into words with the pause before each, using token timings.
    /// Sub-word tokens are merged: a token that starts with the SentencePiece word
    /// boundary (▁) or a space starts a new word.
    static func words(text: String, tokens: [Transcript.Token]) -> [Word] {
        guard !tokens.isEmpty else {
            return text.split(separator: " ").map { Word(text: String($0), gapBefore: 0) }
        }
        var out: [Word] = []
        var lastEnd: TimeInterval = 0
        var current = ""
        var currentGap: TimeInterval = 0
        var currentConf: Float = 1
        func flush() { if !current.isEmpty { out.append(Word(text: current, gapBefore: currentGap, confidence: currentConf)); current = ""; currentConf = 1 } }
        for t in tokens {
            let raw = t.token
            let startsWord = raw.hasPrefix("▁") || raw.hasPrefix(" ") || current.isEmpty
            let piece = raw.replacingOccurrences(of: "▁", with: "").trimmingCharacters(in: .whitespaces)
            if startsWord {
                flush()
                currentGap = max(0, t.start - lastEnd)
            }
            current += piece
            currentConf = min(currentConf, t.confidence)
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
    // "and third glasses", "so first lights", "and then number two": the connector goes with the marker.
    private static let lead = #"(?:\b(?:and\s+then|and|so|then|also|next|okay|ok)\b,?\s+)?"#
    private static let bullet = try! NSRegularExpression(pattern: #"(?i)[,:;]?\s*"# + lead + #"(?<!\ba )(?<!\ban )(?<!\bthe )(?<!\bone )(?<!\beach )(?<!\bevery )\b(?:bullet\s+point|bullet|dash\s+point|(?:new|next)\s+item)\b(?!s\b)(?!\s+(?:points?|form|list)s?\b)[,.:;]?\s*"#)
    private static let numbered = try! NSRegularExpression(pattern: #"(?i)[,:;]?\s*"# + lead + #"\b(?:number|point|step|item)\s+(one|two|three|four|five|six|seven|eight|nine|ten|\d{1,2})\b[,.:;]?\s*"#)
    /// "First, … Second, … Third, …" at the start of sentences.
    private static let ordinal = try! NSRegularExpression(pattern: #"(?i)(^|[.!?]\s+|\n)(first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)(?:ly)?\b[,.:;]?\s*"#)
    /// The same ordinals anywhere in a sentence: "so first lights, second camera and third glasses".
    /// They only count as a list when they run in order from "first" (see `ordinalRun`).
    private static let ordinalAnywhere = try! NSRegularExpression(pattern: #"(?i)[,:;]?\s*"# + lead + #"(?:\bthe\s+)?\b(first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth)(?:ly)?\b(?!\s+(?:of\s+all|things\s+first|time|times|place|half|floor|class|name|round|draft|version|pass|edition|attempt|try|impression|impressions|priority|choice|option|aid|hand|light|gear|born|person|lady)\b)(?:\s+(?:thing|one|point|step|item|part|reason|task)\b)?(?:\s+(?:is|was|would\s+be)\b)?[,.:;]?\s*"#)
    private static let ordinalWords = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth"]

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
            if ords.count >= 3 {
                s = renumber(s, matches: ords, keepGroup: 1)
            } else if let run = ordinalRun(in: s) {
                s = renumber(s, matches: run)
            }
        }
        if !s.contains("\n- "), !s.contains("\n1. ") {
            // Paragraph by paragraph, so a list in the middle of a longer dictation still forms.
            s = s.components(separatedBy: "\n\n").map { naturalList($0) ?? $0 }.joined(separator: "\n\n")
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

    /// "first …, second … and third …" wherever it sits in the sentence: the ordinals must run
    /// in order from "first", three or more of them, or two when a count was announced
    /// ("two things: first the lights and second the camera").
    private static func ordinalRun(in s: String) -> [NSTextCheckingResult]? {
        let all = ordinalAnywhere.matches(in: s, range: NSRange(s.startIndex..., in: s))
        var run: [NSTextCheckingResult] = []
        for m in all {
            guard let r = Range(m.range(at: 1), in: s) else { continue }
            let idx = ordinalWords.firstIndex(of: s[r].lowercased()) ?? -1
            if idx == run.count { run.append(m) }
            else if idx == 0 { run = [m] }   // a fresh "first" restarts the run
        }
        guard run.count >= 2, let first = run.first else { return nil }
        let head = String(s[..<Range(first.range, in: s)!.lowerBound])
        let announced = countCue.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)) != nil
        guard run.count >= 3 || announced else { return nil }
        // Every item needs words of its own; "first, second, third" alone is not a list.
        for (i, m) in run.enumerated() {
            let end = i + 1 < run.count ? Range(run[i + 1].range, in: s)!.lowerBound : s.endIndex
            let body = s[Range(m.range, in: s)!.upperBound..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
        }
        return run
    }

    // MARK: Natural lists

    /// "three things", "a couple of points", "5 reasons": a count that announces how many are coming.
    private static let countCue = try! NSRegularExpression(pattern: #"(?i)\b(?:two|three|four|five|six|seven|eight|nine|ten|\d{1,2}|a\s+couple\s+of|a\s+few|these|the\s+following)\s+(?:things|items|points|reasons|steps|tasks|ideas|options|questions|features|bugs|issues|changes|notes|topics|goals|priorities|updates|requests|asks)\b"#)

    /// Words that announce a list when they appear in the lead-in.
    private static let listCue = try! NSRegularExpression(pattern: #"(?i)\b(?:list|lists|listed|to[- ]?do|todo|checklist|groceries|grocery|shopping|ingredients|things to (?:buy|get|do|pack|bring|remember)|stuff to (?:buy|get|do)|reminders?|items?|errands|essentials|packing)\b"#)

    /// "Grocery list: milk, eggs, bread and butter." → a heading and bullets. The lead-in is the
    /// sentence right before a colon, a sentence end or a comma; it must be short and, unless
    /// the boundary is a colon, announce a list ("my list", "three things"). Three short items
    /// or more, two when a pair was announced. Whatever was said after the list keeps its place.
    private static func naturalList(_ s: String) -> String? {
        guard !s.contains("\n") else { return nil }
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if ":,.?!".contains(c), let out = list(head: String(s[..<i]), rest: String(s[s.index(after: i)...]), boundary: c) {
                return out
            }
            i = s.index(after: i)
        }
        return nil
    }

    private static func list(head: String, rest: String, boundary: Character) -> String? {
        let leadIn = head.split(whereSeparator: { ".!?".contains($0) }).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard (1...12).contains(leadIn.split(separator: " ").count) else { return nil }
        let range = NSRange(leadIn.startIndex..., in: leadIn)
        let count = countCue.firstMatch(in: leadIn, range: range)
        let cued = count != nil || listCue.firstMatch(in: leadIn, range: range) != nil
        guard boundary == ":" || cued else { return nil }
        var minimum = 3
        if let count, let r = Range(count.range, in: leadIn), leadIn[r].lowercased().range(of: #"^(two|2|a\s+couple)\b"#, options: .regularExpression) != nil { minimum = 2 }
        // The list is the sentence right after the boundary; anything after it follows as text.
        var body = rest, tail = ""
        if let m = rest.range(of: #"[.!?](?=\s|$)"#, options: .regularExpression) {
            body = String(rest[..<m.upperBound]); tail = rest[m.upperBound...].trimmingCharacters(in: .whitespaces)
        }
        guard let items = series(body, minimum: minimum) else { return nil }
        let intro = head.trimmingCharacters(in: .whitespaces) + ("?!".contains(boundary) ? String(boundary) : ":")
        return intro + items.map { "\n- " + $0 }.joined() + (tail.isEmpty ? "" : "\n\n" + tail)
    }

    /// "…, sugar, and that's all." / "…, etc." — the words that close a spoken list.
    private static let closer = try! NSRegularExpression(pattern: #"(?i)[,\s]*\b(?:(?:and\s+)?(?:that's|that\s+is|thats)\s+(?:all|it|everything|about\s+it)(?:\s+for\s+now)?|and\s+(?:so\s+on|more|stuff|things|such|the\s+like)|et\s*cetera|etc|I\s+(?:think|guess))\s*$"#)

    /// Splits "milk, eggs, bread and butter." into short items, or nil if it doesn't look like one.
    private static func series(_ text: String, minimum: Int) -> [String]? {
        var t = text.trimmingCharacters(in: .whitespaces)
        while let last = t.last, ".!?".contains(last) { t.removeLast() }
        t = closer.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
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
        // "…and third glasses. Let me know." — what follows a short last item is not part of it.
        if let last = itemIdx.last, last == lines.count - 1,
           let marker = lines[last].range(of: #"^(- |\d+\. )"#, options: .regularExpression),
           let m = lines[last].range(of: #"[.!?](?=\s+\S)"#, options: .regularExpression, range: marker.upperBound..<lines[last].endIndex) {
            let item = String(lines[last][..<m.upperBound]), tail = lines[last][m.upperBound...].trimmingCharacters(in: .whitespaces)
            if item.split(separator: " ").count <= 8 {
                lines[last] = item
                lines.append(""); lines.append(tail)
            }
        }

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
