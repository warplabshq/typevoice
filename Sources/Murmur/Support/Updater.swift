import Sparkle
import SwiftUI

/// Sparkle, the standard macOS updater. Checks the appcast in Info.plist
/// (SUFeedURL) once a day; the user can also check by hand.
@MainActor
final class Updater {
    static let shared = Updater()
    let controller: SPUStandardUpdaterController

    /// True once a real appcast URL is configured in Info.plist.
    static var isConfigured: Bool {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else { return false }
        return !feed.isEmpty && !feed.contains("REPLACE-ME")
    }

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: Self.isConfigured, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func check() { controller.checkForUpdates(nil) }
    var updater: SPUUpdater { controller.updater }
}

/// Settings row: automatic toggle plus a manual check.
struct UpdatesRow: View {
    @State private var automatic = Updater.shared.updater.automaticallyChecksForUpdates
    @State private var lastCheck = Updater.shared.updater.lastUpdateCheckDate

    var body: some View {
        if Updater.isConfigured {
            Toggle("Check for updates automatically", isOn: $automatic)
                .onChange(of: automatic) { _, on in Updater.shared.updater.automaticallyChecksForUpdates = on }
            LabeledContent("Updates") {
                HStack(spacing: 10) {
                    if let d = lastCheck {
                        Text("Last checked \(d.formatted(.relative(presentation: .named)))")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Button("Check Now…") { Updater.shared.check(); lastCheck = .now }
                }
            }
        } else {
            LabeledContent("Updates") {
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") · updates arrive automatically once Murmur is published")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
