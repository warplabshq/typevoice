import SwiftUI

enum Theme {
    /// One accent. Warm, reads on any wallpaper.
    static let accent = Color(red: 1.00, green: 0.60, blue: 0.34)
    static let accentSoft = Color(red: 1.00, green: 0.80, blue: 0.62)
    static let onGlass = Color.white
    static let onGlassDim = Color.white.opacity(0.62)

    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.80)
    static let springSoft = Animation.spring(response: 0.52, dampingFraction: 0.86)
    static let quick = Animation.easeOut(duration: 0.16)
}

/// Fade + blur + slight scale. The only content transition the HUD uses.
struct BlurFade: ViewModifier {
    let amount: CGFloat
    func body(content: Content) -> some View {
        content
            .blur(radius: amount * 6)
            .opacity(1 - Double(amount))
            .scaleEffect(1 - amount * 0.05)
    }
}

extension AnyTransition {
    static let blurFade = AnyTransition.modifier(active: BlurFade(amount: 1), identity: BlurFade(amount: 0))
}
