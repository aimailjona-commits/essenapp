import SwiftUI

// Phase 12 – Sparen: Vorschau nächste Woche (30), Vorratskauf (31), Laden-Empfehlung (42), Budget-Rest (43),
// Bio/Vegan/Nutri-Score (49). Merkliste (27/40/58) steht in Watch.swift.

// MARK: Modelle (= backend/app/schemas.py)

/// = NextWeekDealOut: „Hähnchenbrust nächste Woche −30 % bei Lidl (3,49 € statt 4,99 €) – Kauf verschieben?“
struct NextWeekDealDTO: Codable, Hashable {
    var name: String
    var itemId: Int?  // Listenartikel → POST /items/{id}/next-week; nil = aus der Merkliste
    var watchId: Int?
    var offer: OfferDTO  // Angebot der nächsten Woche
    var nowPriceCents: Int
    var nowChain: String  // "" = Normalpreis ohne Laden
    var savingPct: Int
}

/// = StockupOut: „3 Packungen reichen ~6 Wochen, sparst 4,20 €“.
struct StockupDTO: Codable, Hashable {
    var offer: OfferDTO
    var packs: Int
    var weeks: Double?  // nil = ohne Verbrauchsdaten (konservativ)
    var weeklyUse: Double?
    var savingCents: Int
    var normalPriceCents: Int

    var text: String { "\(headline), sparst \(euro(savingCents))" }

    /// „3 Packungen reichen ~6 Wochen“ (Vorratstipp-Titel, S9); ohne Verbrauchsdaten vorsichtig.
    var headline: String {
        let packs = packs == 1 ? "1 Packung" : "\(self.packs) Packungen"
        guard let weeks else { return "\(packs) (vorsichtig geschätzt, noch ohne Verbrauchsdaten)" }
        return "\(packs) \(self.packs == 1 ? "reicht" : "reichen") ~\(num(weeks, 0...0)) Wochen"
    }

    /// „sparst 2,40 € zum Normalpreis“.
    var sub: String { "sparst \(euro(savingCents)) zum Normalpreis" }
}

/// = StoreComboOut (42).
struct StoreComboDTO: Codable, Hashable {
    var chains: [String]
    var totalCents: Int
    var perStore: [String: Int]
    var savedCents: Int
    var unpriced: Int
    var distanceKm: Double?
    var extraKm: Double?

    var name: String { chains.count == 1 ? "alles bei \(Labels.chain(chains[0]))" : chains.map(Labels.chain).joined(separator: " + ") }
}

/// = BudgetOut (43).
struct BudgetDTO: Codable, Hashable {
    struct Over: Codable, Hashable {
        var entryId: Int
        var day: Int
        var title: String
        var costCents: Int
        var maxCostCents: Int
    }
    var budgetCents: Int
    var totalCents: Int
    var restCents: Int
    var state: String  // rest | over | ok
    var over: Over?
}

/// = BudgetIdeaOut: Dessert/Snack (einplanen) oder Vorratskauf (auf die Liste).
struct BudgetIdeaDTO: Codable, Hashable {
    var kind: String  // dessert | snack | vorrat
    var title: String
    var costCents: Int
    var recipe: RecipeDTO?
    var stockup: StockupDTO?
}

extension OfferDTO {
    /// Gültig erst ab einem späteren Tag (Vorschau nächste Woche, 30).
    var startsLater: Bool { validFrom > Date.now.formatted(PantryDTO.day) }
    var hasLabels: Bool { bio == true || vegan == true || nutriScore != nil }
}

// MARK: Server

extension AppStore {
    func nextWeekDeals() async throws -> [NextWeekDealDTO] {
        demo ? Demo.nextWeekDeals : try await api.request("GET", "/offers/next-week-cheaper", timeout: 30)
    }

