import Foundation
import SQLite3

/// SQLite + FTS5 store for dictations. Handles millions of words without
/// breaking a sweat; search is indexed, stats are one aggregate query.
final class HistoryDB: @unchecked Sendable {
    private var db: OpaquePointer?
    private let q = DispatchQueue(label: "typevoice.history", qos: .userInitiated)

    struct Stats: Sendable, Equatable {
        var count = 0
        var words = 0
        var seconds: Double = 0
        var weekCount = 0
        var weekWords = 0
        var wordsPerMinute: Double { seconds > 0 ? Double(words) / (seconds / 60) : 0 }
    }

    init(url: URL) {
        q.sync {
            guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
                Log.app.error("sqlite open failed: \(String(cString: sqlite3_errmsg(self.db)))")
                return
            }
            exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")
            exec("""
            CREATE TABLE IF NOT EXISTS dictations(
                id TEXT PRIMARY KEY, text TEXT NOT NULL, date REAL NOT NULL,
                app TEXT NOT NULL, bundle TEXT, seconds REAL NOT NULL, words INTEGER NOT NULL, latency_ms INTEGER
            );
            CREATE INDEX IF NOT EXISTS dictations_date ON dictations(date DESC);
            CREATE INDEX IF NOT EXISTS dictations_date_words ON dictations(date, words, seconds);
            CREATE TABLE IF NOT EXISTS totals(id INTEGER PRIMARY KEY CHECK (id = 1), count INTEGER NOT NULL, words INTEGER NOT NULL, seconds REAL NOT NULL);
            INSERT OR IGNORE INTO totals(id, count, words, seconds)
                SELECT 1, COUNT(*), COALESCE(SUM(words),0), COALESCE(SUM(seconds),0) FROM dictations;
            CREATE TRIGGER IF NOT EXISTS t_ai AFTER INSERT ON dictations BEGIN
                UPDATE totals SET count = count + 1, words = words + new.words, seconds = seconds + new.seconds WHERE id = 1; END;
            CREATE TRIGGER IF NOT EXISTS t_ad AFTER DELETE ON dictations BEGIN
                UPDATE totals SET count = count - 1, words = words - old.words, seconds = seconds - old.seconds WHERE id = 1; END;
            CREATE VIRTUAL TABLE IF NOT EXISTS dictations_fts USING fts5(text, content='dictations', content_rowid='rowid', tokenize='porter unicode61');
            CREATE TRIGGER IF NOT EXISTS d_ai AFTER INSERT ON dictations BEGIN
                INSERT INTO dictations_fts(rowid, text) VALUES (new.rowid, new.text); END;
            CREATE TRIGGER IF NOT EXISTS d_ad AFTER DELETE ON dictations BEGIN
                INSERT INTO dictations_fts(dictations_fts, rowid, text) VALUES('delete', old.rowid, old.text); END;
            """)
        }
    }

    deinit { sqlite3_close(db) }

    // MARK: Writes

    func insert(_ d: Dictation) {
        q.async { [self] in
            let sql = "INSERT OR REPLACE INTO dictations(id,text,date,app,bundle,seconds,words,latency_ms) VALUES(?,?,?,?,?,?,?,?)"
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(st) }
            bind(st, 1, d.id.uuidString); bind(st, 2, d.text)
            sqlite3_bind_double(st, 3, d.date.timeIntervalSince1970)
            bind(st, 4, d.appName); bind(st, 5, d.bundleID)
            sqlite3_bind_double(st, 6, d.seconds)
            sqlite3_bind_int(st, 7, Int32(d.words))
            if let l = d.latencyMs { sqlite3_bind_int(st, 8, Int32(l)) } else { sqlite3_bind_null(st, 8) }
            sqlite3_step(st)
        }
    }

    func delete(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        q.sync {
            exec("BEGIN")
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM dictations WHERE id=?", -1, &st, nil) == SQLITE_OK else { exec("ROLLBACK"); return }
            for id in ids { sqlite3_reset(st); bind(st, 1, id.uuidString); sqlite3_step(st) }
            sqlite3_finalize(st)
            exec("COMMIT")
        }
    }

    func clear() {
        q.sync { exec("DELETE FROM dictations; UPDATE totals SET count = 0, words = 0, seconds = 0 WHERE id = 1; INSERT INTO dictations_fts(dictations_fts) VALUES('rebuild'); VACUUM;") }
    }

    // MARK: Reads

    func page(query: String?, since: Date? = nil, before: Date?, beforeRow: Int64?, limit: Int) -> [Dictation] {
        q.sync {
            let trimmed = query?.trimmingCharacters(in: .whitespaces) ?? ""
            let sinceT = since?.timeIntervalSince1970 ?? 0
            if trimmed.isEmpty {
                return rows(sql: "SELECT rowid,id,text,date,app,bundle,seconds,words,latency_ms FROM dictations WHERE (? IS NULL OR date < ?) AND date >= ? ORDER BY date DESC LIMIT ?") { st in
                    if let b = before { sqlite3_bind_double(st, 1, b.timeIntervalSince1970); sqlite3_bind_double(st, 2, b.timeIntervalSince1970) }
                    else { sqlite3_bind_null(st, 1); sqlite3_bind_null(st, 2) }
                    sqlite3_bind_double(st, 3, sinceT)
                    sqlite3_bind_int(st, 4, Int32(limit))
                }
            }
            // Two steps: let FTS5 walk matches newest-first by rowid (cheap even when a
            // common word matches everything), then fetch just those rows.
            var ids: [Int64] = []
            var st: OpaquePointer?
            let ftsSQL = "SELECT rowid FROM dictations_fts WHERE dictations_fts MATCH ? AND (? IS NULL OR rowid < ?) ORDER BY rowid DESC LIMIT ?"
            guard sqlite3_prepare_v2(db, ftsSQL, -1, &st, nil) == SQLITE_OK else {
                Log.app.error("sqlite fts: \(String(cString: sqlite3_errmsg(self.db)))"); return []
            }
            bind(st, 1, Self.ftsQuery(trimmed))
            if let r = beforeRow { sqlite3_bind_int64(st, 2, r); sqlite3_bind_int64(st, 3, r) } else { sqlite3_bind_null(st, 2); sqlite3_bind_null(st, 3) }
            sqlite3_bind_int(st, 4, Int32(limit))
            while sqlite3_step(st) == SQLITE_ROW { ids.append(sqlite3_column_int64(st, 0)) }
            sqlite3_finalize(st)
            guard !ids.isEmpty else { return [] }
            let list = ids.map(String.init).joined(separator: ",")
            return rows(sql: "SELECT rowid,id,text,date,app,bundle,seconds,words,latency_ms FROM dictations WHERE rowid IN (\(list)) AND date >= ? ORDER BY rowid DESC") { st in
                sqlite3_bind_double(st, 1, sinceT)
            }
        }
    }

    /// Runs a SELECT with the standard column order and maps rows.
    private func rows(sql: String, bind bindValues: (OpaquePointer?) -> Void) -> [Dictation] {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else {
            Log.app.error("sqlite page: \(String(cString: sqlite3_errmsg(self.db)))"); return []
        }
        defer { sqlite3_finalize(st) }
        bindValues(st)
        var out: [Dictation] = []
        while sqlite3_step(st) == SQLITE_ROW {
            var d = Dictation(
                id: UUID(uuidString: col(st, 1)) ?? UUID(),
                text: col(st, 2),
                date: Date(timeIntervalSince1970: sqlite3_column_double(st, 3)),
                appName: col(st, 4),
                bundleID: sqlite3_column_type(st, 5) == SQLITE_NULL ? nil : col(st, 5),
                seconds: sqlite3_column_double(st, 6),
                words: Int(sqlite3_column_int(st, 7)),
                latencyMs: sqlite3_column_type(st, 8) == SQLITE_NULL ? nil : Int(sqlite3_column_int(st, 8))
            )
            d.rowid = sqlite3_column_int64(st, 0)
            out.append(d)
        }
        return out
    }

    /// O(1) totals from the maintained `totals` row plus an index-range scan for the week.
    func stats() -> Stats {
        q.sync {
            var s = Stats()
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT count, words, seconds FROM totals WHERE id = 1", -1, &st, nil) == SQLITE_OK {
                if sqlite3_step(st) == SQLITE_ROW {
                    s.count = Int(sqlite3_column_int64(st, 0))
                    s.words = Int(sqlite3_column_int64(st, 1))
                    s.seconds = sqlite3_column_double(st, 2)
                }
                sqlite3_finalize(st)
            }
            let weekAgo = Date().addingTimeInterval(-7 * 86400).timeIntervalSince1970
            if sqlite3_prepare_v2(db, "SELECT COUNT(*), COALESCE(SUM(words),0) FROM dictations WHERE date > ?", -1, &st, nil) == SQLITE_OK {
                sqlite3_bind_double(st, 1, weekAgo)
                if sqlite3_step(st) == SQLITE_ROW {
                    s.weekCount = Int(sqlite3_column_int64(st, 0))
                    s.weekWords = Int(sqlite3_column_int64(st, 1))
                }
                sqlite3_finalize(st)
            }
            return s
        }
    }

    // MARK: Helpers

    /// Prefix-match every word the user typed: `vid ai` → `"vid"* "ai"*`.
    private static func ftsQuery(_ q: String) -> String {
        q.split(whereSeparator: { $0.isWhitespace })
            .map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }
            .joined(separator: " ")
    }

    private func exec(_ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK, let err {
            Log.app.error("sqlite: \(String(cString: err))"); sqlite3_free(err)
        }
    }

    private func bind(_ st: OpaquePointer?, _ i: Int32, _ s: String?) {
        if let s { sqlite3_bind_text(st, i, s, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        else { sqlite3_bind_null(st, i) }
    }

    private func col(_ st: OpaquePointer?, _ i: Int32) -> String {
        sqlite3_column_text(st, i).map { String(cString: $0) } ?? ""
    }
}
