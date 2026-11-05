import SwiftUI

// Monats-Dashboard S32 und Ersparnis S11 (v8, Mockup v8-parts/f.html): Ausgaben = abgehakte Artikel zum Zeitpunkt des Abhakens (A10, E74).

/// = SpendingOut.
struct SpendingDTO: Codable, Hashable {
    struct Week: Codable, Hashable {
        var week: String  // "2026-W45"
        var totalCents: Int
    }
    /// Laden (`chain`) bzw. Kategorie (`category`) mit Summe.
    struct Part: Codable, Hashable {
        var chain: String?
        var category: String?
        var totalCents: Int
        var key: String { chain ?? category ?? "" }
    }
    struct Purchase: Codable, Hashable, Identifiable {
        var id: Int
        var name: String
        var amount: Double?
        var unit: String
        var chain: String
        var category: String
        var priceCents: Int
        var savedCents: Int
        var estimated: Bool
        var boughtAt: String
        var boughtBy: String
    }
    var month: String
    var totalCents: Int
    var estimatedCents: Int
    var budgetCents: Int
    var savedCents: Int
    var bonusCents: Int
    var weeks: [Week]
    var stores: [Part]
    var categories: [Part]
    var top: [Purchase]
    var prevTotalCents: Int
    var changePct: Double?
    var items: [Purchase]
}

/// Monate als "YYYY-MM".
enum Month {
    static var current: String {
        let c = Calendar.current.dateComponents([.year, .month], from: .now)
        return String(format: "%04d-%02d", c.year ?? 2026, c.month ?? 1)
    }

    static func shift(_ key: String, _ n: Int) -> String {
        let p = key.split(separator: "-").compactMap { s in Int(s) }
        guard p.count == 2 else { return key }
        let total = p[0] * 12 + (p[1] - 1) + n
        return String(format: "%04d-%02d", total / 12, total % 12 + 1)
    }

    /// „November 2026“ bzw. ohne Jahr „November“.
    static func name(_ key: String, year: Bool = true) -> String {
        let p = key.split(separator: "-").compactMap { s in Int(s) }
        guard p.count == 2, let d = Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: 1)) else { return key }
        return year ? d.formatted(.dateTime.month(.wide).year().locale(.de)) : d.formatted(.dateTime.month(.wide).locale(.de))
    }

    /// Aktuelle ISO-Woche „2026-W45“ (Balken hervorheben).
    static var week: String { week(of: .now) }

    static func week(of date: Date) -> String {
        let cal = Calendar(identifier: .iso8601)
        return String(format: "%04d-W%02d", cal.component(.yearForWeekOfYear, from: date), cal.component(.weekOfYear, from: date))
    }

    /// „2026-11-03T18:20:00“ → Datum (nur der Tag zählt).
    static func day(_ iso: String) -> Date? {
        let p = iso.prefix(10).split(separator: "-").compactMap { s in Int(s) }
        guard p.count == 3 else { return nil }
        return Calendar(identifier: .iso8601).date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    static let shortMonths = ["Jan", "Feb", "März", "Apr", "Mai", "Juni", "Juli", "Aug", "Sep", "Okt", "Nov", "Dez"]

    /// „3. Nov“ bzw. mit Wochentag „Dienstag, 3. Nov“.
    static func short(_ date: Date, weekday: Bool = false) -> String {
        let cal = Calendar(identifier: .iso8601)
        let text = "\(cal.component(.day, from: date)). \(shortMonths[cal.component(.month, from: date) - 1])"
        return weekday ? "\(date.formatted(.dateTime.weekday(.wide).locale(.de))), \(text)" : text
    }

    #if DEBUG
    static func selfTest() {
        assert(shift("2026-01", -1) == "2025-12" && shift("2026-12", 1) == "2027-01" && shift("2026-11", 0) == "2026-11")
        assert(name("2026-11") == "November 2026" && name("2026-03", year: false) == "März", name("2026-11"))
        assert(day("2026-11-03T18:20:00").map { d in short(d) } == "3. Nov" && week(of: day("2026-11-03")!) == "2026-W45")
        assert(day("2026-11-03").map { d in short(d, weekday: true) } == "Dienstag, 3. Nov")
    }
    #endif
}

extension AppStore {
    func spending(_ month: String) async throws -> SpendingDTO {
        demo ? Demo.spending(month) : try await api.request("GET", "/spending?month=\(month)")
    }

