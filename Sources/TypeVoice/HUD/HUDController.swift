import AppKit
import Observation

/// Shows the pill on the right screen while a session is active. The window
/// is created on first use and merely hidden afterwards; nothing runs while idle.
@MainActor
final class HUDController {
    let state: AppState
    var onCopy: () -> Void = {}
    var onDismiss: () -> Void = {}
    private var window: HUDWindow?
    var debugWindow: NSWindow? { window }
    private var hideTask: Task<Void, Never>?

    init(state: AppState) {
        self.state = state
        watchPhase()
    }

    func present(for target: TextInserter.Target?) {
        hideTask?.cancel()
        let w = window ?? makeWindow()
        window = w
        // A Mac with the lid shut and nothing plugged in has no screens at all; then there is
        // nowhere to put the pill, and nothing to see it on.
        guard let screen = Self.screen(containing: target?.windowFrame) ?? Self.screenUnderMouse() ?? NSScreen.main ?? NSScreen.screens.first else { return }
        w.place(on: screen, position: Prefs.hudPosition)
        w.orderFrontRegardless()
    }

    /// Hide after the collapse animation has had time to finish.
    func dismiss() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(480))
            guard let self, !Task.isCancelled, !self.state.phase.isActive else { return }
            self.window?.orderOut(nil)
        }
    }

    private func makeWindow() -> HUDWindow {
        let w = HUDWindow(state: state)
        w.onCopy = { [weak self] in self?.onCopy() }
        w.onDismiss = { [weak self] in self?.onDismiss() }
        return w
    }

    private func watchPhase() {
        withObservationTracking {
            _ = state.phase
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // Hover and the Copy button need mouse events; idle stays click-through.
                self.window?.setInteractive(self.state.phase.isActive)
                self.watchPhase()
            }
        }
    }

    // MARK: Screen choice

    static func screen(containing rect: CGRect?) -> NSScreen? {
        guard let rect else { return nil }
        var best: NSScreen?
        var bestArea: CGFloat = 0
        for s in NSScreen.screens {
            let i = s.frame.intersection(rect)
            if i.isNull { continue }
            let area = i.width * i.height
            if area > bestArea { bestArea = area; best = s }
        }
        return best
    }

    static func screenUnderMouse() -> NSScreen? {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(p) }
    }
}
