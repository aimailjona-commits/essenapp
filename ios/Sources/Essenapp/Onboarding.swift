import SwiftUI

/// S6 Onboarding: Willkommen → PLZ → Läden auf der Karte → Haushalt → Budget & Ziel.
struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var step = 0
    @State private var plz = ""
    @State private var persons = 2
    @State private var diet = "alles"
    @State private var allergies: Set<String> = []
    @State private var dislikes = ""
    @State private var budgetEuro = 60.0
    @State private var goal = "ausgewogen"
    @State private var meals: Set<String> = ["mittag", "abend"]
    @State private var cuisines: Set<String> = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Group {
            if step == 0 {
                welcome.transition(.opacity)
            } else if step == 2 {
                VStack(spacing: 0) {
                    progress.padding(.horizontal, Theme.pagePadding).padding(.top, 8)
                    StoreMapView { withAnimation(Theme.spring) { step = 3 } }
                }
                .background(Theme.C.bg)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                form.transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(Theme.spring, value: step)
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(1...4, id: \.self) { i in
                Capsule().fill(i <= step ? Theme.C.ink : Color(hex: 0xD8D3C8)).frame(height: 5)
            }
        }
        .animation(Theme.spring, value: step)
    }

    private var form: some View {
        ZStack(alignment: .bottom) {
            Theme.C.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        RoundIconButton(systemName: "chevron.left", label: "Zurück") { step = step == 3 ? 2 : step - 1 }
                        progress
                    }
                    switch step {
                    case 1: plzStep
                    case 3: householdStep
                    default: budgetStep
                    }
                    if let error { Text(error).font(Theme.F.caption).foregroundStyle(Theme.C.danger) }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.immediately)
            Button(action: next) {
                HStack {
                    if busy { ProgressView().tint(Theme.C.onAction) }
                    if step == 4 && !busy { Image(systemName: "sparkles") }
                    Text(busy ? "Einen Moment …" : step == 4 ? "Ersten Plan erstellen" : "Weiter")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canContinue || busy)
            .opacity(canContinue ? 1 : 0.4)
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 12)
        }
    }

    private var canContinue: Bool {
        step != 1 || (plz.count == 5 && plz.allSatisfy(\.isNumber))
    }

    private func next() {
        error = nil
        switch step {
        case 1:
            busy = true
            Task {
                defer { busy = false }
                do {
                    if store.api.token == nil { try await store.createHousehold(name: "Zuhause", memberName: "Ich") }
                    try await store.save(HouseholdPatch(plz: plz))
                    step = 2
                } catch {
                    self.error = error.localizedDescription
                }
            }
        case 4:
            busy = true
            Task {
                defer { busy = false }
                do {
                    try await store.save(HouseholdPatch(
                        persons: persons, diet: diet, allergies: Array(allergies),
                        excludedIngredients: dislikes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                        cuisines: Array(cuisines), mealTypes: Labels.mealTypes.map(\.0).filter(meals.contains),
                        budgetFoodWeekCents: Int(budgetEuro) * 100, nutritionGoal: goal))
                    store.onboarded = true
                    Task {
                        store.generating = true  // Start zeigt Skeleton, bis Angebote + Plan da sind
                        await store.refreshOffers()
                        await store.generatePlan()
                    }
                } catch {
                    self.error = error.localizedDescription
                }
            }
        default:
            step += 1
        }
    }

    // MARK: Schritte

    /// Schritt 1 v3: Sticker-Collage (alles gerade), unten Fortschritt, Titel, Satz, Server, „Los geht's“.
    private var welcome: some View {
        @Bindable var api = store.api
        let pasta = Bundle.module.url(forResource: "pasta", withExtension: "jpg")
        return ZStack(alignment: .bottom) {
            Theme.C.bg.ignoresSafeArea()
            ZStack(alignment: .topLeading) {  // Positionen wie im Mockup (390 pt breit)
                Ellipse().fill(Theme.C.lav).frame(width: 150, height: 150).offset(x: 28, y: 44)
                Plate(url: pasta, size: 112).offset(x: 52, y: 66)
                Text("Spart 12 € pro Woche!").font(.custom("Bradley Hand", size: 21, relativeTo: .title3)).foregroundStyle(Theme.C.ink)
                    .padding(18).frame(width: 150, height: 150, alignment: .topLeading)
                    .background(Theme.C.sun, in: RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 10)
                    .offset(x: 216, y: 58)
                BurstShape(points: 10, inner: 0.4).fill(Theme.C.sky).frame(width: 160, height: 160).offset(x: 150, y: 226)
                Text("🥑").font(.system(size: 72)).rotationEffect(.degrees(-14)).shadow(color: .black.opacity(0.2), radius: 5, y: 10)
                    .offset(x: 26, y: 248)
                Text("Mo – So geplant ✓").font(.system(.callout, weight: .heavy)).foregroundStyle(Theme.C.ink)
                    .padding(.horizontal, 18).padding(.vertical, 10).background(Theme.C.tomato, in: Capsule())
                    .offset(x: 196, y: 368)
                Text("🛒").font(.system(size: 40)).frame(width: 76, height: 76).background(Theme.C.mint, in: Circle())
                    .offset(x: 40, y: 378)
            }
            .frame(width: 390, height: 470, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Capsule().fill(Theme.C.ink).frame(width: 44, height: 5)
                    ForEach(0..<3, id: \.self) { _ in Capsule().fill(Color(hex: 0xD8D3C8)).frame(width: 20, height: 5) }
                }
                .padding(.bottom, 22)
                DisplayHeader(line1: "Kochen nach", line2: "Angebot.", size: 50)
                Text("Wir lesen die Prospekte deiner Läden und planen daraus deine Woche.")
                    .font(.system(.callout)).foregroundStyle(Theme.C.text2).lineSpacing(4).padding(.top, 12).padding(.bottom, 16)
                TextField("Server, z.B. http://192.168.178.20:8000", text: $api.baseURL)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(Theme.F.caption)
                    .padding(.horizontal, 18).frame(height: 44)
                    .background(Theme.C.card, in: Capsule()).overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: 1))
                    .padding(.bottom, 10)
                Button("Los geht's") { step = 1 }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(api.baseURL.isEmpty)
                    .opacity(api.baseURL.isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
            .appear(delay: 0.2)
        }
    }

    private var plzStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            DisplayHeader(line1: "Wo wohnst", line2: "du?")
            Text("Wir suchen die Läden in deiner Nähe und laden ihre Prospekte.").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            VStack(alignment: .leading, spacing: 2) {
                Text("POSTLEITZAHL").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                TextField("50667", text: $plz).keyboardType(.numberPad)
                    .font(.system(size: 34, weight: .bold, design: .rounded)).tracking(3)
            }
            .padding(.horizontal, 18).padding(.vertical, 14).card()
            Text("📍").font(.system(size: 80)).frame(maxWidth: .infinity).padding(.top, 20).appear(delay: 0.1)
        }
    }

    private var householdStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            DisplayHeader(line1: "Wer isst", line2: "mit?")
            HStack {
                stepButton("minus") { persons = max(1, persons - 1) }
                Spacer()
                VStack {
                    Text(String(repeating: "🙂", count: min(persons, 6))).font(.system(size: 22))
                    Text("\(persons) Personen").font(.system(.title3, design: .rounded, weight: .bold)).contentTransition(.numericText())
                }
                Spacer()
                stepButton("plus") { persons = min(20, persons + 1) }
            }
            .padding(12).card()
            .animation(Theme.spring, value: persons)
            label("ERNÄHRUNG")
            ChipFlow(items: Labels.diets.map { ($0.0, $0.1) }, selected: [diet]) { diet = $0 }
            label("ALLERGIEN & UNVERTRÄGLICHKEITEN")
            ChipFlow(items: Labels.allergies.map { ($0, $0) }, selected: allergies, color: Theme.C.protein) { allergies.formSymmetricDifference([$0]) }
            label("MAG ICH NICHT")
            TextField("z.B. Koriander, Pilze …", text: $dislikes)
                .padding(16).background(Theme.C.card, in: RoundedRectangle(cornerRadius: Theme.R.tile))
                .overlay(RoundedRectangle(cornerRadius: Theme.R.tile).strokeBorder(Theme.C.line, lineWidth: 0.5))
        }
    }

    private var budgetStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            DisplayHeader(line1: "Budget", line2: "& Ziel")
            VStack(spacing: 4) {
                Text(euro(Int(budgetEuro) * 100)).font(.system(size: 54, weight: .bold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(Theme.spring, value: budgetEuro)
                Text("pro Woche für Lebensmittel").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                Slider(value: $budgetEuro, in: 20...200, step: 5).tint(Theme.C.accent)
                    .sensoryFeedback(.selection, trigger: budgetEuro)
            }
            .padding(18).card()
            label("ZIEL")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Labels.goals, id: \.0) { g in
                    let on = goal == g.0
                    Button { withAnimation(Theme.spring) { goal = g.0 } } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(g.0 == "proteinreich" ? "💪" : g.0 == "kalorienarm" ? "🥗" : "⚖️").font(.system(size: 28))
                            Text(g.1).font(Theme.F.callout)
                            Text(g.2).font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                        }
                        .foregroundStyle(Theme.C.text1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(on ? Theme.C.accentSoft : Theme.C.card, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(on ? Theme.C.accent : Theme.C.line, lineWidth: on ? 2 : 0.5))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            label("MAHLZEITEN")
            ChipFlow(items: Labels.mealTypes.filter { m in m.0 != "snack" }, selected: meals, color: Theme.C.kcal) { meals.formSymmetricDifference([$0]) }
            label("KÜCHE (leer = gemischt)")
            ChipFlow(items: Labels.cuisines.map { ($0, $0) }, selected: cuisines, color: Theme.C.accent) { cuisines.formSymmetricDifference([$0]) }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Theme.F.micro).foregroundStyle(Theme.C.text2).padding(.top, 4)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.C.text1)
                .frame(width: 48, height: 48).background(Theme.C.surface, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.selection, trigger: persons)
    }
}

/// Umbrechende Chips mit Mehrfach- oder Einfachauswahl.
struct ChipFlow: View {
    let items: [(String, String)]
    let selected: Set<String>
    var color: Color = Theme.C.action
    let toggle: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.0) { item in
                FilterChip(label: item.1, color: color, selected: selected.contains(item.0)) {
                    withAnimation(Theme.spring) { toggle(item.0) }
                }
            }
        }
    }
}
