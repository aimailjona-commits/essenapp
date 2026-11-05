import Foundation
import Security

/// Anmeldung der App, die Teilen-Erweiterung und Widget mitbenutzen (E102).
public struct ShareSession: Codable, Sendable, Equatable {
    public var server: String
    public var token: String  // "" = nicht angemeldet

    public init(server: String, token: String) {
        self.server = server
        self.token = token
    }
}

/// Geteilter Inhalt: erster http(s)-Link + Text (Instagram gibt manchmal die Beschreibung mit).
public struct ShareInput: Sendable, Equatable {
    public var url: String
    public var text: String

    public init(url: String, text: String) {
        self.url = url
        self.text = text
    }

    public static func parse(url: String?, text: String?) -> ShareInput {
        let text = String((text ?? "").prefix(10_000))
        if let url, url.hasPrefix("http") { return ShareInput(url: url, text: text == url ? "" : text) }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let found = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap(\.url).first { u in u.scheme == "http" || u.scheme == "https" }
        return ShareInput(url: found?.absoluteString ?? "", text: text)
    }

    static func selfTest() {
        assert(parse(url: "https://www.instagram.com/reel/abc/", text: nil).url == "https://www.instagram.com/reel/abc/")
        let mixed = parse(url: nil, text: "Lecker! https://www.instagram.com/p/xyz/?igsh=1 #pasta")
        assert(mixed.url == "https://www.instagram.com/p/xyz/?igsh=1", "Link im Text nicht erkannt")
        assert(parse(url: nil, text: "kein Link").url.isEmpty)
    }
}

/// Geteilter Schlüsselbund über die App Group (E102): die App schreibt, Erweiterungen lesen.
public enum SharedLogin {
    // shortcut: Team-ID fest (xtool signiert die Gruppe um zu group.XTL-<Team>.…); bei Teamwechsel anpassen
    public static let group: String? = ["group.XTL-UW22N583GV.de.jsenf.essenapp", "group.de.jsenf.essenapp"]
        .first { id in FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil }

    private static func query(_ group: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "de.jsenf.essenapp.shared",
         kSecAttrAccessGroup as String: group]
    }

    public static func load() -> ShareSession? {
        guard let group else { return nil }
        var q = query(group)
        q[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(ShareSession.self, from: data)
    }

    /// Leeres Token = abgemeldet → Eintrag weg.
    public static func save(_ session: ShareSession) {
        guard let group else { return }
        SecItemDelete(query(group) as CFDictionary)
        guard !session.token.isEmpty else { return }
        var q = query(group)
        q[kSecValueData as String] = try? JSONEncoder().encode(session)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock  // Widget lädt auch bei gesperrtem iPhone
        SecItemAdd(q as CFDictionary, nil)
    }
}

/// = backend RecipeDetail (nur was das Ergebnis braucht).
struct ImportedRecipe: Decodable, Sendable, Equatable {
    struct Ingredient: Decodable, Sendable, Equatable {
        var name: String
        var estimated: Bool?
    }
    var id: Int
    var title: String
    var imageUrl: String
    var ingredients: [Ingredient]
    var steps: [String]
    var source: String
    var sourceAuthor: String
}

/// = backend PlanOut (Einträge für „Diese Woche einplanen“).
struct SharePlan: Decodable, Sendable {
    struct Entry: Decodable, Sendable, Equatable, Identifiable {
        struct Recipe: Decodable, Sendable, Equatable {
            var id: Int
            var title: String
            var imageUrl: String
        }
        var id: Int?
        var day: Int
        var mealType: String
        var locked: Bool
        var recipe: Recipe
    }
    var entries: [Entry]
}

struct ErrorDetail: Decodable { var detail: String }

struct ShareError: LocalizedError {
    let status: Int
    let detail: String
    var errorDescription: String? { detail }
}

enum ShareAPI {
    /// Anfrage mit JSON-Body; Fehler tragen den Status und den `detail`-Text des Backends.
    static func call<T: Decodable & Sendable>(_ method: String, _ server: String, _ path: String, token: String?,
                                              body: Data? = nil, timeout: TimeInterval = 20) async throws -> (T, Int) {
        let base = server.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + path), url.scheme == "http" || url.scheme == "https" else {
            throw ShareError(status: 0, detail: "Server-Adresse ungültig (z. B. http://192.168.0.10:8000)")
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        if let token, !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw ShareError(status: 0, detail: "Server nicht erreichbar – Adresse und WLAN prüfen.")
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let detail = (try? JSONDecoder().decode(ErrorDetail.self, from: data))?.detail
            throw ShareError(status: code, detail: detail ?? "Server-Fehler (\(code)).")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try decoder.decode(T.self, from: data), code)
    }

    static func json(_ object: [String: Any]) -> Data? { try? JSONSerialization.data(withJSONObject: object) }

    /// Relativer Bildpfad (/media/…) → volle Adresse auf dem Server.
    static func media(_ path: String, _ server: String) -> URL? {
        guard path.hasPrefix("/") else { return URL(string: path) }
        return URL(string: server.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path)
    }
}
