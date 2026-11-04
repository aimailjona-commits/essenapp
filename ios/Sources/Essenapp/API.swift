import Foundation
import Network
import SwiftUI
import Observation
import Security
import WidgetKit

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
    var stepImages: Bool? = nil  // Schalter „Schritt-Bilder erzeugen“ (9)
    var stepImagesAvailable: Bool? = nil  // FAL_KEY im Backend gesetzt → Schalter zeigen
    var variety: VarietyDTO? = nil  // Abwechslungsregeln (12)
    var storageSpace: String? = nil  // Vorratsplatz klein | mittel | gross (31)
    var productRules: [ProductRuleDTO]? = nil  // „Hafermilch statt Milch“ (19.2)
}

struct ProductRuleDTO: Codable, Hashable {
    var instead: String
    var use: String
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
    var subcategory: String? = nil  // feine Kategorie (19.1/19.4)
    var priceCents: Int
    var regularPriceCents: Int?
    var amount: Double?
    var unit: String
    var basePriceCents: Int?
    var validFrom: String
    var validTo: String
    var imageUrl: String
    var storeRef: String?
    var verdict: String? = nil  // Preisverlauf-Urteil (28): bestpreis | gut | normal | kein_echtes | zu_wenig_daten
    var bio: Bool? = nil  // Bio, Vegan, Nutri-Score (49): lieber kein Badge als ein falsches
    var vegan: Bool? = nil
    var vegetarian: Bool? = nil
    var nutriScore: String? = nil  // A–E
    var labelSources: [String]? = nil  // „Prospekttext“, „Open Food Facts (ODbL)“
    var offCode: String? = nil  // Open-Food-Facts-Barcode des sicheren Treffers
    var monthly: Bool? = nil  // dm/Rossmann-Monatsaktion (59)
    var bonusCents: Int? = nil  // Rewe-Bonus-Aktion (39): Badge „🎁 0,50 € Bonus“
}

enum APIError: LocalizedError {
    case noServer, http(Int), queued

    var errorDescription: String? {
        switch self {
        case .noServer: "Keine Server-Adresse eingestellt."
        case .queued: "Offline – wird später übertragen."
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
        didSet {
            Keychain.write(token)
            if token != oldValue { OfflineStore.clear(); pending = [] }  // anderer Haushalt: alter Cache und Warteschlange weg
        }
    }

    // MARK: Offline (66)

    /// Netz da (NWPathMonitor) und Server zuletzt erreichbar – sonst Banner, Cache und Warteschlange.
    var online: Bool { pathOK && reachable }
    private(set) var pathOK = Demo.screen != "offline"
    private(set) var reachable = true
    /// Änderungen (abhaken, hinzufügen, Vorrat), die beim nächsten Netz gesendet werden.
    private(set) var pending: [PendingRequest] = OfflineStore.load("pending") ?? [] {
        didSet { OfflineStore.save(pending, "pending") }
    }
    /// Für `RemoteImage`: ohne Netz Bilder direkt aus dem URLCache.
    static var offline = Demo.screen == "offline"
    private let monitor = NWPathMonitor()
    @ObservationIgnored private var flushing = false
    @ObservationIgnored private var sending: UUID?
    nonisolated static let tempBase = -1_000_000  // offline angelegte Einträge bekommen IDs darunter, bis der Server echte vergibt

    init() {
        guard Demo.screen == nil else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            Task { @MainActor in self?.setPath(ok) }
        }
        monitor.start(queue: .main)
    }

    private func setPath(_ ok: Bool) {
        pathOK = ok
        if ok { reachable = true }  // neuer Versuch; schlägt die nächste Anfrage fehl, wieder offline
        Self.offline = !online
    }

    private func setReachable(_ ok: Bool) {
        if reachable != ok { reachable = ok }
        Self.offline = !online
    }

    nonisolated static func isTemp(_ id: Int) -> Bool { id <= tempBase }

    func newTempId() -> Int {
        let id = (UserDefaults.standard.object(forKey: "offlineTempId") as? Int ?? Self.tempBase) - 1
        UserDefaults.standard.set(id, forKey: "offlineTempId")
        return id
    }

