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

    /// Website (the typevoice-site repo, Cloudflare Pages). Clean paths; Pages redirects `.html`.
    static let website = URL(string: "https://typevoice.ai")!
    static var privacyURL: URL { website.appendingPathComponent("privacy") }
    static var termsURL: URL { website.appendingPathComponent("terms") }
    static var eulaURL: URL { website.appendingPathComponent("eula") }
    static var supportURL: URL { website.appendingPathComponent("support") }
    static let supportEmail = "mail@warplabs.co"

    /// Dodo Payments hosted checkout for the one-time purchase (live product
    /// pdt_0NnyeIUl5lH6A5vMnNQl0; its test-mode twin is pdt_0Nnye4FRV4gyNve43FkdY on
    /// test.checkout.dodopayments.com, used when the `dodoTest` default is on). The return
    /// page hands the new key back to the app.
    static var checkoutURL: URL {
        let test = UserDefaults.standard.bool(forKey: "dodoTest")
        let base = test ? "https://test.checkout.dodopayments.com/buy/pdt_0Nnye4FRV4gyNve43FkdY"
                        : "https://checkout.dodopayments.com/buy/pdt_0NnyeIUl5lH6A5vMnNQl0"
        return URL(string: base + "?redirect_url=" + returnPage)!
    }

    /// Where Dodo sends the buyer afterwards, percent-encoded. Test mode returns to the locally
    /// served site, so the whole flow can be tried before launch.
    private static var returnPage: String {
        let test = UserDefaults.standard.bool(forKey: "dodoTest")
        let page = test ? "http://localhost:8787/thanks.html" : website.appendingPathComponent("thanks").absoluteString
        return page.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }
    /// Shown next to the Buy buttons; keep them in step with the Dodo products.
    static let price = "$79"
    static let teamPrice = "$299"
    static let teamSeats = 5

    /// The team key: one purchase, one shared key, five people with two Macs each.
    static var teamCheckoutURL: URL {
        let test = UserDefaults.standard.bool(forKey: "dodoTest")
        let base = test ? "https://test.checkout.dodopayments.com/buy/pdt_0Nnye4HFHXLRKq4WkVJXG"
                        : "https://checkout.dodopayments.com/buy/pdt_0NnyeIYh7eg5s2udMzUGZ"
        return URL(string: base + "?redirect_url=" + returnPage)!
    }
    /// Custom URL scheme, registered in Info.plist. The site's thank-you page opens
    /// `typevoice://activate?key=…` so a fresh purchase lands in the app without retyping.
    static let urlScheme = "typevoice"
}
