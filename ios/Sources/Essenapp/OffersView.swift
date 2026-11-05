import SwiftUI
import UIKit
import CoreLocation

/// S4 Angebote v9 Variante C „Ein Markt im Fokus“ (docs/ui/mockups/v9-parts/c.html): runde Markt-Knöpfe, blaue Bühne des
/// gewählten Markts, Kategorie-Pillen, Kacheln nach Nutzen. Dazu Wochen-Umschalter, Filter-Sheet, Drogerie-Monatsaktionen,
/// Leer-Zustände und Umschalter zur Merkliste (S10, `WatchListView`).
struct OffersView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("offers.chain") private var chain: String?  // Auswahl merken (19.4), nil = „Alle“
    @AppStorage("offers.category") private var category: String?
    @AppStorage("offers.subcategory") private var subcategory: String?
    @State private var search = ""
    @State private var watchMode = ["watch", "scanner", "watchedit", "watchsearch"].contains(Demo.screen ?? "")
    @State private var nextWeek = Demo.screen == "nextweek"  // Vorschau (30)
    @State private var realOnly = false  // „Nur echte Angebote“ (28)
    @State private var bio = false  // 49
    @State private var vegan = Demo.screen == "offersempty"
    @State private var nutri = Demo.screen == "offersempty"
    @State private var bonusOnly = Demo.screen == "offersempty"  // Rewe-Bonus-Aktionen (39)
    @State private var forYou = false  // Pille „Für dich“: nur Angebote aus dem Wochenplan
    @State private var allDeals = false  // „alle N →“ bei „Größte Rabatte“
    @State private var filtering = Demo.screen == "offersfilter"
    @State private var pull: CGFloat = 0
    @State private var refreshing = false
    @State private var fresh: Set<Int> = []  // nach dem Aktualisieren neu dazugekommen (a2-pull)
    @State private var fly: OfferFly?

    /// Maße aus dem Mockup (v9 c.html, Variante C).
    private enum L {
        static let top: CGFloat = 14  // .scr 66 − 52
        static let pullAt: CGFloat = 110  // so weit ziehen, dann lädt es
        static let hold: CGFloat = 120  // Liste bleibt beim Laden so weit unten (a2-pull)
        static let emptyGap: CGFloat = 372  // Leer-Text bei y 556, gemessen ab Chip-Reihe
        static let market: CGFloat = 64  // .c9-cb .r
        static let marketWidth: CGFloat = 70
        static let marketPad: CGFloat = 9
        static let allArt: CGFloat = 52
        static let stageHeight: CGFloat = 178  // .c9-stage
        static let stageRadius: CGFloat = 80
        static let stageText: CGFloat = 210
        static let stageArt: CGFloat = 150
        static let logoPill: CGFloat = 42
        static let logo = CGSize(width: 90, height: 22)
        static let pill: CGFloat = 44  // .c9-pc
        static let pillArt: CGFloat = 34
        static let gridGap: CGFloat = 10  // .c9-g2
        static let topDeals = 6  // „Größte Rabatte“ zugeklappt
    }

    private enum Empty { case nextWeek, none, filter }

    var body: some View {
        Group {
            if watchMode {
                WatchListView { withAnimation(Theme.spring) { watchMode = false } }
            } else {
                offersScreen
            }
        }
        .onAppear {
            if store.demo {
                category = Demo.screen == "drogerie" ? "drogerie" : nil; subcategory = nil
                chain = Demo.screen == "offersempty" ? "aldi_sued" : nil  // kein Aldi-Angebot erfüllt alle Filter
            }
        }
    }

    private func matches(_ o: OfferDTO) -> Bool {
        (chain == nil || o.chain == chain) && (category == nil || o.category == category)
            && (subcategory == nil || o.subcategory == subcategory)
            && (search.isEmpty || o.title.localizedCaseInsensitiveContains(search))
            && (!realOnly || o.verdict != "kein_echtes") && (!bio || o.bio == true) && (!vegan || o.vegan == true)
            && (!nutri || ["A", "B"].contains(o.nutriScore ?? "")) && (!bonusOnly || (o.bonusCents ?? 0) > 0)
    }

    private var activeFilters: Int {
        [realOnly, bio, vegan, nutri, bonusOnly, !search.isEmpty, chain != nil].filter { $0 }.count
    }

    /// Angebots-ID → Gericht im Wochenplan, das die Zutat nutzt („Passt zu deiner Woche“).
    private var plannedDishes: [Int: String] {
        var map: [Int: String] = [:]
        for m in store.plan?.entries ?? [] {
            for i in m.recipe.ingredients { if let id = i.offerId, map[id] == nil { map[id] = m.recipe.title } }
        }
        return map
    }

    private var offersScreen: some View {
        let all = (nextWeek ? store.nextOffers : store.offers).filter { $0.category != "nonfood" }  // Möbel, Technik … (19.1)
        let planned = plannedDishes
        let filtered = all.filter(matches).filter { o in !forYou || planned[o.id] != nil }
        let drug = category == "drogerie" && !nextWeek  // Monatsaktionen (59)
        let monthly = drug ? filtered.filter { o in o.monthly == true } : []
        let rows = drug ? filtered.filter { o in o.monthly != true } : filtered
        let empty: Empty? = nextWeek && store.nextOffers.isEmpty ? .nextWeek
            : all.isEmpty ? .none : rows.isEmpty && monthly.isEmpty ? .filter : nil
        return GeometryReader { g in
            ScrollView {
                content(all: all, rows: rows, monthly: monthly, drug: drug, empty: empty, planned: planned)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, g.safeAreaInsets.top + L.top)
                    .padding(.bottom, Theme.S.nav)
                    .modifier(OffersForms(empty: empty != nil, refreshing: refreshing))
                    .padding(.top, refreshing ? L.hold : 0)
                    .onGeometryChange(for: CGFloat.self) { p in p.frame(in: .scrollView).minY } action: { y in
                        pull = max(0, y)
                        if y > L.pullAt { refresh() }
                    }
            }
            .scrollDismissesKeyboard(.immediately)
            .overlay(alignment: .top) { PullPeek(pull: pull, refreshing: refreshing, threshold: L.pullAt) }
            .ignoresSafeArea(edges: .top)
        }
        .overlay { if let fly { OfferFlight(fly: fly) } }
        .task(id: fly?.start) {
            guard fly != nil else { return }
            try? await Task.sleep(for: .seconds(0.6))
            fly = nil
        }
        .sheet(isPresented: $filtering) { filterSheet(all: all, count: filtered.count).presentationDetents([.medium, .large]) }
    }

    // MARK: Inhalt

    @ViewBuilder
    private func content(all: [OfferDTO], rows: [OfferDTO], monthly: [OfferDTO], drug: Bool, empty: Empty?,
                         planned: [Int: String]) -> some View {
        let weekRow = !store.nextOffers.isEmpty || nextWeek
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink { StoreMapView() } label: {
                Text(headline)
                    .font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                    .padding(.vertical, 12).contentShape(Rectangle()).padding(.vertical, -12)  // Tap-Fläche 44
            }
            .buttonStyle(.plain)
            .accessibilityHint("Läden und Umkreis ändern")
            HStack {
                Text("Angebote").font(Theme.F.t1).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                filterButton  // ohne Mockup: Suche und Filter bleiben erreichbar
            }

            if empty == .filter {
                filterChips.padding(.top, 16)
            } else {
                if weekRow { weekChips.padding(.top, 8) }
                if empty == nil {
                    marketRow(all).padding(.top, 14)
                    stage(all)
                }
                categoryPills(all: all, planned: planned).padding(.top, 16)
                subcategoryRow(all: all)
            }

            if realOnly && !all.contains(where: { o in Verdict.pill(o.verdict) != nil }) {
                HintRow(icon: .chart, title: "Noch zu wenig Preisdaten.",
                        text: "Ab 3 Wochen greift „Nur echte Angebote“ – bis dahin siehst du alle.")
                    .padding(.top, 16)
            }

            if let empty {
                emptyBlock(empty)
            } else {
                if drug { drugstore(monthly: monthly) }
                sections(rows, planned: planned)
            }
        }
    }

    /// „24118 · KW 45 · 2.11.–8.11.“ (Woche Mo–So, bei „Nächste Woche“ die folgende).
    private var headline: String {
        let cal = Calendar(identifier: .iso8601)
        let day = cal.date(byAdding: .day, value: nextWeek ? 7 : 0, to: .now) ?? .now
        var parts = [store.household?.plz ?? "", "KW \(cal.component(.weekOfYear, from: day))"]
        if let start = cal.dateInterval(of: .weekOfYear, for: day)?.start, let end = cal.date(byAdding: .day, value: 6, to: start) {
            let dm = { (d: Date) in "\(cal.component(.day, from: d)).\(cal.component(.month, from: d))." }
            parts.append("\(dm(start))–\(dm(end))")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Diese / nächste Woche (S4 Nächste Woche).
    private var weekChips: some View {
        HStack(spacing: 6) {
            SmallChip(title: "Diese Woche \(store.offers.count)", on: !nextWeek, compact: true) {
                withAnimation(Theme.spring) { nextWeek = false }
            }
            SmallChip(title: "Nächste Woche \(store.nextOffers.count)", on: nextWeek, compact: true,
                      badge: store.nextOffers.isEmpty ? nil : "neu") {
                withAnimation(Theme.spring) { nextWeek = true }
            }
        }
    }

    // MARK: Märkte (.c9-cb) und Bühne (.c9-stage)

    /// Runde Logo-Knöpfe zum Wischen: „Alle“ + jeder Markt mit Angeboten. Immer genau einer gewählt.
    private func marketRow(_ all: [OfferDTO]) -> some View {
        let chains = Labels.chains.map(\.key).filter { c in all.contains { $0.chain == c } }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 6) {
                marketButton(nil, count: all.count)
                ForEach(chains, id: \.self) { c in marketButton(c, count: all.filter { $0.chain == c }.count) }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 4)  // Ring ragt über den Kreis
        }
        .padding(.horizontal, -Theme.pagePadding)
    }

    private func marketButton(_ c: String?, count: Int) -> some View {
        let on = chain == c
        let ring: CGFloat = on ? 3 : Theme.S.hair
        let name = c.map(Labels.chain) ?? "Alle"
        return Button { withAnimation(Theme.spring) { chain = c; subcategory = nil } } label: {
            VStack(spacing: 0) {
                Group {
                    if let c {
                        RemoteImage(url: Labels.logoURL(c), dim: false) {
                            Text(String(name.prefix(2))).font(Theme.F.text(14, .extrabold, relativeTo: .footnote))
                        }
                        .padding(L.marketPad)
                        .frame(width: L.market, height: L.market)
                        .background(Theme.C.plate, in: Circle())
                    } else {
                        Ill("binoculars").frame(width: L.allArt)
                            .frame(width: L.market, height: L.market)
                            .background(Theme.C.blue1, in: Circle())
                    }
                }
                .clipShape(Circle())
                .overlay(Circle().stroke(on ? Theme.C.ink : Theme.C.line, lineWidth: ring).padding(-ring / 2))
                Text(name).font(Theme.F.text(11.5, .bold, relativeTo: .caption)).lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.top, 7)
                Text("\(count)").font(Theme.F.text(11, .bold, relativeTo: .caption2)).foregroundStyle(Theme.C.ink2)
            }
            .foregroundStyle(Theme.C.ink)
            .frame(width: L.marketWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(c == nil ? "Alle Märkte" : name), \(count) Angebote")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Blaue Bühne des gewählten Markts: Logo, Anzahl, Gültigkeit, Filiale (wenn bekannt). Bei „Alle“: Zahl der Läden.
    private func stage(_ all: [OfferDTO]) -> some View {
        let mine = all.filter { o in chain == nil || o.chain == chain }
        let label = ["Angebote", validity(mine)].compactMap { $0 }.joined(separator: "\n")
        return VStack(alignment: .leading, spacing: 0) {
            Group {
                if let chain {
                    RemoteImage(url: Labels.logoURL(chain), dim: false) {
                        Text(Labels.chain(chain)).font(Theme.F.text(14, .extrabold, relativeTo: .footnote))
                    }
                    .frame(maxWidth: L.logo.width, maxHeight: L.logo.height)
                } else {
                    Text("Alle Märkte").font(Theme.F.text(14, .extrabold, relativeTo: .footnote))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: L.logoPill)
            .background(Theme.C.plate, in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chain.map(Labels.chain) ?? "Alle Märkte")
            StatNumber(label: label, value: "\(mine.count)", size: 46).padding(.top, 14)
            if let line = branchLine {
                Text(line).font(Theme.F.text(12.5, .semibold, relativeTo: .footnote)).lineLimit(1).padding(.top, 8)
            }
        }
        .foregroundStyle(Theme.C.ink)
        .frame(width: L.stageText, alignment: .leading)
        .padding(.vertical, 20)
        .padding(.horizontal, Theme.pagePadding)
        .frame(maxWidth: .infinity, minHeight: L.stageHeight, alignment: .topLeading)
        .background(alignment: .topTrailing) { Ill("shopper").frame(width: L.stageArt).offset(x: 6, y: 6) }
        .background(Theme.C.blue)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: L.stageRadius))
        .padding(.horizontal, -Theme.pagePadding)
        .padding(.top, 16)
    }

    /// „bis Sa 8.11.“ – häufigstes Ende der Angebote (nächste Woche: häufigster Beginn).
    private func validity(_ offers: [OfferDTO]) -> String? {
        let days = offers.map { nextWeek ? $0.validFrom : $0.validTo }
        guard let top = Dictionary(grouping: days, by: { $0 }).max(by: { ($0.value.count, $0.key) < ($1.value.count, $1.key) })?.key
        else { return nil }
        return (nextWeek ? "ab " : "bis ") + weekdayDay(top)
    }

    /// „Rewe Holtenauer Str. 12 · 1,2 km“ aus der eingestellten Filiale; bei „Alle“ „5 Läden“.
    private var branchLine: String? {
        guard let chain else {
            let n = store.household?.stores.filter(\.enabled).count ?? 0
            return n > 0 ? "\(n) Läden" : nil
        }
        guard let shop = store.household?.stores.first(where: { $0.chain == chain && $0.enabled }) else { return nil }
        let street = shop.address.flatMap { a in a.split(separator: ",").first.map { "\(Labels.chain(chain)) \($0)" } }
        var km: String?
        if let a = shop.lat, let b = shop.lng, let h = store.household, let la = h.lat, let lo = h.lng {
            km = "\(num(CLLocation(latitude: a, longitude: b).distance(from: CLLocation(latitude: la, longitude: lo)) / 1000)) km"
        }
        let parts = [street ?? (shop.storeName.isEmpty ? nil : shop.storeName), km].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Kategorien (.c9-pc)

    /// Für dich · Kategorien mit Treffern im gewählten Markt · Merkliste. Antippen = an/aus.
    private func categoryPills(all: [OfferDTO], planned: [Int: String]) -> some View {
        let mine = all.filter { o in chain == nil || o.chain == chain }
        let fits = mine.filter { planned[$0.id] != nil }.count
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if fits > 0 || forYou {
                    pill("Für dich", count: fits, on: forYou, tint: Theme.C.blue) { Icon(.sparkle, size: 20) } action: {
                        forYou.toggle()
                        if forYou { category = nil; subcategory = nil }
                    }
                }
                ForEach(Labels.categories, id: \.0) { c in
                    let n = mine.filter { $0.category == c.0 }.count
                    if n > 0 {
                        pill(c.1.split(separator: " ").dropFirst().joined(separator: " "), count: n, on: category == c.0,
                             tint: Theme.hue(category: c.0).tint) { categoryArt(c.0) } action: {
                            category = category == c.0 ? nil : c.0; subcategory = nil; forYou = false
                        }
                    }
                }
                pill("Merkliste", count: store.watches.isEmpty ? nil : store.watches.count, on: false, tint: Theme.C.rose) {
                    Icon(.heart, size: 20)
                } action: { watchMode = true }
            }
            .padding(.horizontal, Theme.pagePadding)
        }
        .padding(.horizontal, -Theme.pagePadding)
    }

    /// Zeichnung je Kategorie (`ill/`); ohne passende Zeichnung das Etikett-Symbol.
    @ViewBuilder
    private func categoryArt(_ c: String) -> some View {
        if let ill = ["obst_gemuese": "tomato", "kuehlung": "fridge", "vorrat": "pot", "drogerie": "bag"][c] {
            Ill(ill)
        } else {
            Icon(.tag, size: 20)
        }
    }

    private func pill<Art: View>(_ title: String, count: Int?, on: Bool, tint: Color, @ViewBuilder art: () -> Art,
                                 action: @escaping () -> Void) -> some View {
        Button { withAnimation(Theme.spring) { action() } } label: {
            HStack(spacing: 8) {
                art().frame(width: L.pillArt, height: L.pillArt)
                Text(title).font(Theme.F.text(13.5, .extrabold, relativeTo: .footnote))
                if let count {
                    Text("\(count)").font(Theme.F.text(12, .bold, relativeTo: .caption)).foregroundStyle(on ? Theme.C.ink3 : Theme.C.ink2)
                }
            }
            .lineLimit(1)
            .foregroundStyle(on ? Theme.C.onInk : Theme.C.ink)
            .padding(.leading, 6).padding(.trailing, 16)
            .frame(height: L.pill)
            .background(on ? Theme.C.ink : tint, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Feine Kategorien der gewählten Kategorie (19.4): Joghurt ≠ Käse. Ohne Mockup, im Stil `.c-chip`.
    @ViewBuilder
    private func subcategoryRow(all: [OfferDTO]) -> some View {
        if let category {
            let inCat = all.filter { o in o.category == category && (chain == nil || o.chain == chain) }
            let subs = Labels.subcategories.filter { s in inCat.contains { $0.subcategory == s.0 } }
            if subs.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(subs, id: \.0) { s in
                            SmallChip(title: "\(s.1) \(inCat.filter { $0.subcategory == s.0 }.count)", on: subcategory == s.0) {
                                withAnimation(Theme.spring) { subcategory = subcategory == s.0 ? nil : s.0 }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                }
                .padding(.horizontal, -Theme.pagePadding)
                .padding(.top, 8)
            }
        }
    }

    // MARK: Kacheln nach Nutzen (.c9-g2)

    /// „Passt zu deiner Woche“ (Zutat im Plan) · „Größte Rabatte“ · übrige Angebote.
    @ViewBuilder
    private func sections(_ rows: [OfferDTO], planned: [Int: String]) -> some View {
        let byDeal: (OfferDTO, OfferDTO) -> Bool = { ($0.discount ?? 0) > ($1.discount ?? 0) }
        let week = rows.filter { planned[$0.id] != nil }.sorted(by: byDeal)
        let others = rows.filter { planned[$0.id] == nil }
        let deals = others.filter { $0.discount != nil }.sorted(by: byDeal)
        let shown = allDeals ? deals : Array(deals.prefix(L.topDeals))
        let shownIDs = Set(shown.map(\.id))
        let rest = others.filter { !shownIDs.contains($0.id) }
        VStack(alignment: .leading, spacing: 0) {
            if !week.isEmpty {
                sectionHead("Passt zu deiner Woche") { Text("Rabatt ↓") }
                grid(week, planned: planned)
            }
            if !deals.isEmpty {
                sectionHead("Größte Rabatte") {
                    if deals.count > L.topDeals {
                        Button { withAnimation(Theme.spring) { allDeals.toggle() } } label: {
                            Text(allDeals ? "weniger ↑" : "alle \(deals.count) →")
                                .padding(.vertical, 12).contentShape(Rectangle()).padding(.vertical, -12)  // Tap-Fläche 44
                        }
                        .buttonStyle(.plain)
                    }
                }
                grid(shown, planned: planned)
            }
            if !rest.isEmpty {
                if !week.isEmpty || !deals.isEmpty { sectionHead("Weitere Angebote") { EmptyView() } }  // ohne Mockup
                grid(rest, planned: planned).padding(.top, week.isEmpty && deals.isEmpty ? 22 : 0)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: rows.map(\.id))
    }

    private func sectionHead<Trail: View>(_ title: String, @ViewBuilder trail: () -> Trail) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Theme.F.serif(22)).foregroundStyle(Theme.C.ink).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trail().font(Theme.F.text(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
        }
        .padding(.top, 22)
        .padding(.bottom, 10)
    }

    private func grid(_ offers: [OfferDTO], planned: [Int: String]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: L.gridGap, alignment: .top), count: 2), spacing: L.gridGap) {
            ForEach(offers) { o in
                NavigationLink { OfferDetailView(offer: o) } label: {
                    OfferTile(offer: o, dish: planned[o.id], fresh: fresh.contains(o.id)) { frame in
                        if !reduceMotion { fly = OfferFly(offer: o, from: frame, start: .now) }
                    }
                }
                .buttonStyle(PressableStyle())
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
    }

    /// S4 Leer: aktive Filter als Chips (antippen = an/aus), darunter der Leer-Text.
    private var filterChips: some View {
        let toggles: [(String, Icon8?, Binding<Bool>)] = [
            ("Vegan", .leaf, $vegan), ("Nutri A/B", nil, $nutri), ("Bonus", .gift, $bonusOnly), ("Bio", nil, $bio),
            ("Nur echte", nil, $realOnly),
        ]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let c = category {
                    SmallChip(title: Labels.categories.first { $0.0 == c }.map { String($0.1.split(separator: " ").dropFirst().joined(separator: " ")) } ?? c,
                              on: true) { withAnimation(Theme.spring) { category = nil; subcategory = nil } }
                }
                if let c = chain { SmallChip(title: Labels.chain(c), on: true) { withAnimation(Theme.spring) { chain = nil } } }
                if forYou { SmallChip(title: "Für dich", on: true) { withAnimation(Theme.spring) { forYou = false } } }
                if !search.isEmpty { SmallChip(title: "„\(search)“", on: true) { withAnimation(Theme.spring) { search = "" } } }
                ForEach(Array(toggles.sorted { $0.2.wrappedValue && !$1.2.wrappedValue }.enumerated()), id: \.element.0) { _, t in
                    SmallChip(title: t.0, on: t.2.wrappedValue, icon: t.1) { withAnimation(Theme.spring) { t.2.wrappedValue.toggle() } }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
        }
        .padding(.horizontal, -Theme.pagePadding)
    }

    private var filterButton: some View {
        Button { filtering = true } label: {
            FilterIcon().stroke(style: StrokeStyle(lineWidth: Theme.S.iconStroke, lineCap: .round))
                .frame(width: 18, height: 18)
                .foregroundStyle(Theme.C.ink)
                .frame(width: 36, height: 36)
                .overlay(Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
                .overlay(alignment: .topTrailing) {
                    if activeFilters > 0 {
                        Text("\(activeFilters)").font(Theme.F.deal).foregroundStyle(Theme.C.onInk)
                            .padding(.horizontal, 6).frame(height: 18)
                            .background(Theme.C.ink, in: Capsule())
                            .offset(x: 6, y: -6)
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(activeFilters > 0 ? "Suche und Filter, \(activeFilters) aktiv" : "Suche und Filter")
    }

    @ViewBuilder
    private func emptyBlock(_ empty: Empty) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch empty {
            case .filter:
                Text("Keine Angebote für diesen Filter").font(Theme.F.t2)
                emptyText("Nimm einen Filter raus – oder schau Donnerstag wieder rein, dann kommen neue Prospekte.")
                OutlineButton(title: "Filter zurücksetzen", icon: .refresh) { withAnimation(Theme.spring) { resetFilters() } }
                    .fixedSize(horizontal: true, vertical: false).padding(.top, 16)
            case .nextWeek:
                Text("Noch keine Prospekte für nächste Woche").font(Theme.F.t2)
                emptyText("Die meisten Läden zeigen sie ab Donnerstag oder Freitag – wir laden sie automatisch.")
            case .none:
                Text(refreshing ? "Prospekte werden geladen …" : "Noch keine Angebote").font(Theme.F.t2)
                emptyText("Die Angebote deiner Läden werden wöchentlich geladen.")
                if !refreshing {
                    OutlineButton(title: "Jetzt laden", icon: .refresh) { refresh() }
                        .fixedSize(horizontal: true, vertical: false).padding(.top, 16)
                }
            }
        }
        .padding(.top, L.emptyGap)
    }

    private func emptyText(_ text: String) -> some View {
        Text(text).font(Theme.F.text(15, .semibold, relativeTo: .body)).lineSpacing(2).foregroundStyle(Theme.C.ink2)
            .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
    }

    private func resetFilters() {
        realOnly = false; bio = false; vegan = false; nutri = false; bonusOnly = false; forYou = false
        search = ""; chain = nil; category = nil; subcategory = nil
    }

    /// S4 Drogerie: Monatsaktionen von dm/Rossmann nebeneinander; die übrigen Angebote folgen als Kacheln.
    private func drugstore(monthly: [OfferDTO]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Icon(.cal, size: 16)
                SectionLabel("Monatsaktionen", big: true)
                Spacer()
                Text(Date.now.formatted(.dateTime.month(.wide).locale(.de))).font(Theme.F.text(12, .extrabold, relativeTo: .caption))
            }
            .foregroundStyle(Theme.C.ink2)
            .padding(.top, 30)
            if monthly.isEmpty {
                Text("Gerade keine Monatsaktion bei dm oder Rossmann.").font(Theme.F.text(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Theme.C.ink2).padding(.top, 10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 15) {
                        ForEach(Array(monthly.enumerated()), id: \.element.id) { i, o in
                            NavigationLink { OfferDetailView(offer: o) } label: { MiniOffer(offer: o, tint: MiniOffer.tints[i % 3]) }
                                .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                }
                .padding(.horizontal, -Theme.pagePadding)
                .padding(.top, 10)
            }
        }
    }

    /// Ziehen zum Aktualisieren (a2-pull): Liste bleibt unten, Fernglas schaut hervor, neue Angebote ploppen ein.
    private func refresh() {
        guard !refreshing else { return }
        let before = Set((nextWeek ? store.nextOffers : store.offers).map(\.id))
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6)) { refreshing = true }
        Task {
            await store.refreshOffers()
            await store.loadWatch()
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.75)) { refreshing = false }
            let now = Set((nextWeek ? store.nextOffers : store.offers).map(\.id))
            fresh = before.isEmpty ? [] : now.subtracting(before)
        }
    }

    // MARK: Filter-Sheet (S4 Filter)

    private func filterSheet(all: [OfferDTO], count: Int) -> some View {
        let chains = Labels.chains.map(\.key).filter { c in all.contains { $0.chain == c } }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Filter").font(Theme.F.t2)
                    Spacer()
                    CloseButton { filtering = false }
                }
                // ohne Mockup: Suche und Laden (vorher im Such-Sheet, 19.4)
                FieldBox(icon: .search) { TextField("Produkt suchen", text: $search).submitLabel(.search) }
                    .padding(.top, 24)
                if chains.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Chip8(title: "Alle Läden", on: chain == nil) { withAnimation(Theme.spring) { chain = nil } }
                            ForEach(chains, id: \.self) { c in
                                Chip8(title: Labels.chain(c), on: chain == c) { withAnimation(Theme.spring) { chain = chain == c ? nil : c } }
                            }
                        }
                        .padding(.horizontal, Theme.pagePadding)
                    }
                    .padding(.horizontal, -Theme.pagePadding)
                    .padding(.top, 12)
                }
                VStack(spacing: 0) {
                    switchRow("Nur echte Angebote", "blendet Scheinangebote aus", $realOnly)
                    switchRow("Bio", nil, $bio)
                    switchRow("Vegan", nil, $vegan)
                    switchRow("Nutri-Score A oder B", nil, $nutri)
                    let bonus = all.filter { o in (o.bonusCents ?? 0) > 0 }.count
                    switchRow("Bonus-Aktionen", bonus > 0 ? "\(bonus) Angebote mit Bonus" : nil, $bonusOnly)
                }
                .padding(.top, 24)
                PrimaryButton(title: count == 1 ? "1 Angebot zeigen" : "\(count) Angebote zeigen") { filtering = false }
                    .padding(.top, 28)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 40)
        }
        .sheet8()
    }

    private func switchRow(_ title: String, _ sub: String?, _ on: Binding<Bool>) -> some View {
        Toggle(isOn: on.animation(Theme.spring)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.F.text(16, .bold, relativeTo: .body)).foregroundStyle(Theme.C.ink)
                if let sub { Text(sub).font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2) }
            }
        }
        .toggleStyle(.v8)
        .padding(.vertical, 11)
        .overlay(alignment: .top) { Hairline() }
    }
}

