import MapKit
import SwiftUI

/// S4 Angebote + S10 Merkliste (lokal).
struct OffersView: View {
    @Environment(AppStore.self) private var store
    @State private var chain: String?
    @State private var category: String?
    @State private var search = ""
    @State private var watchlist = false

    var body: some View {
        let all = watchlist ? store.offers.filter { store.watchlist.contains($0.id) } : store.offers
        let byChain = Dictionary(grouping: all, by: \.chain)
        let chains = Labels.chains.map(\.key).filter { byChain[$0] != nil }
        let filtered = all.filter {
            (chain == nil || $0.chain == chain) && (category == nil || $0.category == category)
                && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
        }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: []) {
                NavigationLink { StoreMapView() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.C.accent)
                        Text("PLZ \(store.household?.plz ?? "") · \(store.household?.stores.filter(\.enabled).count ?? 0) Läden · \(store.household?.radiusKm ?? 5) km")
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.C.text3)
                    }
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(Theme.C.text1)
                    .padding(.horizontal, 14).frame(height: 40)
                    .background(Theme.C.card, in: Capsule()).overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: 0.5))
                }
                .buttonStyle(PressableStyle())

                DisplayHeader(line1: watchlist ? "Merkliste" : "Angebote", line2: watchlist ? "\(all.count) gemerkt" : "\(all.count) diese Woche")
                Picker("", selection: $watchlist.animation(Theme.spring)) {
                    Text("Angebote").tag(false)
                    Text("Merkliste · \(store.watchlist.count)").tag(true)
                }
                .pickerStyle(.segmented)
                SearchField(text: $search, placeholder: "Produkt suchen")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(label: "Alle", count: all.count, selected: chain == nil) { withAnimation(Theme.spring) { chain = nil } }
                        ForEach(chains, id: \.self) { c in
                            FilterChip(label: Labels.chain(c), count: byChain[c]?.count, color: Theme.storeColor(c), selected: chain == c) {
                                withAnimation(Theme.spring) { chain = chain == c ? nil : c }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                }
                .padding(.horizontal, -Theme.pagePadding)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Labels.categories, id: \.0) { c in
                            let hue = Theme.hue(category: c.0)
                            FilterChip(label: c.1, color: hue.color, selected: category == c.0) {
                                withAnimation(Theme.spring) { category = category == c.0 ? nil : c.0 }
                            }
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                }
                .padding(.horizontal, -Theme.pagePadding)

                if store.offers.isEmpty {
                    EmptyState(emoji: "🏷️", title: "Noch keine Angebote", text: "Die Angebote deiner Läden werden wöchentlich geladen.",
                               buttonTitle: "Jetzt laden") { Task { await store.refreshOffers() } }
                } else if filtered.isEmpty {
                    EmptyState(emoji: watchlist ? "🤍" : "🔍", title: watchlist ? "Noch nichts gemerkt" : "Nichts gefunden",
                               text: watchlist ? "Tippe bei einem Angebot aufs Herz." : "Andere Filter probieren.")
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        ForEach(filtered) { offer in
                            NavigationLink { OfferDetailView(offer: offer) } label: { OfferCard(offer: offer) }
                                .buttonStyle(PressableStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await store.refreshOffers() }
    }
}

extension OfferDTO {
    var discount: Int? {
        guard let regular = regularPriceCents, regular > priceCents else { return nil }
        return Int((Double(regular - priceCents) / Double(regular) * 100).rounded())
    }

    var baseUnitLabel: String { unit == "stk" ? "Stk" : unit == "ml" ? "l" : "kg" }

    var amountText: String? {
        amount.map { "\($0.formatted()) \(unit == "stk" ? "Stück" : unit)" }
    }

    var daysLeft: Int? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let end = f.date(from: validTo) else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: end).day
    }
}

struct OfferCard: View {
    @Environment(AppStore.self) private var store
    let offer: OfferDTO

    var body: some View {
        let hue = Theme.hue(category: offer.category)
        let onList = store.isOnList(offer)
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(hue.tint)
                RemoteImage(url: URL(string: offer.imageUrl)) { Text(hue.emoji).font(.system(size: 44)) }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                DealBadge(text: offer.discount.map { "−\($0) %" } ?? "Angebot").padding(8)
            }
            .frame(height: 122)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    withAnimation(Theme.spring) { store.addToList(offer) }
                } label: {
                    Image(systemName: onList ? "checkmark" : "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(onList ? Theme.C.text1 : .white)
                        .frame(width: 34, height: 34)
                        .background(onList ? Theme.C.highlight : Theme.C.action, in: Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(PressableStyle())
                .sensoryFeedback(.success, trigger: onList)
                .padding(8)
                .accessibilityLabel(onList ? "Auf der Liste" : "Zur Einkaufsliste")
            }
            Text(offer.title).font(.system(.subheadline, weight: .bold)).lineLimit(2).foregroundStyle(Theme.C.text1).padding(.top, 6)
            if let amount = offer.amountText {
                Text("\(amount)\(offer.basePriceCents.map { " · \(euro($0))/\(offer.baseUnitLabel)" } ?? "")")
                    .font(Theme.F.micro).foregroundStyle(Theme.C.text2).lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(euro(offer.priceCents)).font(Theme.F.price).monospacedDigit().foregroundStyle(Theme.C.text1)
                if let regular = offer.regularPriceCents {
                    Text(euro(regular)).font(Theme.F.micro).strikethrough().foregroundStyle(Theme.C.text3)
                }
            }
            .padding(.top, 2)
            StoreChip(chain: offer.chain)
        }
        .padding(8)
        .card(radius: 22)
    }
}

