import EssenappShareUI
import SwiftUI

// Meine Rezepte (Feature 3) und Nährwerte pro Person (Feature 2).

/// = backend RecipeCostOut (nur was die App braucht: welche Zutat gerade im Angebot ist).
struct RecipeCostDTO: Decodable {
    struct Line: Decodable {
        var name: String
        var offerId: Int?
        var inOffer: Bool
    }
    var lines: [Line]
}

extension AppStore {
    /// Alle gespeicherten Rezepte (Suche im Backend inkl. Tags); die Filter-Pillen filtern lokal, damit sie Anzahlen zeigen.
    func recipes(q: String) async throws -> [RecipeCard] {
        if demo { return q.isEmpty ? Demo.cards : Demo.cards.filter { c in c.title.localizedCaseInsensitiveContains(q) } }
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))
        let query = q.isEmpty ? "" : "&q=" + (q.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        return try await api.request("GET", "/recipes?filter=alle" + query)
    }

    /// Favoriten/≥ 4★, deren Kosten diese Woche zu ≥ 40 % aus Angeboten kommen.
    func recipeDeals() async throws -> [RecipeCard] {
        demo ? Demo.cards.filter { c in c.favorite && c.offerShare >= 0.4 } : try await api.request("GET", "/recipes/deals")
    }

    func recipe(_ id: Int) async throws -> RecipeDTO {
        guard !demo else {
            guard let r = [Demo.savedRecipe, Demo.importedRecipe].first(where: { r in r.id == id }) else { throw APIError.http(404) }
            return r
        }
        return try await api.request("GET", "/recipes/\(id)")
    }

    /// Gespeichertes Rezept als „Gericht“ für S3: Live-Kosten pro Portion, Angebotszutaten aus GET /recipes/{id}/cost.
    func savedMeal(_ id: Int) async throws -> MealDTO {
        var r = try await recipe(id)
        if !demo, let cost: RecipeCostDTO = try? await api.request("GET", "/recipes/\(id)/cost") {
            for i in r.ingredients.indices {
                let line = cost.lines.first { l in l.name == r.ingredients[i].name }
                r.ingredients[i].offerId = line?.inOffer == true ? line?.offerId : nil
            }
        }
        return MealDTO(id: nil, day: -1, mealType: r.mealType, costCents: (r.costPerServingCents ?? 0) * r.servings, locked: false,
                       recipe: r, portionsTotal: Double(r.servings))
    }

    /// Anlegen (POST) oder ändern (PATCH).
    func saveRecipe(id: Int?, _ body: RecipeDraft.Body) async throws {
        if !demo {
            let _: RecipeDTO = try await api.request(id == nil ? "POST" : "PATCH", id.map { i in "/recipes/\(i)" } ?? "/recipes",
                                                     body: body, timeout: 60)
        }
        recipesVersion += 1
    }

    func deleteRecipe(_ id: Int) async {
        do {
            if !demo { try await api.send("DELETE", "/recipes/\(id)") }
            recipesVersion += 1
            flash("Rezept gelöscht")
        } catch APIError.http(403) {
            flash("KI-Rezepte können nicht gelöscht werden")
        } catch {
            flash("Nicht gelöscht: \(error.localizedDescription)")
        }
    }

    /// Herz an/aus (gilt für den Haushalt). Gibt den neuen Stand zurück, bei Fehler den alten.
    func toggleFavorite(_ id: Int, current: Bool) async -> Bool {
        struct Out: Decodable { var favorite: Bool }
        var new = !current
        if !demo {
            guard let out: Out = try? await api.request("POST", "/recipes/\(id)/favorite") else {
                flash("Favorit nicht gespeichert")
                return current
            }
            new = out.favorite
        }
        if var p = plan {
            for i in p.entries.indices where p.entries[i].recipe.id == id { p.entries[i].recipe.favorite = new }
            plan = p
        }
        recipesVersion += 1
        return new
    }

    /// Bewertung nach „Gekocht ★“ (wer und wann setzt das Backend).
    func rate(_ id: Int, stars: Int, again: String, note: String) async -> Bool {
        struct Body: Encodable { var stars: Int; var again: String; var note: String }
        do {
            if !demo { try await api.send("POST", "/recipes/\(id)/rate", body: Body(stars: stars, again: again, note: note)) }
            recipesVersion += 1
            return true
        } catch {
            flash("Bewertung nicht gespeichert: \(error.localizedDescription)")
            return false
        }
    }

    /// „Diese Woche einplanen“: Rezept ersetzt das Gericht im Slot (ohne KI).
    func replace(_ entry: MealDTO, with recipeId: Int) async -> Bool {
        guard let id = entry.id else { return false }
        struct Body: Encodable { var recipeId: Int }
        do {
            if !demo {
                plan = try await api.request("POST", "/plans/current/entries/\(id)/replace", body: Body(recipeId: recipeId), timeout: 60)
                await loadLists()  // Backend gleicht die Einkaufsliste ab
                await loadNutrition()
            }
            return true
        } catch {
            flash("Nicht eingeplant: \(error.localizedDescription)")
            return false
        }
    }

    /// Tagesringe; solange Nährwerte fehlen (Zuordnung läuft im Hintergrund), einmal nach ~3 s Plan + Werte neu laden.
    func loadNutrition(retry: Bool = true) async {
        guard !demo, plan != nil else { return }
        nutrition = try? await api.request("GET", "/plans/current/nutrition")
        let pending = nutrition?.days.contains { d in d.members.contains { m in !m.complete } } ?? false
        guard retry, pending || plan?.entries.contains(where: { e in e.recipe.nutrition == nil }) == true else { return }
        try? await Task.sleep(for: .seconds(3))
        plan = (try? await api.request("GET", "/plans/current")) ?? plan
        await loadNutrition(retry: false)
    }

    /// Vorschläge im Rezept-Formular: Zutaten aus Plan und Vorrat.
    var knownIngredients: [String] {
        ((plan?.entries.flatMap { e in e.recipe.ingredients.map(\.name) } ?? []) + pantry.map(\.name)).uniqued().sorted()
    }
}

