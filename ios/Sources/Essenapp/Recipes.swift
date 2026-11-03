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
    var openPlan: (() -> Void)?  // v3: Kachel „Plan dieser Woche“ → S2
    @State private var query = ""
    @State private var cards: [RecipeCard]?
    @State private var deals: [RecipeCard] = []
    @State private var error: String?
    @State private var creating = false
    @State private var planning: RecipeCard?
    @State private var importing = false  // „Link einfügen“ (S22)
    @State private var opened: Int?  // importiertes Rezept öffnen

    static let filters = [("alle", "Alle"), ("favoriten", "Favoriten"), ("im_angebot", "Im Angebot"), ("eigene", "Eigene"),
                          ("importiert", "Importiert"), ("zuletzt", "Zuletzt gekocht")]

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
            HStack(alignment: .top) {
                DisplayHeader(line1: "Rezepte")
                HStack(spacing: 8) {
                    if let cards { Text("\(cards.count)").font(.system(.subheadline, weight: .semibold)).foregroundStyle(Theme.C.text1) }
                    Menu {
                        Button("Rezept anlegen", systemImage: "square.and.pencil") { creating = true }
                        Button("Aus Link importieren", systemImage: "link") { importing = true }
                    } label: {
                        Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.C.text1)
                            .frame(width: Theme.S.roundButton, height: Theme.S.roundButton).background(Theme.C.surface, in: Circle())
                    }
                    .accessibilityLabel("Rezept anlegen oder importieren")
                }
                .padding(.top, 4)
            }
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
                let matching = cards.filter { c in Self.matches(c, filter) && (query.isEmpty || c.title.localizedCaseInsensitiveContains(query)) }
                let shown = filter == "zuletzt" ? matching.sorted { a, b in (a.lastCooked ?? "") > (b.lastCooked ?? "") } : matching
                let wall = filter == "alle" && query.isEmpty
                if shown.isEmpty && !wall {
                    if cards.isEmpty && query.isEmpty {
                        EmptyState(emoji: "📖", title: "Noch keine Rezepte gespeichert",
                                   text: "Tippe bei einem Gericht aufs Herz oder lege dein eigenes Rezept an.",
                                   buttonTitle: "Rezept anlegen") { creating = true }
                    } else {
                        EmptyState(emoji: "🔍", title: "Nichts gefunden", text: "Für diese Auswahl gibt es noch keine Rezepte.")
                    }
                } else {
                    tileWall(shown, intro: wall ? introTiles(cards) : [])
                }
            } else if let error {
                ErrorState(message: error) { Task { await load() } }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 10) { SkeletonCard(height: 236); SkeletonCard(height: 150) }
                    VStack(spacing: 10) { SkeletonCard(height: 186); SkeletonCard(height: 200) }
                }
            }
            // Noch nicht gemockt (redesign-v3.md 7, Gruppe B): Suche unter der Wand
            SearchField(text: $query, placeholder: "Rezept oder Tag suchen")
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

    // MARK: Kachel-Wand (S12, wie GoodNotes „My Notes“)

    private enum Tile: Identifiable {
        case plan, imported(Int), deals, recipe(RecipeCard, CGFloat, Int)
        var id: String {
            switch self {
            case .plan: "plan"
            case .imported: "imported"
            case .deals: "deals"
            case .recipe(let c, _, _): "r\(c.id)"
            }
        }
    }

    /// Feste Kacheln oben: links Plan + Instagram-Sammlung, rechts (nach dem ersten Foto) Lieblingsrezepte günstig.
    private func introTiles(_ cards: [RecipeCard]) -> [Tile] {
        var tiles: [Tile] = []
        if store.plan != nil, openPlan != nil { tiles.append(.plan) }
        let imported = cards.filter { c in Self.matches(c, "importiert") }.count
        if imported > 0 { tiles.append(.imported(imported)) }
        if !deals.isEmpty { tiles.append(.deals) }
        return tiles
    }

    private func tileWall(_ shown: [RecipeCard], intro: [Tile]) -> some View {
        // Reihenfolge wie im Mockup: links Plan, Sammlung …; rechts Foto, günstig, …
        var left: [Tile] = intro.filter { if case .deals = $0 { false } else { true } }
        var right: [Tile] = []
        let recipes = shown.enumerated().map { i, c in Tile.recipe(c, [186, 220, 170, 200][i % 4], i) }
        var rest = recipes[...]
        if let first = rest.popFirst() { right.append(first) }
        if intro.contains(where: { if case .deals = $0 { true } else { false } }) { right.append(.deals) }
        var leftHeight = left.reduce(CGFloat(0)) { s, t in s + height(t) }, rightHeight = right.reduce(CGFloat(0)) { s, t in s + height(t) }
        for t in rest {
            if leftHeight <= rightHeight { left.append(t); leftHeight += height(t) } else { right.append(t); rightHeight += height(t) }
        }
        return HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 10) { ForEach(left) { tile($0) } }
            VStack(spacing: 10) { ForEach(right) { tile($0) } }
        }
    }

    private func height(_ t: Tile) -> CGFloat {
        switch t {
        case .plan: 236
        case .imported: 150
        case .deals: 200
        case .recipe(_, let h, _): h
        }
    }

    @ViewBuilder private func tile(_ t: Tile) -> some View {
        switch t {
        case .plan:
            Button { openPlan?() } label: { planTile }.buttonStyle(PressableStyle())
        case .imported(let n):
            Button { withAnimation(Theme.spring) { filter = "importiert" } } label: {
                RTile(color: Theme.C.lav, height: 150) {
                    Text("Aus Instagram").font(Theme.F.cardTitle(17)).fixedSize(horizontal: false, vertical: true)
                    Text(n == 1 ? "1 Rezept" : "\(n) Rezepte").font(.footnote.weight(.medium)).foregroundStyle(Color(hex: 0x3D3566)).padding(.top, 4)
                    Spacer(minLength: 0)
                    Text("📲").font(.system(size: 58)).rotationEffect(.degrees(10))
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(.bottom, -10).padding(.trailing, -6)
                }
            }
            .buttonStyle(PressableStyle())
        case .deals:
            Button { withAnimation(Theme.spring) { filter = "im_angebot" } } label: {
                RTile(color: Theme.C.lime, height: 200) {
                    Text(deals.count == 1 ? "1 Lieblingsrezept günstig" : "\(deals.count) Lieblings\u{AD}rezepte günstig").font(Theme.F.cardTitle(17))
                    HStack(spacing: -16) {
                        ForEach(deals.prefix(3)) { c in Plate(url: mediaURL(c.imageUrl), size: 48, seed: c.title) }
                    }
                    .padding(.top, 14)
                    Spacer(minLength: 0)
                    DealBadge(text: "im Angebot")  // Rabatt je Rezept liefert die API nicht
                }
            }
            .buttonStyle(PressableStyle())
        case .recipe(let card, let h, let i):
            NavigationLink { SavedRecipeView(recipeId: card.id) } label: { RecipePhotoTile(card: card, height: h, color: Theme.C.day[i % 7]) { toggle(card) } }
                .buttonStyle(PressableStyle())
                .contextMenu { Button("Diese Woche einplanen", systemImage: "calendar.badge.plus") { planning = card } }
        }
    }

    /// „Plan dieser Woche“ (Tomate): Mini-Checkliste der Gerichte, erledigt = schon vorbei.
    private var planTile: some View {
        let entries = (store.plan?.entries ?? []).sorted { a, b in
            (a.day, Labels.slotOrder.firstIndex(of: a.mealType) ?? 9) < (b.day, Labels.slotOrder.firstIndex(of: b.mealType) ?? 9)
        }
        let mains = entries.filter { ["mittag", "abend"].contains($0.mealType) }
        return RTile(color: Theme.C.tomato, height: 236) {
            Text("Plan\ndieser Woche").font(Theme.F.cardTitle(17)).multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(mains.prefix(3).enumerated()), id: \.offset) { _, m in miniRow(m.recipe.title, done: m.day < store.today) }
                if mains.count > 3 { miniRow("+ \(mains.count - 3) weitere", done: false) }
            }
            .padding(.top, 14)
        } corner: {
            Image(systemName: "heart").font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36).background(Color.black.opacity(0.08), in: Circle())
        }
    }

    private func miniRow(_ text: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: 1.6).background(Circle().fill(done ? Theme.C.ink : .clear))
                .frame(width: 18, height: 18)
            Text(text).font(.system(.footnote, weight: .semibold)).strikethrough(done).lineLimit(1)
        }
        .padding(.horizontal, 10).frame(height: 36).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.08), in: Capsule())
        .opacity(done ? 0.55 : 1)
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

