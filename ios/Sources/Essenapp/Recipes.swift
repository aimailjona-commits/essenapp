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
            if stars >= 4 {  // Bewertungsabfrage nur nach einem Erfolgsmoment, nie im Onboarding (R12)
                let good = UserDefaults.standard.integer(forKey: "goodCooks") + 1
                UserDefaults.standard.set(good, forKey: "goodCooks")
                askReview = good == 3
            }
            return true
        } catch {
            flash("Bewertung nicht gespeichert: \(error.localizedDescription)")
            return false
        }
    }

    /// „Wieder vorschlagen“ (19.9): Rezept von der Nie-Liste nehmen, Bewertungen bleiben.
    func unhide(_ id: Int) async -> RecipeDTO? {
        do {
            let r: RecipeDTO = try await api.request("POST", "/recipes/\(id)/unhide")
            recipesVersion += 1
            flash("Wird wieder vorgeschlagen")
            return r
        } catch {
            flash("Nicht gespeichert: \(error.localizedDescription)")
            return nil
        }
    }

    /// „Fehler melden“ (19.9): landet in der Übersicht des Entwicklers.
    func report(_ id: Int, kind: String, ingredient: String = "", note: String) async {
        struct Body: Encodable { var kind: String; var ingredient: String; var note: String }
        do {
            if !demo { try await api.send("POST", "/recipes/\(id)/report", body: Body(kind: kind, ingredient: ingredient, note: note)) }
            flash("Danke, ist gemeldet")
        } catch {
            flash("Nicht gemeldet: \(error.localizedDescription)")
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

/// Tab „Rezepte“ (S12, b.html): Kopf mit Anzahl, Suche mit Filtern, „Rezepte im Angebot“, Rezepte als Teller.
struct MyRecipesList: View {
    @Environment(AppStore.self) private var store
    @Binding var filter: String
    var openPlan: (() -> Void)?  // v3-Kachel „Plan dieser Woche“ – in v8 übernimmt der Tab „Woche“ (wird nicht mehr gezeigt)
    @State private var query = ""
    @State private var cards: [RecipeCard]?
    @State private var deals: [RecipeCard] = []
    @State private var error: String?
    @State private var creating = false
    @State private var planning: RecipeCard?
    @State private var importing = false  // „Link einfügen“ (S22)
    @State private var opened: Int?  // importiertes Rezept öffnen
    @Namespace private var zoom  // a2-open: Teller wächst ins Rezept

    // Mockup-Maße (b.html S12), y ab Inhaltsbeginn (Mockup-y − 66)
    private static let blob = (x: 176.0, y: 30.0, size: 290.0)
    private static let book = (x: 190.0, y: 46.0, width: 150.0)
    private static let plate: CGFloat = 110

    static let filters = [("alle", "Alle"), ("favoriten", "Favoriten"), ("eigene", "Eigene"), ("importiert", "Importiert"),
                          ("im_angebot", "Im Angebot"), ("zuletzt", "Zuletzt gekocht"), ("ausgeblendet", "Ausgeblendet")]

    static func matches(_ c: RecipeCard, _ filter: String) -> Bool {
        switch filter {
        case "favoriten": c.favorite
        case "eigene": c.source == "user"
        case "importiert": ["instagram", "web", "shared"].contains(c.source)
        case "im_angebot": c.offerShare >= 0.4
        case "zuletzt": c.lastCooked != nil
        case "ausgeblendet": c.hidden == true  // „Nie“/≤ 2 ★ (19.9, R15)
        default: true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Rezepte").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                Spacer()
                HStack(spacing: 10) {
                    RoundIcon(icon: .link, label: "Rezept aus Link importieren") { importing = true }
                    RoundIcon(icon: .plus, filled: true, label: "Rezept anlegen") { creating = true }
                }
            }
            Text("Meine\nRezepte").font(Theme.F.t1).foregroundStyle(Theme.C.ink).padding(.top, 4)
            StatNumber(label: "Gespeichert", value: cards.map { "\($0.count)" } ?? "–", size: 56)
                .frame(width: 170).padding(.top, 14)
            FieldBox(icon: .search) {
                TextField("", text: $query, prompt: Text("Rezept oder Tag suchen").foregroundStyle(Theme.C.ink2))
                    .submitLabel(.search)
            }
            .padding(.top, 28)
            chips.padding(.top, 8)  // Chip 36 in 44er-Tapfläche → 4 pt oben/unten
            content
        }
        .pinned(left: Self.book.x, top: Self.book.y) { Ill("cookbook").frame(width: Self.book.width) }
        .pinned(left: Self.blob.x, top: Self.blob.y) {
            Circle().fill(Theme.C.blue1).frame(width: Self.blob.size, height: Self.blob.size).accessibilityHidden(true)
        }
        .task(id: "\(query)|\(store.recipesVersion)") {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }  // erst suchen, wenn das Tippen pausiert
            guard !Task.isCancelled else { return }
            await load()
        }
        .sheet(isPresented: $creating) { RecipeFormSheet().presentationDetents([.large]) }
        .sheet(isPresented: $importing, onDismiss: { store.recipesVersion += 1 }) {
            ShareFlowView(input: nil, session: store.shareSession, onOpen: { id in
                importing = false
                opened = id
            }) { importing = false }
            .presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet)
        }
        .navigationDestination(item: $opened) { id in SavedRecipeView(recipeId: id) }
        .sheet(item: $planning) { card in
            PlanSlotSheet(recipeId: card.id, title: card.title).presentationDetents([.medium, .large])
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Self.filters, id: \.0) { key, title in
                    let n = cards.map { all in all.filter { c in Self.matches(c, key) }.count }
                    let count = n.map { " \($0)" } ?? ""
                    Chip8(title: key == "favoriten" ? (n.map(String.init) ?? "") : title + count, on: filter == key,
                          icon: key == "favoriten" ? .heart : nil) { withAnimation(Theme.spring) { filter = key } }
                        .accessibilityLabel(title + count)
                }
            }
            .padding(.trailing, Theme.pagePadding)
        }
        .padding(.trailing, -Theme.pagePadding)  // läuft rechts aus dem Rand (margin-right −24)
    }

    @ViewBuilder private var content: some View {
        if let cards {
            let matching = cards.filter { c in Self.matches(c, filter) && (query.isEmpty || c.title.localizedCaseInsensitiveContains(query)) }
            let shown = filter == "zuletzt" ? matching.sorted { a, b in (a.lastCooked ?? "") > (b.lastCooked ?? "") } : matching
            if !deals.isEmpty && filter == "alle" && query.isEmpty {
                DealsRow(deals: deals) { withAnimation(Theme.spring) { filter = "im_angebot" } }
                    .overlay(alignment: .bottom) { Hairline() }
                    .padding(.top, 24)
            }
            if shown.isEmpty {
                Group {
                    if cards.isEmpty && query.isEmpty {
                        StateNote8(ill: "cookbook", title: "Noch keine Rezepte gespeichert",
                                   text: "Tippe bei einem Gericht aufs Herz oder lege dein eigenes Rezept an.",
                                   button: "Rezept anlegen") { creating = true }
                    } else {
                        StateNote8(ill: "binoculars", title: "Nichts gefunden", text: "Für diese Auswahl gibt es noch keine Rezepte.")
                    }
                }
                .padding(.top, 24)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 22, alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                          alignment: .leading, spacing: 22) {
                    ForEach(shown) { card in cell(card) }
                }
                .padding(.top, 24)
            }
        } else if let error {
            StateNote8.error(error) { Task { await load() } }.padding(.top, 24)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 22, alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                      alignment: .leading, spacing: 22) {
                ForEach(0..<4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 10) {
                        Skeleton8(width: Self.plate, height: Self.plate).clipShape(Circle()).padding(.leading, 6)
                        Skeleton8(width: 120, height: 14)
                        Skeleton8(width: 70, height: 12)
                    }
                }
            }
            .padding(.top, 52)
        }
    }

    /// Ein Rezept: Teller 110 mit Herz oben rechts und Badge unten links, darunter Name und Preis · Sterne.
    private func cell(_ card: RecipeCard) -> some View {
        NavigationLink {
            SavedRecipeView(recipeId: card.id).zoomDestination(card.id, zoom)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                PlatePhoto(url: mediaURL(card.imageUrl), size: Self.plate)
                    .zoomSource(card.id, zoom)
                    .overlay(alignment: .bottomLeading) { badge(card).offset(x: -6, y: 4) }
                    .padding(.leading, 6)
                Text(card.title).font(Theme.F.serif(16, relativeTo: .headline)).foregroundStyle(Theme.C.ink)
                    .multilineTextAlignment(.leading).lineLimit(2).padding(.top, 14)
                HStack(spacing: 6) {
                    Text(euro(card.costPerServingCents)).font(Theme.F.text(15, .bold)).foregroundStyle(Theme.C.ink).fixedSize()
                    Text("·")
                    if let stars = card.avgStars {
                        HStack(spacing: 3) {
                            FilledIcon(icon: .star, size: 13)
                            Text(num(stars))
                        }
                        .accessibilityElement(children: .ignore).accessibilityLabel("\(num(stars)) Sterne")
                    } else {
                        Text("nicht bewertet").lineLimit(1)
                    }
                }
                .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        // Herz außerhalb des Links, damit der Tipp nicht das Rezept öffnet (Mockup: right −10, top −4 am Teller)
        .overlay(alignment: .topLeading) {
            PlateHeart(on: card.favorite) { toggle(card) }
                .offset(x: 6 + Self.plate + 10 - 34 - 5, y: -4 - 5)  // 34er-Kreis in 44er-Tapfläche
        }
        .contextMenu { Button("Diese Woche einplanen", systemImage: "calendar.badge.plus") { planning = card } }
    }

    @ViewBuilder private func badge(_ card: RecipeCard) -> some View {
        if card.offerShare >= 0.4 {
            DealPill(text: "im Angebot")
        } else if let source = ["instagram": "Instagram", "web": "Web", "shared": "Geteilt"][card.source] {
            SoftPill(text: source)
        }
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
        cards?[i].favorite.toggle()
        Task {
            let new = await store.toggleFavorite(card.id, current: card.favorite)
            if let j = cards?.firstIndex(where: { c in c.id == card.id }) { cards?[j].favorite = new }
        }
    }
}

