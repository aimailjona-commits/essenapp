import SwiftUI

/// S1 Start (v3, redesign-v3.md 6.1): schwarzer Kopf mit Tages-Satz, darunter Creme-Sheet „Diese Woche“.
struct StartView: View {
    @Environment(AppStore.self) private var store
    @Binding var showGenerator: Bool
    @Binding var planWeek: Bool  // Woche per Swipe (20)
    @Binding var quickOpen: Bool  // Schnell-Aktionen hinter dem „+“ im Kopf (v8)
    @State private var search = ""
    @State private var banner: SpecialDTO?  // Feiertag/Saison in ≤ 14 Tagen (25)
    @State private var noMood = false  // „Keine Lust“ (16)

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 20) {
                    sheetContent
                }
                .padding(.horizontal, 22).padding(.top, 22)
                .padding(.bottom, 120)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.C.startSheet, in: UnevenRoundedRectangle(topLeadingRadius: Theme.R.sheet, topTrailingRadius: Theme.R.sheet, style: .continuous))
            }
            .background(alignment: .top) { Theme.C.ink.frame(height: 900).offset(y: -400) }  // Tinte auch beim Überziehen oben
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {  // Demo: Spar-Karten (43/30/31) im Bild
            if ["savings", "budgetover"].contains(Demo.screen ?? "") { proxy.scrollTo("savings", anchor: .top) }
        }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .scrollDismissesKeyboard(.immediately)
        .refreshable {
            await store.loadAll()
            banner = await store.specials()?.banner
        }
        .task { banner = await store.specials()?.banner }
        .sheet(isPresented: $noMood) { NoMoodSheet().presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
    }

    // MARK: Kopf (Tinte)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                DisplayHeader(line1: "Heute", size: 52, onDark: true)
                HStack(spacing: 10) {
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack(spacing: 4) {
                            Circle().fill(Theme.C.day[store.today]).frame(width: 7, height: 7)
                            Text("KW \(week)").foregroundStyle(.white)
                        }
                        Text(Labels.dayNames[store.today]).foregroundStyle(Theme.C.onInk2)
                    }
                    .font(.system(.subheadline, weight: .semibold))
                    NavigationLink { SettingsView() } label: {
                        Image(systemName: "person").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: Theme.S.roundButtonSmall, height: Theme.S.roundButtonSmall)
                            .background(Theme.C.inkRaised, in: Circle())
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Einstellungen")
                }
                .padding(.top, 4)
            }
            SentenceHero(parts: sentence).padding(.top, 30)
            if !chains.isEmpty {
                HStack(spacing: 8) {
                    Text(chains.count == 1 ? "Aus 1 Prospekt" : "Aus \(chains.count) Prospekten")
                        .font(.system(.subheadline, weight: .semibold)).foregroundStyle(Theme.C.onInk2).lineLimit(1)
                    ForEach(chains.prefix(3), id: \.self) { StoreChip(chain: $0, onDark: true) }
                }
                .padding(.top, 22)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 66)
        .padding(.bottom, 46)
    }

    private var week: String {
        store.plan.map { String($0.week.suffix(2)) } ?? String(Calendar(identifier: .iso8601).component(.weekOfYear, from: .now))
    }

    private var chains: [String] {
        var seen = Set<String>()
        return (store.household?.stores ?? []).filter(\.enabled).map(\.chain).filter { seen.insert($0).inserted }
    }

    private var sentence: [SentenceHero.Part] {
        let name = store.profile?.name ?? store.household?.name ?? ""
        var parts: [SentenceHero.Part] = [.text(name.isEmpty ? "Hallo!" : "Hallo \(name)!")]
        guard let today = store.todayMeal else {
            parts.append(.text(store.plan == nil ? "Noch kein Plan für diese Woche." : "Heute ist nichts geplant."))
            return parts
        }
        parts += [.text("Heute gibt's"), .bold(today.recipe.title),
                  .sticker(mediaURL(today.recipe.imageUrl), "🍽️", -8)]
        if let next = tomorrowMeal {
            parts += [.glue(","), .text("morgen"), .bold(next.recipe.title), .sticker(mediaURL(next.recipe.imageUrl), "🍽️", 7)]
        }
        if let saved = store.plan?.savedCents, saved > 0 {
            parts += [.text("– und mit den Angeboten"), .bold("sparst du"), .amount(euro(saved)), .emoji("🏷️")]
        } else {
            parts.append(.glue("."))
        }
        return parts
    }

    private var tomorrowMeal: MealDTO? {
        let meals = store.plan?.entries.filter { $0.day == (store.today + 1) % 7 } ?? []
        return meals.first { $0.mealType == store.todayMeal?.mealType } ?? meals.first
    }

    // MARK: Sheet (Creme)

    @ViewBuilder private var sheetContent: some View {
        if let plan = store.plan {
            HStack(alignment: .firstTextBaseline) {
                Text("Diese Woche").font(Theme.F.section).tracking(-0.66)
                Spacer()
                HStack(spacing: 6) {
                    Text("\(plan.entries.count) Gerichte")
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .font(.system(.subheadline, weight: .semibold)).foregroundStyle(Theme.C.text2)
            }
            VStack(spacing: 0) {
                ForEach(Array(upcoming(plan).enumerated()), id: \.element) { i, meal in
                    if i > 0 { Theme.C.line.frame(height: 1) }
                    NavigationLink { RecipeDetailView(meal: meal) } label: { WeekRow(meal: meal, today: meal.day == store.today) }
                        .buttonStyle(PressableStyle()).appear(delay: Double(i) * 0.04)
                }
            }
            .padding(.top, -8)
        }
        // Ab hier noch nicht gemockt (redesign-v3.md 7, Gruppe A) – Bausteine im v3-Stil
        SearchField(text: $search, placeholder: "Gericht oder Angebot suchen")
        if search.isEmpty, let banner {
            SpecialBanner(banner: banner) {
                store.generatorSpecial = banner.key
                showGenerator = true
            }
            .appear()
        }
        if !search.isEmpty {
            searchResults
        } else if let error = store.error, store.plan == nil {
            ErrorState(message: error) { Task { await store.loadAll() } }
        } else if store.generating && store.plan == nil {
            SkeletonCard(height: 300)
            SkeletonCard(height: 160)
        } else if let plan = store.plan {
            if store.todayMeal != nil {
                Button { noMood = true } label: { Text("😮‍💨 Keine Lust") }
                    .buttonStyle(SecondaryButtonStyle()).appear(delay: 0.05)
            }
            BudgetCard(plan: plan, budgetCents: store.household?.budgetFoodWeekCents ?? 0).appear(delay: 0.1).id("savings")
            BudgetHintCard()  // Budget-Rest / über Budget (43)
            NextWeekCard()  // nächste Woche günstiger (30)
            StockupCard()  // Vorrat anlegen lohnt sich (31)
            SpendingCard()  // Ausgaben des Monats (34)
            ReviewCard()  // Wochenrückblick (55)
            FavoriteDealsCard().appear(delay: 0.12)
            FridgeCard().appear(delay: 0.14)
            DealsTeaser().appear(delay: 0.15)
        } else {
            EmptyState(emoji: "🥘", title: "Noch kein Wochenplan",
                       text: "Wir planen deine Woche mit den aktuellen Angeboten deiner Läden.",
                       buttonTitle: "Woche planen") { planWeek = true }
        }
    }

    /// Gerichte ab heute, nach Tag und Mahlzeit.
    private func upcoming(_ plan: PlanDTO) -> [MealDTO] {
        let order = Labels.slotOrder
        return plan.entries.filter { $0.day >= store.today }
            .sorted { ($0.day, order.firstIndex(of: $0.mealType) ?? 9) < ($1.day, order.firstIndex(of: $1.mealType) ?? 9) }
    }

    private var searchResults: some View {
        let meals = store.plan?.entries.filter { $0.recipe.title.localizedCaseInsensitiveContains(search) } ?? []
        let offers = store.offers.filter { $0.title.localizedCaseInsensitiveContains(search) }.prefix(20)
        return VStack(alignment: .leading, spacing: 10) {
            if !meals.isEmpty { Text("Gerichte").font(Theme.F.headline) }
            ForEach(meals, id: \.self) { meal in
                NavigationLink { RecipeDetailView(meal: meal) } label: { MealRow(meal: meal) }.buttonStyle(PressableStyle())
            }
            if !offers.isEmpty { Text("Angebote").font(Theme.F.headline).padding(.top, 6) }
            ForEach(Array(offers)) { offer in
                NavigationLink { OfferDetailView(offer: offer) } label: { OfferRow(offer: offer) }.buttonStyle(PressableStyle())
            }
            if meals.isEmpty && offers.isEmpty {
                EmptyState(emoji: "🔍", title: "Nichts gefunden", text: "Versuch einen anderen Begriff.")
            }
        }
    }
}

