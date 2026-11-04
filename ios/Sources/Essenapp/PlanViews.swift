import SwiftUI

/// Tab „Rezepte“: S2 Wochenplan + S12 Meine Rezepte.
struct RecipesTab: View {
    @Environment(AppStore.self) private var store
    @Binding var planWeek: Bool  // Woche per Swipe (20)
    @State private var mine: Bool  // v8: eigener Tab „Woche“ (Plan) und „Rezepte“ (S12)
    @State private var filter = "alle"
    @State private var person: Int?  // „Für:“ in der Tagesansicht (48), nil = ich
    @State private var day = Demo.screen != nil ? 1 : (Calendar(identifier: .iso8601).component(.weekday, from: .now) + 5) % 7
    @State private var noMood = false  // „Keine Lust“ (16)
    @State private var guestsFor: MealDTO? = Demo.screen == "guests" ? Demo.plan.entries[3] : nil  // „Gäste hinzufügen“ (15)
    @Namespace private var dayPill

    init(planWeek: Binding<Bool>, week: Bool = false) {
        _planWeek = planWeek
        _mine = State(initialValue: !week)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if mine {
                    MyRecipesList(filter: $filter) { withAnimation(Theme.spring) { mine = false } }
                } else if let plan = store.plan {
                    HStack(alignment: .top) {
                        DisplayHeader(line1: "Woche", line2: "KW \(plan.week.suffix(2))")
                        HStack(spacing: 8) {
                            ShareButton()
                            RoundIconButton(systemName: "dice", dark: true, label: "Woche planen") { planWeek = true }
                        }
                        .padding(.top, 4)
                    }
                    budgetLine(plan)
                    dayPicker(plan)
                    let meals = plan.entries.filter { $0.day == day }
                        .sorted { a, b in (Labels.slotOrder.firstIndex(of: a.mealType) ?? 9) < (Labels.slotOrder.firstIndex(of: b.mealType) ?? 9) }
                    if meals.isEmpty {
                        EmptyState(emoji: "😴", title: "Nichts geplant", text: "Für \(Labels.dayNames[day]) ist kein Gericht geplant.")
                    }
                    VStack(spacing: -18) {  // Karten überlappen wie Sprechblasen
                        ForEach(Array(meals.enumerated()), id: \.element) { i, meal in
                            DayCard(meal: meal, color: DayCard.color(day: day, index: i, mealType: meal.mealType)) { guestsFor = meal }
                                .zIndex(Double(i))
                                .appear(delay: Double(i) * 0.06)
                        }
                    }
                    .id(day)
                    // Ab hier noch nicht gemockt (redesign-v3.md 7, Gruppe A)
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
                    if let l = plan.leftovers, l.planned > 0 || !l.left.isEmpty { LeftoversCard(leftovers: l) }  // Reste (19)
                    if day == store.today && !meals.isEmpty {
                        Button { noMood = true } label: { Text("😮‍💨 Keine Lust") }.buttonStyle(SecondaryButtonStyle())
                    }
                    DayNutritionCard(day: day, person: $person)  // Tageswerte unten (S2)
                } else {
                    EmptyState(emoji: "📅", title: "Noch kein Wochenplan", text: "Erstelle deinen ersten Plan.",
                               buttonTitle: "Woche planen") { planWeek = true }
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

    /// „38,20 € von 60 €“ + Ersparnis-Pille, Balken (Tinte auf `surface`).
    private func budgetLine(_ plan: PlanDTO) -> some View {
        let budget = store.household?.budgetFoodWeekCents ?? 0
        return VStack(spacing: 10) {
            HStack {
                (Text(euro(plan.totalCents)).foregroundStyle(Theme.C.text1)
                    + Text(" von \(euro(budget))").font(.system(.headline, weight: .semibold)).foregroundStyle(Theme.C.text2))
                    .font(.system(.headline, weight: .heavy)).monospacedDigit()
                Spacer()
                if plan.savedCents > 0 {
                    Text("\(euro(plan.savedCents)) gespart").font(.system(.caption, weight: .bold)).foregroundStyle(Theme.C.onLime)
                        .padding(.horizontal, 10).frame(height: 26).background(Theme.C.lime, in: Capsule())
                }
            }
            GeometryReader { g in
                Capsule().fill(Theme.C.surface)
                Capsule().fill(plan.totalCents > budget ? Theme.C.danger : Theme.C.action)
                    .frame(width: g.size.width * min(Double(plan.totalCents) / Double(max(budget, 1)), 1))
            }
            .frame(height: 12)
        }
        .accessibilityElement(children: .combine)
    }

    /// Tagesleiste v3: 7 Pillen 44×58, Punkt in der Tagesfarbe, aktiv schwarz (gleitet).
    private func dayPicker(_ plan: PlanDTO) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { d in
                let has = plan.entries.contains { $0.day == d }
                let on = day == d
                Button { withAnimation(Theme.spring) { day = d } } label: {
                    VStack(spacing: 5) {
                        Text(Labels.days[d]).font(.system(.footnote, weight: .heavy))
                        Circle().fill(has ? Theme.C.day[d] : .clear).frame(width: 8, height: 8)
                    }
                    .frame(width: 44, height: 58)
                    .foregroundStyle(on ? Theme.C.onAction : Theme.C.text1)
                    .background {
                        if on {
                            Capsule().fill(Theme.C.action).matchedGeometryEffect(id: "day", in: dayPill)
                        } else {
                            Capsule().fill(Theme.C.card).overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: 1))
                        }
                    }
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(Labels.dayNames[d])
                .accessibilityAddTraits(on ? .isSelected : [])
                if d < 6 { Spacer(minLength: 0) }
            }
        }
        .padding(.vertical, 2)
        .sensoryFeedback(.selection, trigger: day)
    }
}

