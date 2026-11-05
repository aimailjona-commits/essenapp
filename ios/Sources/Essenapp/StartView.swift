import EssenappShareUI
import SwiftUI

/// S1 Start v9 (f.html 1A): Bereiche mit Label + Serifen-Titel – Heute (Gericht-Leiste), Deine Woche (Tageskreise),
/// Angebote für dich (wischbar), Einkauf, Schnell (4 Kacheln), Fortschritt. Darunter Budget-Rest, Spar-Tipps, Specials.
struct StartView: View {
    @Environment(AppStore.self) private var store
    @Binding var tab: AppTab
    @Binding var showGenerator: Bool
    @Binding var planWeek: Bool  // Woche per Swipe (20)
    @Binding var allOpen: Bool  // „Alles“ (Suche, alle Funktionen)
    @State private var banner: SpecialDTO?  // Feiertag/Saison in ≤ 14 Tagen (25)
    @State private var noMood = false  // „Keine Lust“ (16)
    @State private var importing = false  // Rezept aus Link/Instagram (5)
    @State private var opened: Int?  // importiertes Rezept öffnen
    @State private var tips = 0  // weitere Spar-Tipps (30, 31)
    @State private var showTips = false
    @State private var next: AchievementDTO?  // nächster Erfolg (54)

    // Maße aus dem Mockup (f.html, Bildschirm-Oberkante = 0)
    private enum K {
        static let top: CGFloat = 66
        static let blob = (left: CGFloat(210), top: CGFloat(100), size: CGFloat(330))
        static let groupTop: CGFloat = 36, todayTop: CGFloat = 26
        static let card: CGFloat = 28
        static let tile: CGFloat = 164
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if store.plan == nil {
                    PlanEmptyHero { planWeek = true }
                        .overlay(alignment: .topTrailing) { headButtons.padding(.top, K.top).padding(.trailing, Theme.pagePadding) }
                } else {
                    content
                }
            }
            .ignoresSafeArea(edges: .top)
            .onAppear {  // Demo: Spar-Bereich (43/30/31) im Bild
                if ["savings", "budgetover"].contains(Demo.screen ?? "") { proxy.scrollTo("savings", anchor: .top) }
            }
        }
        .refreshable {
            await store.loadAll()
            banner = await store.specials()?.banner
        }
        .task { banner = await store.specials()?.banner }
        .task(id: store.plan?.id) {
            let a = (try? await store.nextWeekDeals())?.count ?? 0
            let b = (try? await store.stockups())?.count ?? 0
            tips = min(a, 3) + min(b, 3)
        }
        .task { next = (try? await store.achievements())?.filter { a in !a.unlocked }.max { a, b in a.fraction < b.fraction } }
        .sheet(isPresented: $noMood) { NoMoodSheet().presentationDetents([.large]) }
        .sheet(isPresented: $showTips) { TipsSheet().presentationDetents([.large]) }
        .sheet(isPresented: $importing, onDismiss: { store.recipesVersion += 1 }) {
            ShareFlowView(input: nil, session: store.shareSession, onOpen: { id in
                importing = false
                opened = id
            }) { importing = false }
            .presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet)
        }
        .navigationDestination(item: $opened) { id in SavedRecipeView(recipeId: id) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            today
            if let plan = store.plan {
                head(Self.weekLabel(plan.week), "Deine Woche", link: "Ansehen ›") { tab = .woche }
                weekCard(plan)
            }
            offers
            shop
            head("Schnell", "Was willst du tun?", link: "Alles ›") { withAnimation(Theme.spring) { allOpen = true } }
            tiles
            head("Du & Familie", "Fortschritt")
            progress
            VStack(alignment: .leading, spacing: 12) {  // bleibt aus v8 (nicht im Mockup ersetzt)
                BudgetHintCard()  // Budget-Rest / über Budget (43)
                FavoriteDealsCard()  // Lieblingsrezepte günstig
            }
            .padding(.horizontal, Theme.pagePadding).padding(.top, 24)
            .id("savings")
        }
        .padding(.bottom, Theme.S.nav)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pinned(left: K.blob.left, top: K.blob.top) {
            Circle().fill(Theme.C.blue1).frame(width: K.blob.size, height: K.blob.size).accessibilityHidden(true)
        }
    }

    // MARK: Kopf

    private var name: String { store.profile?.name ?? store.household?.name ?? "" }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(.de)))
                    .font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                Text(name.isEmpty ? "Hallo" : "Hallo \(name)").font(Theme.F.t1).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            headButtons
        }
        .padding(.horizontal, Theme.pagePadding).padding(.top, K.top)
    }

    /// Suche (→ „Alles“ mit Suchfeld) und Avatar (→ Einstellungen).
    private var headButtons: some View {
        HStack(spacing: 8) {
            Button { withAnimation(Theme.spring) { allOpen = true } } label: {
                Icon(.search, size: 20).foregroundStyle(Theme.C.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.C.bg, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Suchen")
            NavigationLink { SettingsView() } label: {
                Text(String(name.prefix(1)).uppercased()).font(Theme.F.serif(20)).foregroundStyle(Theme.C.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.C.sand, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Einstellungen")
        }
    }

    /// Bereichs-Kopf (`.f9-gh`): Label 11 + Serif 27, rechts „… ›“ in Blau.
    private func head(_ label: String, _ title: String, color: Color = Theme.C.ink2, top: CGFloat = K.groupTop,
                      link: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label.uppercased()).font(Theme.F.lbl).tracking(11 * 0.08).foregroundStyle(color)
                Text(title).font(Theme.F.serif(27, relativeTo: .title)).foregroundStyle(Theme.C.ink)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let link, let action {
                Button(action: action) {
                    Text(link).font(Theme.F.text(13, .extrabold, relativeTo: .footnote)).foregroundStyle(Theme.C.blue3)
                        .padding(12).contentShape(Rectangle()).padding(-12)  // Tap-Fläche 44
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(.horizontal, Theme.pagePadding).padding(.top, top).padding(.bottom, 12)
    }

    /// „2026-W45“ → „KW 45 · 2.–8. Nov“.
    static func weekLabel(_ week: String) -> String {
        let parts = week.split(separator: "-W")
        guard parts.count == 2, let y = Int(parts[0]), let w = Int(parts[1]) else { return "Diese Woche" }
        let cal = Calendar(identifier: .iso8601)
        guard let mon = cal.date(from: DateComponents(weekday: 2, weekOfYear: w, yearForWeekOfYear: y)),
              let sun = cal.date(byAdding: .day, value: 6, to: mon) else { return "KW \(w)" }
        let month = { (d: Date) in d.formatted(.dateTime.month(.abbreviated).locale(.de)).replacingOccurrences(of: ".", with: "") }
        let day = { (d: Date) in cal.component(.day, from: d) }
        let range = month(mon) == month(sun) ? "\(day(mon)).–\(day(sun)). \(month(sun))" : "\(day(mon)). \(month(mon)) – \(day(sun)). \(month(sun))"
        return "KW \(w) · \(range)"
    }

    // MARK: Heute

    @ViewBuilder private var today: some View {
        if let meal = store.todayMeal {
            head("\(Labels.dayNames[store.today]) · \(Labels.meal(meal.mealType))", "Heute", color: Theme.C.blue3, top: K.todayTop)
            TodayBlock(meal: meal) { tab = .einkauf }
        } else {
            head(Labels.dayNames[store.today], "Heute", color: Theme.C.blue3, top: K.todayTop)
            VStack(alignment: .leading, spacing: 4) {
                Text("Nichts geplant").font(Theme.F.serif(25, relativeTo: .title))
                Text("Heute ist frei.").font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
            }
            .padding(.horizontal, Theme.pagePadding)
        }
    }

    // MARK: Deine Woche

    private func weekCard(_ plan: PlanDTO) -> some View {
        let days = Set(plan.entries.map(\.day))
        let done = days.filter { d in d < store.today }.count  // shortcut: vergangene Tage mit Gericht gelten als gekocht, bis das Backend „gekocht“ je Tag liefert
        let free = (store.today..<7).first { d in !days.contains(d) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { d in
                    dayCircle(d, plan)
                    if d < 6 { Spacer(minLength: 0) }
                }
            }
            PlanStat(label: "Gekocht") {
                (Text("\(done)") + Text("/\(days.count)").foregroundStyle(Theme.C.ink3))
                    .font(Theme.F.num(40)).tracking(Theme.F.numTracking(40))
            }
            .padding(.top, 18)
            HStack(spacing: 8) {
                Button { planWeek = true } label: {
                    HStack(spacing: 8) {
                        Icon(.heart, size: 18)
                        Text(free.map { d in "\(Labels.days[d]) swipen" } ?? "Woche swipen").lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(Theme.F.text(14, .extrabold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.C.onInk)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.C.ink, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                Button { showGenerator = true } label: {
                    HStack(spacing: 8) {
                        Icon(.dice, size: 18)
                        Text("Überrasch mich").lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(Theme.F.text(14, .extrabold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.C.ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .overlay(Capsule().strokeBorder(Theme.C.ink, lineWidth: Theme.S.hair))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.top, 14)
        }
        .padding(18)
        .background(Theme.C.card, in: RoundedRectangle(cornerRadius: K.card, style: .continuous))
        .padding(.horizontal, Theme.pagePadding)
    }

    /// Tageskreis 38: gekocht = Tinte mit Haken, heute = Ring, sonst Foto des Gerichts bzw. leer.
    @ViewBuilder private func dayCircle(_ d: Int, _ plan: PlanDTO) -> some View {
        let meal = plan.entries.first { m in m.day == d }
        let now = d == store.today
        let done = meal != nil && d < store.today
        let circle = VStack(spacing: 6) {
            ZStack {
                if done {
                    Circle().fill(Theme.C.ink)
                    Icon(.check, size: 16).foregroundStyle(Theme.C.onInk)
                } else {
                    RemoteImage(url: meal.flatMap { m in mediaURL(m.recipe.imageUrl) }, contentMode: .fill) { Color.clear }
                        .clipShape(Circle())
                        .overlay { if !now { Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
                }
            }
            .frame(width: 38, height: 38)
            .overlay { if now { Circle().strokeBorder(Theme.C.ink, lineWidth: 2).padding(-4) } }
            Text(Labels.days[d]).font(Theme.F.text(11, .extrabold, relativeTo: .caption2))
                .foregroundStyle(now ? Theme.C.ink : Theme.C.ink2)
        }
        .frame(width: 38)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Labels.dayNames[d]): \(meal?.recipe.title ?? "frei")\(done ? ", gekocht" : "")")
        if let meal {
            NavigationLink { RecipeDetailView(meal: meal) } label: { circle.contentShape(Rectangle()) }.buttonStyle(PressableStyle())
        } else {
            circle
        }
    }

    // MARK: Angebote für dich

    /// Angebote aus den Zutaten des Plans; ohne Treffer die stärksten Rabatte.
    private var forYou: (matched: Bool, offers: [OfferDTO]) {
        let ids = Set(store.plan?.entries.flatMap { m in m.recipe.ingredients.compactMap(\.offerId) } ?? [])
        let hits = store.offers.filter { o in ids.contains(o.id) }
        if !hits.isEmpty { return (true, Array(hits.prefix(10))) }
        return (false, Array(store.offers.sorted { a, b in (a.discount ?? 0) > (b.discount ?? 0) }.prefix(10)))
    }

    @ViewBuilder private var offers: some View {
        let pick = forYou
        if !pick.offers.isEmpty {
            head(pick.matched ? "Passt zu deinem Plan" : "Diese Woche", "Angebote für dich", link: "Alle \(store.offers.count) ›") { tab = .angebote }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(pick.offers) { o in StartOfferCard(offer: o) }
                }
                .padding(.horizontal, Theme.pagePadding).padding(.bottom, 6)
            }
        }
    }

    // MARK: Einkauf

    @ViewBuilder private var shop: some View {
        let items = (store.householdList?.items ?? []).filter { i in !i.checked && i.nextWeek != true }
        let counts = Dictionary(grouping: items, by: \.chain).mapValues(\.count)
        let chains = counts.keys.sorted { a, b in (counts[a] ?? 0) > (counts[b] ?? 0) }.prefix(3)
        head(items.count == 1 ? "1 Sache offen" : "\(items.count) Sachen offen", "Einkauf", link: "Liste ›") { tab = .einkauf }
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(chains), id: \.self) { chain in
                    NavigationLink { ShoppingListView(chain: chain) } label: {
                        HStack(spacing: 8) {
                            StoreLogo(chain: chain, size: 30)
                            Text("\(chain.isEmpty ? "Überall" : Labels.chain(chain)) · \(counts[chain] ?? 0)")
                                .font(Theme.F.text(14, .extrabold, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink)
                        }
                        .padding(.vertical, 7).contentShape(Rectangle()).padding(.vertical, -7)  // Tap-Fläche 44
                    }
                    .buttonStyle(PressableStyle())
                }
                if chains.isEmpty {
                    Text("Liste ist leer").font(Theme.F.text(14, .extrabold, relativeTo: .subheadline))
                }
            }
            .frame(width: 190, alignment: .leading)
            StatF(label: "Gespart diese Woche", value: euro(store.plan?.savedCents ?? 0), size: 34, valueColor: Theme.C.deal)
                .padding(.top, 18)
            HStack(spacing: 8) {
                NavigationLink { PantryView(page: .constant(1)).backBar() } label: { chip(.box, "Vorrat") }
                    .buttonStyle(PressableStyle())
                NavigationLink { CouponWalletView(page: .constant(2)).backBar() } label: {
                    chip(.gift, store.coupons.isEmpty ? "Coupons" : "\(store.coupons.count) Coupons")
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.top, 12)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) { Ill("bag").frame(width: 140).offset(x: 20, y: -6) }
        .background(Theme.C.sand)
        .clipShape(RoundedRectangle(cornerRadius: K.card, style: .continuous))
        .padding(.horizontal, Theme.pagePadding)
    }

    private func chip(_ icon: Icon8, _ title: String) -> some View {
        HStack(spacing: 6) {
            Icon(icon, size: 16)
            Text(title).lineLimit(1)
        }
        .font(Theme.F.chip)
        .foregroundStyle(Theme.C.ink)
        .padding(.horizontal, 15)
        .frame(height: Theme.S.chip)
        .background(Theme.C.bg, in: Capsule())
        .padding(4).contentShape(Rectangle()).padding(-4)
    }

    // MARK: Schnell

    private var tiles: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                tile("Kühlschrank-Foto", "Was koche ich jetzt?", ill: "fridge", tint: Theme.C.sage, id: "fridge") { store.scanning = true }
                tile("Rezept importieren", "Instagram, Link", ill: "cookbook", tint: Theme.C.blue1, id: "import") { importing = true }
            }
            HStack(spacing: 12) {
                tile("Keine Lust?", "15 min, ohne Einkauf", ill: "lying", tint: Theme.C.rose, illWidth: 120, illRight: -20, id: "nomood") { noMood = true }
                tile("Barcode scannen", "merken & Alarm", ill: "binoculars", tint: Theme.C.sand, id: "barcode") { store.barcode = true }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
    }

    private func tile(_ title: String, _ sub: String, ill: String, tint: Color, illWidth: CGFloat = 96, illRight: CGFloat = -8,
                      id: String, action: @escaping () -> Void) -> some View {
        Button {
            AllSheet.markTried(id)
            action()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.F.serif(20, relativeTo: .title3)).multilineTextAlignment(.leading)
                Text(sub).font(Theme.F.text(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
            }
            .foregroundStyle(Theme.C.ink)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: K.tile, alignment: .topLeading)
            .background(alignment: .bottomTrailing) { Ill(ill).frame(width: illWidth).offset(x: -illRight, y: 12) }
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: K.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: K.card, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Fortschritt

    private var progress: some View {
        VStack(spacing: 0) {
            ReviewRow()  // Wochenrückblick (55)
            NavigationLink { AchievementsView() } label: {
                StartRow(icon: .trophy, tint: Theme.C.sand, name: "Erfolge",
                         sub: next.map { a in "Noch \(a.remainingValue) bis „\(a.title)“" } ?? "Sparen und gesund essen")
            }
            .buttonStyle(PressableStyle())
            if tips > 0 {
                Button { showTips = true } label: {
                    StartRow(icon: .tag, tint: Theme.C.sand, name: tips == 1 ? "1 weiterer Spar-Tipp" : "\(tips) weitere Spar-Tipps",
                             sub: "Nächste Woche günstiger · Vorrat anlegen")
                }
                .buttonStyle(PressableStyle())
            }
            if let banner {
                SpecialBanner(banner: banner) {
                    store.generatorSpecial = banner.key
                    showGenerator = true
                }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
    }
}

/// Heute (1A): Gericht mit Teller rechts und der festen Gericht-Leiste Kochen · Tauschen · Liste · Teilen · Mehr.
private struct TodayBlock: View {
    @Environment(AppStore.self) private var store
    let meal: MealDTO
    let toList: () -> Void
    @State private var choosing = false
    @State private var shareCard = false
    @State private var shareLink = false
    @State private var noMood = false
    @State private var guests = false

    private enum K {
        static let width: CGFloat = 190
        static let plate: CGFloat = 190, plateRight: CGFloat = -30, plateTop: CGFloat = -70
        static let act: CGFloat = 46, actWidth: CGFloat = 56
    }

    var body: some View {
        let deals = meal.recipe.ingredients.filter { i in i.offerId != nil }.count
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink { RecipeDetailView(meal: meal) } label: {
                Text(meal.recipe.title).font(Theme.F.serif(25, relativeTo: .title)).foregroundStyle(Theme.C.ink)
                    .multilineTextAlignment(.leading).lineLimit(4).minimumScaleFactor(0.7)
            }
            .buttonStyle(.plain)
            .frame(width: K.width, alignment: .leading)
            (Text("\(meal.recipe.prepMinutes) min · \(euro(PlanWeek.perPortion(meal))) p. P.")
                + (deals > 0 ? Text(" · ") + Text("\(deals) im Angebot").foregroundStyle(Theme.C.deal) : Text("")))
                .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                .frame(width: K.width, alignment: .leading)
                .padding(.top, 6)
            HStack(spacing: 0) {
                NavigationLink { RecipeDetailView(meal: meal) } label: { act(.play, "Kochen", go: true) }
                    .buttonStyle(PressableStyle())
                Spacer(minLength: 4)
                Button { choosing = true } label: { act(.swap, "Tauschen") }.buttonStyle(PressableStyle())
                Spacer(minLength: 4)
                Button(action: toList) { act(.bag, "Liste") }.buttonStyle(PressableStyle())
                Spacer(minLength: 4)
                Button { shareCard = true } label: { act(.share, "Teilen") }.buttonStyle(PressableStyle())
                Spacer(minLength: 4)
                Menu {
                    Button("Keine Lust?", systemImage: "moon.zzz") { noMood = true }
                    Button("Gäste", systemImage: "person.2") { guests = true }
                    Button("Als Link teilen", systemImage: "link") { shareLink = true }
                } label: { act(.dots, "Mehr") }
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, Theme.pagePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pinned(right: K.plateRight, top: K.plateTop) {
            PlanPlate(url: mediaURL(meal.recipe.imageUrl), size: K.plate)
        }
        .modifier(RerollDialog(meal: meal, isPresented: $choosing) { direction, wish in
            Task { await store.reroll(meal, direction: direction, wish: wish) }
        })
        .sheet(isPresented: $shareCard) { ShareCardSheet(meal: meal).presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
        .sheet(isPresented: $shareLink) {
            RecipeLinkSheet(recipeId: meal.recipe.id, title: meal.recipe.title).presentationDetents([.medium, .large])
                .presentationCornerRadius(Theme.R.sheet)
        }
        .sheet(isPresented: $noMood) { NoMoodSheet().presentationDetents([.large]) }
        .sheet(isPresented: $guests) { GuestsSheet(meal: meal).presentationDetents([.height(466), .large]) }
    }

    /// Knopf der Gericht-Leiste (`.f9-acts`): Kreis 46 mit Tinten-Rand (Kochen gefüllt), Beschriftung 11.
    private func act(_ icon: Icon8, _ title: String, go: Bool = false) -> some View {
        VStack(spacing: 5) {
            Icon(icon, size: 19)
                .foregroundStyle(go ? Theme.C.onInk : Theme.C.ink)
                .frame(width: K.act, height: K.act)
                .background(go ? Theme.C.ink : Theme.C.bg, in: Circle())
                .overlay { if !go { Circle().strokeBorder(Theme.C.ink, lineWidth: Theme.S.hair) } }
            Text(title).font(Theme.F.text(11, .extrabold, relativeTo: .caption2)).foregroundStyle(Theme.C.ink)
        }
        .frame(width: K.actWidth)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// Angebots-Karte (1A „Angebote für dich“): Laden, Rabatt, Name, Preis; Merken · Auf Liste · Rezepte damit.
private struct StartOfferCard: View {
    @Environment(AppStore.self) private var store
    let offer: OfferDTO

    private enum K {
        static let width: CGFloat = 156, radius: CGFloat = 26
        static let art: CGFloat = 120, artRight: CGFloat = -26, artTop: CGFloat = -18
        static let img: CGFloat = 96, imgLeft: CGFloat = 10, imgTop: CGFloat = 18
        static let nameTop: CGFloat = 62
        static let mini: CGFloat = 32
    }

    var body: some View {
        let watched = store.watch(for: offer) != nil
        let listed = store.isOnList(offer)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                StoreLogo(chain: offer.chain, size: 30)
                if let d = offer.discount { DealPill(text: "−\(d) %") }
            }
            NavigationLink { OfferDetailView(offer: offer) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(offer.title).font(Theme.F.text(14, .extrabold, relativeTo: .subheadline)).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(euro(offer.priceCents)).font(Theme.F.num(30)).tracking(Theme.F.numTracking(30))
                }
                .foregroundStyle(Theme.C.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, K.nameTop)
            HStack(spacing: 6) {
                Button { Task { await store.toggleWatch(offer) } } label: { mini(.heart, on: watched) }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(watched ? "Von der Merkliste entfernen" : "Auf die Merkliste")
                Button { store.addToList(offer) } label: { mini(listed ? .check : .plus, go: true) }
                    .buttonStyle(PressableStyle())
                    .disabled(listed)
                    .accessibilityLabel(listed ? "Auf der Einkaufsliste" : "Auf die Einkaufsliste")
                NavigationLink { OfferDetailView(offer: offer) } label: { mini(.book) }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Rezepte damit")
            }
            .padding(.top, 10)
        }
        .padding(14)
        .frame(width: K.width, alignment: .leading)
        .background(alignment: .topTrailing) {
            Circle().fill(OfferArt.tint(offer.title, category: offer.category))
                .frame(width: K.art, height: K.art)
                .overlay(alignment: .topLeading) {
                    OfferArt(title: offer.title, url: offer.imageUrl).frame(width: K.img, height: K.img).offset(x: K.imgLeft, y: K.imgTop)
                }
                .offset(x: -K.artRight, y: K.artTop)
                .accessibilityHidden(true)
        }
        .background(Theme.C.card)
        .clipShape(RoundedRectangle(cornerRadius: K.radius, style: .continuous))
    }

    /// `.f9-mini`: Kreis 32 (Haarlinie, gemerkt = Blau, Liste = Tinte); Tap-Fläche 44.
    private func mini(_ icon: Icon8, on: Bool = false, go: Bool = false) -> some View {
        Icon(icon, size: 15)
            .foregroundStyle(go ? Theme.C.onInk : Theme.C.ink)
            .frame(width: K.mini, height: K.mini)
            .background(go ? Theme.C.ink : on ? Theme.C.blue : Theme.C.bg, in: Circle())
            .overlay { if !go && !on { Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
            .padding(6).contentShape(Rectangle()).padding(-6)
    }
}

/// Zeile im Start (S1 gescrollt): Kreis 48 mit Icon, Name Serif 17, Unterzeile 12, Chevron.
private struct StartRow: View {
    let icon: Icon8
    let tint: Color
    let name: String
    let sub: String

    var body: some View {
        HStack(spacing: 14) {
            Icon(icon).foregroundStyle(Theme.C.ink)
                .frame(width: Theme.S.rowCircle, height: Theme.S.rowCircle).background(tint, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(Theme.F.serif(17, relativeTo: .body)).lineLimit(2)
                Text(sub).font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2).lineLimit(1)
            }
            .foregroundStyle(Theme.C.ink)
            Spacer(minLength: 8)
            Icon(.chev, size: 18).foregroundStyle(Theme.C.ink3)
        }
        .frame(minHeight: Theme.S.row)
        .overlay(alignment: .top) { Hairline() }
        .contentShape(Rectangle())
    }
}

/// „Wochenrückblick KW 44“ → Story; lange drücken → Archiv; ab Sonntag beim ersten Öffnen einmal automatisch (55).
private struct ReviewRow: View {
    @Environment(AppStore.self) private var store
    @State private var r: WeekReviewDTO?
    @State private var archive = false

    var body: some View {
        VStack(spacing: 0) {
            if let r {
                Button { store.review = r.week } label: {
                    StartRow(icon: .book, tint: Theme.C.blue1, name: "Wochenrückblick KW \(r.kw)",
                             sub: "\(euro(r.money.spentCents)) · \(euro(r.money.savedCents + r.money.bonusCents)) gespart")
                }
                .buttonStyle(PressableStyle())
                .contextMenu { Button("Alle Wochenrückblicke", systemImage: "book") { archive = true } }
                .accessibilityAction(named: "Alle Wochenrückblicke") { archive = true }
                .transition(.opacity)
            }
        }
        .animation(Theme.spring, value: r)
        .navigationDestination(isPresented: $archive) { ReviewArchiveView() }
        .task {
            guard let fresh = try? await store.review("") else { return }
            r = fresh
            let sunday = Calendar.current.component(.weekday, from: .now) == 1
            if sunday, !store.demo, UserDefaults.standard.string(forKey: "reviewShown") != fresh.week {
                UserDefaults.standard.set(fresh.week, forKey: "reviewShown")
                store.review = fresh.week
            }
        }
    }
}

/// „N weitere Spar-Tipps“: nächste Woche günstiger (30) und Vorrat anlegen (31).
struct TipsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .top) {
                        Text("Spar-Tipps").font(Theme.F.t2)
                        Spacer()
                        CloseButton { dismiss() }
                    }
                    NextWeekCard()
                    StockupCard()
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 24)
            }
            .background(Theme.C.bg)
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet8()
    }
}

/// S1 Leer (auch Woche ohne Plan): Figur liegt auf dem Hügel, „Plan erstellen“ mit Pfeil (`a2-empty`).
/// Während der Erstellung bzw. bei Fehler zeigt dieselbe Fläche Topf bzw. Fehler.
struct PlanEmptyHero: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if store.generating {
                VStack(spacing: 0) {
                    PotLoader().padding(.top, 140)
                    Text("Dein Plan entsteht …").font(Theme.F.t2).padding(.top, 30)
                    Text("Dauert meist unter einer Minute").font(Theme.F.text(14, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Theme.C.ink2).padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
            } else if let error = store.error {
                VStack(spacing: 10) {
                    Ill("binoculars").frame(width: 180).padding(.top, 160)
                    Text("Das hat nicht geklappt").font(Theme.F.t2)
                    Text(error).font(Theme.F.text(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2)
                        .multilineTextAlignment(.center)
                    PrimaryButton(title: "Erneut versuchen", icon: .refresh) { Task { await store.loadAll() } }.padding(.top, 8)
                }
                .padding(.horizontal, Theme.pagePadding)
                .frame(maxWidth: .infinity)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .containerRelativeFrame(.vertical, alignment: .top)
    }

    private var empty: some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
            let breathe = reduceMotion ? 0 : (1 - cos(2 * .pi * t / 4)) / 2  // 4 s hin und zurück
            let nudge = Self.nudge(reduceMotion ? 1 : t.truncatingRemainder(dividingBy: 4) / 0.6)
            // Kreis, Figur und „z“ als Hintergrund/Overlay: nehmen keinen Platz ein (510er-Kreis machte die Seite sonst breiter)
            VStack(alignment: .leading, spacing: 8) {
                Text("Noch nichts\ngeplant.").font(Theme.F.serif(42, relativeTo: .largeTitle))
                Text("Kein Stress – in 30 Sekunden steht dein Plan.").font(Theme.F.text(17, .medium, relativeTo: .body))
                    .foregroundStyle(Theme.C.ink2)
            }
            .padding(.horizontal, Theme.pagePadding).padding(.top, 66 + 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .topLeading) {
                if !reduceMotion {
                    zzz(t, delay: 0, size: 24, x: 300, y: 458)
                    zzz(t, delay: 2.25, size: 18, x: 304, y: 466)
                }
            }
            .pinned(left: 14, top: 330) {
                Ill("lying").frame(width: 360)
                    .scaleEffect(x: 1 + 0.012 * breathe, y: 1 + 0.025 * breathe, anchor: UnitPoint(x: 0.5, y: 0.85))
            }
            .pinned(left: -60, top: 470) {
                Circle().fill(Theme.C.blue1).frame(width: 510, height: 510).accessibilityHidden(true)
            }
            .overlay(alignment: .bottom) {
                Button(action: action) {
                    HStack {
                        Text("Plan erstellen").font(Theme.F.text(17, .extrabold, relativeTo: .headline)).foregroundStyle(Theme.C.ink)
                        Spacer()
                        Icon(.arrow).foregroundStyle(Theme.C.onInk).offset(x: 5 * nudge.arrow)
                            .frame(width: 72, height: 72)
                            .background(Theme.C.ink, in: Circle())
                            .scaleEffect(nudge.scale).offset(y: nudge.y)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 124)
                .accessibilityLabel("Plan erstellen")
            }
        }
        .clipped()
    }

    /// Knopf stupst alle 4 s an: hoch −10 (1,04), kurz +2, zurück; Pfeil 5 nach rechts.
    private static func nudge(_ k: Double) -> (y: CGFloat, scale: CGFloat, arrow: CGFloat) {
        guard k < 1 else { return (0, 1, 0) }
        let y: Double = k < 0.4 ? -10 * Bezier.easeInOut(k / 0.4) : k < 0.7 ? -10 + 12 * Bezier.easeInOut((k - 0.4) / 0.3) : 2 - 2 * Bezier.easeInOut((k - 0.7) / 0.3)
        let up = max(0, -y / 10)
        return (CGFloat(y), CGFloat(1 + 0.04 * up), CGFloat(up))
    }

    /// „z“ steigt auf, wächst und verblasst (4,5 s).
    private func zzz(_ t: Double, delay: Double, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        let raw = ((t - delay) / 4.5).truncatingRemainder(dividingBy: 1)
        let p = raw < 0 ? raw + 1 : raw
        return Text("z").font(Theme.F.serif(size)).foregroundStyle(Theme.C.ink)
            .scaleEffect(0.6 + 0.5 * p)
            .opacity(sin(.pi * p))
            .offset(x: x + 26 * p, y: y - 72 * p)
            .accessibilityHidden(true)
    }
}

