import SwiftUI

/// S1 Start.
struct StartView: View {
    @Environment(AppStore.self) private var store
    @Binding var showGenerator: Bool
    @State private var search = ""
    @State private var banner: SpecialDTO?  // Feiertag/Saison in ≤ 14 Tagen (25)
    @State private var noMood = false  // „Keine Lust“ (16)

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<11: "Guten\nMorgen."
        case 11..<17: "Mahl-\nzeit."
        default: "Guten\nAbend."
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Großes Foto mit Begrüßung (Vorlage „HEY, ALEX.“)
                ZStack(alignment: .bottomLeading) {
                    HeroImage(name: "grill").frame(height: 330)
                    LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(greeting.uppercased()).font(Theme.F.hero).foregroundStyle(.white).lineSpacing(-6)
                        Text(store.plan.map { "KW \($0.week.suffix(2)) · \($0.entries.count) Gerichte geplant" } ?? "Was kochen wir diese Woche?")
                            .font(Theme.F.callout).foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(20)
                    .padding(.bottom, 10)
                }
                .overlay(alignment: .topTrailing) {
                    NavigationLink { SettingsView() } label: {
                        Image(systemName: "person.crop.circle").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.C.text1)
                            .frame(width: 44, height: 44).background(Theme.C.card.opacity(0.9), in: Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Einstellungen")
                    .padding(.top, 56).padding(.trailing, 20)
                }
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 36, bottomTrailingRadius: 36, style: .continuous))
                .padding(.horizontal, -Theme.pagePadding)
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
                    if let meal = store.todayMeal {
                        HStack {
                            Text("Heute · \(Labels.dayNames[meal.day])").font(Theme.F.headline)
                            Spacer()
                            Text(Labels.meal(meal.mealType)).font(Theme.F.micro).foregroundStyle(Theme.C.accentDeep)
                                .padding(.horizontal, 12).frame(height: 28).background(Theme.C.accentSoft, in: Capsule())
                        }
                        NavigationLink { RecipeDetailView(meal: meal) } label: { MealCardBig(meal: meal) }
                            .buttonStyle(PressableStyle()).padding(.top, 70).appear()
                        Button { noMood = true } label: { Text("😮‍💨 Keine Lust") }
                            .buttonStyle(SecondaryButtonStyle()).appear(delay: 0.05)
                    }
                    HStack {
                        Text("Diese Woche").font(Theme.F.headline)
                        Spacer()
                        Text("\(plan.entries.count) Gerichte").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 14) {
                            ForEach(Array(plan.entries.enumerated()), id: \.element) { i, meal in
                                NavigationLink { RecipeDetailView(meal: meal) } label: { MealCardSmall(meal: meal) }
                                    .buttonStyle(PressableStyle()).appear(delay: Double(i) * 0.04)
                            }
                        }
                        .padding(.horizontal, Theme.pagePadding).padding(.top, 40).padding(.bottom, 16)
                    }
                    .padding(.horizontal, -Theme.pagePadding)
                    BudgetCard(plan: plan, budgetCents: store.household?.budgetFoodWeekCents ?? 0).appear(delay: 0.1)
                    FavoriteDealsCard().appear(delay: 0.12)
                    FridgeCard().appear(delay: 0.14)
                    DealsTeaser().appear(delay: 0.15)
                } else {
                    EmptyState(emoji: "🥘", title: "Noch kein Wochenplan",
                               text: "Wir planen deine Woche mit den aktuellen Angeboten deiner Läden.",
                               buttonTitle: "Plan erstellen") { showGenerator = true }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
        }
        .ignoresSafeArea(edges: .top)
        .scrollDismissesKeyboard(.immediately)
        .refreshable {
            await store.loadAll()
            banner = await store.specials()?.banner
        }
        .task { banner = await store.specials()?.banner }
        .sheet(isPresented: $noMood) { NoMoodSheet().presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
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

struct MealCardBig: View {
    let meal: MealDTO

    var body: some View {
        let deals = meal.recipe.ingredients.filter { $0.offerId != nil }.count
        VStack(spacing: 4) {
            Plate(url: mediaURL(meal.recipe.imageUrl), size: 170, seed: meal.recipe.title).padding(.top, -78).padding(.bottom, 12)
            Text(meal.recipe.title).font(.system(.title3, design: .rounded, weight: .bold)).multilineTextAlignment(.center)
                .foregroundStyle(Theme.C.text1)
            HStack(spacing: 14) {
                Label("\(meal.recipe.prepMinutes) min", systemImage: "clock")
                Label("\(euro(meal.costCents / max(meal.recipe.servings, 1))) p. P.", systemImage: "eurosign.circle")
                Label("\(meal.recipe.servings)", systemImage: "person.2")
            }
            .font(Theme.F.caption).foregroundStyle(Theme.C.text2).padding(.top, 2)
            if deals > 0 {
                DealBadge(text: deals == 1 ? "1 Zutat im Angebot" : "\(deals) Zutaten im Angebot", style: .soft).padding(.top, 10)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .card()
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

struct BudgetCard: View {
    let plan: PlanDTO
    let budgetCents: Int
    @State private var progress = 0.0

    var body: some View {
        let ratio = min(Double(plan.totalCents) / Double(max(budgetCents, 1)), 1)
        let over = plan.totalCents > budgetCents
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Theme.C.surface, lineWidth: 10)
                Circle().trim(from: 0, to: progress)
                    .stroke(over ? Theme.C.danger : Theme.C.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(ratio * 100)) %").font(.system(.footnote, design: .rounded, weight: .bold))
            }
            .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text("Budget KW \(plan.week.suffix(2))").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(euro(plan.totalCents)).font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("/ \(euro(budgetCents))").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                }
                if plan.savedCents > 0 {
                    Label("\(euro(plan.savedCents)) gespart", systemImage: "arrow.down.circle.fill")
                        .font(Theme.F.callout).foregroundStyle(Theme.C.success)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .card()
        .onAppear { withAnimation(.easeOut(duration: 0.9).delay(0.2)) { progress = ratio } }
    }
}