// MARK: S12 Meine Rezepte

/// Tab „Rezepte“, Pille „Meine Rezepte“: Filter, Suche, „Im Angebot diese Woche“, Raster.
struct MyRecipesList: View {
    @Environment(AppStore.self) private var store
    @Binding var filter: String
    @State private var query = ""
    @State private var cards: [RecipeCard]?
    @State private var deals: [RecipeCard] = []
    @State private var error: String?
    @State private var creating = false
    @State private var planning: RecipeCard?
    @State private var importing = false  // „Link einfügen“ (S22)
    @State private var opened: Int?  // importiertes Rezept öffnen

    static let filters = [("alle", "Alle"), ("favoriten", "♥ Favoriten"), ("eigene", "Eigene"), ("importiert", "Importiert"),
                          ("im_angebot", "Im Angebot"), ("zuletzt", "Zuletzt gekocht")]

    static func matches(_ c: RecipeCard, _ filter: String) -> Bool {
        switch filter {
        case "favoriten": c.favorite
        case "eigene": c.source == "user"
        case "importiert": ["instagram", "web", "shared"].contains(c.source)
        case "im_angebot": c.offerShare >= 0.4
        case "zuletzt": c.lastCooked != nil
        default: true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                DisplayHeader(line1: "Meine Rezepte", line2: cards.map { c in "\(c.count) gespeichert" } ?? "Gemerkt & eigene")
                RoundIconButton(systemName: "link", label: "Rezept aus Link importieren") { importing = true }
                RoundIconButton(systemName: "plus", dark: true, label: "Rezept anlegen") { creating = true }
            }
            SearchField(text: $query, placeholder: "Rezept oder Tag suchen")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.filters, id: \.0) { f in
                        FilterChip(label: f.1, count: cards.map { all in all.filter { c in Self.matches(c, f.0) }.count },
                                   selected: filter == f.0) { withAnimation(Theme.spring) { filter = f.0 } }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
            .padding(.horizontal, -Theme.pagePadding)

            if let cards {
                if filter == "alle" && query.isEmpty && !deals.isEmpty { dealsSection }
                let matching = cards.filter { c in Self.matches(c, filter) }
                let shown = filter == "zuletzt" ? matching.sorted { a, b in (a.lastCooked ?? "") > (b.lastCooked ?? "") } : matching
                if shown.isEmpty {
                    if cards.isEmpty && query.isEmpty {
                        EmptyState(emoji: "📖", title: "Noch keine Rezepte gespeichert",
                                   text: "Tippe bei einem Gericht aufs Herz oder lege dein eigenes Rezept an.",
                                   buttonTitle: "Rezept anlegen") { creating = true }
                    } else {
                        EmptyState(emoji: "🔍", title: "Nichts gefunden", text: "Für diese Auswahl gibt es noch keine Rezepte.")
                    }
                } else {
                    grid(shown)
                }
            } else if let error {
                ErrorState(message: error) { Task { await load() } }
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(0..<4, id: \.self) { _ in SkeletonCard(height: 210) }
                }
            }
        }
        .task(id: "\(query)|\(store.recipesVersion)") {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }  // erst suchen, wenn das Tippen pausiert
            guard !Task.isCancelled else { return }
            await load()
        }
        .sheet(isPresented: $creating) { RecipeFormSheet().presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
        .sheet(isPresented: $importing, onDismiss: { store.recipesVersion += 1 }) {
            ShareFlowView(input: nil, session: store.shareSession, onOpen: { id in
                importing = false
                opened = id
            }) { importing = false }
            .presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet)
        }
        .navigationDestination(item: $opened) { id in SavedRecipeView(recipeId: id) }
        .sheet(item: $planning) { card in
            PlanSlotSheet(recipeId: card.id, title: card.title).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet)
        }
    }

    private var dealsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("🔥 Im Angebot diese Woche").font(Theme.F.headline)
            Text("Lieblingsrezepte, die gerade günstig sind").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(deals) { card in
                        NavigationLink { SavedRecipeView(recipeId: card.id) } label: { RecipeGridCard(card: card).frame(width: 160) }
                            .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, Theme.pagePadding).padding(.top, 44).padding(.bottom, 12)
            }
            .padding(.horizontal, -Theme.pagePadding)
        }
    }

    private func grid(_ shown: [RecipeCard]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 54) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, card in
                ZStack(alignment: .topTrailing) {
                    NavigationLink { SavedRecipeView(recipeId: card.id) } label: { RecipeGridCard(card: card) }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            Button("Diese Woche einplanen", systemImage: "calendar.badge.plus") { planning = card }
                        }
                    HeartButton(on: card.favorite) { toggle(card) }.scaleEffect(0.85).padding(4)
                }
                .appear(delay: Double(i) * 0.04)
            }
        }
        .padding(.top, 44)
    }

    private func load() async {
        do {
            let found = try await store.recipes(q: query)
            withAnimation(Theme.spring) { cards = found }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        deals = (try? await store.recipeDeals()) ?? deals
    }

    private func toggle(_ card: RecipeCard) {
        guard let i = cards?.firstIndex(where: { c in c.id == card.id }) else { return }
        withAnimation(Theme.spring) { cards?[i].favorite.toggle() }
        Task {
            let new = await store.toggleFavorite(card.id, current: card.favorite)
            if let j = cards?.firstIndex(where: { c in c.id == card.id }) { cards?[j].favorite = new }
        }
    }
}

