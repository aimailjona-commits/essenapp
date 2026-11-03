import SwiftUI

/// Tab „Rezepte“: S2 Wochenplan + S12 Meine Rezepte.
struct RecipesTab: View {
    @Environment(AppStore.self) private var store
    @Binding var showGenerator: Bool
    @State private var mine = Demo.screen == "recipes"
    @State private var filter = "alle"
    @State private var person: Int?  // „Für:“ in der Tagesansicht (48), nil = ich
    @State private var day = Demo.screen != nil ? 1 : (Calendar(identifier: .iso8601).component(.weekday, from: .now) + 5) % 7
    @State private var noMood = false  // „Keine Lust“ (16)
    @State private var guestsFor: MealDTO? = Demo.screen == "guests" ? Demo.plan.entries[3] : nil  // „Gäste hinzufügen“ (15)
    @Namespace private var dayPill

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PillSegment(options: [(false, "Wochenplan"), (true, "Meine Rezepte")], selection: $mine)

                if mine {
                    MyRecipesList(filter: $filter)
                } else if let plan = store.plan {
                    HStack(alignment: .bottom) {
                        DisplayHeader(line1: "KW \(plan.week.suffix(2))", line2: "Dein Plan")
                        ShareButton()
                        Button { showGenerator = true } label: {
                            Image(systemName: "arrow.clockwise").font(.system(size: 15, weight: .bold))
                                .frame(width: 40, height: 40).background(Theme.C.card, in: Circle())
                                .overlay(Circle().strokeBorder(Theme.C.line, lineWidth: 0.5))
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("Neuen Plan erstellen")
                    }
                    let eaters = store.profiles.filter { p in p.eatsOn(day: day, mealTypes: store.household?.mealTypes ?? Labels.mealTypes.map(\.0)) }
                    if !eaters.isEmpty {
                        HStack(spacing: 8) {
                            HStack(spacing: -8) { ForEach(eaters) { p in Avatar(profile: p) } }
                            Text("\(Labels.dayNames[day]) essen mit: \(eaters.map(\.name).joined(separator: ", "))")
                                .font(Theme.F.caption).foregroundStyle(Theme.C.text2).lineLimit(1)
                        }
                        .animation(Theme.spring, value: eaters)
                    }
                    if let v = plan.variety { VarietyChip(check: v) }  // Abwechslung (12)
                    weekAverage
                    HStack(spacing: 10) {
                        summary("eurosign.circle.fill", Theme.C.warning, euro(plan.totalCents), "von \(euro(store.household?.budgetFoodWeekCents ?? 0))")
                        summary("arrow.down.circle.fill", Theme.C.accent, euro(plan.savedCents), "gespart")
                        summary("fork.knife.circle.fill", Theme.C.kcal, "\(plan.entries.count)", "Gerichte")
                    }
                    if let l = plan.leftovers, l.planned > 0 || !l.left.isEmpty { LeftoversCard(leftovers: l) }  // Reste (19)
                    dayPicker(plan)
                    let meals = plan.entries.filter { $0.day == day }
                        .sorted { a, b in (Labels.slotOrder.firstIndex(of: a.mealType) ?? 9) < (Labels.slotOrder.firstIndex(of: b.mealType) ?? 9) }
                    if meals.isEmpty {
                        EmptyState(emoji: "😴", title: "Nichts geplant", text: "Für \(Labels.dayNames[day]) ist kein Gericht geplant.")
                    }
                    ForEach(Array(meals.enumerated()), id: \.element) { i, meal in
                        VStack(alignment: .leading, spacing: 8) {
                            Text((meal.mealType == "lunchbox" ? "🥡 " : "") + Labels.meal(meal.mealType).uppercased())
                                .font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                            MealRow(meal: meal, actions: true) { guestsFor = meal }
                        }
                        .appear(delay: Double(i) * 0.06)
                    }
                    .id(day)
                    if day == store.today && !meals.isEmpty {
                        Button { noMood = true } label: { Text("😮‍💨 Keine Lust") }.buttonStyle(SecondaryButtonStyle())
                    }
                    DayNutritionCard(day: day, person: $person)  // Tageswerte unten (S2)
                } else {
                    EmptyState(emoji: "📅", title: "Noch kein Wochenplan", text: "Erstelle deinen ersten Plan.",
                               buttonTitle: "Plan erstellen") { showGenerator = true }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
        }
        .onAppear {  // Start-Karte „Lieblingsrezepte günstig“ → gefilterte Liste
            if let f = store.recipeFilter { mine = true; filter = f; store.recipeFilter = nil }
        }
        .sheet(isPresented: $noMood) { NoMoodSheet().presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
        .sheet(item: $guestsFor) { m in GuestsSheet(meal: m).presentationDetents([.height(380), .medium]).presentationCornerRadius(Theme.R.sheet) }
    }

    /// Wochenschnitt der gewählten Person im Kopf (2).
    @ViewBuilder private var weekAverage: some View {
        let id = person ?? store.profile?.memberId
        if let n = store.nutrition, let m = n.members.first(where: { m in m.memberId == id }) ?? n.members.first {
            Label("\(m.emoji) Ø \(Int(m.avgKcal.rounded())) / \(m.kcalGoal) kcal · \(Int(m.avgProtein.rounded())) / \(m.proteinGoal) g Protein pro Tag",
                  systemImage: "flame.fill")
                .font(Theme.F.caption).foregroundStyle(Theme.C.text2).lineLimit(2)
                .contentTransition(.numericText())
                .animation(Theme.spring, value: m)
        }
    }

    private func dayPicker(_ plan: PlanDTO) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { d in
                let has = plan.entries.contains { $0.day == d }
                let on = day == d
                Button { withAnimation(Theme.spring) { day = d } } label: {
                    VStack(spacing: 4) {
                        Text(Labels.days[d].uppercased()).font(Theme.F.micro)
                        Circle().fill(has ? (on ? Theme.C.highlight : Theme.C.accent) : .clear).frame(width: 6, height: 6)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(on ? Theme.C.onAction : Theme.C.text1)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.C.action)
                                .matchedGeometryEffect(id: "day", in: dayPill)
                        } else {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.C.card)
                        }
                    }
                }
                .buttonStyle(PressableStyle())
            }
        }
        .sensoryFeedback(.selection, trigger: day)
    }

    private func summary(_ symbol: String, _ color: Color, _ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value).font(.system(.headline, design: .rounded, weight: .bold)).monospacedDigit().contentTransition(.numericText())
            Text(label).font(Theme.F.micro).foregroundStyle(Theme.C.text2).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .card(radius: Theme.R.tile)
    }
}