/// S9 Angebotsdetail: wo, welcher Laden, Liste, Merken, passende Rezepte, Alternativen.
struct OfferDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let offer: OfferDTO
    @State private var zoom = false

    var body: some View {
        let hue = Theme.hue(category: offer.category)
        let stores = store.household?.stores.filter { $0.chain == offer.chain && $0.enabled } ?? []
        let meals = store.plan?.entries.filter { $0.recipe.ingredients.contains { $0.offerId == offer.id } } ?? []
        let similar = store.offers
            .filter { $0.category == offer.category && $0.id != offer.id && offer.category != "sonstiges" }
            .sorted { ($0.basePriceCents ?? .max) < ($1.basePriceCents ?? .max) }
            .prefix(8)
        let onList = store.isOnList(offer)
        let watched = store.watchlist.contains(offer.id)

        ZStack(alignment: .bottom) {
            Theme.C.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: Theme.R.sheet, style: .continuous).fill(hue.tint)
                        RemoteImage(url: URL(string: offer.imageUrl)) { Text(hue.emoji).font(.system(size: 110)) }
                            .padding(36)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .scaleEffect(zoom ? 1 : 0.85)
                            .opacity(zoom ? 1 : 0)
                        HStack {
                            RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                            Spacer()
                            if let d = offer.discount { DealBadge(text: "−\(d) %").scaleEffect(1.2) }
                            Spacer()
                            RoundIconButton(systemName: watched ? "heart.fill" : "heart", label: "Merken") {
                                withAnimation(Theme.spring) { store.toggleWatch(offer) }
                            }
                            .foregroundStyle(watched ? Theme.C.deal : Theme.C.text1)
                            .symbolEffect(.bounce, value: watched)
                        }
                        .padding(14)
                    }
                    .frame(height: 320)
                    .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { zoom = true } }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack { StoreChip(chain: offer.chain); if !offer.brand.isEmpty { Text(offer.brand).font(Theme.F.micro).foregroundStyle(Theme.C.text2) } }
                        Text(offer.title).font(Theme.F.title)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(euro(offer.priceCents)).font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
                            if let regular = offer.regularPriceCents {
                                Text(euro(regular)).font(.system(.body, design: .rounded)).strikethrough().foregroundStyle(Theme.C.text3)
                            }
                        }
                        if let regular = offer.regularPriceCents, regular > offer.priceCents {
                            Label("Du sparst \(euro(regular - offer.priceCents))", systemImage: "arrow.down.circle.fill")
                                .font(Theme.F.callout).foregroundStyle(Theme.C.success)
                        }
                    }
                    .appear()

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        fact("scalemass.fill", Theme.C.kcal, "Menge", offer.amountText ?? "–")
                        fact("eurosign.circle.fill", Theme.C.warning, "Grundpreis", offer.basePriceCents.map { "\(euro($0))/\(offer.baseUnitLabel)" } ?? "–")
                        fact("calendar", Theme.C.accent, "Gültig", offer.daysLeft.map { $0 <= 0 ? "nur noch heute" : "noch \($0) Tage" } ?? "bis \(offer.validTo)")
                        fact("square.grid.2x2.fill", hue.color, "Kategorie", Labels.categories.first { $0.0 == offer.category }?.1 ?? "Sonstiges")
                    }
                    .appear(delay: 0.05)

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
                                    Text(String(Labels.chain(s.chain).prefix(1))).font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white).frame(width: 36, height: 36)
                                        .background(Theme.storeColor(s.chain), in: RoundedRectangle(cornerRadius: 11))
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
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 200)
            }
            Button { withAnimation(Theme.spring) { store.addToList(offer) } } label: {
                Label(onList ? "Auf der Einkaufsliste" : "Zur Einkaufsliste", systemImage: onList ? "checkmark" : "cart.badge.plus")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PrimaryButtonStyle(color: onList ? Theme.C.accentDeep : Theme.C.action))
            .sensoryFeedback(.success, trigger: onList)
            .padding(.horizontal, Theme.pagePadding).padding(.bottom, Theme.ctaAboveTabBar)
        }
        .toolbar(.hidden, for: .navigationBar)
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