// MARK: Rand-Formen S4

/// Leer-Zustände: Kreis + Fernglas (beim Laden der Topf). Mockup-Koordinaten.
private struct OffersForms: ViewModifier {
    let empty: Bool
    let refreshing: Bool

    func body(content: Content) -> some View {
        if empty {
            content
                .pinned(left: 70, top: 290) {
                    if refreshing { PotLoader() } else { Ill("binoculars").frame(width: 240) }
                }
                .edgeForm(.circle, Theme.C.blue1, width: 440, height: 440, left: -70, top: 300)
        } else {
            content
        }
    }
}

/// Fernglas im blauen Kreis, das beim Ziehen von oben hereinschaut und beim Laden schaukelt (a2-pull).
private struct PullPeek: View {
    let pull: CGFloat
    let refreshing: Bool
    let threshold: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sway = false

    var body: some View {
        let p = refreshing ? 1 : min(1, pull / threshold)
        Color.clear
            .frame(width: 72, height: 72)
            .overlay(alignment: .topLeading) {
                Ill("binoculars").frame(width: 170)
                    .rotationEffect(.degrees(sway && !reduceMotion ? 7 : -7 * (refreshing && !reduceMotion ? 1 : 0)), anchor: UnitPoint(x: 0.5, y: 0.92))
                    .offset(x: -50, y: 3 + (refreshing ? 0 : 60))
            }
            .background(Circle().fill(Theme.C.blue))
            .clipShape(Circle())
        .scaleEffect(0.6 + 0.4 * p)
        .offset(y: refreshing ? -8 : -140 * (1 - p))
        .padding(.top, 56)
        .opacity(p > 0 ? 1 : 0)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: refreshing)
        .onChange(of: refreshing) { _, on in
            if on, !reduceMotion {
                withAnimation(.easeInOut(duration: 0.65).repeatForever().delay(0.4)) { sway = true }
            } else {
                withAnimation(.default) { sway = false }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(!refreshing)
        .accessibilityLabel("Angebote werden geladen")
    }
}

/// Filter-Symbol des Mockups (`#c-filter`: M4 7h16 M7 12h10 M10 17h4).
private struct FilterIcon: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 24
        var p = Path()
        for (x0, x1, y) in [(4.0, 20.0, 7.0), (7, 17, 12), (10, 14, 17)] {
            p.move(to: CGPoint(x: r.minX + x0 * s, y: r.minY + y * s))
            p.addLine(to: CGPoint(x: r.minX + x1 * s, y: r.minY + y * s))
        }
        return p
    }
}