struct MealRow: View {
    @Environment(AppStore.self) private var store
    let meal: MealDTO
    var actions = false
    var onGuests: (() -> Void)?  // Wochenplan: „Gäste hinzufügen“ (15)
    @State private var rolling = false
    @State private var replacing = false  // S2 „ersetzen durch eigenes Rezept“ → S19

    var body: some View {
        let deals = meal.recipe.ingredients.filter { $0.offerId != nil }.count
        VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 14) {
            NavigationLink { RecipeDetailView(meal: meal) } label: {
                HStack(spacing: 14) {
                    Plate(url: mediaURL(meal.recipe.imageUrl), size: 72, seed: meal.recipe.title)
                        .rotationEffect(.degrees(rolling ? 360 : 0))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meal.recipe.title).font(.system(.subheadline, design: .rounded, weight: .bold)).lineLimit(2)
                            .foregroundStyle(Theme.C.text1)
                        Text("\(meal.recipe.prepMinutes) min · \(euro(meal.costCents))").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                        if deals > 0 { DealBadge(text: deals == 1 ? "1 Zutat im Angebot" : "\(deals) Zutaten im Angebot", style: .soft) }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(PressableStyle())
            if actions && meal.id != nil {
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                  GridRow {
                    small(meal.recipe.favorite ? "heart.fill" : "heart", on: meal.recipe.favorite,
                          label: meal.recipe.favorite ? "Aus Favoriten entfernen" : "Als Favorit merken") {
                        Task { _ = await store.toggleFavorite(meal.recipe.id, current: meal.recipe.favorite) }
                    }
                    .symbolEffect(.bounce, value: meal.recipe.favorite)
                    small("arrow.triangle.2.circlepath", on: false, label: "Durch eigenes Rezept ersetzen") { replacing = true }
                  }
                  GridRow {
                    small(meal.locked ? "lock.fill" : "lock.open", on: meal.locked, label: meal.locked ? "Lösen" : "Fixieren") {
                        Task { await store.setLocked(meal, !meal.locked) }
                    }
                    small("dice", on: false, label: "Neu würfeln") {
                        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false)) { rolling = true }
                        Task {
                            await store.reroll(meal)
                            withAnimation(Theme.spring) { rolling = false }
                        }
                    }
                    .disabled(meal.locked || rolling)
                    .opacity(meal.locked ? 0.35 : 1)
                  }
                }
            }
        }
        MealBadges(meal: meal, onGuests: actions && meal.id != nil ? onGuests : nil)
        }
        .padding(12)
        .card()
        .sheet(isPresented: $replacing) {
            PlanSlotSheet(entry: meal).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet)
        }
    }

    private func small(_ symbol: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? Theme.C.onAction : Theme.C.text1)
                .frame(width: 36, height: 36)
                .background(on ? Theme.C.action : Theme.C.surface, in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: on)
        .accessibilityLabel(label)
    }
}