    /// Nur diese Änderungen dürfen offline warten: Listen-Artikel und Vorrat.
    nonisolated static func queueable(_ method: String, _ path: String) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        switch (method, parts.count) {
        case ("POST", 1): return parts[0] == "pantry"
        case ("POST", 3): return (parts[0] == "lists" && parts[2] == "items") || (parts[0] == "items" && parts[2] == "next-week")
        case ("PATCH", 2), ("DELETE", 2): return ["items", "pantry"].contains(parts[0]) && Int(parts[1]) != nil
        default: return false
        }
    }

    nonisolated static func ids(_ path: String) -> [Int] { path.split(separator: "/").compactMap { p in Int(p) } }

    /// Wert so in den Cache schreiben, wie ihn der Server unter `path` liefern würde (Offline-Änderungen).
    func store<T: Encodable>(_ value: T, _ path: String) {
        if let data = try? encoder.encode(value) { OfflineStore.write(data, path) }
    }

    func cached<T: Decodable>(_ path: String) -> T? {
        OfflineStore.read(path).flatMap { d in try? decoder.decode(T.self, from: d) }
    }

    private func enqueue(_ r: PendingRequest) throws -> Never {
        if r.method == "DELETE", let id = Self.ids(r.path).last, Self.isTemp(id) {
            pending.removeAll { p in p.tempId == id || Self.ids(p.path).contains(id) }  // offline angelegt und wieder gelöscht
        } else if r.method == "PATCH", let i = pending.lastIndex(where: { p in p.method == "PATCH" && p.path == r.path && p.id != sending }) {
            pending[i].body = PendingRequest.merge(pending[i].body, r.body)  // letzter Stand gewinnt pro Feld
        } else {
            pending.append(r)
        }
        throw APIError.queued
    }

    /// Warteschlange der Reihe nach senden. `keepChecked`: auf dem Server abgehakte Artikel – ein offline gesetztes
    /// „nicht abgehakt“ fällt dann weg (abgehakt bleibt abgehakt).
    func flush(keepChecked: Set<Int>) async {
        guard !flushing else { return }
        flushing = true
        defer { flushing = false; sending = nil }
        while let r = pending.first {
            if r.method == "PATCH", r.path.hasPrefix("/items/"), let id = Self.ids(r.path).first, keepChecked.contains(id),
               r.fields?["checked"] as? Bool == false {
                pending.removeAll { p in p.id == r.id }
                continue
            }
            sending = r.id
            do {
                let data = try await perform(r.method, r.path, r.body, timeout: 15)
                pending.removeAll { p in p.id == r.id }
                if let temp = r.tempId, let real = PendingRequest.createdId(data) {
                    for i in pending.indices {  // spätere Änderungen am selben Eintrag zeigen jetzt auf die echte ID
                        pending[i].path = pending[i].path.split(separator: "/", omittingEmptySubsequences: false)
                            .map { p in p == "\(temp)" ? "\(real)" : String(p) }.joined(separator: "/")
                    }
                }
            } catch is URLError {
                return  // weiter beim nächsten Netz
            } catch {
                pending.removeAll { p in p.id == r.id }  // z. B. 404: Artikel inzwischen gelöscht – verwerfen
            }
        }
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

    /// `tempId`: offline angelegter Eintrag (POST), dessen echte ID nach dem Senden die späteren Änderungen bekommen.
    /// `cache: false`: GET ohne Cache (Abgleich vor dem Senden der Warteschlange).
    func request<T: Decodable>(_ method: String, _ path: String, body: (some Encodable)? = nil as String?,
                               timeout: TimeInterval = 15, tempId: Int? = nil, cache: Bool = true) async throws -> T {
        try decoder.decode(T.self, from: try await send(method, path, body: body, timeout: timeout, tempId: tempId, cache: cache))
    }

    /// Wie `request`, aber ohne Dekodieren (z. B. 204-Antworten). GET: Antwort kommt in den Offline-Cache, ohne Netz
    /// liefert der Cache. Listen-/Vorrats-Änderungen ohne Netz → Warteschlange (`APIError.queued`).
    @discardableResult
    func send(_ method: String, _ path: String, body: (some Encodable)? = nil as String?,
              timeout: TimeInterval = 15, tempId: Int? = nil, cache: Bool = true) async throws -> Data {
        let data = try body.map { b in try encoder.encode(b) }
        if method == "GET", cache, path != "/health" {
            if pathOK {
                do {
                    let fresh = try await perform(method, path, nil, timeout: timeout)
                    OfflineStore.write(fresh, path)
                    return fresh
                } catch let e as URLError {
                    guard let old = OfflineStore.read(path) else { throw e }
                    return old
                }
            }
            guard let old = OfflineStore.read(path) else { throw URLError(.notConnectedToInternet) }
            return old
        }
        let queueable = Self.queueable(method, path)
        let request = PendingRequest(method: method, path: path, body: data, tempId: tempId)
        if queueable, !online || Self.ids(path).contains(where: Self.isTemp) || flushing {
            try enqueue(request)  // Reihenfolge bleibt erhalten, solange gesendet wird
        }
        do {
            return try await perform(method, path, data, timeout: timeout)
        } catch let e as URLError {
            guard queueable else { throw e }
            try enqueue(request)
        }
    }

    private func perform(_ method: String, _ path: String, _ body: Data?, timeout: TimeInterval) async throws -> Data {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces) + path), !baseURL.isEmpty else { throw APIError.noServer }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch let e as URLError {
            if e.code != .cancelled { setReachable(false) }
            throw e
        }
        setReachable(true)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw APIError.http(code) }
        return data
    }

    /// Multipart-Upload (Kühlschrank-Fotos „files“, Coupon-Foto „file“): JPEGs + Formularfelder; `progress` 0–1 beim Senden.
    func upload<T: Decodable>(_ path: String, files: [Data], fields: [String: String], field: String = "files", timeout: TimeInterval = 120,
                              progress: @escaping @Sendable (Double) -> Void) async throws -> T {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces) + path), !baseURL.isEmpty else { throw APIError.noServer }
        let boundary = "essenapp-\(UUID().uuidString)"
        var body = Data()
        for (key, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n".utf8))
        }
        for (i, file) in files.enumerated() {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field)\"; filename=\"foto\(i + 1).jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
            body.append(file)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.upload(for: req, from: body, delegate: UploadProgress(report: progress))
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw APIError.http(code) }
        return try decoder.decode(T.self, from: data)
    }
}

