import SwiftUI

enum MainTab: String, CaseIterable, Identifiable, Hashable {
    case history, dictionary, style, settings, privacy
    var id: String { rawValue }
    var label: String {
        switch self {
        case .history: return "History"
        case .dictionary: return "Dictionary"
        case .style: return "Style"
        case .settings: return "Settings"
        case .privacy: return "Privacy"
        }
    }
    var icon: String {
        switch self {
        case .history: return "clock"
        case .dictionary: return "character.book.closed"
        case .style: return "textformat"
        case .settings: return "gearshape"
        case .privacy: return "lock.shield"
        }
    }
}

/// The app's one real window. Sidebar + detail, like every good Mac app.
struct MainView: View {
    let state: AppState
    let history: HistoryStore
    let dictionary: DictionaryStore
    @Binding var tab: MainTab

    var body: some View {
        NavigationSplitView {
            List(MainTab.allCases, selection: Binding(get: { Optional(tab) }, set: { tab = $0 ?? .history })) { t in
                Label(t.label, systemImage: t.icon).tag(t)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .top) { Brand() }
            .safeAreaInset(edge: .bottom) { StatusFooter(state: state) }
        } detail: {
            Group {
                switch tab {
                case .history: HistoryView(history: history)
                case .dictionary: DictionaryView(dictionary: dictionary)
                case .style: StyleView()
                case .settings: SettingsView()
                case .privacy: PrivacyView(history: history, dictionary: dictionary)
                }
            }
            .navigationTitle(tab.label)
            // Every tab carries a toolbar so the title bar keeps one height.
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { NotificationCenter.default.post(name: .murmurShowOnboarding, object: nil) } label: {
                        Label("How to use", systemImage: "questionmark.circle")
                    }
                    .help("How to use Murmur")
                }
            }
        }
        .frame(minWidth: 800, minHeight: 520)
    }
}

/// Small brand row at the top of the sidebar.
private struct Brand: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 30, height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Murmur").font(.headline)
                Text("Local dictation").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

/// Model state + hint, pinned under the sidebar.
private struct StatusFooter: View {
    let state: AppState
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.isReady ? Color.green : (state.warmError == nil ? Color.orange : Color.red))
                .frame(width: 7, height: 7)
            Text(state.warmError ?? (state.isReady ? "On-device, ready" : state.warm.label))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