    /// CSV als Datei zum Teilen („ausgaben-2026-11.csv“, Semikolon, Dezimalkomma).
    func spendingCSV(_ month: String) async -> URL? {
        let data: Data? = demo ? Data("Datum;Artikel;Menge;Einheit;Laden;Kategorie;Preis €;Gespart €;Geschätzt\n".utf8)
            : try? await api.send("GET", "/spending/export?month=\(month)")
        guard let data else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "ausgaben-\(month).csv")
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        return url
    }
}

/// „87,96“ – Betrag ohne Währungszeichen (Balken-Beschriftung).
func euroPlain(_ cents: Int) -> String { (Double(cents) / 100).formatted(.number.precision(.fractionLength(2)).locale(.de)) }

// MARK: S32 Monats-Dashboard

/// Push-Screen aus der Start-Zeile „Ausgaben November“ und Einstellungen › Einkaufen › Ausgaben.
struct SpendingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var month = Month.current
    @State private var data: [String: SpendingDTO] = [:]
    @State private var error: String?
    @State private var csv: URL?
    @State private var grown = false
    @State private var scrolled = false
    @State private var allCategories = false
    @State private var allTop = false

    // Mockup S32 oben (Telefon 390 × 844, Statusleiste 52, Kopfzeile 14 + 44 darunter)
    private enum L {
        static let blob: CGFloat = 300, blobRight: CGFloat = -106, blobTop: CGFloat = 56 - 52 - 58
        static let ring: CGFloat = 160, ringRight: CGFloat = 18, ringTop: CGFloat = 120 - 52 - 58
        static let ringRadius: CGFloat = 50 * 160 / 120, ringLine: CGFloat = 11 * 160 / 120
        static let head: CGFloat = 376 - 52 - 58  // Block „‹ Oktober“ beginnt bei y 376
    }

    var body: some View {
        let s = data[month]
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Month.name(month)).font(Theme.F.small).foregroundStyle(Theme.C.ink2).contentTransition(.opacity)
                    Text("Ausgaben").font(Theme.F.t1)
                }
                .padding(.top, 24)
                .frame(maxWidth: .infinity, minHeight: L.head, alignment: .topLeading)
                .background(GeometryReader { g in
                    Color.clear.onChange(of: g.frame(in: .named("spending")).minY < -60, initial: true) { _, on in
                        withAnimation(.easeOut(duration: 0.2)) { scrolled = on }
                    }
                })
                monthSwitch
                if let s {
                    content(s)
                } else if let error {
                    ErrorBlock8(message: error) { Task { await load() } }.padding(.top, 36)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Skeleton8(height: 72).padding(.top, 36)
                        Skeleton8(height: 120)
                        Skeleton8(height: 136)
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, Theme.S.nav)
            .background(alignment: .topTrailing) { if let s { ring(s).offset(x: -L.ringRight, y: L.ringTop) } }
            .edgeForm(.circle, Theme.C.blue1, width: L.blob, height: L.blob, right: L.blobRight, top: L.blobTop)
            .animation(Theme.spring, value: month)
        }
        .coordinateSpace(name: "spending")
        .scrollClipDisabled()
        .safeAreaInset(edge: .top, spacing: 0) { topBar(s) }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { v in  // Monatswahl wischbar
            guard abs(v.translation.width) > 60, abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
            go(v.translation.width < 0 ? 1 : -1)
        })
        .sensoryFeedback(.selection, trigger: month)
        .task(id: month) { await load() }
    }

    /// Kopfzeile: zurück, beim Scrollen „Ausgaben · November“, CSV teilen (S32 Mitte/unten).
    private func topBar(_ s: SpendingDTO?) -> some View {
        HStack {
            BackButton8()
            Spacer()
            Text("Ausgaben · \(Month.name(month, year: false))").font(Theme.F.text(16, .extrabold, relativeTo: .headline))
                .opacity(scrolled ? 1 : 0)
            Spacer()
            if let csv, s.map({ x in !x.items.isEmpty }) == true {
                ShareLink(item: csv, preview: SharePreview("Ausgaben \(Month.name(month))")) {
                    Icon(.share, size: 20).foregroundStyle(Theme.C.onInk).frame(width: 44, height: 44).background(Theme.C.ink, in: Circle())
                }
                .accessibilityLabel("Als CSV teilen")
                .transition(.scale.combined(with: .opacity))
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 14)
        .background(Theme.C.bg.opacity(scrolled ? 1 : 0).ignoresSafeArea(edges: .top))
    }

    /// Ring 61 % vom Budget im Pastell-Kreis (oben rechts).
    private func ring(_ s: SpendingDTO) -> some View {
        let ratio = s.budgetCents > 0 ? Double(s.totalCents) / Double(s.budgetCents) : 0
        return ZStack {
            Circle().stroke(Theme.C.card, lineWidth: L.ringLine)
            Circle().trim(from: 0, to: grown ? min(ratio, 1) : 0)
                .stroke(ratio > 1 ? Theme.C.deal : Theme.C.ink, style: StrokeStyle(lineWidth: L.ringLine, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                BigNumber(s.budgetCents > 0 ? "\(Int((ratio * 100).rounded())) %" : "–", size: 40)
                Text("vom Budget").font(Theme.F.text(12, .semibold, relativeTo: .caption))
            }
            .foregroundStyle(Theme.C.ink)
        }
        .frame(width: L.ringRadius * 2, height: L.ringRadius * 2)
        .frame(width: L.ring, height: L.ring)
        .accessibilityElement(children: .combine)
    }

    private var monthSwitch: some View {
        let next = Month.shift(month, 1)
        let canNext = next <= Month.current
        return HStack {
            Button { go(-1) } label: {
                HStack(spacing: 4) { Icon(.back, size: 18); Text(Month.name(Month.shift(month, -1), year: false)) }
                    .contentShape(Rectangle().inset(by: -11))
            }
            .accessibilityLabel("Vormonat")
            Spacer()
            Button { go(1) } label: {
                HStack(spacing: 4) { Text(Month.name(next, year: false)); Icon(.chev, size: 18) }
                    .foregroundStyle(canNext ? Theme.C.ink : Theme.C.ink3)
                    .contentShape(Rectangle().inset(by: -11))
            }
            .disabled(!canNext)
            .accessibilityLabel("Nächster Monat")
        }
        .font(Theme.F.text(16, .extrabold, relativeTo: .headline))
        .foregroundStyle(Theme.C.ink)
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder private func content(_ s: SpendingDTO) -> some View {
        if s.items.isEmpty && s.totalCents == 0 {
            EmptyBlock8(ill: "bag", title: "Noch keine Einkäufe im \(Month.name(month, year: false))",
                        text: "Ausgaben entstehen, wenn ihr Artikel auf der Liste abhakt – mit Angebotspreis, sonst geschätzt.")
                .padding(.top, 36)
        } else {
            totals(s)
            saved(s).padding(.top, 40)
            weeks(s)
            if !s.stores.isEmpty { stores(s.stores) }
            if !s.categories.isEmpty { categories(s.categories) }
            if !s.top.isEmpty { top(s.top) }
        }
    }

    private func totals(_ s: SpendingDTO) -> some View {
        let parts = euroParts(s.totalCents)
        return VStack(alignment: .leading, spacing: 0) {
            StatF(label: "Ausgegeben", value: parts.0, unit: parts.1, size: 72, unitSize: 32, roll: 0).padding(.top, 36)
            if s.estimatedCents > 0 {
                Text("davon \(euro(s.estimatedCents)) geschätzt").font(Theme.F.text(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Theme.C.ink2).frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 8)
            }
            HStack(alignment: .top, spacing: 20) {
                StatF(label: "Budget", value: s.budgetCents > 0 ? euro(s.budgetCents) : "–", size: 24, mute: true, roll: 0.15)
                if let pct = s.changePct {
                    StatF(label: "zum \(Month.name(Month.shift(month, -1), year: false))",
                          value: "\(pct > 0 ? "+" : pct < 0 ? "−" : "±")\(num(abs(pct))) %", size: 24,
                          valueColor: pct > 0 ? Theme.C.deal : nil, mute: true, roll: 0.15)
                } else {
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
            .padding(.top, 36)
        }
    }

    /// Gespart als Hauptzahl, Angebote/Bonus als eine graue Zeile.
    private func saved(_ s: SpendingDTO) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            StatF(label: "Gespart", value: euro(s.savedCents + s.bonusCents), size: 64)
            Text("\(euro(s.savedCents)) Angebote · \(euro(s.bonusCents)) Bonus").font(Theme.F.text(13, .semibold, relativeTo: .footnote))
                .foregroundStyle(Theme.C.ink2).frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 8)
        }
    }

    /// Balken je KW mit Betrag darüber (kommende/leere Wochen als Umriss).
    private func weeks(_ s: SpendingDTO) -> some View {
        let top = max(s.weeks.map(\.totalCents).max() ?? 0, 1)
        let now = Month.week
        return VStack(alignment: .leading, spacing: 0) {
            SecHead("Pro Woche").padding(.top, 40)
            FBars(bars: s.weeks.map { w in
                FBars.Bar(id: w.week, height: w.totalCents > 0 ? 120 * CGFloat(w.totalCents) / CGFloat(top) : 14, on: w.week == now,
                          no: w.totalCents == 0, top: w.totalCents > 0 ? euroPlain(w.totalCents) : "–", axis: "KW \(w.week.suffix(2))",
                          a11y: euro(w.totalCents))
            }, grown: grown)
            .padding(.top, 30)
        }
    }

    /// Ring-Torte pro Laden: die drei größten Läden, Rest „Andere“; Farben nach Rang wie im Mockup.
    private func stores(_ parts: [SpendingDTO.Part]) -> some View {
        let sorted = parts.sorted { a, b in a.totalCents > b.totalCents }
        let named = Array(sorted.filter { p in !p.key.isEmpty }.prefix(3))
        let rest = sorted.filter { p in !named.contains(p) }.map(\.totalCents).reduce(0, +)
        let rows = named.map { p in (p.key, p.totalCents) } + (rest > 0 ? [("", rest)] : [])
        let total = max(rows.map(\.1).reduce(0, +), 1)
        let colors = [Theme.C.rose, Theme.C.blue, Theme.C.sand, Theme.C.sage]
        let pcts = rows.map { r in Int((Double(r.1) / Double(total) * 100).rounded()) }
        let starts = pcts.indices.map { i in pcts.prefix(i).reduce(0, +) }
        return VStack(alignment: .leading, spacing: 0) {
            SecHead("Pro Laden").padding(.top, 40)
            HStack(spacing: 22) {
                ZStack {
                    ForEach(rows.indices, id: \.self) { i in
                        Circle()
                            .trim(from: CGFloat(starts[i]) / 100, to: grown ? CGFloat(starts[i] + max(pcts[i] - 1, 0)) / 100 : CGFloat(starts[i]) / 100)
                            .stroke(colors[i], lineWidth: 22 * 136 / 120)
                    }
                }
                .rotationEffect(.degrees(-90))
                .frame(width: 88 * 136 / 120, height: 88 * 136 / 120)
                .frame(width: 136, height: 136)
                .accessibilityHidden(true)
                VStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            Circle().fill(colors[i]).frame(width: 10, height: 10)
                            if !rows[i].0.isEmpty { LogoInline(chain: rows[i].0, height: 14, fallback: false) }
                            Text(rows[i].0.isEmpty ? "Andere" : Labels.chain(rows[i].0)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(pcts[i]) %").font(Theme.F.text(14, .bold, relativeTo: .subheadline))
                        }
                        .frame(minHeight: 32)
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(euro(rows[i].1))
                    }
                }
                .font(Theme.F.text(14, .semibold, relativeTo: .subheadline))
            }
            .padding(.top, 16)
        }
    }

    /// Pro Kategorie: drei Zeilen, Rest hinter „Alle Kategorien ›“.
    private func categories(_ parts: [SpendingDTO.Part]) -> some View {
        let sorted = parts.sorted { a, b in a.totalCents > b.totalCents }
        let total = max(sorted.map(\.totalCents).reduce(0, +), 1)
        let shown = allCategories ? sorted : Array(sorted.prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            SecHead("Pro Kategorie").padding(.top, 40).padding(.bottom, 8)
            ForEach(shown, id: \.key) { p in
                let look = CategoryLook(p.key)
                HStack(spacing: 14) {
                    look.circle
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Labels.categoryName(p.key)).font(Theme.F.rowName).lineLimit(1)
                        Text("\(Int((Double(p.totalCents) / Double(total) * 100).rounded())) % der Ausgaben")
                            .font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                    }
                    Spacer(minLength: 8)
                    BigNumber(euro(p.totalCents), size: 22)
                }
                .frame(minHeight: 64)
                .overlay(alignment: .top) { Hairline() }
                .accessibilityElement(children: .combine)
            }
            if sorted.count > 3 { moreRow(allCategories ? "Weniger anzeigen" : "Alle Kategorien · \(sorted.count - 3) weitere", open: allCategories) { allCategories.toggle() } }
        }
    }

    /// Top 5 teuerste: drei mit Rang, Logo, Datum; Rest hinter „Alle 5 anzeigen ›“.
    private func top(_ top: [SpendingDTO.Purchase]) -> some View {
        let shown = allTop ? top : Array(top.prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            SecHead("Top \(top.count) teuerste").padding(.top, 40).padding(.bottom, 8)
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, p in
                HStack(spacing: 14) {
                    BigNumber("\(i + 1)", size: 30).frame(width: 30, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(Theme.F.text(16, .extrabold, relativeTo: .body)).lineLimit(1)
                        HStack(spacing: 6) {
                            if !p.chain.isEmpty { LogoInline(chain: p.chain, height: 12) }
                            Text(Month.day(p.boughtAt).map { d in Month.short(d) } ?? shortDate(p.boughtAt))
                            if p.estimated { Text("· geschätzt") }
                        }
                        .font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                    }
                    Spacer(minLength: 8)
                    BigNumber(euro(p.priceCents), size: 22)
                }
                .frame(minHeight: 64)
                .overlay(alignment: .top) { Hairline() }
                .accessibilityElement(children: .combine)
            }
            if top.count > 3 { moreRow(allTop ? "Weniger anzeigen" : "Alle \(top.count) anzeigen", open: allTop) { allTop.toggle() } }
        }
    }

    private func moreRow(_ title: String, open: Bool, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(Theme.spring) { action() } } label: {
            HStack {
                Text(title).font(Theme.F.text(16, .bold, relativeTo: .body))
                Spacer()
                Icon(.chev, size: 18).rotationEffect(.degrees(open ? 90 : 0))
            }
            .foregroundStyle(Theme.C.ink2)
            .frame(minHeight: 52)
            .overlay(alignment: .top) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func go(_ n: Int) {
        let target = Month.shift(month, n)
        guard target <= Month.current else { return }
        withAnimation(Theme.spring) { month = target }
    }

    private func load() async {
        grown = false
        csv = nil
        do {
            let s = try await store.spending(month)
            data[month] = s
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        withAnimation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.8)) { grown = true }
        let url = await store.spendingCSV(month)
        withAnimation(Theme.spring) { csv = url }
    }
}

