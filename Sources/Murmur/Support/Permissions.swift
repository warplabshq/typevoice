import AppKit
import AVFoundation
import ApplicationServices

enum Permissions {
    enum Mic { case granted, denied, undetermined }

    static var mic: Mic {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .notDetermined: return .undetermined
        default: return .denied
        }
    }

    @discardableResult
    static func requestMic() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static var accessibility: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt and opens the pane. If a stale entry exists from an
    /// earlier build (ad-hoc signatures change every build), clear it first so the
    /// switch the user flips applies to *this* binary.
    static func requestAccessibility() {
        if !AXIsProcessTrusted() { resetStaleAccessibilityEntry() }
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private static func resetStaleAccessibilityEntry() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "Accessibility", id]
        p.standardOutput = nil; p.standardError = nil
        try? p.run()
        p.waitUntilExit()
        Log.app.info("tccutil reset Accessibility → \(p.terminationStatus)")
    }

    static func openAccessibilityPane() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openMicPane() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    /// The Keyboard pane, where "Press 🌐 key to" lives.
    static func openKeyboardPane() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    /// Start a fresh instance and quit this one. macOS sometimes only honours a
    /// new Accessibility grant for processes started after the switch was flipped.
    @MainActor
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private static func open(_ s: String) {
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }
}
