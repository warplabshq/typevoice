import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Puts text where the user was typing. Captures the target at key-down so a
/// focus change during the hold cannot send text to the wrong app. Inserts through
/// the Accessibility API when the focused field allows it (no clipboard involved,
/// and the text before the caret decides spacing and capitalisation); otherwise
/// pastes into the app that was frontmost.
@MainActor
final class TextInserter {
    struct Target: @unchecked Sendable {   // AXUIElement is thread-safe to hold; it is only used on the main actor
        let pid: pid_t
        let appName: String
        let bundleID: String?
        let element: AXUIElement?
        let context: Cleaner.Context
        /// Cocoa-space frame of the focused window, for choosing the HUD's screen.
        let windowFrame: CGRect?
    }

    enum Method: String, Sendable { case accessibility, paste }

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
        let pid = app.processIdentifier
        let element = Self.focusedElement()
        let context = element.map(Self.readContext) ?? .unknown
        let frame = Self.focusedWindowFrame(pid: pid) ?? Self.frontWindowFrame(pid: pid)
        return Target(pid: pid, appName: app.localizedName ?? "app", bundleID: app.bundleIdentifier,
                      element: element, context: context, windowFrame: frame)
    }

    /// Whether the captured focus looks like somewhere text can go. Conservative:
    /// only well-known non-text roles say no, so Electron/web apps still get a try.
    func hasTextTarget(_ target: Target) -> Bool {
        guard let el = target.element else {
            // No focused element reported (web editors like Mail's compose do this): we
            // can't know, so let paste have a go rather than withholding the text. The
            // bare desktop is the one place we know has nothing to type into.
            return !(target.bundleID == "com.apple.finder" && target.windowFrame == nil)
        }
        let role = Self.string(el, kAXRoleAttribute) ?? ""
        Log.d("focused role=\(role) subrole=\(Self.string(el, kAXSubroleAttribute) ?? "-") in \(target.appName)")
        let nonText: Set<String> = [
            kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXStaticTextRole, kAXImageRole,
            kAXRowRole, kAXCellRole, kAXOutlineRole, kAXTableRole, kAXListRole, kAXMenuRole, kAXMenuItemRole,
            kAXMenuBarRole, kAXWindowRole, kAXScrollBarRole, kAXSliderRole, kAXTabGroupRole, kAXToolbarRole,
            kAXPopUpButtonRole, kAXDisclosureTriangleRole, "AXLink", kAXScrollAreaRole,
        ]
        if nonText.contains(role) { return false }
        let subrole = Self.string(el, kAXSubroleAttribute) ?? ""
        if subrole == "AXDesktop" { return false }
        if role == kAXGroupRole || role == "AXWebArea" {
            // Containers count as text only if they behave like a text view.
            var r: CFTypeRef?, n: CFTypeRef?
            let hasRange = AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &r) == .success
            let hasCount = AXUIElementCopyAttributeValue(el, kAXNumberOfCharactersAttribute as CFString, &n) == .success
            return hasRange && hasCount
        }
        return true
    }

    // MARK: Insert

    @discardableResult
    func insert(_ text: String, into target: Target) async throws -> Method {
        let t0 = ContinuousClock.now
        if IsSecureEventInputEnabled() == true || target.element.map(Self.isSecure) == true {
            throw InsertError.secureField
        }
        if Prefs.insertion == .auto, let el = target.element, Self.insertViaAX(text, into: el) {
            Log.timing("insert.ax", since: t0)
            return .accessibility
        }
        try await paste(text, into: target)
        Log.timing("insert.paste", since: t0)
        return .paste
    }

    // MARK: Accessibility path

    /// Accessibility calls block the caller until the other app answers; a hung or busy app
    /// would otherwise freeze insertion for the system default of several seconds. Ask for a
    /// short answer and fall back to paste instead.
    private static let axTimeout: Float = 0.3

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, axTimeout)
        var v: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &v)
        guard err == .success, let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        let element = v as! AXUIElement
        AXUIElementSetMessagingTimeout(element, axTimeout)
        return element
    }

    private static func string(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private static func isSecure(_ el: AXUIElement) -> Bool {
        string(el, kAXSubroleAttribute) == kAXSecureTextFieldSubrole
    }

    /// Text before the caret, capped so huge documents stay cheap.
    private static func readContext(_ el: AXUIElement) -> Cleaner.Context {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return .unknown }
        var range = CFRange()
        guard AXValueGetValue((rangeRef as! AXValue), .cfRange, &range) else { return .unknown }
        guard let value = string(el, kAXValueAttribute) else { return .unknown }
        let ns = value as NSString
        guard range.location >= 0, range.location <= ns.length else { return .unknown }
        let start = max(0, range.location - 200)
        return Cleaner.Context(textBeforeCaret: ns.substring(with: NSRange(location: start, length: range.location - start)))
    }

    private static func insertViaAX(_ text: String, into el: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(el, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }
        let before = string(el, kAXValueAttribute)
        guard AXUIElementSetAttributeValue(el, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success else {
            return false
        }
        // Some web views report success without changing anything. Verify when we can.
        if let after = string(el, kAXValueAttribute) {
            if after == before && !text.isEmpty { return false }
            if !after.contains(text.trimmingCharacters(in: .whitespaces)) { return false }
        }
        return true
    }

    private static func focusedWindowFrame(pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, axTimeout)
        var w: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &w) == .success,
              let w, CFGetTypeID(w) == AXUIElementGetTypeID() else { return nil }
        let win = w as! AXUIElement
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue((posRef as! AXValue), .cgPoint, &p),
              AXValueGetValue((sizeRef as! AXValue), .cgSize, &s) else { return nil }
        // AX uses a top-left origin on the primary display; Cocoa uses bottom-left.
        guard let primary = NSScreen.screens.first else { return nil }
        return CGRect(x: p.x, y: primary.frame.maxY - p.y - s.height, width: s.width, height: s.height)
    }

    /// Frame of the app's frontmost window from the window list, for apps that don't
    /// answer Accessibility queries.
    private static func frontWindowFrame(pid: pid_t) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
                  width > 50, height > 50 else { continue }
            guard let primary = NSScreen.screens.first else { return nil }
            return CGRect(x: x, y: primary.frame.maxY - y - height, width: width, height: height)
        }
        return nil
    }

    // MARK: Paste path

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

        // With a chord trigger (⌥⌘) the session ends on the first key you let go, so the
        // other modifier is often still down when the text is ready. A ⌘V posted then
        // arrives as ⌥⌘V, which most apps answer with the error beep. Wait for clean hands.
        for _ in 0..<80 {
            let held = CGEventSource.flagsState(.combinedSessionState)
                .intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn])
            if held.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
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