/// „156,86 €“ → ("156,86", " €") für Zahl und kleinere Einheit.
func euroParts(_ cents: Int) -> (String, String) { (euroPlain(cents), " €") }

/// Kreis + Zeichnung/Icon je Kategorie (Mockup S32 unten: Obst rosé mit Tomate, Drogerie sand mit Box, Vorrat blau mit Pasta).
struct CategoryLook {
    let key: String
    init(_ key: String) { self.key = key }

    var circle: some View {
        let (tint, ill, icon): (Color, String?, Icon8?) = switch key {
        case "obst_gemuese": (Theme.C.rose, "tomato", nil)
        case "vorrat": (Theme.C.blue1, "pasta", nil)
        case "drogerie": (Theme.C.sand, nil, .box)
        case "kuehlung": (Theme.C.blue1, "fridge", nil)
        case "fleisch_fisch": (Theme.C.sage, "pot", nil)
        case "haushalt": (Theme.C.sage, nil, .sparkle)
        default: (Theme.C.sand, "bag", nil)
        }
        return ZStack {
            if let ill { Ill(ill).frame(width: Theme.S.rowImage, height: Theme.S.rowImage) }
            if let icon { Icon(icon).foregroundStyle(Theme.C.ink) }
        }
        .frame(width: Theme.S.rowCircle, height: Theme.S.rowCircle)
        .background(tint, in: Circle())
    }
}