// MARK: Bausteine Angebote (auch für Merkliste, Zutaten-Sheet)

/// Kleiner Chip (`.c-chip`): 32 hoch, 13/700; `compact` = Wochen-Pillen (Padding 10, 12,5). Optional `.deal`-Marke.
struct SmallChip: View {
    let title: String
    var on = false
    var icon: Icon8?
    var compact = false
    var badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Icon(icon, size: 16) }
                Text(title).lineLimit(1)
                if let badge { DealPill(text: badge) }
            }
            .font(Theme.F.text(compact ? 12.5 : 13, .bold, relativeTo: .footnote))
            .foregroundStyle(on ? Theme.C.onInk : Theme.C.ink2)
            .padding(.horizontal, compact ? 10 : 12)
            .frame(height: 32)
            .background(on ? Theme.C.ink : .clear, in: Capsule())
            .overlay { if !on { Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Ruhiger Hinweis zwischen zwei Linien (S4 „Händler nicht erreichbar“): Kreis 36 in `warn`, fett + grau.
struct HintRow: View {
    let icon: Icon8
    let title: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Icon(icon, size: 18).frame(width: 36, height: 36).background(Theme.C.warn, in: Circle())
            (Text(title).font(Theme.F.text(13, .bold, relativeTo: .footnote)) + Text("\n")
                + Text(text).font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.C.ink)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Hairline() }
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .combine)
    }
}

