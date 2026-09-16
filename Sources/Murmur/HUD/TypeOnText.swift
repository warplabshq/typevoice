import SwiftUI

/// Reveals the inserted sentence character by character, then flicks a check.
/// Hugs its text up to `maxWidth`, then truncates.
struct TypeOnText: View {
    let text: String
    var maxWidth: CGFloat = 440
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { ctx in
            let elapsed = ctx.date.timeIntervalSince(start)
            let per = min(0.012, 0.4 / Double(max(text.count, 1)))
            let n = min(text.count, Int(elapsed / per))
            let finished = n >= text.count
            HStack(spacing: 10) {
                HuggingText(text: String(text.prefix(n)), maxWidth: maxWidth - 30)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .scaleEffect(finished ? 1 : 0.4)
                    .opacity(finished ? 1 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.55), value: finished)
            }
        }
        .onAppear { start = Date() }
    }
}

/// Single-line text that takes only the width it needs, until `maxWidth`.
struct HuggingText: View {
    let text: String
    let maxWidth: CGFloat
    var body: some View {
        ViewThatFits(in: .horizontal) {
            label.fixedSize(horizontal: true, vertical: false)
            label.frame(width: maxWidth, alignment: .leading)
        }
        .frame(maxWidth: maxWidth)
    }
    private var label: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.onGlass)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
