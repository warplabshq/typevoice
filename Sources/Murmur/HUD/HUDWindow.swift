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

    static let margin: CGFloat = 20

    /// Put the canvas in the chosen corner/edge of `screen`'s visible area.
    func place(on screen: NSScreen, position: Prefs.HUDPosition) {
        let v = screen.visibleFrame
        let s = Self.canvas
        let y = position.isTop ? v.maxY - s.height : v.minY
        let x: CGFloat
        switch position.horizontal {
        case 0: x = v.minX
        case 1: x = v.midX - s.width / 2
        default: x = v.maxX - s.width
        }
        setFrame(CGRect(x: x, y: y, width: s.width, height: s.height), display: false)
    }
}
