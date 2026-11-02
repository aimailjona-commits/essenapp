import SwiftUI

// Ersatzzutaten (7): Zutat lange drücken (Rezept S3, Kochmodus S18) → „Ersatz finden“ → Sheet S26.

/// = backend SubstitutesOut.
struct SubstitutesDTO: Decodable {
    struct Offer: Decodable, Hashable {
        var id: Int
        var chain: String
        var priceCents: Int
    }
    struct Ingredient: Decodable, Hashable {
        var name: String
        var amount: Double
        var unit: String
        var inPantry: Bool
        var offer: Offer?
    }
    struct Option: Decodable, Hashable {
        var note: String  // Wirkung, z. B. „cremiger, weniger flüssig“
        var ingredients: [Ingredient]
    }
    struct Original: Decodable {
        var name: String
        var amount: Double?
        var unit: String?
    }
    var ingredient: Original
    var source: String  // tabelle | ki
    var options: [Option]
}

extension AppStore {
    func substitutes(_ recipeId: Int, _ index: Int) async throws -> SubstitutesDTO {
        demo ? Demo.substitutes : try await api.request("GET", "/recipes/\(recipeId)/ingredients/\(index)/substitutes", timeout: 60)
    }

    /// Ersetzt die Zutat in diesem Rezept (globales Rezept → Kopie für den Haushalt). Plan-Gericht: Plan, Liste und
    /// Nährwerte neu laden (nil). Gespeichertes Rezept: das geänderte Rezept als neues „Gericht“ für S3.
    func substitute(_ meal: MealDTO, index: Int, with option: SubstitutesDTO.Option) async throws -> MealDTO? {
        struct Line: Encodable { var name: String; var amount: Double; var unit: String }
        struct Body: Encodable { var ingredients: [Line] }
        if demo {
            var r = meal.recipe
            r.ingredients.replaceSubrange(index...index, with: option.ingredients.map { i in
                IngredientDTO(name: i.name, amount: i.amount, unit: i.unit, offerId: i.offer?.id, inPantry: i.inPantry)
            })
            if meal.id != nil, var p = plan {
                for i in p.entries.indices where p.entries[i].id == meal.id { p.entries[i].recipe = r }
                plan = p
                return nil
            }
            var m = meal
            m.recipe = r
            return m
        }
        let body = Body(ingredients: option.ingredients.map { i in Line(name: i.name, amount: i.amount, unit: i.unit) })
        let out: RecipeDTO = try await api.request("POST", "/recipes/\(meal.recipe.id)/ingredients/\(index)/substitute", body: body, timeout: 60)
        recipesVersion += 1
        guard meal.id != nil else { return try await savedMeal(out.id) }
        plan = (try? await api.request("GET", "/plans/current")) ?? plan
        await loadLists()
        await loadNutrition()
        return nil
    }
}

/// S26 „Ersatz finden“: 2–4 Alternativen mit umgerechneter Menge, Wirkung, „im Vorrat“ / „im Angebot“.
struct SubstituteSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let meal: MealDTO
    let index: Int
    var done: (MealDTO?) -> Void = { _ in }
    @State private var result: SubstitutesDTO?
    @State private var error: String?
    @State private var busy: Int?
    @State private var applied = 0

    private var original: IngredientDTO? { meal.recipe.ingredients.indices.contains(index) ? meal.recipe.ingredients[index] : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ersatz für \(original?.name ?? "Zutat")").font(Theme.F.title)
                    Text(subtitle).font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                }
                Spacer()
                RoundIconButton(systemName: "xmark", label: "Schließen") { dismiss() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let result {
                        if result.options.isEmpty {
                            EmptyState(emoji: "🤷", title: "Kein Ersatz gefunden", text: "Für diese Zutat kennen wir gerade keine passende Alternative.")
                        }
                        ForEach(Array(result.options.enumerated()), id: \.offset) { i, option in
                            optionCard(i, option).appear(delay: Double(i) * 0.06)
                        }
                        if !result.options.isEmpty {
                            Text("Antippen ersetzt die Zutat nur in diesem Rezept – Nährwerte und Kosten werden neu berechnet.")
                                .font(Theme.F.micro).foregroundStyle(Theme.C.text2).padding(.top, 4)
                        }
                    } else if let error {
                        ErrorState(message: error) { Task { await load() } }
                    } else {
                        ForEach(0..<3, id: \.self) { _ in SkeletonCard(height: 104) }
                        Text("Suche passenden Ersatz …").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .padding(Theme.pagePadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.C.bg)
        .sensoryFeedback(.success, trigger: applied)
        .task { if result == nil { await load() } }
    }

    private var subtitle: String {
        let amount = original.map { o in "\(qty(o.amount, o.unit)) im Rezept" } ?? ""
        guard let result else { return amount }
        return "\(amount) · \(result.source == "ki" ? "Vorschläge der KI" : "aus unserer Ersatz-Tabelle")"
    }

    private func optionCard(_ i: Int, _ option: SubstitutesDTO.Option) -> some View {
        let main = option.ingredients.first?.name ?? ""
        return Button { Task { await apply(i, option) } } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(main) statt \(original?.name ?? "")").font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.C.text1).multilineTextAlignment(.leading)
                    Text(option.ingredients.map { g in "\(qty(g.amount, g.unit)) \(g.name)" }.joined(separator: " + "))
                        .font(Theme.F.callout).monospacedDigit().foregroundStyle(Theme.C.accentDeep)
                    if !option.note.isEmpty {
                        Text(option.note).font(Theme.F.caption).foregroundStyle(Theme.C.text2).multilineTextAlignment(.leading)
                    }
                    FlowLayout(spacing: 6) {
                        ForEach(option.ingredients, id: \.self) { g in
                            if g.inPantry { DealBadge(text: option.ingredients.count > 1 ? "\(g.name) im Vorrat" : "im Vorrat", style: .ok) }
                            if let offer = g.offer {
                                DealBadge(text: "im Angebot \(euro(offer.priceCents))")
                                StoreChip(chain: offer.chain)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                if busy == i {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.C.text3)
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(radius: Theme.R.tile)
        }
        .buttonStyle(PressableStyle())
        .disabled(busy != nil)
        .accessibilityHint("Ersetzt \(original?.name ?? "die Zutat") in diesem Rezept")
    }

    private func load() async {
        error = nil
        do {
            let found = try await store.substitutes(meal.recipe.id, index)
            withAnimation(Theme.spring) { result = found }
        } catch APIError.http(502) {
            error = "Die Ersatz-Suche ist gerade nicht erreichbar."
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func apply(_ i: Int, _ option: SubstitutesDTO.Option) async {
        busy = i
        defer { busy = nil }
        do {
            let updated = try await store.substitute(meal, index: index, with: option)
            applied += 1
            store.flash("Ersetzt: \(original?.name ?? "") → \(option.ingredients.map(\.name).joined(separator: " + "))")
            done(updated)
            dismiss()
        } catch {
            store.flash("Nicht ersetzt: \(error.localizedDescription)")
        }
    }
}