/// S3 Rezeptdetail – Plan-Gericht oder gespeichertes Rezept (`meal.id == nil`, siehe `SavedRecipeView`).
struct RecipeDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let given: MealDTO
    @State private var swapped: MealDTO?  // gespeichertes Rezept nach „Ersatz finden“ (7)
    @State private var substituting: Int?  // Index der Zutat für „Ersatz finden“
    @State private var alarmFor: String?  // Zutat für „Preisalarm“ (40)
    @State private var showRating = false
    @State private var openOffer: OfferDTO?
    @State private var searchIngredient: IngredientDTO?
    @State private var servings: Int?
    @State private var person: Int?  // Mitglied für „Deine Portion“ (48), nil = ich
    @State private var done: Set<Int> = []
    @State private var spin = false
    @State private var cooking = Demo.screen == "cooking"
    @State private var rateAfterCooking = false
    @State private var shareCard = Demo.screen == "sharecard"
    @State private var info: RecipeDTO?  // GET /recipes/{id}: Bewertungen, Favorit, Nährwerte, falls im Plan noch null
    @State private var favorite: Bool?
    @State private var planIt = false
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var stepImages: [String]?  // nachgeladene Schritt-Bilder (9)
    @State private var imagesSettled = false  // Erzeugung fertig oder aus → leere Plätze ausblenden
    @Environment(\.openURL) private var openURL

    init(meal: MealDTO) { given = meal }

    /// Plan-Gericht immer im aktuellen Stand des Plans (Ersatz, Gäste, Würfeln ändern es).
    private var meal: MealDTO { swapped ?? given.id.flatMap { id in store.plan?.entries.first { e in e.id == id } } ?? given }
    private var recipe: RecipeDTO { meal.recipe }
    private var images: [String] { stepImages ?? info?.stepImages ?? recipe.stepImages ?? [] }
    /// Bildfläche für Schritt i: Bild da, oder es wird noch erzeugt (Schimmer).
    private func showsImage(_ i: Int) -> Bool {
        i < images.count && (!images[i].isEmpty || (store.stepImagesOn && !imagesSettled))
    }
    private var details: RecipeDTO { info ?? recipe }
    private var nutrition: NutritionDTO? { recipe.nutrition ?? info?.nutrition }
    private var composition: [CompositionItem]? { recipe.composition ?? info?.composition }
    private var isFavorite: Bool { favorite ?? details.favorite }

    var body: some View {
        let base = meal.basePortions  // Rezeptmengen gelten für so viele Portionen
        let factor = (servings.map { Double($0) / base } ?? 1) * meal.scale  // Stepper skaliert das ganze Rezept; scale = eingesetztes Rezept
        let who = store.profiles.first { $0.memberId == (person ?? store.profile?.memberId) } ?? store.profile
        // Anteil der gewählten Person; ohne Esser-Liste (gespeichertes Rezept, alter Plan) der Portionsfaktor aus dem Profil
        let mine: Double? = meal.portions.isEmpty ? (who?.portionFactor ?? 1) : meal.portions.first { $0.memberId == who?.memberId }?.factor
        ZStack(alignment: .bottom) {
            Theme.C.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                        Spacer()
                        HeartButton(on: isFavorite) { toggleFavorite() }
                        if recipe.source != "ai" {  // eigene und importierte Rezepte
                            Menu {
                                Button("Bearbeiten", systemImage: "pencil") { editing = true }
                                Button("Löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
                            } label: { roundLabel("ellipsis") }
                            .accessibilityLabel("Rezept bearbeiten oder löschen")
                        }
                        Menu {
                            Button("Als Bild teilen", systemImage: "photo") { shareCard = true }
                            Button("Als Link teilen (kommt bald)", systemImage: "link") {}.disabled(true)  // Feature 56
                        } label: { roundLabel("square.and.arrow.up") }
                        .accessibilityLabel("Rezept teilen")
                    }
                    ZStack {
                        CornerFrame().stroke(Theme.C.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round)).frame(width: 276, height: 276)
                            .scaleEffect(spin ? 1 : 1.12).opacity(spin ? 1 : 0)
                        Plate(url: mediaURL(recipe.imageUrl), size: 236, seed: recipe.title)
                            .rotationEffect(.degrees(spin ? 0 : -40))
                    }
                    .frame(maxWidth: .infinity)
                    .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) { spin = true } }
                    VStack(alignment: .leading, spacing: 4) {
                        let words = recipe.title.split(separator: " ")
                        (Text(words.prefix(1).joined()).font(.system(.title, weight: .bold))
                            + Text(" " + words.dropFirst().joined(separator: " ")).font(.system(.title, weight: .regular)).foregroundStyle(Theme.C.text2))
                        if !recipe.cuisine.isEmpty { Text(recipe.cuisine).font(Theme.F.caption).foregroundStyle(Theme.C.text2) }
                        if let avg = details.avgStars {
                            HStack(spacing: 6) {
                                StarsView(value: avg)
                                Text("\(num(avg, 1...1)) · \(details.ratings?.count ?? 0) Bewertungen")
                                    .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                            }
                        }
                    }
                    if ["instagram", "web"].contains(recipe.source) { sourceRow }
                    // Infozeile mit Trennstrichen (Vorlage „Grilled Chicken Breast“)
                    HStack(spacing: 0) {
                        infoCell("clock", "\(recipe.prepMinutes) min")
                        Divider().frame(height: 22)
                        infoCell("eurosign.circle", "\(euro(Int(Double(meal.costCents) * (who == nil ? 1 : mine ?? 1) / base))) \(who == nil || mine == nil ? "p. P." : "Portion")")
                        Divider().frame(height: 22)
                        infoCell("tag", "\(recipe.ingredients.filter { $0.offerId != nil }.count) im Angebot")
                    }
                    .padding(.vertical, 12)
                    .card(radius: Theme.R.tile)
                    if !recipe.description.isEmpty {
                        Text(recipe.description).font(Theme.F.body).foregroundStyle(Theme.C.text2)
                    }
                    if meal.id == nil {  // gespeichertes Rezept → Slot im Wochenplan ersetzen (3)
                        Button { planIt = true } label: { Label("Diese Woche einplanen", systemImage: "calendar.badge.plus") }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    if let who { portionCard(who, mine: mine, base: base) }
                    nutritionTiles(mine ?? 1)  // pro Portion der gewählten Person (2)
                    if composition.map({ c in !c.isEmpty }) ?? true {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Zusammensetzung").font(Theme.F.headline)
                            Text("Anteile der Zutaten am Gewicht").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                            if let composition {
                                ShareBloom(items: composition, photo: mediaURL(recipe.imageUrl), seed: recipe.title)
                            } else {
                                SkeletonCard(height: 300).padding(.top, 8)
                            }
                        }
                        .padding(16).card()
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Zutaten").font(Theme.F.headline)
                            Spacer()
                            Stepper(value: Binding(get: { servings ?? max(Int(base.rounded()), 1) }, set: { servings = $0 }), in: 1...12) {
                                Text("\(num(servings.map { Double($0) } ?? base, 0...2)) Portionen")
                                    .font(Theme.F.callout).contentTransition(.numericText())
                            }
                            .fixedSize()
                        }
                        .padding(.bottom, 6)
                        ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { index, ing in
                            let offer = store.offers.first { $0.id == ing.offerId }
                            let rest = meal.rests?.first { r in r.name.localizedCaseInsensitiveCompare(ing.name) == .orderedSame }
                            // Feature 1: Zutat antippen → Angebot (oder passende Angebote)
                            Button { if let offer { openOffer = offer } else { searchIngredient = ing } } label: {
                            HStack(spacing: 12) {
                                Text(offer.map { Theme.hue(category: $0.category).emoji } ?? (ing.inPantry == true ? "🧂" : "🥄")).font(.system(size: 22))
                                    .frame(width: 40, height: 40).background(Theme.C.surface, in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ing.name).font(.system(.body, weight: .semibold))
                                    HStack(spacing: 6) {
                                        if let offer {
                                            DealBadge(text: offer.discount.map { "−\($0) %" } ?? "Angebot")
                                            StoreChip(chain: offer.chain)
                                        }
                                        if ing.inPantry == true { DealBadge(text: "im Vorrat", style: .ok) }
                                        if ing.estimated == true { DealBadge(text: "Menge geschätzt", style: .soft) }
                                        if let rest, Labels.days.indices.contains(rest.fromDay) {
                                            DealBadge(text: "♻︎ Rest von \(Labels.days[rest.fromDay])", style: .ok)
                                        }
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(qty(ing.amount * factor, ing.unit))
                                        .monospacedDigit().foregroundStyle(Theme.C.text2).contentTransition(.numericText())
                                    if let who, let mine {
                                        let own = qty(ing.amount * mine * meal.scale / base, ing.unit)
                                        Text("\(who.emoji) \(own)")
                                            .font(Theme.F.micro).monospacedDigit().foregroundStyle(Theme.C.accentDeep)
                                            .contentTransition(.numericText())
                                            .accessibilityLabel("Portion \(who.name): \(own)")
                                    }
                                }
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.C.text3)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle())
                            .contextMenu {  // lange drücken → Ersatz (7)
                                Button("Ersatz finden", systemImage: "arrow.left.arrow.right") { substituting = index }
                                Button("Preisalarm", systemImage: "bell.badge") { alarmFor = ing.name }
                            }
                            .accessibilityAction(named: "Ersatz finden") { substituting = index }
                            .accessibilityAction(named: "Preisalarm") { alarmFor = ing.name }
                        }
                    }
                    .padding(16).card()
                    .animation(Theme.spring, value: servings)
                    .animation(Theme.spring, value: person)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Zubereitung").font(Theme.F.headline)
                        ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, step in
                            let isDone = done.contains(i)
                            if showsImage(i) { StepImage(path: images[i]).opacity(isDone ? 0.5 : 1).transition(.opacity) }
                            Button {
                                withAnimation(Theme.spring) { if done.remove(i) == nil { done.insert(i) } }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    ZStack {
                                        Circle().fill(isDone ? Theme.C.accent : Theme.C.action)
                                        if isDone { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                                        else { Text("\(i + 1)").font(.system(.footnote, design: .rounded, weight: .bold)) }
                                    }
                                    .foregroundStyle(isDone ? .white : Theme.C.onAction).frame(width: 28, height: 28)
                                    Text(step).font(Theme.F.body).strikethrough(isDone).foregroundStyle(isDone ? Theme.C.text3 : Theme.C.text1)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)
                            .sensoryFeedback(.success, trigger: isDone)
                        }
                    }
                    .padding(16).card()
                    .animation(Theme.spring, value: images)
                    if let ratings = details.ratings, !ratings.isEmpty { ratingsCard(ratings) }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 16)
            }
            .ctaBar {
            VStack(spacing: 10) {
                // Kochmodus S18 (Feature 4)
                Button { cooking = true } label: { Label("Kochen starten", systemImage: "play.fill") }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.C.accent))
                HStack(spacing: 10) {
                    Button {
                        let offers = recipe.ingredients.compactMap { ing in store.offers.first { $0.id == ing.offerId } }
                        withAnimation(Theme.spring) { offers.forEach(store.addToList) }
                        if offers.isEmpty { store.flash("Keine Angebotszutaten") }
                    } label: { Text("Zur Liste") }
                    .buttonStyle(SecondaryButtonStyle())
                    Button { showRating = true } label: { Text("Gekocht ★") }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: store.recipesVersion) { await loadInfo() }
        .task(id: recipe.id) { await pollStepImages() }
        .fullScreenCover(isPresented: $cooking, onDismiss: {
            if rateAfterCooking { rateAfterCooking = false; showRating = true }  // Abschluss → Bewertung + Vorrat (S8)
        }) {
            CookingView(meal: cookMeal, imagesLoading: store.stepImagesOn && !imagesSettled, factor: factor,
                        person: who.flatMap { w in mine.map { m in (w.emoji, m * meal.scale / base) } },
                        onFinish: {
                            rateAfterCooking = true
                            cooking = false
                        },
                        onSubstitute: { m in if let m { swapped = m } })
        }
        .sheet(isPresented: $shareCard) { ShareCardSheet(meal: meal).presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
        .sheet(isPresented: $showRating) { RatingSheet(meal: meal).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet) }
        .sheet(isPresented: $planIt) { PlanSlotSheet(recipeId: recipe.id, title: recipe.title).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet) }
        .sheet(isPresented: $editing) { RecipeFormSheet(editing: details).presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
        .confirmationDialog("Rezept löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                let id = recipe.id
                dismiss()
                Task { await store.deleteRecipe(id) }
            }
        } message: {
            Text("„\(recipe.title)“ verschwindet aus Meine Rezepte. Steht es im Wochenplan, bleibt es dort.")
        }
        .navigationDestination(item: $openOffer) { OfferDetailView(offer: $0) }
        .sheet(isPresented: Binding(get: { alarmFor != nil }, set: { on in if !on { alarmFor = nil } })) {
            WatchSheet(ingredient: alarmFor ?? "").presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet)
        }
        .sheet(item: $searchIngredient) { IngredientOffersSheet(ingredient: $0).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet) }
        .sheet(isPresented: Binding(get: { substituting != nil }, set: { on in if !on { substituting = nil } })) {
            if let i = substituting {
                SubstituteSheet(meal: meal, index: i) { m in if let m { swapped = m } }
                    .presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet)
            }
        }
    }

    /// Plan-Gerichte holen Bewertungen/Favorit nach; fehlen Nährwerte (Berechnung läuft), einmal nach ~3 s neu laden.
    private func loadInfo() async {
        if recipe.ratings == nil { info = (try? await store.recipe(recipe.id)) ?? info }
        guard nutrition == nil || composition == nil else { return }
        try? await Task.sleep(for: .seconds(3))
        if let again = try? await store.recipe(recipe.id) { withAnimation(Theme.spring) { info = again } }
    }

    /// Schritt-Bilder: anfordern (startet die Erzeugung) und mit wachsendem Abstand nachfragen, solange sie entstehen.
    private func pollStepImages() async {
        guard !store.demo else { return }  // Demo: leere Plätze schimmern weiter
        guard store.stepImagesOn, !recipe.steps.isEmpty else { imagesSettled = true; return }
        var wait = 2.0
        while !Task.isCancelled {
            if images.count == recipe.steps.count && !images.contains("") { break }
            guard let out = try? await store.stepImages(recipe.id) else { break }  // 422: aus oder nicht eingerichtet
            withAnimation(Theme.spring) { stepImages = out.stepImages }
            guard out.pending, out.stepImages.contains("") else { break }
            try? await Task.sleep(for: .seconds(wait))
            wait = min(wait * 2, 30)
        }
        imagesSettled = true
    }

    /// Kochmodus bekommt die nachgeladenen Schritt-Bilder.
    private var cookMeal: MealDTO {
        var m = meal
        m.recipe.stepImages = images
        return m
    }

    private func toggleFavorite() {
        let new = !isFavorite
        withAnimation(Theme.spring) { favorite = new }
        Task { favorite = await store.toggleFavorite(recipe.id, current: !new) }
    }
}