/// Wartende Änderung (Offline-Modus 66).
struct PendingRequest: Codable, Identifiable {
    var id = UUID()
    var method: String
    var path: String
    var body: Data?
    var tempId: Int?

    var fields: [String: Any]? { body.flatMap { d in try? JSONSerialization.jsonObject(with: d) as? [String: Any] } }

    static func merge(_ old: Data?, _ new: Data?) -> Data? {
        guard let o = old.flatMap({ d in try? JSONSerialization.jsonObject(with: d) as? [String: Any] }),
              let n = new.flatMap({ d in try? JSONSerialization.jsonObject(with: d) as? [String: Any] }) else { return new }
        return try? JSONSerialization.data(withJSONObject: o.merging(n) { _, b in b })
    }

    /// ID aus der Antwort eines POST (neuer Artikel / Vorratseintrag).
    static func createdId(_ data: Data) -> Int? {
        struct Created: Decodable { var id: Int }
        return (try? JSONDecoder().decode(Created.self, from: data))?.id
    }

    static func selfTest() {
        let merged = merge(Data(#"{"checked":true,"amount":2}"#.utf8), Data(#"{"checked":false}"#.utf8))
        let m = merged.flatMap { d in try? JSONSerialization.jsonObject(with: d) as? [String: Any] }
        assert(m?["checked"] as? Bool == false && m?["amount"] as? Int == 2, "Warteschlange: letzter Stand pro Feld")
        assert(API.queueable("PATCH", "/items/5") && API.queueable("POST", "/lists/3/items") && API.queueable("POST", "/pantry"))
        assert(!API.queueable("POST", "/pantry/basics/3/empty") && !API.queueable("POST", "/items/5/to-pantry"))
        assert(API.queueable("POST", "/items/5/next-week") && !API.queueable("POST", "/lists/3/assign"))
        assert(createdId(Data(#"{"id":42,"name":"Milch"}"#.utf8)) == 42)
    }
}

/// Letzte Server-Antworten und Warteschlange als JSON-Dateien (E25: kein SwiftData). Application Support statt Caches,
/// damit iOS die Warteschlange nicht wegräumt.
enum OfflineStore {
    static let dir: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "offline", directoryHint: .isDirectory)

    static func file(_ key: String) -> URL { dir.appending(path: key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key) }
    static func read(_ key: String) -> Data? { try? Data(contentsOf: file(key)) }

    static func write(_ data: Data, _ key: String) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: file(key), options: .atomic)
    }

    static func load<T: Decodable>(_ key: String) -> T? { read(key).flatMap { d in try? JSONDecoder().decode(T.self, from: d) } }
    static func save<T: Encodable>(_ value: T, _ key: String) { if let d = try? JSONEncoder().encode(value) { write(d, key) } }
    static func clear() { try? FileManager.default.removeItem(at: dir) }
}

/// Meldet den Sende-Fortschritt eines Uploads.
final class UploadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let report: @Sendable (Double) -> Void

    init(report: @escaping @Sendable (Double) -> Void) { self.report = report }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        report(Double(totalBytesSent) / Double(max(totalBytesExpectedToSend, 1)))
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
    var inPantry: Bool?  // fehlt bei eigenen Rezepten (nur Name, Menge, Einheit)
    var packAmount: Double?
    var packPriceCents: Int?
    var estimated: Bool? = nil  // Import (5): Menge von der KI geschätzt
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
    var stepImages: [String]? = nil  // Schritt-Bilder (Feature 9), leer = keine Bildfläche im Kochmodus
    var source = "ai"  // ai | user | instagram | web | shared
    var sourceUrl = ""
    var sourceAuthor = ""
    var tags: [String] = []
    var favorite = false
    var nutrition: NutritionDTO? = nil  // pro Portion; null = Berechnung läuft noch
    var composition: [CompositionItem]? = nil  // Blüten-Diagramm, null wie nutrition
    // nur GET /recipes/{id} (RecipeDetail)
    var avgStars: Double? = nil
    var lastCooked: String? = nil
    var costPerServingCents: Int? = nil
    var offerShare: Double? = nil
    var ratings: [RatingDTO]? = nil
}

/// Pro Portion (1 Portion = Esser mit 2000 kcal/Tag); pro Person × Portionsfaktor.
struct NutritionDTO: Codable, Hashable {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
}

struct CompositionItem: Codable, Hashable {
    var name: String
    var grams: Double
    var share: Double  // 0–1, Summe 1
}

struct RatingDTO: Codable, Hashable, Identifiable {
    var id: Int
    var memberId: Int
    var memberName: String
    var stars: Int
    var again: String
    var note: String
    var cookedAt: String
}

/// = backend RecipeCard (Meine Rezepte).
struct RecipeCard: Codable, Hashable, Identifiable {
    var id: Int
    var title: String
    var imageUrl: String
    var cuisine: String
    var mealType: String
    var prepMinutes: Int
    var servings: Int
    var source: String
    var sourceAuthor: String
    var favorite: Bool
    var avgStars: Double?
    var lastCooked: String?
    var costPerServingCents: Int
    var offerShare: Double  // Badge „im Angebot“ ab 0,4
}

/// = backend PlanNutritionOut (Tagesringe, Wochenschnitt).
struct PlanNutritionDTO: Codable, Hashable {
    struct Member: Codable, Hashable, Identifiable {
        var memberId: Int
        var name: String
        var emoji: String
        var kcalGoal: Int
        var proteinGoal: Int
        var avgKcal: Double
        var avgProtein: Double
        var id: Int { memberId }
    }
    struct MemberDay: Codable, Hashable {
        var memberId: Int
        var kcal: Double
        var protein: Double
        var carbs: Double
        var fat: Double
        var fiber: Double
        var complete: Bool  // false = ein Gericht noch ohne Zuordnung
    }
    struct Day: Codable, Hashable {
        var day: Int
        var members: [MemberDay]
    }
    var members: [Member]
    var days: [Day]
}

/// Fotos eigener Rezepte kommen relativ (/media/…) – hier zentral um die Server-Adresse ergänzt.
func mediaURL(_ path: String) -> URL? {
    guard path.hasPrefix("/") else { return URL(string: path) }
    return URL(string: (UserDefaults.standard.string(forKey: "backendURL") ?? "").trimmingCharacters(in: .whitespaces) + path)
}

struct MealDTO: Codable, Hashable {
    var id: Int?
    var day: Int
    var mealType: String
    var costCents: Int
    var locked: Bool
    var recipe: RecipeDTO
    var portions: [PortionDTO] = []  // Esser dieses Gerichts (48)
    var portionsTotal: Double = 0  // Rezeptmengen gelten für so viele Portionen; 0 = alter Plan → recipe.servings
    var scale: Double = 1  // Menge im Plan = Rezeptmenge × scale (eingesetzte Rezepte)
    var guests: Int? = nil  // Gäste (15), in portionsTotal enthalten
    var rests: [RestBadgeDTO]? = nil  // „♻︎ Rest von Mo“ (19)