/// Raster-Karte (MealCard klein): Foto, Titel, Sterne, Preis/Portion, Badges.
struct RecipeGridCard: View {
    let card: RecipeCard

    var body: some View {
        VStack(spacing: 5) {
            Plate(url: mediaURL(card.imageUrl), size: 96, seed: card.title).padding(.top, -40)
            Text(card.title).font(.system(.subheadline, design: .rounded, weight: .bold)).lineLimit(2)
                .multilineTextAlignment(.center).frame(minHeight: 36).foregroundStyle(Theme.C.text1)
            if let avg = card.avgStars {
                StarsView(value: avg)
            } else {
                Text("noch nicht bewertet").font(Theme.F.micro).foregroundStyle(Theme.C.text3)
            }
            Text("\(euro(card.costPerServingCents)) / Portion").font(Theme.F.micro).foregroundStyle(Theme.C.text2).monospacedDigit()
            HStack(spacing: 4) {
                if card.offerShare >= 0.4 { DealBadge(text: "im Angebot", style: .soft) }
                if card.source == "instagram" { DealBadge(text: "Instagram", style: .ok) }
            }
            .frame(minHeight: 22)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .card()
    }
}

/// Lädt ein gespeichertes Rezept (inkl. Live-Kosten) und zeigt es als S3.
struct SavedRecipeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let recipeId: Int
    @State private var meal: MealDTO?
    @State private var error: String?

