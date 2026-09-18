import Foundation
import Observation

struct Dictation: Identifiable, Codable, Sendable, Equatable, Hashable {
    var id = UUID()
    var text: String
    var date: Date
    var appName: String
    var bundleID: String? = nil
    var seconds: Double
    var words: Int = 0
    var latencyMs: Int? = nil
    /// Database row id, used as the paging cursor for searches. Not persisted in exports.
    var rowid: Int64? = nil
    /// Recording on disk, resolved once when the page loads (a stat per row per frame
    /// while scrolling is what made Summary stutter). Not persisted.
    var audioURL: URL? = nil

    enum CodingKeys: String, CodingKey { case id, text, date, appName, bundleID, seconds, words, latencyMs }

    static func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    init(id: UUID = UUID(), text: String, date: Date, appName: String, bundleID: String? = nil,
         seconds: Double, words: Int = 0, latencyMs: Int? = nil) {
        self.id = id; self.text = text; self.date = date; self.appName = appName
        self.bundleID = bundleID; self.seconds = seconds; self.words = words; self.latencyMs = latencyMs
    }

    /// Tolerant of older files that lack the newer fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decode(String.self, forKey: .text)
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .now
        appName = try c.decodeIfPresent(String.self, forKey: .appName) ?? ""
        bundleID = try c.decodeIfPresent(String.self, forKey: .bundleID)
        seconds = try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
        words = try c.decodeIfPresent(Int.self, forKey: .words) ?? Dictation.wordCount(text)
        latencyMs = try c.decodeIfPresent(Int.self, forKey: .latencyMs)
    }
}

/// Paged, searchable view over `HistoryDB`. The UI only ever holds one page.
@MainActor
@Observable
final class HistoryStore {
    private let db: HistoryDB
    private(set) var entries: [Dictation] = []
    private(set) var stats = HistoryDB.Stats()
    private(set) var hasMore = false
    var query = "" { didSet { if query != oldValue { reload() } } }
    /// How far back Summary looks. Narrower than "all" keeps the list a page or two long.
    enum Range: String, CaseIterable, Identifiable {
        case today, week, month, all
        var id: String { rawValue }
        var label: String {
            switch self { case .today: "Today"; case .week: "7 days"; case .month: "30 days"; case .all: "All" }
        }
        var since: Date? {
            let cal = Calendar.current
            switch self {
            case .today: return cal.startOfDay(for: .now)
            case .week: return cal.date(byAdding: .day, value: -7, to: .now)
            case .month: return cal.date(byAdding: .day, value: -30, to: .now)
            case .all: return nil
            }
        }
    }
    /// Opens on the last seven days every launch; the picker widens it for the session.
    var range: Range = .week { didSet { if range != oldValue { reload() } } }
    /// Thirty rows keeps the list light; older ones arrive on request.
    static let pageSize = 30

    init() {
        db = HistoryDB(url: Paths.support.appendingPathComponent("history.sqlite"))
        migrateJSONIfNeeded()
        reload()
    }

    func add(_ d: Dictation) {
        var d = d
        if d.words == 0 { d.words = Dictation.wordCount(d.text) }
        db.insert(d)
        d.audioURL = RecordingStore.url(for: d.id)
        if query.isEmpty { entries.insert(d, at: 0) } else { reload() }
        stats = db.stats()
    }

    /// A recording saved after the row was added (it's encoded in the background).
    func attachAudio(id: UUID, url: URL) {
        if let i = entries.firstIndex(where: { $0.id == id }) { entries[i].audioURL = url }
    }

    private static func withAudio(_ page: [Dictation]) -> [Dictation] {
        page.map { var d = $0; d.audioURL = RecordingStore.url(for: d.id); return d }
    }

    func delete(_ ids: Set<UUID>) {
        ids.forEach(RecordingStore.delete)
        db.delete(Array(ids))
        entries.removeAll { ids.contains($0.id) }
        stats = db.stats()
    }

    func clear() {
        RecordingStore.deleteAll()
        db.clear()
        entries.removeAll()
        stats = db.stats()
    }

    func reload() {
        let page = Self.withAudio(db.page(query: query, since: range.since, before: nil, beforeRow: nil, limit: Self.pageSize))
        entries = page
        hasMore = page.count == Self.pageSize
        stats = db.stats()
    }

    func loadMore() {
        guard hasMore, let last = entries.last else { return }
        let page = Self.withAudio(db.page(query: query, since: range.since, before: last.date, beforeRow: last.rowid, limit: Self.pageSize))
        entries += page
        hasMore = page.count == Self.pageSize
    }

    var recent: ArraySlice<Dictation> { entries.prefix(10) }

    /// Everything, newest first, for export.
    func all() -> [Dictation] {
        var out: [Dictation] = []
        var before: Date? = nil
        while true {
            let page = db.page(query: nil, before: before, beforeRow: nil, limit: 2000)
            out += page
            if page.count < 2000 { break }
            before = page.last?.date
        }
        return out
    }
    var isEmpty: Bool { stats.count == 0 }

    /// One-time import of the v0 JSON file.
    private func migrateJSONIfNeeded() {
        let old = Paths.history
        guard FileManager.default.fileExists(atPath: old.path),
              let items = JSONFile.load([Dictation].self, from: old) else { return }
        for var d in items { if d.words == 0 { d.words = Dictation.wordCount(d.text) }; db.insert(d) }
        try? FileManager.default.moveItem(at: old, to: old.appendingPathExtension("migrated"))
        Log.app.info("migrated \(items.count) dictations from JSON")
    }
}
