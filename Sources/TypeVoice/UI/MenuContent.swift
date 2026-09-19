import AppKit
import SwiftUI

struct MenuContent: View {
    let state: AppState
    let history: HistoryStore
    let licensing: Licensing

    var body: some View {
        Group {
            if state.accessibilityMissing {
                Button("Accessibility permission missing — fix…") { Permissions.openAccessibilityPane() }
            } else if !state.isReady {
                Text(state.warmError ?? state.warm.label)
            } else if state.paused {
                Text("Paused")
            } else {
                Text("Hold \(Prefs.triggerLabel) to dictate")
            }
        }
        // A quiet nudge in the last stretch of the trial, and the way back in after it.
        switch licensing.state {
        case .trial(let days) where days <= 2:
            Button(days == 1 ? "Last day of your trial · Buy \(Brand.name)…" : "\(days) days left in your trial · Buy…") { openMainWindow(.license) }
        case .expired:
            Button("Trial ended · Enter a license key…") { openMainWindow(.license) }
        default:
            EmptyView()
        }
        Divider()
        Button("Open \(Brand.name)") { openMainWindow(.history) }
            .keyboardShortcut("o")
        Button(state.paused ? "Resume" : "Pause") { state.paused.toggle() }
            .keyboardShortcut("p")
        if !history.entries.isEmpty {
            Divider()
            // The last three, right here: click one to copy it.
            Text("Recent · click to copy")
            ForEach(history.recent.prefix(3)) { d in
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(d.text, forType: .string)
                } label: {
                    Text(Self.line(d))
                }
            }
        }
        Divider()
        Button("Dictionary…") { openMainWindow(.dictionary) }
        Button("Settings…") { openMainWindow(.settings) }
            .keyboardShortcut(",")
        if Updater.isConfigured {
            Button("Check for Updates…") { Updater.shared.check() }
        }
        Menu("Help") {
            Button("What You Can Say…") { CheatsheetWindow.show() }
            Button("Help Online…") { NSWorkspace.shared.open(Brand.supportURL) }
            Button("Report a Problem…") { Support.reportProblem(state: state) }
        }
        Divider()
        Button("Quit \(Brand.name)") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// One menu line: the start of the sentence and how long ago, e.g. "Can we move the launch… · 2m".
    static func line(_ d: Dictation) -> String {
        let text = d.text.replacingOccurrences(of: "\n", with: " ")
        let head = text.count > 56 ? String(text.prefix(56)).trimmingCharacters(in: .whitespaces) + "…" : text
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        let ago = Date.now.timeIntervalSince(d.date) < 60 ? "now" : f.localizedString(for: d.date, relativeTo: .now)
        return "\(head)  ·  \(ago)"
    }
}
