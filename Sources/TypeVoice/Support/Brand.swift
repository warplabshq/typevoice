import Foundation

/// Everything that changes in a rebrand lives here (plus `Packaging/Info.plist`,
/// the Makefile and the icon). UI code never hard-codes the name.
enum Brand {
    /// Display name, from the bundle so Info.plist stays the single source of truth.
    static let name: String =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
        ?? "TypeVoice"
    static let tagline = "Local dictation"
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.priyamventures.typevoice"
    static let company = "Priyam Ventures"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    /// Website. Replace the host once the site is deployed (the typevoice-site repo).
    static let website = URL(string: "https://REPLACE-ME.example")!
    static var privacyURL: URL { website.appendingPathComponent("privacy.html") }
    static var termsURL: URL { website.appendingPathComponent("terms.html") }
    static var eulaURL: URL { website.appendingPathComponent("eula.html") }
    static var supportURL: URL { website.appendingPathComponent("support.html") }
    static let supportEmail = "support@REPLACE-ME.example"

    /// Dodo Payments hosted checkout for the one-time purchase. The product id comes from
    /// the Dodo dashboard (Products › your product › Share); test mode uses
    /// https://test.checkout.dodopayments.com/buy/… instead.
    static let checkoutURL = URL(string: "https://checkout.dodopayments.com/buy/REPLACE-ME")!
    /// Shown next to the Buy button; keep it in step with the Dodo product price.
    static let price = "$79"
    /// Custom URL scheme, registered in Info.plist. The site's thank-you page opens
    /// `typevoice://activate?key=…` so a fresh purchase lands in the app without retyping.
    static let urlScheme = "typevoice"
}