/// Start-Karte „Kühlschrank scannen“ (69) → Kamera-Sheet.
struct FridgeCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Button { store.scanning = true } label: {
            HStack(spacing: 14) {
                Text("📸").font(.system(size: 26))
                    .frame(width: 52, height: 52)
                    .background(Theme.C.carbs.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kühlschrank scannen").font(Theme.F.callout)
                    Text("Fotos machen – wir füllen den Vorrat und schlagen Gerichte vor").font(Theme.F.micro)
                        .foregroundStyle(Theme.C.text2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.C.text3)
            }
            .foregroundStyle(Theme.C.text1)
            .padding(16)
            .card()
        }
        .buttonStyle(PressableStyle())
    }
}

/// Angebot als Zeile (Suche).
struct OfferRow: View {
    let offer: OfferDTO

    var body: some View {
        let hue = Theme.hue(category: offer.category)
        HStack(spacing: 12) {
            RemoteImage(url: URL(string: offer.imageUrl)) { Text(hue.emoji).font(.system(size: 24)) }
                .padding(6).frame(width: 52, height: 52).background(hue.tint, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 3) {
                Text(offer.title).font(.system(.subheadline, weight: .semibold)).lineLimit(1).foregroundStyle(Theme.C.text1)
                StoreChip(chain: offer.chain)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(euro(offer.priceCents)).font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(Theme.C.text1)
                if let d = offer.discount { Text("−\(d) %").font(Theme.F.micro).foregroundStyle(Theme.C.deal) }
            }
        }
        .padding(10)
        .card(radius: Theme.R.tile)
    }
}

