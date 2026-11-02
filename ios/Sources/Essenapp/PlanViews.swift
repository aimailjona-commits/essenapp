import SwiftUI

/// Tab „Rezepte“: S2 Wochenplan + (Phase 4) Meine Rezepte.
struct RecipesTab: View {
    @Environment(AppStore.self) private var store
    @Binding var showGenerator: Bool
    @State private var mine = false
    @State private var day = (Calendar(identifier: .iso8601).component(.weekday, from: .now) + 5) % 7

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("", selection: $mine) {
                    Text("Wochenplan").tag(false)
                    Text("Meine Rezepte").tag(true)
                }
                .pickerStyle(.segmented)

                if mine {
                    EmptyState(symbol: "book.closed", title: "Meine Rezepte", text: "Gespeicherte und eigene Rezepte kommen in Phase 4.")
                } else if let plan = store.plan {
                    DisplayHeader(line1: plan.week.replacingOccurrences(of: "-W", with: " · KW "), line2: "Dein Plan")
                    HStack(spacing: 10) {
                        summary(euro(plan.totalCents), "von \(euro(store.household?.budgetFoodWeekCents ?? 0))")
                        summary(euro(plan.savedCents), "gespart")
                        summary("\(plan.entries.count)", "Gerichte")
                    }
                    HStack(spacing: 8) {
                        ForEach(0..<7, id: \.self) { d in
                            let has = plan.entries.contains { $0.day == d }
                            Button { day = d } label: {
                                VStack(spacing: 2) {
                                    Text(Labels.days[d].uppercased()).font(Theme.F.micro)
                                    Circle().fill(has ? Theme.C.accent : .clear).frame(width: 6, height: 6)
                                }
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .foregroundStyle(day == d ? Theme.C.onAction : Theme.C.text1)
                                .background(day == d ? Theme.C.action : Theme.C.cardTop, in: RoundedRectangle(cornerRadius: 20))
                            }
                        }
                    }
                    let meals = plan.entries.filter { $0.day == day }
                    if meals.isEmpty {
                        EmptyState(symbol: "moon.zzz", title: "Nichts geplant", text: "Für \(Labels.dayNames[day]) ist kein Gericht geplant.")
                    }
                    ForEach(Array(meals.enumerated()), id: \.offset) { _, meal in
                        Text(Labels.meal(meal.mealType).uppercased()).font(Theme.F.micro).foregroundStyle(Theme.C.text2).padding(.top, 4)
                        NavigationLink { RecipeDetailView(meal: meal) } label: { MealRow(meal: meal) }.buttonStyle(.plain)
                    }
                } else {
                    EmptyState(symbol: "calendar", title: "Noch kein Wochenplan", text: "Erstelle deinen ersten Plan.",
                               buttonTitle: "Plan erstellen") { showGenerator = true }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
        }
    }

    private func summary(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.headline, weight: .heavy)).monospacedDigit()
            Text(label).font(Theme.F.micro).foregroundStyle(Theme.C.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.C.cardTop, in: RoundedRectangle(cornerRadius: Theme.R.tile))
    }
}

struct MealRow: View {
    let meal: MealDTO

    var body: some View {
        HStack(spacing: 14) {
            Plate(url: URL(string: meal.recipe.imageUrl), size: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.recipe.title).font(.system(.subheadline, weight: .bold)).lineLimit(2)
                Text("\(meal.recipe.prepMinutes) min · \(euro(meal.costCents))").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                let deals = meal.recipe.ingredients.filter { $0.offerId != nil }.count
                if deals > 0 { DealBadge(text: "\(deals) Zutaten im Angebot", style: .soft) }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.C.text3)
        }
        .padding(12)
        .card(radius: 24)
    }
}