    var body: some View {
        Group {
            if let meal {
                RecipeDetailView(meal: meal)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                        if let error {
                            ErrorState(message: error) { Task { await load() } }
                        } else {
                            SkeletonCard(height: 260)
                            SkeletonCard(height: 90)
                            SkeletonCard(height: 220)
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                }
                .background(Theme.C.bg)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: store.recipesVersion) { await load() }
    }

    private func load() async {
        do {
            meal = try await store.savedMeal(recipeId)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// S19 „Diese Woche einplanen“: Rezept steht fest → Tag/Mahlzeit wählen; aus S2 („ersetzen durch eigenes Rezept“)
/// steht der Slot fest → Rezept aus „Meine Rezepte“ wählen. Ersetzt das Gericht im Slot (wie Würfeln, ohne KI).
struct PlanSlotSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var recipeId = 0
    var title = ""
    var entry: MealDTO?  // gesetzt = Rezept wählen
    @State private var busy: Int?
    @State private var cards: [RecipeCard]?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let entry {
                Text("Durch eigenes Rezept ersetzen").font(Theme.F.title)
                Text("\(Labels.dayNames[entry.day]) · \(Labels.meal(entry.mealType)): „\(entry.recipe.title)“ wird ersetzt.")
                    .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                recipeChoice(entry)
            } else {
                Text("Diese Woche einplanen").font(Theme.F.title)
                Text("„\(title)“ ersetzt das Gericht im gewählten Slot.").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                slotChoice
            }
        }
        .padding(Theme.pagePadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.C.bg)
        .task { if entry != nil { await loadCards() } }
    }

    @ViewBuilder private var slotChoice: some View {
        if let plan = store.plan, !plan.entries.isEmpty {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(plan.entries.sorted { a, b in (a.day, order(a.mealType)) < (b.day, order(b.mealType)) }, id: \.self) { e in
                        Button { Task { await pick(e, recipeId) } } label: {
                            row(e.recipe.imageUrl, e.recipe.title, "\(Labels.dayNames[e.day]) · \(Labels.meal(e.mealType))", e.recipe.title,
                                busy: busy == e.id, locked: e.locked)
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(busy != nil)
                    }
                }
                .padding(.bottom, 20)
            }
        } else {
            EmptyState(emoji: "📅", title: "Noch kein Wochenplan", text: "Erstelle zuerst einen Plan – dann kannst du Rezepte einsetzen.")
        }
    }

