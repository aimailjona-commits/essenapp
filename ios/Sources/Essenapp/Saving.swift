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

    var text: String {
        let packs = packs == 1 ? "1 Packung" : "\(self.packs) Packungen"
        guard let weeks else { return "\(packs) (vorsichtig geschätzt, noch ohne Verbrauchsdaten), sparst \(euro(savingCents))" }
        return "\(packs) \(self.packs == 1 ? "reicht" : "reichen") ~\(num(weeks, 0...0)) Wochen, sparst \(euro(savingCents))"
    }
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

/// Kleine Badges auf Karten: Nutri-Score (Originalfarbe), 🌱 vegan, „Bio“.
struct LabelBadges: View {
    let offer: OfferDTO

    var body: some View {
        if offer.hasLabels {
            HStack(spacing: 4) {
                if let n = offer.nutriScore { NutriBadge(score: n) }
                if offer.vegan == true {
                    Text("🌱").font(.system(size: 11)).frame(width: 20, height: 20).background(Theme.C.card, in: Circle())
                        .accessibilityLabel("vegan")
                }
                if offer.bio == true {
                    Text("Bio").font(Theme.F.micro).foregroundStyle(Theme.C.success)
                        .padding(.horizontal, 6).frame(height: 20)
                        .background(Theme.C.card, in: Capsule()).background(Theme.C.successSoft, in: Capsule())
                }
            }
        }
    }
}

struct NutriBadge: View {
    let score: String
    var size: CGFloat = 20

