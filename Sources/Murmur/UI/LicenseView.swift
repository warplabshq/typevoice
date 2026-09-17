import AppKit
import RevenueCat
import SwiftUI

struct LicenseView: View {
    let licensing: Licensing

    var body: some View {
        Form {
            Section {
                switch licensing.state {
                case .trial(let days):
                    hero(icon: "clock", title: days == 1 ? "1 day left in your trial" : "\(days) days left in your trial",
                         text: "Everything works during the trial. Unlock Murmur Pro to keep dictating after it ends.")
                case .expired:
                    hero(icon: "lock", title: "Your trial has ended",
                         text: "Dictation is paused until you unlock Pro. Everything you dictated is still in your Summary.")
                case .pro:
                    hero(icon: "checkmark.seal.fill", title: "Murmur Pro",
                         text: "Thank you. Purchases are tied to your Apple ID and work on all your Macs.")
                }
            }
            if licensing.state != .pro {
                Section("Unlock Pro") {
                    if !Licensing.isConfigured {
                        Text("Purchases will be available once Murmur is on the App Store.")
                            .foregroundStyle(.secondary)
                    } else if licensing.packages.isEmpty {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Loading prices…").foregroundStyle(.secondary) }
                            .task { await licensing.sync() }
                    } else {
                        ForEach(licensing.packages, id: \.identifier) { p in
                            LabeledContent {
                                Button(licensing.busy ? "…" : p.storeProduct.localizedPriceString) {
                                    Task { await licensing.purchase(p) }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(licensing.busy)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.storeProduct.localizedTitle)
                                    Text(p.storeProduct.localizedDescription).font(.callout).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if let e = licensing.lastError {
                        Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                    }
                    Button("Restore Purchases") { Task { await licensing.restore() } }
                        .disabled(!Licensing.isConfigured || licensing.busy)
                    Text("Billed by Apple through the App Store. No account with Murmur, ever.")
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
                .foregroundStyle(licensing.state == .pro ? Color.green : Color.accentColor)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold))
                Text(text).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
