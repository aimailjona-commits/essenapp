import SwiftUI

extension IngredientDTO: Identifiable {
    public var id: String { "\(name)|\(unit)" }
}

/// Feature 1: Zutat ohne verknüpftes Angebot → passende Angebote der Woche (sonst Normalpreis-Schätzung).
/// Ohne eigenes v8-Mockup: Sheet-Look und Zeilen wie S10 „Produkt merken“.
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
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Angebote für").font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                            Text(ingredient.name).font(Theme.F.t2)
                        }
                        Spacer()
                        CloseButton { dismiss() }
                    }
                    if matches.isEmpty {
                        Ill("binoculars").frame(width: 160).frame(maxWidth: .infinity).padding(.top, 24)
                        Text("Diese Woche nicht im Angebot").font(Theme.F.t2).padding(.top, 16)
                        Text(ingredient.packPriceCents.map { "Normalpreis ca. \(euro($0)) (Schätzung)" } ?? "In keinem Prospekt deiner Läden.")
                            .font(Theme.F.text(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.C.ink2).padding(.top, 6)
                        if let list = store.householdList {
                            PrimaryButton(title: "Zur Einkaufsliste", icon: .bag) {
                                Task { await store.addItem(name: ingredient.name, to: list.id) }
                                store.flash("„\(ingredient.name)“ auf der Liste")
                                dismiss()
                            }
                            .padding(.top, 16)
                        }
                    } else {
                        SectionLabel("Diese Woche im Angebot", big: true).padding(.top, 22).padding(.bottom, 4)
                        ForEach(matches) { o in
                            Button { open = o } label: {
                                OfferLine(offer: o, parts: [Labels.chain(o.chain), o.amountText]) {
                                    Text(euro(o.priceCents)).font(Theme.F.text(17, .bold, relativeTo: .headline)).monospacedDigit()
                                }
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 40)
            }
            .background(Theme.C.bg)
            .navigationDestination(item: $open) { OfferDetailView(offer: $0) }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet8()
    }
}