/// Gericht als Zeile (Suche auf Start).
struct MealRow: View {
    let meal: MealDTO

    var body: some View {
        HStack(spacing: 14) {
            Plate(url: mediaURL(meal.recipe.imageUrl), size: 56, seed: meal.recipe.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.recipe.title).font(.system(.headline, weight: .bold)).lineLimit(2).foregroundStyle(Theme.C.text1)
                Text("\(meal.recipe.prepMinutes) min · \(euro(meal.costCents))").font(.footnote).foregroundStyle(Theme.C.text2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .card(radius: Theme.R.tile)
    }
}

/// `DayCard` (S2): Pastell-Karte, Teller 84 links, Meta, Name in Fraunces, Info, Aktionen; Zähler = Zutaten im Angebot.
struct DayCard: View {
    @Environment(AppStore.self) private var store
    let meal: MealDTO
    let color: Color
    var onGuests: (() -> Void)?  // „Gäste hinzufügen“ (15)
    @State private var rolling = false
    @State private var replacing = false  // „ersetzen durch eigenes Rezept“ → S19
    @State private var open = false
    @State private var choosing = false  // Würfel → Richtung wählen (19.3)

    /// Karten eines Tages: Tagesfarbe, dann die Farben der Folgetage; Dessert/Snack weiß.
    static func color(day: Int, index: Int, mealType: String) -> Color {
        ["dessert", "snack"].contains(mealType) ? Theme.C.card : Theme.C.day[(day + index) % 7]
    }

    private var meta: String {
        let slot = (meal.mealType == "lunchbox" ? "🥡 " : "") + Labels.meal(meal.mealType)
        if meal.mealType == "lunchbox" {
            let names = store.profiles.filter { p in meal.portions.contains { $0.memberId == p.memberId } }.map(\.name)
            return names.isEmpty ? slot : "\(slot) · \(names.joined(separator: ", "))"
        }
        return "\(slot) · \(meal.recipe.prepMinutes) min"
    }

    private var info: String {
        var parts = [euro(meal.costCents / max(Int(meal.basePortions), 1))]
        if meal.mealType == "lunchbox" { parts.append("\(meal.recipe.prepMinutes) min") }
        if let kcal = meal.recipe.nutrition?.kcal { parts.append("\(Int(kcal.rounded())) kcal") }
        let rests = (meal.rests ?? []).map(\.fromDay).filter { Labels.days.indices.contains($0) }.uniqued()
        parts += rests.map { "♻︎ Rest von \(Labels.days[$0])" }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let deals = meal.recipe.ingredients.filter { $0.offerId != nil }.count
        let white = color == Theme.C.card
        VStack(alignment: .leading, spacing: 0) {
                Text(meta.uppercased()).font(.system(.caption, weight: .heavy)).tracking(0.7).opacity(0.65)
                Text(meal.recipe.title).font(Theme.F.cardTitle()).tracking(-0.5).lineLimit(3)
                    .multilineTextAlignment(.leading).padding(.top, 4).padding(.bottom, 8)
                    .padding(.trailing, deals > 0 ? 24 : 0)
                Text(info).font(.system(.footnote, weight: .semibold)).opacity(0.75)
                if meal.id != nil { actions.padding(.top, 10) }
                MealBadges(meal: meal, onGuests: meal.id != nil ? onGuests : nil, guestsOnly: true).padding(.top, 6)  // Lunchbox/Rest stehen schon oben
            }
            .foregroundStyle(white ? Theme.C.text1 : Theme.C.ink)  // weiße Karte wird im Dunkeln dunkel
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .padding(.vertical, 20).padding(.trailing, 20).padding(.leading, 116)
            .background(alignment: .topLeading) {
                Plate(url: mediaURL(meal.recipe.imageUrl), size: 84, seed: meal.recipe.title)
                    .rotationEffect(.degrees(rolling ? 360 : 0))
                    .padding(.leading, 16).padding(.top, 22)
            }
            .overlay(alignment: .topTrailing) {
                if deals > 0 {
                    Text("\(deals)").font(.system(.footnote, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(Theme.C.ink, in: Circle())
                        .padding(.top, 18).padding(.trailing, 16)
                        .accessibilityLabel("\(deals) Zutaten im Angebot")
                }
            }
            .background(color, in: RoundedRectangle(cornerRadius: Theme.R.day, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.R.day, style: .continuous).strokeBorder(Theme.C.line, lineWidth: white ? 1 : 0))
            // Knöpfe (Aktionen, Gäste) haben Vorrang vor dem Antippen der Karte
            .contentShape(RoundedRectangle(cornerRadius: Theme.R.day, style: .continuous))
            .onTapGesture { open = true }
            .accessibilityAddTraits(.isButton)
            .navigationDestination(isPresented: $open) { RecipeDetailView(meal: meal) }
        .sheet(isPresented: $replacing) {
            PlanSlotSheet(entry: meal).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet)
        }
        .modifier(RerollDialog(meal: meal, isPresented: $choosing) { roll(direction: $0, wish: $1) })
    }

    private func roll(direction: String? = nil, wish: String = "") {
        guard !meal.locked, !rolling else { return }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false)) { rolling = true }
        Task {
            await store.reroll(meal, direction: direction, wish: wish)
            withAnimation(Theme.spring) { rolling = false }
        }
    }

    private var actions: some View {
        ActionCluster(items: [
            .init(symbol: meal.recipe.favorite ? "heart.fill" : "heart",
                  label: meal.recipe.favorite ? "Aus Favoriten entfernen" : "Als Favorit merken") {
                Task { _ = await store.toggleFavorite(meal.recipe.id, current: meal.recipe.favorite) }
            },
            .init(symbol: "arrow.left.arrow.right", label: "Durch eigenes Rezept ersetzen") { replacing = true },
            .init(symbol: meal.locked ? "lock.fill" : "lock.open", label: meal.locked ? "Lösen" : "Fixieren") {
                Task { await store.setLocked(meal, !meal.locked) }
            },
            .init(symbol: "dice", label: "Neu würfeln") {
                if !meal.locked, !rolling { choosing = true }
            },
        ], compact: true, ink: color == Theme.C.card ? Theme.C.text1 : Theme.C.ink)
        .sensoryFeedback(.impact(weight: .light), trigger: meal.locked)
    }
}

/// S3 Rezeptdetail – Plan-Gericht oder gespeichertes Rezept (`meal.id == nil`, siehe `SavedRecipeView`).
struct RecipeDetailView: View {
    static let reportKinds = [("zutat_fehlt", "Zutat fehlt"), ("menge_falsch", "Menge falsch"), ("angebot_falsch", "Falsches Angebot"),
                              ("schritt_unklar", "Schritt unklar"), ("sonstiges", "Etwas anderes")]
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
    @State private var shareLink = false  // „Als Link teilen“ (56)
    @State private var reportKind: String?  // „Fehler melden“ (19.9): gewählte Art, dann Notiz
    @State private var reportNote = ""
    @State private var reporting = false
    @State private var info: RecipeDTO?  // GET /recipes/{id}: Bewertungen, Favorit, Nährwerte, falls im Plan noch null
    @State private var favorite: Bool?
    @State private var planIt = false
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var stepImages: [String]?  // nachgeladene Schritt-Bilder (9)
    @State private var imagesSettled = false  // Erzeugung fertig oder aus → leere Plätze ausblenden
    @State private var photoColor: Color?  // Verlaufsfarbe des Rezept-Kopfs (v3)
    @State private var replacingDish = false  // „Ersatz“: Gericht im Plan ersetzen (S19)
    @State private var choosing = false  // „Würfeln“ im Plan-Gericht (19.3), wie auf der Tageskarte
    @State private var disliking = false  // „Mag ich nicht“ mit Grund
    @State private var rolling = false
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
        let heroColor = photoColor ?? Theme.C.recipeFallback
        let deals = recipe.ingredients.filter { $0.offerId != nil }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // RecipeHero: Foto randlos, Verlauf in die Foto-Farbe (redesign-v3.md 6.1 S3)
                Color.clear.frame(height: 420)
                    .overlay {
                        RemoteImage(url: mediaURL(recipe.imageUrl), contentMode: .fill) { Plate(url: nil, size: 160, seed: recipe.title) }
                    }
                    .clipped()
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [heroColor.opacity(0), heroColor], startPoint: .top, endPoint: .bottom).frame(height: 200)
                    }
                    .padding(.bottom, -90)
                VStack(alignment: .leading, spacing: 0) {
                    Text(meal.id != nil ? "Aus deinem Plan · \(Labels.dayNames[meal.day])" : sourceLabel)
                        .font(.system(.subheadline, weight: .bold)).foregroundStyle(Theme.C.onPhoto2)
                    Text(recipe.title).font(Theme.F.titleLarge).tracking(-1.36).foregroundStyle(.white)
                        .lineLimit(3).minimumScaleFactor(0.7).padding(.top, 4)
                    if let avg = details.avgStars {
                        Text("★ \(num(avg, 1...1)) · \(details.ratings?.count ?? 0) Bewertungen")
                            .font(.system(.subheadline, weight: .semibold)).foregroundStyle(Theme.C.onPhoto2).padding(.top, 6)
                    }
                    if ["instagram", "web", "shared"].contains(recipe.source) { sourceRow.padding(.top, 10) }
                    HStack(spacing: 18) {
                        stat("Zeit", "\(recipe.prepMinutes) min")
                        Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 36)
                        stat("Portion", euro(Int(Double(meal.costCents) * (who == nil ? 1 : mine ?? 1) / base)))
                        if let kcal = nutrition?.kcal {
                            Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 36)
                            stat("kcal", "\(Int((kcal * (mine ?? 1)).rounded()))")
                        }
                    }
                    .padding(.top, 18)
                    HStack(spacing: 8) {
                        glassButton("bookmark", "Einplanen") { planIt = true }
                        // Plan-Gericht: „Ersatz“ steckt im Würfel-Dialog, damit drei Knöpfe in eine Zeile passen
                        if meal.id != nil {
                            glassButton(rolling ? "hourglass" : "dice", rolling ? "Würfelt …" : "Ändern") { choosing = true }
                                .disabled(rolling)
                        }
                        Menu {
                            Button("Als Bild teilen", systemImage: "photo") { shareCard = true }
                            Button("Als Link teilen", systemImage: "link") { shareLink = true }  // Feature 56
                        } label: { glassLabel("square.and.arrow.up", "Teilen") }
                        .accessibilityLabel("Rezept teilen")
                    }
                    .padding(.top, 18)
                    ingredientsCard(factor: factor, who: who, mine: mine, base: base).padding(.top, 16)
                    if deals > 0 {
                        Text(deals == 1 ? "1 Zutat im Angebot" : "\(deals) Zutaten im Angebot")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.C.onPhoto2).padding(.top, 8)
                    }
                }
                .padding(.horizontal, 22)

                // Ab hier noch nicht gemockt (redesign-v3.md 7, Gruppe B) – bisherige Karten
                VStack(alignment: .leading, spacing: 16) {
                    if !recipe.description.isEmpty {
                        Text(recipe.description).font(Theme.F.body).foregroundStyle(Theme.C.onPhoto2)
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
                    stepsCard
                    if let ratings = details.ratings, !ratings.isEmpty { ratingsCard(ratings) }
                    HStack {  // 19.9: Nie-Liste zurücknehmen (R15), Fehler melden (R13)
                        if details.hidden == true {
                            Button("Wieder vorschlagen", systemImage: "arrow.uturn.backward") {
                                Task { if let r = await store.unhide(recipe.id) { info = r } }
                            }
                        }
                        Spacer()
                        Button("Fehler melden", systemImage: "exclamationmark.bubble") { reporting = true }
                    }
                    .font(Theme.F.caption).foregroundStyle(Theme.C.text2).frame(minHeight: 44)
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 24)
                .padding(.bottom, 120)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(heroColor.ignoresSafeArea())
        .modifier(RerollDialog(meal: meal, isPresented: $choosing, onReplace: { replacingDish = true }, roll: reroll))
        .modifier(DislikeDialog(meal: meal, isPresented: $disliking, roll: meal.id == nil || meal.locked ? nil : { reroll(nil, "") },
                                  store: store))
        .onChange(of: recipe.id) {  // gewürfelt oder ersetzt: Daten des alten Rezepts verwerfen
            info = nil; favorite = nil; stepImages = nil; imagesSettled = false
        }
        .confirmationDialog("Was stimmt nicht?", isPresented: $reporting, titleVisibility: .visible) {
            ForEach(Self.reportKinds, id: \.0) { kind, label in Button(label) { reportKind = kind } }
        }
        .alert("Fehler melden", isPresented: Binding(get: { reportKind != nil }, set: { if !$0 { reportKind = nil } })) {
            TextField("Was genau? (optional)", text: $reportNote)
            Button("Senden") {
                let kind = reportKind ?? "sonstiges", note = reportNote
                reportNote = ""
                Task { await store.report(recipe.id, kind: kind, note: note) }
            }
            Button("Abbrechen", role: .cancel) { reportNote = "" }
        }
        .overlay(alignment: .top) {
            HStack(spacing: 10) {
                RoundIconButton(systemName: "chevron.left", fill: .clear, label: "Zurück") { dismiss() }.glassDark()
                Spacer()
                RoundIconButton(systemName: "hand.thumbsdown", fill: .clear, label: "Mag ich nicht") { disliking = true }.glassDark()
                Button { toggleFavorite() } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart").font(.system(size: 18, weight: .semibold))
                        .symbolEffect(.bounce, value: isFavorite).contentTransition(.symbolEffect(.replace))
                        .frame(width: Theme.S.roundButton, height: Theme.S.roundButton)
                }
                .buttonStyle(PressableStyle()).glassDark()
                .sensoryFeedback(.impact(weight: .medium), trigger: isFavorite)
                .accessibilityLabel(isFavorite ? "Aus Favoriten entfernen" : "Als Favorit merken")
                Menu {
                    Button("Gekocht – bewerten", systemImage: "star") { showRating = true }
                    Button("Angebotszutaten zur Liste", systemImage: "bag") {
                        let offers = recipe.ingredients.compactMap { ing in store.offers.first { $0.id == ing.offerId } }
                        withAnimation(Theme.spring) { offers.forEach { o in store.addToList(o) } }
                        if offers.isEmpty { store.flash("Keine Angebotszutaten") }
                    }
                    if recipe.source != "ai" {  // eigene und importierte Rezepte
                        Button("Bearbeiten", systemImage: "pencil") { editing = true }
                        Button("Löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold))
                        .frame(width: Theme.S.roundButton, height: Theme.S.roundButton)
                }
                .glassDark()
                .accessibilityLabel("Weitere Aktionen")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.pagePadding).padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            TotalBar(label: "Portionen", value: {
                HStack(spacing: 10) {
                    portionStep("minus", -1, base: base)
                    Text(num(servings.map { Double($0) } ?? base, 0...2)).contentTransition(.numericText())
                    portionStep("plus", 1, base: base)
                }
            }, buttonTitle: "Kochen", symbol: "play.fill") { cooking = true }
            .padding(.bottom, 2)
        }
        .hidesTabBar()
        .task(id: recipe.imageUrl) { photoColor = await PhotoColor.of(mediaURL(recipe.imageUrl)) }
        .sheet(isPresented: $replacingDish) {
            PlanSlotSheet(entry: meal).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(store.recipesVersion)-\(recipe.id)") { await loadInfo() }
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
        .sheet(isPresented: $shareLink) {
            RecipeLinkSheet(recipeId: recipe.id, title: recipe.title).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet)
        }
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
    private func reroll(_ direction: String?, _ wish: String) {
        rolling = true
        Task {
            await store.reroll(meal, direction: direction, wish: wish)
            rolling = false
        }
    }

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
            Label(recipe.source == "shared" ? "von \(recipe.sourceAuthor)"  // übernommen aus einem anderen Haushalt (56)
                    : "\(insta ? "Instagram" : "Web") · \(recipe.sourceAuthor.isEmpty ? host : recipe.sourceAuthor)",
                  systemImage: recipe.source == "shared" ? "person.2.fill" : insta ? "camera.fill" : "globe")
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

    private var sourceLabel: String {
        switch recipe.source {
        case "instagram": "Aus Instagram"
        case "web": "Aus dem Web"
        case "shared": "Geteiltes Rezept"
        case "user": "Eigenes Rezept"
        default: recipe.cuisine.isEmpty ? "Gespeichertes Rezept" : recipe.cuisine
        }
    }

    fileprivate func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(.caption2, weight: .heavy)).tracking(0.7).foregroundStyle(Theme.C.onPhoto2)
            Text(value).font(.system(.title3, weight: .bold)).monospacedDigit().foregroundStyle(.white)
        }
        .accessibilityElement(children: .combine)
    }

    fileprivate func glassLabel(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.system(.subheadline, weight: .bold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(.white.opacity(0.14), in: Capsule())
    }

    fileprivate func glassButton(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { glassLabel(symbol, title) }.buttonStyle(PressableStyle())
    }

    fileprivate func portionStep(_ symbol: String, _ step: Int, base: Double) -> some View {
        let current = servings ?? max(Int(base.rounded()), 1)
        return Button { withAnimation(Theme.spring) { servings = min(12, max(1, current + step)) } } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).frame(width: 28, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!(1...12).contains(current + step))
        .accessibilityLabel(step > 0 ? "Mehr Portionen" : "Weniger Portionen")
        .sensoryFeedback(.selection, trigger: servings)
    }

    /// Zutaten-Karte im Rezept-Kopf (weiß 12 %): Emoji, Name, Menge, rechts Rabatt + Laden bzw. „im Vorrat“.
    fileprivate func ingredientsCard(factor: Double, who: ProfileDTO?, mine: Double?, base: Double) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { index, ing in
                let offer = store.offers.first { $0.id == ing.offerId }
                let rest = meal.rests?.first { r in r.name.localizedCaseInsensitiveCompare(ing.name) == .orderedSame }
                if index > 0 { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
                // Feature 1: Zutat antippen → Angebot (oder passende Angebote)
                Button { if let offer { openOffer = offer } else { searchIngredient = ing } } label: {
                    HStack(spacing: 8) {
                        Text(offer.map { Theme.hue(category: $0.category).emoji } ?? (ing.inPantry == true ? "🧂" : "🥄"))
                        (Text(ing.name).foregroundStyle(.white)
                            + Text(" " + qty(ing.amount * factor, ing.unit)).foregroundStyle(Theme.C.onPhoto2))
                            .font(.system(.callout, weight: .semibold)).lineLimit(2).contentTransition(.numericText())
                        Spacer(minLength: 6)
                        if let offer {
                            DealBadge(text: (offer.discount.map { "−\($0) % " } ?? "Angebot ") + Labels.chain(offer.chain))
                        } else if ing.inPantry == true {
                            Text("im Vorrat").font(.system(.footnote, weight: .semibold)).foregroundStyle(Theme.C.onPhoto2)
                        } else if let rest, Labels.days.indices.contains(rest.fromDay) {
                            Text("♻︎ Rest von \(Labels.days[rest.fromDay])").font(.system(.footnote, weight: .semibold)).foregroundStyle(Theme.C.onPhoto2)
                        } else if ing.estimated == true {
                            Text("geschätzt").font(.footnote).foregroundStyle(Theme.C.onPhoto2)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .contextMenu {  // lange drücken → Ersatz (7)
                    Button("Ersatz finden", systemImage: "arrow.left.arrow.right") { substituting = index }
                    Button("Preisalarm", systemImage: "bell.badge") { alarmFor = ing.name }
                    Button("Mag ich nicht", systemImage: "hand.thumbsdown") { Task { await store.dislike(ing.name) } }  // 19.2
                }
                .accessibilityAction(named: "Ersatz finden") { substituting = index }
                .accessibilityAction(named: "Mag ich nicht") { Task { await store.dislike(ing.name) } }
                .accessibilityAction(named: "Preisalarm") { alarmFor = ing.name }
                .accessibilityHint(who.flatMap { w in mine.map { m in "Portion \(w.name): \(qty(ing.amount * m * meal.scale / base, ing.unit))" } } ?? "")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
        .animation(Theme.spring, value: servings)
    }

    private var stepsCard: some View {
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
                            Circle().fill(isDone ? Theme.C.lime : Theme.C.action)
                            if isDone { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                            else { Text("\(i + 1)").font(.system(.footnote, weight: .bold)) }
                        }
                        .foregroundStyle(isDone ? Theme.C.onLime : Theme.C.onAction).frame(width: 28, height: 28)
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

/// „Neues Gericht – wie soll es sein?“ (19.3): Richtung, eigener Wunsch oder „nie wieder“; Tageskarte und Rezeptdetail.
struct RerollDialog: ViewModifier {
    @Environment(AppStore.self) private var store
    let meal: MealDTO
    @Binding var isPresented: Bool
    var onReplace: (() -> Void)?  // „Durch eigenes Rezept ersetzen“ (Rezeptdetail)
    let roll: (_ direction: String?, _ wish: String) -> Void
    @State private var disliking = false
    @State private var wishing = false
    @State private var wish = ""

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Neues Gericht – wie soll es sein?", isPresented: $isPresented, titleVisibility: .visible) {
                if !meal.locked {
                    Button("Einfach anders") { roll(nil, "") }
                    ForEach(Labels.rerollDirections, id: \.0) { d in Button(d.1) { roll(d.0, "") } }
                    Button("Eigener Wunsch …") { wish = ""; wishing = true }
                }
                if let onReplace { Button("Durch eigenes Rezept ersetzen", action: onReplace) }
                Button("Mag ich nicht …", role: .destructive) { disliking = true }
                Button("Abbrechen", role: .cancel) {}
            }
            .alert("Was hättest du gern?", isPresented: $wishing) {
                TextField("z. B. mit Reis, etwas Asiatisches", text: $wish)
                Button("Würfeln") { roll(nil, wish) }
                Button("Abbrechen", role: .cancel) {}
            }
            .modifier(DislikeDialog(meal: meal, isPresented: $disliking, roll: meal.locked ? nil : { roll(nil, "") }, store: store))
    }
}

/// „Mag ich nicht“ mit Grund: Zutat → „Mag nicht“-Liste (19.2), schmeckt nicht/Sonstiges → Nie-Liste (Bewertung „nie“,
/// E96), keine Lust → nur diese Woche. Im Plan wird danach neu gewürfelt (`roll`), sonst bleibt es beim Merken.
enum DislikeReason {
    case ingredient(String), taste, other(String)

    var note: String {
        switch self {
        case .ingredient(let name): name
        case .taste: "schmeckt nicht"
        case .other(let text): text.isEmpty ? "sonstiges" : text
        }
    }
}

/// „Mag ich nicht“ mit Grund: Rezeptdetail und Würfel-Dialog (19.2), Swipe-Stapel (20).
struct DislikeDialog: ViewModifier {
    let ingredients: [String]
    @Binding var isPresented: Bool
    let noMood: (() -> Void)?  // „Keine Lust (nur diese Woche)“
    let choose: (DislikeReason) -> Void
    @State private var picking = false
    @State private var other = false
    @State private var note = ""

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Was magst du daran nicht?", isPresented: $isPresented, titleVisibility: .visible) {
                if !ingredients.isEmpty { Button("Zutaten mag ich nicht") { picking = true } }
                Button("Schmeckt mir einfach nicht") { choose(.taste) }
                if let noMood { Button("Keine Lust (nur diese Woche)", action: noMood) }
                Button("Sonstiges …") { note = ""; other = true }
                Button("Abbrechen", role: .cancel) {}
            }
            .confirmationDialog("Welche Zutat?", isPresented: $picking, titleVisibility: .visible) {
                ForEach(ingredients, id: \.self) { name in
                    Button(name) { choose(.ingredient(name)) }
                }
                Button("Abbrechen", role: .cancel) {}
            }
            .alert("Was passt dir nicht?", isPresented: $other) {
                TextField("z. B. zu scharf, zu aufwendig", text: $note)
                Button("Nie wieder vorschlagen") { choose(.other(note)) }
                Button("Abbrechen", role: .cancel) {}
            }
    }
}

extension DislikeDialog {
    /// Plan-Gericht: Zutat → Abneigungen, sonst Nie-Liste; danach ggf. neu würfeln.
    init(meal: MealDTO, isPresented: Binding<Bool>, roll: (() -> Void)?, store: AppStore) {
        self.init(ingredients: meal.recipe.ingredients.filter { $0.inPantry != true }.map(\.name).uniqued(),
                  isPresented: isPresented, noMood: roll) { reason in
            Task {
                if case .ingredient(let name) = reason {
                    await store.dislike(name)
                    roll?()
                } else if await store.rate(meal.recipe.id, stars: 1, again: "nie", note: "Mag ich nicht: \(reason.note)") {
                    if let roll { roll() } else { store.flash("Kommt nicht mehr in deine Pläne") }
                }
            }
        }
    }
}
