import Foundation
import Observation

/// Seven-day free trial, then a license key from Dodo Payments (the merchant of record).
/// Network: only Dodo's three public license endpoints, and only when you activate,
/// deactivate, or on the weekly re-check. Nothing else ever leaves the Mac.
@MainActor
@Observable
final class Licensing {
    enum State: Equatable {
        case trial(daysLeft: Int)
        case expired
        case licensed
    }

    static let trialDays = 7
    /// Re-check an activated key this often; a Mac that has been offline longer than the
    /// grace period falls back to the trial rules until it can reach Dodo again.
    static let revalidateEvery: TimeInterval = 7 * 86400
    static let offlineGrace: TimeInterval = 30 * 86400
    /// True once the checkout link in `Brand` points at a real product.
    /// The Buy button works once the website is real (its thank-you page is the return URL), or in test mode.
    static var isConfigured: Bool { UserDefaults.standard.bool(forKey: "dodoTest") || !Brand.checkoutURL.absoluteString.contains("REPLACE-ME") }

    private(set) var state: State = .trial(daysLeft: Licensing.trialDays)
    private(set) var licenseKeyMasked: String?
    /// Which key this Mac holds, from the product Dodo names on activation.
    enum Plan: String { case personal, team }
    private(set) var plan: Plan = .personal
    private(set) var busy = false
    var lastError: String?

    private let d = UserDefaults.standard
    private enum K {
        static let trialStart = "trialStart"
        static let key = "licenseKey"
        static let instance = "licenseInstance"
        static let lastValidated = "licenseValidated"
        static let plan = "licensePlan"
    }
    /// Dodo product ids of the team key (live, test); anything else is a personal key.
    private static let teamProducts: Set<String> = ["pdt_0NnyeIYh7eg5s2udMzUGZ", "pdt_0Nnye4HFHXLRKq4WkVJXG"]

    init() {
        refresh()
        Task { await revalidateIfDue() }
        // A menu bar app runs for weeks: recount the trial days and re-check the key daily,
        // not only at launch.
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(); await self?.revalidateIfDue() }
        }
    }

    var isExpired: Bool { state == .expired }
    var isLicensed: Bool { state == .licensed }

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
        if let key = d.string(forKey: K.key) {
            let validated = d.object(forKey: K.lastValidated) as? Date ?? .distantPast
            licenseKeyMasked = Self.mask(key)
            plan = Plan(rawValue: d.string(forKey: K.plan) ?? "") ?? .personal
            if Date().timeIntervalSince(validated) < Self.offlineGrace { state = .licensed; return }
            // Past the grace period: the trial rules apply until a re-check succeeds.
        } else {
            licenseKeyMasked = nil
        }
        let left = Self.trialDays - Int(Date().timeIntervalSince(trialStart) / 86400)
        state = left > 0 ? .trial(daysLeft: left) : .expired
    }

    // MARK: Dodo Payments

    /// Dodo's public license endpoints. `defaults write com.priyamventures.typevoice dodoTest -bool YES`
    /// points the app at test mode while you try a test-mode purchase.
    private var base: URL {
        URL(string: d.bool(forKey: "dodoTest") ? "https://test.dodopayments.com" : "https://live.dodopayments.com")!
    }

    private struct ActivateResponse: Decodable {
        struct Product: Decodable { let product_id: String }
        let id: String
        let product: Product?
    }
    private struct ValidateResponse: Decodable { let valid: Bool }
    private struct EmptyResponse: Decodable {}
    struct LicenseError: Error { let message: String }

    /// Activates a key for this Mac. Dodo records the activation under the Mac's name so the
    /// user can tell their Macs apart when deactivating one; nothing else is sent.
    func activate(_ rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !busy else { return }
        busy = true; lastError = nil
        defer { busy = false }
        do {
            let name = Host.current().localizedName ?? "Mac"
            let r: ActivateResponse = try await post("licenses/activate", ["license_key": key, "name": name])
            // Switching keys (say, from a personal to a team key): free the old seat, best effort.
            if let old = d.string(forKey: K.key), old != key, let inst = d.string(forKey: K.instance) {
                let _: EmptyResponse? = try? await post("licenses/deactivate", ["license_key": old, "license_key_instance_id": inst])
            }
            d.set(key, forKey: K.key)
            d.set(r.id, forKey: K.instance)
            d.set(Date(), forKey: K.lastValidated)
            d.set((r.product.map { Self.teamProducts.contains($0.product_id) } ?? false) ? Plan.team.rawValue : Plan.personal.rawValue, forKey: K.plan)
            refresh()
            Log.app.info("license activated (\(self.plan.rawValue))")
        } catch let e as LicenseError {
            lastError = e.message
        } catch {
            lastError = "Couldn't reach Dodo Payments. Check your connection and try again."
        }
    }

    /// Frees this Mac's activation so the key can be used on another one.
    func deactivate() async {
        guard !busy else { return }
        busy = true; lastError = nil
        defer { busy = false }
        if let key = d.string(forKey: K.key), let inst = d.string(forKey: K.instance) {
            do {
                let _: EmptyResponse = try await post("licenses/deactivate", ["license_key": key, "license_key_instance_id": inst])
            } catch let e as LicenseError {
                // Dodo said no (e.g. the activation is already gone): forget the key locally anyway.
                Log.app.warning("deactivate: \(e.message)")
            } catch {
                lastError = "Couldn't reach Dodo Payments. Check your connection and try again."
                return
            }
        }
        d.removeObject(forKey: K.key); d.removeObject(forKey: K.instance); d.removeObject(forKey: K.lastValidated); d.removeObject(forKey: K.plan)
        refresh()
        Log.app.info("license deactivated")
    }

    /// Weekly re-check. Offline Macs keep working through the grace period.
    func revalidateIfDue(force: Bool = false) async {
        guard let key = d.string(forKey: K.key) else { return }
        let last = d.object(forKey: K.lastValidated) as? Date ?? .distantPast
        guard force || Date().timeIntervalSince(last) > Self.revalidateEvery else { return }
        do {
            let r: ValidateResponse = try await post("licenses/validate", ["license_key": key, "license_key_instance_id": d.string(forKey: K.instance) ?? ""])
            if r.valid {
                d.set(Date(), forKey: K.lastValidated)
            } else {
                Log.app.warning("license no longer valid")
                d.removeObject(forKey: K.key); d.removeObject(forKey: K.instance); d.removeObject(forKey: K.lastValidated); d.removeObject(forKey: K.plan)
                lastError = "This key is no longer valid on this Mac. It may have been deactivated or refunded."
            }
            refresh()
        } catch {
            // Offline: keep going within the grace period.
        }
    }

    private func post<T: Decodable>(_ path: String, _ body: [String: String]) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("\(Brand.name)/\(Brand.version) macOS", forHTTPHeaderField: "User-Agent")
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200..<300:
            if T.self == EmptyResponse.self { return EmptyResponse() as! T }
            return try JSONDecoder().decode(T.self, from: data)
        case 404: throw LicenseError(message: "That key doesn't exist. Check it for typos.")
        case 403: throw LicenseError(message: "This key is inactive or has expired.")
        case 422: throw LicenseError(message: path.hasSuffix("activate")
                                     ? "This key is already in use on its maximum number of Macs. Deactivate one of them first."
                                     : "That doesn't look like a \(Brand.name) key.")
        default: throw LicenseError(message: "Dodo Payments returned an error (\(code)). Try again in a moment.")
        }
    }

    static func mask(_ key: String) -> String {
        guard key.count > 8 else { return key }
        return String(key.prefix(4)) + "••••" + String(key.suffix(4))
    }
}
