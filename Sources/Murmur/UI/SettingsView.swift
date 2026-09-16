import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Prefs.Key.trigger) private var trigger = Prefs.Trigger.fn.rawValue
    @AppStorage(Prefs.Key.smartCleanup) private var smart = true
    @AppStorage(Prefs.Key.sounds) private var sounds = true
    @AppStorage(Prefs.Key.haptics) private var haptics = true
    @AppStorage(Prefs.Key.hudPosition) private var hudPosition = Prefs.HUDPosition.bottom.rawValue
    @AppStorage(Prefs.Key.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(Prefs.Key.insertion) private var insertion = Prefs.Insertion.auto.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var advanced = false

    var body: some View {
        Form {
            Section {
                Picker("Hold to dictate", selection: $trigger) {
                    Text("🌐 Globe / Fn key").tag(Prefs.Trigger.fn.rawValue)
                    Text("Custom shortcut").tag(Prefs.Trigger.custom.rawValue)
                }
                if trigger == Prefs.Trigger.custom.rawValue {
                    KeyboardShortcuts.Recorder("Shortcut", name: .dictate)
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
            }
            Section {
                Toggle("Smart cleanup", isOn: $smart)
                Text("Fixes false starts and self-corrections with Apple Intelligence, on this Mac. Never adds anything. Tone lives under Style.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Sounds", isOn: $sounds)
                Toggle("Haptics", isOn: $haptics)
                Picker("Show indicator at", selection: $hudPosition) {
                    ForEach(Prefs.HUDPosition.allCases) { Text($0.label).tag($0.rawValue) }
                }
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
            }
            Section {
                DisclosureGroup("Advanced", isExpanded: $advanced) {
                    Picker("Insert text via", selection: $insertion) {
                        Text("Accessibility, then paste").tag(Prefs.Insertion.auto.rawValue)
                        Text("Always paste").tag(Prefs.Insertion.paste.rawValue)
                    }
                    LabeledContent("Speech model") {
                        Text("Parakeet TDT 0.6B v2 · on-device")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onChange(of: trigger) { _, _ in
            NotificationCenter.default.post(name: .murmurTriggerChanged, object: nil)
        }
    }
}
