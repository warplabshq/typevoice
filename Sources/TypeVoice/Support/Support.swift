import AppKit
import Foundation

/// Report a problem: a pre-addressed email with the facts we always end up asking for
/// (versions, Mac, engine state). Nothing the user said is included; the log stays on
/// the Mac unless they choose to attach it.
enum Support {
    @MainActor
    static func reportProblem(state: AppState) {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let model = hardwareModel() ?? "Mac"
        let engine = state.isReady ? "ready" : (state.warmError ?? state.warm.label)
        let body = """
        What happened:


        What I expected:


        ——
        \(Brand.name) \(Brand.version) (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))
        macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · \(model)
        Trigger: \(Prefs.triggerLabel) · Engine: \(engine) · Apple Intelligence: \(SmartCleaner.status.title)
        Accessibility: \(Permissions.accessibility ? "on" : "off") · Microphone: \(Permissions.mic == .granted ? "on" : "off")
        Log: ~/Library/Logs/\(Brand.name)/typevoice.log (attach it if the problem is a crash or nothing being typed)
        """
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = Brand.supportEmail
        c.queryItems = [URLQueryItem(name: "subject", value: "\(Brand.name) \(Brand.version): problem"),
                        URLQueryItem(name: "body", value: body)]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }

    /// "MacBookPro18,3"-style identifier.
    static func hardwareModel() -> String? {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    static func revealLog() {
        let url = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/\(Brand.name)/typevoice.log")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
