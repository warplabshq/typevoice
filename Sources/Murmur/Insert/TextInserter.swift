import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Puts text where the user was typing. Captures the target at key-down so a
/// focus change during the hold cannot send text to the wrong app.
@MainActor
final class TextInserter {
    struct Target: Sendable {
        let pid: pid_t
        let appName: String
        let bundleID: String?
        let element: AXUIElement?
        let context: Cleaner.Context
        /// Cocoa-space frame of the focused window, for choosing the HUD's screen.
        let windowFrame: CGRect?
        /// Whether the app answers Accessibility queries at all.
        let axAvailable: Bool
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
        let frame = Self.focusedWindowFrame(pid: pid)
        return Target(pid: pid, appName: app.localizedName ?? "app", bundleID: app.bundleIdentifier,
                      element: element, context: context, windowFrame: frame, axAvailable: frame != nil || element != nil)
    }

    /// Whether the captured focus looks like somewhere text can go. Conservative:
    /// only well-known non-text roles say no, so Electron/web apps still get a try.
    func hasTextTarget(_ target: Target) -> Bool {
        // No focused element: if the app speaks Accessibility, nothing is focused;
        // if it doesn't, we can't know, so let paste have a go.
        guard let el = target.element else { return !target.axAvailable }
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

    private static func focusedElement() -> AXUIElement? {
        var v: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &v)
        guard err == .success, let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
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
        let cocoaY = primary.frame.maxY - p.y - s.height
        return CGRect(x: p.x, y: cocoaY, width: s.width, height: s.height)
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
