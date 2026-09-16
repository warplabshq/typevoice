import Foundation
import Observation

struct Dictation: Identifiable, Codable, Sendable, Equatable, Hashable {
    var id = UUID()
    var text: String
    var date: Date
    var appName: String
    var seconds: Double
}

/// Every dictation, newest first. Lives in ~/Library/Application Support/Murmur/history.json.
@MainActor
@Observable
final class HistoryStore {
    private(set) var entries: [Dictation]
    static let cap = 2000

    init() {
        entries = JSONFile.load([Dictation].self, from: Paths.history) ?? []
    }

    func add(_ d: Dictation) {
        entries.insert(d, at: 0)
        if entries.count > Self.cap { entries.removeLast(entries.count - Self.cap) }
        persist()
    }

    func delete(_ ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    var recent: ArraySlice<Dictation> { entries.prefix(10) }

    private func persist() { JSONFile.save(entries, to: Paths.history) }
}
