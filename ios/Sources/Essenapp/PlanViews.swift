import SwiftUI

/// Tab „Rezepte“: S2 Wochenplan + (Phase 4) Meine Rezepte.
struct RecipesTab: View {
    @Environment(AppStore.self) private var store
    @Binding var showGenerator: Bool
    @State private var mine = false
    @State private var day = Demo.screen != nil ? 1 : (Calendar(identifier: .iso8601).component(.weekday, from: .now) + 5) % 7
    @Namespace private var dayPill

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PillSegment(options: [(false, "Wochenplan"), (true, "Meine Rezepte")], selection: $mine)

                if mine {
                    EmptyState(emoji: "📖", title: "Meine Rezepte", text: "Gespeicherte und eigene Rezepte kommen in Phase 4.")
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
                    HStack(spacing: 10) {
                        summary("eurosign.circle.fill", Theme.C.warning, euro(plan.totalCents), "von \(euro(store.household?.budgetFoodWeekCents ?? 0))")
                        summary("arrow.down.circle.fill", Theme.C.accent, euro(plan.savedCents), "gespart")
                        summary("fork.knife.circle.fill", Theme.C.kcal, "\(plan.entries.count)", "Gerichte")
                    }
                    dayPicker(plan)
                    let meals = plan.entries.filter { $0.day == day }
                    if meals.isEmpty {
                        EmptyState(emoji: "😴", title: "Nichts geplant", text: "Für \(Labels.dayNames[day]) ist kein Gericht geplant.")
                    }
                    ForEach(Array(meals.enumerated()), id: \.element) { i, meal in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Labels.meal(meal.mealType).uppercased()).font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                            MealRow(meal: meal, actions: true)
                        }
                        .appear(delay: Double(i) * 0.06)
                    }
                    .id(day)
                } else {
                    EmptyState(emoji: "📅", title: "Noch kein Wochenplan", text: "Erstelle deinen ersten Plan.",
                               buttonTitle: "Plan erstellen") { showGenerator = true }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
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
    @State private var rolling = false

    var body: some View {
        let deals = meal.recipe.ingredients.filter { $0.offerId != nil }.count
        HStack(spacing: 14) {
            NavigationLink { RecipeDetailView(meal: meal) } label: {
                HStack(spacing: 14) {
                    Plate(url: URL(string: meal.recipe.imageUrl), size: 72, seed: meal.recipe.title)
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
                VStack(spacing: 8) {
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
        .padding(12)
        .card()
    }

    private func small(_ symbol: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(on ? .white : Theme.C.text1)
                .frame(width: 36, height: 36)
                .background(on ? Theme.C.action : Theme.C.surface, in: Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.impact(weight: .light), trigger: on)
        .accessibilityLabel(label)
    }
}

/// S3 Rezeptdetail.
struct RecipeDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let meal: MealDTO
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

    private var recipe: RecipeDTO { meal.recipe }

    var body: some View {
        let base = meal.basePortions  // Rezeptmengen gelten für so viele Portionen
        let factor = servings.map { Double($0) / base } ?? 1  // Portionen-Stepper skaliert das ganze Rezept
        let who = store.profiles.first { $0.memberId == (person ?? store.profile?.memberId) } ?? store.profile
        // Anteil der gewählten Person; alte Pläne ohne Portionen: 1 Portion je Person
        let mine: Double? = meal.portions.isEmpty ? 1 : meal.portions.first { $0.memberId == who?.memberId }?.factor
        ZStack(alignment: .bottom) {
            Theme.C.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                        Spacer()
                        Menu {
                            Button("Als Bild teilen", systemImage: "photo") { shareCard = true }
                            Button("Als Link teilen (kommt bald)", systemImage: "link") {}.disabled(true)  // Feature 56
                        } label: {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .foregroundStyle(Theme.C.text1)
                                .background(Theme.C.card, in: Circle())
                                .overlay(Circle().strokeBorder(Theme.C.line, lineWidth: 0.5))
                        }
                        .accessibilityLabel("Rezept teilen")
                    }
                    ZStack {
                        CornerFrame().stroke(Theme.C.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round)).frame(width: 276, height: 276)
                            .scaleEffect(spin ? 1 : 1.12).opacity(spin ? 1 : 0)
                        Plate(url: URL(string: recipe.imageUrl), size: 236, seed: recipe.title)
                            .rotationEffect(.degrees(spin ? 0 : -40))
                    }
                    .frame(maxWidth: .infinity)
                    .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) { spin = true } }
                    VStack(alignment: .leading, spacing: 4) {
                        let words = recipe.title.split(separator: " ")
                        (Text(words.prefix(1).joined()).font(.system(.title, weight: .bold))
                            + Text(" " + words.dropFirst().joined(separator: " ")).font(.system(.title, weight: .regular)).foregroundStyle(Theme.C.text2))
                        if !recipe.cuisine.isEmpty { Text(recipe.cuisine).font(Theme.F.caption).foregroundStyle(Theme.C.text2) }
                    }
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
                    // Nährwerte: werden berechnet, sobald Zutaten-Stammdaten da sind (E10)
                    if let who { portionCard(who, mine: mine, base: base) }

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Zutaten").font(Theme.F.headline)
                            Spacer()
                            Stepper(value: Binding(get: { servings ?? max(Int(base.rounded()), 1) }, set: { servings = $0 }), in: 1...12) {
                                Text("\(servings.map { Double($0) } ?? base, format: .number.precision(.fractionLength(0...2))) Portionen")
                                    .font(Theme.F.callout).contentTransition(.numericText())
                            }
                            .fixedSize()
                        }
                        .padding(.bottom, 6)
                        ForEach(recipe.ingredients, id: \.self) { ing in
                            let offer = store.offers.first { $0.id == ing.offerId }
                            // Feature 1: Zutat antippen → Angebot (oder passende Angebote)
                            Button { if let offer { openOffer = offer } else { searchIngredient = ing } } label: {
                            HStack(spacing: 12) {
                                Text(offer.map { Theme.hue(category: $0.category).emoji } ?? (ing.inPantry ? "🧂" : "🥄")).font(.system(size: 22))
                                    .frame(width: 40, height: 40).background(Theme.C.surface, in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ing.name).font(.system(.body, weight: .semibold))
                                    HStack(spacing: 6) {
                                        if let offer {
                                            DealBadge(text: offer.discount.map { "−\($0) %" } ?? "Angebot")
                                            StoreChip(chain: offer.chain)
                                        }
                                        if ing.inPantry { DealBadge(text: "im Vorrat", style: .ok) }
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(qty(ing.amount * factor, ing.unit))
                                        .monospacedDigit().foregroundStyle(Theme.C.text2).contentTransition(.numericText())
                                    if let who, let mine {
                                        Text("\(who.emoji) \(qty(ing.amount * mine / base, ing.unit))")
                                            .font(Theme.F.micro).monospacedDigit().foregroundStyle(Theme.C.accentDeep)
                                            .contentTransition(.numericText())
                                            .accessibilityLabel("Portion \(who.name): \(qty(ing.amount * mine / base, ing.unit))")
                                    }
                                }
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.C.text3)
                            }
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .padding(16).card()
                    .animation(Theme.spring, value: servings)
                    .animation(Theme.spring, value: person)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Zubereitung").font(Theme.F.headline)
                        ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, step in
                            let isDone = done.contains(i)
                            Button {
                                withAnimation(Theme.spring) { if done.remove(i) == nil { done.insert(i) } }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    ZStack {
                                        Circle().fill(isDone ? Theme.C.accent : Theme.C.action)
                                        if isDone { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                                        else { Text("\(i + 1)").font(.system(.footnote, design: .rounded, weight: .bold)) }
                                    }
                                    .foregroundStyle(.white).frame(width: 28, height: 28)
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
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 270)
            }
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
            .padding(.horizontal, Theme.pagePadding).padding(.bottom, Theme.ctaAboveTabBar)
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $cooking, onDismiss: {
            if rateAfterCooking { rateAfterCooking = false; showRating = true }  // Abschluss → Bewertung + Vorrat (S8)
        }) {
            CookingView(meal: meal, factor: factor, person: who.flatMap { w in mine.map { m in (w.emoji, m / base) } }) {
                rateAfterCooking = true
                cooking = false
            }
        }
        .sheet(isPresented: $shareCard) { ShareCardSheet(meal: meal).presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
        .sheet(isPresented: $showRating) { RatingSheet(meal: meal).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet) }
        .navigationDestination(item: $openOffer) { OfferDetailView(offer: $0) }
        .sheet(item: $searchIngredient) { IngredientOffersSheet(ingredient: $0).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet) }
    }
}

