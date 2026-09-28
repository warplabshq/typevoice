import Foundation

/// Grammar the speech model can't hear. People often ask without raising their voice at the
/// end, so "Can you send it" comes back with a full stop; the words still say it's a question.
/// Also the small capitalisation slips: "i", a sentence that starts in lowercase. Word lists
/// and one pass per sentence, no model: it runs in microseconds on every dictation.
enum Grammar {
    static func apply(_ text: String, style: Style) -> String {
        var s = text
        if style.punctuation != .none { s = questions(s) }
        s = hyphens(s)
        if style.casing == .sentence { s = capitals(s) }
        return s
    }

    // MARK: Questions

    /// Sentence by sentence (a sentence ends at . ? ! or a line break). One that reads as a
    /// question but ends in a full stop, or in nothing at the very end, gets a question mark.
    static func questions(_ text: String) -> String {
        var out = "", sentence = ""
        func flush(_ terminator: String) {
            if sentence.trimmingCharacters(in: .whitespaces).isEmpty { out += sentence + terminator; sentence = ""; return }
            if (terminator == "." || terminator == "") && isQuestion(sentence) { out += sentence + "?" }
            else { out += sentence + terminator }
            sentence = ""
        }
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\n" { flush(""); out.append(c); i += 1; continue }
            if c == "." || c == "?" || c == "!" {
                // Only a stop that ends a sentence: followed by a space, a line break or the end.
                // "typevoice.ai", "a.m.", "2.5" stay inside their sentence.
                let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
                let ends = next == nil || next == " " || next == "\n"
                if ends && !(c == "." && isAbbreviation(sentence)) {
                    var j = i; var run = ""
                    while j < chars.count, ".?!".contains(chars[j]) { run.append(chars[j]); j += 1 }
                    flush(run == "." ? "." : run); i = j; continue
                }
            }
            sentence.append(c); i += 1
        }
        flush("")
        return out
    }

    private static func isAbbreviation(_ sentence: String) -> Bool {
        guard let last = sentence.split(separator: " ").last?.lowercased() else { return false }
        return abbreviations.contains(last) || last.range(of: #"^([a-z]\.)+[a-z]$"#, options: .regularExpression) != nil
    }
    private static let abbreviations: Set<String> = ["etc", "vs", "mr", "mrs", "ms", "dr", "st", "approx", "e.g", "i.e", "fig"]

    // Words that can open the subject of a question: "Can *you*", "Is *the* build…".
    private static let pronouns: Set<String> = ["i", "you", "we", "they", "he", "she", "it", "u", "y'all", "ya"]
    private static let subjects: Set<String> = pronouns.union(["this", "that", "these", "those", "there", "anyone", "anybody", "someone", "somebody",
        "everyone", "everybody", "everything", "anything", "something", "nothing", "your", "my", "our", "their", "his", "her", "its",
        "the", "a", "an", "people", "guys", "all", "any", "some", "any1"])
    private static let copulas: Set<String> = ["is", "are", "was", "were", "isn't", "aren't", "wasn't", "weren't"]
    private static let modals: Set<String> = ["can", "could", "would", "should", "shall", "will", "must", "can't", "couldn't", "wouldn't", "shouldn't", "won't", "cannot"]
    private static let auxiliaries: Set<String> = copulas.union(modals).union(["do", "does", "did", "don't", "doesn't", "didn't", "have", "has", "had",
        "haven't", "hasn't", "hadn't", "may", "might", "am"])
    private static let whWords: Set<String> = ["what", "why", "how", "where", "when", "who", "which", "whose", "whom"]
    /// Openers that come before the question itself: "So, can you…", "Okay and what about…".
    private static let openers: Set<String> = ["so", "and", "also", "okay", "ok", "alright", "hey", "hi", "hello", "yo", "well", "oh", "actually",
        "anyway", "anyways", "but", "um", "uh", "like", "wait", "then", "now", "plus", "yeah", "yes", "no", "right", "sorry", "quick", "question",
        "btw", "honestly", "seriously", "basically", "listen", "look", "guys", "dude", "bro", "man", "please", "or"]
    /// After "Did it…/Did that…": these mean the subject was left out ("Did that already").
    private static let notVerbs: Set<String> = ["already", "yesterday", "today", "earlier", "before", "again", "too", "twice", "once", "last",
        "just", "as", "for", "with", "in", "on", "at", "and", "but", "so", "myself", "ourselves"]

    private struct Token { let word: String; let capital: Bool; let comma: Bool }

    static func isQuestion(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        var tokens: [Token] = []
        for raw in sentence.split(whereSeparator: { $0 == " " }) {
            let word = raw.lowercased().replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: CharacterSet(charactersIn: "\"“”‘'()[],;:—-…"))
            guard !word.isEmpty else { continue }
            tokens.append(Token(word: word, capital: raw.first(where: \.isLetter)?.isUppercase ?? false, comma: raw.hasSuffix(",")))
        }
        guard tokens.count >= 2 else { return false }

        // A tag on the end: "…, right", "…, isn't it", "…, don't you".
        if lower.range(of: #",\s*(right|isn't it|aren't (you|they|we)|don't (you|they|we)|doesn't it|didn't (you|we|they|it|he|she)|won't (you|it|they)|can't (you|we)|wasn't it|weren't (you|they)|shouldn't (we|i)|wouldn't (you|it)|huh)\s*$"#, options: .regularExpression) != nil { return true }
        // Asking about something rather than asking it: "I wonder if…", "Let me know when…".
        if lower.range(of: #"^\s*(i wonder|i was wondering|i'm wondering|let me know|tell me|not sure|no idea|i don't know|i dunno|guess)\b"#, options: .regularExpression) != nil { return false }
        // "Why we did it is what I don't get", "What's new can be the changelog": a clause as the subject.
        if lower.range(of: #"\b(is|was) (what|why|how|where|when|the reason|beyond me|unclear|a mystery)\b"#, options: .regularExpression) != nil { return false }
        if lower.range(of: #"^\s*(what|who)('s| is) \w+ (is|was|can|could|will|would|should|must|has|needs|means|matters|goes)\b"#, options: .regularExpression) != nil { return false }

        // Skip openers and a short name after a greeting: "Hey Alfred, what do you…".
        var k = 0
        while k < tokens.count - 1, openers.contains(tokens[k].word) { k += 1 }
        if k > 0, k < tokens.count - 1, tokens[k].capital, !subjects.contains(tokens[k].word), !auxiliaries.contains(tokens[k].word), !whWords.contains(tokens[k].word) {
            if tokens[k].comma { k += 1 } else if k + 1 < tokens.count - 1, tokens[k + 1].comma { k += 2 }
        }
        let t = Array(tokens[k...])
        guard t.count >= 2 || ["why", "how", "what"].contains(t.first?.word ?? "") else { return false }
        // A question that trails into a plain statement: "What's up, so I was thinking…".
        if let c = t.firstIndex(where: \.comma), c + 2 < t.count {
            var r = c + 1
            if ["so", "and", "but"].contains(t[r].word) { r += 1 }
            if r + 1 < t.count, ["i", "we"].contains(t[r].word),
               ["was", "were", "think", "thought", "just", "wanted", "want", "have", "had", "am", "need", "guess", "mean", "feel"].contains(t[r + 1].word) { return false }
        }
        let w0 = t[0].word, w1 = t.count > 1 ? t[1].word : "", w2 = t.count > 2 ? t[2].word : ""
        let subject1 = subjects.contains(w1) || (t.count > 1 && t[1].capital && !auxiliaries.contains(w1))

        // Yes/no questions: an auxiliary, then who it's about.
        if copulas.contains(w0) { return subject1 }
        if ["will", "won't"].contains(w0) { return subjects.contains(w1) }       // "Will Smith said…" is not one
        if modals.contains(w0) { return subjects.contains(w1) }
        if ["may", "might"].contains(w0) { return ["i", "we"].contains(w1) }     // "May the best one win" is not one
        if ["do", "don't"].contains(w0) { return (pronouns.contains(w1) && w1 != "it") || ["people", "guys", "any", "these", "those"].contains(w1) }   // "Do it", "Do a research", "Don't show this" are orders
        if ["does", "doesn't", "has", "hasn't", "had", "hadn't"].contains(w0) { return subject1 }
        if ["did", "didn't"].contains(w0) {
            guard subject1 else { return false }
            if ["it", "that", "this"].contains(w1) { return !w2.isEmpty && !notVerbs.contains(w2) }
            return true
        }
        if ["have", "haven't"].contains(w0) { return pronouns.contains(w1) }       // "Have a good one" is not one
        if w0 == "am" { return w1 == "i" }
        if w0 == "any" { return ["idea", "ideas", "update", "updates", "news", "thoughts", "chance", "luck", "word", "feedback", "questions", "plans", "clue", "reason"].contains(w1) }

        // Wh-questions.
        let whContracted = ["what's", "where's", "how's", "who's", "when's", "why's", "what're", "who're", "how'd", "what'd", "where'd", "why'd",
                            "who'd", "what've", "what'll", "who'll", "where'll", "how'll", "when'll"]
        if whContracted.contains(w0) { return !pronouns.contains(w1) || w0.hasSuffix("'s") }
        guard whWords.contains(w0) else { return false }
        if ["about", "come"].contains(w1) && ["how", "what"].contains(w0) { return true }          // "How about Friday", "How come", "What about it"
        if w0 == "what" && w1 == "if" { return true }
        if w0 == "why" && w1 == "not" { return true }
        if auxiliaries.contains(w1) { return true }                                               // "Why did…", "Where is…", "What do you…"
        if pronouns.contains(w1) { return false }                                                 // "What you say…", "When I got home…"
        if ["what", "which", "whose", "how"].contains(w0) {
            // "What time is it", "Which one should I pick", "How long does it take", "How many are coming".
            if w0 == "how", !["much", "many", "long", "often", "far", "big", "old", "soon", "late", "early", "fast", "good", "bad", "well", "hard", "else", "exactly"].contains(w1) { return false }
            // The auxiliary must be followed by its subject ("is it", "should I"); only "how many/much"
            // may ask about the subject itself ("How many are coming"). "What matters is speed" is a statement.
            let rest = Array(t.dropFirst(2).prefix(4))
            if let a = rest.firstIndex(where: { auxiliaries.contains($0.word) }) {
                if w0 == "how", ["many", "much"].contains(w1) { return true }
                return a + 1 < rest.count && subjects.contains(rest[a + 1].word)
            }
            return false
        }
        if ["who", "what"].contains(w0) {
            // "Who wants coffee", "What happened": the wh-word is the subject. Short, and no
            // "is/was" later ("What matters is speed").
            let verbish = w1.hasSuffix("s") || w1.hasSuffix("ed") || ["said", "made", "took", "got", "went", "broke", "wrote", "came", "knew", "told", "did", "ate"].contains(w1)
            return verbish && t.count <= 8 && !t.dropFirst(2).contains { ["is", "was", "are", "were"].contains($0.word) }
        }
        return false
    }

    // MARK: Hyphens

    /// Always one word with a hyphen, wherever they stand.
    private static let alwaysHyphen: [(NSRegularExpression, String)] = [
        (#"\b(self) (hosted|driving|serve|service|employed|aware|explanatory|contained|made|taught|funded|sufficient|care|paced|published)\b"#, "$1-$2"),
        (#"\b(co) (founders?|founded|pilot|author|working)\b"#, "$1-$2"),
        (#"\b([Ww]i) ?([Ff]i)\b"#, "Wi-Fi"), (#"\b([Tt]) (shirts?)\b"#, "$1-$2"), (#"\b([Ee]) (commerce|book|books|sign|signature)\b"#, "$1-$2"),
        (#"\b([Xx]) (rays?)\b"#, "$1-$2"), (#"\b(one) (on) (one)\b"#, "$1-$2-$3"),
    ].map { (try! NSRegularExpression(pattern: "(?i)" + $0.0), $0.1) }

    /// Hyphenated only in front of what they describe: "a one-time purchase", "real-time updates";
    /// "we met one time", "in real time", "it's open source." stay as they are.
    private static let compounds: [String] = [
        "state of the art", "end to end", "up to date", "out of the box", "day to day", "peer to peer", "face to face", "step by step",
        "side by side", "back to back", "easy to use", "nice to have", "off the shelf", "word of mouth",
        "one time", "real time", "long term", "short term", "open source", "built in", "full time", "part time", "last minute",
        "high quality", "low quality", "high level", "low level", "first class", "world class", "well known", "well designed", "fine tuned",
        "hands free", "one click", "long running", "open ended", "third party", "first party", "on device", "top notch",
        "cutting edge", "next gen", "full stack", "front end", "back end", "real world", "long form", "short form", "user facing",
        "customer facing", "data driven", "AI powered", "privacy first", "offline first", "mobile first", "high end", "low end",
        "follow up", "check in", "add on", "pop up", "drop down", "opt in", "opt out", "sign in", "run through", "mock up", "write up", "must have",
    ]
    private static let compoundRE: NSRegularExpression = {
        let alt = compounds.sorted { $0.count > $1.count }.map { $0.replacingOccurrences(of: " ", with: #"\s"#) }.joined(separator: "|")
        return try! NSRegularExpression(pattern: #"(?i)(?<![\w-])("# + alt + #")(?=( [\w'’]+)?)"#)
    }()
    /// Verb-like pairs ("follow up", "check in"…) take the hyphen only as a noun: after a/the/this….
    private static let verbPairs: Set<String> = ["must have", "follow up", "check in", "add on", "pop up", "drop down", "opt in", "opt out", "sign in", "run through", "mock up", "write up"]
    private static let determiners: Set<String> = ["a", "an", "the", "this", "that", "our", "your", "my", "their", "his", "her", "its", "quick", "another", "one", "product"]
    /// What can't be the noun being described: the compound stands on its own.
    private static let notNouns: Set<String> = ["is", "are", "was", "were", "be", "been", "and", "or", "but", "to", "of", "in", "on", "at", "for", "with", "by",
        "the", "a", "an", "it", "that", "this", "only", "again", "now", "today", "too", "so", "if", "then", "as", "than", "from", "i", "we", "you",
        "they", "he", "she", "basis", "please", "right", "yet", "anyway", "though", "about", "because", "when", "while", "since", "until",
        "can", "will", "would", "should", "could", "do", "does", "did", "has", "have", "had", "not", "just", "very", "really", "all",
        "here", "there", "actually", "basically", "instead", "first", "maybe", "max", "total", "ago", "later", "enough", "overall", "anyway"]
    private static let unitRE = try! NSRegularExpression(pattern:
        #"(?i)\b(\d+|one|two|three|four|five|six|seven|eight|nine|ten|twelve|fifteen|twenty|thirty|forty|fifty|sixty|ninety|hundred) (second|minute|hour|day|week|month|year|step|page|point|person|mile|foot|inch|star|player|seat|dollar)(?= ([a-z][\w'’]*))"#)

    static func hyphens(_ text: String) -> String {
        var s = text
        for (re, template) in alwaysHyphen { s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template) }
        var ns = s as NSString
        for m in compoundRE.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let phrase = ns.substring(with: m.range(at: 1)), lower = phrase.lowercased()
            let before = ns.substring(to: m.range.location).split(separator: " ").last.map { $0.lowercased() } ?? ""
            if verbPairs.contains(lower) {
                guard determiners.contains(before) else { continue }                  // "a follow-up"; "I'll follow up" stays a verb
            } else {
                let nextRange = m.range(at: 2)
                guard nextRange.location != NSNotFound else { continue }             // ends the sentence: stands alone
                if notNouns.contains(String(ns.substring(with: nextRange).dropFirst().lowercased())) { continue }
                if lower == "one time", !["a", "the", "this", "that", "your", "our"].contains(before) { continue }   // "one time, very simple"
            }
            s = ns.replacingCharacters(in: m.range(at: 1), with: phrase.replacingOccurrences(of: " ", with: "-")); ns = s as NSString
        }
        for m in unitRE.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let next = ns.substring(with: m.range(at: 3)).lowercased()
            if notNouns.contains(next) { continue }
            if ["ago", "later", "long", "old", "away", "early", "late", "left", "each", "per", "ahead", "behind"].contains(next) { continue }
            let r = NSRange(location: m.range(at: 1).location, length: m.range(at: 2).location + m.range(at: 2).length - m.range(at: 1).location)
            s = ns.replacingCharacters(in: r, with: ns.substring(with: m.range(at: 1)) + "-" + ns.substring(with: m.range(at: 2))); ns = s as NSString
        }
        return s
    }

    // MARK: Capitals

    private static let loneI = try! NSRegularExpression(pattern: #"(?<![\w'’.])i(?=(?:['’](?:m|ve|ll|d))?(?![\w'’])(?!\.\w))"#)
    private static let sentenceStart = try! NSRegularExpression(pattern: #"([.?!])( +)([a-z])"#)

    /// "i" → "I" (and i'm, i've…), and a sentence that begins in lowercase gets its capital.
    static func capitals(_ text: String) -> String {
        var s = loneI.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "I")
        let ns = s as NSString
        for m in sentenceStart.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let before = ns.substring(to: m.range.location)
            if ns.substring(with: m.range(at: 1)) == ".", isAbbreviation(before) { continue }
            let r = m.range(at: 3)
            s = (s as NSString).replacingCharacters(in: r, with: ns.substring(with: r).uppercased())
        }
        return s
    }
}
