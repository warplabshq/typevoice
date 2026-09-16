import AppKit
import SwiftUI

struct HistoryView: View {
    let history: HistoryStore
    @State private var query = ""
    @State private var selection = Set<UUID>()
    @State private var confirmClear = false
    @State private var copiedID: UUID?

    private var grouped: [(String, [Dictation])] {
        let cal = Calendar.current
        var order: [Date] = []
        var dict: [Date: [Dictation]] = [:]
        for d in history.entries {
            let day = cal.startOfDay(for: d.date)
            if dict[day] == nil { order.append(day); dict[day] = [] }
            dict[day]!.append(d)
        }
        return order.map { day in
            let title: String
            if cal.isDateInToday(day) { title = "Today" }
            else if cal.isDateInYesterday(day) { title = "Yesterday" }
            else { title = day.formatted(.dateTime.weekday(.wide).day().month(.wide)) }
            return (title, dict[day]!)
        }
    }

    var body: some View {
        Group {
            if history.isEmpty {
                ContentUnavailableView {
                    Label("No dictations yet", systemImage: "waveform")
                } description: {
                    Text("Hold 🌐 anywhere, say something, and it'll show up here.")
                }
            } else {
                List(selection: $selection) {
                    if query.isEmpty {
                        Section {
                            statsRow
                                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 10, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    if history.entries.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    ForEach(grouped, id: \.0) { day, items in
                        Section {
                            ForEach(items) { d in
                                HistoryRow(d: d, copied: copiedID == d.id) { copy(d) } onDelete: { history.delete([d.id]) }
                                    .tag(d.id)
                                    .onAppear { if d.id == history.entries.last?.id { history.loadMore() } }
                            }
                        } header: {
                            Text(day).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .onDeleteCommand { history.delete(selection); selection.removeAll() }
                .onCopyCommand {
                    let items = history.entries.filter { selection.contains($0.id) }
                    return [NSItemProvider(object: items.map(\.text).joined(separator: "\n") as NSString)]
                }
            }
        }
        .navigationTitle("History")
        .searchable(text: $query, placement: .toolbar, prompt: "Search")
        .onChange(of: query) { _, q in history.query = q }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) { confirmClear = true } label: {
                    Label("Clear History", systemImage: "trash")
                }
                .disabled(history.isEmpty)
                .help("Delete every dictation")
            }
        }
        .confirmationDialog("Clear all \(history.stats.count.formatted()) dictations?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { history.clear(); selection.removeAll() }
        } message: {
            Text("This only affects Murmur's history on this Mac. Text you already inserted into other apps stays where it is.")
        }
    }

    private var statsRow: some View {
        let s = history.stats
        return HStack(spacing: 12) {
            StatTile(value: Fmt.count(s.words), label: "Words", detail: "\(Fmt.count(s.weekWords)) this week")
            StatTile(value: Fmt.count(s.count), label: "Dictations", detail: "\(Fmt.count(s.weekCount)) this week")
            StatTile(value: Fmt.duration(s.seconds), label: "Time talking", detail: s.seconds > 0 ? "≈ \(Fmt.duration(s.seconds * 3.2)) of typing saved" : nil)
            StatTile(value: s.wordsPerMinute > 0 ? "\(Int(s.wordsPerMinute))" : "–", label: "Words / min", detail: "typing is about 40")
        }
        .fixedSize(horizontal: false, vertical: true)
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
            AppIconView(bundleID: d.bundleID, size: 24)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(d.text)
                    .font(.body)
                    .lineLimit(3)
                    .textSelection(.enabled)
                HStack(spacing: 5) {
                    Text(d.appName)
                    Text("·")
                    Text(d.date, style: .time)
                    Text("·")
                    Text("\(d.words) words")
                    Text("·")
                    Text(Fmt.duration(d.seconds))
                    if let l = d.latencyMs {
                        Text("·")
                        Text("\(l) ms").help("Key-up to text inserted")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                Button(action: onCopy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 24, height: 24)
                }
                .help("Copy")
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash").frame(width: 24, height: 24)
                }
                .help("Delete")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(copied ? Color.accentColor : .secondary)
            .opacity(hover || copied ? 1 : 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .contextMenu {
            Button("Copy", action: onCopy)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
