import AppKit
import SwiftUI

struct LicenseView: View {
    let licensing: Licensing
    @State private var key = ""
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                switch licensing.state {
                case .trial(let days):
                    hero(icon: "clock", title: days == 1 ? "1 day left in your trial" : "\(days) days left in your trial",
                         text: "Everything works during the trial. Buy once, use it forever on this Mac.")
                case .expired:
                    hero(icon: "lock", title: "Your trial has ended",
                         text: "Dictation is paused until you enter a license. Everything you dictated is still in your history.")
                case .licensed:
                    hero(icon: "checkmark.seal.fill", title: "Licensed",
                         text: "Thank you. This Mac is activated with key \(licensing.licenseKeyMasked ?? "").")
                }
            }
            if licensing.state != .licensed {
                Section("Buy") {
                    LabeledContent("Lifetime license") {
                        Button("Buy Murmur…") { NSWorkspace.shared.open(Licensing.checkoutURL) }
                            .buttonStyle(.borderedProminent)
                    }
                    Text("Checkout is handled by Dodo Payments. Your key arrives by email within a minute.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section("Already have a key?") {
                    HStack(spacing: 8) {
                        TextField(text: $key, prompt: Text("Paste your license key")) { Text("License key") }
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onSubmit(activate)
                        Button(busy ? "Activating…" : "Activate") { activate() }
                            .disabled(busy || key.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let e = licensing.lastError {
                        Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                    }
                    Text("Activation contacts Dodo Payments once to register this Mac, then re-checks about weekly. No other data is sent.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Button("Deactivate this Mac…", role: .destructive) { Task { await licensing.deactivate() } }
                    Text("Frees the activation so you can use the key on another Mac.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func hero(icon: String, title: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(licensing.state == .licensed ? Color.green : Color.accentColor)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold))
                Text(text).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func activate() {
        busy = true
        Task { await licensing.activate(key); busy = false; if licensing.state == .licensed { key = "" } }
    }
}