    /// „Auf nächste Woche schieben“: Listenartikel in die Gruppe „Nächste Woche“ (offline: Warteschlange),
    /// Merklisten-Treffer kommen gleich dort auf die Liste.
    func deferToNextWeek(_ d: NextWeekDealDTO) async -> Bool {
        guard !demo, let list = householdList else { return true }
        if let id = d.itemId {
            struct Body: Encodable { var offerId: Int }
            do {
                let _: ListItemDTO = try await api.request("POST", "/items/\(id)/next-week", body: Body(offerId: d.offer.id))
            } catch APIError.queued {
                editList(list.id) { l in
                    if let i = l.items.firstIndex(where: { x in x.id == id }) { l.items[i].nextWeek = true }
                }
                return true
            } catch {
                flash("Nicht verschoben: \(error.localizedDescription)")
                return false
            }
        } else {
            await addItem(name: d.name, chain: d.offer.chain, offerId: d.offer.id, nextWeek: true, to: list.id)
        }
        await loadLists()
        return true
    }

    /// „Doch diese Woche“ (Gruppe „Nächste Woche“ verlassen).
    func undoNextWeek(_ item: ListItemDTO) async {
        if let i = householdList?.items.firstIndex(where: { x in x.id == item.id }) { householdList?.items[i].nextWeek = false }
        guard !demo, item.id > 0 || API.isTemp(item.id) else { return }
        struct Body: Encodable { var nextWeek: Bool }
        _ = try? await api.send("PATCH", "/items/\(item.id)", body: Body(nextWeek: false))
    }

    func stockups(limit: Int = 3) async throws -> [StockupDTO] {
        demo ? Demo.stockups : try await api.request("GET", "/stockup?limit=\(limit)", timeout: 30)
    }

    func stockup(for offer: OfferDTO) async -> StockupDTO? {
        if demo { return Demo.stockups.first { t in t.offer.id == offer.id } }
        return try? await api.request("GET", "/offers/\(offer.id)/stockup") as StockupDTO?
    }

    /// „3× auf die Liste“ mit Badge „Vorratskauf“ (offline: Warteschlange).
    func addStockup(_ t: StockupDTO, packs: Int? = nil) async {
        guard let list = householdList else { return }
        let n = packs ?? t.packs
        flash("\(n)× „\(t.offer.title)“ auf der Liste")
        await addItem(name: t.offer.title, amount: Double(n), unit: "stk", chain: t.offer.chain, offerId: t.offer.id,
                      source: "stockup", to: list.id)
    }

    func storeCombos(_ listId: Int) async throws -> [StoreComboDTO] {
        demo ? Demo.storeCombos : try await api.request("GET", "/lists/\(listId)/stores", timeout: 30)
    }

    /// „So aufteilen“: jeder offene Artikel in den günstigsten der Läden.
    func assignStores(_ listId: Int, _ chains: [String]) async -> Bool {
        struct Body: Encodable { var chains: [String] }
        do {
            if !demo { householdList = try await api.request("POST", "/lists/\(listId)/assign", body: Body(chains: chains), timeout: 30) }
            flash("Liste neu aufgeteilt")
            return true
        } catch {
            flash("Nicht aufgeteilt: \(error.localizedDescription)")
            return false
        }
    }

    func planBudget() async throws -> BudgetDTO {
        if demo { return Demo.screen == "budgetover" ? Demo.budgetOver : Demo.budget }
        return try await api.request("GET", "/plans/current/budget")
    }

    /// 3 Ideen für den Rest (KI, bis ~16 s) – je Plan-Stand nur einmal.
    func ideasForBudget() async throws -> [BudgetIdeaDTO] {
        let key = "\(plan?.id ?? 0)-\(plan?.totalCents ?? 0)"
        if let cached = budgetIdeas, cached.key == key { return cached.ideas }
        let ideas: [BudgetIdeaDTO] = demo ? Demo.budgetIdeas : try await api.request("POST", "/plans/current/budget/ideas", timeout: 90)
        budgetIdeas = (key, ideas)
        return ideas
    }