    var basePortions: Double { portionsTotal > 0 ? portionsTotal : Double(max(recipe.servings, 1)) }
}

struct PortionDTO: Codable, Hashable {
    var memberId: Int
    var factor: Double
}

struct PlanDTO: Codable {
    var id: Int
    var week: String
    var totalCents: Int
    var savedCents: Int
    var entries: [MealDTO]
    var variety: VarietyCheckDTO? = nil  // Chip „✓ Abwechslung“ / „⚠ 2× Pasta“ (12)
    var leftovers: LeftoversDTO? = nil  // Reste-Karte im Plan-Kopf (19)
}

/// Anzeige-Namen; Schlüssel wie im Backend.
enum Labels {
    static let chains: [(key: String, name: String, drugstore: Bool)] = [
        ("rewe", "Rewe", false), ("aldi_sued", "Aldi Süd", false), ("aldi_nord", "Aldi Nord", false), ("lidl", "Lidl", false),
        ("edeka", "Edeka", false), ("kaufland", "Kaufland", false), ("penny", "Penny", false), ("netto_md", "Netto", false),
        ("dm", "dm", true), ("rossmann", "Rossmann", true),
    ]
    static func chain(_ key: String) -> String { chains.first { $0.key == key }?.name ?? key }

    /// Offizielle Logos als PNG-Thumbnails von Wikimedia Commons (geprüfte URLs, nur verlinkt, E39).
    static let logos: [String: String] = [
        "rewe": "https://upload.wikimedia.org/wikipedia/commons/thumb/4/4c/Logo_REWE.svg/250px-Logo_REWE.svg.png",
        "aldi_sued": "https://upload.wikimedia.org/wikipedia/commons/thumb/e/e5/Aldi_S%C3%BCd_2017_logo.svg/250px-Aldi_S%C3%BCd_2017_logo.svg.png",
        "aldi_nord": "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f0/AldiNord-WorldwideLogo.svg/250px-AldiNord-WorldwideLogo.svg.png",
        "lidl": "https://upload.wikimedia.org/wikipedia/commons/thumb/9/91/Lidl-Logo.svg/250px-Lidl-Logo.svg.png",
        "edeka": "https://upload.wikimedia.org/wikipedia/commons/thumb/c/cf/Edeka_Logo_Aktuell.svg/250px-Edeka_Logo_Aktuell.svg.png",
        "kaufland": "https://upload.wikimedia.org/wikipedia/commons/thumb/4/44/Kaufland_201x_logo.svg/250px-Kaufland_201x_logo.svg.png",
        "penny": "https://upload.wikimedia.org/wikipedia/commons/thumb/8/8e/Penny-Logo.svg/250px-Penny-Logo.svg.png",
        "netto_md": "https://upload.wikimedia.org/wikipedia/commons/thumb/f/f1/Netto_Marken-Discount_2018_logo.svg/250px-Netto_Marken-Discount_2018_logo.svg.png",
        "dm": "https://upload.wikimedia.org/wikipedia/commons/thumb/2/2c/Dm-drogerie-Logo.svg/250px-Dm-drogerie-Logo.svg.png",
        "rossmann": "https://upload.wikimedia.org/wikipedia/commons/thumb/7/7c/Logo_rossmann_2024.svg/250px-Logo_rossmann_2024.svg.png",
    ]
    static func logoURL(_ key: String) -> URL? { logos[key].flatMap(URL.init(string:)) }

