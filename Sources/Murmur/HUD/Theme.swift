import SwiftUI

enum Theme {
    /// Monochrome by default. The accent only tints the waveform and the check.
    static var accent: Color { color(for: Prefs.accent) }
    static let onGlass = Color.white
    static let onGlassDim = Color.white.opacity(0.62)

    static func color(for a: Prefs.Accent) -> Color {
        switch a {
        case .mono: return .white
        case .system: return Color(nsColor: .controlAccentColor)
        case .blue: return Color(red: 0.35, green: 0.62, blue: 1.00)
        case .purple: return Color(red: 0.72, green: 0.55, blue: 1.00)
        case .pink: return Color(red: 1.00, green: 0.50, blue: 0.70)
        case .green: return Color(red: 0.40, green: 0.85, blue: 0.55)
        case .amber: return Color(red: 1.00, green: 0.72, blue: 0.35)
        }
    }

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

/// The pill's material, rim and shadow. Used by the real HUD and every preview,
/// so what you see in Settings is exactly what appears on screen.
struct PillChrome: ViewModifier {
    var look: Prefs.PillLook = Prefs.pillLook
    var shadow: Prefs.PillShadow = Prefs.pillShadow

    func body(content: Content) -> some View {
        content
            .frame(height: 22)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                ZStack {
                    // Glass underneath for refraction; "Black" skips it so it is truly black.
                    if look != .black {
                        Capsule().fill(.clear).glassEffect(.regular, in: .capsule)
                    }
                    // The shadow lives on this static shape, never on the animating content,
                    // so nothing is re-rasterised per frame and the bars stay crisp.
                    Capsule()
                        .fill(Color.black.opacity(look.tint))
                        .shadow(color: .black.opacity(shadowAlpha(0.28, 0.45)), radius: shadowRadius, y: shadowY)
                        .shadow(color: .black.opacity(shadowAlpha(0.16, 0.25)), radius: shadow == .none ? 0 : 2, y: shadow == .none ? 0 : 1)
                    Capsule().strokeBorder(
                        LinearGradient(colors: [.white.opacity(look == .glass ? 0.22 : 0.14), .white.opacity(0.03)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.6
                    )
                }
            }
    }

    private func shadowAlpha(_ soft: Double, _ strong: Double) -> Double {
        switch shadow { case .none: return 0; case .soft: return soft; case .strong: return strong }
    }
    private var shadowRadius: CGFloat { switch shadow { case .none: return 0; case .soft: return 16; case .strong: return 26 } }
    private var shadowY: CGFloat { switch shadow { case .none: return 0; case .soft: return 6; case .strong: return 10 } }
}

extension View {
    func pillChrome(look: Prefs.PillLook = Prefs.pillLook, shadow: Prefs.PillShadow = Prefs.pillShadow) -> some View {
        modifier(PillChrome(look: look, shadow: shadow))
    }
}