/// Rezept-Kachel (v3 `rtile`): farbige Fläche mit Titel oben, Inhalt, optional Element oben rechts.
struct RTile<Content: View, Corner: View>: View {
    let color: Color
    let height: CGFloat
    @ViewBuilder let content: () -> Content
    @ViewBuilder var corner: () -> Corner

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .foregroundStyle(Theme.C.ink)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)  // nicht auf Spaltenhöhe strecken
            .overlay(alignment: .topTrailing) { corner().padding(12) }
            .background(color, in: RoundedRectangle(cornerRadius: Theme.R.rtile, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.R.rtile, style: .continuous))
    }
}

extension RTile where Corner == EmptyView {
    init(color: Color, height: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.init(color: color, height: height, content: content, corner: { EmptyView() })
    }
}

/// Foto-Kachel: Bild randlos, Verlauf unten, Titel weiß, Herz oben rechts. Ohne Foto: Teller auf Pastell.
struct RecipePhotoTile: View {
    let card: RecipeCard
    let height: CGFloat
    var color = Theme.C.sun
    let toggle: () -> Void

    var body: some View {
        let url = mediaURL(card.imageUrl)
        ZStack(alignment: .bottomLeading) {
            if url != nil {
                RemoteImage(url: url, contentMode: .fill) { color }
                    .frame(maxWidth: .infinity, minHeight: height, maxHeight: height).clipped()
                LinearGradient(stops: [.init(color: .clear, location: 0.4), .init(color: .black.opacity(0.55), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                color
                Plate(url: nil, size: 72, seed: card.title).frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title).font(Theme.F.cardTitle(17)).lineLimit(2).multilineTextAlignment(.leading)
                Text("\(card.prepMinutes) min · \(euro(card.costPerServingCents))").font(.caption)
                    .opacity(0.85)
            }
            .foregroundStyle(url != nil ? .white : Theme.C.ink)
            .padding(16)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.R.rtile, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: toggle) {
                Image(systemName: card.favorite ? "heart.fill" : "heart").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(url != nil ? .white : Theme.C.ink)
                    .frame(width: 36, height: 36)
                    .background(url != nil ? Color.white.opacity(0.3) : Color.black.opacity(0.08), in: Circle())
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(PressableStyle())
            .padding(6)
            .accessibilityLabel(card.favorite ? "Aus Favoriten entfernen" : "Als Favorit merken")
        }
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

    private func order(_ mealType: String) -> Int { Labels.slotOrder.firstIndex(of: mealType) ?? 9 }

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
