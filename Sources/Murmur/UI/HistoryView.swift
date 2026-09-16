import AppKit
import SwiftUI

struct HistoryView: View {
    let history: HistoryStore
    @State private var query = ""
    @State private var selection = Set<UUID>()
    @State private var confirmClear = false
    @State private var copiedID: UUID?

    private var filtered: [Dictation] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return history.entries }
        return history.entries.filter { $0.text.localizedCaseInsensitiveContains(q) || $0.appName.localizedCaseInsensitiveContains(q) }
    }

    private var grouped: [(String, [Dictation])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: filtered) { d -> Date in cal.startOfDay(for: d.date) }
        return dict.keys.sorted(by: >).map { day in
            let title: String
            if cal.isDateInToday(day) { title = "Today" }
            else if cal.isDateInYesterday(day) { title = "Yesterday" }
            else { title = day.formatted(.dateTime.weekday(.wide).day().month(.wide)) }
            return (title, dict[day]!)
        }
    }

    var body: some View {
        Group {
            if history.entries.isEmpty {
                ContentUnavailableView {
                    Label("No dictations yet", systemImage: "waveform")
                } description: {
                    Text("Hold 🌐 anywhere, say something, and it'll show up here.")
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(selection: $selection) {
                    ForEach(grouped, id: \.0) { day, items in
                        Section(day) {
                            ForEach(items) { d in
                                HistoryRow(d: d, copied: copiedID == d.id) { copy(d) } onDelete: { history.delete([d.id]) }
                                    .tag(d.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .onDeleteCommand { history.delete(selection); selection.removeAll() }
                .onCopyCommand {
                    let items = history.entries.filter { selection.contains($0.id) }
                    return [NSItemProvider(object: items.map(\.text).joined(separator: "\n") as NSString)]
                }
            }
        }
        .navigationTitle("History")
        .searchable(text: $query, placement: .toolbar, prompt: "Search dictations")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) { confirmClear = true } label: {
                    Label("Clear History", systemImage: "trash")
                }
                .disabled(history.entries.isEmpty)
                .help("Delete every dictation")
            }
        }
        .confirmationDialog("Clear all \(history.entries.count) dictations?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { history.clear(); selection.removeAll() }
        } message: {
            Text("This only affects Murmur's history on this Mac. Text you already inserted into other apps stays where it is.")
        }
    }

    private func copy(_ d: Dictation) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(d.text, forType: .string)
        copiedID = d.id
        Task { try? await Task.sleep(for: .seconds(1.2)); if copiedID == d.id { copiedID = nil } }
    }
}

private struct HistoryRow: View {
    let d: Dictation
    let copied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(d.text)
                    .font(.body)
                    .lineLimit(3)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Text(d.appName)
                    Text("·")
                    Text(d.date, style: .time)
                    Text("·")
                    Text(String(format: "%.0fs", d.seconds))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Button(action: onCopy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .help("Copy")
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .help("Delete")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(copied ? Color.accentColor : .secondary)
            .opacity(hover || copied ? 1 : 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .contextMenu {
            Button("Copy", action: onCopy)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
