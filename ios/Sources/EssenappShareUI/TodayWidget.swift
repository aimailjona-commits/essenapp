import Foundation
import Security
import SwiftUI
import UIKit
import WidgetKit

// Widget „Heute“ (Feature 65). Daten, Auswahl und Ansichten liegen hier, damit die App sie für die Demo-Screenshots
// rendern kann; die Erweiterung `EssenappWidget` hat nur Bundle, Konfiguration und Timeline (E83).

/// Hauptgericht aus `GET /plans/current` (nur was das Widget zeigt).
public struct TodayDish: Codable, Sendable, Hashable {
    public var recipeId: Int
    public var title: String
    public var mealType: String
    public var day: Int  // 0 = Montag
    public var minutes: Int
    public var imageUrl: String

    public init(recipeId: Int, title: String, mealType: String, day: Int, minutes: Int, imageUrl: String) {
        self.recipeId = recipeId; self.title = title; self.mealType = mealType; self.day = day; self.minutes = minutes; self.imageUrl = imageUrl
    }
}

/// Letzter Server-Stand: Gerichte der Woche + offene Artikel der Haushaltsliste.
public struct TodayData: Codable, Sendable {
    public var week: String  // „2026-W45“
    public var dishes: [TodayDish]
    public var openCount: Int
    public var openNames: [String]
    public var updated: Date

    public init(week: String, dishes: [TodayDish], openCount: Int, openNames: [String], updated: Date) {
        self.week = week; self.dishes = dishes; self.openCount = openCount; self.openNames = openNames; self.updated = updated
    }

    // shortcut: feste Uhrzeiten, ab denen eine Mahlzeit vorbei ist; Mahlzeit-Zeiten aus dem Haushalt, sobald es sie gibt
    static let ends = ["fruehstueck": 10, "lunchbox": 12, "mittag": 14, "snack": 17, "vorspeise": 21, "abend": 21, "dessert": 22]
    static let slots = ["fruehstueck", "lunchbox", "mittag", "snack", "vorspeise", "abend", "dessert"]  // = Labels.slotOrder

    static func week(_ date: Date) -> String {
        let cal = Calendar(identifier: .iso8601)
        let w = cal.component(.weekOfYear, from: date)
        return "\(cal.component(.yearForWeekOfYear, from: date))-W\(w < 10 ? "0" : "")\(w)"
    }

    static func weekday(_ date: Date) -> Int { (Calendar(identifier: .iso8601).component(.weekday, from: date) + 5) % 7 }

    /// Aktuelles bzw. nächstes Hauptgericht (Mittag/Abend, sonst alle) und das danach – nur aus der Woche des Plans.
    public func pick(at date: Date) -> (hero: TodayDish?, next: TodayDish?) {
        guard week == Self.week(date) else { return (nil, nil) }
        let main = dishes.filter { d in d.mealType == "mittag" || d.mealType == "abend" }
        let today = Self.weekday(date), hour = Calendar(identifier: .iso8601).component(.hour, from: date)
        let left = (main.isEmpty ? dishes : main)
            .filter { d in d.day > today || (d.day == today && (Self.ends[d.mealType] ?? 21) > hour) }
            .sorted { a, b in (a.day, Self.slots.firstIndex(of: a.mealType) ?? 9) < (b.day, Self.slots.firstIndex(of: b.mealType) ?? 9) }
        return (left.first, left.dropFirst().first)
    }

    /// Zeitpunkte, an denen das Widget ein anderes Gericht zeigt (Mahlzeitwechsel, Mitternacht) in den nächsten 24 h.
    public static func switches(after date: Date) -> [Date] {
        let cal = Calendar(identifier: .iso8601)
        let midnight = cal.startOfDay(for: date)
        return [0, 1].flatMap { d in [0, 14, 21].compactMap { h in cal.date(byAdding: .hour, value: d * 24 + h, to: midnight) } }
            .filter { t in t > date && t < date.addingTimeInterval(86_400) }
    }

    /// „Heute“, „Morgen“ oder Wochentag + Mahlzeit.
    public static func label(_ dish: TodayDish, at date: Date) -> String {
        let today = weekday(date)
        let day = dish.day == today ? "Heute" : dish.day == today + 1 ? "Morgen" : ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"][dish.day]
        return "\(day) · \(meals[dish.mealType] ?? dish.mealType)"
    }

    static let meals = ["fruehstueck": "Frühstück", "lunchbox": "Lunchbox", "mittag": "Mittag", "snack": "Snack", "vorspeise": "Vorspeise",
                        "abend": "Abend", "dessert": "Dessert"]

