import Foundation
import SQLite3

/// SQLite + FTS5 store for dictations. Handles millions of words without
/// breaking a sweat; search is indexed, stats are one aggregate query.
final class HistoryDB: @unchecked Sendable {
    private var db: OpaquePointer?
    private let q = DispatchQueue(label: "murmur.history", qos: .userInitiated)

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
        q.sync {
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
        q.sync { exec("DELETE FROM dictations; INSERT INTO dictations_fts(dictations_fts) VALUES('rebuild'); VACUUM;") }
    }

    // MARK: Reads

    func page(query: String?, before: Date?, limit: Int) -> [Dictation] {
        q.sync {
            var sql: String
            let trimmed = query?.trimmingCharacters(in: .whitespaces) ?? ""
            if trimmed.isEmpty {
                sql = "SELECT id,text,date,app,bundle,seconds,words,latency_ms FROM dictations WHERE (? IS NULL OR date < ?) ORDER BY date DESC LIMIT ?"
            } else {
                sql = """
                SELECT d.id,d.text,d.date,d.app,d.bundle,d.seconds,d.words,d.latency_ms FROM dictations d
                JOIN dictations_fts f ON f.rowid = d.rowid
                WHERE dictations_fts MATCH ? AND (? IS NULL OR d.date < ?) ORDER BY d.date DESC LIMIT ?
                """
            }
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else {
                Log.app.error("sqlite page: \(String(cString: sqlite3_errmsg(self.db)))"); return []
            }
            defer { sqlite3_finalize(st) }
            var i: Int32 = 1
            if !trimmed.isEmpty { bind(st, i, Self.ftsQuery(trimmed)); i += 1 }
            if let b = before { sqlite3_bind_double(st, i, b.timeIntervalSince1970); sqlite3_bind_double(st, i + 1, b.timeIntervalSince1970) }
            else { sqlite3_bind_null(st, i); sqlite3_bind_null(st, i + 1) }
            sqlite3_bind_int(st, i + 2, Int32(limit))
            var out: [Dictation] = []
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(Dictation(
                    id: UUID(uuidString: col(st, 0)) ?? UUID(),
                    text: col(st, 1),
                    date: Date(timeIntervalSince1970: sqlite3_column_double(st, 2)),
                    appName: col(st, 3),
                    bundleID: sqlite3_column_type(st, 4) == SQLITE_NULL ? nil : col(st, 4),
                    seconds: sqlite3_column_double(st, 5),
                    words: Int(sqlite3_column_int(st, 6)),
                    latencyMs: sqlite3_column_type(st, 7) == SQLITE_NULL ? nil : Int(sqlite3_column_int(st, 7))
                ))
            }
            return out
        }
    }

    func stats() -> Stats {
        q.sync {
            var s = Stats()
            let weekAgo = Date().addingTimeInterval(-7 * 86400).timeIntervalSince1970
            var st: OpaquePointer?
            let sql = """
            SELECT COUNT(*), COALESCE(SUM(words),0), COALESCE(SUM(seconds),0),
                   COALESCE(SUM(CASE WHEN date > ? THEN 1 ELSE 0 END),0),
                   COALESCE(SUM(CASE WHEN date > ? THEN words ELSE 0 END),0)
            FROM dictations
            """
            guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return s }
            defer { sqlite3_finalize(st) }
            sqlite3_bind_double(st, 1, weekAgo); sqlite3_bind_double(st, 2, weekAgo)
            if sqlite3_step(st) == SQLITE_ROW {
                s.count = Int(sqlite3_column_int64(st, 0))
                s.words = Int(sqlite3_column_int64(st, 1))
                s.seconds = sqlite3_column_double(st, 2)
                s.weekCount = Int(sqlite3_column_int64(st, 3))
                s.weekWords = Int(sqlite3_column_int64(st, 4))
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
