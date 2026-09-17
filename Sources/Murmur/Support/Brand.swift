import Foundation

/// Everything that changes in a rebrand lives here (plus `project.yml`,
/// `Packaging/Info.plist` and the icon). UI code never hard-codes the name.
enum Brand {
    /// Display name, from the bundle so Info.plist stays the single source of truth.
    static let name: String =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
        ?? "Murmur"
    static let tagline = "Local dictation"
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.priyam.murmur"
    static let company = "Priyam Ventures"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
}
