import Foundation
import Observation
import Security

// Codable-Modelle = backend/app/schemas.py (snake_case wird automatisch umgewandelt).

struct StoreDTO: Codable, Hashable {
    var chain: String
    var storeRef = ""
    var storeName = ""
    var enabled = true
}

struct HouseholdDTO: Codable {
    var id: Int
    var name: String
    var plz: String
    var persons: Int
    var diet: String
    var allergies: [String]
    var excludedIngredients: [String]
    var cuisines: [String]
    var mealTypes: [String]
    var planDays: [Int]
    var budgetFoodWeekCents: Int
    var budgetDrugstoreCents: Int?
    var nutritionGoal: String
    var maxCookMinutes: Int
    var stores: [StoreDTO]
}

struct HouseholdCreated: Codable {
    var token: String
    var household: HouseholdDTO
}

struct OfferDTO: Codable, Identifiable, Hashable {
    var id: Int
    var chain: String
    var title: String
    var brand: String
    var category: String
    var priceCents: Int
    var regularPriceCents: Int?
    var amount: Double?
    var unit: String
    var basePriceCents: Int?
    var validFrom: String
    var validTo: String
    var imageUrl: String
}

enum APIError: LocalizedError {
    case noServer, http(Int)

    var errorDescription: String? {
        switch self {
        case .noServer: "Keine Server-Adresse eingestellt."
        case .http(401): "Nicht angemeldet."
        case .http(let code): "Server-Fehler (\(code))."
        }
    }
}

@MainActor @Observable
final class API {
    var baseURL: String = UserDefaults.standard.string(forKey: "backendURL") ?? "" {
        didSet { UserDefaults.standard.set(baseURL, forKey: "backendURL") }
    }
    var token: String? = Keychain.read() {
        didSet { Keychain.write(token) }
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    func health() async -> Bool {
        struct Health: Decodable { var status: String }
        return (try? await request("GET", "/health") as Health)?.status == "ok"
    }

    func request<T: Decodable>(_ method: String, _ path: String, body: (some Encodable)? = nil as String?) async throws -> T {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces) + path), !baseURL.isEmpty else { throw APIError.noServer }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw APIError.http(code) }
        return try decoder.decode(T.self, from: data)
    }
}

/// Token gehört in den Schlüsselbund, nicht in UserDefaults.
enum Keychain {
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
                                               kSecAttrService as String: "de.jsenf.essenapp.token"] }

    static func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ token: String?) {
        SecItemDelete(query as CFDictionary)
        guard let token else { return }
        var q = query
        q[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}