// MARK: S11 Ersparnis

/// Gesamtersparnis der letzten drei Monate, diese Woche, acht Wochenbalken, Verlauf je Einkauf (Laden + Tag).
/// Datenquelle: GET /spending der drei Monate (Angebots-Ersparnis je Artikel, Bonus je Monat).
struct SavingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var months: [SpendingDTO]?
    @State private var error: String?
    @State private var grown = false
    @State private var all = false

    // Mockup S11: Kreis 330 bei x 190 / y −120, Tasche 136 bei x 236 / y 52
    private enum L {
        static let blob: CGFloat = 330, blobRight: CGFloat = 390 - 190 - 330, blobTop: CGFloat = -120 - 52
        static let ill: CGFloat = 136, illRight: CGFloat = 390 - 236 - 136, illTop: CGFloat = 52 - 52
    }

    private struct Visit: Identifiable {
        var id: String
        var chain: String
        var date: Date
        var count: Int
        var savedCents: Int
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackButton8()
                if let months {
                    content(months)
                } else if let error {
                    ErrorBlock8(message: error) { Task { await load() } }.padding(.top, 34)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Skeleton8(width: 140, height: 18).padding(.top, 34)
                        Skeleton8(height: 96)
                        Skeleton8(height: 120)
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding).padding(.top, 14).padding(.bottom, Theme.S.nav)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pinned(right: L.illRight, top: L.illTop) { Ill("bag").frame(width: L.ill, height: L.ill) }
            .edgeForm(.circle, Theme.C.blue1, width: L.blob, height: L.blob, right: L.blobRight, top: L.blobTop)
        }
        .scrollClipDisabled()
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await load() }
        .task { await load() }
    }

    @ViewBuilder private func content(_ months: [SpendingDTO]) -> some View {
        let items = months.flatMap(\.items)
        let total = months.map { m in m.savedCents + m.bonusCents }.reduce(0, +)
        let byWeek = Dictionary(grouping: items) { p in Month.day(p.boughtAt).map(Month.week(of:)) ?? "" }
            .mapValues { ps in ps.map(\.savedCents).reduce(0, +) }
        let cal = Calendar(identifier: .iso8601)
        let weeks = (0..<8).reversed().compactMap { i in cal.date(byAdding: .weekOfYear, value: -i, to: .now) }
        let values = weeks.map { d in byWeek[Month.week(of: d)] ?? 0 }
        let maxValue = max(values.max() ?? 0, 1)
        let visits = Dictionary(grouping: items) { p in "\(p.boughtAt.prefix(10))|\(p.chain)" }
            .compactMap { key, ps -> Visit? in
                guard let date = Month.day(ps[0].boughtAt) else { return nil }
                return Visit(id: key, chain: ps[0].chain, date: date, count: ps.count, savedCents: ps.map(\.savedCents).reduce(0, +))
            }
            .sorted { a, b in a.date > b.date }
        let parts = euroParts(total)
        Text("seit 1. \(Month.name(months.last?.month ?? Month.current, year: false))").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
            .padding(.top, 34)
        Text("Gespart").font(Theme.F.t1)
        StatF(label: "Gesamt", value: parts.0, unit: parts.1, size: 96, unitSize: 40, roll: 0).padding(.top, 24)
        StatF(label: "Diese Woche", value: euro(byWeek[Month.week] ?? 0), size: 32, mute: true, roll: 0.15).padding(.top, 12)
        HStack {
            Text("Letzte 8 Wochen").font(Theme.F.text(16, .extrabold, relativeTo: .headline))
            Spacer()
            Text("Ø \(euro(values.reduce(0, +) / 8))").font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
        }
        .padding(.top, 36)
        FBars(bars: zip(weeks, values).map { d, v in
            let w = Month.week(of: d)
            return FBars.Bar(id: w, height: v > 0 ? 120 * CGFloat(v) / CGFloat(maxValue) : 14, on: w == Month.week, no: v == 0, top: nil,
                             axis: String(w.suffix(2)), a11y: "KW \(w.suffix(2)): \(euro(v))")
        }, grown: grown)
        .padding(.top, 14)
        SecHead("Verlauf").padding(.top, 36).padding(.bottom, 6)
        if visits.isEmpty {
            Text("Noch keine Einkäufe abgehakt.").font(Theme.F.small).foregroundStyle(Theme.C.ink2).padding(.vertical, 12)
        }
        ForEach(all ? visits : Array(visits.prefix(2))) { v in
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(v.chain.isEmpty ? "Ohne Laden" : Labels.chain(v.chain)) · \(v.count) Artikel").font(Theme.F.text(16, .extrabold, relativeTo: .body))
                    Text(Month.short(v.date, weekday: true)).font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                }
                Spacer(minLength: 8)
                BigNumber("+\(euro(v.savedCents))", size: 22)
            }
            .frame(minHeight: Theme.S.row)
            .overlay(alignment: .top) { Hairline() }
            .accessibilityElement(children: .combine)
        }
        if visits.count > 2 {
            Button { withAnimation(Theme.spring) { all.toggle() } } label: {
                HStack {
                    Text(all ? "Weniger anzeigen" : "Alle Einkäufe · \(visits.count - 2) weitere").font(Theme.F.text(16, .bold, relativeTo: .body))
                    Spacer()
                    Icon(.chev, size: 18).rotationEffect(.degrees(all ? 90 : 0))
                }
                .foregroundStyle(Theme.C.ink2)
                .frame(minHeight: 52)
                .overlay(alignment: .top) { Hairline() }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func load() async {
        grown = false
        do {
            var loaded: [SpendingDTO] = []
            for n in 0..<3 { loaded.append(try await store.spending(Month.shift(Month.current, -n))) }
            months = loaded
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        withAnimation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.8)) { grown = true }
    }
}

