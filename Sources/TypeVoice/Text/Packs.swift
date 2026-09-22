import Foundation

/// Word packs: lists of spellings the speech model tends to mangle (developer tools, internet
/// slang, anything the person imports), matched by sound against the transcript the same way
/// the Dictionary is, but only where the model itself was unsure. Files inside the app or in
/// Application Support; nothing is fetched.
enum Packs {
    struct Pack: Identifiable, Equatable {
        let id: String          // file name without extension
        let name: String
        let url: URL
        let count: Int
        let builtIn: Bool
    }

    /// Only replace a span whose least confident piece scored below this. Confident spans are
    /// what the person said; a pack must never "correct" those.
    static let confidenceGate: Float = 0.85

    static var importedFolder: URL { Paths.support.appendingPathComponent("Packs", isDirectory: true) }

    static func builtIn() -> [Pack] {
        let names = ["developer-tools": "Developer tools", "internet-slang": "Internet slang"]
        return names.compactMap { id, name in
            guard let url = Bundle.module.url(forResource: id, withExtension: "txt", subdirectory: "Packs") else { return nil }
            return Pack(id: id, name: name, url: url, count: lineCount(url), builtIn: true)
        }.sorted { $0.name < $1.name }
    }

    static func imported() -> [Pack] {
        let files = (try? FileManager.default.contentsOfDirectory(at: importedFolder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "txt" }.map {
            Pack(id: "import:" + $0.deletingPathExtension().lastPathComponent, name: $0.deletingPathExtension().lastPathComponent,
                 url: $0, count: lineCount($0), builtIn: false)
        }.sorted { $0.name < $1.name }
    }

    static func all() -> [Pack] { builtIn() + imported() }

    /// Copies a text file (one term per line) into the imported folder and switches it on.
    @discardableResult
    static func importFile(_ source: URL) throws -> Pack {
        try FileManager.default.createDirectory(at: importedFolder, withIntermediateDirectories: true)
        let name = source.deletingPathExtension().lastPathComponent
        let dest = importedFolder.appendingPathComponent(name + ".txt")
        let text = try String(contentsOf: source, encoding: .utf8)
        try text.write(to: dest, atomically: true, encoding: .utf8)
        let pack = Pack(id: "import:" + name, name: name, url: dest, count: lineCount(dest), builtIn: false)
        if !Prefs.packs.contains(pack.id) { Prefs.packs.append(pack.id) }
        Index.invalidate()
        return pack
    }

    static func remove(_ pack: Pack) {
        guard !pack.builtIn else { return }
        try? FileManager.default.removeItem(at: pack.url)
        Prefs.packs.removeAll { $0 == pack.id }
        Index.invalidate()
    }

    static func setEnabled(_ pack: Pack, _ on: Bool) {
        var ids = Prefs.packs
        ids.removeAll { $0 == pack.id }
        if on { ids.append(pack.id) }
        Prefs.packs = ids
        Index.invalidate()
    }

    /// The terms in a pack file: one per line; blank lines and `#` comments are skipped.
    static func terms(in url: URL) -> [String] {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private static func lineCount(_ url: URL) -> Int { terms(in: url).count }

    // MARK: The index

    /// Every enabled term, keyed by the first letter and length of its phonetic form, so a
    /// span of the transcript only meets the handful of terms that could possibly match.
    final class Index: Sendable {
        struct Entry: Sendable { let term: String; let phon: String; let skel: String; let words: Int }
        let buckets: [String: [Entry]]       // "\(firstChar)\(phonCount)" → entries
        let count: Int
        let maxWords: Int
        /// Spellings that are right as they are: every term of every pack (enabled or not) and
        /// the household names in known.txt. The model saying "Reddit" must stay "Reddit", not
        /// become the pack's "Rediff" because the two sound alike.
        let known: Set<String>

        init(terms: [String], known: [String] = []) {
            var b: [String: [Entry]] = [:]
            var maxW = 1
            var k = Set<String>(minimumCapacity: known.count + terms.count)
            for t in known { k.insert(Packs.key(t)) }
            for t in terms { k.insert(Packs.key(t)) }
            self.known = k
            for t in terms {
                let key = Vocabulary.normalize(t)
                let phon = Vocabulary.phonetic(key)
                guard let f = phon.first, phon.count >= 2 else { continue }
                let e = Entry(term: t, phon: phon, skel: Vocabulary.skeleton(phon), words: max(1, t.split(separator: " ").count))
                b["\(f)\(phon.count)", default: []].append(e)
                maxW = max(maxW, e.words)
            }
            buckets = b; count = terms.count; maxWords = min(maxW, 3)
        }

        func candidates(for phon: String) -> [Entry] {
            guard let f = phon.first else { return [] }
            let n = Double(phon.count)
            var out: [Entry] = []
            for len in Int((n / 1.5).rounded(.up))...Int(n / 0.6) { out += buckets["\(f)\(len)"] ?? [] }
            return out
        }

        // One shared index, rebuilt in the background whenever the enabled set changes.
        nonisolated(unsafe) private static var cached: Index?
        nonisolated(unsafe) private static var building = false
        private static let lock = NSLock()

        static var current: Index? { lock.withLock { cached } }

        static func invalidate() {
            lock.withLock { cached = nil }
            warm()
        }

        static func warm(ids: [String]? = nil) {
            lock.withLock { if building || cached != nil { return }; building = true }
            let enabled = Set(ids ?? Prefs.packs)
            Task.detached(priority: .utility) {
                var terms: [String] = [], known: [String] = []
                for pack in Packs.all() {
                    if enabled.contains(pack.id) { terms += Packs.terms(in: pack.url) } else { known += Packs.terms(in: pack.url) }
                }
                if let url = Bundle.module.url(forResource: "known", withExtension: "txt", subdirectory: "Packs") { known += Packs.terms(in: url) }
                let t0 = ContinuousClock.now
                let index = Index(terms: terms, known: known)
                Log.timing("packs.index(\(terms.count))", since: t0)
                lock.withLock { cached = index; building = false }
            }
        }
    }

    // MARK: Correction

    /// Replaces spans the model was unsure about with pack terms that sound the same.
    static func correct(_ words: [Structure.Word], dictionary: [String] = []) -> [Structure.Word] {
        guard let index = Index.current, index.count > 0, !words.isEmpty else { return words }
        let yours = Set(dictionary.map(key))
        var out = words
        var i = 0
        while i < out.count {
            for span in stride(from: min(index.maxWords + 1, out.count - i), through: 1, by: -1) {
                let slice = out[i..<(i + span)]
                // A misheard term leaves every one of its pieces doubtful; a span that includes a
                // word the model was sure of is not a candidate.
                guard slice.allSatisfy({ $0.confidence < confidenceGate }) else { continue }
                let minConf = slice.map(\.confidence).min() ?? 1
                let parts = slice.map { strip($0.text) }
                let candidate = parts.map(\.core).joined()
                guard candidate.count >= 3 else { continue }
                // Spelled like a name we know (a pack term, a household name, your Dictionary):
                // the model heard it right, however unsure it was.
                let spelled = key(parts.map(\.core).joined(separator: " "))
                if index.known.contains(spelled) || yours.contains(spelled) { continue }
                let cPhon = Vocabulary.phonetic(candidate)
                guard cPhon.count >= 2 else { continue }
                // Real words that merely sound like a term ("sell it" / sqlite) need a much closer
                // match than a non-word does: the model may well have heard them right.
                let allReal = parts.allSatisfy { English.isWord($0.core) }
                var best: (entry: Index.Entry, score: Double)?
                for e in index.candidates(for: cPhon)
                where Vocabulary.matches(candidatePhon: cPhon, keyPhon: e.phon, keySkel: e.skel) {
                    let score = Vocabulary.similarity(cPhon, e.phon)
                    if allReal, score < 0.85 { continue }
                    if best == nil || score > best!.score { best = (e, score) }
                }
                if let hit = best, key(hit.entry.term) != spelled {
                    let text = (parts.first?.lead ?? "") + hit.entry.term + (parts.last?.trail ?? "")
                    Log.d("pack: \"\(slice.map(\.text).joined(separator: " "))\" → \(hit.entry.term) (\(String(format: "%.2f", hit.score)), confidence \(String(format: "%.2f", minConf)))")
                    out.replaceSubrange(i..<(i + span), with: [Structure.Word(text: text, gapBefore: slice.first!.gapBefore, confidence: 1)])
                    break
                }
            }
            i += 1
        }
        return out
    }

    /// How spellings are compared: no case, no possessive. Spaces stay, so "rip grep" is
    /// not yet "ripgrep" and still gets fixed.
    static func key(_ s: String) -> String {
        var k = s.lowercased()
        if k.hasSuffix("'s") || k.hasSuffix("’s") { k.removeLast(2) }
        return k
    }

    private static func strip(_ w: String) -> (lead: String, core: String, trail: String) {
        var core = w, lead = "", trail = ""
        while let f = core.first, "\"'(“‘[".contains(f) { lead.append(f); core.removeFirst() }
        while let l = core.last, "\"'),.!?;:”’]…".contains(l) { trail.insert(l, at: trail.startIndex); core.removeLast() }
        return (lead, core, trail)
    }
}

/// The Mac's own word list (/usr/share/dict/words, on every Mac, read once): what counts as a
/// real English word when deciding how sure a pack must be before it overrides one.
enum English {
    nonisolated(unsafe) private static var words: Set<String> = {
        guard let s = try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8) else { return [] }
        var set = Set<String>(minimumCapacity: 240_000)
        for line in s.split(separator: "\n") { set.insert(line.lowercased()) }
        return set
    }()
    static func isWord(_ w: String) -> Bool {
        let core = w.lowercased().trimmingCharacters(in: .punctuationCharacters)
        guard !core.isEmpty else { return true }
        if words.contains(core) { return true }
        for (suffix, stem) in [("ies", "y"), ("es", ""), ("s", ""), ("ed", ""), ("ed", "e"), ("ing", ""), ("ing", "e"), ("'s", "")]
        where core.hasSuffix(suffix) && core.count > suffix.count + 2 {
            if words.contains(String(core.dropLast(suffix.count)) + stem) { return true }
        }
        return false
    }
}