extension RecipeDetailView {
    /// Quelle-Chip „Instagram · @autor“ + „▶︎ Original-Reel“ (öffnet Instagram-App bzw. Safari, 5/9).
    fileprivate var sourceRow: some View {
        let insta = recipe.source == "instagram"
        let host = URL(string: recipe.sourceUrl)?.host()?.replacingOccurrences(of: "www.", with: "") ?? ""
        return HStack(spacing: 8) {
            Label("\(insta ? "Instagram" : "Web") · \(recipe.sourceAuthor.isEmpty ? host : recipe.sourceAuthor)",
                  systemImage: insta ? "camera.fill" : "globe")
                .font(Theme.F.micro).foregroundStyle(Theme.C.text2).lineLimit(1)
                .padding(.horizontal, 10).frame(height: 28).background(Theme.C.surface, in: Capsule())
            Spacer(minLength: 0)
            if insta, let url = URL(string: recipe.sourceUrl), !recipe.sourceUrl.isEmpty {
                Button { openURL(url) } label: {
                    Label("Original-Reel", systemImage: "play.fill")
                        .font(Theme.F.callout).foregroundStyle(Theme.C.onAction)
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(Theme.C.action, in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    fileprivate func infoCell(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.system(.footnote, weight: .semibold)).foregroundStyle(Theme.C.text1)
            .frame(maxWidth: .infinity)
    }

    fileprivate func roundLabel(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
            .frame(width: 44, height: 44)
            .foregroundStyle(Theme.C.text1)
            .background(Theme.C.card, in: Circle())
            .overlay(Circle().strokeBorder(Theme.C.line, lineWidth: 0.5))
    }

    /// 4 Kacheln kcal, Protein, KH, Fett; Schimmer, solange die Berechnung läuft.
    fileprivate func nutritionTiles(_ k: Double) -> some View {
        HStack(spacing: 8) {
            if let n = nutrition {
                NutrientTile(nutrient: .kcal, value: "\(Int((n.kcal * k).rounded()))")
                NutrientTile(nutrient: .protein, value: "\(Int((n.protein * k).rounded())) g")
                NutrientTile(nutrient: .carbs, value: "\(Int((n.carbs * k).rounded())) g")
                NutrientTile(nutrient: .fat, value: "\(Int((n.fat * k).rounded())) g")
            } else {
                ForEach(0..<4, id: \.self) { _ in SkeletonCard(height: 92) }
            }
        }
        .animation(Theme.spring, value: k)
    }

    fileprivate func ratingsCard(_ ratings: [RatingDTO]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bewertungen").font(Theme.F.headline)
            ForEach(ratings) { r in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(r.memberName).font(.system(.subheadline, weight: .semibold))
                        StarsView(value: Double(r.stars))
                        Spacer()
                        Text(shortDate(r.cookedAt)).font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                    }
                    Text("Wieder kochen: \(Labels.again.first { $0.0 == r.again }?.1 ?? r.again)")
                        .font(Theme.F.micro).foregroundStyle(r.again == "nie" ? Theme.C.danger : Theme.C.text2)
                    if !r.note.isEmpty { Text(r.note).font(Theme.F.body) }
                }
                .accessibilityElement(children: .combine)
                if r.id != ratings.last?.id { Divider() }
            }
        }
        .padding(16).card()
    }

    /// „Für: 🧑‍🍳 Jona ▾“ + „Deine Portion: 520 g · 2,10 €“ (48).
    fileprivate func portionCard(_ who: ProfileDTO, mine: Double?, base: Double) -> some View {
        let isMe = who.memberId == store.profile?.memberId
        let grams = recipe.ingredients.filter { ["g", "ml"].contains($0.unit) }.map(\.amount).reduce(0, +) * (mine ?? 0) * meal.scale / base
        let parts = [grams > 0 ? "\(Int(grams.rounded())) g" : nil, mine.map { euro(Int(Double(meal.costCents) * $0 / base)) },
                     mine.map { "×\(num($0, 0...2)) von \(num(base, 0...2)) Portionen" }].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PersonPicker(person: $person)
                Spacer()
            }
            if mine == nil {
                Text("\(who.name) isst bei diesem Gericht nicht mit.").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            } else {
                (Text(isMe ? "Deine Portion: " : "Portion \(who.name): ").foregroundStyle(Theme.C.text2)
                    + Text(parts.joined(separator: " · ")).foregroundStyle(Theme.C.text1))
                    .font(Theme.F.callout)
            }
        }
        .padding(14)
        .card(radius: Theme.R.tile)
    }
}

