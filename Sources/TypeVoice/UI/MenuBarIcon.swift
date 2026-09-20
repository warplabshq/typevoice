import AppKit
import SwiftUI

/// The menu bar glyph: the brand waveform as a template image so it follows the menu
/// bar's light and dark appearance. Three states so the menu bar tells you what the app
/// is doing without a HUD: resting bars, bars lifted a little while listening, and a dimmed
/// glyph while it works on the words. State changes ease over a quarter second instead of
/// snapping, so the icon breathes rather than jumps.
enum MenuBarIcon {
    /// Listening: the same silhouette, a third taller. Recognisably the brand, visibly awake.
    static let listeningHeights: [CGFloat] = BrandWave.heights.map { min(1, $0 * 1.35) }
    static let pausedHeights: [CGFloat] = BrandWave.heights.map { $0 * 0.55 }

    // 1.5 pt bars give the icon's proportions a 12.5 pt tallest bar on an 18 pt canvas.
    static let image = BrandWave.image(height: 18, barWidth: 1.5)

    /// The look a phase asks for: bar heights and opacity.
    struct Look: Equatable {
        var heights: [CGFloat]
        var alpha: CGFloat
        static let resting = Look(heights: BrandWave.heights, alpha: 1)
        static let listening = Look(heights: listeningHeights, alpha: 1)
        static let processing = Look(heights: BrandWave.heights, alpha: 0.42)
        static let paused = Look(heights: pausedHeights, alpha: 0.55)

        static func mix(_ a: Look, _ b: Look, _ t: CGFloat) -> Look {
            Look(heights: zip(a.heights, b.heights).map { $0 + ($1 - $0) * t }, alpha: a.alpha + (b.alpha - a.alpha) * t)
        }
        var image: NSImage { BrandWave.image(height: 18, barWidth: 1.5, alpha: alpha, heights: heights) }
    }

    static func look(for phase: AppState.Phase, paused: Bool) -> Look {
        if paused { return .paused }
        switch phase {
        case .listening: return .listening
        case .processing: return .processing
        default: return .resting
        }
    }

    static func image(for phase: AppState.Phase, paused: Bool) -> NSImage { look(for: phase, paused: paused).image }
}

/// The menu bar label: eases between looks over ~240 ms (eight small frames), so listening
/// lifts the bars instead of swapping in a different icon.
struct MenuBarGlyph: View {
    let target: MenuBarIcon.Look
    @State private var shown: MenuBarIcon.Look = .resting
    @State private var animator: Task<Void, Never>?

    var body: some View {
        Image(nsImage: shown.image)
            .onAppear { shown = target }
            .onChange(of: target) { _, next in
                animator?.cancel()
                let from = shown
                animator = Task { @MainActor in
                    let steps = 8
                    for i in 1...steps {
                        try? await Task.sleep(for: .milliseconds(30))
                        if Task.isCancelled { return }
                        let t = CGFloat(i) / CGFloat(steps)
                        let eased = 1 - pow(1 - t, 3)   // ease-out
                        shown = MenuBarIcon.Look.mix(from, next, eased)
                    }
                    shown = next
                }
            }
    }
}
