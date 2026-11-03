import MapKit
import SwiftUI

/// S4 Angebote (diese/nächste Woche, Filter Urteil/Bio/Vegan/Nutri, Monatsaktionen) + S10 Merkliste.
struct OffersView: View {
    @Environment(AppStore.self) private var store
    @State private var chain: String?
    @State private var category: String?
    @State private var search = ""
    @State private var watchMode = ["watch", "scanner"].contains(Demo.screen ?? "")
    @State private var nextWeek = Demo.screen == "nextweek"  // Vorschau (30)
    @State private var realOnly = false  // „Nur echte Angebote“ (28)
    @State private var bio = false  // 49
    @State private var vegan = false
    @State private var nutri = false
    @State private var bonusOnly = false  // Rewe-Bonus-Aktionen (39)
    @State private var filtering = false  // v3: Suche + weitere Filter im Sheet hinter dem Such-Knopf

    var body: some View {
        let all = nextWeek ? store.nextOffers : store.offers
        let byChain = Dictionary(grouping: all, by: \.chain)
        let chains = Labels.chains.map(\.key).filter { byChain[$0] != nil }
        let filtered = all.filter {
            (chain == nil || $0.chain == chain) && (category == nil || $0.category == category)
                && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
                && (!realOnly || $0.verdict != "kein_echtes") && (!bio || $0.bio == true) && (!vegan || $0.vegan == true)
                && (!nutri || ["A", "B"].contains($0.nutriScore ?? "")) && (!bonusOnly || ($0.bonusCents ?? 0) > 0)
        }
        // Monatsaktionen (59): eigener Abschnitt unter Drogerie
        let drugstore = category == "drogerie" && !nextWeek
        let monthly = drugstore ? filtered.filter { o in o.monthly == true } : []
        let grid = drugstore ? filtered.filter { o in o.monthly != true } : filtered
        let judged = all.contains { o in Verdict.badge(o.verdict) != nil }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: []) {
                HStack(alignment: .top) {
                    DisplayHeader(line1: nextWeek ? "Nächste Woche" : "Angebote", size: nextWeek ? 40 : 46)
                    Button { filtering = true } label: {
                        Image(systemName: activeFilters > 0 ? "line.3.horizontal.decrease" : "magnifyingglass")
                            .font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.C.onAction)
                            .frame(width: Theme.S.roundButton, height: Theme.S.roundButton)
                            .background(Theme.C.action, in: Circle())
                            .overlay(alignment: .topTrailing) {
                                if activeFilters > 0 {
                                    Text("\(activeFilters)").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                                        .frame(minWidth: 18, minHeight: 18).background(Theme.C.deal, in: Capsule()).offset(x: 4, y: -4)
                                }
                            }
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.top, 4)
                    .accessibilityLabel(activeFilters > 0 ? "Suche und Filter, \(activeFilters) aktiv" : "Suche und Filter")
                }
                HStack(spacing: 6) {
                    NavigationLink { StoreMapView() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin")
                            Text("\(store.household?.plz ?? "") · \(store.household?.stores.filter(\.enabled).count ?? 0) Läden")
                            Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Theme.C.text2).frame(minHeight: 44)
                    }
                    .buttonStyle(PressableStyle())
                    Spacer()
                    Text("\(all.count) \(nextWeek ? "ab nächster Woche" : "diese Woche")").foregroundStyle(Theme.C.text1)
                }
                .font(.system(.subheadline, weight: .semibold))
                .padding(.top, -6)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(label: "Alle", count: all.count, selected: !watchMode && category == nil) {
                            withAnimation(Theme.spring) { watchMode = false; category = nil }
                        }
                        FilterChip(label: "Merkliste", count: store.watches.count, countHighlight: store.watchHits > 0, selected: watchMode) {
                            withAnimation(Theme.spring) { watchMode.toggle() }
                        }
                        ForEach(Labels.categories, id: \.0) { c in
                            let n = all.filter { o in o.category == c.0 }.count
                            if n > 0 {
                                FilterChip(label: String(c.1.split(separator: " ").dropFirst().joined(separator: " ")), count: n,
                                           selected: !watchMode && category == c.0) {
                                    withAnimation(Theme.spring) { watchMode = false; category = category == c.0 ? nil : c.0 }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                }
                .padding(.horizontal, -Theme.pagePadding)

                if watchMode {
                    WatchListView()
                } else {
                    if let top = knaller(grid) {
                        NavigationLink { OfferDetailView(offer: top) } label: { KnallerCard(offer: top) }.buttonStyle(PressableStyle())
                    }
                    if realOnly && !judged {
                        Label("Noch zu wenig Preisdaten (ab 3 Wochen) – bis dahin zeigt der Filter alle Angebote.",
                              systemImage: "chart.line.uptrend.xyaxis")
                            .font(Theme.F.caption).foregroundStyle(Theme.C.text2).fixedSize(horizontal: false, vertical: true)
                    }
                    if drugstore { monthlySection(monthly) }

                    if nextWeek && store.nextOffers.isEmpty {
                        EmptyState(emoji: "👀", title: "Noch keine Prospekte für nächste Woche",
                                   text: "Die meisten Läden zeigen sie ab Donnerstag oder Freitag – wir laden sie automatisch.")
                    } else if all.isEmpty {
                        EmptyState(emoji: "🏷️", title: "Noch keine Angebote", text: "Die Angebote deiner Läden werden wöchentlich geladen.",
                                   buttonTitle: "Jetzt laden") { Task { await store.refreshOffers() } }
                    } else if grid.isEmpty && monthly.isEmpty {
                        EmptyState(emoji: "🔍", title: "Nichts gefunden", text: "Andere Filter probieren.")
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                            ForEach(grid.filter { o in o.id != knaller(grid)?.id }) { offer in
                                NavigationLink { OfferDetailView(offer: offer) } label: { OfferCard(offer: offer) }
                                    .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable {
            await store.refreshOffers()
            await store.loadWatch()
        }
        .sheet(isPresented: $filtering) { filterSheet(chains: chains, byChain: byChain, all: all).presentationDetents([.medium, .large]) }
    }

    private var activeFilters: Int {
        [chain != nil, nextWeek, realOnly, bio, vegan, nutri, bonusOnly, !search.isEmpty].filter { $0 }.count
    }

    /// „Knaller der Woche“: größter Rabatt (ohne Drogerie/Haushalt).
    private func knaller(_ offers: [OfferDTO]) -> OfferDTO? {
        offers.filter { o in o.discount != nil && !["drogerie", "haushalt"].contains(o.category) }.max { ($0.discount ?? 0) < ($1.discount ?? 0) }
    }

    /// Suche, Woche, Läden, Eigenschaften (im Mockup nicht sichtbar → Sheet hinter dem Such-Knopf).
    private func filterSheet(chains: [String], byChain: [String: [OfferDTO]], all: [OfferDTO]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Suchen & filtern").font(Theme.F.display(30))
                SearchField(text: $search, placeholder: "Produkt suchen")
                Text("Woche").font(Theme.F.headline)
                HStack(spacing: 8) {
                    FilterChip(label: "Diese Woche", selected: !nextWeek) { withAnimation(Theme.spring) { nextWeek = false } }
                    FilterChip(label: "Nächste Woche", count: store.nextOffers.isEmpty ? nil : store.nextOffers.count, selected: nextWeek) {
                        withAnimation(Theme.spring) { nextWeek = true }
                    }
                }
                Text("Läden").font(Theme.F.headline)
                FlowLayout(spacing: 8) {
                    FilterChip(label: "Alle", count: all.count, selected: chain == nil) { withAnimation(Theme.spring) { chain = nil } }
                    ForEach(chains, id: \.self) { c in
                        FilterChip(label: Labels.chain(c), count: byChain[c]?.count, selected: chain == c) {
                            withAnimation(Theme.spring) { chain = chain == c ? nil : c }
                        }
                    }
                }
                Text("Eigenschaften").font(Theme.F.headline)
                FlowLayout(spacing: 8) {
                    FilterChip(label: "✓ Nur echte Angebote", filled: true, selected: realOnly) { withAnimation(Theme.spring) { realOnly.toggle() } }
                    FilterChip(label: "Bio", filled: true, selected: bio) { withAnimation(Theme.spring) { bio.toggle() } }
                    FilterChip(label: "🌱 Vegan", filled: true, selected: vegan) { withAnimation(Theme.spring) { vegan.toggle() } }
                    FilterChip(label: "Nutri A/B", filled: true, selected: nutri) { withAnimation(Theme.spring) { nutri.toggle() } }
                    FilterChip(label: "🎁 Bonus-Aktionen", count: all.filter { o in (o.bonusCents ?? 0) > 0 }.count, filled: true, selected: bonusOnly) {
                        withAnimation(Theme.spring) { bonusOnly.toggle() }
                    }
                }
                Button("Fertig") { filtering = false }.buttonStyle(PrimaryButtonStyle()).padding(.top, 8)
            }
            .padding(Theme.pagePadding).padding(.top, 8)
        }
        .background(Theme.C.bg)
        .presentationCornerRadius(Theme.R.sheet)
    }

    /// „Monatsaktionen“ von dm/Rossmann (gültig bis Monatsende).
    private func monthlySection(_ offers: [OfferDTO]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label { Text("Monatsaktionen").font(Theme.F.headline) } icon: { Text("📅") }
            if offers.isEmpty {
                Text("Gerade keine Monatsaktion bei dm oder Rossmann.").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(offers) { o in
                            NavigationLink { OfferDetailView(offer: o) } label: { MiniOffer(offer: o) }.buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal, 2).padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .card()
        .appear()
    }
}

extension OfferDTO {
    var discount: Int? {
        guard let regular = regularPriceCents, regular > priceCents else { return nil }
        return Int((Double(regular - priceCents) / Double(regular) * 100).rounded())
    }

    /// „🎁 0,50 € Bonus“ (Rewe-Bonus-Aktion, 39).
    var bonusText: String? { bonusCents.flatMap { b in b > 0 ? "🎁 \(euro(b)) Bonus" : nil } }

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

/// `OfferCard` v3: Kategorie-Tönung, Preis-Stern oben links, Urteil-Emoji oben rechts, Preis-Pille + Plus.
struct OfferCard: View {
    @Environment(AppStore.self) private var store
    let offer: OfferDTO

    var body: some View {
        let hue = Theme.hue(category: offer.category)
        let onList = store.isOnList(offer)
        VStack(alignment: .leading, spacing: 0) {
            RemoteImage(url: URL(string: offer.imageUrl)) { Text(hue.emoji).font(.system(size: 66)) }
                .shadow(color: .black.opacity(0.15), radius: 5, y: 10)
                .frame(maxWidth: .infinity).frame(height: 118)
                .overlay(alignment: .bottomLeading) { LabelBadges(offer: offer) }  // 49
            Text(offer.title).font(.system(.subheadline, weight: .bold)).lineLimit(2).multilineTextAlignment(.leading)
                .foregroundStyle(Theme.C.text1)
            Text([Labels.chain(offer.chain), offer.amountText].compactMap { $0 }.joined(separator: " · ")
                 + (offer.basePriceCents.map { " · \(euro($0))/\(offer.baseUnitLabel)" } ?? ""))
                .font(.caption).foregroundStyle(Theme.C.text2).lineLimit(1).padding(.top, 2)
            if let b = offer.bonusText { DealBadge(text: b, style: .ok).lineLimit(1).padding(.top, 4) }  // 39
            Spacer(minLength: 10)
            HStack {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(euro(offer.priceCents)).font(.system(.callout, weight: .heavy)).monospacedDigit()
                    if let regular = offer.regularPriceCents {
                        Text(euro(regular).replacingOccurrences(of: " €", with: "")).font(.system(size: 11, weight: .semibold))
                            .strikethrough().foregroundStyle(Theme.C.onInk3)
                    }
                }
                .foregroundStyle(.white).padding(.horizontal, 14).frame(height: 36).background(Theme.C.ink, in: Capsule())
                Spacer(minLength: 4)
                Button { withAnimation(Theme.spring) { store.addToList(offer) } } label: {
                    Image(systemName: onList ? "checkmark" : "plus")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.C.ink)
                        .frame(width: 38, height: 38)
                        .background(onList ? Theme.C.lime : Theme.C.plate, in: Circle())
                        .shadow(color: .black.opacity(0.08), radius: 5, y: 4)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(PressableStyle())
                .sensoryFeedback(.success, trigger: onList)
                .accessibilityLabel(onList ? "Auf der Liste" : "Zur Einkaufsliste")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hue.tint, in: RoundedRectangle(cornerRadius: Theme.R.offer, style: .continuous))
        .overlay(alignment: .topLeading) {
            if let d = offer.discount { PriceBurst(percent: d).offset(x: -6, y: -8) }
        }
        .overlay(alignment: .topTrailing) { VerdictBadge(verdict: offer.verdict, emojiOnly: true).padding(10) }  // 28
    }
}

/// „Knaller der Woche“ (S4): Limetten-Coupon mit Kerben, Name in Fraunces, Produkt, Stern in Tinte.
struct KnallerCard: View {
    let offer: OfferDTO

    var body: some View {
        let hue = Theme.hue(category: offer.category)
        ZStack(alignment: .topLeading) {
            CouponShape().fill(Theme.C.lime)
            Line().stroke(Color.black.opacity(0.18), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                .frame(height: 2).padding(.horizontal, 18).offset(y: 150 * 0.64)
            VStack(alignment: .leading, spacing: 4) {
                Text("KNALLER DER WOCHE").font(.system(.caption2, weight: .heavy)).tracking(0.7).opacity(0.6)
                Text(offer.title).font(Theme.F.cardTitle(25)).lineLimit(1).minimumScaleFactor(0.7)
                Text("bei \(Labels.chain(offer.chain))").font(.custom("FrauncesV3-TextItalic", size: 25, relativeTo: .title2))
            }
            .foregroundStyle(Theme.C.ink)
            .padding(.leading, 18).padding(.top, 16).padding(.trailing, 140)
            RemoteImage(url: URL(string: offer.imageUrl)) { Text(hue.emoji).font(.system(size: 76)) }
                .frame(width: 90, height: 90).rotationEffect(.degrees(-12))
                .shadow(color: .black.opacity(0.2), radius: 5, y: 10)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 58).padding(.top, 2)
            if let d = offer.discount {
                PriceBurst(percent: d, size: 66, fill: Theme.C.ink, ink: Theme.C.lime)
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 10).padding(.top, 12)
            }
            VerdictBadge(verdict: offer.verdict, long: true)
                .frame(maxHeight: .infinity, alignment: .bottomLeading).padding(.leading, 18).padding(.bottom, 12)
        }
        .frame(height: 150)
        .accessibilityElement(children: .combine)
    }

    private struct Line: Shape {
        func path(in r: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
    }
}

/// S9 Angebotsdetail: wo, welcher Laden, Liste, Merken, passende Rezepte, Alternativen.
struct OfferDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let offer: OfferDTO
    @State private var zoom = false
    @State private var count = Demo.screen == "offer" ? 2 : 1
    @State private var bars: [OfferHistoryDTO.Point] = []  // Mini-Preisverlauf
    @State private var showHistory = false

    var body: some View {
        let hue = Theme.hue(category: offer.category)
        let stores = store.household?.stores.filter { $0.chain == offer.chain && $0.enabled } ?? []
        let meals = store.plan?.entries.filter { $0.recipe.ingredients.contains { $0.offerId == offer.id } } ?? []
        let similar = store.offers
            .filter { $0.category == offer.category && $0.id != offer.id && offer.category != "sonstiges" }
            .sorted { ($0.basePriceCents ?? .max) < ($1.basePriceCents ?? .max) }
            .prefix(8)
        let onList = store.isOnList(offer)
        let watched = store.watch(for: offer) != nil

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Oberer Teil weiß (Snack-Shop-Vorlage): Kopf, Produkt groß, Menge, Preis-Pille
                VStack(spacing: 0) {
                    HStack {
                        RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                        Spacer()
                        Text("Angebot").font(.system(.headline, weight: .heavy))
                        Spacer()
                        RoundIconButton(systemName: watched ? "heart.fill" : "heart", label: watched ? "Nicht mehr merken" : "Merken") {
                            Task { await store.toggleWatch(offer) }
                        }
                        .symbolEffect(.bounce, value: watched)
                    }
                    ZStack {
                        Circle().fill(hue.tint).frame(width: 230, height: 230)
                        RemoteImage(url: URL(string: offer.imageUrl)) { Text(hue.emoji).font(.system(size: 150)) }
                            .frame(width: 190, height: 190)
                            .shadow(color: .black.opacity(0.2), radius: 9, y: 18)
                            .scaleEffect(zoom ? 1 : 0.8).opacity(zoom ? 1 : 0)
                    }
                    .frame(height: 250)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topLeading) {
                        if let d = offer.discount { PriceBurst(percent: d, size: 100).padding(.leading, 10).padding(.top, -4) }
                    }
                    .padding(.top, 10)
                    .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) { zoom = true } }
                    QtyStepper(value: $count, range: 1...20, large: true).padding(.top, -4)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(euro(offer.priceCents * count)).font(.system(.title3, weight: .heavy)).monospacedDigit()
                            .contentTransition(.numericText())
                        if let regular = offer.regularPriceCents {
                            Text(euro(regular * count).replacingOccurrences(of: " €", with: "")).font(.system(size: 12, weight: .semibold))
                                .strikethrough().foregroundStyle(Theme.C.onInk3).contentTransition(.numericText())
                        }
                    }
                    .foregroundStyle(.white).padding(.horizontal, 16).frame(height: 42).background(Theme.C.ink, in: Capsule())
                    .padding(.top, 8).padding(.bottom, 26)
                }
                .padding(.horizontal, Theme.pagePadding).padding(.top, 8)
                .background(Theme.C.card.ignoresSafeArea(edges: .top))

                // Unteres Sheet (Creme): Name, Fakten-Chips, Mini-Preisverlauf
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(offer.title).font(Theme.F.title).tracking(-0.84).lineLimit(3)
                                Text([offer.brand.isEmpty ? nil : offer.brand, offer.amountText,
                                      offer.basePriceCents.map { "\(euro($0))/\(offer.baseUnitLabel)" },
                                      offer.startsLater ? "ab \(shortDate(offer.validFrom))" : offer.daysLeft.map { $0 <= 0 ? "nur heute" : "noch \($0) Tage" }]
                                    .compactMap { $0 }.joined(separator: " · "))
                                    .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                            }
                            Spacer()
                            RoundIconButton(systemName: watched ? "bookmark.fill" : "bookmark", fill: Theme.C.card, label: "Auf die Merkliste") {
                                Task { await store.toggleWatch(offer) }
                            }
                        }
                        FlowLayout(spacing: 6) {
                            StoreChip(chain: offer.chain)
                            VerdictBadge(verdict: offer.verdict)
                            if let b = offer.bonusText { DealBadge(text: b, style: .ok) }  // Rewe-Bonus (39)
                            LabelBadges(offer: offer)  // 49
                        }
                        if !bars.isEmpty {
                            Button { withAnimation(Theme.spring) { showHistory.toggle() } } label: { miniHistory }
                                .buttonStyle(PressableStyle())
                                .accessibilityLabel(showHistory ? "Preisverlauf zuklappen" : "Preisverlauf öffnen")
                                .padding(.top, 4)
                        }
                    }
                    // Ab hier noch nicht gemockt (redesign-v3.md 7, Gruppe C)
                    if showHistory || bars.isEmpty { PriceHistoryCard(offer: offer).appear(delay: 0.03) }  // Preisverlauf (28)
                    StockupTipCard(offer: offer)  // Vorratstipp (31)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        fact("scalemass.fill", Theme.C.kcal, "Menge", offer.amountText ?? "–")
                        fact("eurosign.circle.fill", Theme.C.warning, "Grundpreis", offer.basePriceCents.map { "\(euro($0))/\(offer.baseUnitLabel)" } ?? "–")
                        fact("calendar", Theme.C.accent, "Gültig", offer.daysLeft.map { $0 <= 0 ? "nur noch heute" : "noch \($0) Tage" } ?? "bis \(offer.validTo)")
                        fact("square.grid.2x2.fill", hue.color, "Kategorie", Labels.categories.first { $0.0 == offer.category }?.1 ?? "Sonstiges")
                    }
                    .appear(delay: 0.05)

                    if offer.hasLabels { LabelsInfoCard(offer: offer).appear(delay: 0.06) }  // Erklärung + Quelle (49)
                    OfferNutritionCard(offer: offer)  // nur bei sicherer Zuordnung (2)

                    section("Erhältlich bei") {
                        if stores.isEmpty {
                            Text("Alle \(Labels.chain(offer.chain))-Filialen in deiner Region").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                        } else {
                            let pins = stores.filter { $0.lat != nil }
                            if !pins.isEmpty {
                                Map(initialPosition: .automatic) {
                                    ForEach(pins, id: \.self) { s in
                                        Marker(s.storeName, coordinate: CLLocationCoordinate2D(latitude: s.lat!, longitude: s.lng!))
                                            .tint(Theme.storeColor(s.chain))
                                    }
                                }
                                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                                .frame(height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
                                .allowsHitTesting(false)
                            }
                            ForEach(stores, id: \.self) { s in
                                HStack(spacing: 12) {
                                    StoreLogo(chain: s.chain, size: 38)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.storeName.isEmpty ? Labels.chain(s.chain) : s.storeName).font(.system(.subheadline, weight: .semibold))
                                        if let a = s.address, !a.isEmpty { Text(a).font(Theme.F.micro).foregroundStyle(Theme.C.text2) }
                                    }
                                    Spacer()
                                    if let lat = s.lat, let lng = s.lng, let url = URL(string: "maps://?daddr=\(lat),\(lng)") {
                                        Link(destination: url) {
                                            Label("Route", systemImage: "arrow.triangle.turn.up.right.circle.fill").font(Theme.F.micro)
                                                .padding(.horizontal, 10).frame(height: 30).background(Theme.C.accentSoft, in: Capsule())
                                                .foregroundStyle(Theme.C.accentDeep)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !meals.isEmpty {
                        section("Passt zu deinem Plan") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(meals, id: \.self) { meal in
                                        NavigationLink { RecipeDetailView(meal: meal) } label: { MealCardSmall(meal: meal) }.buttonStyle(PressableStyle())
                                    }
                                }
                                .padding(.top, 40).padding(.bottom, 8).padding(.horizontal, 2)
                            }
                        }
                    }

                    if !similar.isEmpty {
                        section("Ähnliche Angebote") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(Array(similar)) { o in
                                        NavigationLink { OfferDetailView(offer: o) } label: { MiniOffer(offer: o) }.buttonStyle(PressableStyle())
                                    }
                                }
                                .padding(.horizontal, 2).padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 22)
                .padding(.bottom, 120)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.C.bg, in: UnevenRoundedRectangle(topLeadingRadius: 36, topTrailingRadius: 36, style: .continuous))
                .padding(.top, -10)
            }
        }
        .background(alignment: .top) { Theme.C.card.frame(height: 600).ignoresSafeArea() }
        .background(Theme.C.bg.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            TotalBar(label: "Gesamt", value: {
                Text("\(count) × \(euro(offer.priceCents))").monospacedDigit().contentTransition(.numericText())
            }, buttonTitle: onList ? "Auf der Liste" : "Auf die Liste", symbol: onList ? "checkmark" : "bag") {
                withAnimation(Theme.spring) { store.addToList(offer, count: count) }
            }
            .sensoryFeedback(.success, trigger: onList)
            .padding(.bottom, 2)
        }
        .hidesTabBar()
        .toolbar(.hidden, for: .navigationBar)
        .task { bars = (try? await store.offerHistory(offer.id))?.points ?? [] }
    }

    /// 12 Balken der letzten Wochen: Normalwochen `surface`, Angebote `chipBorder`, aktuelle Woche Limette mit Rand.
    private var miniHistory: some View {
        let weeks = Dictionary(grouping: bars, by: \.week).sorted { $0.key < $1.key }.suffix(12)
        let prices = weeks.map { w in w.value.map(\.priceCents).min() ?? 0 }
        let top = Double(prices.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { i, w in
                let isNow = i == weeks.count - 1
                let offerWeek = w.value.contains { $0.isOffer }
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isNow ? Theme.C.lime : offerWeek ? Theme.C.chipBorder : Theme.C.surface)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(isNow ? Theme.C.ink : .clear, lineWidth: 2))
                    .frame(height: 44 * max(0.2, Double(prices[i]) / top))
            }
        }
        .frame(height: 44, alignment: .bottom)
    }

    private func darkChip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(Theme.F.micro).foregroundStyle(.white)
            .padding(.horizontal, 10).frame(height: 26).background(Color.white.opacity(0.14), in: Capsule())
    }

    private func fact(_ symbol: String, _ color: Color, _ title: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
                .frame(width: 32, height: 32).background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                Text(value).font(.system(.footnote, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .card(radius: Theme.R.tile)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.F.headline)
            content()
        }
        .padding(16)
        .card()
        .appear(delay: 0.1)
    }
}

/// Kleine Angebotskachel für horizontale Listen.
struct MiniOffer: View {
    let offer: OfferDTO

    var body: some View {
        let hue = Theme.hue(category: offer.category)
        VStack(alignment: .leading, spacing: 4) {
            RemoteImage(url: URL(string: offer.imageUrl)) { Text(hue.emoji).font(.system(size: 30)) }
                .padding(8).frame(width: 112, height: 80).background(hue.tint, in: RoundedRectangle(cornerRadius: 14))
            Text(offer.title).font(.system(.caption, weight: .semibold)).lineLimit(1).foregroundStyle(Theme.C.text1)
            Text(euro(offer.priceCents)).font(.system(.subheadline, design: .rounded, weight: .bold)).foregroundStyle(Theme.C.text1)
            StoreChip(chain: offer.chain)
        }
        .frame(width: 112)
    }
}