/// Start-Zeile „Ausgaben November“ (Mockup S1 gescrollt): große Zahl, Balken „von 257,14 €“ → Monats-Dashboard.
struct SpendingCard: View {
    @Environment(AppStore.self) private var store
    @State private var s: SpendingDTO?

    var body: some View {
        VStack(spacing: 0) {
            if let s {
                NavigationLink { SpendingView() } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        StatF(label: "Ausgaben\n\(Month.name(s.month, year: false))", value: euro(s.totalCents), size: 44, roll: 0)
                        if s.budgetCents > 0 {
                            HStack(spacing: 10) {
                                ProgressBar8(value: Double(s.totalCents) / Double(s.budgetCents), color: s.totalCents > s.budgetCents ? Theme.C.deal : Theme.C.ink)
                                Text("von \(euro(s.budgetCents))").font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                            }
                        }
                    }
                    .foregroundStyle(Theme.C.ink)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .transition(.opacity)
            }
        }
        .animation(Theme.spring, value: s)
        .task(id: store.householdList?.items.filter(\.checked).count) { s = (try? await store.spending(Month.current)) ?? s }
    }
}

// MARK: v8-Hilfen Gruppe F (Ausgaben, Ersparnis, Erfolge, Rückblick)

/// `.stat` mit den freien Größen aus dem Mockup: Haarlinie, Label links oben (auch zweizeilig), Zahl rechts, Einheit kleiner.
/// `roll` = Verzögerung für „a1-num“: Haarlinie zieht sich von links (0,5 s), Ziffern rollen wie ein Zählwerk ein.
struct StatF: View {
    let label: String
    let value: String
    var unit: String?
    var size: CGFloat
    var unitSize: CGFloat = 0
    var unitColor: Color?
    var valueColor: Color?
    var mute = false
    var roll: Double?
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = mute ? Theme.C.ink3 : Theme.C.ink
        VStack(spacing: 6) {
            Rectangle().fill(color).frame(height: Theme.S.hair)
                .scaleEffect(x: roll == nil || shown || reduceMotion ? 1 : 0.001, anchor: .leading)
            HStack(alignment: .top, spacing: 8) {
                Text(label).font(Theme.F.text(12, .bold, relativeTo: .caption)).foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    RollText(text: value, size: size, shown: roll == nil ? nil : shown, delay: roll ?? 0)
                        .foregroundStyle(valueColor ?? color)
                    if let unit {
                        Text(unit).font(Theme.F.num(unitSize)).tracking(Theme.F.numTracking(unitSize))
                            .foregroundStyle(unitColor ?? valueColor ?? color)
                    }
                }
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.replacingOccurrences(of: "\n", with: " ")): \(value)\(unit ?? "")")
        .onAppear {
            guard let roll, !shown else { return }
            withAnimation(reduceMotion ? nil : .timingCurve(0.3, 1, 0.5, 1, duration: 0.5).delay(roll)) { shown = true }
        }
    }
}

