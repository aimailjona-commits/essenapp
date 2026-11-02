import SwiftUI

/// S4 Angebote (Merkliste folgt in Phase 5).
struct OffersView: View {
    @Environment(AppStore.self) private var store
    @State private var chain: String?
    @State private var category: String?
    @State private var search = ""
    @State private var watchlist = false

    private var filtered: [OfferDTO] {
        store.offers.filter {
            (chain == nil || $0.chain == chain) && (category == nil || $0.category == category)
                && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("\(store.household?.plz ?? "") · \(store.household?.stores.filter(\.enabled).count ?? 0) Läden", systemImage: "mappin")
                        .font(.system(.subheadline, weight: .semibold))
                        .padding(.horizontal, 16).frame(height: 44).background(Theme.C.cardTop, in: Capsule()).softShadow()
                    Spacer()
                }
                DisplayHeader(line1: "Angebote", line2: "diese Woche")
                Picker("", selection: $watchlist) {
                    Text("Angebote · \(store.offers.count)").tag(false)
                    Text("Merkliste").tag(true)
                }
                .pickerStyle(.segmented)

                if watchlist {
                    EmptyState(symbol: "heart", title: "Merkliste",
                               text: "Merk dir Lieblingsprodukte – wir sagen Bescheid, wenn sie im Angebot sind. Kommt in Phase 5.")
                } else {
                    SearchField(text: $search, placeholder: "Produkt suchen")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(label: "Alle", count: store.offers.count, selected: chain == nil) { chain = nil }
                            ForEach(store.household?.stores.filter(\.enabled) ?? [], id: \.chain) { s in
                                FilterChip(label: Labels.chain(s.chain), count: store.offers.filter { $0.chain == s.chain }.count,
                                           selected: chain == s.chain) { chain = s.chain }
                            }
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Labels.categories, id: \.0) { c in
                                FilterChip(label: c.1, selected: category == c.0) { category = category == c.0 ? nil : c.0 }
                            }
                        }
                    }
                    if store.offers.isEmpty {
                        EmptyState(symbol: "tag", title: "Noch keine Angebote",
                                   text: "Die Angebote deiner Läden werden wöchentlich geladen.",
                                   buttonTitle: "Jetzt laden") { Task { await store.refreshOffers() } }
                    } else if filtered.isEmpty {
                        EmptyState(symbol: "magnifyingglass", title: "Nichts gefunden", text: "Andere Filter probieren.")
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                            ForEach(filtered) { OfferCard(offer: $0) }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
        }
        .refreshable { await store.refreshOffers() }
    }
}

struct OfferCard: View {
    let offer: OfferDTO

    private var discount: Int? {
        guard let regular = offer.regularPriceCents, regular > offer.priceCents else { return nil }
        return Int((Double(regular - offer.priceCents) / Double(regular) * 100).rounded())
    }

    private var tint: Color {
        let tints = Theme.C.listTints
        return switch offer.category {
        case "fleisch_fisch": tints[0]
        case "obst_gemuese": tints[1]
        case "drogerie", "haushalt": tints[2]
        case "vorrat": tints[3]
        default: tints[4]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint)
                AsyncImage(url: URL(string: offer.imageUrl)) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                    .padding(10)
                DealBadge(text: discount.map { "−\($0) %" } ?? "Angebot").padding(8)
            }
            .frame(height: 118)
            Text(offer.title).font(.system(.subheadline, weight: .bold)).lineLimit(2).padding(.top, 6)
            if let amount = offer.amount {
                Text("\(amount.formatted()) \(offer.unit)\(offer.basePriceCents.map { " · \(euro($0))/\(offer.unit == "stk" ? "Stk" : offer.unit == "ml" ? "l" : "kg")" } ?? "")")
                    .font(Theme.F.micro).foregroundStyle(Theme.C.text2)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(euro(offer.priceCents)).font(.system(.title3, weight: .heavy)).monospacedDigit()
                if let regular = offer.regularPriceCents {
                    Text(euro(regular)).font(Theme.F.micro).strikethrough().foregroundStyle(Theme.C.text3)
                }
            }
            .padding(.top, 4)
            StoreChip(name: Labels.chain(offer.chain))
        }
        .padding(8)
        .background(Theme.C.cardTop, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .softShadow()
    }
}
