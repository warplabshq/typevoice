import AppKit
import Combine
import SwiftUI

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage(Prefs.Key.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra("Murmur", systemImage: "waveform", isInserted: $showMenuBarIcon) {
            MenuContent(state: delegate.state, history: delegate.history)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static private(set) weak var shared: AppDelegate?

    let state = AppState()
    let history = HistoryStore()
    let dictionary = DictionaryStore()
    private(set) var controller: DictationController!
    private(set) var hud: HUDController!
    private var onboarding: NSWindow?
    private var main: NSWindow?
    private var mainTab: MainTab = .history
    private var observers: [Any] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if PipelineTest.runIfRequested() { return }
        Log.d("didFinishLaunching ax=\(Permissions.accessibility) mic=\(Permissions.mic) onboarded=\(Prefs.hasOnboarded)")
        Self.shared = self
        installMainMenu()
        if Log.debugTimings {
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("murmur.debug.showTab"), object: nil, queue: .main
            ) { n in
                Task { @MainActor in
                    if let raw = n.object as? String, let t = MainTab(rawValue: raw) { openMainWindow(t) }
                }
            }
        }
        controller = DictationController(state: state, history: history, dictionary: dictionary)
        hud = HUDController(state: state)
        controller.hud = hud

        observers.append(NotificationCenter.default.addObserver(
            forName: .murmurTriggerChanged, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.controller.restartHotkey() } })
        observers.append(NotificationCenter.default.addObserver(
            forName: .murmurOnboardingDone, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.finishOnboarding() } })
        observers.append(NotificationCenter.default.addObserver(
            forName: .murmurRetryWarm, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.controller.warm() } })

        if Prefs.hasOnboarded, Permissions.accessibility, Permissions.mic == .granted {
            controller.start()
        } else {
            showOnboarding()
            // Warm the model in the background so the last card is quick.
            controller.warm()
        }
        Log.app.info("Murmur launched")
        Log.d("launch complete; screens=\(NSScreen.screens.count)")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !Prefs.hasOnboarded { showOnboarding() } else { showMain() }
        return false
    }

    // MARK: Main window

    func showMain(tab: MainTab? = nil) {
        if let tab { mainTab = tab }
        if main == nil {
            let host = NSHostingController(rootView: MainRoot(delegate: self))
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = false
            w.toolbarStyle = .unified
            w.setContentSize(NSSize(width: 860, height: 560))
            w.minSize = NSSize(width: 720, height: 460)
            w.center()
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("MurmurMain")
            w.delegate = self
            main = w
        }
        NSApp.activate(ignoringOtherApps: true)
        main?.makeKeyAndOrderFront(nil)
        tabBinding.wrappedValue = mainTab
    }

    /// Accessory apps have no visible menu bar, but key equivalents still route
    /// through `mainMenu`, so this is what makes ⌘C/⌘V/⌘A/⌘W work in our windows.
    private func installMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "Settings…", action: #selector(showSettingsFromMenu), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Murmur", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit Murmur", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app

        let editItem = NSMenuItem(); menu.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let windowItem = NSMenuItem(); menu.addItem(windowItem)
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = window
        NSApp.mainMenu = menu
    }

    @objc private func showSettingsFromMenu() { showMain(tab: .settings) }

    /// Shared with `MainRoot` so the menu can pick a tab before the window exists.
    lazy var tabBinding = Binding<MainTab>(
        get: { [weak self] in self?.mainTab ?? .history },
        set: { [weak self] in self?.mainTab = $0 }
    )

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) == main else { return }
        // Hand focus back to whatever the user was doing.
        NSApp.hide(nil)
    }

    func showOnboarding() {
        Log.d("showOnboarding")
        if let onboarding { onboarding.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        let view = OnboardingView(state: state)
        let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 560),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.backgroundColor = .black
        w.contentView = NSHostingView(rootView: view)
        w.center()
        w.isReleasedWhenClosed = false
        onboarding = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        Log.d("onboarding window visible=\(w.isVisible) frame=\(w.frame) policy=\(NSApp.activationPolicy().rawValue)")
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: Prefs.Key.hasOnboarded)
        onboarding?.close()
        onboarding = nil
        controller.start()
        showMain(tab: .history)
    }
}

extension Notification.Name {
    static let murmurTriggerChanged = Notification.Name("murmur.triggerChanged")
    static let murmurOnboardingDone = Notification.Name("murmur.onboardingDone")
}

/// Bridges the AppKit-owned tab selection into SwiftUI.
private struct MainRoot: View {
    let delegate: AppDelegate
    @State private var tab: MainTab = .history
    var body: some View {
        MainView(state: delegate.state, history: delegate.history, dictionary: delegate.dictionary, tab: $tab)
            .onAppear { tab = delegate.tabBinding.wrappedValue }
            .onReceive(NotificationCenter.default.publisher(for: .murmurShowTab)) { n in
                if let t = n.object as? MainTab { tab = t }
            }
    }
}

extension Notification.Name {
    static let murmurShowTab = Notification.Name("murmur.showTab")
}

@MainActor
func openMainWindow(_ tab: MainTab) {
    AppDelegate.shared?.showMain(tab: tab)
    NotificationCenter.default.post(name: .murmurShowTab, object: tab)
}
