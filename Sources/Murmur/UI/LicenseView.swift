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
                         text: "Everything works during the trial. Unlock \(Brand.name) Pro to keep dictating after it ends.")
                case .expired:
                    hero(icon: "lock", title: "Your trial has ended",
                         text: "Dictation is paused until you unlock Pro. Everything you dictated is still in your Summary.")
                case .pro:
                    hero(icon: "checkmark.seal.fill", title: "\(Brand.name) Pro",
                         text: "Thank you. Purchases are tied to your Apple ID and work on all your Macs.")
                }
            }
            if licensing.state != .pro {
                Section("Unlock Pro") {
                    if !Licensing.isConfigured {
                        Text("Purchases will be available once \(Brand.name) is on the App Store.")
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
                    Text("Billed by Apple through the App Store. No account with \(Brand.name), ever.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        Button("Terms of Use") { NSWorkspace.shared.open(Brand.eulaURL) }
                        Button("Privacy Policy") { NSWorkspace.shared.open(Brand.privacyURL) }
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                    if let id = Licensing.supportID {
                        LabeledContent("Support ID") {
                            HStack(spacing: 6) {
                                Text(id).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                                Button {
                                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(id, forType: .string)
                                } label: { Image(systemName: "doc.on.doc") }
                                .buttonStyle(.borderless).help("Copy")
                            }
                        }
                        Text("A random identifier the purchase check is filed under. It is not linked to you; quote it if you ever want those records deleted.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
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