/// Menge mit Einheit, z. B. „400 g“, „1 Stück“ (Rezept, Kochmodus, Bildkarte).
func qty(_ amount: Double, _ unit: String) -> String {
    "\(num(amount)) \(Labels.unit(unit))"
}

/// Eckrahmen wie Referenz 02.
struct CornerFrame: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let l: CGFloat = 42
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.minX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.maxY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - l))
        return p
    }
}

/// S8 Bewertung: Sterne, „Wieder kochen?“, Notiz → POST /recipes/{id}/rate (wer/wann setzt das Backend), dann Vorrat abziehen.
struct RatingSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let meal: MealDTO
    @State private var rating = 0
    @State private var again = "bald"
    @State private var note = ""
    @State private var saving = false
    @State private var consumed: [PantryDTO]?  // nach „Speichern“: vom Vorrat abgezogene Einträge (editierbar)
    @State private var rests: [RestRow]?  // danach: tatsächliche Reste bestätigen (19)
    @State private var nextRests: [RestRow] = []
    var demoRests = false  // Demo „leftovers“: direkt die Reste-Abfrage

    var body: some View {
        Group {
            if let rests {
                RestsConfirmView(rows: rests) { dismiss() }
            } else if let consumed {
                consumedList(consumed)
            } else {
                ratingForm
            }
        }
        .onAppear { if demoRests && rests == nil { rests = Demo.entryLeftovers.map(RestRow.init) } }
    }

    /// Rückfrage-Liste: was abgezogen wurde, Mengen hier korrigierbar.
    private func consumedList(_ items: [PantryDTO]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vom Vorrat abgezogen").font(Theme.F.title)
            Text("Stimmt etwas nicht? Menge hier korrigieren.").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(items) { c in
                        if let p = store.pantry.first(where: { p in p.id == c.id }) {
                            PantryRow(item: p)
                        } else {
                            HStack {
                                Text(c.name).font(.system(.body, weight: .semibold))
                                Spacer()
                                Text("aufgebraucht").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                            }
                            .padding(14).card(radius: Theme.R.tile)
                        }
                    }
                }
            }
            Button(nextRests.isEmpty ? "Fertig" : "Weiter") {
                if nextRests.isEmpty { dismiss() } else { withAnimation(Theme.spring) { rests = nextRests } }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(Theme.pagePadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.C.bg)
        .transition(.opacity)
    }

    private var ratingForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Plate(url: mediaURL(meal.recipe.imageUrl), size: 64, seed: meal.recipe.title)
                Text(meal.recipe.title).font(Theme.F.headline)
            }
            Text("Wie war's?").font(Theme.F.title)
            RatingStars(rating: $rating).frame(maxWidth: .infinity)
            Picker("Wieder kochen?", selection: $again) {
                ForEach(Labels.again, id: \.0) { a in Text(a.1).tag(a.0) }
            }
            .pickerStyle(.segmented)
            TextField("Notiz, z.B. mehr Chili …", text: $note).padding(14)
                .background(Theme.C.card, in: RoundedRectangle(cornerRadius: Theme.R.tile))
            Button(saving ? "Speichere …" : "Speichern") {
                saving = true
                Task {
                    defer { saving = false }
                    guard await store.rate(meal.recipe.id, stars: rating, again: again, note: note) else { return }
                    store.flash(rating >= 4 ? "Gespeichert – kommt öfter 🎉" : "Danke für deine Bewertung")
                    let changed = await store.consume(meal)
                    nextRests = await store.entryLeftovers(meal).map(RestRow.init)  // erwartete Reste angebrochener Packungen
                    if changed.isEmpty {
                        if nextRests.isEmpty { dismiss() } else { withAnimation(Theme.spring) { rests = nextRests } }
                        return
                    }
                    store.flash("Vorrat aktualisiert")
                    withAnimation(Theme.spring) { consumed = changed }
                }
            }
            .buttonStyle(PrimaryButtonStyle()).disabled(rating == 0 || saving).opacity(rating == 0 ? 0.5 : 1)
        }
        .padding(Theme.pagePadding)
        .background(Theme.C.bg)
    }
}