    public static func selfTest() {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let tue = cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9))!  // Di, KW 45
        let dish = { (day: Int, meal: String, title: String) in TodayDish(recipeId: day, title: title, mealType: meal, day: day, minutes: 30, imageUrl: "") }
        let data = TodayData(week: "2026-W45", dishes: [dish(1, "abend", "B"), dish(1, "mittag", "A"), dish(1, "fruehstueck", "F"), dish(2, "mittag", "C")],
                             openCount: 0, openNames: [], updated: tue)
        assert(data.pick(at: tue).hero?.title == "A" && data.pick(at: tue).next?.title == "B", "Widget: Mittag vor Abend")
        assert(data.pick(at: tue.addingTimeInterval(6 * 3600)).hero?.title == "B", "Widget: ab 14 Uhr Abend")
        assert(data.pick(at: tue.addingTimeInterval(13 * 3600)).hero?.title == "C", "Widget: ab 21 Uhr morgen")
        assert(data.pick(at: tue.addingTimeInterval(7 * 86_400)).hero == nil, "Widget: alter Plan zeigt nichts")
        assert(switches(after: tue).count == 3, "Widget: 14, 21, 0 Uhr")
        assert(label(data.dishes[3], at: tue) == "Morgen · Mittag")
    }
}

/// Ein Zeitpunkt der Timeline. `stale` = letzter Stand, weil der Server gerade nicht antwortet.
public struct TodayEntry: TimelineEntry, Sendable {
    public enum State: Sendable, Equatable { case unpaired(String?), ok, failed(String) }

    public var date: Date
    public var state: State
    public var data: TodayData?
    public var images: [Int: Data]  // recipeId → verkleinertes JPEG
    public var stale = false

    public init(date: Date, state: State, data: TodayData?, images: [Int: Data] = [:], stale: Bool = false) {
        self.date = date; self.state = state; self.data = data; self.images = images; self.stale = stale
    }

    /// Demo und Platzhalter: heute 9:41 (wie die Statusleiste der CI-Screenshots), damit immer das Mittagessen oben steht.
    public static let demo = TodayEntry(date: Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: .now) ?? .now, state: .ok, data: TodayData(
        week: TodayData.week(.now),
        dishes: [TodayDish(recipeId: 1, title: "Chicken Tikka Masala", mealType: "mittag", day: TodayData.weekday(.now), minutes: 35, imageUrl: ""),
                 TodayDish(recipeId: 2, title: "Linsen-Dal mit Spinat", mealType: "abend", day: TodayData.weekday(.now), minutes: 25, imageUrl: "")],
        openCount: 6, openNames: ["Hähnchenbrust", "Feta", "Lachsfilet"], updated: .now))
}

// MARK: - Laden (läuft in der Erweiterung)