    /// Wählbare Mahlzeiten (Snack: 23c); Lunchbox (24) und Vorspeise (25) legt der Planer selbst an.
    static let mealTypes = [("fruehstueck", "Frühstück"), ("mittag", "Mittag"), ("snack", "Snack"), ("abend", "Abend"), ("dessert", "Dessert")]
    static let slotOrder = ["fruehstueck", "lunchbox", "mittag", "snack", "vorspeise", "abend", "dessert"]  // = Backend SLOT_ORDER
    static func meal(_ key: String) -> String {
        (mealTypes + [("lunchbox", "Lunchbox"), ("vorspeise", "Vorspeise")]).first { $0.0 == key }?.1 ?? key
    }

    static let units = [("g", "g"), ("kg", "kg"), ("ml", "ml"), ("l", "l"), ("stk", "Stück"), ("el", "EL"), ("tl", "TL"), ("prise", "Prise")]
    static func unit(_ key: String) -> String { units.first { $0.0 == key }?.1 ?? key }
    static let again = [("bald", "Bald"), ("irgendwann", "Irgendwann"), ("nie", "Nie")]

    static let days = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    static let dayNames = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
    static let diets = [("alles", "Alles"), ("vegetarisch", "Vegetarisch"), ("vegan", "Vegan"), ("pescetarisch", "Pescetarisch"), ("halal", "Halal")]
    static let allergies = ["Gluten", "Laktose", "Nüsse", "Erdnüsse", "Ei", "Soja", "Fisch", "Sellerie"]
    static let rerollDirections = [("schneller", "Schneller"), ("guenstiger", "Günstiger"), ("ohne_fleisch", "Ohne Fleisch"),
                                   ("leichter", "Leichter"), ("anders", "Ganz andere Küche")]
    static let goals = [("ausgewogen", "Ausgewogen", "Alle Nährstoffe abdecken"), ("proteinreich", "Proteinreich", "Viel Eiweiß"),
                        ("kalorienarm", "Kalorienarm", "Leichter essen")]
    static let cuisines = ["Indisch", "Asiatisch", "Italienisch", "Deutsch", "Mexikanisch", "Orientalisch"]
    static let categories = [("obst_gemuese", "🥦 Obst & Gemüse"), ("fleisch_fisch", "🥩 Fleisch & Fisch"), ("kuehlung", "🧀 Kühlung"),
                             ("vorrat", "🥫 Vorrat"), ("getraenke", "🥤 Getränke"), ("drogerie", "🧴 Drogerie"), ("haushalt", "🧽 Haushalt")]
    /// Feine Kategorien (Backend kaufda.SUBCATEGORIES) für die zweite Chip-Reihe im Angebote-Screen (19.4).
    static let subcategories = [("obst", "Obst"), ("gemuese", "Gemüse"), ("fleisch", "Fleisch"), ("wurst", "Wurst"), ("fisch", "Fisch"),
                                ("molkerei", "Milch & Butter"), ("joghurt", "Joghurt & Quark"), ("kaese", "Käse"), ("tiefkuehl", "Tiefkühl"),
                                ("brot", "Brot"), ("nudeln_reis", "Nudeln & Reis"), ("konserven", "Konserven & Öl"), ("saucen", "Saucen"),
                                ("backen", "Backen"), ("fruehstueck", "Frühstück"), ("kaffee_tee", "Kaffee & Tee"), ("suesses", "Süßes"),
                                ("snacks", "Snacks & Nüsse")]
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
    var maxCookMinutes: Int?
    var radiusKm: Int?
    var stores: [StoreDTO]?
    var stepImages: Bool?
    var variety: VarietyDTO?
    var storageSpace: String?
    var productRules: [ProductRuleDTO]?
}

/// App-Zustand: lädt und hält Haushalt, Angebote und Plan.
@MainActor @Observable
final class AppStore {
    var tabBarHiders = 0  // > 0: Detail-Screen mit Summen-Leiste ist offen (v3)
    let api: API
    var household: HouseholdDTO? {
        didSet { if !demo { StoreReminder.shared.update(household) } }  // Standort-Erinnerung (36) folgt den gewählten Läden
    }
    var offers: [OfferDTO] = []
    var nextOffers: [OfferDTO] = []  // Vorschau nächste Woche (30)
    var watches: [WatchDTO] = []  // Merkliste + Preisalarme (27/40/58)
    var barcode = false  // Barcode-Scanner (27): aus Schnell-Aktion und Merkliste
    var budgetIdeas: (key: String, ideas: [BudgetIdeaDTO])?  // Budget-Rest-Ideen (43), je Plan-Stand einmal laden
    var plan: PlanDTO? {  // Widget „Heute“ lädt selbst vom Server (65) – nach einer Planänderung gleich neu
        didSet { if !demo, plan?.entries.map(\.recipe.id) != oldValue?.entries.map(\.recipe.id) { WidgetCenter.shared.reloadAllTimelines() } }
    }
    var error: String?
    var generating = false
    var toast: String?
    var toastAction: (title: String, run: () -> Void)?
    var profile: ProfileDTO?  // angemeldetes Mitglied (48)
    var profiles: [ProfileDTO] = []
    var pantry: [PantryDTO] = [] {
        didSet { if !demo { api.store(pantry, "/pantry") } }
    }
    var lists: [ListSummaryDTO] = []
    var householdList: ListDTO? {  // Änderungen gehen auch in den Offline-Cache (66)
        didSet {
            guard !demo else { return }
            if let l = householdList { api.store(l, "/lists/\(l.id)") }
            LiveShop.sync(householdList)  // Live-Aktivität folgt jedem Haken (37)
        }
    }
    var nutrition: PlanNutritionDTO?  // Tagesringe (2)
    var recipesVersion = 0  // +1 nach Anlegen/Ändern/Bewerten → Listen und Detail laden neu
    var recipeFilter: String?  // Start-Karte → Rezepte-Tab mit diesem Filter
    var scanning = false  // Kühlschrank-Foto (69): Sheet aus Schnell-Aktion, Start-Karte, Vorrat
    var generatorSpecial: String?  // Start-Banner (25) → Plan-Generator mit dieser Special-Vorlage
    var coupons: [CouponDTO] = []  // Wallet (38)
    var bonusAccounts: [BonusAccountDTO] = []  // Payback / Rewe Bonus (38b)
    var checkoutCoupon: Int? = Demo.screen == "coupon" ? 1 : nil  // Kassen-Vollbild (Wallet, Badge, Push essenapp://coupon/<id>)
    var review: String? = Demo.screen == "review" ? "" : nil  // Wochenrückblick-Story: Woche, "" = aktuelle (55)
    var newAchievements: [AchievementDTO] = Demo.screen == "unlock" ? Demo.unlocked : []  // Vollbild-Moment (54)

