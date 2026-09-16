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
                    Text("Murmur has no account, no analytics, no crash reporting and no telemetry of any kind. It does not know you exist.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Section("How it works") {
                row("mic", "Audio is captured only while you hold the key, and is discarded the moment it's transcribed. It is never written to disk.")
                row("cpu", "Speech recognition runs on the Neural Engine using NVIDIA's Parakeet model. No audio is ever sent anywhere.")
                row("sparkles", "Smart cleanup uses Apple Intelligence's on-device model. Text stays on this Mac.")
                row("network", "The only network request Murmur ever makes is the one-time model download from huggingface.co on first launch.")
                row("internaldrive", "History and your dictionary are plain JSON files you can read, back up or delete.")
            }
            Section("Your data") {
                LabeledContent("Location") {
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Paths.history]) }
                }
                LabeledContent("History") { Text("\(history.entries.count) dictations").foregroundStyle(.secondary) }
                LabeledContent("Dictionary") { Text("\(dictionary.terms.count) terms").foregroundStyle(.secondary) }
                Button("Delete Everything…", role: .destructive) { confirmWipe = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Privacy")
        .confirmationDialog("Delete all Murmur data on this Mac?", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) {
                history.clear(); dictionary.clear(); Prefs.reset()
            }
        } message: {
            Text("History, dictionary and settings are removed. The downloaded speech model stays so you don't have to fetch it again.")
        }
    }

    private func row(_ icon: String, _ text: String) -> some View {
        Label { Text(text) } icon: { Image(systemName: icon).foregroundStyle(Color.accentColor) }
            .padding(.vertical, 2)
    }
}
