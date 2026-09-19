import AppKit
import SwiftUI

struct HistoryView: View {
    let history: HistoryStore
    @State private var query = ""
    @State private var selection = Set<UUID>()
    @State private var confirmClear = false
    @State private var copiedID: UUID?
    @State private var playingID: UUID?

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
                VStack(spacing: 16) {
                    statsRow.padding(.horizontal, 16).padding(.top, 8)
                    ContentUnavailableView {
                        Label("No dictations yet", systemImage: "waveform")
                    } description: {
                        Text("Hold \(Prefs.triggerLabel) anywhere, say something, and it'll show up here.")
                    }
                }
            } else {
                List(selection: $selection) {
                    if query.isEmpty {
                        Section {
                            statsRow
                                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 14, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                    if history.entries.isEmpty {
                        Group {
                            if query.isEmpty {
                                ContentUnavailableView("Nothing in the last \(history.range.label.lowercased())", systemImage: "calendar",
                                                       description: Text("Pick a wider range above."))
                            } else {
                                ContentUnavailableView.search(text: query)
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    ForEach(grouped, id: \.0) { day, items in
                        Section {
                            ForEach(items) { d in
                                HistoryRow(d: d, copied: copiedID == d.id, playing: playingID == d.id) { copy(d) } onDelete: { history.delete([d.id]) }
                                    .tag(d.id)
                            }
                        } header: {
                            Text(day).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    if history.hasMore {
                        // Older pages come when asked for, like Mail, not by scrolling past the end.
                        Section {
                            Button { history.loadMore() } label: {
                                Label("Show earlier dictations", systemImage: "arrow.down.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .padding(.vertical, 6)
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
        .onReceive(NotificationCenter.default.publisher(for: .typevoicePlaybackChanged)) { _ in playingID = RecordingPlayer.shared.playingID }
        .searchable(text: $query, placement: .toolbar, prompt: "Search")
        .onChange(of: query) { _, q in history.query = q }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Range", selection: Binding(get: { history.range }, set: { history.range = $0 })) {
                    ForEach(HistoryStore.Range.allCases) { r in Text(r.label).tag(r) }
                }
                .pickerStyle(.segmented)
                .help("How far back to show")
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Plain text (.txt)") { export(.txt) }
                    Button("Markdown (.md)") { export(.md) }
                    Button("CSV (.csv)") { export(.csv) }
                    Button("JSON (.json)") { export(.json) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(history.isEmpty)
                .help("Export all dictations")
            }
            ToolbarItem(placement: .destructiveAction) {
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
            Text("This only affects \(Brand.name)'s history on this Mac. Text you already inserted into other apps stays where it is.")
        }
    }

    /// Typing the same words at 40 words a minute, plus the backspacing and re-reading
    /// that comes with typing (about a fifth again), minus the time actually spent talking.
    static func secondsSaved(words: Int, talking: Double) -> Double {
        max(0, Double(words) / 40 * 60 * 1.2 - talking)
    }

    /// What the saved time is good for. Largest thing that fits, with a nod to the change.
    static func funLine(minutes: Double) -> String {
        let units: [(Double, String, String)] = [
            (2400, "take a week off", "take %d weeks off"),
            (480, "take a whole working day off", "take %d working days off"),
            (300, "read a short novel", "read %d short novels"),
            (120, "watch a feature film", "watch %d feature films"),
            (45, "play an album start to finish", "play %d albums start to finish"),
            (22, "watch a sitcom episode, ads skipped", "watch %d sitcom episodes, ads skipped"),
            (15, "watch a TED talk", "watch %d TED talks"),
            (6, "read a five-page chapter", "read %d five-page chapters"),
            (3.5, "listen to a song", "listen to %d songs"),
        ]
        guard minutes >= 1 else { return "Keep talking; this grows fast." }
        guard let (unit, one, many) = units.first(where: { minutes >= $0.0 }) else { return "Enough to stretch your legs." }
        let n = Int(minutes / unit)
        let rest = (minutes - Double(n) * unit) / unit
        let what = n == 1 ? one : String(format: many, n)
        return "That's enough to \(what)" + (rest >= 0.5 ? ", and then some." : ".")
    }

    private var statsRow: some View {
        let s = history.stats
        let saved = Self.secondsSaved(words: s.words, talking: s.seconds)
        return VStack(spacing: 12) {
            Card(padding: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Time saved")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(Fmt.durationLong(saved))
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Color(red: 0.20, green: 0.78, blue: 0.45))
                                .contentTransition(.numericText())
                            if s.weekWords > 0 {
                                Text("\(Fmt.durationLong(Self.secondsSaved(words: s.weekWords, talking: weekSeconds))) this week")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if s.count == 0 {
                            Text("Hold \(Prefs.triggerLabel) anywhere and start talking.")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                        } else {
                            Text(Self.funLine(minutes: saved / 60))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .contentTransition(.opacity)
                            Text("Against typing at 40 words a minute, fixes included. You speak at about \(Int(s.wordsPerMinute.rounded())).")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    // The brand's bars, alive: a calm synthetic voice in the same green.
                    WaveformView(bars: 8, barWidth: 3, gap: 3 * BrandWave.gapRatio, color: Color(red: 0.20, green: 0.78, blue: 0.45).opacity(0.8), demo: true)
                        .frame(width: 66, height: 30)
                        .accessibilityHidden(true)
                }
            }
            HStack(spacing: 12) {
                StatTile(value: Fmt.count(s.words), label: "Words", detail: "\(Fmt.count(s.weekWords)) this week")
                StatTile(value: Fmt.count(s.count), label: "Dictations", detail: "\(Fmt.count(s.weekCount)) this week")
                StatTile(value: Fmt.duration(s.seconds), label: "Time talking", detail: s.count > 0 ? "\(Int(s.seconds / Double(s.count)))s on average" : nil)
                StatTile(value: s.wordsPerMinute > 0 ? "\(Int(s.wordsPerMinute))" : "–", label: "Words / min", detail: "typing is about 40")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Seconds spoken this week, estimated from this week's words at the overall pace.
    private var weekSeconds: Double {
        let s = history.stats
        guard s.wordsPerMinute > 0 else { return 0 }
        return Double(s.weekWords) / s.wordsPerMinute * 60
    }

    private enum ExportFormat: String { case txt, md, csv, json }

    private func export(_ format: ExportFormat) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(Brand.name) history.\(format.rawValue)"
        panel.canCreateDirectories = true
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            let items = history.all()
            let data: Data
            switch format {
            case .txt:
                data = items.map { "\($0.date.formatted(date: .abbreviated, time: .shortened)) · \($0.appName)\n\($0.text)\n" }
                    .joined(separator: "\n").data(using: .utf8)!
            case .md:
                var md = "# \(Brand.name) history\n\n"
                for d in items { md += "- **\(d.date.formatted(date: .abbreviated, time: .shortened))** · \(d.appName)\n\n  \(d.text)\n\n" }
                data = md.data(using: .utf8)!
            case .csv:
                func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
                var csv = "date,app,seconds,words,text\n"
                let iso = ISO8601DateFormatter()
                for d in items { csv += "\(iso.string(from: d.date)),\(q(d.appName)),\(d.seconds),\(d.words),\(q(d.text))\n" }
                data = csv.data(using: .utf8)!
            case .json:
                let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                data = (try? enc.encode(items)) ?? Data()
            }
            try? data.write(to: url, options: .atomic)
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
    let playing: Bool
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
                HStack(spacing: 5) {
                    Text(d.appName)
                    Text("·")
                    Text(d.date, style: .time)
                    Text("·")
                    Text(d.words == 1 ? "1 word" : "\(d.words) words")
                    Text("·")
                    Text(Fmt.duration(d.seconds))
                    if let l = d.latencyMs {
                        Text("·")
                        Text("\(l) ms").help("Key-up to text inserted")
                    }
                    if let url = d.audioURL {
                        Text("·")
                        Button {
                            RecordingPlayer.shared.toggle(id: d.id)
                        } label: {
                            Label(playing ? "Stop" : "Play", systemImage: playing ? "stop.fill" : "play.fill")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        // The AppKit drag source only exists for the row under the mouse;
                        // hosting one per row is what a heavy list is made of.
                        if hover {
                            RecordingDrag(url: url, fileName: RecordingStore.fileName(for: d.text)) {
                                Image(systemName: "waveform")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 2)
                            }
                            .fixedSize()
                            .help("Drag into a message to send the recording")
                        } else {
                            Image(systemName: "waveform")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 2)
                        }
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
            if let url = d.audioURL {
                Button("Reveal Recording in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
