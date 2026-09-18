import Foundation
import Observation

/// Words and phrases spelled the way the user wants them: product names, people,
/// jargon. Used for fuzzy correction of the transcript and as hints to cleanup.
@MainActor
@Observable
final class DictionaryStore {
    private(set) var terms: [String]

    init() {
        terms = JSONFile.load([String].self, from: Paths.dictionary) ?? []
    }

    @discardableResult
    func add(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !terms.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) else { return false }
        terms.append(t)
        terms.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        persist()
        return true
    }

    func remove(_ term: String) {
        terms.removeAll { $0 == term }
        persist()
    }

    func clear() {
        terms.removeAll()
        persist()
    }

    private func persist() { JSONFile.save(terms, to: Paths.dictionary) }
}
