import AppKit
import Observation

/// The menu bar item, in AppKit. The item and its menu belong to this object, which lives as
/// long as the app; the menu is rebuilt from scratch every time it opens, so no item ever
/// carries an action bound to something that has since gone away. (1.0.6 crashed in exactly
/// that way with SwiftUI's MenuBarExtra: a click on a menu item whose callback had been
/// released while the menu was still up.)
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let state: AppState
    private let history: HistoryStore
    private let licensing: Licensing
    private let item: NSStatusItem
    private let menu = NSMenu()
    private var shown: MenuBarIcon.Look = .resting
    private var animator: Task<Void, Never>?
    private var defaultsObserver: Any?

    init(state: AppState, history: HistoryStore, licensing: Licensing) {
        self.state = state; self.history = history; self.licensing = licensing
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        menu.delegate = self
        item.menu = menu
        item.button?.image = shown.image
        item.button?.imagePosition = .imageOnly
        item.isVisible = Prefs.showMenuBarIcon
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.item.isVisible = Prefs.showMenuBarIcon }
        }
        observe()
    }

    // MARK: The glyph

    /// Re-run whenever the phase or the pause flag changes (Observation fires once per change).
    private func observe() {
        withObservationTracking {
            refreshIcon(to: MenuBarIcon.look(for: state.phase, paused: state.paused))
        } onChange: {
            Task { @MainActor [weak self] in self?.observe() }
        }
    }

    private func refreshIcon(to target: MenuBarIcon.Look) {
        item.button?.setAccessibilityLabel(accessibilityLabel)
        guard target != shown else { return }
        animator?.cancel()
        let from = shown
        // Eight small frames over ~240 ms, eased out: the bars lift instead of snapping.
        animator = Task { @MainActor [weak self] in
            let steps = 8
            for i in 1...steps {
                try? await Task.sleep(for: .milliseconds(30))
                if Task.isCancelled { return }
                let t = CGFloat(i) / CGFloat(steps)
                let eased = 1 - pow(1 - t, 3)
                self?.show(MenuBarIcon.Look.mix(from, target, eased))
            }
            self?.show(target)
        }
    }

    private func show(_ look: MenuBarIcon.Look) {
        shown = look
        item.button?.image = look.image
    }

    private var accessibilityLabel: String {
        if state.paused { return "\(Brand.name), paused" }
        switch state.phase {
        case .listening: return "\(Brand.name), listening"
        case .processing: return "\(Brand.name), typing"
        default: return Brand.name
        }
    }

    /// Debug hook: pop the menu for a moment so it can be screenshotted, then close it.
    func debugFlashMenu(seconds: Double = 2) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.menu.cancelTracking() }
        item.button?.performClick(nil)
    }

    // MARK: The menu, rebuilt on every open

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Status line, or the one thing that needs fixing first.
        if state.accessibilityMissing {
            menu.addItem(action("Accessibility permission missing — fix…") { Permissions.openAccessibilityPane() })
        } else {
            let text = !state.isReady ? (state.warmError ?? state.warm.label)
                     : state.paused ? "Paused" : "Hold \(Prefs.triggerLabel) to dictate"
            menu.addItem(label(text))
        }
        // A quiet nudge in the last two days of the trial, and the way back in after it.
        switch licensing.state {
        case .trial(let days) where days <= 2:
            menu.addItem(action(days == 1 ? "Last day of your trial · Buy \(Brand.name)…" : "\(days) days left in your trial · Buy…") { openMainWindow(.license) })
        case .expired:
            menu.addItem(action("Trial ended · Enter a license key…") { openMainWindow(.license) })
        default: break
        }
        menu.addItem(.separator())
        menu.addItem(action("Open \(Brand.name)", key: "o") { openMainWindow(.history) })
        menu.addItem(action(state.paused ? "Resume" : "Pause", key: "p") { [weak self] in self?.state.paused.toggle() })

        // The last three dictations, right here: click one to copy it.
        let recent = Array(history.recent.prefix(3))
        if !recent.isEmpty {
            menu.addItem(.separator())
            menu.addItem(label("Recent · click to copy"))
            for d in recent {
                let text = d.text
                menu.addItem(action(Self.line(d)) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                })
            }
        }
        menu.addItem(.separator())
        menu.addItem(action("Dictionary…") { openMainWindow(.dictionary) })
        menu.addItem(action("Settings…", key: ",") { openMainWindow(.settings) })
        let updates = action("Check for Updates…") { Updater.shared.check() }
        updates.isEnabled = Updater.isConfigured
        menu.addItem(updates)
        let help = NSMenu(title: "Help")
        help.addItem(action("What You Can Say…") { CheatsheetWindow.show() })
        help.addItem(action("Help Online…") { NSWorkspace.shared.open(Brand.supportURL) })
        help.addItem(action("Source Code…") { NSWorkspace.shared.open(Brand.sourceURL) })
        help.addItem(action("Report a Problem…") { [weak self] in if let s = self { Support.reportProblem(state: s.state) } })
        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        helpItem.submenu = help
        menu.addItem(helpItem)
        menu.addItem(.separator())
        menu.addItem(action("Quit \(Brand.name)", key: "q") { NSApp.terminate(nil) })
    }

    /// One menu line: the start of the sentence and how long ago, e.g. "Can we move the launch… · 2m".
    static func line(_ d: Dictation) -> String {
        let text = d.text.replacingOccurrences(of: "\n", with: " ")
        let head = text.count > 56 ? String(text.prefix(56)).trimmingCharacters(in: .whitespaces) + "…" : text
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        let ago = Date.now.timeIntervalSince(d.date) < 60 ? "now" : f.localizedString(for: d.date, relativeTo: .now)
        return "\(head)  ·  \(ago)"
    }

    // MARK: Items

    /// A disabled, informational row.
    private func label(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    /// An item whose closure runs when it is chosen. The closure is held by the item, the item
    /// by the menu, the menu by this controller: nothing here outlives its owner.
    private func action(_ title: String, key: String = "", _ run: @escaping @MainActor () -> Void) -> NSMenuItem {
        let i = ClosureItem(title: title, key: key, run: run)
        return i
    }

    /// AppKit sends the action on the main thread; the item is main-actor so the closure runs
    /// directly, with no executor check in between (the 1.0.6 crash was inside that check).
    @MainActor
    private final class ClosureItem: NSMenuItem {
        private let run: @MainActor () -> Void
        init(title: String, key: String, run: @escaping @MainActor () -> Void) {
            self.run = run
            super.init(title: title, action: #selector(fire), keyEquivalent: key)
            target = self
        }
        required init(coder: NSCoder) { fatalError() }
        @objc private func fire() { run() }
    }
}