/// Händler-Logo auf Kreis (`.c-lg`, echte Logos von Wikimedia, nur verlinkt, E44). Ohne Logo: Kürzel.
struct LogoCircle: View {
    let chain: String
    var size: CGFloat = 48
    var tint: Color = Theme.C.plate

    var body: some View {
        RemoteImage(url: Labels.logoURL(chain), dim: false) {
            Text(String(Labels.chain(chain).prefix(2))).font(Theme.F.text(size > 60 ? 20 : 14, .extrabold, relativeTo: .footnote))
                .foregroundStyle(Theme.C.ink)
        }
        .frame(width: size * (size > 60 ? 46 : 34) / (size > 60 ? 72 : 48))
        .frame(width: size, height: size)
        .background(tint, in: Circle())
        .clipShape(Circle())
        .accessibilityLabel(Labels.chain(chain))
    }
}

/// Zeichnung zur Ware (Tusche, `ill/`): nach Stichwort im Titel, sonst Produktfoto, sonst Tasche.
struct OfferArt: View {
    let title: String
    let url: String

    /// Prospektfoto (eckig, mit Preis-Aufdruck): ganz sichtbar auf weißem Plättchen statt der Zeichnung.
    static let photoRadius: CGFloat = 18
    static let photoInset: CGFloat = 8

