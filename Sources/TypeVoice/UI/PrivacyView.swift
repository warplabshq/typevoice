import AppKit
import SwiftUI

struct PrivacyView: View {
    let history: HistoryStore
    let dictionary: DictionaryStore
    @State private var confirmWipe = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Nothing leaves your Mac.", systemImage: "lock.shield.fill")
                        .font(.title3.weight(.semibold))
                    Text("\(Brand.name) has no account, no analytics, no crash reporting and no telemetry of any kind. It does not know you exist.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section("How it works") {
                row("mic", Prefs.keepRecordings
                    ? "Audio is captured only while you hold the key. Because “Offer the audio after each dictation” is on, each dictation is also saved as an audio file on this Mac. Turn it off in Settings and nothing is written."
                    : "Audio is captured only while you hold the key, and is discarded the moment it's transcribed. It is never written to disk.")
                row("cpu", "Speech recognition runs on the Neural Engine using NVIDIA's Parakeet model. No audio is ever sent anywhere.")
                row("sparkles", "Smart cleanup uses Apple Intelligence's on-device model. Text stays on this Mac.")
                row("network", "Network use is limited to: the one-time model download from huggingface.co, the update check against \(Brand.name)'s own appcast, one request to \(Brand.website.host ?? "the site") from the License tab to show the price for your country (nothing about you is sent), and, once you buy a license, activating and re-checking that key with Dodo Payments. No analytics, no accounts.")
                row("internaldrive", "History is a small database and your dictionary a text file, both on this Mac, both yours to open, back up or delete.")
                row("chevron.left.forwardslash.chevron.right", "None of this asks for trust: the source is public under the GPL v3, so anyone can read exactly what the app does and build it themselves.")
                Button("Read the source on GitHub") { NSWorkspace.shared.open(Brand.sourceURL) }
                    .buttonStyle(.link).padding(.leading, 28)
            }
            Section("Legal") {
                LabeledContent("Privacy Policy") { Button("Read online") { NSWorkspace.shared.open(Brand.privacyURL) } }
                LabeledContent("Terms of Use") { Button("Read online") { NSWorkspace.shared.open(Brand.termsURL) } }
                LabeledContent("License Agreement") { Button("Read online") { NSWorkspace.shared.open(Brand.eulaURL) } }
                LabeledContent("Support") {
                    HStack(spacing: 10) {
                        Button("Help & FAQ") { NSWorkspace.shared.open(Brand.supportURL) }
                        Button("Email") { NSWorkspace.shared.open(URL(string: "mailto:\(Brand.supportEmail)?subject=\(Brand.name)%20\(Brand.version)")!) }
                    }
                }
            }
            Section("Your data") {
                LabeledContent("Location") {
                    HStack(spacing: 10) {
                        Text(Paths.support.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Reveal in Finder") { reveal() }
                    }
                }
                LabeledContent("History") { Text("\(history.entries.count) dictations").foregroundStyle(.secondary) }
                LabeledContent("Dictionary") { Text("\(dictionary.terms.count) terms").foregroundStyle(.secondary) }
                if RecordingStore.totalBytes() > 0 {
                    LabeledContent("Recordings") {
                        HStack(spacing: 10) {
                            Text(ByteCountFormatter.string(fromByteCount: RecordingStore.totalBytes(), countStyle: .file)).foregroundStyle(.secondary)
                            Button("Delete Recordings…", role: .destructive) { RecordingStore.deleteAll() }
                        }
                    }
                }
                Button("Delete Everything…", role: .destructive) { confirmWipe = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Delete all \(Brand.name) data on this Mac?", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) {
                history.clear(); dictionary.clear(); Prefs.reset()
            }
        } message: {
            Text("History, dictionary and settings are removed. The downloaded speech model stays so you don't have to fetch it again.")
        }
    }

    private func reveal() {
        let files = [Paths.historyDB, Paths.dictionary].filter { FileManager.default.fileExists(atPath: $0.path) }
        if files.isEmpty {
            NSWorkspace.shared.open(Paths.support)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(files)
        }
    }

    private func row(_ icon: String, _ text: String) -> some View {
        Label { Text(text) } icon: { Image(systemName: icon).foregroundStyle(Color.accentColor) }
            .padding(.vertical, 2)
    }
}