    @ViewBuilder private func recipeChoice(_ entry: MealDTO) -> some View {
        if let cards, !cards.isEmpty {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(cards) { c in
                        Button { Task { await pick(entry, c.id) } } label: {
                            row(c.imageUrl, c.title, c.title, "\(euro(c.costPerServingCents)) / Portion · \(c.prepMinutes) min",
                                busy: busy == c.id, locked: false)
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(busy != nil || c.id == entry.recipe.id)
                    }
                }
                .padding(.bottom, 20)
            }
        } else if cards != nil {
            EmptyState(emoji: "📖", title: "Noch keine Rezepte gespeichert", text: "Merk dir Gerichte mit dem Herz oder lege eigene Rezepte an.")
        } else if let error {
            ErrorState(message: error) { Task { await loadCards() } }
        } else {
            ForEach(0..<4, id: \.self) { _ in SkeletonCard(height: 68) }
        }
    }

    private func order(_ mealType: String) -> Int { Labels.mealTypes.firstIndex { m in m.0 == mealType } ?? 9 }

    private func row(_ image: String, _ seed: String, _ line1: String, _ line2: String, busy: Bool, locked: Bool) -> some View {
        HStack(spacing: 12) {
            Plate(url: mediaURL(image), size: 44, seed: seed)
            VStack(alignment: .leading, spacing: 2) {
                Text(line1).font(Theme.F.callout).foregroundStyle(Theme.C.text1).lineLimit(1)
                Text(line2).font(Theme.F.caption).foregroundStyle(Theme.C.text2).lineLimit(1)
            }
            Spacer()
            if busy {
                ProgressView()
            } else {
                if locked { Image(systemName: "lock.fill").foregroundStyle(Theme.C.text3).accessibilityLabel("fixiert") }
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Theme.C.accentDeep).accessibilityHidden(true)
            }
        }
        .padding(12)
        .frame(minHeight: 44)
        .card(radius: Theme.R.tile)
    }

    private func loadCards() async {
        do {
            cards = try await store.recipes(q: "")
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func pick(_ e: MealDTO, _ recipe: Int) async {
        busy = entry == nil ? e.id : recipe
        defer { busy = nil }
        if await store.replace(e, with: recipe) {
            store.flash("Eingeplant: \(Labels.days[e.day]) · \(Labels.meal(e.mealType))")
            dismiss()
        }
    }
}

// MARK: Nährwerte (2)

/// Tageswerte im Wochenplan: Ringe pro Person (kcal/Protein gegen Ziel) + Werte der gewählten Person.
struct DayNutritionCard: View {
    @Environment(AppStore.self) private var store
    let day: Int
    @Binding var person: Int?

    var body: some View {
        if let n = store.nutrition, let d = n.days.first(where: { $0.day == day }) {
            let sel = person ?? store.profile?.memberId ?? n.members.first?.memberId
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Tageswerte").font(Theme.F.headline)
                    Spacer()
                    PersonPicker(person: $person)
                }
                HStack(spacing: 12) {
                    ForEach(n.members) { m in
                        rings(m, d.members.first { x in x.memberId == m.memberId }, selected: m.memberId == sel)
                    }
                    Spacer(minLength: 0)
                }
                if let m = n.members.first(where: { x in x.memberId == sel }), let v = d.members.first(where: { x in x.memberId == sel }) {
                    HStack(spacing: 4) {
                        NutrientStat(nutrient: .kcal, value: "\(Int(v.kcal.rounded()))")
                        NutrientStat(nutrient: .protein, value: "\(Int(v.protein.rounded())) g")
                        NutrientStat(nutrient: .carbs, value: "\(Int(v.carbs.rounded())) g")
                        NutrientStat(nutrient: .fat, value: "\(Int(v.fat.rounded())) g")
                    }
                    .modifier(Shimmer(active: !v.complete))
                    Text(v.complete ? "Ziel \(m.name): \(m.kcalGoal) kcal · \(m.proteinGoal) g Protein"
                                    : "Nährwerte werden noch berechnet …")
                        .font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                }
            }
            .padding(16)
            .card()
            .animation(Theme.spring, value: d)
            .animation(Theme.spring, value: sel)
        }
    }

    private func rings(_ m: PlanNutritionDTO.Member, _ v: PlanNutritionDTO.MemberDay?, selected: Bool) -> some View {
        Button { withAnimation(Theme.spring) { person = m.memberId } } label: {
            VStack(spacing: 6) {
                ZStack {
                    GoalRing(fraction: (v?.kcal ?? 0) / Double(max(m.kcalGoal, 1)), color: Theme.C.kcal)
                    GoalRing(fraction: (v?.protein ?? 0) / Double(max(m.proteinGoal, 1)), color: Theme.C.protein).padding(10)
                    Text(m.emoji).font(.system(size: 20))
                }
                .frame(width: 70, height: 70)
                .modifier(Shimmer(active: v?.complete == false))
                Text(m.name).font(Theme.F.micro).foregroundStyle(selected ? Theme.C.text1 : Theme.C.text2)
            }
            .padding(6)
            .background(selected ? Theme.C.accentSoft : .clear, in: RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(m.name): \(Int(v?.kcal ?? 0)) von \(m.kcalGoal) kcal, \(Int(v?.protein ?? 0)) von \(m.proteinGoal) Gramm Protein")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Start-Karte „3 Lieblingsrezepte sind diese Woche günstig“ → Rezepte-Tab, Filter „Im Angebot“.
struct FavoriteDealsCard: View {
    @Environment(AppStore.self) private var store
    @State private var deals: [RecipeCard] = []

    var body: some View {
        VStack(spacing: 0) {
            if !deals.isEmpty {
                Button { store.recipeFilter = "im_angebot" } label: {
                    HStack(spacing: 14) {
                        HStack(spacing: -18) {
                            ForEach(deals.prefix(3)) { c in Plate(url: mediaURL(c.imageUrl), size: 48, seed: c.title) }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(deals.count == 1 ? "1 Lieblingsrezept ist diese Woche günstig"
                                                  : "\(deals.count) Lieblingsrezepte sind diese Woche günstig")
                                .font(Theme.F.callout).multilineTextAlignment(.leading)
                            Text(deals.prefix(2).map(\.title).joined(separator: ", ")).font(Theme.F.micro).foregroundStyle(Theme.C.text2).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.C.text3)
                    }
                    .foregroundStyle(Theme.C.text1)
                    .padding(16)
                    .card()
                }
                .buttonStyle(PressableStyle())
                .transition(.opacity)
            }
        }
        .task(id: store.recipesVersion) { deals = (try? await store.recipeDeals()) ?? deals }
    }
}