    static func hasPhoto(_ title: String, url: String) -> Bool { ill(title) == nil && !url.isEmpty }

    var body: some View {
        if let ill = Self.ill(title) {
            Ill(ill)
        } else if url.isEmpty {
            Ill("bag")
        } else {
            RemoteImage(url: URL(string: url)) { Ill("bag") }
                .padding(Self.photoInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.C.plate, in: RoundedRectangle(cornerRadius: Self.photoRadius, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: Self.photoRadius, style: .continuous))
                .softShadow()
        }
    }

    static func ill(_ title: String) -> String? {
        let t = title.lowercased()
        let map = [("tomat", "tomato"), ("knoblauch", "garlic"), ("basilikum", "basil"), ("spaghetti", "pasta"), ("nudel", "pasta"),
                   ("pasta", "pasta"), ("penne", "pasta"), ("fusilli", "pasta"), ("tagliatelle", "pasta")]
        return map.first { t.contains($0.0) }?.1
    }

    /// Formfarbe wie im Mockup (Tomate rosé, Knoblauch sand, Basilikum salbei, Nudeln blau), sonst nach Kategorie.
    static func tint(_ title: String, category: String) -> Color {
        switch ill(title) {
        case "tomato": Theme.C.rose
        case "garlic": Theme.C.sand
        case "basil": Theme.C.sage
        case "pasta": Theme.C.blue1
        default: Theme.hue(category: category).tint
        }
    }
}

/// Angebotskachel (v9 `.c9-tc`): Fläche `card`, Bildfeld in Formfarbe mit Zeichnung oder Produktfoto auf weißem Plättchen,
/// Rabatt oben links, „+“ unten rechts = Zur Liste (a1-add), Name, Preis mit altem Preis, Menge · Frist, Gericht aus dem Plan.
struct OfferTile: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let offer: OfferDTO
    var dish: String?  // „Passt zu deiner Woche“: Gericht, das die Zutat nutzt
    var fresh = false  // „neu“ nach dem Aktualisieren
    var onAdd: ((CGRect) -> Void)?  // Rahmen der Zeichnung (global) für den Flug zum Einkauf-Symbol
    @State private var artFrame: CGRect = .zero
    @State private var gone = false

    private enum L {
        static let pad: CGFloat = 8  // .c9-tc padding 8 8 12
        static let padBottom: CGFloat = 12
        static let photoHeight: CGFloat = 104
        static let photoRadius: CGFloat = 18
        static let art: CGFloat = 80
        static let photo: CGFloat = 92  // weißes Plättchen
        static let text: CGFloat = 4
        static let plus: CGFloat = 32
        static let plusRing: CGFloat = 3
        static let plusOffset = CGSize(width: -2, height: 18)  // Kreis 32: rechts 8, unten −12; Tap-Fläche 44
    }

    var body: some View {
        let onList = store.isOnList(offer)
        let photo = OfferArt.hasPhoto(offer.title, url: offer.imageUrl)
        let size = photo ? L.photo : L.art
        let sub = [offer.amountText, offer.startsLater ? "ab \(weekdayDay(offer.validFrom))" : "bis \(weekdayDay(offer.validTo))"]
            .compactMap { $0 }.joined(separator: " · ")
        VStack(alignment: .leading, spacing: 0) {
            OfferArt(title: offer.title, url: offer.imageUrl)
                .frame(width: size, height: size)
                .onGeometryChange(for: CGRect.self) { g in g.frame(in: .global) } action: { f in artFrame = f }
                .opacity(gone ? 0 : 1).scaleEffect(gone ? 0.6 : 1)
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity)
                .frame(height: L.photoHeight)
                .background(OfferArt.tint(offer.title, category: offer.category),
                            in: RoundedRectangle(cornerRadius: L.photoRadius, style: .continuous))
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 4) {
                        if let d = offer.discount { DealPill(text: "−\(d) %") }
                        if fresh { SoftPill(text: "neu") }
                    }
                    .padding(L.pad)
                }
                .overlay(alignment: .bottomTrailing) { plus(onList).offset(L.plusOffset) }
            Text(offer.title).font(Theme.F.serif(17, relativeTo: .headline)).lineLimit(2)
                .padding(.top, 10).padding(.horizontal, L.text)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(euro(offer.priceCents)).font(Theme.F.num(22)).tracking(Theme.F.numTracking(22))
                if let regular = offer.regularPriceCents, regular > offer.priceCents {
                    Text(num(Double(regular) / 100, 2...2)).strikethrough()
                        .font(Theme.F.text(11, .semibold, relativeTo: .caption2)).foregroundStyle(Theme.C.ink2)
                        .accessibilityLabel("statt \(euro(regular))")
                }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            .padding(.top, 6).padding(.horizontal, L.text)
            Text(sub).font(Theme.F.text(11, .semibold, relativeTo: .caption2)).foregroundStyle(Theme.C.ink2).lineLimit(1)
                .padding(.top, 3).padding(.horizontal, L.text)
            if let dish {
                HStack(spacing: 4) {
                    Icon(.sparkle, size: 13)
                    Text(dish).lineLimit(1)
                }
                .font(Theme.F.text(11, .extrabold, relativeTo: .caption2)).foregroundStyle(Theme.C.blue3)
                .padding(.top, 6).padding(.horizontal, L.text)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("passt zu \(dish)")
            }
        }
        .foregroundStyle(Theme.C.ink)
        .padding([.horizontal, .top], L.pad)
        .padding(.bottom, L.padBottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.C.card, in: RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    private func plus(_ onList: Bool) -> some View {
        Button {
            guard !onList else { return }
            store.addToList(offer)
            guard !reduceMotion else { return }
            onAdd?(artFrame)
            gone = true
            Task {
                try? await Task.sleep(for: .seconds(0.6))
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { gone = false }
            }
        } label: {
            Icon(onList ? .check : .plus, size: 16)
                .foregroundStyle(Theme.C.onInk)
                .frame(width: L.plus, height: L.plus)
                .background(Theme.C.ink, in: Circle())
                .overlay(Circle().stroke(Theme.C.card, lineWidth: L.plusRing).padding(-L.plusRing / 2))
                .keyframeAnimator(initialValue: 1.0, trigger: onList) { v, s in v.scaleEffect(s) } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(reduceMotion ? 1 : 0.7, duration: 0.01)
                        CubicKeyframe(reduceMotion ? 1 : 1.15, duration: 0.2)
                        CubicKeyframe(1, duration: 0.14)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.success, trigger: onList)
        .accessibilityLabel(onList ? "Auf der Einkaufsliste" : "Zur Einkaufsliste")
    }
}

/// Flug der Zeichnung im Bogen zum Einkauf-Symbol der Nav (a1-add: 0,6 s, cubic-bezier(.35,0,.65,1), −220°, kleiner).
struct OfferFly: Equatable {
    let offer: OfferDTO
    let from: CGRect
    let start: Date
}

struct OfferFlight: View {
    let fly: OfferFly
    private static let curve = Bezier(x1: 0.35, y1: 0, x2: 0.65, y2: 1)

