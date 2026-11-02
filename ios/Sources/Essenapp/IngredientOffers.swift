import SwiftUI

extension IngredientDTO: Identifiable {
    public var id: String { "\(name)|\(unit)" }
}

/// Feature 1: Zutat ohne verknüpftes Angebot → passende Angebote der Woche (sonst Normalpreis-Schätzung).
struct IngredientOffersSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let ingredient: IngredientDTO
    @State private var open: OfferDTO?

    /// Wortstämme der Zutat (≥ 4 Buchstaben), z.B. „Hähnchenbrust“ findet „Hähnchenbrustfilet“.
    private var matches: [OfferDTO] {
        let words = ingredient.name.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 4 }
        guard !words.isEmpty else { return [] }
        return store.offers
            .filter { o in let t = o.title.lowercased(); return words.contains { t.contains($0) || $0.contains(t) } }
            .filter { !["drogerie", "haushalt"].contains($0.category) }
            .sorted { ($0.basePriceCents ?? $0.priceCents) < ($1.basePriceCents ?? $1.priceCents) }
            .prefix(20).map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Angebote für").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                    Text(ingredient.name).font(Theme.F.title)
                    if matches.isEmpty {
                        EmptyState(emoji: "🔍", title: "Diese Woche nicht im Angebot",
                                   text: ingredient.packPriceCents.map { "Normalpreis ca. \(euro($0)) (Schätzung)" } ?? "In keinem Prospekt deiner Läden.")
                        if let list = store.householdList {
                            Button {
                                Task { await store.addItem(name: ingredient.name, to: list.id) }
                                store.flash("„\(ingredient.name)“ auf der Liste")
                                dismiss()
                            } label: { Label("Zur Einkaufsliste", systemImage: "cart.badge.plus") }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    } else {
                        ForEach(matches) { o in
                            Button { open = o } label: { OfferRow(offer: o) }.buttonStyle(PressableStyle())
                        }
                    }
                }
                .padding(Theme.pagePadding)
            }
            .background(Theme.C.bg)
            .navigationDestination(item: $open) { OfferDetailView(offer: $0) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
