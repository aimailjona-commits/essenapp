import Foundation
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
    public enum State: Sendable, Equatable { case signedOut, ok, failed(String) }

    public var date: Date
    public var state: State
    public var data: TodayData?
    public var images: [Int: Data]  // recipeId → verkleinertes JPEG
    public var stale = false

    public init(date: Date, state: State, data: TodayData?, images: [Int: Data] = [:], stale: Bool = false) {
        self.date = date; self.state = state; self.data = data; self.images = images; self.stale = stale
    }

    /// Demo und Platzhalter wie S39: heute 9:41 (Statusleiste der CI-Screenshots), oben das Abendessen.
    public static let demo = TodayEntry(date: Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: .now) ?? .now, state: .ok, data: TodayData(
        week: TodayData.week(.now),
        dishes: [TodayDish(recipeId: 1, title: "Spaghetti Pomodoro", mealType: "abend", day: TodayData.weekday(.now), minutes: 25, imageUrl: ""),
                 TodayDish(recipeId: 2, title: "Linsen-Dal mit Spinat", mealType: "mittag", day: TodayData.weekday(.now) + 1, minutes: 30, imageUrl: "")],
        openCount: 6, openNames: ["Basmatireis", "Kaffee"], updated: .now))
}

// MARK: - Laden (läuft in der Erweiterung)