    var body: some View {
        GeometryReader { g in
            TimelineView(.animation) { ctx in
                let k = Self.curve(min(1, ctx.date.timeIntervalSince(fly.start) / 0.6))
                let o = g.frame(in: .global).origin
                let step = g.size.width / 5  // 5 Plätze inkl. „+“
                let bag = CGPoint(x: step / 2 + step * CGFloat(AppTab.einkauf.slot),
                                  y: g.size.height - (Theme.S.nav - Theme.S.navT - 34))  // inaktives Symbol: T + 34
                let p0 = CGPoint(x: fly.from.midX - o.x, y: fly.from.midY - o.y)
                let c = CGPoint(x: p0.x + 10, y: p0.y - 320)
                let x = (1 - k) * (1 - k) * p0.x + 2 * (1 - k) * k * c.x + k * k * bag.x
                let y = (1 - k) * (1 - k) * p0.y + 2 * (1 - k) * k * c.y + k * k * bag.y
                OfferArt(title: fly.offer.title, url: fly.offer.imageUrl)
                    .frame(width: fly.from.width, height: fly.from.height)
                    .rotationEffect(.degrees(-220 * k))
                    .scaleEffect(1 - 0.78 * k)
                    .position(x: x, y: y)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Angebot als schlichte Zeile (`.c-r2`): Logo-Kreis, Name, Unterzeile mit Rabatt in `deal`, rechts ein Zusatz.
struct OfferLine<Trail: View>: View {
    let offer: OfferDTO
    var parts: [String?]
    @ViewBuilder var trail: Trail

    var body: some View {
        HStack(spacing: 14) {
            LogoCircle(chain: offer.chain)
            VStack(alignment: .leading, spacing: 2) {
                Text(offer.title).font(Theme.F.text(16, .bold, relativeTo: .body)).lineLimit(1)
                offerSub(parts, deal: offer.discount)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trail
        }
        .foregroundStyle(Theme.C.ink)
        .padding(.vertical, 11)
        .overlay(alignment: .top) { Hairline() }
        .contentShape(Rectangle())
    }
}

/// „Rossmann · 20 WL · −35 %“, Rabatt in `deal`.
func offerSub(_ parts: [String?], deal: Int?) -> some View {
    let head = parts.compactMap { $0 }.joined(separator: " · ")
    let dealText = deal.map { d in Text("−\(d) %").foregroundStyle(Theme.C.deal) }
    return Group {
        if let dealText { Text("\(head)\(head.isEmpty ? "" : " · ")\(dealText)") } else { Text(head) }
    }
    .font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2).lineLimit(1)
}

/// „2026-11-09“ → „9.11.“
func dayMonth(_ iso: String) -> String {
    let p = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
    return p.count == 3 ? "\(p[2]).\(p[1])." : iso
}

/// „2026-11-07“ → „Sa 7.11.“
func weekdayDay(_ iso: String) -> String {
    guard let d = try? Date(String(iso.prefix(10)), strategy: PantryDTO.day) else { return dayMonth(iso) }
    return "\(Labels.days[(Calendar.current.component(.weekday, from: d) + 5) % 7]) \(dayMonth(iso))"
}

/// Kleine Angebotskachel (`.c-mini`): Kreis 72 mit Logo (Drogerie) oder Zeichnung, Name zweizeilig, Preis + Rabatt.
struct MiniOffer: View {
    let offer: OfferDTO
    var tint: Color?

    static let tints = [Theme.C.blue1, Theme.C.rose, Theme.C.sage]

    var body: some View {
        let drug = ["drogerie", "haushalt"].contains(offer.category)
        VStack(spacing: 0) {
            if drug {
                LogoCircle(chain: offer.chain, size: 72, tint: tint ?? Theme.C.plate)
            } else {
                OfferArt(title: offer.title, url: offer.imageUrl).frame(width: 60, height: 60)
                    .frame(width: 72, height: 72)
                    .background(tint ?? OfferArt.tint(offer.title, category: offer.category), in: Circle())
            }
            Text(offer.title).font(Theme.F.text(13, .bold, relativeTo: .footnote)).lineLimit(2).multilineTextAlignment(.center)
                .frame(height: 36, alignment: .top).padding(.top, 8)
            HStack(spacing: 4) {
                Text(euro(offer.priceCents))
                if let d = offer.discount { Text("−\(d) %").foregroundStyle(Theme.C.deal) }
            }
            .font(Theme.F.text(16, .extrabold, relativeTo: .callout)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.C.ink)
        .frame(width: 104)
        .accessibilityElement(children: .combine)
    }
}

extension OfferDTO {
    var discount: Int? {
        guard let regular = regularPriceCents, regular > priceCents else { return nil }
        return Int((Double(regular - priceCents) / Double(regular) * 100).rounded())
    }

    /// „0,50 € Bonus“ (Rewe-Bonus-Aktion, 39).
    var bonusText: String? { bonusCents.flatMap { b in b > 0 ? "\(euro(b)) Bonus" : nil } }

    var baseUnitLabel: String { unit == "stk" ? "Stk" : unit == "ml" ? "l" : "kg" }

    var amountText: String? {
        amount.map { "\(num($0, 0...2)) \(unit == "stk" ? "Stück" : unit)" }
    }

    var daysLeft: Int? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let end = f.date(from: validTo) else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: end).day
    }
}

// MARK: S9 Angebotsdetail

/// S9: Packung im Kreis, Herz (a1-fav), Preis riesig, Normalpreis grau, Grundpreis/Laden/Frist; Preisverlauf, Vorratstipp,
/// Nährwerte, Siegel, Passt zu; unten „Zur Einkaufsliste“.
struct OfferDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let offer: OfferDTO
    @State private var count = Demo.screen == "offer" ? 2 : 1
    @State private var compact = false  // Kopf schrumpft beim Scrollen (S9 Teil 2/3)

    private enum L {
        static let top: CGFloat = 14
        static let titleWidth: CGFloat = 200  // Titel läuft nicht in die Zeichnung
        static let photo: CGFloat = 170  // Foto-Plättchen rechts oben
        static let photoGap: CGFloat = 12  // Titel endet 12 vor dem Foto
        static let titleSize: CGFloat = 34  // .t1
        static let infoRow: CGFloat = 50
        static let bottom: CGFloat = 120  // Platz für den festen Knopf
    }

    var body: some View {
        let onList = store.isOnList(offer)
        let watched = store.watch(for: offer) != nil
        let photo = OfferArt.hasPhoto(offer.title, url: offer.imageUrl)
        GeometryReader { g in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        backButton
                        Spacer()
                        FavButton(on: watched) { Task { await store.toggleWatch(offer) } }
                    }
                    top(photo ? g.size.width - 2 * Theme.pagePadding - L.photo - L.photoGap : L.titleWidth, photo: photo)
                    infoRows
                    PriceHistoryCard(offer: offer).padding(.top, 40)
                    StockupTip(offer: offer).padding(.top, 56)
                    OfferNutrition8(offer: offer)
                    if offer.hasLabels { labels }
                    meals
                    similar
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, g.safeAreaInsets.top + L.top)
                .padding(.bottom, L.bottom)
                .pinned(left: 176, top: 92) {
                    // Foto steht im Fluss neben dem Titel (`top`), hier nur die Zeichnung
                    if !photo { OfferArt(title: offer.title, url: offer.imageUrl).frame(width: 230, height: 230) }
                }
                .edgeForm(.circle, Theme.C.sand, width: 380, height: 380, left: 160, top: -110)
                .onGeometryChange(for: Bool.self) { p in p.frame(in: .scrollView).minY < -260 } action: { c in
                    withAnimation(.easeOut(duration: 0.2)) { compact = c }
                }
            }
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) { if compact { compactBar(watched).transition(.opacity) } }
        }
        .background(Theme.C.bg.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            Group {
                if onList {
                    OutlineButton(title: "Auf der Liste", icon: .check) {}
                        .background(Theme.C.bg, in: Capsule())
                        .allowsHitTesting(false)
                } else {
                    PrimaryButton(title: "Zur Einkaufsliste", icon: .bag) {
                        withAnimation(Theme.spring) { store.addToList(offer, count: count) }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .sensoryFeedback(.success, trigger: onList)
        }
        .hidesTabBar()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var backButton: some View {
        Button { dismiss() } label: { Icon(.back, size: 26).frame(width: 44, height: 44, alignment: .leading).contentShape(Rectangle()) }
            .buttonStyle(PressableStyle())
            .foregroundStyle(Theme.C.ink)
            .accessibilityLabel("Zurück")
    }

    /// Geschrumpfter Kopf (S9 Teil 2/3): Zurück · Name klein · Herz.
    private func compactBar(_ watched: Bool) -> some View {
        HStack {
            backButton
            Spacer()
            Text([offer.brand, offer.title].filter { !$0.isEmpty }.joined(separator: " ")).font(Theme.F.small)
                .foregroundStyle(Theme.C.ink).lineLimit(1)
            Spacer()
            FavButton(on: watched) { Task { await store.toggleWatch(offer) } }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 6)
        .background(Theme.C.bg.ignoresSafeArea(edges: .top))
    }

    /// t1 inkl. Dynamic Type, aber so klein, dass das längste Wort (echt gemessen) in eine Zeile passt:
    /// Umbruch nur zwischen Wörtern, nie mitten im Wort.
    private func titleSize(_ width: CGFloat) -> CGFloat {
        let size = UIFontMetrics(forTextStyle: .largeTitle).scaledValue(for: L.titleSize)
        guard let font = UIFont(name: Theme.F.serifName, size: size) else { return size }
        let widest = offer.title.split(whereSeparator: \.isWhitespace)
            .map { (String($0) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return widest > width ? floor(size * width / widest * 0.98) : size  // 2 % Luft für Rundung
    }

    /// Mit Prospektfoto steht das Plättchen rechts neben Titel und Untertitel, Titel endet 12 davor.
    private func top(_ titleWidth: CGFloat, photo: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: L.photoGap) {
                VStack(alignment: .leading, spacing: 0) {
                    if let d = offer.discount { DealPill(text: "−\(d) %").padding(.top, 30) }
                    Text(offer.title)
                        .font(.custom(Theme.F.serifName, fixedSize: titleSize(titleWidth)))
                        .lineLimit(3)
                        .frame(maxWidth: titleWidth, alignment: .leading)
                        .padding(.top, 8)
                        .accessibilityAddTraits(.isHeader)
                    let sub = [offer.brand.isEmpty ? nil : offer.brand, offer.amountText].compactMap { $0 }.joined(separator: " · ")
                    if !sub.isEmpty { Text(sub).font(Theme.F.small).foregroundStyle(Theme.C.ink2).padding(.top, 4) }
                }
                if photo {
                    Spacer(minLength: 0)
                    OfferArt(title: offer.title, url: offer.imageUrl)
                        .frame(width: L.photo, height: L.photo)
                        .padding(.top, 12)
                        .accessibilityHidden(true)
                }
            }
            HStack(spacing: 5) {
                if let n = offer.nutriScore { NutriPill(score: n) }
                if offer.vegan == true { SoftPill(text: "Vegan", icon: .leaf, tint: Theme.C.sage) }
                if offer.bio == true { SoftPill(text: "Bio", tint: Theme.C.sage) }
                if let b = offer.bonusText { SoftPill(text: b, icon: .gift) }  // Rewe-Bonus (39)
            }
            .padding(.top, 10)
            StatNumber(label: "Preis", value: euro(offer.priceCents), size: 92).padding(.top, 44)
            if let regular = offer.regularPriceCents, regular > offer.priceCents {
                StrikeStat(label: "Normal", value: euro(regular)).padding(.top, 14)
            }
        }
    }

    private var infoRows: some View {
        let stores = store.household?.stores.filter { $0.chain == offer.chain && $0.enabled } ?? []
        return VStack(spacing: 0) {
            if let base = offer.basePriceCents { infoRow("Grundpreis") { Text("\(euro(base))/\(offer.baseUnitLabel)") } }
            if stores.isEmpty {
                infoRow("Laden") { logo; Text("alle Filialen") }
            }
            ForEach(stores, id: \.self) { s in
                let name = s.address.flatMap { a in a.split(separator: ",").first.map(String.init) } ?? (s.storeName.isEmpty ? Labels.chain(s.chain) : s.storeName)
                if let lat = s.lat, let lng = s.lng, let url = URL(string: "maps://?daddr=\(lat),\(lng)") {
                    Button { openURL(url) } label: { infoRow("Laden") { logo; Text(name) } }
                        .buttonStyle(.plain)
                        .accessibilityHint("Route in Karten öffnen")
                } else {
                    infoRow("Laden") { logo; Text(name) }
                }
            }
            infoRow(offer.startsLater ? "Gültig ab" : "Gültig bis") { Text(validity) }
            infoRow("Menge") { Stepper8(value: $count, range: 1...20) { "\($0)×" } }  // ohne Mockup: Menge für die Liste
        }
        .padding(.top, 14)
    }

    private var logo: some View {
        RemoteImage(url: Labels.logoURL(offer.chain), dim: false) { EmptyView() }.frame(height: 13).frame(maxWidth: 60, alignment: .trailing)
            .accessibilityHidden(true)
    }

    private func infoRow(_ label: String, @ViewBuilder _ value: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(label).font(Theme.F.small).foregroundStyle(Theme.C.ink2).frame(maxWidth: .infinity, alignment: .leading)
            value().font(Theme.F.text(16, .bold, relativeTo: .body)).foregroundStyle(Theme.C.ink).lineLimit(1)
        }
        .frame(minHeight: L.infoRow)
        .overlay(alignment: .top) { Hairline() }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// „Sa, 7.11. · noch 3 Tage“
    private var validity: String {
        let iso = offer.startsLater ? offer.validFrom : offer.validTo
        var text = dayMonth(iso)
        if let d = try? Date(String(iso.prefix(10)), strategy: PantryDTO.day) {
            text = "\(Labels.days[(Calendar.current.component(.weekday, from: d) + 5) % 7]), \(text)"
        }
        guard !offer.startsLater, let left = offer.daysLeft else { return text }
        return text + (left <= 0 ? " · nur heute" : left == 1 ? " · noch 1 Tag" : " · noch \(left) Tage")
    }

    /// Bio, vegan, Nutri-Score (49): Siegel mit Erklärung, Quelle als Zeile mit Pfeil.
    private var labels: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Bio, vegan, Nutri-Score").font(Theme.F.t2).padding(.bottom, 8)
            if let n = offer.nutriScore {
                labelRow(NutriPill(score: n), "Nährwert-Ampel von A (günstig) bis E")
            }
            if offer.vegan == true { labelRow(SoftPill(text: "Vegan", icon: .leaf, tint: Theme.C.sage), "ohne tierische Zutaten") }
            if offer.bio == true { labelRow(SoftPill(text: "Bio", tint: Theme.C.sage), "laut Bio-Siegel bzw. „Bio“ im Prospekt") }
            let source = "Quelle: " + ((offer.labelSources ?? []).isEmpty ? "Prospekt" : (offer.labelSources ?? []).joined(separator: " · "))
            if let code = offer.offCode, !code.isEmpty, let url = URL(string: "https://world.openfoodfacts.org/product/\(code)") {
                Button { openURL(url) } label: {
                    HStack {
                        Text(source).font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Icon(.chev, size: 18).foregroundStyle(Theme.C.ink3)
                    }
                    .padding(.vertical, 11).frame(minHeight: 44)
                    .overlay(alignment: .top) { Hairline() }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Bei Open Food Facts ansehen")
            } else {
                Text(source).font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                    .padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Hairline() }
            }
        }
        .padding(.top, 30)
    }

    private func labelRow(_ pill: some View, _ text: String) -> some View {
        HStack(spacing: 14) {
            pill.frame(width: 72)
            Text(text).font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { Hairline() }
        .accessibilityElement(children: .combine)
    }

    /// „Passt zu“: Gerichte im Plan, die dieses Angebot nutzen – Teller über dem Kreis links.
    @ViewBuilder private var meals: some View {
        let meals = store.plan?.entries.filter { $0.recipe.ingredients.contains { $0.offerId == offer.id } } ?? []
        if !meals.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Passt zu").font(Theme.F.t2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 15) {
                        ForEach(meals, id: \.self) { meal in
                            NavigationLink { RecipeDetailView(meal: meal) } label: {
                                VStack(spacing: 0) {
                                    RemoteImage(url: mediaURL(meal.recipe.imageUrl), contentMode: .fill) { Theme.C.card }.plate(92)
                                    Text(meal.recipe.title).font(Theme.F.text(13, .bold, relativeTo: .footnote)).lineLimit(2)
                                        .multilineTextAlignment(.center).frame(height: 36, alignment: .top).padding(.top, 8)
                                        .foregroundStyle(Theme.C.ink)
                                }
                                .frame(width: 104)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding).padding(.vertical, 8)
                }
                .padding(.horizontal, -Theme.pagePadding)
                .padding(.top, 6)
            }
            .edgeForm(.circle, Theme.C.blue1, width: 340, height: 340, left: -124, top: 0)
            .padding(.top, 30)
        }
    }

    /// Ähnliche Angebote (ohne Mockup, im Stil „Passt zu“).
    @ViewBuilder private var similar: some View {
        let similar = store.offers
            .filter { $0.category == offer.category && $0.id != offer.id && offer.category != "sonstiges" }
            .sorted { ($0.basePriceCents ?? .max) < ($1.basePriceCents ?? .max) }
            .prefix(8)
        if !similar.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ähnliche Angebote").font(Theme.F.t2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 15) {
                        ForEach(Array(similar)) { o in
                            NavigationLink { OfferDetailView(offer: o) } label: { MiniOffer(offer: o) }.buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                }
                .padding(.horizontal, -Theme.pagePadding)
                .padding(.top, 14)
            }
            .padding(.top, 30)
        }
    }
}

