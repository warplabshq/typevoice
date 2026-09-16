import AppKit
import SwiftUI

/// Transparent, click-through, non-activating panel that hosts the pill.
/// Lives above everything (including full-screen apps) and is invisible to
/// screen capture.
final class HUDWindow: NSPanel {
    static let canvas = CGSize(width: 720, height: 120)

    init(state: AppState) {
        super.init(
            contentRect: CGRect(origin: .zero, size: Self.canvas),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        sharingType = Log.debugTimings ? .readOnly : .none   // capturable only for debugging
        ignoresMouseEvents = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isFloatingPanel = true
        contentView = NSHostingView(rootView: HUDView(state: state))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Centre the canvas horizontally on `screen`, near the top or bottom edge.
    func place(on screen: NSScreen, position: Prefs.HUDPosition) {
        let v = screen.visibleFrame
        let s = Self.canvas
        let y: CGFloat
        switch position {
        case .bottom: y = v.minY + 22
        case .top: y = v.maxY - s.height - 10
        }
        setFrame(CGRect(x: v.midX - s.width / 2, y: y, width: s.width, height: s.height), display: false)
    }
}
