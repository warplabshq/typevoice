import Sparkle
import SwiftUI

/// Sparkle, the standard macOS updater. Checks the appcast named in Info.plist
/// (SUFeedURL) once a day; the user can also check by hand. Updates are signed with
/// the EdDSA key whose public half is in Info.plist (SUPublicEDKey).
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    static let shared = Updater()
    private(set) var controller: SPUStandardUpdaterController!
    /// Set just before Sparkle relaunches us; read once at the next launch.
    static let reopenKey = "reopenAfterUpdate"

    /// True once a real appcast URL and public key are in Info.plist.
    static var isConfigured: Bool {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else { return false }
        return !feed.isEmpty && !feed.contains("REPLACE-ME") && !key.isEmpty && !key.contains("REPLACE-ME")
    }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: Self.isConfigured, updaterDelegate: self, userDriverDelegate: nil)
    }

    /// A menu bar app relaunches invisibly after an update, which reads as "nothing happened".
    /// Note which window was open so the next launch brings it straight back.
    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        // Sparkle calls this on the main thread; never block it waiting for itself.
        let read: @MainActor () -> String = { (NSApp.delegate as? AppDelegate)?.openMainTab?.rawValue ?? MainTab.settings.rawValue }
        let tab = Thread.isMainThread ? MainActor.assumeIsolated(read) : DispatchQueue.main.sync { MainActor.assumeIsolated(read) }
        UserDefaults.standard.set(tab, forKey: Updater.reopenKey)
    }

    /// Called once at launch: reopen the window an update closed, on the tab it was showing.
    static func reopenIfUpdated(_ show: (MainTab) -> Void) {
        guard let raw = UserDefaults.standard.string(forKey: reopenKey) else { return }
        UserDefaults.standard.removeObject(forKey: reopenKey)
        show(MainTab(rawValue: raw) ?? .settings)
    }

    func check() { controller.checkForUpdates(nil) }
    var updater: SPUUpdater { controller.updater }
}

/// Settings › About: the app at a glance, with the update check where people expect it.
struct UpdatesRows: View {
    @State private var automatic = Updater.shared.updater.automaticallyChecksForUpdates
    @State private var lastCheck = Updater.shared.updater.lastUpdateCheckDate

    private var status: String {
        guard Updater.isConfigured else { return "Version \(Brand.version)" }
        guard let d = lastCheck else { return "Version \(Brand.version)" }
        return "Version \(Brand.version) · checked \(d.formatted(.relative(presentation: .named)))"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().interpolation(.high)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(Brand.name).font(.headline)
                Text(status).font(.callout).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            Button("Check for Updates…") { Updater.shared.check(); lastCheck = .now }
                .disabled(!Updater.isConfigured)
        }
        .padding(.vertical, 4)
        if Updater.isConfigured {
            Toggle("Check for updates automatically", isOn: $automatic)
                .onChange(of: automatic) { _, on in Updater.shared.updater.automaticallyChecksForUpdates = on }
            Text("Once a day, quietly. Updates are signed and install in place; nothing about you is sent.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