    var body: some View {
        Text(score).font(.system(size: size * 0.6, weight: .heavy, design: .rounded))
            .foregroundStyle(score == "C" ? Theme.C.onBright : .white)
            .frame(width: size, height: size)
            .background(Theme.C.nutri[score] ?? Theme.C.text3, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityLabel("Nutri-Score \(score)")
    }
}

/// Angebotsdetail: Erklärung + Quelle der Badges.
struct LabelsInfoCard: View {
    let offer: OfferDTO
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bio, vegan, Nutri-Score").font(Theme.F.headline)
            if let n = offer.nutriScore {
                line(NutriBadge(score: n, size: 28), "Nutri-Score \(n)", "Nährwert-Ampel von A (günstig) bis E (ungünstig) pro 100 g")
            }
            if offer.vegan == true {
                line(Text("🌱").font(.system(size: 18)).frame(width: 28, height: 28), "Vegan", "ohne tierische Zutaten")
            }
            if offer.bio == true {
                line(Text("Bio").font(Theme.F.micro).foregroundStyle(Theme.C.success).frame(width: 28, height: 28)
                        .background(Theme.C.successSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous)),
                     "Bio", "laut Bio-Siegel bzw. „Bio“ im Prospekt")
            }
            Text("Quelle: \((offer.labelSources ?? []).isEmpty ? "Prospekttext" : (offer.labelSources ?? []).joined(separator: " · ")). Wir zeigen nur sichere Treffer – lieber kein Badge als ein falsches.")
                .font(Theme.F.micro).foregroundStyle(Theme.C.text2).fixedSize(horizontal: false, vertical: true)
            if let code = offer.offCode, !code.isEmpty, let url = URL(string: "https://world.openfoodfacts.org/product/\(code)") {
                Button { openURL(url) } label: { Label("Bei Open Food Facts ansehen", systemImage: "arrow.up.right.square") }
                    .font(Theme.F.callout).frame(minHeight: 44)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func line(_ icon: some View, _ title: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.F.callout)
                Text(text).font(Theme.F.micro).foregroundStyle(Theme.C.text2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: 31 Vorratskauf

/// Angebotsdetail „Vorratstipp: 3 Packungen reichen ~6 Wochen, sparst 4,20 €“ + „3× auf die Liste“ (nur bei Tipp).
struct StockupTipCard: View {
    @Environment(AppStore.self) private var store
    let offer: OfferDTO
    @State private var tip: StockupDTO?
    @State private var added = false

    var body: some View {
        VStack(spacing: 0) {
            if let tip {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        Text("💡").font(.system(size: 22)).frame(width: 44, height: 44)
                            .background(Theme.C.successSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Vorratstipp").font(Theme.F.headline)
                            Text(tip.text).font(Theme.F.caption).foregroundStyle(Theme.C.text2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button {
                        added = true
                        Task { await store.addStockup(tip) }
                    } label: {
                        Label(added ? "Auf der Liste" : "\(tip.packs)× auf die Liste", systemImage: added ? "checkmark" : "cart.badge.plus")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(PrimaryButtonStyle(color: added ? Theme.C.accentDeep : Theme.C.action))
                    .disabled(added)
                    .sensoryFeedback(.success, trigger: added)
                }
                .padding(16)
                .card()
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(Theme.spring, value: tip)
        .task(id: offer.id) { tip = await store.stockup(for: offer) }
    }
}

/// Start-Karte „💡 Vorrat anlegen lohnt sich“ (max. 3).
struct StockupCard: View {
    @Environment(AppStore.self) private var store
    @State private var tips: [StockupDTO] = []
    @State private var added: Set<Int> = []

    var body: some View {
        VStack(spacing: 0) {
            if !tips.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label { Text("Vorrat anlegen lohnt sich").font(Theme.F.headline) } icon: { Text("💡") }
                    ForEach(Array(tips.prefix(3).enumerated()), id: \.element.offer.id) { i, t in
                        row(t).appear(delay: Double(i) * 0.05)
                        if i < min(tips.count, 3) - 1 { Divider() }
                    }
                }
                .padding(16)
                .card()
                .transition(.opacity)
            }
        }
        .task { tips = (try? await store.stockups()) ?? tips }
    }

    private func row(_ t: StockupDTO) -> some View {
        let hue = Theme.hue(category: t.offer.category)
        let done = added.contains(t.offer.id)
        return HStack(spacing: 12) {
            NavigationLink { OfferDetailView(offer: t.offer) } label: {
                HStack(spacing: 12) {
                    RemoteImage(url: URL(string: t.offer.imageUrl)) { Text(hue.emoji).font(.system(size: 22)) }
                        .padding(5).frame(width: 48, height: 48).background(hue.tint, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.offer.title).font(Theme.F.callout).foregroundStyle(Theme.C.text1).lineLimit(1)
                        Text(t.text).font(Theme.F.micro).foregroundStyle(Theme.C.text2).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(PressableStyle())
            Button {
                withAnimation(Theme.spring) { _ = added.insert(t.offer.id) }
                Task { await store.addStockup(t) }
            } label: {
                Text(done ? "✓" : "\(t.packs)×").font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(done ? .white : Theme.C.onAction)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(done ? Theme.C.success : Theme.C.action, in: Capsule())
                    .contentTransition(.numericText())
            }
            .buttonStyle(PressableStyle())
            .disabled(done)
            .sensoryFeedback(.success, trigger: done)
            .accessibilityLabel(done ? "Auf der Liste" : "\(t.packs)× \(t.offer.title) auf die Liste")
        }
    }
}

// MARK: 30 Nächste Woche günstiger

/// Start-Karte „👀 Nächste Woche günstiger“: Kauf verschieben.
struct NextWeekCard: View {
    @Environment(AppStore.self) private var store
    @State private var deals: [NextWeekDealDTO] = []
    @State private var busy: String?

    var body: some View {
        VStack(spacing: 0) {
            if !deals.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label { Text("Nächste Woche günstiger").font(Theme.F.headline) } icon: { Text("👀") }
                    ForEach(Array(deals.prefix(3).enumerated()), id: \.element.name) { i, d in
                        row(d).appear(delay: Double(i) * 0.05)
                        if i < min(deals.count, 3) - 1 { Divider() }
                    }
                }
                .padding(16)
                .card()
                .transition(.opacity)
            }
        }
        .animation(Theme.spring, value: deals)
        .task(id: store.householdList?.items.count) { deals = (try? await store.nextWeekDeals()) ?? deals }
    }

    private func row(_ d: NextWeekDealDTO) -> some View {
        let now = d.nowChain.isEmpty ? euro(d.nowPriceCents) : "\(euro(d.nowPriceCents)) bei \(Labels.chain(d.nowChain))"
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                StoreLogo(chain: d.offer.chain, size: 32)
                (Text(d.name).bold() + Text(" nächste Woche ") + Text("−\(d.savingPct) %").bold().foregroundStyle(Theme.C.deal)
                    + Text(" bei \(Labels.chain(d.offer.chain)) (\(euro(d.offer.priceCents)) statt \(now)) – Kauf verschieben?"))
                    .font(Theme.F.caption).foregroundStyle(Theme.C.text1).fixedSize(horizontal: false, vertical: true)
            }
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
                Label(busy == d.name ? "Verschiebe …" : "Auf nächste Woche schieben", systemImage: "calendar.badge.clock")
                    .font(Theme.F.callout).foregroundStyle(Theme.C.accentDeep)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Theme.C.accentSoft, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .disabled(busy != nil)
            .sensoryFeedback(.success, trigger: deals.count)
        }
    }
}

// MARK: 43 Budget-Rest

/// Start-Karte nach dem Plan: „💶 Noch 6,80 € übrig – wie wär's mit …“ (3 Ideen) bzw. „⚠️ 3,20 € über Budget – günstigere
/// Alternative für Do?“ (würfelt das teuerste Gericht mit Kostengrenze). Bei „ok“ keine Karte.
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
                overCard(b, over).transition(.opacity)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("💶 Noch \(euro(b.restCents)) übrig – wie wär's mit …").font(Theme.F.headline)
                .contentTransition(.numericText())
            if let ideas {
                if ideas.isEmpty {
                    Text("Gerade keine Idee, die ins Restbudget passt.").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                }
                ForEach(Array(ideas.enumerated()), id: \.element.title) { i, idea in ideaRow(idea).appear(delay: Double(i) * 0.06) }
            } else if let ideasError {
                HStack {
                    Text(ideasError).font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                    Spacer()
                    Button("Erneut versuchen") { Task { await load() } }.font(Theme.F.callout).frame(minHeight: 44)
                }
            } else {
                ForEach(0..<3, id: \.self) { _ in SkeletonCard(height: 56) }
                Text("Ideen werden gesucht …").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
            }
        }
        .padding(16)
        .card()
    }