/// Zahl wie ein Zählwerk (a1-num): jede Ziffer ist ein Streifen 0–9, rollt von unten ein (0,6 s, je Ziffer 60 ms versetzt)
/// und rollt bei neuem Wert weiter. Passt sie nicht in die Breite, steht sie als `BigNumber` (schrumpft).
struct RollText: View {
    let text: String
    let size: CGFloat
    var shown: Bool?  // nil = ohne Einrollen
    var delay: Double = 0
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 100
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if shown == nil || reduceMotion {
            BigNumber(text, size: size)
        } else {
            ViewThatFits(in: .horizontal) {
                columns
                BigNumber(text, size: size)
            }
        }
    }

    private var columns: some View {
        let em = size * scale / 100, h = em * 0.92
        let curve = Animation.timingCurve(0.3, 1.25, 0.5, 1, duration: 0.6)
        return HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { j, ch in
                if let d = ch.wholeNumberValue {
                    VStack(spacing: 0) { ForEach(0..<10, id: \.self) { n in Text("\(n)").frame(height: h) } }
                        .offset(y: shown == true ? -CGFloat(d) * h : 1.1 * em)
                        .frame(height: h, alignment: .top)
                        .clipped()
                        .animation(curve.delay(delay + Double(j) * 0.06), value: shown)
                        .animation(curve, value: d)
                } else {
                    Text(String(ch)).frame(height: h)
                }
            }
        }
        .font(Theme.F.num(size))
        .tracking(Theme.F.numTracking(size))
        .fixedSize()
        .accessibilityLabel(text)
    }
}