/// Zeile „3 Rezepte im Angebot ›“ mit drei kleinen Tellern (S12; auch Start-Karte).
struct DealsRow: View {
    let deals: [RecipeCard]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                HStack(spacing: -10) {
                    ForEach(deals.prefix(3)) { c in
                        PlatePhoto(url: mediaURL(c.imageUrl), size: 34, ring: 3, ringColor: Theme.C.bg, shadow: false)
                    }
                }
                Text(deals.count == 1 ? "1 Rezept im Angebot" : "\(deals.count) Rezepte im Angebot")
                    .font(Theme.F.text(16, .extrabold)).foregroundStyle(Theme.C.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Icon(.chev, size: 20).foregroundStyle(Theme.C.ink2)
            }
            .frame(minHeight: Theme.S.row)
            .overlay(alignment: .top) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: Gemeinsame Bausteine der Gruppe B (Rezepte & Kochen)

/// Teller (`.plate`) für Fotos; der Rand liegt außen wie `box-shadow` und nimmt keinen Platz ein.
/// Ohne Foto: Topf-Zeichnung auf `blue1` (keine Emojis).
struct PlatePhoto: View {
    let url: URL?
    var size: CGFloat
    var ring: CGFloat = Theme.S.plateRing
    var ringColor = Theme.C.card
    var shadow = true