    /// Toast oben, optional mit Aktions-Knopf (bleibt dann länger stehen).
    func flash(_ text: String, action: (title: String, run: () -> Void)? = nil) {
        withAnimation(Theme.spring) { toast = text; toastAction = action }
        let seconds = action == nil ? 1.8 : 4.5
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if toast == text { withAnimation(Theme.spring) { toast = nil; toastAction = nil } }
        }
    }

    func isOnList(_ offer: OfferDTO) -> Bool {
        householdList?.items.contains { $0.offerId == offer.id } ?? false
    }

    func addToList(_ offer: OfferDTO, count: Int = 1) {
        guard !isOnList(offer), let list = householdList else { return }
        let later = offer.startsLater  // Vorschau-Angebot (30) → Gruppe „Nächste Woche“
        let amount: Double? = count > 1 ? Double(count) : nil  // Menge aus dem Angebotsdetail (v3)
        // sofort anzeigen, Server bestätigt im Hintergrund
        householdList?.items.append(ListItemDTO(id: -offer.id, name: offer.title, amount: amount, unit: amount == nil ? "" : "stk", chain: offer.chain,
                                                offerId: offer.id, checked: false, addedBy: "", checkedBy: "", source: "manual",
                                                nextWeek: later))
        flash(later ? "Für nächste Woche auf der Liste" : "Zur Einkaufsliste hinzugefügt")
        Task { await addItem(name: offer.title, amount: amount, unit: amount == nil ? "" : "stk", chain: offer.chain, offerId: offer.id,
                             nextWeek: later, to: list.id) }
    }

