import AppKit
import SwiftUI

struct LicenseView: View {
    let licensing: Licensing
    var history: HistoryStore? = nil
    @State private var key = ""
    @State private var regional: RegionalPrice?
    @FocusState private var keyFocused: Bool

    var body: some View {
        Form {
            Section {
                switch licensing.state {
                case .trial(let days):
                    hero(icon: "clock", title: days == 1 ? "1 day left in your trial" : "\(days) days left in your trial",
                         text: "Everything works during the trial. Buy \(Brand.name) once to keep dictating after it ends; there is no subscription.")
                case .expired:
                    hero(icon: "lock", title: "Your trial has ended",
                         text: "Dictation is paused until you enter a license key. Everything you dictated is still in your Summary.")
                case .licensed:
                    hero(icon: "checkmark.seal.fill", title: "\(Brand.name) is yours",
                         text: licensing.plan == .team
                             ? "Thank you. This Mac is activated with your team's key; each person can use it on two Macs."
                             : "Thank you. This Mac is activated; use the same key on your other Mac.")
                }
            }
            if !licensing.isLicensed, let line = benefitLine {
                // One quiet line: what the trial has already given back, in the user's own numbers.
                Section {
                    Label(line, systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            if licensing.isLicensed {
                Section("License") {
                    LabeledContent("Key") {
                        Text(licensing.licenseKeyMasked ?? "").font(.system(.body, design: .monospaced))
                    }
                    Text(licensing.plan == .team
                         ? "A team key: \(Brand.teamSeats) people, two Macs each. Deactivate this Mac before handing it on, so the seat is free for someone else."
                         : "Your key was emailed to you by Dodo Payments when you bought \(Brand.name); it covers two Macs. Deactivate this Mac before selling it or handing it on, so the seat is free for your next one.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button(licensing.busy ? "…" : "Deactivate this Mac") { Task { await licensing.deactivate() } }
                            .disabled(licensing.busy)
                        Button("Re-check") { Task { await licensing.revalidateIfDue(force: true) } }
                            .disabled(licensing.busy)
                    }
                    if let e = licensing.lastError {
                        Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                    }
                }
                if licensing.plan == .personal {
                    Section("Growing?") {
                        LabeledContent {
                            Button("Buy — \(regional.map { $0.format($0.team) } ?? Brand.teamPrice)") { NSWorkspace.shared.open(Brand.teamCheckoutURL) }
                                .disabled(!Licensing.isConfigured)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Team key · \(Brand.teamSeats) people, two Macs each")
                                Text("One shared key. Enter it below when it arrives; this Mac moves over and your personal seat is freed.")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Use a different key") {
                    HStack {
                        TextField("XXXX-XXXX-XXXX-XXXX", text: $key).textFieldStyle(.roundedBorder).focused($keyFocused)
                            .onSubmit { Task { await licensing.activate(key); if licensing.isLicensed { key = "" } } }
                        Button(licensing.busy ? "…" : "Switch") { Task { await licensing.activate(key); if licensing.isLicensed { key = "" } } }
                            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || licensing.busy)
                    }
                    Text("For moving this Mac onto a team key, or a new key after a refund. The old seat is released.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Section("Buy \(Brand.name)") {
                    if let r = regional {
                        Text("\(r.flag) A special price for where you are: \(r.format(r.personal)) instead of \(Brand.price), plus \(r.tax). The checkout goes by billing country.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    LabeledContent {
                        Button("Buy — \(regional.map { $0.format($0.personal) } ?? Brand.price)") { NSWorkspace.shared.open(Brand.checkoutURL) }
                            .buttonStyle(.borderedProminent)
                            .disabled(!Licensing.isConfigured)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("For you · one purchase, two Macs")
                            Text(Licensing.isConfigured
                                 ? "Checkout opens in your browser. The key arrives by email and lands here by itself."
                                 : "The checkout link isn't configured in this build.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent {
                        Button("Buy — \(regional.map { $0.format($0.team) } ?? Brand.teamPrice)") { NSWorkspace.shared.open(Brand.teamCheckoutURL) }
                            .disabled(!Licensing.isConfigured)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("For a team · \(Brand.teamSeats) people, two Macs each")
                            Text(regional == nil ? "One shared key for the whole team. A few countries have their own price, shown at checkout."
                                                 : "One shared key for the whole team.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Already have a key?") {
                    HStack(spacing: 10) {
                        TextField("XXXX-XXXX-XXXX-XXXX", text: $key)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .focused($keyFocused)
                            .onSubmit { activate() }
                        Button(licensing.busy ? "…" : "Activate") { activate() }
                            .buttonStyle(.borderedProminent)
                            .disabled(licensing.busy || key.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let e = licensing.lastError {
                        Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
                    }
                    Text("Activation sends the key and this Mac's name to Dodo Payments, nothing else. No account with \(Brand.name), ever.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack(spacing: 14) {
                        Button("License Agreement") { NSWorkspace.shared.open(Brand.eulaURL) }
                        Button("Privacy Policy") { NSWorkspace.shared.open(Brand.privacyURL) }
                        Button("Lost your key?") { NSWorkspace.shared.open(Brand.supportURL) }
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .task { if !(licensing.isLicensed && licensing.plan == .team), regional == nil { regional = await RegionalPrice.fetch() } }
        .onAppear { keyFocused = licensing.isExpired }
        .onChange(of: licensing.state) { _, s in if s == .licensed { key = "" } }
    }

    private func activate() {
        Task { await licensing.activate(key) }
    }

    /// "You've saved 1h 40m of typing so far — about 45 minutes a week." Nothing until
    /// there is at least a few minutes to point at; a made-up number would read as a pitch.
    private var benefitLine: String? {
        guard let s = history?.stats, s.allCount >= 3 else { return nil }
        let saved = HistoryView.secondsSaved(words: s.allWords, talking: s.allSeconds)
        guard saved >= 180 else { return nil }
        // This week's words at the overall speaking pace.
        let weekTalking = s.allWordsPerMinute > 0 ? Double(s.weekWords) / s.allWordsPerMinute * 60 : 0
        let weekly = HistoryView.secondsSaved(words: s.weekWords, talking: weekTalking)
        var line = "You've saved \(Fmt.durationLong(saved)) of typing so far"
        // Mention the week only once it is a fraction of a longer history, not a repeat of the total.
        if weekly >= 300, weekly < saved * 0.8 { line += ", \(Fmt.durationLong(weekly)) of it this week" }
        return line + ". Buying once keeps that going."
    }

    private func hero(icon: String, title: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(licensing.isLicensed ? Color.green : Color.accentColor)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.weight(.semibold))
                Text(text).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