    var body: some View {
        RemoteImage(url: url, contentMode: .fill) { Theme.C.blue1.overlay { Ill("pot").padding(size * 0.1) } }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .padding(ring)
            .background(ringColor, in: Circle())
            .modifier(PlateShadowIf(on: shadow))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private struct PlateShadowIf: ViewModifier {
        let on: Bool

        func body(content: Content) -> some View {
            if on { content.plateShadow() } else { content }
        }
    }
}

/// Gefülltes Mockup-Icon (`fill:currentColor`, z. B. Stern, Herz).
struct FilledIcon: View {
    let icon: Icon8
    var size: CGFloat = Theme.S.icon

    var body: some View {
        icon.path(.stroke).fill().frame(width: 24, height: 24).scaleEffect(size / 24).frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Runder Icon-Knopf 44 aus den Mockup-Köpfen: `.circle` (Tinte) oder `card` mit Haarlinie, Icon 20.
struct RoundIcon: View {
    let icon: Icon8
    var filled = false
    var size: CGFloat = 44
    var iconSize: CGFloat = 20
    var fill: Color?
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(icon, size: iconSize)
                .foregroundStyle(filled ? Theme.C.onInk : Theme.C.ink)
                .frame(width: size, height: size)
                .background(fill ?? (filled ? Theme.C.ink : Theme.C.card), in: Circle())
                .overlay { if !filled && fill == nil { Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// `.stat` mit grauem Zusatz hinter der Zahl („3 von 6“, „02/05“, „1980 /2500“).
struct StatPair: View {
    let label: String
    let value: String
    let size: CGFloat
    var rest = ""
    var restSize: CGFloat = 17
    var color = Theme.C.ink

    var body: some View {
        VStack(spacing: 6) {
            Hairline(color: Theme.C.ink)
            HStack(alignment: .top) {
                Text(label).font(Theme.F.text(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.C.ink)
                Spacer(minLength: 8)
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    BigNumber(value, size: size).foregroundStyle(color)
                    if !rest.isEmpty {
                        Text(rest).font(Theme.F.num(restSize)).tracking(Theme.F.numTracking(restSize)).foregroundStyle(Theme.C.ink3)
                            .lineLimit(1)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Leer- oder Fehler-Zustand ohne Mockup: Zeichnung im blauen Kreis, `t2`, Text, `.btn`.
struct StateNote8: View {
    var ill = "pot"
    let title: String
    let text: String
    var button: String?
    var action: (() -> Void)?

    static func error(_ message: String, retry: @escaping () -> Void) -> StateNote8 {
        StateNote8(ill: "pot", title: "Das hat nicht geklappt", text: message, button: "Erneut versuchen", action: retry)
    }

    var body: some View {
        VStack(spacing: 4) {
            Ill(ill).frame(width: 150, height: 150).background(Circle().fill(Theme.C.blue1).frame(width: 130, height: 130))
            Text(title).font(Theme.F.t2).foregroundStyle(Theme.C.ink).multilineTextAlignment(.center).padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
            Text(text).font(Theme.F.small).foregroundStyle(Theme.C.ink2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let button, let action { PrimaryButton(title: button, action: action).padding(.top, 14) }
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }
}

/// Herz auf dem Teller (S12, `a1-fav`): Füllung steigt von unten (0,35 s), Ploppen 1,3× (0,4 s), sechs Funken (0,45 s).
/// Entfernen: Farbe läuft ab (0,25 s), ohne Funken. Bewegung reduzieren: sofort, ohne Ploppen/Funken.
struct PlateHeart: View {
    let on: Bool
    var bare = false  // Kopf-Herz (S3, a1-fav): ohne Kreis, Icon 24, Füllung Rosé
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pops = 0

    var body: some View {
        Button {
            if !on && !reduceMotion { pops += 1 }
            withAnimation(reduceMotion ? nil : on ? .easeIn(duration: 0.25) : .timingCurve(0.3, 1, 0.5, 1, duration: 0.35)) { action() }
        } label: {
            ZStack {
                if !bare {
                    Circle().fill(on ? Theme.C.ink : Theme.C.card)
                        .overlay { if !on { Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
                }
                ZStack {
                    Icon8.heart.path(.stroke).fill(bare ? Theme.C.rose : Theme.C.onInk)
                        .frame(width: 24, height: 24)
                        .mask(alignment: .bottom) { Rectangle().frame(height: on ? 24 : 0) }
                    Icon(.heart).foregroundStyle(on && !bare ? Theme.C.onInk : Theme.C.ink)
                }
                .scaleEffect(bare ? 1 : 16 / 24)
                .keyframeAnimator(initialValue: 1.0, trigger: pops) { v, s in v.scaleEffect(s) } keyframes: { _ in
                    CubicKeyframe(1.3, duration: 0.16)
                    CubicKeyframe(1, duration: 0.24)
                }
            }
            .frame(width: 34, height: 34)
            .overlay {  // Funken (64) als Overlay, sonst bläht der Rahmen den 34er-Kreis auf
                KeyframeAnimator(initialValue: 0.0, trigger: pops) { t in Sparks(t: t) } keyframes: { _ in
                    LinearKeyframe(0.001, duration: 0.01)
                    LinearKeyframe(1, duration: 0.45, timingCurve: .easeOut)
                    LinearKeyframe(0, duration: 0.01)
                }
                .frame(width: 64, height: 64)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(trigger: on) { _, new in new ? .success : .impact(weight: .light) }
        .accessibilityLabel(on ? "Aus Favoriten entfernen" : "Als Favorit merken")
    }

    /// `.a1-spark`: sechs Striche (r 17 → 25) zeichnen sich und verschwinden wieder.
    private struct Sparks: View {
        let t: Double

        var body: some View {
            Path { p in
                for i in 0..<6 {
                    let a = Double(i) * .pi / 3
                    p.move(to: CGPoint(x: 32 + 17 * sin(a), y: 32 - 17 * cos(a)))
                    p.addLine(to: CGPoint(x: 32 + 25 * sin(a), y: 32 - 25 * cos(a)))
                }
            }
            .stroke(Theme.C.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .mask { SparkMask(t: t) }
            .frame(width: 64, height: 64)
            .opacity(t > 0 && t < 1 ? 1 : 0)
            .allowsHitTesting(false)
        }
    }

    /// Ring-Maske: erst wächst der Strich von innen nach außen, dann verschwindet er von innen (stroke-dashoffset 1 → 0 → −1).
    private struct SparkMask: View {
        let t: Double

        var body: some View {
            let inner = 17 + 8 * max(0, 2 * t - 1), outer = 17 + 8 * min(1, 2 * t)
            Circle().stroke(lineWidth: max(0, outer - inner) + 0.01)
                .frame(width: inner + outer, height: inner + outer)
        }
    }
}

extension View {
    /// Hintergrund-Ebene ab Bildschirm-Oberkante (Mockup-Koordinaten inkl. Statusleiste 52): Grund `bg` + Rand-Formen.
    /// Beispiel: `.backdrop8 { Color.clear.edgeForm(.circle, Theme.C.blue, width: 430, height: 430, left: -60, top: -80) }`
    func backdrop8<V: View>(@ViewBuilder _ layer: () -> V) -> some View {
        background { layer().frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.C.bg).ignoresSafeArea() }
    }

    /// a2-open: Teller wächst ins Rezept (ab iOS 18 Zoom-Übergang, sonst normaler Push).
    @ViewBuilder func zoomSource(_ id: some Hashable, _ ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) { matchedTransitionSource(id: id, in: ns) } else { self }
    }

    @ViewBuilder func zoomDestination(_ id: some Hashable, _ ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) { navigationTransition(.zoom(sourceID: id, in: ns)) } else { self }
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
                // Laden ohne Mockup: Kopf wie S3 (Bogen oben links), Platzhalter für Titel, Zahlen und Zutaten
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Spacer()
                            RoundIcon(icon: .back, fill: .clear, label: "Zurück") { dismiss() }
                        }
                        if let error {
                            StateNote8.error(error) { Task { await load() } }.padding(.top, 40)
                        } else {
                            Skeleton8(width: 220, height: 34).padding(.top, 18)
                            Skeleton8(width: 160, height: 34).padding(.top, 8)
                            VStack(spacing: 10) { ForEach(0..<3, id: \.self) { _ in Skeleton8(width: 140, height: 40) } }.padding(.top, 30)
                            VStack(spacing: 12) { ForEach(0..<4, id: \.self) { _ in Skeleton8(height: 48) } }.padding(.top, 34)
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, 14)
                }
                .backdrop8 { Color.clear.edgeForm(.circle, Theme.C.blue, width: 430, height: 430, left: -60, top: -80) }
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

// MARK: S19 Diese Woche einplanen (a.html)

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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(entry == nil ? "Diese Woche einplanen" : "Durch eigenes Rezept ersetzen").font(Theme.F.t2).foregroundStyle(Theme.C.ink)
                Spacer()
                CloseButton { dismiss() }
            }
            Group {
                if let entry {
                    Text("\(Labels.dayNames[entry.day]) · \(Labels.meal(entry.mealType)): „\(entry.recipe.title)“ wird ersetzt.")
                } else {
                    Text("„\(title)“ ersetzt das Gericht im gewählten Slot.")
                }
            }
            .font(Theme.F.text(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2).padding(.top, 4)
            if let entry { recipeChoice(entry).padding(.top, 14) } else { slotChoice.padding(.top, 14) }
        }
        .padding(.horizontal, Theme.pagePadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .sheet8()
        .task { if entry != nil { await loadCards() } }
    }

    @ViewBuilder private var slotChoice: some View {
        if let plan = store.plan, !plan.entries.isEmpty {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(plan.entries.sorted { a, b in (a.day, order(a.mealType)) < (b.day, order(b.mealType)) }, id: \.self) { e in
                        Button { Task { await pick(e, recipeId) } } label: {
                            row(e.recipe.imageUrl, "\(Labels.dayNames[e.day]) · \(Labels.meal(e.mealType))", e.recipe.title,
                                busy: busy == e.id, locked: e.locked)
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(busy != nil)
                    }
                }
                .padding(.bottom, 40)
                .padding(.horizontal, Theme.pagePadding)  // Tellerrand nicht an der ScrollView abschneiden
            }
            .padding(.horizontal, -Theme.pagePadding)
        } else {
            StateNote8(ill: "lying", title: "Noch kein Wochenplan", text: "Erstelle zuerst einen Plan – dann kannst du Rezepte einsetzen.")
                .padding(.top, 20)
        }
    }

    @ViewBuilder private func recipeChoice(_ entry: MealDTO) -> some View {
        if let cards, !cards.isEmpty {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(cards) { c in
                        Button { Task { await pick(entry, c.id) } } label: {
                            row(c.imageUrl, "\(euro(c.costPerServingCents)) p. P. · \(c.prepMinutes) min", c.title, busy: busy == c.id, locked: false)
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(busy != nil || c.id == entry.recipe.id)
                    }
                }
                .padding(.bottom, 40)
                .padding(.horizontal, Theme.pagePadding)  // Tellerrand nicht an der ScrollView abschneiden
            }
            .padding(.horizontal, -Theme.pagePadding)
        } else if cards != nil {
            StateNote8(ill: "cookbook", title: "Noch keine Rezepte gespeichert", text: "Merk dir Gerichte mit dem Herz oder lege eigene Rezepte an.")
                .padding(.top, 20)
        } else if let error {
            StateNote8.error(error) { Task { await loadCards() } }.padding(.top, 20)
        } else {
            VStack(spacing: 12) { ForEach(0..<4, id: \.self) { _ in Skeleton8(height: 52) } }
        }
    }

    private func order(_ mealType: String) -> Int { Labels.slotOrder.firstIndex(of: mealType) ?? 9 }

    /// `.irow` 64: kleiner Teller (a-mini), Label in Großbuchstaben, Name; rechts Tauschen bzw. Schloss.
    private func row(_ image: String, _ label: String, _ name: String, busy: Bool, locked: Bool) -> some View {
        HStack(spacing: 14) {
            PlatePhoto(url: mediaURL(image), size: 44, ring: 3, shadow: false)  // a-mini: ohne großen Schatten (wurde im Scroll-Rand abgeschnitten)
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(label)
                Text(name).font(Theme.F.text(16, .bold)).foregroundStyle(Theme.C.ink).lineLimit(1)
            }
            Spacer(minLength: 8)
            if busy {
                Hop3().frame(width: 60)
            } else if locked {
                Icon(.lock).foregroundStyle(Theme.C.ink3).accessibilityLabel("fixiert")
            } else {
                Icon(.swap).foregroundStyle(Theme.C.ink)
            }
        }
        .frame(minHeight: 64)
        .overlay(alignment: .top) { Hairline() }
        .contentShape(Rectangle())
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

// MARK: Nährwerte (2) – S2 Tageswerte (a.html)

/// Tageswerte im Wochenplan: Ringe pro Person (kcal Tinte, Protein blau), zwei große Zahlen gegen das Ziel, KH und Fett klein.
struct DayNutritionCard: View {
    @Environment(AppStore.self) private var store
    let day: Int
    @Binding var person: Int?

    var body: some View {
        if let n = store.nutrition, let d = n.days.first(where: { $0.day == day }) {
            let sel = person ?? store.profile?.memberId ?? n.members.first?.memberId
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SectionLabel("Tageswerte")
                    Spacer()
                    if let m = n.members.first(where: { x in x.memberId == sel }) {
                        Menu {
                            ForEach(n.members) { p in Button(p.name) { withAnimation(Theme.spring) { person = p.memberId } } }
                        } label: {
                            Text("Für: \(m.name) ▾").font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink)
                                .frame(minHeight: 44)
                        }
                        .accessibilityLabel("Für \(m.name), ändern")
                    }
                }
                HStack(alignment: .top, spacing: 22) {
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(n.members) { m in
                            ring(m, d.members.first { x in x.memberId == m.memberId }, selected: m.memberId == sel)
                        }
                    }
                    .fixedSize()
                    if let m = n.members.first(where: { x in x.memberId == sel }), let v = d.members.first(where: { x in x.memberId == sel }) {
                        VStack(spacing: 12) {
                            StatPair(label: "kcal", value: "\(Int(v.kcal.rounded()))", size: 30, rest: " /\(m.kcalGoal)")
                            StatPair(label: "Protein", value: "\(Int(v.protein.rounded()))", size: 30, rest: " /\(m.proteinGoal) g")
                        }
                        .opacity(v.complete ? 1 : 0.5)
                    }
                }
                .padding(.top, 4)  // 14 − Tapfläche der „Für“-Zeile
                if let v = d.members.first(where: { x in x.memberId == sel }) {
                    Text(v.complete ? "KH \(Int(v.carbs.rounded())) g · Fett \(Int(v.fat.rounded())) g" : "Nährwerte werden noch berechnet …")
                        .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2).padding(.top, 12)
                }
            }
            .animation(Theme.spring, value: d)
            .animation(Theme.spring, value: sel)
            .sensoryFeedback(.selection, trigger: person)
        }
    }

    /// Ring wie im Mockup (viewBox 88): gewählt 76 auf `blue1`, sonst 50; außen kcal (Tinte), innen Protein (blue3).
    private func ring(_ m: PlanNutritionDTO.Member, _ v: PlanNutritionDTO.MemberDay?, selected: Bool) -> some View {
        let size: CGFloat = selected ? 76 : 50, k = size / 88, width = (selected ? 7 : 8) * k
        return Button { withAnimation(Theme.spring) { person = m.memberId } } label: {
            VStack(spacing: 4) {
                ZStack {
                    if selected { Circle().fill(Theme.C.blue1) }
                    arc((v?.kcal ?? 0) / Double(max(m.kcalGoal, 1)), Theme.C.ink, width).frame(width: 72 * k, height: 72 * k)
                    arc((v?.protein ?? 0) / Double(max(m.proteinGoal, 1)), Theme.C.blue3, width)
                        .frame(width: (selected ? 52 : 50) * k, height: (selected ? 52 : 50) * k)
                    Text(String(m.name.prefix(1))).font(Theme.F.serif((selected ? 20 : 26) * k, relativeTo: .body)).foregroundStyle(Theme.C.ink)
                }
                .frame(width: size, height: size)
                Text(m.name).font(Theme.F.text(12, .extrabold, relativeTo: .caption)).foregroundStyle(selected ? Theme.C.ink : Theme.C.ink2)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(m.name): \(Int(v?.kcal ?? 0)) von \(m.kcalGoal) kcal, \(Int(v?.protein ?? 0)) von \(m.proteinGoal) Gramm Protein")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func arc(_ fraction: Double, _ color: Color, _ width: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Theme.C.line, lineWidth: width)
            Circle().trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Start: „3 Rezepte im Angebot ›“ → Rezepte-Tab, Filter „Im Angebot“ (gleiche Zeile wie in S12).
struct FavoriteDealsCard: View {
    @Environment(AppStore.self) private var store
    @State private var deals: [RecipeCard] = []

    var body: some View {
        VStack(spacing: 0) {
            if !deals.isEmpty {
                DealsRow(deals: deals) { store.recipeFilter = "im_angebot" }.transition(.opacity)
            }
        }
        .task(id: store.recipesVersion) { deals = (try? await store.recipeDeals()) ?? deals }
    }
}
