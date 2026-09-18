import AppKit
import SwiftUI

/// Icon of the app a dictation went into. Cached; falls back to a generic glyph.
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    @MainActor
    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let c = cache[bundleID] { return c }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 32, height: 32)
        cache[bundleID] = img
        return img
    }
}

struct AppIconView: View {
    let bundleID: String?
    var size: CGFloat = 22
    var body: some View {
        if let img = AppIcons.icon(for: bundleID) {
            Image(nsImage: img).resizable().frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: size, height: size)
                .overlay(Image(systemName: "app").font(.system(size: size * 0.5)).foregroundStyle(.secondary))
        }
    }
}