    /// Rezept zusätzlich einplanen (Dessert/Snack aus den Budget-Ideen).
    func addEntry(recipeId: Int, day: Int, mealType: String) async -> Bool {
        struct Body: Encodable { var recipeId: Int; var day: Int; var mealType: String }
        guard !demo else { return true }
        do {
            plan = try await api.request("POST", "/plans/current/entries", body: Body(recipeId: recipeId, day: day, mealType: mealType), timeout: 60)
            await loadLists()
            await loadNutrition()
            return true
        } catch APIError.http(422) {
            flash("Bei dieser Mahlzeit isst niemand mit")
        } catch {
            flash("Nicht eingeplant: \(error.localizedDescription)")
        }
        return false
    }
}

// MARK: 49 Bio, Vegan, Nutri-Score

/// Siegel als weiche Pillen (`.soft`): „Nutri A“ in Ampelfarbe, „Vegan“ mit Blatt (`.ok`), „Bio“.
struct LabelBadges: View {
    let offer: OfferDTO

    var body: some View {
        if offer.hasLabels {
            HStack(spacing: 5) {
                if let n = offer.nutriScore { NutriBadge(score: n) }
                if offer.vegan == true { SoftPill(text: "Vegan", icon: .leaf, tint: Theme.C.sage) }
                if offer.bio == true { SoftPill(text: "Bio", tint: Theme.C.sage) }
            }
        }
    }
}

/// „Nutri A“ als `.soft`-Pille in der Originalfarbe (`.c-nA`), Schrift weiß, auf C dunkel.
struct NutriBadge: View {
    let score: String

    var body: some View {
        Text("Nutri \(score)").font(Theme.F.soft)
            .foregroundStyle(score == "C" ? Theme.C.onBright : Theme.C.onInk)
            .padding(.horizontal, 10).frame(height: Theme.S.softPill)
            .background(Theme.C.nutri[score] ?? Theme.C.ink3, in: Capsule())
            .accessibilityLabel("Nutri-Score \(score)")
    }
}

/// Angebotsdetail „Bio, vegan, Nutri-Score“ (S9): Siegel mit Erklärung als Zeilen, Quelle als Zeile mit Pfeil.
struct LabelsInfoCard: View {
    let offer: OfferDTO
    @Environment(\.openURL) private var openURL