/// Normalpreis grau durchgestrichen (`.stat.mute` + line-through 2).
private struct StrikeStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Hairline(color: Theme.C.ink3)
            HStack(alignment: .top) {
                Text(label).font(Theme.F.text(12, .bold, relativeTo: .caption))
                Spacer(minLength: 8)
                BigNumber(value, size: 38).overlay { Rectangle().frame(height: 2) }
            }
            .foregroundStyle(Theme.C.ink3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }
}

/// Nutri-Score als weiche Pille in der Originalfarbe (`.soft.c-nA`).
struct NutriPill: View {
    let score: String

    var body: some View {
        TintPill(text: "Nutri \(score)", bg: Theme.C.nutri[score] ?? Theme.C.line, fg: score == "C" ? Theme.C.onBright : Theme.C.onInk)
            .accessibilityLabel("Nutri-Score \(score)")
    }
}

/// Weiche Pille (`.soft`) mit eigener Text- und Grundfarbe (Urteil, Nutri-Score).
struct TintPill: View {
    let text: String
    let bg: Color
    let fg: Color

    var body: some View {
        Text(text).font(Theme.F.soft).foregroundStyle(fg)
            .padding(.horizontal, 10).frame(height: Theme.S.softPill)
            .background(bg, in: Capsule())
    }
}

