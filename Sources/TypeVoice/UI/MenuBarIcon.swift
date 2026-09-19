import AppKit

/// The menu bar glyph: the brand waveform as a template image so it follows the menu
/// bar's light and dark appearance. Three states so the menu bar tells you what the app
/// is doing without a HUD: resting bars, bars raised while listening, and a dimmed glyph
/// while it works on the words.
enum MenuBarIcon {
    /// Raised, as if mid-sentence.
    static let listeningHeights: [CGFloat] = [0.40, 0.66, 0.90, 0.98, 0.78, 0.94, 0.70, 0.44]

    // 1.5 pt bars give the icon's proportions a 12.5 pt tallest bar on an 18 pt canvas.
    static let image = BrandWave.image(height: 18, barWidth: 1.5)
    static let listening = BrandWave.image(height: 18, barWidth: 1.5, heights: listeningHeights)
    static let processing = BrandWave.image(height: 18, barWidth: 1.5, alpha: 0.42)
    static let paused = BrandWave.image(height: 18, barWidth: 1.5, alpha: 0.55, heights: BrandWave.heights.map { $0 * 0.55 })

    static func image(for phase: AppState.Phase, paused: Bool) -> NSImage {
        if paused { return Self.paused }
        switch phase {
        case .listening: return listening
        case .processing: return processing
        default: return image
        }
    }
}
