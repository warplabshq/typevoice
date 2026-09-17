import AppKit
import Carbon.HIToolbox

/// Puts text where the user was typing, by pasting into the app that was
/// frontmost at key-down. (The App Sandbox rules out the Accessibility API, so
/// there is no reading of the focused field; native text views add the space
/// around a paste themselves, and web apps get the "Start with a space" setting.)
@MainActor
final class TextInserter {
    struct Target: Sendable {
        let pid: pid_t
        let appName: String
        let bundleID: String?
        /// Cocoa-space frame of the app's frontmost window, for choosing the HUD's screen.
        let windowFrame: CGRect?
        var context: Cleaner.Context { .unknown }
    }

    enum Method: String, Sendable { case paste }

    enum InsertError: LocalizedError {
        case secureField
        case noFocusedApp
        case noTextTarget
        var errorDescription: String? {
            switch self {
            case .secureField: return "Can't type into a password field"
            case .noFocusedApp: return "No app to type into"
            case .noTextTarget: return "Nothing to type into here"
            }
        }
    }

    // MARK: Capture

    func captureTarget() -> Target? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return Target(pid: app.processIdentifier, appName: app.localizedName ?? "app", bundleID: app.bundleIdentifier,
                      windowFrame: Self.frontWindowFrame(pid: app.processIdentifier))
    }

    /// Without Accessibility we can't see the focused field. The desktop is the one
    /// place we know has nothing to type into; everything else gets a paste.
    func hasTextTarget(_ target: Target) -> Bool {
        if target.bundleID == "com.apple.finder", target.windowFrame == nil { return false }
        return true
    }

    // MARK: Insert

    @discardableResult
    func insert(_ text: String, into target: Target) async throws -> Method {
        let t0 = ContinuousClock.now
        if IsSecureEventInputEnabled() == true { throw InsertError.secureField }
        try await paste(text, into: target)
        Log.timing("insert.paste", since: t0)
        return .paste
    }

    /// Frame of the app's frontmost window from the window list (no Accessibility needed).
    private static func frontWindowFrame(pid: pid_t) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
                  width > 50, height > 50 else { continue }
            // Window list uses a top-left origin on the primary display; Cocoa uses bottom-left.
            guard let primary = NSScreen.screens.first else { return nil }
            return CGRect(x: x, y: primary.frame.maxY - y - height, width: width, height: height)
        }
        return nil
    }

    // MARK: Paste

    private struct ClipboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
        let changeCount: Int
    }

    private func paste(_ text: String, into target: Target) async throws {
        let pb = NSPasteboard.general
        let snapshot = ClipboardSnapshot(
            items: (pb.pasteboardItems ?? []).map { item in
                var d: [NSPasteboard.PasteboardType: Data] = [:]
                for t in item.types { if let data = item.data(forType: t) { d[t] = data } }
                return d
            },
            changeCount: pb.changeCount
        )

        if NSWorkspace.shared.frontmostApplication?.processIdentifier != target.pid,
           let app = NSRunningApplication(processIdentifier: target.pid) {
            app.activate()
            try await Task.sleep(for: .milliseconds(80))
        }

        pb.clearContents()
        pb.setString(text, forType: .string)
        let ours = pb.changeCount

        let src = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            throw InsertError.noTextTarget
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        // Give the app time to read the pasteboard, then put the user's clipboard back.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard pb.changeCount == ours else { return }   // user copied something meanwhile
            pb.clearContents()
            let restored: [NSPasteboardItem] = snapshot.items.map { dict in
                let item = NSPasteboardItem()
                for (t, d) in dict { item.setData(d, forType: t) }
                return item
            }
            if !restored.isEmpty { pb.writeObjects(restored) }
        }
    }

    /// Fallback when insertion fails: leave the text on the clipboard.
    func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
