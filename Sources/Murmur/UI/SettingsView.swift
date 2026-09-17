import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Prefs.Key.trigger) private var trigger = Prefs.Trigger.fn.rawValue
    @AppStorage(Prefs.Key.smartCleanup) private var smart = true
    @AppStorage(Prefs.Key.numbersAsDigits) private var numbers = true
    @AppStorage(Prefs.Key.voiceCommands) private var voiceCommands = true
    @AppStorage(Prefs.Key.pauseParagraphs) private var pauseParagraphs = true
    @AppStorage(Prefs.Key.showPreview) private var showPreview = true
    @AppStorage(Prefs.Key.hudPosition) private var hudPosition = Prefs.HUDPosition.bottomCenter.rawValue
    @AppStorage(Prefs.Key.accent) private var accent = Prefs.Accent.mono.rawValue
    @AppStorage(Prefs.Key.pillLook) private var pillLook = Prefs.PillLook.black.rawValue
    @AppStorage(Prefs.Key.pillShadow) private var pillShadow = Prefs.PillShadow.soft.rawValue
    @AppStorage(Prefs.Key.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(Prefs.Key.insertion) private var insertion = Prefs.Insertion.auto.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var advanced = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle("Show in menu bar", isOn: $showMenuBarIcon)
                Text(showMenuBarIcon ? "Murmur lives in the menu bar; there is no Dock icon." : "With the icon hidden, open Murmur again from Finder or Spotlight to get here.")
                    .font(.callout).foregroundStyle(.secondary)
                UpdatesRow()
            }
            Section("Dictating") {
                Picker("Hold to dictate", selection: $trigger) {
                    Text("🌐 Globe / Fn key").tag(Prefs.Trigger.fn.rawValue)
                    Text("Custom shortcut").tag(Prefs.Trigger.custom.rawValue)
                }
                if trigger == Prefs.Trigger.custom.rawValue {
                    LabeledContent("Shortcut") { ShortcutRecorder() }
                    Text("A lone modifier works best for holding: Right ⌘, Right ⌥ or Fn. Combos like ⌥Space work too.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    LabeledContent("") {
                        HStack(spacing: 6) {
                            Text("Set “Press 🌐 key to” to **Do Nothing** in")
                            Button("Keyboard settings") { Permissions.openKeyboardPane() }
                                .buttonStyle(.link)
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
                Toggle("Smart cleanup", isOn: $smart)
                Text("Fixes false starts and self-corrections with Apple Intelligence, on this Mac. Never adds anything. Tone lives under Style.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Numbers as digits", isOn: $numbers)
                Text("“twenty twenty four” becomes 2024, “five dollars fifty” becomes $5.50. Small numbers stay as words.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Voice commands", isOn: $voiceCommands)
                Text("Say “new line”, “new paragraph”, “bullet …”, or “number one …, number two …” to shape the text.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Paragraph after a pause", isOn: $pauseParagraphs)
                Text("Finish a sentence, pause a second, and the next one starts a new paragraph.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Indicator") {
                LabeledContent("Position") {
                    PositionGrid(selection: $hudPosition)
                }
                LabeledContent("Look") {
                    Picker("Look", selection: $pillLook) {
                        ForEach(Prefs.PillLook.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                }
                LabeledContent("Shadow") {
                    Picker("Shadow", selection: $pillShadow) {
                        ForEach(Prefs.PillShadow.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                }
                LabeledContent("Accent") {
                    AccentSwatches(selection: $accent)
                }
                LabeledContent("Preview") {
                    PillPreview(accent: Prefs.Accent(rawValue: accent) ?? .mono,
                                look: Prefs.PillLook(rawValue: pillLook) ?? .black,
                                shadow: Prefs.PillShadow(rawValue: pillShadow) ?? .soft)
                }
                Toggle("Show the text after each dictation", isOn: $showPreview)
            }

            Section {
                DisclosureGroup("Advanced", isExpanded: $advanced) {
                    Picker("Insert text via", selection: $insertion) {
                        Text("Accessibility, then paste").tag(Prefs.Insertion.auto.rawValue)
                        Text("Always paste").tag(Prefs.Insertion.paste.rawValue)
                    }
                    LabeledContent("Speech model") {
                        Text("Parakeet TDT 0.6B v2 · Neural Engine")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: trigger) { _, _ in
            NotificationCenter.default.post(name: .murmurTriggerChanged, object: nil)
        }
    }
}

/// A little monitor with six dots. Click where you want the pill.
private struct PositionGrid: View {
    @Binding var selection: String
    private let rows: [[Prefs.HUDPosition]] = [[.topLeft, .topCenter, .topRight], [.bottomLeft, .bottomCenter, .bottomRight]]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.first!.rawValue) { row in
                HStack(spacing: 0) {
                    ForEach(row) { p in
                        Button { withAnimation(.snappy(duration: 0.2)) { selection = p.rawValue } } label: {
                            ZStack {
                                Capsule()
                                    .fill(selection == p.rawValue ? Color.accentColor : Color.secondary.opacity(0.25))
                                    .frame(width: selection == p.rawValue ? 22 : 12, height: 6)
                            }
                            .frame(width: 44, height: 30)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(p.label)
                    }
                }
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.background.secondary))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator, lineWidth: 1))
        .overlay(alignment: .bottom) {
            Capsule().fill(.separator).frame(width: 30, height: 3).offset(y: 7)
        }
        .padding(.bottom, 6)
        .accessibilityLabel("Indicator position")
    }
}

private struct AccentSwatches: View {
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Prefs.Accent.allCases) { a in
                Button { selection = a.rawValue } label: {
                    ZStack {
                        Circle()
                            .fill(swatch(a))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                        if selection == a.rawValue {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(a == .mono ? .black : .white)
                        }
                    }
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(a.label)
            }
        }
    }
    private func swatch(_ a: Prefs.Accent) -> AnyShapeStyle {
        switch a {
        case .mono: return AnyShapeStyle(LinearGradient(colors: [.white, Color(white: 0.8)], startPoint: .top, endPoint: .bottom))
        default: return AnyShapeStyle(Theme.color(for: a))
        }
    }
}

/// The pill exactly as it will look. The bars drive themselves on a timer, so
/// SwiftUI does no per-frame work here.
struct PillPreview: View {
    let accent: Prefs.Accent
    var look: Prefs.PillLook = Prefs.pillLook
    var shadow: Prefs.PillShadow = Prefs.pillShadow

    var body: some View {
        WaveformView(barWidth: 2.5, gap: 2, color: Theme.color(for: accent), demo: true)
            .frame(width: 84, height: 20)
            .pillChrome(look: look, shadow: shadow)
            .padding(.vertical, 6)
    }
}