extension RecipeDetailView {
    fileprivate func infoCell(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).font(.system(.footnote, weight: .semibold)).foregroundStyle(Theme.C.text1)
            .frame(maxWidth: .infinity)
    }

    /// „Für: 🧑‍🍳 Jona ▾“ + „Deine Portion: 520 g · 2,10 €“ (48).
    fileprivate func portionCard(_ who: ProfileDTO, mine: Double?, base: Double) -> some View {
        let isMe = who.memberId == store.profile?.memberId
        let grams = recipe.ingredients.filter { ["g", "ml"].contains($0.unit) }.map(\.amount).reduce(0, +) * (mine ?? 0) / base
        let parts = [grams > 0 ? "\(Int(grams.rounded())) g" : nil, mine.map { euro(Int(Double(meal.costCents) * $0 / base)) },
                     mine.map { "×\($0.formatted()) von \(base.formatted()) Portionen" }].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Für:").font(Theme.F.callout).foregroundStyle(Theme.C.text2)
                Menu {
                    ForEach(store.profiles) { p in
                        Button("\(p.emoji) \(p.name)") { withAnimation(Theme.spring) { person = p.memberId } }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("\(who.emoji) \(who.name)")
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                    }
                    .font(Theme.F.callout).foregroundStyle(Theme.C.text1)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Theme.C.surface, in: Capsule())
                }
                .accessibilityLabel("Portion für \(who.name), ändern")
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
    "\(amount.formatted(.number.precision(.fractionLength(0...1)))) \(unit == "stk" ? "Stück" : unit)"
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

