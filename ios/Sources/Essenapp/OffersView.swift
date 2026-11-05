import SwiftUI

/// S4 Angebote v8 „Tinte & Bogen“ (diese/nächste Woche, Kategorien, Filter-Sheet, Drogerie mit Monatsaktionen, Leer)
/// und Umschalter zur Merkliste (S10, `WatchListView`). Mockup: docs/ui/mockups/v8-parts/c.html, Kern S4 in redesign-v8.html.
struct OffersView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("offers.chain") private var chain: String?  // Auswahl merken (19.4)
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
    @State private var filtering = Demo.screen == "offersfilter"
    @State private var pull: CGFloat = 0
    @State private var refreshing = false
    @State private var fresh: Set<Int> = []  // nach dem Aktualisieren neu dazugekommen (a2-pull)
    @State private var fly: OfferFly?

    /// Lagen aus dem Mockup (Bildschirm-Koordinaten ab Oberkante, Telefon 390 breit, Statusleiste 52).
    private enum L {
        static let top: CGFloat = 14  // .scr 66 − 52
        static let pullAt: CGFloat = 110  // so weit ziehen, dann lädt es
        static let hold: CGFloat = 120  // Liste bleibt beim Laden so weit unten (a2-pull)
        static let emptyGap: CGFloat = 372  // Leer-Text bei y 556, gemessen ab Chip-Reihe
        static let statWidth: CGFloat = 170
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

    private var offersScreen: some View {
        let all = (nextWeek ? store.nextOffers : store.offers).filter { $0.category != "nonfood" }  // Möbel, Technik … (19.1)
        let filtered = all.filter(matches)
        let drug = category == "drogerie" && !nextWeek  // Monatsaktionen (59)
        let monthly = drug ? filtered.filter { o in o.monthly == true } : []
        let rows = drug ? filtered.filter { o in o.monthly != true } : filtered
        let empty: Empty? = nextWeek && store.nextOffers.isEmpty ? .nextWeek
            : all.isEmpty ? .none : rows.isEmpty && monthly.isEmpty ? .filter : nil
        return GeometryReader { g in
            ScrollView {
                content(all: all, filtered: filtered, rows: rows, monthly: monthly, drug: drug, empty: empty)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, g.safeAreaInsets.top + L.top)
                    .padding(.bottom, Theme.S.nav)
                    .modifier(OffersForms(empty: empty != nil, drug: drug, nextWeek: nextWeek, refreshing: refreshing, looking: pull > 20 || refreshing))
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
    private func content(all: [OfferDTO], filtered: [OfferDTO], rows: [OfferDTO], monthly: [OfferDTO], drug: Bool,
                         empty: Empty?) -> some View {
        let weekRow = !store.nextOffers.isEmpty || nextWeek
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink { StoreMapView() } label: {
                Text("\(store.household?.plz ?? "") · \(store.household?.stores.filter(\.enabled).count ?? 0) Läden")
                    .font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                    .padding(.vertical, 12).contentShape(Rectangle()).padding(.vertical, -12)  // Tap-Fläche 44
            }
            .buttonStyle(.plain)
            .accessibilityHint("Läden und Umkreis ändern")
            Text("Angebote").font(Theme.F.t1).accessibilityAddTraits(.isHeader)

            if empty == nil && !drug {
                StatNumber(label: nextWeek ? "Ab nächster\nWoche" : "Diese\nWoche", value: "\(all.count)", size: nextWeek ? 56 : 64)
                    .frame(width: L.statWidth)
                    .padding(.top, nextWeek ? 18 : 22)
                    .animation(Theme.spring, value: all.count)
            }

            if empty == .filter {
                filterChips.padding(.top, 16)
            } else {
                if weekRow { weekChips.padding(.top, empty == nil && !drug ? 28 : 40) }
                categoryRow(all: all, withFilter: !weekRow).padding(.top, weekRow ? 12 : 40)
                subcategoryRow(all: all)
            }

            if realOnly && !all.contains(where: { o in Verdict.pill(o.verdict) != nil }) {
                HintRow(icon: .chart, title: "Noch zu wenig Preisdaten.",
                        text: "Ab 3 Wochen greift „Nur echte Angebote“ – bis dahin siehst du alle.")
                    .padding(.top, 16)
            }

            if let empty {
                emptyBlock(empty)
            } else if drug {
                drugstore(monthly: monthly, rows: rows)
            } else if category == "haushalt" {
                LazyVStack(spacing: 0) { ForEach(rows) { o in lineLink(o) } }.padding(.top, 16)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { o in
                        NavigationLink { OfferDetailView(offer: o) } label: {
                            OfferRow8(offer: o, fresh: fresh.contains(o.id)) { frame in
                                if !reduceMotion { fly = OfferFly(offer: o, from: frame, start: .now) }
                            }
                        }
                        .buttonStyle(PressableStyle())
                        .transition(.scale(scale: 0.85, anchor: .leading).combined(with: .opacity))
                    }
                }
                .padding(.top, nextWeek ? 20 : 16)
                .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: rows.map(\.id))
            }
        }
    }

    /// Diese / nächste Woche + Filter-Knopf (S4 Nächste Woche).
    private var weekChips: some View {
        HStack(spacing: 6) {
            SmallChip(title: "Diese Woche \(store.offers.count)", on: !nextWeek, compact: true) {
                withAnimation(Theme.spring) { nextWeek = false }
            }
            SmallChip(title: "Nächste Woche \(store.nextOffers.count)", on: nextWeek, compact: true,
                      badge: store.nextOffers.isEmpty ? nil : "neu") {
                withAnimation(Theme.spring) { nextWeek = true }
            }
            Spacer(minLength: 0)
            filterButton
        }
    }

    /// Alle · Merkliste · Kategorien mit Treffern (S4, S4 Drogerie). Ohne Wochen-Reihe sitzt der Filter-Knopf rechts.
    private func categoryRow(all: [OfferDTO], withFilter: Bool) -> some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Chip8(title: "Alle", on: category == nil) {
                        withAnimation(Theme.spring) { category = nil; subcategory = nil }
                    }
                    Chip8(title: store.watches.isEmpty ? "Merkliste" : "Merkliste \(store.watches.count)") {
                        withAnimation(Theme.spring) { watchMode = true }
                    }
                    ForEach(Labels.categories, id: \.0) { c in
                        let n = all.filter { o in o.category == c.0 }.count
                        if n > 0 {
                            Chip8(title: "\(c.1.split(separator: " ").dropFirst().joined(separator: " ")) \(n)", on: category == c.0) {
                                withAnimation(Theme.spring) { category = category == c.0 ? nil : c.0; subcategory = nil }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
            .padding(.leading, -Theme.pagePadding)
            .padding(.trailing, withFilter ? 0 : -Theme.pagePadding)
            if withFilter { filterButton }
        }
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
        realOnly = false; bio = false; vegan = false; nutri = false; bonusOnly = false
        search = ""; chain = nil; category = nil; subcategory = nil
    }

    /// S4 Drogerie: Monatsaktionen von dm/Rossmann nebeneinander, darunter die übrigen Angebote als Zeilen.
    private func drugstore(monthly: [OfferDTO], rows: [OfferDTO]) -> some View {
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
            LazyVStack(spacing: 0) { ForEach(rows) { o in lineLink(o) } }.padding(.top, 30)
        }
    }

    private func lineLink(_ o: OfferDTO) -> some View {
        NavigationLink { OfferDetailView(offer: o) } label: {
            OfferLine(offer: o, parts: [Labels.chain(o.chain), o.amountText]) {
                Text(euro(o.priceCents)).font(Theme.F.text(17, .bold, relativeTo: .headline)).monospacedDigit()
            }
        }
        .buttonStyle(PressableStyle())
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

/// Blatt + Fernglas (S4, Nächste Woche), Viertelkreis + Tasche (Drogerie), Kreis + Fernglas (Leer). Mockup-Koordinaten.
private struct OffersForms: ViewModifier {
    let empty: Bool
    let drug: Bool
    let nextWeek: Bool
    let refreshing: Bool
    let looking: Bool  // beim Ziehen weicht das große Fernglas nach oben aus (a2-look)

    func body(content: Content) -> some View {
        if empty {
            content
                .pinned(left: 70, top: 290) {
                    if refreshing { PotLoader() } else { Ill("binoculars").frame(width: 240) }
                }
                .edgeForm(.circle, Theme.C.blue1, width: 440, height: 440, left: -70, top: 300)
        } else if drug {
            content
                .pinned(left: 262, top: 46) { Ill("bag").frame(width: 110) }
                .edgeForm(.quarter, Theme.C.rose, width: 190, height: 190, right: 0, top: 0)
        } else if nextWeek {
            content
                .pinned(left: 222, top: 58) { look(Ill("binoculars").frame(width: 160)) }
                .edgeForm(.leaf(130), Theme.C.blue1, width: 200, height: 240, right: 0, top: 0)
        } else {
            content
                .pinned(left: 200, top: 56) { look(Ill("binoculars").frame(width: 200)) }
                .edgeForm(.leaf(150), Theme.C.blue1, width: 240, height: 290, right: 0, top: 0)
        }
    }

    private func look(_ v: some View) -> some View {
        v.opacity(looking ? 0 : 1).offset(y: looking ? -24 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: looking)
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
        ZStack(alignment: .topLeading) {
            Circle().fill(Theme.C.blue)
            Ill("binoculars").frame(width: 170)
                .rotationEffect(.degrees(sway && !reduceMotion ? 7 : -7 * (refreshing && !reduceMotion ? 1 : 0)), anchor: UnitPoint(x: 0.5, y: 0.92))
                .offset(x: -50, y: 3 + (refreshing ? 0 : 60))
        }
        .frame(width: 72, height: 72)
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

    var body: some View {
        if let ill = Self.ill(title) {
            Ill(ill)
        } else {
            RemoteImage(url: URL(string: url)) { Ill("bag") }
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

/// Angebot als Zeile mit Farb-Lasche von rechts (`.offer` + `.tab`): Rabatt, Name, Laden · Menge, Preis; „+“ = Zur Liste (a1-add).
struct OfferRow8: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let offer: OfferDTO
    var fresh = false  // „neu“ nach dem Aktualisieren
    var onAdd: ((CGRect) -> Void)?  // Rahmen der Zeichnung (global) für den Flug zum Einkauf-Symbol
    @State private var artFrame: CGRect = .zero
    @State private var gone = false

    private enum L {
        static let tabRight: CGFloat = -24
        static let tabTop: CGFloat = 12
        static let artLeft: CGFloat = 12
        static let artTop: CGFloat = -4
        static let artWidth: CGFloat = 118
        static let plus = CGPoint(x: 194, y: 46)
        static let textWidth: CGFloat = 186
    }

    var body: some View {
        let onList = store.isOnList(offer)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if let d = offer.discount { DealPill(text: "−\(d) %") }
                if offer.verdict == "bestpreis", let v = Verdict.pill(offer.verdict) { TintPill(text: v.text, bg: v.bg, fg: v.fg) }
                if fresh { SoftPill(text: "neu") }
            }
            Text(offer.title).font(Theme.F.t2).lineLimit(2).minimumScaleFactor(0.75).padding(.top, 6)
            Text([Labels.chain(offer.chain), offer.amountText, offer.startsLater ? "ab \(dayMonth(offer.validFrom))" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2).lineLimit(1)
            BigNumber(euro(offer.priceCents), size: 34).padding(.top, 8)
        }
        .foregroundStyle(Theme.C.ink)
        .frame(maxWidth: L.textWidth, alignment: .leading)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, minHeight: Theme.S.offerRow, alignment: .topLeading)
        .overlay(alignment: .top) { Hairline() }
        .pinned(right: L.tabRight, top: L.tabTop) {
            EdgeForm(.tab(Theme.R.offer)).fill(OfferArt.tint(offer.title, category: offer.category))
                .frame(width: Theme.S.offerTab.width, height: Theme.S.offerTab.height)
                .overlay(alignment: .topLeading) {
                    OfferArt(title: offer.title, url: offer.imageUrl)
                        .frame(width: L.artWidth, height: L.artWidth)
                        .onGeometryChange(for: CGRect.self) { g in g.frame(in: .global) } action: { f in artFrame = f }
                        .opacity(gone ? 0 : 1).scaleEffect(gone ? 0.6 : 1)
                        .offset(x: L.artLeft, y: L.artTop)
                }
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topLeading) { plus(onList).offset(x: L.plus.x, y: L.plus.y) }
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
            Icon(onList ? .check : .plus, size: 20)
                .foregroundStyle(Theme.C.onInk)
                .frame(width: 44, height: 44)
                .background(Theme.C.ink, in: Circle())
                .keyframeAnimator(initialValue: 1.0, trigger: onList) { v, s in v.scaleEffect(s) } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(reduceMotion ? 1 : 0.7, duration: 0.01)
                        CubicKeyframe(reduceMotion ? 1 : 1.15, duration: 0.2)
                        CubicKeyframe(1, duration: 0.14)
                    }
                }
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
                let step = g.size.width / CGFloat(AppTab.allCases.count)
                let bag = CGPoint(x: step / 2 + step * CGFloat(AppTab.allCases.firstIndex(of: .einkauf) ?? 3),
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
        static let titleSize: CGFloat = 34  // .t1
        static let glyph: CGFloat = 0.44  // mittlere Zeichenbreite der Serif in em
        static let infoRow: CGFloat = 50
        static let bottom: CGFloat = 120  // Platz für den festen Knopf
    }

    var body: some View {
        let onList = store.isOnList(offer)
        let watched = store.watch(for: offer) != nil
        GeometryReader { g in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        backButton
                        Spacer()
                        FavButton(on: watched) { Task { await store.toggleWatch(offer) } }
                    }
                    top
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
                    OfferArt(title: offer.title, url: offer.imageUrl).frame(width: 230, height: 230)
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

    private var top: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let d = offer.discount { DealPill(text: "−\(d) %").padding(.top, 30) }
            // Längstes Wort passt in eine Zeile: Umbruch nur zwischen Wörtern
            let word = offer.title.split(separator: " ").map(\.count).max() ?? 1
            Text(offer.title)
                .font(Theme.F.serif(min(L.titleSize, L.titleWidth / (CGFloat(word) * L.glyph)), relativeTo: .largeTitle))
                .lineLimit(3)
                .frame(maxWidth: L.titleWidth, alignment: .leading)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            let sub = [offer.brand.isEmpty ? nil : offer.brand, offer.amountText].compactMap { $0 }.joined(separator: " · ")
            if !sub.isEmpty { Text(sub).font(Theme.F.small).foregroundStyle(Theme.C.ink2).padding(.top, 4) }
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