/// S3 Rezeptdetail.
struct RecipeDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let meal: MealDTO
    @State private var showRating = false

    private var recipe: RecipeDTO { meal.recipe }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.C.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                        Spacer()
                    }
                    ZStack {
                        CornerFrame().stroke(Theme.C.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round)).frame(width: 276, height: 276)
                        Plate(url: URL(string: recipe.imageUrl), size: 236)
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 4) {
                        Text(recipe.title).font(Theme.F.title).multilineTextAlignment(.center)
                        Text("\(euro(meal.costCents / max(recipe.servings, 1))) pro Portion · \(recipe.prepMinutes) min\(recipe.cuisine.isEmpty ? "" : " · \(recipe.cuisine)")")
                            .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                    }
                    .frame(maxWidth: .infinity)
                    if !recipe.description.isEmpty {
                        Text(recipe.description).font(Theme.F.body).foregroundStyle(Theme.C.text2)
                    }
                    // Nährwerte: werden berechnet, sobald Zutaten-Stammdaten da sind (E10)

                    Text("Zutaten · \(recipe.servings) Portionen").font(Theme.F.headline).padding(.top, 6)
                    VStack(spacing: 0) {
                        ForEach(recipe.ingredients, id: \.self) { ing in
                            let offer = store.offers.first { $0.id == ing.offerId }
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ing.name).font(.system(.body, weight: .semibold))
                                    HStack(spacing: 6) {
                                        if let offer {
                                            DealBadge(text: offer.regularPriceCents.map { r in "−\(Int((Double(r - offer.priceCents) / Double(r) * 100).rounded())) %" } ?? "Angebot")
                                            StoreChip(name: Labels.chain(offer.chain))
                                        }
                                        if ing.inPantry { DealBadge(text: "im Vorrat", style: .ok) }
                                    }
                                }
                                Spacer()
                                Text("\(ing.amount.formatted()) \(ing.unit == "stk" ? "Stück" : ing.unit)").monospacedDigit().foregroundStyle(Theme.C.text2)
                            }
                            .padding(.vertical, 10)
                            Divider()
                        }
                    }
                    Text("Zubereitung").font(Theme.F.headline).padding(.top, 6)
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)").font(.system(.footnote, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 28, height: 28).background(Theme.C.action, in: Circle())
                            Text(step).font(Theme.F.body)
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 120)
            }
            Button { showRating = true } label: { Label("Gekocht – jetzt bewerten", systemImage: "checkmark") }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, Theme.pagePadding).padding(.bottom, 12)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showRating) { RatingSheet(meal: meal).presentationDetents([.medium]) }
    }
}

/// Limetten-Eckrahmen wie Referenz 02.
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
    @Environment(\.dismiss) private var dismiss
    let meal: MealDTO
    @State private var rating = 0
    @State private var again = "bald"
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Plate(url: URL(string: meal.recipe.imageUrl), size: 64)
                Text(meal.recipe.title).font(Theme.F.headline)
            }
            Text("Wie war's?").font(Theme.F.title)
            RatingStars(rating: $rating)
            Picker("Wieder kochen?", selection: $again) {
                Text("Bald").tag("bald"); Text("Irgendwann").tag("irgendwann"); Text("Nie").tag("nie")
            }
            .pickerStyle(.segmented)
            TextField("Notiz, z.B. mehr Chili …", text: $note).padding(14).background(Theme.C.cardTop, in: RoundedRectangle(cornerRadius: 18))
            Button("Speichern") { dismiss() }.buttonStyle(PrimaryButtonStyle()).disabled(rating == 0)
        }
        .padding(Theme.pagePadding)
        .background(Theme.C.bg)
    }
}

/// S7 Plan-Generator (vereinfachte Version: nutzt die Einstellungen, zeigt Lade-Zustand).
struct PlanGeneratorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var phase = 0
    @State private var started = false

    private let steps = ["Angebote auswerten", "Lieblingsrezepte prüfen", "Gerichte planen", "Preise & Nährwerte rechnen"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if started {
                VStack(spacing: 20) {
                    Plate(url: nil, size: 150).rotationEffect(.degrees(Double(phase) * 90)).animation(.linear(duration: 6), value: phase)
                    Text(store.error == nil ? "Dein Plan entsteht …" : "Das hat nicht geklappt").font(Theme.F.title)
                    Text(store.error ?? "Dauert meist unter einer Minute").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                            HStack(spacing: 12) {
                                Image(systemName: i < phase ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(i < phase ? Theme.C.accentDeep : Theme.C.text3)
                                Text(step).font(Theme.F.callout).foregroundStyle(i <= phase ? Theme.C.text1 : Theme.C.text3)
                            }
                        }
                    }
                    if store.error != nil {
                        Button("Erneut versuchen") { start() }.buttonStyle(PrimaryButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
            } else {
                Text("Wochenplan erstellen").font(Theme.F.title)
                if let h = store.household {
                    info("LÄDEN", h.stores.filter(\.enabled).map { Labels.chain($0.chain) }.joined(separator: ", "))
                    info("MAHLZEITEN", h.mealTypes.map(Labels.meal).joined(separator: ", "))
                    info("TAGE", h.planDays.sorted().map { Labels.days[$0] }.joined(separator: " "))
                    info("BUDGET", euro(h.budgetFoodWeekCents))
                    info("ZIEL", h.nutritionGoal.capitalized)
                }
                Text("Ändern kannst du das in den Einstellungen.").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                Spacer()
                Button { start() } label: { Label("Plan erstellen", systemImage: "sparkles") }.buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(Theme.pagePadding)
        .background(Theme.C.bg)
    }

    private func info(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.F.micro).foregroundStyle(Theme.C.text2)
            Text(value).font(Theme.F.callout)
        }
    }

    private func start() {
        started = true
        phase = 0
        Task {
            async let done: Void = store.generatePlan()
            for i in 1..<steps.count {  // Fortschritt ist nur Anzeige, das Backend arbeitet in einem Aufruf
                try? await Task.sleep(for: .seconds(8))
                if store.generating { phase = i }
            }
            await done
            if store.error == nil { phase = steps.count; dismiss() }
        }
    }
}