/// S8 Bewertung. shortcut: speichert noch nicht im Backend (Phase 4).
struct RatingSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let meal: MealDTO
    @State private var rating = 0
    @State private var again = "bald"
    @State private var note = ""
    @State private var consumed: [PantryDTO]?  // nach „Speichern“: vom Vorrat abgezogene Einträge (editierbar)

    var body: some View {
        if let consumed { consumedList(consumed) } else { ratingForm }
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
            Button("Fertig") { dismiss() }.buttonStyle(PrimaryButtonStyle())
        }
        .padding(Theme.pagePadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.C.bg)
        .transition(.opacity)
    }

    private var ratingForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Plate(url: URL(string: meal.recipe.imageUrl), size: 64, seed: meal.recipe.title)
                Text(meal.recipe.title).font(Theme.F.headline)
            }
            Text("Wie war's?").font(Theme.F.title)
            RatingStars(rating: $rating).frame(maxWidth: .infinity)
            Picker("Wieder kochen?", selection: $again) {
                Text("Bald").tag("bald"); Text("Irgendwann").tag("irgendwann"); Text("Nie").tag("nie")
            }
            .pickerStyle(.segmented)
            TextField("Notiz, z.B. mehr Chili …", text: $note).padding(14)
                .background(Theme.C.card, in: RoundedRectangle(cornerRadius: Theme.R.tile))
            Button("Speichern") {
                store.flash(rating >= 4 ? "Gespeichert – kommt öfter 🎉" : "Danke für deine Bewertung")
                Task {
                    let changed = await store.consume(meal)
                    if changed.isEmpty { dismiss(); return }
                    store.flash("Vorrat aktualisiert")
                    withAnimation(Theme.spring) { consumed = changed }
                }
            }
            .buttonStyle(PrimaryButtonStyle()).disabled(rating == 0).opacity(rating == 0 ? 0.5 : 1)
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
                        Text("Passe an, was du diese Woche essen möchtest – gilt nur für diesen Plan.").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                        VStack(alignment: .leading, spacing: 8) {
                            Label { Text("Wünsche").font(Theme.F.headline) } icon: { Text("💭") }
                            TextField("z.B. mehr Fisch, ein Gericht mit Kürbis", text: $wishes, axis: .vertical)
                                .lineLimit(1...3)
                                .padding(12).background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.chip))
                        }
                        .padding(16).card()
                        PreferencesForm(prefs: $prefs, showDiet: false)
                        Toggle("Als Standard speichern", isOn: $saveAsDefault).tint(Theme.C.accent).padding(16).card()
                    }
                    .padding(.bottom, 90)
                }
                .scrollDismissesKeyboard(.immediately)
                .overlay(alignment: .bottom) {
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
    }

    private func start() {
        withAnimation(Theme.spring) { started = true; phase = 0 }
        guard !store.demo else { return }
        Task {
            async let done: Void = store.generatePlan(prefs.options(wishes: wishes, saveAsDefault: saveAsDefault))
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
