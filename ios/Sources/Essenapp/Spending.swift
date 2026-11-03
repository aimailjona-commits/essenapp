import Charts
import SwiftUI

// Monats-Dashboard (34): Ausgaben = abgehakte Artikel zum Zeitpunkt des Abhakens (A10, E74).

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
    static var week: String {
        let cal = Calendar(identifier: .iso8601)
        return String(format: "%04d-W%02d", cal.component(.yearForWeekOfYear, from: .now), cal.component(.weekOfYear, from: .now))
    }

    #if DEBUG
    static func selfTest() {
        assert(shift("2026-01", -1) == "2025-12" && shift("2026-12", 1) == "2027-01" && shift("2026-11", 0) == "2026-11")
        assert(name("2026-11") == "November 2026" && name("2026-03", year: false) == "März", name("2026-11"))
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

// MARK: S32 Monats-Dashboard

/// Push-Screen aus der Start-Karte „Ausgaben November“ und Einstellungen › Einkaufen › Ausgaben.
struct SpendingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var month = Month.current
    @State private var data: [String: SpendingDTO] = [:]
    @State private var error: String?
    @State private var csv: URL?
    @State private var grown = false

    var body: some View {
        let s = data[month]
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                    Spacer()
                    if let csv, s.map({ x in !x.items.isEmpty }) == true {
                        ShareLink(item: csv, preview: SharePreview("Ausgaben \(Month.name(month))")) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold))
                                .frame(width: 44, height: 44).foregroundStyle(Theme.C.text1)
                                .background(Theme.C.card, in: Circle()).overlay(Circle().strokeBorder(Theme.C.line, lineWidth: 0.5))
                        }
                        .accessibilityLabel("Als CSV teilen")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                DisplayHeader(line1: "Ausgaben", line2: Month.name(month))
                    .contentTransition(.opacity)
                monthSwitch
                if let s {
                    content(s)
                } else if let error {
                    ErrorState(message: error) { Task { await load() } }
                } else {
                    SkeletonCard(height: 150)
                    SkeletonCard(height: 220)
                    SkeletonCard(height: 200)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
            .animation(Theme.spring, value: month)
        }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { v in  // Monatswahl wischbar
            guard abs(v.translation.width) > 60, abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
            go(v.translation.width < 0 ? 1 : -1)
        })
        .sensoryFeedback(.selection, trigger: month)
        .task(id: month) { await load() }
    }

    private var monthSwitch: some View {
        let next = Month.shift(month, 1)
        return HStack {
            Button { go(-1) } label: { Label(Month.name(Month.shift(month, -1), year: false), systemImage: "chevron.left") }
                .accessibilityLabel("Vormonat")
            Spacer()
            if next <= Month.current {
                Button { go(1) } label: {
                    HStack(spacing: 6) { Text(Month.name(next, year: false)); Image(systemName: "chevron.right") }
                }
                .accessibilityLabel("Nächster Monat")
            }
        }
        .font(Theme.F.callout).foregroundStyle(Theme.C.text1)
        .buttonStyle(PressableStyle())
        .frame(minHeight: 44)
    }

    @ViewBuilder private func content(_ s: SpendingDTO) -> some View {
        if s.items.isEmpty && s.totalCents == 0 {
            EmptyState(emoji: "🧾", title: "Noch keine Einkäufe im \(Month.name(month, year: false))",
                       text: "Ausgaben entstehen, wenn ihr Artikel auf der Liste abhakt – mit Angebotspreis, sonst geschätzt.")
        } else {
            ringCard(s).appear()
            savedCard(s).appear(delay: 0.04)
            weeksCard(s).appear(delay: 0.08)
            if !s.stores.isEmpty { pieCard("Pro Laden", s.stores, stores: true).appear(delay: 0.12) }
            if !s.categories.isEmpty { pieCard("Pro Kategorie", s.categories, stores: false).appear(delay: 0.16) }
            if !s.top.isEmpty { topCard(s.top).appear(delay: 0.2) }
        }
    }

    /// Ring: Monatssumme gegen Budget, Vergleich zum Vormonat.
    private func ringCard(_ s: SpendingDTO) -> some View {
        let ratio = s.budgetCents > 0 ? Double(s.totalCents) / Double(s.budgetCents) : 0
        return HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Theme.C.surface, lineWidth: 12)
                Circle().trim(from: 0, to: grown ? min(ratio, 1) : 0)
                    .stroke(ratio > 1 ? Theme.C.danger : Theme.C.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(s.budgetCents > 0 ? "\(Int((ratio * 100).rounded())) %" : "–")
                        .font(.system(.headline, design: .rounded, weight: .bold)).monospacedDigit()
                    Text("vom Budget").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                }
            }
            .frame(width: 104, height: 104)
            VStack(alignment: .leading, spacing: 4) {
                Text("Ausgegeben").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                Text(euro(grown ? s.totalCents : 0)).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.7)
                Text(s.budgetCents > 0 ? "Budget \(euro(s.budgetCents))" : "Kein Budget eingestellt").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                if s.estimatedCents > 0 {
                    Text("davon \(euro(s.estimatedCents)) geschätzt").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                }
                if let pct = s.changePct {
                    Label("\(pct > 0 ? "+" : pct < 0 ? "−" : "±")\(num(abs(pct))) % zum \(Month.name(Month.shift(month, -1), year: false))",
                          systemImage: pct > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(Theme.F.micro).foregroundStyle(pct > 0 ? Theme.C.danger : Theme.C.success)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .card()
        .accessibilityElement(children: .combine)
    }

    /// Ersparnis: Angebote + Bonus (38b) als eigene Spalte.
    private func savedCard(_ s: SpendingDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label { Text("Gespart").font(Theme.F.headline) } icon: { Text("💰") }
                Spacer()
                Text(euro(s.savedCents + s.bonusCents)).font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Theme.C.success)
            }
            HStack(spacing: 10) {
                tile("Angebote", euro(s.savedCents))
                tile("Bonus", euro(s.bonusCents))
            }
        }
        .padding(16)
        .card()
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.F.micro).foregroundStyle(Theme.C.text2)
            Text(value).font(.system(.headline, design: .rounded, weight: .bold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Balken pro Woche (aktuelle Woche dunkler), wachsen beim Erscheinen.
    private func weeksCard(_ s: SpendingDTO) -> some View {
        let top = Double(s.weeks.map(\.totalCents).max() ?? 0) / 100
        let now = Month.week
        return VStack(alignment: .leading, spacing: 12) {
            Text("Pro Woche").font(Theme.F.headline)
            Chart(s.weeks, id: \.week) { w in
                BarMark(x: .value("Woche", "KW \(w.week.suffix(2))"), y: .value("Euro", grown ? Double(w.totalCents) / 100 : 0), width: .ratio(0.6))
                    .foregroundStyle(w.week == now ? Theme.C.accentDeep : Theme.C.accent)
                    .cornerRadius(6)
                    .annotation(position: .top) {
                        if w.totalCents > 0 && grown {
                            Text(euro(w.totalCents)).font(Theme.F.micro).foregroundStyle(Theme.C.text2).monospacedDigit()
                        }
                    }
                    .accessibilityLabel("KW \(w.week.suffix(2))")
                    .accessibilityValue(euro(w.totalCents))
            }
            .chartYScale(domain: 0...max(top * 1.2, 1))
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine().foregroundStyle(Theme.C.line)
                    AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d)) €").font(Theme.F.micro) } }
                }
            }
            .frame(height: 190)
        }
        .padding(16)
        .card()
    }

    /// Torte (Ring) pro Laden (Logos) bzw. Kategorie (Emoji) mit Legende.
    private func pieCard(_ title: String, _ parts: [SpendingDTO.Part], stores: Bool) -> some View {
        let total = max(parts.map(\.totalCents).reduce(0, +), 1)
        func color(_ p: SpendingDTO.Part) -> Color {
            stores ? (p.key.isEmpty ? Theme.C.text3 : Theme.storeColor(p.key)) : Theme.hue(category: p.key).color
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Theme.F.headline)
            HStack(alignment: .center, spacing: 16) {
                Chart(parts, id: \.key) { p in
                    SectorMark(angle: .value("Betrag", p.totalCents), innerRadius: .ratio(0.6), angularInset: 1.5)
                        .cornerRadius(4)
                        .foregroundStyle(color(p))
                }
                .frame(width: 128, height: 128)
                .scaleEffect(grown ? 1 : 0.4)
                .rotationEffect(.degrees(grown ? 0 : -120))
                .opacity(grown ? 1 : 0)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(parts.prefix(6), id: \.key) { p in
                        HStack(spacing: 8) {
                            Circle().fill(color(p)).frame(width: 8, height: 8)
                            if stores {
                                if p.key.isEmpty { Text("🧺").font(.system(size: 15)) } else { StoreLogo(chain: p.key, size: 22) }
                            } else {
                                Text(Theme.hue(category: p.key).emoji).font(.system(size: 15))
                            }
                            Text(stores ? (p.key.isEmpty ? "Ohne Laden" : Labels.chain(p.key)) : Labels.categoryName(p.key))
                                .font(Theme.F.caption).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(Int((Double(p.totalCents) / Double(total) * 100).rounded())) %").font(Theme.F.micro)
                                .foregroundStyle(Theme.C.text2).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(euro(p.totalCents))
                    }
                }
            }
        }
        .padding(16)
        .card()
    }

    /// Top 5 teuerste Artikel.
    private func topCard(_ top: [SpendingDTO.Purchase]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top 5 teuerste").font(Theme.F.headline)
            ForEach(Array(top.enumerated()), id: \.element.id) { i, p in
                HStack(spacing: 12) {
                    Text("\(i + 1)").font(.system(.subheadline, design: .rounded, weight: .bold))
                        .frame(width: 30, height: 30).background(Theme.C.surface, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.name).font(Theme.F.callout).lineLimit(1)
                        HStack(spacing: 6) {
                            if !p.chain.isEmpty { StoreChip(chain: p.chain) }
                            Text(shortDate(p.boughtAt)).font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                            if p.estimated { DealBadge(text: "geschätzt", style: .soft) }
                        }
                    }
                    Spacer(minLength: 4)
                    Text(euro(p.priceCents)).font(.system(.subheadline, weight: .bold)).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                if i < top.count - 1 { Divider() }
            }
        }
        .padding(16)
        .card()
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
        withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) { grown = true }
        let url = await store.spendingCSV(month)
        withAnimation(Theme.spring) { csv = url }
    }
}

