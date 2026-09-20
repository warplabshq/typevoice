import SwiftUI

struct StyleView: View {
    @AppStorage(Prefs.Key.casing) private var casing = Style.Casing.sentence.rawValue
    @AppStorage(Prefs.Key.punctuation) private var punctuation = Style.Punctuation.full.rawValue
    @AppStorage(Prefs.Key.tone) private var tone = Style.Tone.natural.rawValue
    @AppStorage(Prefs.Key.removeFillers) private var removeFillers = true
    @AppStorage(Prefs.Key.fixStutters) private var fixStutters = true
    @AppStorage(Prefs.Key.smartCleanup) private var smart = true
    @AppStorage(Prefs.Key.numbersAsDigits) private var numbers = true
    @AppStorage(Prefs.Key.pauseParagraphs) private var pauseParagraphs = true
    @AppStorage(Prefs.Key.voiceCommands) private var voiceCommands = true
    @State private var aiStatus = SmartCleaner.status

    private static let sample = "okay so um the the launch is Tuesday, no wait, Wednesday, and I think we're gonna need like two more days for QA, it's very very close"

    private var style: Style {
        Style(casing: .init(rawValue: casing) ?? .sentence,
              punctuation: .init(rawValue: punctuation) ?? .full,
              tone: .init(rawValue: tone) ?? .natural,
              removeFillers: removeFillers, fixStutters: fixStutters)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("You say")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("“\(Self.sample)”")
                        .font(.body).foregroundStyle(.secondary)
                    Text("You get")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                    Text(preview)
                        .font(.body)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.2), value: preview)
                }
                .padding(.vertical, 4)
            }
            Section("Casing") {
                Picker("Casing", selection: $casing) {
                    ForEach(Style.Casing.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Section("Punctuation") {
                Picker("Punctuation", selection: $punctuation) {
                    ForEach(Style.Punctuation.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(style.punctuation.detail).font(.caption).foregroundStyle(.secondary)
            }
            Section("Cleanup") {
                Toggle("Remove filler words", isOn: $removeFillers)
                Text("um, uh, hmm. “like” and “so” are left alone because they're often real words.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Fix stutters", isOn: $fixStutters)
                Text("“the the” becomes “the”. Repeats for emphasis like “very very” or “no no” are always kept. Turn off to keep every repeat.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Numbers as digits", isOn: $numbers)
                Text("“twenty twenty four” becomes 2024, “five dollars fifty” becomes $5.50. Small numbers stay as words.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Paragraph after a pause", isOn: $pauseParagraphs)
                Text("Finish a sentence, pause a second, and the next one starts a new paragraph.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Spoken commands") {
                Toggle("Voice commands", isOn: $voiceCommands)
                Text("Say “new line”, “new paragraph”, “bullet …”, or “number one …, number two …” to shape the text.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("What you can say") { CheatsheetWindow.show() }.buttonStyle(.link).font(.caption)
            }
            Section("Smart cleanup") {
                Toggle("Smart cleanup", isOn: $smart)
                Text("Fixes false starts and self-corrections with Apple Intelligence, on this Mac. Never adds anything.")
                    .font(.caption).foregroundStyle(.secondary)
                // A definite answer, not a shrug: is Apple's model doing the cleanup right now?
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(aiStatus.isReady ? Color.green : Color.orange).frame(width: 8, height: 8).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(aiStatus.title).font(.callout.weight(.medium))
                        Text(aiStatus.detail).font(.caption).foregroundStyle(.secondary)
                        if aiStatus.canOpenSettings {
                            Button("Open Siri & Apple Intelligence settings") { Permissions.openAppleIntelligencePane() }
                                .buttonStyle(.link).font(.caption).padding(.top, 2)
                        }
                    }
                }
                .onAppear { aiStatus = SmartCleaner.status }
                .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in aiStatus = SmartCleaner.status }
            }
            Section("Tone") {
                Picker("Tone", selection: $tone) {
                    ForEach(Style.Tone.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!smart)
                Text(smart ? style.tone.detail : "Tone needs Smart cleanup, above.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// A faithful preview of the deterministic layers, plus a hand-written
    /// stand-in for what the model does with the self-correction.
    private var preview: String {
        var s = Cleaner.clean(Self.sample, style: style)
        if smart {
            s = s.replacingOccurrences(of: "Tuesday, no wait, Wednesday", with: "Wednesday")
            s = s.replacingOccurrences(of: "okay so ", with: "", options: .caseInsensitive)
            s = s.replacingOccurrences(of: "need like two", with: "need two")
            switch style.tone {
            case .formal:
                s = s.replacingOccurrences(of: "we're gonna need", with: "we will need")
                    .replacingOccurrences(of: "I think ", with: "")
            case .casual, .natural:
                s = s.replacingOccurrences(of: "gonna", with: "going to")
            }
        }
        s = Cleaner.fit(s, to: .unknown, style: style)
        if style.punctuation == .full, !s.hasSuffix(".") { s += "." }
        return style.finish(s)
    }
}
