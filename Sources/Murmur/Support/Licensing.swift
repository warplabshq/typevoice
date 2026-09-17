import Foundation
import Observation

/// Three-day free trial, then a license key from Dodo Payments.
/// Network: only the two public license endpoints, only when you activate or
/// on the weekly re-check. Nothing else ever leaves the Mac.
@MainActor
@Observable
final class Licensing {
    enum State: Equatable {
        case trial(daysLeft: Int)
        case expired
        case licensed
    }

    static let trialDays = 3
    /// Hosted checkout for the product. Replace with the real Dodo checkout link.
    static let checkoutURL = URL(string: "https://checkout.dodopayments.com/buy/REPLACE-ME")!
    /// Grace period without a successful re-validation (offline Macs keep working).
    static let revalidateEvery: TimeInterval = 7 * 86400
    static let offlineGrace: TimeInterval = 30 * 86400

    private(set) var state: State = .trial(daysLeft: Licensing.trialDays)
    private(set) var licenseKeyMasked: String?
    var lastError: String?

    private let d = UserDefaults.standard
    private enum K {
        static let trialStart = "trialStart"
        static let key = "licenseKey"
        static let instance = "licenseInstance"
        static let lastValidated = "licenseValidated"
    }

    init() {
        refresh()
        Task { await revalidateIfDue() }
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
        if d.string(forKey: K.key) != nil {
            let validated = d.object(forKey: K.lastValidated) as? Date ?? .distantPast
            state = Date().timeIntervalSince(validated) < Self.offlineGrace ? .licensed : .expired
            licenseKeyMasked = Self.mask(d.string(forKey: K.key) ?? "")
            return
        }
        let elapsed = Date().timeIntervalSince(trialStart)
        let left = Self.trialDays - Int(elapsed / 86400)
        state = left > 0 ? .trial(daysLeft: left) : .expired
        licenseKeyMasked = nil
    }

    // MARK: Dodo Payments

    private var base: URL {
        URL(string: d.bool(forKey: "dodoTest") ? "https://test.dodopayments.com" : "https://dodopayments.com")!
    }

    struct ActivateResponse: Decodable { let id: String }
    struct ValidateResponse: Decodable { let valid: Bool }

    /// Activates a key for this Mac. Throws a readable message on failure.
    func activate(_ rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        lastError = nil
        do {
            let name = Host.current().localizedName ?? "Mac"
            let r: ActivateResponse = try await post("licenses/activate", ["license_key": key, "name": name])
            d.set(key, forKey: K.key)
            d.set(r.id, forKey: K.instance)
            d.set(Date(), forKey: K.lastValidated)
            refresh()
            Log.app.info("license activated")
        } catch let e as LicenseError {
            lastError = e.message
        } catch {
            lastError = "Couldn't reach Dodo Payments. Check your connection and try again."
        }
    }

    func deactivate() async {
        if let key = d.string(forKey: K.key), let inst = d.string(forKey: K.instance) {
            _ = try? await post("licenses/deactivate", ["license_key": key, "license_key_instance_id": inst]) as EmptyResponse
        }
        d.removeObject(forKey: K.key); d.removeObject(forKey: K.instance); d.removeObject(forKey: K.lastValidated)
        refresh()
    }

    func revalidateIfDue() async {
        guard let key = d.string(forKey: K.key) else { return }
        let last = d.object(forKey: K.lastValidated) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > Self.revalidateEvery else { return }
        do {
            let r: ValidateResponse = try await post("licenses/validate", ["license_key": key, "license_key_instance_id": d.string(forKey: K.instance) ?? ""])
            if r.valid {
                d.set(Date(), forKey: K.lastValidated)
            } else {
                Log.app.warning("license no longer valid")
                d.removeObject(forKey: K.key); d.removeObject(forKey: K.instance)
            }
            refresh()
        } catch {
            // Offline: keep going within the grace period.
        }
    }

    struct EmptyResponse: Decodable {}
    struct LicenseError: Error { let message: String }

    private func post<T: Decodable>(_ path: String, _ body: [String: String]) async throws -> T {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200..<300:
            if T.self == EmptyResponse.self { return EmptyResponse() as! T }
            return try JSONDecoder().decode(T.self, from: data)
        case 404: throw LicenseError(message: "That key doesn't exist. Check for typos.")
        case 403: throw LicenseError(message: "This key is inactive or has expired.")
        case 422: throw LicenseError(message: "This key is already used on its maximum number of Macs.")
        default: throw LicenseError(message: "Dodo Payments returned an error (\(code)). Try again in a moment.")
        }
    }

    static func mask(_ key: String) -> String {
        guard key.count > 8 else { return key }
        return String(key.prefix(4)) + "••••" + String(key.suffix(4))
    }
}
