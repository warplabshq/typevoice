import AppKit
import SwiftUI

struct MenuContent: View {
    let state: AppState
    let history: HistoryStore

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
        Button("Help…") { NSWorkspace.shared.open(Brand.supportURL) }
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
