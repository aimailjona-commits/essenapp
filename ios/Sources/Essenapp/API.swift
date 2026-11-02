import Foundation
import SwiftUI
import Observation
import Security

// Codable-Modelle = backend/app/schemas.py (snake_case wird automatisch umgewandelt).

struct StoreDTO: Codable, Hashable {
    var chain: String
    var storeRef = ""
    var storeName = ""
    var enabled = true
    var osmId: String? = nil
    var lat: Double? = nil
    var lng: Double? = nil
    var address: String? = nil
}

/// Laden aus der Umkreissuche (GET /stores/nearby).
struct NearbyStore: Codable, Identifiable, Hashable {
    var osmId: String
    var chain: String
    var name: String
    var address: String
    var lat: Double
    var lng: Double
    var distanceKm: Double
    var id: String { osmId }
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
    var radiusKm: Int?
    var lat: Double?
    var lng: Double?
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
    var storeRef: String?
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
    var id: Int?
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
    var radiusKm: Int?
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
    var toast: String?
    var detailDepth = 0  // > 0: Detailseite offen → Tab-Leiste ausblenden
    var extras: [ExtraItem] = Persist.load("extras") ?? [] { didSet { Persist.save(extras, "extras") } }
    var watchlist: Set<Int> = Persist.load("watchlist") ?? [] { didSet { Persist.save(watchlist, "watchlist") } }

    func flash(_ text: String) {
        withAnimation(Theme.spring) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if toast == text { withAnimation(Theme.spring) { toast = nil } }
        }
    }

    func isOnList(_ offer: OfferDTO) -> Bool {
        extras.contains { $0.offerId == offer.id } || shoppingItems.contains { $0.offer?.id == offer.id }
    }

    func addToList(_ offer: OfferDTO) {
        guard !isOnList(offer) else { return }
        extras.append(ExtraItem(name: offer.title, chain: offer.chain, offerId: offer.id, priceCents: offer.priceCents))
        flash("Zur Einkaufsliste hinzugefügt")
    }

    func toggleWatch(_ offer: OfferDTO) {
        if watchlist.remove(offer.id) == nil {
            watchlist.insert(offer.id)
            flash("Auf der Merkliste")
        }
    }

    let demo = Demo.screen != nil

    init(api: API) {
        self.api = api
        if demo, Demo.screen != "empty" {
            household = Demo.household; offers = Demo.offers; plan = Demo.plan
        }
    }

    /// Onboarding ist erst fertig, wenn alle Schritte durch sind (Haushalt entsteht schon in Schritt 1).
    // Bestehende Installationen (Token schon da, Flag noch nicht) gelten als fertig eingerichtet.
    var onboarded: Bool = UserDefaults.standard.object(forKey: "onboarded") as? Bool ?? (Keychain.read() != nil) {
        didSet { UserDefaults.standard.set(onboarded, forKey: "onboarded") }
    }

    var isOnboarded: Bool { demo ? Demo.screen != "onboarding" : api.token != nil && onboarded }

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

/// Lokale Einträge: selbst hinzugefügte Artikel und gemerkte Angebote.
/// shortcut: nur auf diesem Gerät gespeichert; gemeinsame Liste/Merkliste übers Backend in Phase 4/5.
struct ExtraItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var chain: String = ""
    var offerId: Int?
    var priceCents: Int?
}

extension AppStore {
    func nearbyStores(radiusKm: Int) async throws -> [NearbyStore] {
        try await api.request("GET", "/stores/nearby?radius_km=\(radiusKm)", timeout: 60)
    }

    func reroll(_ meal: MealDTO) async {
        guard let id = meal.id else { return }
        do {
            plan = try await api.request("POST", "/plans/current/entries/\(id)/reroll", timeout: 180)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setLocked(_ meal: MealDTO, _ locked: Bool) async {
        guard let id = meal.id else { return }
        struct Body: Encodable { var locked: Bool }
        plan = (try? await api.request("PATCH", "/plans/current/entries/\(id)", body: Body(locked: locked))) ?? plan
    }
}

/// Kleine Codable-Ablage in UserDefaults.
enum Persist {
    static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    static func save<T: Encodable>(_ value: T, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