/// Holt Plan + Liste mit dem eigenen Token der Erweiterung. Ein Actor, damit zwei Widgets einen Code nicht doppelt einlösen.
public actor TodayLoader {
    public static let shared = TodayLoader()

    struct Pairing: Codable { var token: String; var code: String; var error: String? }

    /// Konfiguration aus „Widget bearbeiten“ → Eintrag; Fehler → letzter Stand mit `stale`.
    public func load(server raw: String?, code raw2: String?) async -> TodayEntry {
        let server = (raw ?? "").trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let code = (raw2 ?? "").filter(\.isNumber)
        guard server.hasPrefix("http") else { return TodayEntry(date: .now, state: .unpaired(nil), data: nil) }
        var pairing = Self.read(server)
        if code.count == 6, pairing?.code != code {  // neuer Code eingetippt → koppeln
            do {
                let body = ShareAPI.json(["code": code, "label": "Widget"])
                let (out, _): (PairResult, Int) = try await ShareAPI.call("POST", server, "/pair", token: nil, body: body)
                pairing = Pairing(token: out.token, code: code)
            } catch let e as ShareError {
                if e.status == 0 { return cached(server, e.detail) }  // offline: später erneut versuchen
                pairing = Pairing(token: "", code: code, error: e.detail)  // gleichen Code nicht erneut einlösen (429)
            } catch {
                pairing = Pairing(token: "", code: code, error: error.localizedDescription)
            }
            Self.write(server, pairing)
        }
        guard let token = pairing?.token, !token.isEmpty else { return TodayEntry(date: .now, state: .unpaired(pairing?.error), data: nil) }
        do {
            let data = try await fetch(server, token)
            let entry = TodayEntry(date: .now, state: .ok, data: data, images: await images(data, server))
            Self.save(entry, server)
            return entry
        } catch let e as ShareError where e.status == 401 {
            Self.write(server, Pairing(token: "", code: code, error: "Die Kopplung wurde widerrufen – bitte neuen Code eingeben."))
            return TodayEntry(date: .now, state: .unpaired("Die Kopplung wurde widerrufen – bitte neuen Code eingeben."), data: nil)
        } catch {
            return cached(server, (error as? ShareError)?.detail ?? error.localizedDescription)
        }
    }

    private struct Plan: Decodable, Sendable {
        struct Entry: Decodable, Sendable {
            struct Recipe: Decodable, Sendable { var id: Int; var title: String; var prepMinutes: Int; var imageUrl: String }
            var day: Int; var mealType: String; var recipe: Recipe
        }
        var week: String; var entries: [Entry]
    }
    private struct Summary: Decodable, Sendable { var id: Int; var kind: String }
    private struct List: Decodable, Sendable {
        struct Item: Decodable, Sendable { var name: String; var checked: Bool; var nextWeek: Bool? }
        var items: [Item]
    }

    // Wunsch ans Backend (E83): ein kompakter Endpunkt statt drei Anfragen.
    private func fetch(_ server: String, _ token: String) async throws -> TodayData {
        var dishes: [TodayDish] = [], week = TodayData.week(.now)
        do {
            let (plan, _): (Plan, Int) = try await ShareAPI.call("GET", server, "/plans/current", token: token)
            week = plan.week
            dishes = plan.entries.map { e in
                TodayDish(recipeId: e.recipe.id, title: e.recipe.title, mealType: e.mealType, day: e.day, minutes: e.recipe.prepMinutes, imageUrl: e.recipe.imageUrl)
            }
        } catch let e as ShareError where e.status == 404 {}  // noch kein Plan
        let (lists, _): ([Summary], Int) = try await ShareAPI.call("GET", server, "/lists", token: token)
        var open: [String] = []
        if let id = lists.first(where: { l in l.kind == "household" })?.id {
            let (list, _): (List, Int) = try await ShareAPI.call("GET", server, "/lists/\(id)", token: token)
            open = list.items.filter { i in !i.checked && i.nextWeek != true }.map(\.name)
        }
        return TodayData(week: week, dishes: dishes, openCount: open.count, openNames: Array(open.prefix(3)), updated: .now)
    }

    /// Fotos der Gerichte, die in den nächsten 24 h oben stehen – verkleinert (Speichergrenze der Widgets).
    private func images(_ data: TodayData, _ server: String) async -> [Int: Data] {
        let shown = ([Date.now] + TodayData.switches(after: .now)).compactMap { t in data.pick(at: t).hero }
        var out: [Int: Data] = [:]
        for dish in shown where out[dish.recipeId] == nil {
            guard let url = ShareAPI.media(dish.imageUrl, server), !dish.imageUrl.isEmpty,
                  let raw = try? await URLSession.shared.data(from: url).0, let small = Self.thumb(raw, side: 400) else { continue }
            out[dish.recipeId] = small
        }
        return out
    }

    static func thumb(_ data: Data, side: CGFloat) -> Data? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, side / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.7)
    }

    // MARK: Ablage der Erweiterung (kein geteilter Speicher, E48)

    private static func query(_ server: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "de.jsenf.essenapp.widget", kSecAttrAccount as String: server]
    }

    static func read(_ server: String) -> Pairing? {
        var q = query(server)
        q[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Pairing.self, from: data)
    }

    static func write(_ server: String, _ pairing: Pairing?) {
        SecItemDelete(query(server) as CFDictionary)
        guard let pairing else { return }
        var q = query(server)
        q[kSecValueData as String] = try? JSONEncoder().encode(pairing)
        SecItemAdd(q as CFDictionary, nil)
    }

    private struct Saved: Codable { var server: String; var data: TodayData; var images: [Int: Data] }
    private static let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "today.json")

    private static func save(_ entry: TodayEntry, _ server: String) {
        guard let data = entry.data else { return }
        try? JSONEncoder().encode(Saved(server: server, data: data, images: entry.images)).write(to: file, options: .atomic)
    }

    private func cached(_ server: String, _ error: String) -> TodayEntry {
        guard let saved = try? JSONDecoder().decode(Saved.self, from: Data(contentsOf: Self.file)), saved.server == server else {
            return TodayEntry(date: .now, state: .failed(error), data: nil)
        }
        return TodayEntry(date: .now, state: .ok, data: saved.data, images: saved.images, stale: true)
    }
}

// MARK: - Ansichten

/// Emoji zum Gericht – gleiche Auswahl wie der Teller der App (`Plate`).
func dishEmoji(_ seed: String) -> String {
    ["🍛", "🍲", "🍝", "🥗", "🍳", "🍣"][abs(seed.unicodeScalars.reduce(0) { h, c in h &* 31 &+ Int(c.value) }) % 6]
}

/// Inhalt des Widgets je Größe. Die App rendert dieselbe Ansicht als Demo-Screen (`family` statt Umgebung).
public struct TodayWidgetView: View {
    let entry: TodayEntry
    let family: WidgetFamily

