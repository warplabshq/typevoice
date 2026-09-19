import Sparkle
import SwiftUI

/// Sparkle, the standard macOS updater. Checks the appcast named in Info.plist
/// (SUFeedURL) once a day; the user can also check by hand. Updates are signed with
/// the EdDSA key whose public half is in Info.plist (SUPublicEDKey).
@MainActor
final class Updater {
    static let shared = Updater()
    let controller: SPUStandardUpdaterController

    /// True once a real appcast URL and public key are in Info.plist.
    static var isConfigured: Bool {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else { return false }
        return !feed.isEmpty && !feed.contains("REPLACE-ME") && !key.isEmpty && !key.contains("REPLACE-ME")
    }

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: Self.isConfigured, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func check() { controller.checkForUpdates(nil) }
    var updater: SPUUpdater { controller.updater }
}

/// Settings rows: the automatic toggle plus a manual check.
struct UpdatesRows: View {
    @State private var automatic = Updater.shared.updater.automaticallyChecksForUpdates
    @State private var lastCheck = Updater.shared.updater.lastUpdateCheckDate

    var body: some View {
        if Updater.isConfigured {
            Toggle("Check for updates automatically", isOn: $automatic)
                .onChange(of: automatic) { _, on in Updater.shared.updater.automaticallyChecksForUpdates = on }
            LabeledContent("Version \(Brand.version)") {
                HStack(spacing: 10) {
                    if let d = lastCheck {
                        Text("Checked \(d.formatted(.relative(presentation: .named)))")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Button("Check for Updates…") { Updater.shared.check(); lastCheck = .now }
                }
            }
        } else {
            LabeledContent("Version") {
                Text("\(Brand.version) · this build has no update feed configured")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