    var body: some View {
        let sources = (offer.labelSources ?? []).isEmpty ? "Prospekt" : (offer.labelSources ?? []).joined(separator: " · ")
        let off = offer.offCode.flatMap { c in c.isEmpty ? nil : URL(string: "https://world.openfoodfacts.org/product/\(c)") }
        VStack(alignment: .leading, spacing: 0) {
            Text("Bio, vegan, Nutri-Score").font(Theme.F.t2).padding(.bottom, 8)
            if let n = offer.nutriScore { line(NutriBadge(score: n), "Nährwert-Ampel von A (günstig) bis E") }
            if offer.vegan == true { line(SoftPill(text: "Vegan", icon: .leaf, tint: Theme.C.sage), "ohne tierische Zutaten") }
            if offer.bio == true { line(SoftPill(text: "Bio", tint: Theme.C.sage), "laut Bio-Siegel bzw. „Bio“ im Prospekt") }
            Button { if let off { openURL(off) } } label: {
                HStack(spacing: 14) {
                    Text("Quelle: \(sources)\(off == nil ? "" : " · Open Food Facts (ODbL)")")
                        .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                        .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    if off != nil { Icon(.chev, size: 18).foregroundStyle(Theme.C.ink3) }
                }
                .padding(.vertical, 11).frame(minHeight: 44)
                .overlay(alignment: .top) { Hairline() }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(off == nil)
            .accessibilityHint(off == nil ? "" : "Bei Open Food Facts ansehen")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ pill: some View, _ text: String) -> some View {
        HStack(spacing: 14) {
            pill.frame(width: 72)
            Text(text).font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { Hairline() }
        .accessibilityElement(children: .combine)
    }
}

// MARK: 31 Vorratskauf

/// Angebotsdetail „Vorratstipp“ (S9) neben der Tasche im Salbei-Kreis; „3× auf die Liste“ (nur bei Tipp).
/// Volle Breite: Kreis läuft rechts aus dem Rand (Mockup: Kreis 300 bei x 240 / y 520, Tipp bei x 24 / y 524).
struct StockupTipCard: View {
    @Environment(AppStore.self) private var store
    let offer: OfferDTO
    @State private var tip: StockupDTO?
    @State private var added = false

    private enum L {
        static let text: CGFloat = 220
        static let blob: CGFloat = 300, blobLeft: CGFloat = 240 - 24, blobTop: CGFloat = 520 - 524
        static let ill: CGFloat = 124, illLeft: CGFloat = 258 - 24, illTop: CGFloat = 530 - 524
    }

    var body: some View {
        VStack(spacing: 0) {
            if let tip {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Icon(.sparkle, size: 15)
                        Text("VORRATSTIPP").font(Theme.F.lbl).tracking(11 * 0.08)
                    }
                    .foregroundStyle(Theme.C.ink)
                    Text(tip.headline).font(Theme.F.t2).padding(.top, 6).fixedSize(horizontal: false, vertical: true)
                    Text(tip.sub).font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2).padding(.top, 4)
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
                .frame(width: L.text, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .pinned(left: L.illLeft, top: L.illTop) { Ill("bag").frame(width: L.ill, height: L.ill) }
                .edgeForm(.circle, Theme.C.sage, width: L.blob, height: L.blob, left: L.blobLeft, top: L.blobTop)
                .transition(.opacity)
            }
        }
        .animation(Theme.spring, value: tip)
        .task(id: offer.id) { tip = await store.stockup(for: offer) }
    }
}

/// Spar-Tipp „Vorrat anlegen lohnt sich“ (max. 3) als Zeilen; „3× auf die Liste“ legt auf die Liste.
struct StockupCard: View {
    @Environment(AppStore.self) private var store
    @State private var tips: [StockupDTO] = []
    @State private var added: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !tips.isEmpty {
                SecHead("Vorrat anlegen lohnt sich").padding(.bottom, 6)
                ForEach(Array(tips.prefix(3).enumerated()), id: \.element.offer.id) { i, t in row(t).appear(delay: Double(i) * 0.05) }
            }
        }
        .task { tips = (try? await store.stockups()) ?? tips }
    }

