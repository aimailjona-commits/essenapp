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

    func request<T: Decodable>(_ method: String, _ path: String, body: (some Encodable)? = nil as String?,
                               timeout: TimeInterval = 15) async throws -> T {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces) + path), !baseURL.isEmpty else { throw APIError.noServer }
        var req = URLRequest(url: url, timeoutInterval: timeout)
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

struct IngredientDTO: Codable, Hashable {
    var name: String
    var amount: Double
    var unit: String
    var offerId: Int?
    var inPantry: Bool
}

struct RecipeDTO: Codable, Identifiable, Hashable {
    var id: Int
    var title: String
    var description: String
    var cuisine: String
    var mealType: String
    var servings: Int
    var prepMinutes: Int
    var ingredients: [IngredientDTO]
    var steps: [String]
    var imageUrl: String
}

struct MealDTO: Codable, Hashable {
    var day: Int
    var mealType: String
    var costCents: Int
    var locked: Bool
    var recipe: RecipeDTO
}

struct PlanDTO: Codable {
    var id: Int
    var week: String
    var totalCents: Int
    var savedCents: Int
    var entries: [MealDTO]
}

/// Anzeige-Namen; Schlüssel wie im Backend.
enum Labels {
    static let chains: [(key: String, name: String, drugstore: Bool)] = [
        ("rewe", "Rewe", false), ("aldi_sued", "Aldi Süd", false), ("aldi_nord", "Aldi Nord", false), ("lidl", "Lidl", false),
        ("edeka", "Edeka", false), ("kaufland", "Kaufland", false), ("penny", "Penny", false), ("netto_md", "Netto", false),
        ("dm", "dm", true), ("rossmann", "Rossmann", true),
    ]
    static func chain(_ key: String) -> String { chains.first { $0.key == key }?.name ?? key }

    static let mealTypes = [("fruehstueck", "Frühstück"), ("mittag", "Mittag"), ("abend", "Abend"), ("dessert", "Dessert")]
    static func meal(_ key: String) -> String { mealTypes.first { $0.0 == key }?.1 ?? key }

    static let days = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    static let dayNames = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
    static let diets = [("alles", "Alles"), ("vegetarisch", "Vegetarisch"), ("vegan", "Vegan"), ("pescetarisch", "Pescetarisch"), ("halal", "Halal")]
    static let allergies = ["Gluten", "Laktose", "Nüsse", "Erdnüsse", "Ei", "Soja", "Fisch", "Sellerie"]
    static let goals = [("ausgewogen", "Ausgewogen", "Alle Nährstoffe abdecken"), ("proteinreich", "Proteinreich", "Viel Eiweiß"),
                        ("kalorienarm", "Kalorienarm", "Leichter essen")]
    static let cuisines = ["Indisch", "Asiatisch", "Italienisch", "Deutsch", "Mexikanisch", "Orientalisch"]
    static let categories = [("obst_gemuese", "🥦 Obst & Gemüse"), ("fleisch_fisch", "🥩 Fleisch & Fisch"), ("kuehlung", "🧀 Kühlung"),
                             ("vorrat", "🥫 Vorrat"), ("getraenke", "🥤 Getränke"), ("drogerie", "🧴 Drogerie"), ("haushalt", "🧽 Haushalt")]
}

/// Settings-PATCH: nur gesetzte Felder werden gesendet (Optionals fallen beim Encoden weg).
struct HouseholdPatch: Encodable {
    var name: String?
    var plz: String?
    var persons: Int?
    var diet: String?
    var allergies: [String]?
    var excludedIngredients: [String]?
    var cuisines: [String]?
    var mealTypes: [String]?
    var planDays: [Int]?
    var budgetFoodWeekCents: Int?
    var nutritionGoal: String?
    var stores: [StoreDTO]?
}

/// App-Zustand: lädt und hält Haushalt, Angebote und Plan.
@MainActor @Observable
final class AppStore {
    let api: API
    var household: HouseholdDTO?
    var offers: [OfferDTO] = []
    var plan: PlanDTO?
    var error: String?
    var generating = false

    let demo = Demo.screen != nil

    init(api: API) {
        self.api = api
        if demo, Demo.screen != "empty" {
            household = Demo.household; offers = Demo.offers; plan = Demo.plan
        }
    }

    var isOnboarded: Bool { demo ? Demo.screen != "onboarding" : api.token != nil }

    func createHousehold(name: String, memberName: String) async throws {
        struct Body: Encodable { var name: String; var memberName: String }
        let created: HouseholdCreated = try await api.request("POST", "/households", body: Body(name: name, memberName: memberName))
        api.token = created.token
        household = created.household
    }

    func save(_ patch: HouseholdPatch) async throws {
        household = try await api.request("PATCH", "/household", body: patch)
    }

    func loadAll() async {
        guard !demo else { return }
        do {
            household = try await api.request("GET", "/household")
            offers = try await api.request("GET", "/offers")
            plan = try? await api.request("GET", "/plans/current")
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Lädt die Angebote der Läden neu (Backend fragt kaufDA, dauert 10–60 s).
    func refreshOffers() async {
        struct Result: Decodable { var imported: Int }
        do {
            let _: Result = try await api.request("POST", "/offers/refresh", timeout: 180)
            offers = try await api.request("GET", "/offers")
        } catch {
            self.error = error.localizedDescription
        }
    }

    func generatePlan() async {
        generating = true
        defer { generating = false }
        do {
            plan = try await api.request("POST", "/plans", timeout: 300)  // KI-Plan dauert bis ~2 min
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Gericht für heute (erste Mahlzeit des heutigen Wochentags, Mittag bevorzugt).
    var todayMeal: MealDTO? {
        let weekday = demo ? 1 : (Calendar(identifier: .iso8601).component(.weekday, from: .now) + 5) % 7  // 0 = Montag
        let today = plan?.entries.filter { $0.day == weekday } ?? []
        return today.first { $0.mealType == "mittag" } ?? today.first
    }
}
