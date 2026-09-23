import Foundation

/// Spoken web addresses. People say "typevoice dot ai", "logs dot so", "jane at example dot com",
/// "slash support"; the model writes the words, or turns "dot" into a full stop and starts a new
/// sentence ("logs. So"). Both forms become the address they meant.
enum Spoken {
    /// Endings that are not English words: after a full stop they can only be a domain.
    static let clearTLDs: Set<String> = ["com", "ai", "io", "xyz", "co", "ly", "gg", "fm", "sh", "tv", "org", "net", "edu", "gov",
                                         "biz", "eu", "uk", "de", "fr", "es", "nl", "se", "ch", "jp", "kr", "br", "au", "nz", "sg", "ae"]
    /// Endings that are also ordinary words ("so", "dev", "app", "live"): joined when the speaker
    /// said "dot" out loud, or when the model's full stop is followed by the end of the sentence
    /// or by a word it did not capitalise.
    static let wordTLDs: Set<String> = ["so", "in", "us", "me", "it", "is", "to", "be", "no", "at", "ca", "id", "am", "do", "cc",
                                        "dev", "app", "info", "site", "online", "tech", "store", "shop", "cloud", "page", "link", "live",
                                        "news", "blog", "design", "studio", "agency", "email", "chat", "video", "games", "wiki",
                                        "pro", "one", "new", "now", "run", "art", "fun", "top", "best", "world", "zone", "space", "life", "team", "today"]

    static func apply(_ text: String) -> String {
        var s = text
        // "jane at example dot com", "typevoice dot ai slash support": spelled out.
        s = joinSpoken(s)
        // "logs. So", "typevoice. Ai": the model heard "dot" as a full stop.
        s = joinStops(s)
        return s
    }

    private static let all = clearTLDs.union(wordTLDs)
    private static let tldAlt = all.sorted { $0.count > $1.count }.joined(separator: "|")

    /// dot → ".", and "at" → "@" when it introduces a domain, "slash" → "/" after one.
    private static func joinSpoken(_ text: String) -> String {
        var s = text
        // word dot tld (optionally dot tld again: "dot co dot uk")
        let domain = try! NSRegularExpression(pattern: #"(?i)\b([a-z0-9][a-z0-9-]*)\s+dot\s+(?:(\#(tldAlt))\s+dot\s+)?(\#(tldAlt))\b"#)
        s = domain.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1.$2.$3")
        s = s.replacingOccurrences(of: "..", with: ".")
        // an email: "name at domain.tld" (the domain just got its dot). "the docs are at typevoice.ai"
        // is not one: the name must look like a handle, or follow "to", "email", "cc"…
        let email = try! NSRegularExpression(pattern: #"(?i)(?:^|\b(\w+)\s+)([a-z0-9][a-z0-9._+-]*)\s+at\s+([a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:\#(tldAlt)))\b"#)
        let ns = s as NSString
        for m in email.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let before = m.range(at: 1).location == NSNotFound ? "" : ns.substring(with: m.range(at: 1)).lowercased()
            let local = ns.substring(with: m.range(at: 2)), domain = ns.substring(with: m.range(at: 3))
            let handleLike = local.contains(where: { $0.isNumber || "._+-".contains($0) }) || !English.isWord(local)
            let introduced = ["to", "email", "mail", "cc", "bcc", "contact", "reach", "write", "ping", "message", "address", "or"].contains(before)
            guard handleLike || introduced else { continue }
            let lead = m.range(at: 1).location == NSNotFound ? "" : ns.substring(with: m.range(at: 1)) + " "
            s = (s as NSString).replacingCharacters(in: m.range, with: "\(lead)\(local)@\(domain)")
        }
        // "typevoice.ai slash support slash faq"
        let slash = try! NSRegularExpression(pattern: #"(?i)(\b[a-z0-9.-]+\.(?:\#(tldAlt)))\s+slash\s+([a-z0-9][a-z0-9-]*)"#)
        var prev = ""
        while prev != s {
            prev = s
            s = slash.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1/$2")
        }
        return s
    }

    /// "word. Tld" → "word.tld". Clear endings always; word-like endings only when the part before
    /// the stop is not an ordinary English word (so "check logs. So we…" survives, "typevoice. Ai" joins).
    private static func joinStops(_ text: String) -> String {
        let re = try! NSRegularExpression(pattern: #"\b([A-Za-z0-9][A-Za-z0-9-]*)\.\s+([A-Za-z]{2,7})\b(?![.\w-]*@)"#)
        let ns = text as NSString
        var out = text
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let head = ns.substring(with: m.range(at: 1)), tail = ns.substring(with: m.range(at: 2))
            let tld = tail.lowercased()
            guard all.contains(tld) else { continue }
            let after = m.range.location + m.range.length
            let rest = (after < ns.length ? ns.substring(from: after) : "").drop(while: { $0 == " " })
            // "it's", "so," and friends carry on a sentence; a domain ends at a stop or the end.
            if let f = rest.first, "'’,;:".contains(f) { continue }
            let endsHere = rest.first.map { ".!?)".contains($0) } ?? true
            if wordTLDs.contains(tld) {
                // "Check the logs. So we should…" is a sentence; "it's on logs. So." is a domain,
                // and so is "logs. so" (the model would have capitalised a new sentence).
                let modelCapitalised = tail.first!.isUppercase
                guard endsHere || !modelCapitalised else { continue }
            } else if let f = rest.first, f.isUppercase {
                continue   // "…com. The next thing" – a real sentence boundary after the domain
            }
            out = (out as NSString).replacingCharacters(in: m.range, with: "\(head).\(tld)")
        }
        return out
    }
}