    public init(entry: TodayEntry, family: WidgetFamily) {
        self.entry = entry
        self.family = family
    }

    public var body: some View {
        content.containerBackground(for: .widget) { family == .systemSmall || family == .systemMedium ? ST.card : Color.clear }
    }

    @ViewBuilder private var content: some View {
        let pick: (hero: TodayDish?, next: TodayDish?) = entry.data?.pick(at: entry.date) ?? (nil, nil)
        switch (family, entry.state) {
        case (.accessoryInline, _):
            Text(pick.hero.map { d in "\(dishEmoji(d.title)) \(d.title) · \(d.minutes) min" } ?? (entry.state == .ok ? "Kein Gericht geplant" : "Kochpilot koppeln"))
        case (.accessoryRectangular, _):
            rectangular(pick.hero)
        case (_, .unpaired(let error)):
            message("🔗", "Widget bearbeiten → Code eingeben", error ?? "Code: Kochpilot › Einstellungen › Widget einrichten")
        case (_, .failed(let error)):
            message("📡", "Gerade kein Stand", error)
        default:
            if let hero = pick.hero {
                family == .systemMedium ? AnyView(medium(hero, pick.next)) : AnyView(small(hero))
            } else {
                message("🗓️", "Noch kein Wochenplan", "In der App einen Plan erstellen.")
            }
        }
    }

    private func photo(_ dish: TodayDish) -> some View {
        // Overlay statt ZStack: scaledToFill darf das Widget nicht verbreitern (sonst wird der Text links abgeschnitten)
        ST.accentSoft.overlay {
            if let data = entry.images[dish.recipeId], let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(dishEmoji(dish.title)).font(.system(size: 44))
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private func small(_ hero: TodayDish) -> some View {
        ZStack(alignment: .bottomLeading) {
            photo(hero)
            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(TodayData.label(hero, at: entry.date).uppercased()).font(ST.micro).foregroundStyle(.white.opacity(0.85))
                Text(hero.title).font(ST.headline).foregroundStyle(.white).lineLimit(2)
                Label("\(hero.minutes) min", systemImage: "clock").font(ST.caption).foregroundStyle(.white.opacity(0.85))
                staleLine.foregroundStyle(.white.opacity(0.85))
            }
            .padding(14)
        }
        .widgetURL(URL(string: "essenapp://recipe/\(hero.recipeId)"))
    }

    private func medium(_ hero: TodayDish, _ next: TodayDish?) -> some View {
        HStack(spacing: 14) {
            photo(hero).frame(width: 130).clipShape(RoundedRectangle(cornerRadius: ST.tile, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(TodayData.label(hero, at: entry.date).uppercased()).font(ST.micro).foregroundStyle(ST.accentDeep)
                Text(hero.title).font(ST.headline).foregroundStyle(ST.text1).lineLimit(2)
                Label("\(hero.minutes) min", systemImage: "clock").font(ST.caption).foregroundStyle(ST.text2)
                Spacer(minLength: 4)
                if let next {
                    Text("Danach: \(next.title)").font(ST.caption).foregroundStyle(ST.text1).lineLimit(1)
                }
                let open = entry.data?.openCount ?? 0
                Text(open == 0 ? "🛒 Liste erledigt" : "🛒 \(open) offen · \(entry.data?.openNames.joined(separator: ", ") ?? "")")
                    .font(ST.caption).foregroundStyle(ST.text2).lineLimit(1)
                staleLine.foregroundStyle(ST.text3)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(ST.card)
        .widgetURL(URL(string: "essenapp://recipe/\(hero.recipeId)"))
    }

    @ViewBuilder private var staleLine: some View {
        if entry.stale, let updated = entry.data?.updated {
            Label("Stand \(updated.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE"))))", systemImage: "wifi.slash").font(ST.micro)
        }
    }

    private func rectangular(_ hero: TodayDish?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let hero {
                Text(TodayData.label(hero, at: entry.date)).font(ST.micro).widgetAccentable()
                Text("\(dishEmoji(hero.title)) \(hero.title)").font(.headline).lineLimit(1)
                Text("\(hero.minutes) min" + ((entry.data?.openCount ?? 0) > 0 ? " · 🛒 \(entry.data!.openCount) offen" : "")).font(ST.caption)
            } else {
                Text("Kochpilot").font(.headline).widgetAccentable()
                Text(entry.state == .ok ? "Kein Gericht geplant" : "Widget bearbeiten → Code eingeben").font(ST.caption).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func message(_ emoji: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(emoji).font(.system(size: 28))
            Text(title).font(ST.headline).foregroundStyle(ST.text1).lineLimit(2).minimumScaleFactor(0.8)
            Text(text).font(ST.caption).foregroundStyle(ST.text2).lineLimit(3).minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ST.card)
    }
}