/// S7 Plan-Generator: Einstellungen im Überblick, dann animierter Lade-Zustand.
struct PlanGeneratorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var phase = 0
    @State private var started = Demo.screen == "generating"
    @State private var spin = false
    @State private var prefs = Prefs()
    @State private var wishes = ""
    @State private var saveAsDefault = false
    @State private var info: GeneratorDTO?  // KW + „Diese Woche im Angebot“ (17)
    @State private var specials: [SpecialDTO] = []  // Vorlagen (25)
    @State private var special: String?
    @State private var guests: [String: Int] = [:]  // „+ Gäste“ (15)
    @State private var guestEuro: Double?
    @State private var nextWeek = Demo.screen == "singlestore"  // „Plan für nächste Woche“ (30)
    @State private var singleStore: String? = Demo.screen == "singlestore" ? "lidl" : nil  // „Nur ein Laden“ (41)

    private let steps = [("Angebote auswerten", "🏷️"), ("Lieblingsrezepte prüfen", "❤️"),
                         ("Gerichte planen", "👩‍🍳"), ("Preise rechnen", "🧮")]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if started {
                VStack(spacing: 18) {
                    ZStack {
                        Circle().stroke(Theme.C.accentSoft, lineWidth: 6).frame(width: 190, height: 190)
                        Circle().trim(from: 0, to: 0.25).stroke(Theme.C.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .frame(width: 190, height: 190).rotationEffect(.degrees(spin ? 360 : 0))
                        Plate(url: nil, size: 150, seed: steps[min(phase, steps.count - 1)].0).rotationEffect(.degrees(spin ? -360 : 0))
                    }
                    .onAppear { withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) { spin = true } }
                    Text(store.error == nil ? "Dein Plan entsteht …" : "Das hat nicht geklappt").font(Theme.F.title)
                    Text(store.error ?? "Dauert meist unter einer Minute").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                        .multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                            HStack(spacing: 12) {
                                Text(step.1).font(.system(size: 20)).frame(width: 36, height: 36)
                                    .background(i <= phase ? Theme.C.accentSoft : Theme.C.surface, in: Circle())
                                Text(step.0).font(Theme.F.callout).foregroundStyle(i <= phase ? Theme.C.text1 : Theme.C.text3)
                                Spacer()
                                Image(systemName: i < phase ? "checkmark.circle.fill" : i == phase ? "ellipsis.circle" : "circle")
                                    .foregroundStyle(i < phase ? Theme.C.accent : Theme.C.text3)
                                    .contentTransition(.symbolEffect(.replace))
                                    .symbolEffect(.pulse, isActive: i == phase)
                            }
                        }
                    }
                    .padding(16).card()
                    if store.error != nil {
                        Button("Erneut versuchen") { start() }.buttonStyle(PrimaryButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Wochenplan erstellen").font(Theme.F.title)
                        Text("\(weekLabel)Passe an, was du diese Woche essen möchtest – gilt nur für diesen Plan.")
                            .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                            .contentTransition(.numericText())
                        weekAndStoreCard.appear()
                        if let top = info?.topOffers, !top.isEmpty { TopOffersHint(offers: top).appear() }
                        if !specials.isEmpty { SpecialPicker(specials: specials, selected: $special).appear(delay: 0.04) }
                        VStack(alignment: .leading, spacing: 8) {
                            Label { Text("Wünsche").font(Theme.F.headline) } icon: { Text("💭") }
                            TextField("z.B. mehr Fisch, ein Gericht mit Kürbis", text: $wishes, axis: .vertical)
                                .lineLimit(1...3)
                                .padding(12).background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.chip))
                        }
                        .padding(16).card()
                        GuestPlanner(guests: $guests, extraEuro: $guestEuro, days: prefs.planDays.sorted(), meals: prefs.mealTypeList)
                        PreferencesForm(prefs: $prefs, showDiet: false)
                        Toggle("Als Standard speichern", isOn: $saveAsDefault).tint(Theme.C.accent).padding(16).card()
                    }
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.immediately)
                .ctaBar(bottom: 0, horizontal: 0) {
                    Button { start() } label: { Label("Plan erstellen", systemImage: "sparkles") }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(prefs.mealTypes.isEmpty || prefs.planDays.isEmpty)
                }
            }
        }
        .padding(Theme.pagePadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationBackground(Theme.C.bg)
        .presentationCornerRadius(Theme.R.sheet)
        .onAppear { if let h = store.household { prefs = Prefs(h) } }
        .task {
            if let s = store.generatorSpecial { special = s; store.generatorSpecial = nil }  // Start-Banner (25)
            info = await store.generatorInfo()
            specials = await store.specials()?.specials ?? []
            if store.demo && special == nil { special = info?.banner?.key }
        }
    }

    /// „KW 46 · “ – mit „Plan für nächste Woche“ die KW des nächsten Montags.
    private var weekLabel: String {
        let cal = Calendar(identifier: .iso8601)
        let week = nextWeek ? cal.component(.weekOfYear, from: cal.date(byAdding: .weekOfYear, value: 1, to: .now) ?? .now) : info?.week
        return week.map { w in "KW \(w) · " } ?? ""
    }

    /// „Plan für nächste Woche“ (30) und „Nur ein Laden“ mit Logo-Auswahl (41).
    private var weekAndStoreCard: some View {
        let chains = Labels.chains.map(\.key).filter { c in store.household?.stores.contains { s in s.chain == c && s.enabled } ?? false }
        let preview = store.nextOffers.count
        return VStack(alignment: .leading, spacing: 10) {
            Label { Text("Woche & Läden").font(Theme.F.headline) } icon: { Text("🛒") }
            Toggle("Plan für nächste Woche", isOn: $nextWeek.animation(Theme.spring))
                .font(Theme.F.callout)
                .disabled(preview == 0 && !nextWeek)
            Text(preview == 0 ? "Noch keine Prospekte für nächste Woche – meist ab Donnerstag oder Freitag."
                              : "Nutzt die Vorschau-Angebote (\(preview)) der nächsten Woche.")
                .font(Theme.F.micro).foregroundStyle(Theme.C.text2)
            Divider()
            Toggle("Nur ein Laden", isOn: Binding(get: { singleStore != nil }, set: { on in
                withAnimation(Theme.spring) { singleStore = on ? chains.first : nil }
            }))
            .font(Theme.F.callout)
            .disabled(chains.count < 2 && singleStore == nil)
            if let picked = singleStore {
                HStack(spacing: 10) {
                    ForEach(chains, id: \.self) { c in
                        let on = c == picked
                        Button { withAnimation(Theme.spring) { singleStore = c } } label: {
                            StoreLogo(chain: c, size: 44)
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Theme.C.accent : .clear, lineWidth: 3))
                                .scaleEffect(on ? 1.08 : 1)
                                .opacity(on ? 1 : 0.55)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel(Labels.chain(c))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .sensoryFeedback(.selection, trigger: picked)
                Text("Einkauf komplett bei \(Labels.chain(picked)) – Zutaten ohne Angebot zum Normalpreis von \(Labels.chain(picked)).")
                    .font(Theme.F.micro).foregroundStyle(Theme.C.text2).fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .tint(Theme.C.accent)
        .padding(16)
        .card()
    }

    private func start() {
        withAnimation(Theme.spring) { started = true; phase = 0 }
        guard !store.demo else { return }
        Task {
            var options = prefs.options(wishes: wishes, saveAsDefault: saveAsDefault)
            let slots = GuestPlanner.slots(guests, days: prefs.planDays.sorted(), meals: prefs.mealTypeList)
            options.guests = slots.isEmpty ? nil : slots
            options.guestBudgetCents = slots.isEmpty ? nil : guestEuro.map { e in Int(e) * 100 }
            options.special = special
            options.nextWeek = nextWeek
            options.singleStore = singleStore
            let body = options
            async let done: Void = store.generatePlan(body)
            for i in 1..<steps.count {  // Fortschritt ist nur Anzeige, das Backend arbeitet in einem Aufruf
                try? await Task.sleep(for: .seconds(8))
                if store.generating { withAnimation(Theme.spring) { phase = i } }
            }
            await done
            if store.error == nil {
                withAnimation(Theme.spring) { phase = steps.count }
                store.flash("Dein Wochenplan ist fertig 🎉")
                dismiss()
            }
        }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } }
}