/// Schlichte Balken (`.f-bars` + `.f-ax`): Pastellblau, aktuelle Woche Tinte, leer als Umriss; Grundlinie Tinte.
struct FBars: View {
    struct Bar: Identifiable {
        var id: String
        var height: CGFloat
        var on: Bool
        var no: Bool
        var top: String?
        var axis: String
        var a11y: String
    }
    let bars: [Bar]
    var grown = true
    var height: CGFloat = 120

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(bars) { b in
                    let shape = UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8)
                    Group {
                        if b.no { shape.strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } else { shape.fill(b.on ? Theme.C.ink : Theme.C.blue) }
                    }
                    .frame(height: grown || b.no ? b.height : 0)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .top) {
                        if let t = b.top {
                            Text(t).font(Theme.F.text(11, .extrabold, relativeTo: .caption2)).foregroundStyle(b.no ? Theme.C.ink3 : Theme.C.ink)
                                .fixedSize().alignmentGuide(.top) { d in d[.bottom] + 5 }
                                .opacity(grown ? 1 : 0)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(b.axis)
                    .accessibilityValue(b.a11y)
                }
            }
            .frame(height: height, alignment: .bottom)
            Rectangle().fill(Theme.C.ink).frame(height: Theme.S.hair)
            HStack(spacing: 10) {
                ForEach(bars) { b in
                    Text(b.axis).font(Theme.F.text(11, b.on ? .extrabold : .bold, relativeTo: .caption2))
                        .foregroundStyle(b.on ? Theme.C.ink : Theme.C.ink2).lineLimit(1).frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 6)
            .accessibilityHidden(true)
        }
    }
}

