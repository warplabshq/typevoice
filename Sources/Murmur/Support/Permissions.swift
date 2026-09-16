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

    /// Shows the system prompt (once per app signature) and opens the pane.
    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
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

    private static func open(_ s: String) {
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }
}