    private func ideaRow(_ idea: BudgetIdeaDTO) -> some View {
        let emoji = ["dessert": "🍰", "snack": "🥨", "vorrat": "🥫"][idea.kind] ?? "✨"
        let done = added.contains(idea.title)
        let action = idea.kind == "vorrat" ? "auf die Liste" : "einplanen"
        return Button {
            if idea.kind == "vorrat", let t = idea.stockup {
                withAnimation(Theme.spring) { _ = added.insert(idea.title) }
                Task { await store.addStockup(t) }
            } else if idea.recipe != nil {
                planIdea = idea
            }
        } label: {
            HStack(spacing: 12) {
                Text(emoji).font(.system(size: 22)).frame(width: 44, height: 44)
                    .background(Theme.C.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(idea.title).font(Theme.F.callout).foregroundStyle(Theme.C.text1).multilineTextAlignment(.leading)
                    Text(idea.kind == "vorrat" ? "Vorratskauf · \(idea.stockup.map { t in "\(t.packs)×" } ?? "")" : Labels.meal(idea.kind))
                        .font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(euro(idea.costCents)).font(.system(.subheadline, design: .rounded, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Theme.C.text1)
                    Text(done ? "✓ erledigt" : action).font(Theme.F.micro).foregroundStyle(done ? Theme.C.success : Theme.C.accentDeep)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(done)
        .sensoryFeedback(.success, trigger: done)
    }

    private func overCard(_ b: BudgetDTO, _ over: BudgetDTO.Over) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("⚠️ \(euro(-b.restCents)) über Budget – günstigere Alternative für \(Labels.days[max(0, min(over.day, 6))])?")
                .font(Theme.F.headline).fixedSize(horizontal: false, vertical: true)
            Text("„\(over.title)“ kostet \(euro(over.costCents)) – neu würfeln mit höchstens \(euro(over.maxCostCents)).")
                .font(Theme.F.caption).foregroundStyle(Theme.C.text2).fixedSize(horizontal: false, vertical: true)
            Button {
                guard let meal = store.plan?.entries.first(where: { e in e.id == over.entryId }) else { return }
                rerolling = true
                Task {
                    await store.reroll(meal, maxCost: over.maxCostCents)
                    rerolling = false
                    if store.error == nil { store.flash("Günstigere Alternative eingeplant") }
                }
            } label: {
                if rerolling { ProgressView().tint(Theme.C.onAction) } else { Label("Günstiger würfeln", systemImage: "dice") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(rerolling)
        }
        .padding(16)
        .background(Theme.C.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.R.card, style: .continuous))
        .background(Theme.C.card, in: RoundedRectangle(cornerRadius: Theme.R.card, style: .continuous))
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

/// Einkauf-Tab: „🏆 Am günstigsten: alles bei Lidl 41,20 € · Rewe + Lidl 38,90 € (2,30 € gespart, +1 Laden, +1,2 km)“,
/// „So aufteilen“ ordnet die Liste dem gewählten Vorschlag zu (Standard: der günstigste).
struct StoreAdviceCard: View {
    @Environment(AppStore.self) private var store
    let listId: Int
    @State private var combos: [StoreComboDTO]?
    @State private var failed = false
    @State private var picked: [String]?
    @State private var assigning = false

    var body: some View {
        let open = store.listItems.filter { i in !i.checked && i.nextWeek != true }
        VStack(spacing: 0) {
            if let combos, combos.count > 1, !open.isEmpty {
                card(combos).transition(.opacity)
            } else if failed {
                HStack {
                    Text("Laden-Empfehlung gerade nicht verfügbar.").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                    Spacer()
                    Button("Erneut versuchen") { Task { await load() } }.font(Theme.F.callout).frame(minHeight: 44)
                }
                .padding(.horizontal, 16).padding(.vertical, 6).card()
            } else if combos == nil && !open.isEmpty {
                SkeletonCard(height: 150)
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

    private func card(_ combos: [StoreComboDTO]) -> some View {
        let single = combos.first { c in c.chains.count == 1 }
        let pair = combos.first { c in c.chains.count == 2 && c.savedCents > 0 }
        let shown = [single, pair].compactMap { c in c }
        let chosen = picked ?? combos[0].chains
        return VStack(alignment: .leading, spacing: 10) {
            Text("🏆 Am günstigsten").font(Theme.F.headline)
            ForEach(shown, id: \.chains) { c in row(c, on: c.chains == chosen) }
            if let u = shown.map(\.unpriced).max(), u > 0 {
                Text(u == 1 ? "1 Artikel ohne bekannten Preis zählt nicht mit." : "\(u) Artikel ohne bekannten Preis zählen nicht mit.")
                    .font(Theme.F.micro).foregroundStyle(Theme.C.text2)
            }
            Button {
                assigning = true
                Task {
                    if await store.assignStores(listId, chosen) { await load() }
                    assigning = false
                }
            } label: { Label(assigning ? "Teile auf …" : "So aufteilen", systemImage: "arrow.triangle.branch") }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(assigning)
            .sensoryFeedback(.success, trigger: assigning)
        }
        .padding(16)
        .card()
    }

    private func row(_ c: StoreComboDTO, on: Bool) -> some View {
        let extra = [c.savedCents > 0 ? "\(euro(c.savedCents)) gespart" : nil, c.chains.count > 1 ? "+1 Laden" : nil,
                     c.chains.count > 1 ? c.extraKm.map { km in "+\(num(km, 1...1)) km" } : c.distanceKm.map { km in "\(num(km, 1...1)) km Weg" }]
            .compactMap { s in s }
        return Button { withAnimation(Theme.spring) { picked = c.chains } } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 22))
                    .foregroundStyle(on ? Theme.C.accent : Theme.C.text3).contentTransition(.symbolEffect(.replace))
                HStack(spacing: -6) { ForEach(c.chains, id: \.self) { ch in StoreLogo(chain: ch, size: 30) } }
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).font(Theme.F.callout).foregroundStyle(Theme.C.text1)
                    if !extra.isEmpty {
                        Text(extra.joined(separator: " · ")).font(Theme.F.micro).foregroundStyle(c.savedCents > 0 ? Theme.C.success : Theme.C.text2)
                    }
                }
                Spacer(minLength: 4)
                Text(euro(c.totalCents)).font(.system(.headline, design: .rounded, weight: .bold)).monospacedDigit()
                    .foregroundStyle(Theme.C.text1)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityAddTraits(on ? .isSelected : [])
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
