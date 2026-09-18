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
            Menu("Recent") {
                ForEach(history.recent) { d in
                    Button(String(d.text.prefix(48)) + (d.text.count > 48 ? "…" : "")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(d.text, forType: .string)
                    }
                }
            }
        }
        Divider()
        Button("Dictionary…") { openMainWindow(.dictionary) }
        Button("Settings…") { openMainWindow(.settings) }
            .keyboardShortcut(",")
        Button("Help…") { NSWorkspace.shared.open(Brand.supportURL) }
        Divider()
        Button("Quit \(Brand.name)") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