    let demo = Demo.screen != nil

    /// Eine Instanz für Oberfläche und App Intents (Abhaken aus der Live-Aktivität startet die App ohne Fenster).
    static let shared = AppStore(api: API())

    /// Abhaken aus der Live-Aktivität (37): wie in der App (sofort lokal, Server bzw. Offline-Warteschlange);
    /// `householdList.didSet` aktualisiert danach die Aktivität.
    func checkFromActivity(_ id: Int) async {
        if householdList == nil { await loadLists() }
        if let item = householdList?.items.first(where: { i in i.id == id }), !item.checked { await toggle(item) }
    }

    init(api: API) {
        self.api = api
        if demo, Demo.screen != "empty" {
            household = Demo.household; offers = Demo.offers; nextOffers = Demo.nextOffers; watches = Demo.watches; plan = Demo.plan
            barcode = Demo.screen == "scanner"
            householdList = Demo.householdList; lists = Demo.lists
            profiles = Demo.profiles; profile = Demo.profiles.first; pantry = Demo.pantry; nutrition = Demo.nutrition
        }
    }

    /// Onboarding ist erst fertig, wenn alle Schritte durch sind (Haushalt entsteht schon in Schritt 1).
    // Bestehende Installationen (Token schon da, Flag noch nicht) gelten als fertig eingerichtet.
    var onboarded: Bool = UserDefaults.standard.object(forKey: "onboarded") as? Bool ?? (Keychain.read() != nil) {
        didSet {
            UserDefaults.standard.set(onboarded, forKey: "onboarded")
            if onboarded { askPush = true }  // direkt nach dem Onboarding einmal nach Mitteilungen fragen
        }
    }
    var askPush = false

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
        await syncPending()
        do {
            household = try await api.request("GET", "/household")
            offers = try await api.request("GET", "/offers")
            nextOffers = (try? await api.request("GET", "/offers?week=next")) ?? nextOffers
            plan = try? await api.request("GET", "/plans/current")
            await loadWatch()
            await loadLists()
            await loadProfiles()
            try? await loadPantry()
            error = nil
            await loadNutrition()
            await loadAchievements()  // schaltet Neues frei → Vollbild-Moment
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
            nextOffers = (try? await api.request("GET", "/offers?week=next")) ?? nextOffers
        } catch {
            self.error = error.localizedDescription
        }
    }

    func generatePlan(_ options: PlanOptions? = nil) async {
        generating = true
        defer { generating = false }
        do {
            let had = plan != nil
            plan = try await api.request("POST", "/plans", body: options, timeout: 300)  // KI-Plan dauert bis ~2 min
            await loadLists()  // Backend übernimmt die Zutaten in die Haushaltsliste
            error = nil
            if had { flash("Neuer Plan erstellt", action: ("Rückgängig", { Task { await self.undoPlan() } })) }  // 19.3
            await loadNutrition()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Heutiger Wochentag, 0 = Montag (Demo: Dienstag).
    var today: Int { demo ? 1 : (Calendar(identifier: .iso8601).component(.weekday, from: .now) + 5) % 7 }

    /// Gericht für heute (Hauptgericht des heutigen Wochentags, Mittag bevorzugt).
    var todayMeal: MealDTO? {
        let meals = plan?.entries.filter { $0.day == today } ?? []
        return meals.first { $0.mealType == "mittag" } ?? meals.first { $0.mealType == "abend" } ?? meals.first
    }
}

extension AppStore {
    /// Offline-Änderungen senden, sobald wieder Netz da ist (66). Auf dem Server abgehakte Artikel bleiben abgehakt.
    func syncPending() async {
        guard !demo, !api.pending.isEmpty, api.pathOK else { return }
        var checked = Set<Int>()
        do {
            let all: [ListSummaryDTO] = try await api.request("GET", "/lists", cache: false)
            for l in all {
                let list: ListDTO = try await api.request("GET", "/lists/\(l.id)", cache: false)
                checked.formUnion(list.items.filter(\.checked).map(\.id))
            }
        } catch {
            return  // Server noch nicht erreichbar
        }
        await api.flush(keepChecked: checked)
    }

    /// Offline-Änderung an einer Liste: im Speicher und im Cache, damit sie Neuladen und Neustart übersteht (66).
    func editList(_ id: Int, _ edit: (inout ListDTO) -> Void) {
        if householdList?.id == id {
            edit(&householdList!)
        } else if var l: ListDTO = api.cached("/lists/\(id)") {
            edit(&l)
            api.store(l, "/lists/\(id)")
        }
    }

    func nearbyStores(radiusKm: Int) async throws -> [NearbyStore] {
        try await api.request("GET", "/stores/nearby?radius_km=\(radiusKm)", timeout: 60)
    }

    /// Neu würfeln; `maxCost`: „günstigere Alternative“ mit Kostengrenze (43); `direction`/`wish`: Richtung (19.3).
    func reroll(_ meal: MealDTO, maxCost: Int? = nil, direction: String? = nil, wish: String = "") async {
        guard let id = meal.id else { return }
        struct Body: Encodable { var maxCostCents: Int?; var direction: String?; var wish: String }
        do {
            plan = try await api.request("POST", "/plans/current/entries/\(id)/reroll",
                                         body: Body(maxCostCents: maxCost, direction: direction, wish: wish), timeout: 180)
            let title = plan?.entries.first { $0.id == id }?.recipe.title ?? "Neues Gericht"
            flash(title, action: ("Rückgängig", { Task { await self.undo(entry: id) } }))
            await loadNutrition()  // Tagesringe reagieren aufs Würfeln
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Gericht vor dem letzten Würfeln/Ersetzen zurück (19.3).
    func undo(entry id: Int) async {
        do {
            plan = try await api.request("POST", "/plans/current/entries/\(id)/undo")
            await loadLists()
            await loadNutrition()
        } catch {
            flash("Rückgängig nicht möglich: \(error.localizedDescription)")
        }
    }

    /// Vorigen Plan wieder aktiv machen (19.3); der neue bleibt gespeichert.
    func undoPlan() async {
        do {
            plan = try await api.request("POST", "/plans/current/undo")
            await loadLists()
            await loadNutrition()
            flash("Voriger Plan ist wieder aktiv")
        } catch {
            flash("Rückgängig nicht möglich: \(error.localizedDescription)")
        }
    }

    /// „Mag ich nicht“ (19.2): Zutat in die Abneigungen; die KI plant sie nicht mehr ein, der Code prüft das nach.
    func dislike(_ ingredient: String) async {
        guard let h = household, !h.excludedIngredients.contains(where: { $0.caseInsensitiveCompare(ingredient) == .orderedSame }) else { return }
        do {
            try await save(HouseholdPatch(excludedIngredients: h.excludedIngredients + [ingredient]))
            flash("„\(ingredient)“ kommt nicht mehr in deine Pläne")
        } catch {
            flash("Nicht gespeichert: \(error.localizedDescription)")
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