/// Start-Karte „🧾 Ausgaben November“ (34) → Monats-Dashboard.
struct SpendingCard: View {
    @Environment(AppStore.self) private var store
    @State private var s: SpendingDTO?

    var body: some View {
        VStack(spacing: 0) {
            if let s {
                let ratio = s.budgetCents > 0 ? min(Double(s.totalCents) / Double(s.budgetCents), 1) : 0
                NavigationLink { SpendingView() } label: {
                    HStack(spacing: 14) {
                        Text("🧾").font(.system(size: 26)).frame(width: 52, height: 52)
                            .background(Theme.C.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ausgaben \(Month.name(s.month, year: false))").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                            Text(s.budgetCents > 0 ? "\(euro(s.totalCents)) von \(euro(s.budgetCents))" : euro(s.totalCents))
                                .font(.system(.headline, design: .rounded, weight: .bold)).monospacedDigit().foregroundStyle(Theme.C.text1)
                            ProgressView(value: ratio).tint(s.totalCents > s.budgetCents && s.budgetCents > 0 ? Theme.C.danger : Theme.C.accent)
                        }
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.C.text3)
                    }
                    .padding(16)
                    .card()
                }
                .buttonStyle(PressableStyle())
                .transition(.opacity)
            }
        }
        .animation(Theme.spring, value: s)
        .task(id: store.householdList?.items.filter(\.checked).count) { s = (try? await store.spending(Month.current)) ?? s }
    }
}