/// Holt Plan + Liste mit der Anmeldung der App (geteilter Schlüsselbund, E102).
public actor TodayLoader {
    public static let shared = TodayLoader()

    /// Anmeldung der App → Eintrag; Fehler → letzter Stand mit `stale`.
    public func load() async -> TodayEntry {
        guard let session = SharedLogin.load() else { return TodayEntry(date: .now, state: .signedOut, data: nil) }
        let server = session.server.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        do {
            let data = try await fetch(server, session.token)
            let entry = TodayEntry(date: .now, state: .ok, data: data, images: await images(data, server))
            Self.save(entry, server)
            return entry
        } catch let e as ShareError where e.status == 401 {
            return TodayEntry(date: .now, state: .signedOut, data: nil)
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

    // MARK: Letzter Stand der Erweiterung

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

// MARK: - Ansichten (S39, e.html)

/// Inhalt des Widgets je Größe. Die App rendert dieselbe Ansicht als Demo-Screen (`family` statt Umgebung).
public struct TodayWidgetView: View {
    let entry: TodayEntry
    let family: WidgetFamily

    // Mockup-Maße: Teller klein 96 aus der Ecke (−22), mittel 120 bei 16/19, Text ab 156
    private let smallPlate: CGFloat = 96
    private let smallPlateOut: CGFloat = -22
    private let mediumPlate: CGFloat = 120
    private let mediumText: CGFloat = 156
    private let pad: CGFloat = 14

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
            Label(pick.hero.map { d in "\(d.title) · \(d.minutes) min" } ?? (entry.state == .ok ? "Kein Gericht geplant" : "In Kochpilot anmelden"),
                  systemImage: "fork.knife")
        case (.accessoryRectangular, _):
            rectangular(pick.hero)
        case (_, .signedOut):
            message("person.crop.circle", "Nicht angemeldet", "Öffne Kochpilot einmal und melde dich an.")
        case (_, .failed(let error)):
            message("wifi.slash", "Gerade kein Stand", error)
        default:
            if let hero = pick.hero {
                family == .systemMedium ? AnyView(medium(hero, pick.next)) : AnyView(small(hero))
            } else {
                message("calendar", "Noch kein Wochenplan", "In der App einen Plan erstellen.")
            }
        }
    }

    /// Teller (`.plate`): Kreis-Foto, Rand 6 `card`, Schatten.
    private func plate(_ dish: TodayDish, _ size: CGFloat) -> some View {
        ST.plate.overlay {
            if let data = entry.images[dish.recipeId], let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "fork.knife").font(.system(size: size * 0.3, weight: .light)).foregroundStyle(ST.ink3)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .padding(ST.plateRing)
        .background(ST.card, in: Circle())
        .shadow(color: ST.shadow.opacity(0.16), radius: 15, y: 14)
        .accessibilityHidden(true)
    }

    private func label(_ hero: TodayDish) -> some View {
        Text(TodayData.label(hero, at: entry.date).uppercased())
            .font(ST.text(10, .extrabold, relativeTo: .caption2)).tracking(0.8).foregroundStyle(ST.blue3)
    }

    private func minutes(_ hero: TodayDish) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "clock").font(.system(size: 11, weight: .medium))
            Text("\(hero.minutes) min")
        }
        .font(ST.text(12)).foregroundStyle(ST.ink2)
    }

    private func small(_ hero: TodayDish) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
            VStack(alignment: .leading, spacing: 0) {
                label(hero)
                Text(hero.title).font(ST.serif(18, relativeTo: .headline)).foregroundStyle(ST.ink).lineLimit(2).padding(.top, 2)
                minutes(hero).padding(.top, 4)
                staleLine
            }
            .padding(pad)
        }
        .overlay(alignment: .topTrailing) { plate(hero, smallPlate).offset(x: -smallPlateOut, y: smallPlateOut) }
        .widgetURL(URL(string: "essenapp://recipe/\(hero.recipeId)"))
    }

    private func medium(_ hero: TodayDish, _ next: TodayDish?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            plate(hero, mediumPlate - 2 * ST.plateRing)
                .frame(width: mediumText - 16, alignment: .leading)
                .padding(.leading, 16)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 0) {
                label(hero)
                Text(hero.title).font(ST.serif(19, relativeTo: .headline)).foregroundStyle(ST.ink).lineLimit(2).padding(.top, 2)
                minutes(hero).padding(.top, 3)
                Rectangle().fill(ST.line).frame(height: ST.hair).padding(.top, 6)
                if let next {
                    Text("Danach: \(next.title)").font(ST.text(11.5)).foregroundStyle(ST.ink).lineLimit(1).padding(.top, 5)
                }
                let open = entry.data?.openCount ?? 0
                HStack(spacing: 4) {
                    Image(systemName: "bag").font(.system(size: 11, weight: .medium))
                    Text(open == 0 ? "Liste erledigt" : "\(open) offen · \(entry.data?.openNames.joined(separator: ", ") ?? "")").lineLimit(1)
                }
                .font(ST.text(11.5)).foregroundStyle(ST.ink).padding(.top, 3)
                staleLine
                Spacer(minLength: 0)
            }
            .padding(.top, pad).padding(.trailing, pad)
        }
        .widgetURL(URL(string: "essenapp://recipe/\(hero.recipeId)"))
    }

    @ViewBuilder private var staleLine: some View {
        if entry.stale, let updated = entry.data?.updated {
            Label("Stand \(updated.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE"))))", systemImage: "wifi.slash")
                .font(ST.text(10, .bold)).foregroundStyle(ST.ink3).padding(.top, 3)
        }
    }

    /// Sperrbildschirm rechteckig: „Heute · Abend“, Gericht, Zeit und offene Artikel.
    private func rectangular(_ hero: TodayDish?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let hero {
                Text(TodayData.label(hero, at: entry.date)).font(ST.text(12, .extrabold)).widgetAccentable()
                Text(hero.title).font(ST.text(15, .extrabold)).lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "clock").font(.system(size: 11, weight: .semibold))
                    Text("\(hero.minutes) min")
                    let open = entry.data?.openCount ?? 0
                    if open > 0 {
                        Text("·")
                        Image(systemName: "bag").font(.system(size: 11, weight: .semibold))
                        Text("\(open) offen")
                    }
                }
                .font(ST.text(12, .bold))
            } else {
                Text("Kochpilot").font(ST.text(15, .extrabold)).widgetAccentable()
                Text(entry.state == .ok ? "Kein Gericht geplant" : "Kochpilot öffnen und anmelden").font(ST.text(12, .bold)).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Abgemeldet, Fehler, leer: blauer Kreis mit Symbol, Satz, Hinweis.
    private func message(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(ST.ink)
                .frame(width: 36, height: 36).background(ST.blue1, in: Circle())
            Text(title).font(ST.text(14, .extrabold)).foregroundStyle(ST.ink).lineLimit(2).minimumScaleFactor(0.8).padding(.top, 10)
            Text(text).font(ST.text(10.5)).foregroundStyle(ST.ink2).lineLimit(3).minimumScaleFactor(0.8).padding(.top, 6)
        }
        .padding(pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