/// Top-Angebote der Woche (größter Rabatt).
struct DealsTeaser: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let top = store.offers.filter { $0.discount != nil && !["drogerie", "haushalt"].contains($0.category) }
            .sorted { ($0.discount ?? 0) > ($1.discount ?? 0) }.prefix(8)
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("🔥 Top-Angebote").font(Theme.F.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(top)) { o in
                            NavigationLink { OfferDetailView(offer: o) } label: { MiniOffer(offer: o) }.buttonStyle(PressableStyle())
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            .padding(16)
            .card()
        }
    }
}

/// Zeile „Diese Woche“ (v3 `WeekRow`): Teller 56, Meta (heute in `deal`), Name, Preis/Zeit, Angebots-Pille oder Chevron.
struct WeekRow: View {
    let meal: MealDTO
    var today = false

    var body: some View {
        let deals = meal.recipe.ingredients.filter { $0.offerId != nil }.count
        HStack(spacing: 14) {
            Plate(url: mediaURL(meal.recipe.imageUrl), size: 56, seed: meal.recipe.title)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(today ? "Heute" : Labels.days[meal.day]) · \(Labels.meal(meal.mealType))".uppercased())
                    .font(.system(.caption, weight: .bold)).tracking(0.6)
                    .foregroundStyle(today ? Theme.C.deal : Theme.C.text2)
                Text(meal.recipe.title).font(.system(.headline, weight: .bold)).tracking(-0.34).lineLimit(2)
                    .multilineTextAlignment(.leading).foregroundStyle(Theme.C.text1)
                Text("\(euro(meal.costCents / max(Int(meal.basePortions), 1))) · \(meal.recipe.prepMinutes) min")
                    .font(.footnote).foregroundStyle(Theme.C.text2)
            }
            Spacer(minLength: 0)
            if deals > 0 {
                DealBadge(text: "\(deals) im Angebot")
            } else {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.C.text3)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct MealCardSmall: View {
    let meal: MealDTO

    var body: some View {
        VStack(spacing: 4) {
            Plate(url: mediaURL(meal.recipe.imageUrl), size: 96, seed: meal.recipe.title).padding(.top, -36)
            Text(meal.recipe.title).font(.system(.subheadline, design: .rounded, weight: .bold)).lineLimit(2)
                .multilineTextAlignment(.center).frame(minHeight: 36).foregroundStyle(Theme.C.text1)
            Text("\(euro(meal.costCents)) · \(meal.recipe.prepMinutes) min").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
        }
        .padding(14)
        .frame(width: 150)
        .overlay(alignment: .topLeading) {
            Text(Labels.days[meal.day].uppercased()).font(Theme.F.micro).foregroundStyle(Theme.C.accentDeep)
                .padding(.horizontal, 7).frame(height: 20).background(Theme.C.accentSoft, in: Capsule()).padding(10)
        }
        .card()
    }
}

/// Budget-Karte v3 (Tinte): geplant vs. Budget, Ersparnis-Pille, Balken in Limette.
struct BudgetCard: View {
    let plan: PlanDTO
    let budgetCents: Int
    @State private var progress = 0.0

    var body: some View {
        let ratio = min(Double(plan.totalCents) / Double(max(budgetCents, 1)), 1)
        let over = plan.totalCents > budgetCents
        let left = budgetCents - plan.totalCents
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Budget KW \(plan.week.suffix(2))".uppercased()).font(.system(.caption2, weight: .bold)).tracking(0.7)
                    .foregroundStyle(Theme.C.onInk3)
                Spacer()
                if plan.savedCents > 0 {
                    Text("−\(euro(plan.savedCents)) gespart").font(.system(.caption, weight: .bold)).foregroundStyle(Theme.C.onLime)
                        .padding(.horizontal, 10).frame(height: 26).background(Theme.C.lime, in: Capsule())
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(euro(plan.totalCents)).font(.system(.largeTitle, weight: .black)).tracking(-1.4).monospacedDigit()
                Text("von \(euro(budgetCents))").font(.system(.title3, weight: .semibold)).foregroundStyle(Theme.C.onInk2)
            }
            .foregroundStyle(.white).padding(.top, 8)
            GeometryReader { g in
                Capsule().fill(Theme.C.inkChipLine)
                Capsule().fill(over ? Theme.C.danger : Theme.C.lime).frame(width: g.size.width * progress)
            }
            .frame(height: 12).padding(.top, 14).padding(.bottom, 10)
            Text(over ? "\(euro(-left)) über Budget" : "Noch \(euro(left)) übrig")
                .font(.footnote).foregroundStyle(Theme.C.onInk3)
        }
        .padding(20)
        .background(Theme.C.ink, in: RoundedRectangle(cornerRadius: Theme.R.card, style: .continuous))
        .onAppear { withAnimation(.easeOut(duration: 0.9).delay(0.2)) { progress = ratio } }
        .accessibilityElement(children: .combine)
    }
}
