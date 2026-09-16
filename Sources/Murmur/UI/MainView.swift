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
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .safeAreaInset(edge: .bottom) { StatusFooter(state: state) }
        } detail: {
            switch tab {
            case .history: HistoryView(history: history)
            case .dictionary: DictionaryView(dictionary: dictionary)
            case .style: StyleView()
            case .settings: SettingsView()
            case .privacy: PrivacyView(history: history, dictionary: dictionary)
            }
        }
        .frame(minWidth: 720, minHeight: 460)
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