    private func row(_ t: StockupDTO) -> some View {
        let done = added.contains(t.offer.id)
        return HStack(spacing: 14) {
            NavigationLink { OfferDetailView(offer: t.offer) } label: {
                HStack(spacing: 14) {
                    RemoteImage(url: URL(string: t.offer.imageUrl)) { Icon(.tag) }
                        .frame(width: Theme.S.rowImage, height: Theme.S.rowImage)
                        .frame(width: Theme.S.rowCircle, height: Theme.S.rowCircle)
                        .background(Theme.hue(category: t.offer.category).tint, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.offer.title).font(Theme.F.serif(17, relativeTo: .body)).lineLimit(1)
                        Text(t.text).font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.C.ink)
            }
            .buttonStyle(PressableStyle())
            Button {
                withAnimation(Theme.spring) { _ = added.insert(t.offer.id) }
                Task { await store.addStockup(t) }
            } label: {
                Text(done ? "auf der Liste" : "\(t.packs)× auf die Liste").font(Theme.F.text(13, .extrabold, relativeTo: .footnote))
                    .foregroundStyle(done ? Theme.C.ink3 : Theme.C.blue3).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .disabled(done)
            .sensoryFeedback(.success, trigger: done)
            .accessibilityLabel(done ? "Auf der Liste" : "\(t.packs)× \(t.offer.title) auf die Liste")
        }
        .frame(minHeight: 52)
        .overlay(alignment: .top) { Hairline() }
    }
}

// MARK: 30 Nächste Woche günstiger

/// Spar-Tipp „Nächste Woche günstiger“ als Zeilen: Kauf verschieben.
struct NextWeekCard: View {
    @Environment(AppStore.self) private var store
    @State private var deals: [NextWeekDealDTO] = []
    @State private var busy: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !deals.isEmpty {
                SecHead("Nächste Woche günstiger").padding(.bottom, 6)
                ForEach(Array(deals.prefix(3).enumerated()), id: \.element.name) { i, d in row(d).appear(delay: Double(i) * 0.05) }
            }
        }
        .animation(Theme.spring, value: deals)
        .sensoryFeedback(.success, trigger: deals.count)
        .task(id: store.householdList?.items.count) { deals = (try? await store.nextWeekDeals()) ?? deals }
    }

    private func row(_ d: NextWeekDealDTO) -> some View {
        let now = d.nowChain.isEmpty ? euro(d.nowPriceCents) : "\(euro(d.nowPriceCents)) bei \(Labels.chain(d.nowChain))"
        return HStack(spacing: 14) {
            StoreLogo(chain: d.offer.chain, size: 34)
                .frame(width: Theme.S.rowCircle, height: Theme.S.rowCircle).background(Theme.C.blue1, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(d.name).font(Theme.F.serif(17, relativeTo: .body)).lineLimit(1)
                (Text("−\(d.savingPct) %").foregroundStyle(Theme.C.deal)
                    + Text(" bei \(Labels.chain(d.offer.chain)) · \(euro(d.offer.priceCents)) statt \(now)"))
                    .font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button {
                busy = d.name
                Task {
                    if await store.deferToNextWeek(d) {
                        store.flash("„\(d.name)“ → Nächste Woche")
                        withAnimation(Theme.spring) { deals.removeAll { x in x.name == d.name } }
                    }
                    busy = nil
                }
            } label: {
                Group {
                    if busy == d.name { Hop3().frame(width: 60) } else { Text("verschieben") }
                }
                .font(Theme.F.text(13, .extrabold, relativeTo: .footnote)).foregroundStyle(Theme.C.blue3)
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .disabled(busy != nil)
            .accessibilityLabel("„\(d.name)“ auf nächste Woche schieben")
        }
        .frame(minHeight: 52)
        .overlay(alignment: .top) { Hairline() }
    }
}

// MARK: 43 Budget-Rest

/// Start (S1 gescrollt): „Budget-Rest – wie wär's mit …“ als große Zahl mit Ideen-Zeilen bzw. „Über Budget“ mit
/// günstigerer Alternative (Mockup „Knopf wartet“: Zahl rot, Gericht als Zeile, Knopf blau mit hüpfenden Zutaten). Bei „ok“ nichts.
struct BudgetHintCard: View {
    @Environment(AppStore.self) private var store
    @State private var budget: BudgetDTO?
    @State private var ideas: [BudgetIdeaDTO]?
    @State private var ideasError: String?
    @State private var planIdea: BudgetIdeaDTO?
    @State private var rerolling = false
    @State private var added: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            if let b = budget, b.state == "rest" {
                rest(b).transition(.opacity)
            } else if let b = budget, b.state == "over", let over = b.over {
                overView(b, over).transition(.opacity)
            }
        }
        .animation(Theme.spring, value: budget)
        .animation(Theme.spring, value: ideas)
        .task(id: store.plan?.totalCents) { await load() }
        .confirmationDialog("Wann einplanen?", isPresented: Binding(get: { planIdea != nil }, set: { on in if !on { planIdea = nil } }),
                            titleVisibility: .visible, presenting: planIdea) { idea in
            ForEach((store.household?.planDays ?? Array(0..<7)).sorted(), id: \.self) { d in
                Button(Labels.dayNames[d]) { Task { await plan(idea, day: d) } }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { idea in
            Text("„\(idea.title)“ als \(Labels.meal(idea.kind))")
        }
    }

    private func load() async {
        guard store.plan != nil else { budget = nil; return }
        budget = try? await store.planBudget()
        guard budget?.state == "rest" else { return }
        ideasError = nil
        do {
            ideas = try await store.ideasForBudget()
        } catch APIError.http(502) {
            ideasError = "Die Ideen-Suche ist gerade nicht erreichbar."
        } catch {
            ideasError = error.localizedDescription
        }
    }

    private func rest(_ b: BudgetDTO) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            StatF(label: "Budget-Rest –\nwie wär's mit …", value: euro(b.restCents), size: 52)
            VStack(spacing: 0) {
                if let ideas {
                    if ideas.isEmpty {
                        Text("Gerade keine Idee, die ins Restbudget passt.").font(Theme.F.text(13, .semibold, relativeTo: .footnote))
                            .foregroundStyle(Theme.C.ink2).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                    }
                    ForEach(Array(ideas.enumerated()), id: \.element.title) { i, idea in ideaRow(idea).appear(delay: Double(i) * 0.06) }
                } else if let ideasError {
                    HStack {
                        Text(ideasError).font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                        Spacer()
                        Button("Erneut versuchen") { Task { await load() } }
                            .font(Theme.F.text(13, .extrabold, relativeTo: .footnote)).foregroundStyle(Theme.C.blue3).frame(minHeight: 44)
                    }
                    .overlay(alignment: .top) { Hairline() }
                } else {
                    HStack(spacing: 14) {
                        Hop3()
                        Text("Ideen werden gesucht …").font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                        Spacer()
                    }
                    .frame(minHeight: 52)
                    .overlay(alignment: .top) { Hairline() }
                }
            }
            .padding(.top, 12)
        }
    }

    private func ideaRow(_ idea: BudgetIdeaDTO) -> some View {
        let look: (String, Color) = switch idea.kind {
        case "vorrat": ("pasta", Theme.C.blue1)
        case "snack": ("tomato", Theme.C.rose)
        default: ("pot", Theme.C.sand)
        }
        let done = added.contains(idea.title)
        let kind = idea.kind == "vorrat" ? "Vorrat\(idea.stockup.map { t in " \(t.packs)×" } ?? "")" : Labels.meal(idea.kind)
        return Button {
            if idea.kind == "vorrat", let t = idea.stockup {
                withAnimation(Theme.spring) { _ = added.insert(idea.title) }
                Task { await store.addStockup(t) }
            } else if idea.recipe != nil {
                planIdea = idea
            }
        } label: {
            HStack(spacing: 14) {
                Ill(look.0).frame(width: Theme.S.rowImage, height: Theme.S.rowImage)
                    .frame(width: Theme.S.rowCircle, height: Theme.S.rowCircle).background(look.1, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(idea.title).font(Theme.F.serif(17, relativeTo: .body)).foregroundStyle(Theme.C.ink).multilineTextAlignment(.leading)
                    Text("\(kind) · \(euro(idea.costCents))").font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                }
                Spacer(minLength: 4)
                Text(done ? "erledigt" : idea.kind == "vorrat" ? "auf die Liste" : "einplanen")
                    .font(Theme.F.text(13, .extrabold, relativeTo: .footnote)).foregroundStyle(done ? Theme.C.ink3 : Theme.C.blue3)
            }
            .frame(minHeight: 52)
            .overlay(alignment: .top) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(done)
        .sensoryFeedback(.success, trigger: done)
    }

    private func overView(_ b: BudgetDTO, _ over: BudgetDTO.Over) -> some View {
        let meal = store.plan?.entries.first { e in e.id == over.entryId }
        return VStack(alignment: .leading, spacing: 0) {
            StatF(label: "Über Budget", value: euro(-b.restCents), size: 56, valueColor: Theme.C.deal)
            Text("Günstigere Alternative für \(Labels.dayNames[max(0, min(over.day, 6))])?").font(Theme.F.t2)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 28)
            HStack(spacing: 14) {
                Plate(url: meal.flatMap { m in mediaURL(m.recipe.imageUrl) }, size: 54, seed: over.title)
                VStack(alignment: .leading, spacing: 1) {
                    Text(over.title).font(Theme.F.rowName)
                    Text(([euro(over.costCents)] + (meal.map { m in ["\(m.recipe.prepMinutes) min"] } ?? [])).joined(separator: " · "))
                        .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                    Text("neu würfeln mit höchstens \(euro(over.maxCostCents))").font(Theme.F.text(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Theme.C.ink2)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 76)
            .overlay(alignment: .top) { Hairline() }
            .padding(.top, 14)
            Button {
                guard let meal else { return }
                rerolling = true
                Task {
                    await store.reroll(meal, maxCost: over.maxCostCents)
                    rerolling = false
                    if store.error == nil { store.flash("Günstigere Alternative eingeplant") }
                }
            } label: {
                ZStack {
                    if rerolling { Hop3() } else { Text("Günstiger würfeln").font(Theme.F.button).foregroundStyle(Theme.C.onInk) }
                }
                .frame(maxWidth: .infinity, minHeight: Theme.S.button)
                .background(rerolling ? Theme.C.blue : Theme.C.ink, in: Capsule())
                .animation(.easeInOut(duration: 0.25), value: rerolling)
                .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .disabled(rerolling || meal == nil)
            .accessibilityLabel(rerolling ? "Würfelt …" : "Günstiger würfeln")
            .padding(.top, 22)
        }
    }

    private func plan(_ idea: BudgetIdeaDTO, day: Int) async {
        guard let r = idea.recipe else { return }
        if await store.addEntry(recipeId: r.id, day: day, mealType: idea.kind) {
            withAnimation(Theme.spring) { _ = added.insert(idea.title) }
            store.flash("Eingeplant: \(Labels.days[day]) · \(Labels.meal(idea.kind))")
        }
    }
}

// MARK: 42 Laden-Empfehlung

/// Einkauf (S5): Empfehlungs-Zeile „Rewe + Lidl · 39,50 € / 2,30 € gespart“ mit „So aufteilen“, darunter die zweite
/// Möglichkeit (antippen = wählen) und „Mehr“ (Weg, Artikel ohne Preis).
struct StoreAdviceCard: View {
    @Environment(AppStore.self) private var store
    let listId: Int
    @State private var combos: [StoreComboDTO]?
    @State private var failed = false
    @State private var picked: [String]?
    @State private var assigning = false
    @State private var more = false

    var body: some View {
        let open = store.listItems.filter { i in !i.checked && i.nextWeek != true }
        VStack(spacing: 0) {
            if let combos, combos.count > 1, !open.isEmpty {
                content(combos).transition(.opacity)
            } else if failed {
                HStack {
                    Text("Laden-Empfehlung gerade nicht verfügbar.").font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                    Spacer()
                    Button("Erneut versuchen") { Task { await load() } }
                        .font(Theme.F.text(13, .extrabold, relativeTo: .footnote)).foregroundStyle(Theme.C.blue3).frame(minHeight: 44)
                }
                .overlay(alignment: .top) { Hairline() }
            } else if combos == nil && !open.isEmpty {
                Skeleton8(height: 68)
            }
        }
        .animation(Theme.spring, value: combos)
        .task(id: open.map(\.id).hashValue ^ open.map(\.chain).hashValue) { await load() }
    }

    private func load() async {
        do {
            let found = try await store.storeCombos(listId)
            combos = found
            failed = false
        } catch {
            failed = combos == nil
        }
    }

    private func content(_ combos: [StoreComboDTO]) -> some View {
        let single = combos.first { c in c.chains.count == 1 }
        let pair = combos.first { c in c.chains.count == 2 && c.savedCents > 0 }
        let shown = [single, pair].compactMap { c in c }
        let chosenChains = picked ?? combos[0].chains
        let chosen = combos.first { c in c.chains == chosenChains } ?? combos[0]
        let other = shown.first { c in c.chains != chosen.chains }
        let way = chosen.chains.count > 1 ? chosen.extraKm.map { km in "+1 Laden, +\(num(km, 1...1)) km" } : chosen.distanceKm.map { km in "\(num(km, 1...1)) km Weg" }
        let unpriced: String? = chosen.unpriced == 0 ? nil : chosen.unpriced == 1 ? "1 Artikel ohne bekannten Preis zählt nicht mit."
            : "\(chosen.unpriced) Artikel ohne bekannten Preis zählen nicht mit."
        let details = [way, unpriced].compactMap { s in s }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Icon(.trophy).foregroundStyle(Theme.C.ink)
                    .frame(width: Theme.S.rowCircle, height: Theme.S.rowCircle).background(Theme.C.blue1, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(chosen.chains.map(Labels.chain).joined(separator: " + ")) · \(euro(chosen.totalCents))")
                        .font(Theme.F.text(16, .extrabold, relativeTo: .body))
                    if chosen.savedCents > 0 {
                        Text("\(euro(chosen.savedCents)) gespart").font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.success)
                    }
                }
                Spacer(minLength: 4)
                Button {
                    assigning = true
                    Task {
                        if await store.assignStores(listId, chosen.chains) { await load() }
                        assigning = false
                    }
                } label: {
                    Group { if assigning { Hop3().frame(width: 70) } else { Pill8(text: "So aufteilen") } }
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .disabled(assigning)
                .sensoryFeedback(.success, trigger: assigning)
            }
            .padding(.vertical, 10)
            .overlay(alignment: .top) { Hairline() }
            HStack {
                if let other {
                    Button { withAnimation(Theme.spring) { picked = other.chains } } label: {
                        Text("\(other.chains.count == 1 ? "Alles bei \(Labels.chain(other.chains[0]))" : other.name) · \(euro(other.totalCents))")
                            .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityHint("Diesen Vorschlag wählen")
                }
                Spacer()
                if !details.isEmpty {
                    Button { withAnimation(Theme.spring) { more.toggle() } } label: {
                        HStack(spacing: 0) { Text("Mehr"); Icon(.chev, size: 16).rotationEffect(.degrees(more ? 90 : 0)) }
                            .font(Theme.F.text(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .frame(minHeight: 44)
            .overlay(alignment: .top) { Hairline() }
            .sensoryFeedback(.selection, trigger: picked)
            if more {
                Text(details.joined(separator: " · ")).font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                    .fixedSize(horizontal: false, vertical: true).padding(.bottom, 8).transition(.opacity)
            }
        }
    }
}

// MARK: Selbsttest

enum SavingSelfTest {
    static func run() {
        let o = Demo.offers[6]
        let t = StockupDTO(offer: o, packs: 6, weeks: 6, weeklyUse: 1, savingCents: 300, normalPriceCents: 199)
        assert(t.text == "6 Packungen reichen ~6 Wochen, sparst \(euro(300))", t.text)
        var one = t
        one.packs = 1; one.weeks = nil
        assert(one.text.hasPrefix("1 Packung (vorsichtig geschätzt"), one.text)
        assert(StoreComboDTO(chains: ["lidl"], totalCents: 1, perStore: [:], savedCents: 0, unpriced: 0).name == "alles bei Lidl")
        assert(Verdict.badge("zu_wenig_daten") == nil && Verdict.badge("gut")?.text == "👍 Gutes Angebot")
        var later = o
        later.validFrom = "2999-01-01"
        assert(later.startsLater && !o.startsLater)
    }
}
