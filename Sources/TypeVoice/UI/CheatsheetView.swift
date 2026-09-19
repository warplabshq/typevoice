import AppKit
import SwiftUI

/// Everything you can do with your voice and the trigger, on one card.
struct CheatsheetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What you can say").font(.title2.weight(.semibold))
                Text("Hold \(Prefs.triggerLabel), talk, let go. The rest is optional.").foregroundStyle(.secondary)
            }
            group("The trigger", [
                ("Hold \(Prefs.triggerLabel)", "Dictate while held; the words are typed when you let go."),
                ("Tap twice", "Keep listening hands-free; tap once to finish."),
                ("Esc", "Cancel; nothing is typed."),
            ])
            group("While talking", [
                ("“new line” · “new paragraph”", "A line or paragraph break."),
                ("“bullet …”", "A bulleted line; say “bullet” before each item."),
                ("“number one …, number two …”", "A numbered list."),
                ("A pause after a sentence", "Starts a new paragraph on its own."),
            ])
            group("After", [
                ("Copy glyph on the pill", "Copies the words if you'd rather paste them yourself."),
                ("Drag audio", "With the audio option on, drag your voice into any chat."),
                ("Summary", "Every dictation, searchable, with time saved."),
            ])
            Text("Voice commands and pause paragraphs can be turned off in Settings › Dictating.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(26)
        .frame(width: 460, alignment: .leading)
    }

    private func group(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).kerning(0.6)
            ForEach(rows, id: \.0) { r in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(r.0).font(.system(.body, design: .rounded).weight(.medium)).frame(width: 190, alignment: .leading)
                    Text(r.1).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A small floating window for the cheatsheet; one instance, brought forward on repeat.
@MainActor
enum CheatsheetWindow {
    private static var window: NSWindow?

    static func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentViewController: NSHostingController(rootView: CheatsheetView()))
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
