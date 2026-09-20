import Foundation

/// The price for the country this Mac is in, from the site's `/geo` (the same table the site and
/// the Dodo checkout use). One GET with nothing about the user in it; only asked for on the
/// License tab, and only until a key is activated. Nil means the list price applies.
struct RegionalPrice: Decodable, Sendable {
    let country: String
    let currency: String
    let personal: Int
    let team: Int
    let tax: String

    /// "🇮🇳" from "IN".
    var flag: String {
        String(String.UnicodeScalarView(country.unicodeScalars.compactMap { UnicodeScalar(0x1F1E6 + $0.value - 65) }))
    }

    func format(_ amount: Int) -> String {
        Decimal(amount).formatted(.currency(code: currency).precision(.fractionLength(0)).locale(Locale(identifier: "en_US")))
    }

    static func fetch() async -> RegionalPrice? {
        var request = URLRequest(url: Brand.website.appendingPathComponent("geo"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let price = try? JSONDecoder().decode(RegionalPrice.self, from: data),
              price.country.count == 2 else { return nil }
        return price
    }
}
