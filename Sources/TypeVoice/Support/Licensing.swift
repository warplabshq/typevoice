import Foundation
import Observation
import RevenueCat

/// Three-day free trial, then "Pro" through the App Store, managed by RevenueCat.
/// Network: only App Store purchase validation via RevenueCat. Nothing else.
@MainActor
@Observable
final class Licensing {
    enum State: Equatable {
        case trial(daysLeft: Int)
        case expired
        case pro
    }

    static let trialDays = 3
    /// RevenueCat public SDK key for this app (starts with "appl_"). Replace before shipping.
    /// From Sources/TypeVoice/Support/Secrets.swift (git-ignored; `make` creates it from Secrets.example.swift).
    static let apiKey = Secrets.revenueCatAPIKey
    static let entitlement = "pro"
    static var isConfigured: Bool { !apiKey.contains("REPLACE-ME") }
    /// The random identifier RevenueCat knows this Mac by. Shown in the License tab so a
    /// user can ask for their (anonymous) purchase records to be deleted.
    static var supportID: String? { isConfigured ? Purchases.shared.appUserID : nil }

    private(set) var state: State = .trial(daysLeft: Licensing.trialDays)
    private(set) var packages: [Package] = []
    private(set) var busy = false
    var lastError: String?

    private let d = UserDefaults.standard
    private enum K { static let trialStart = "trialStart"; static let pro = "proCached" }

    init() {
        if Self.isConfigured {
            Purchases.logLevel = .warn
            Purchases.configure(withAPIKey: Self.apiKey)
        }
        refresh()
        Task { await sync() }
    }

    var isExpired: Bool { state == .expired }

    // MARK: Trial

    /// First-launch date, kept in defaults and in a hidden marker file so a
    /// reinstall doesn't restart the clock.
    private var trialStart: Date {
        if let t = d.object(forKey: K.trialStart) as? Date { return t }
        let marker = Paths.support.appendingPathComponent(".first")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: marker.path), let c = attrs[.creationDate] as? Date {
            d.set(c, forKey: K.trialStart); return c
        }
        let now = Date()
        d.set(now, forKey: K.trialStart)
        FileManager.default.createFile(atPath: marker.path, contents: Data())
        return now
    }

    func refresh() {
        if d.bool(forKey: K.pro) { state = .pro; return }
        let left = Self.trialDays - Int(Date().timeIntervalSince(trialStart) / 86400)
        state = left > 0 ? .trial(daysLeft: left) : .expired
    }

    // MARK: RevenueCat

    /// Pulls entitlements and the current offering. Safe to call any time.
    func sync() async {
        guard Self.isConfigured else { return }
        do {
            let info = try await Purchases.shared.customerInfo()
            apply(info)
            if let current = try await Purchases.shared.offerings().current {
                packages = current.availablePackages
            }
        } catch {
            Log.app.warning("revenuecat sync: \(error.localizedDescription)")
        }
    }

    func purchase(_ package: Package) async {
        guard !busy else { return }
        busy = true; lastError = nil
        defer { busy = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if !result.userCancelled { apply(result.customerInfo) }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore() async {
        guard !busy else { return }
        busy = true; lastError = nil
        defer { busy = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(info)
            if state != .pro { lastError = "No purchase found for this Apple ID." }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func apply(_ info: CustomerInfo) {
        let pro = info.entitlements[Self.entitlement]?.isActive == true
        d.set(pro, forKey: K.pro)
        refresh()
        Log.app.info("entitlement pro=\(pro)")
    }
}