/// Herz im Tinten-Kreis (a1-fav): füllt sich von unten (0,35 s), ploppt auf 1,3 (0,4 s), sechs Funken (0,45 s).
private struct FavButton: View {
    let on: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spark: Date?

    var body: some View {
        Button {
            if !on && !reduceMotion { spark = .now }
            action()
        } label: {
            ZStack {
                Icon8.heart.path(.stroke).fill(Theme.C.onInk)
                    .mask(alignment: .top) { Rectangle().offset(y: on ? 0 : 24) }
                    .frame(width: 24, height: 24).scaleEffect(20 / 24).frame(width: 20, height: 20)
                    .animation(reduceMotion ? nil : on ? .timingCurve(0.3, 1, 0.5, 1, duration: 0.35) : .easeIn(duration: 0.25), value: on)
                Icon(.heart, size: 20)
            }
            .foregroundStyle(Theme.C.onInk)
            .keyframeAnimator(initialValue: 1.0, trigger: on) { v, s in v.scaleEffect(s) } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(on && !reduceMotion ? 1.3 : 1, duration: 0.16)
                    CubicKeyframe(1, duration: 0.24)
                }
            }
            .frame(width: 44, height: 44)
            .background(Theme.C.ink, in: Circle())
            .overlay { if let spark { Sparks(start: spark) } }
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(trigger: on) { _, new in new ? .success : .impact(weight: .light) }
        .task(id: spark) {
            guard spark != nil else { return }
            try? await Task.sleep(for: .seconds(0.45))
            spark = nil
        }
        .accessibilityLabel(on ? "Von der Merkliste entfernen" : "Auf die Merkliste")
    }

    /// Sechs Tinten-Striche springen aus dem Herz (r 17 → 25), wachsen und verschwinden.
    private struct Sparks: View {
        let start: Date

        var body: some View {
            TimelineView(.animation) { ctx in
                let p = Bezier(x1: 0, y1: 0, x2: 0.58, y2: 1)(min(1, ctx.date.timeIntervalSince(start) / 0.45))
                // Strich wächst von innen (bis 50 %), dann verschwindet er nach außen (stroke-dashoffset 1 → 0 → −1)
                let inner = 17 + 8 * max(0, p - 0.5) * 2, outer = 17 + 8 * min(1, p * 2)
                Path { path in
                    for i in 0..<6 {
                        let a = Double(i) * .pi / 3
                        path.move(to: CGPoint(x: 32 + inner * sin(a), y: 32 - inner * cos(a)))
                        path.addLine(to: CGPoint(x: 32 + outer * sin(a), y: 32 - outer * cos(a)))
                    }
                }
                .stroke(Theme.C.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .opacity(p < 1 ? 1 : 0)
                .frame(width: 64, height: 64)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Vorratstipp (31) neben der Tasche im Salbei-Kreis: „3 Packungen reichen ~6 Wochen“, „3× auf die Liste“.
private struct StockupTip: View {
    @Environment(AppStore.self) private var store
    let offer: OfferDTO
    @State private var tip: StockupDTO?
    @State private var added = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let tip {
                HStack(spacing: 6) { Icon(.sparkle, size: 15); Text("VORRATSTIPP").font(Theme.F.lbl).tracking(11 * 0.08) }
                    .foregroundStyle(Theme.C.ink)
                Text(headline(tip)).font(Theme.F.t2).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                Text("sparst \(euro(tip.savingCents)) zum Normalpreis").font(Theme.F.text(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Theme.C.ink2).padding(.top, 4)
                Button {
                    added = true
                    Task { await store.addStockup(tip) }
                } label: {
                    HStack(spacing: 8) {
                        if added { Icon(.check, size: 18) }
                        Text(added ? "Auf der Liste" : "\(tip.packs)× auf die Liste")
                    }
                    .font(Theme.F.button).foregroundStyle(Theme.C.ink)
                    .padding(.horizontal, 22).frame(height: 48)
                    .background(Theme.C.blue, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .disabled(added)
                .sensoryFeedback(.success, trigger: added)
                .padding(.top, 12)
            }
        }
        .frame(width: 220, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topLeading) {
            if tip != nil {
                ZStack(alignment: .topLeading) {
                    Circle().fill(Theme.C.sage).frame(width: 300, height: 300).offset(x: 216, y: -4)
                    Ill("bag").frame(width: 124).offset(x: 234, y: 6)
                }
                .accessibilityHidden(true)
            }
        }
        .animation(Theme.spring, value: tip)
        .task(id: offer.id) { tip = await store.stockup(for: offer) }
    }

    private func headline(_ t: StockupDTO) -> String {
        let packs = t.packs == 1 ? "1 Packung" : "\(t.packs) Packungen"
        guard let w = t.weeks else { return "\(packs) auf Vorrat" }
        return "\(packs) \(t.packs == 1 ? "reicht" : "reichen") ~\(num(w, 0...0)) Wochen"
    }
}

/// Nährwerte (2): kcal groß, Protein/KH/Fett klein; pro 100 g / pro Packung; nur bei sicherer Zuordnung.
private struct OfferNutrition8: View {
    @Environment(AppStore.self) private var store
    let offer: OfferDTO
    @State private var data: OfferNutritionDTO?
    @State private var perPack = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let d = data, d.status != "none" {
                let values = perPack ? d.perPack : d.per100g
                Text("Nährwerte").font(Theme.F.t2)
                if d.perPack != nil {
                    Segmented8(options: [(false, "pro 100 g"), (true, "pro Packung\(offer.amountText.map { a in " (\(a))" } ?? "")")],
                               selection: $perPack)
                        .padding(.top, 12)
                }
                HStack(alignment: .bottom, spacing: 14) {
                    if let n = values {
                        StatNumber(label: "kcal", value: "\(Int(n.kcal.rounded()))", size: 44).frame(width: 120)
                        macro("Protein", n.protein)
                        macro("KH", n.carbs)
                        macro("Fett", n.fat)
                    } else {
                        Skeleton8(height: 54)
                    }
                }
                .padding(.top, 18)
                .animation(Theme.spring, value: perPack)
                Text(d.status == "pending" ? "Nährwerte werden zugeordnet …" : "Quelle: USDA FoodData Central · „\(d.food)“")
                    .font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2).padding(.top, 8)
            }
        }
        .padding(.top, data.map { $0.status != "none" } == true ? 40 : 0)
        .task(id: offer.id) { await load() }
    }

    private func macro(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
            Text("\(num(value)) g").font(Theme.F.text(17, .bold, relativeTo: .headline)).contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        var wait = 3.0
        for _ in 0..<4 {  // pending: Zuordnung läuft im Hintergrund → mit wachsendem Abstand nachfragen
            guard let d = try? await store.offerNutrition(offer.id) else { return }
            withAnimation(Theme.spring) { data = d }
            guard d.status == "pending" else { return }
            try? await Task.sleep(for: .seconds(wait))
            wait *= 2
        }
    }
}