/// Abschnitts-Titel 16/800 („Pro Woche“, „Verlauf“).
struct SecHead: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(Theme.F.text(16, .extrabold, relativeTo: .headline)).foregroundStyle(Theme.C.ink).accessibilityAddTraits(.isHeader)
    }
}

/// Zurück-Pfeil 26 wie im Mockup, Tap-Fläche 44.
struct BackButton8: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            Icon(.back, size: 26).foregroundStyle(Theme.C.ink)
                .frame(width: 44, height: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .frame(width: 44, height: 26, alignment: .leading)
        .accessibilityLabel("Zurück")
    }
}

/// Händler-Logo ohne Plättchen in Zeilenhöhe (Legende, Top 5); ohne Logo der Name bzw. nichts.
struct LogoInline: View {
    let chain: String
    var height: CGFloat
    var fallback = true

    var body: some View {
        RemoteImage(url: Labels.logoURL(chain), dim: false) {
            if fallback { Text(Labels.chain(chain)) }
        }
        .frame(height: height)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHidden(true)
    }
}

/// Fehler im v8-Stil: t2, Grund, „Erneut versuchen“.
struct ErrorBlock8: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Das hat nicht geklappt").font(Theme.F.t2)
            Text(message).font(Theme.F.small).foregroundStyle(Theme.C.ink2).fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "Erneut versuchen", icon: .refresh, action: retry).padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Leer-Zustand v8: Zeichnung im blauen Kreis, t2, Text, optional Knopf.
struct EmptyBlock8: View {
    let ill: String
    let title: String
    let text: String
    var button: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 4) {
            Ill(ill).frame(width: 150, height: 150).background(Circle().fill(Theme.C.blue1).frame(width: 130, height: 130))
            Text(title).font(Theme.F.t2).padding(.top, 6).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Text(text).font(Theme.F.small).foregroundStyle(Theme.C.ink2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if let button, let action { PrimaryButton(title: button, action: action).padding(.top, 14) }
        }
        .frame(maxWidth: .infinity)
        .appear()
    }
}
