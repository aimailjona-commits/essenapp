import SwiftUI

/// S6 Onboarding: Willkommen → Ort & Läden → Haushalt → Budget & Ziel.
struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var step = 0
    @State private var plz = ""
    @State private var chains: Set<String> = ["rewe", "lidl"]
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
        if step == 0 {
            welcome
        } else {
            ZStack(alignment: .bottom) {
                Theme.C.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 6) {
                            ForEach(1...4, id: \.self) { i in
                                Capsule().fill(i <= step + 1 ? Theme.C.action : Color(hex: 0xD6D5D0)).frame(height: 5)
                            }
                        }
                        switch step {
                        case 1: places
                        case 2: householdStep
                        default: budgetStep
                        }
                        if let error { Text(error).font(Theme.F.caption).foregroundStyle(Theme.C.danger) }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.bottom, 120)
                }
                Button(action: next) {
                    HStack {
                        if step == 3 { Image(systemName: "sparkles") }
                        Text(busy ? "Einen Moment …" : step == 3 ? "Ersten Plan erstellen" : "Weiter")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canContinue || busy)
                .opacity(canContinue ? 1 : 0.4)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 12)
            }
        }
    }

    private var canContinue: Bool {
        step != 1 || (plz.count == 5 && plz.allSatisfy(\.isNumber) && !chains.isEmpty)
    }

    private func next() {
        guard step == 3 else { step += 1; return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await store.createHousehold(name: "Zuhause", memberName: "Ich")
                try await store.save(HouseholdPatch(
                    plz: plz, persons: persons, diet: diet, allergies: Array(allergies),
                    excludedIngredients: dislikes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                    cuisines: Array(cuisines), mealTypes: Labels.mealTypes.map(\.0).filter(meals.contains),
                    budgetFoodWeekCents: Int(budgetEuro) * 100, nutritionGoal: goal,
                    stores: Labels.chains.map(\.key).filter(chains.contains).map { StoreDTO(chain: $0) }))
                await store.loadAll()
                Task {
                    store.generating = true  // Start zeigt Skeleton, bis Angebote + Plan da sind
                    await store.refreshOffers()
                    await store.generatePlan()
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: Schritte

    private var welcome: some View {
        @Bindable var api = store.api
        return ZStack(alignment: .bottomLeading) {
            Color(hex: 0x1A1A18).ignoresSafeArea()
            ZStack {
                Plate(url: nil, size: 230, seed: "a").offset(x: -110, y: -230)
                Plate(url: nil, size: 180, seed: "d").offset(x: 130, y: -280)
                Plate(url: nil, size: 200, seed: "e").offset(x: 40, y: -60)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            LinearGradient(colors: [.clear, Theme.C.action], startPoint: .center, endPoint: .bottom).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                (Text("Kochen nach\n").foregroundStyle(.white) + Text("Angebot.").foregroundStyle(Color(hex: 0x8F8F8A)))
                    .font(.system(size: 40, weight: .heavy))
                Text("Wir lesen die Prospekte deiner Läden und planen daraus deine Woche – passend zu Budget, Geschmack und Zielen.")
                    .foregroundStyle(Color(hex: 0xBDBDBD))
                TextField("", text: $api.baseURL, prompt: Text("Server, z.B. http://192.168.178.20:8000").foregroundStyle(Color(hex: 0x8F8F8A)))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.R.chip))
                Button("Los geht's") { step = 1 }
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Theme.C.text1)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(.white, in: Capsule())
                    .disabled(api.baseURL.isEmpty)
            }
            .padding(24)
        }
    }

    private var places: some View {
        VStack(alignment: .leading, spacing: 18) {
            DisplayHeader(line1: "Wo kaufst", line2: "du ein?")
            VStack(alignment: .leading, spacing: 2) {
                Text("POSTLEITZAHL").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                TextField("50667", text: $plz).keyboardType(.numberPad).font(.system(size: 30, weight: .heavy)).tracking(2)
            }
            .padding(.horizontal, 18).padding(.vertical, 14).card(radius: 22)
            VStack(spacing: 0) {
                ForEach(Labels.chains, id: \.key) { chain in
                    Toggle(isOn: Binding(get: { chains.contains(chain.key) },
                                         set: { if $0 { chains.insert(chain.key) } else { chains.remove(chain.key) } })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chain.name).font(.system(.body, weight: .semibold))
                            Text(chain.drugstore ? "Drogerie" : ["rewe", "edeka"].contains(chain.key) ? "Filiale in deiner Nähe" : "regional")
                                .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                        }
                    }
                    .tint(Theme.C.accentDeep)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    Divider().opacity(chain.key == Labels.chains.last?.key ? 0 : 1)
                }
            }
            .card(radius: 24)
        }
    }

    private var householdStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            DisplayHeader(line1: "Wer isst", line2: "mit?")
            HStack {
                stepButton("minus") { persons = max(1, persons - 1) }
                Spacer()
                VStack { Text("\(persons)").font(.system(size: 30, weight: .heavy)); Text("Personen").font(Theme.F.caption).foregroundStyle(Theme.C.text2) }
                Spacer()
                stepButton("plus") { persons = min(20, persons + 1) }
            }
            .padding(12).card(radius: 24)
            label("ERNÄHRUNG")
            ChipFlow(items: Labels.diets.map { ($0.0, $0.1) }, selected: [diet]) { diet = $0 }
            label("ALLERGIEN & UNVERTRÄGLICHKEITEN")
            ChipFlow(items: Labels.allergies.map { ($0, $0) }, selected: allergies) { allergies.formSymmetricDifference([$0]) }
            label("MAG ICH NICHT")
            TextField("z.B. Koriander, Pilze …", text: $dislikes)
                .padding(16).background(Theme.C.cardTop, in: RoundedRectangle(cornerRadius: 18)).softShadow()
        }
    }

    private var budgetStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            DisplayHeader(line1: "Budget", line2: "& Ziel")
            VStack(spacing: 4) {
                Text(euro(Int(budgetEuro) * 100)).font(.system(size: 56, weight: .heavy)).monospacedDigit()
                Text("pro Woche für Lebensmittel").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                Slider(value: $budgetEuro, in: 20...200, step: 5).tint(Theme.C.accent)
            }
            .frame(maxWidth: .infinity)
            label("ZIEL")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Labels.goals, id: \.0) { g in
                    Button { goal = g.0 } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            NutrientIcon(nutrient: g.0 == "proteinreich" ? .protein : g.0 == "kalorienarm" ? .kcal : .carbs)
                            Text(g.1).font(Theme.F.callout)
                            Text(g.2).font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                        }
                        .foregroundStyle(Theme.C.text1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Theme.C.cardTop, in: RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(goal == g.0 ? Theme.C.action : .clear, lineWidth: 2))
                    }
                }
            }
            label("MAHLZEITEN")
            ChipFlow(items: Labels.mealTypes, selected: meals) { meals.formSymmetricDifference([$0]) }
            label("KÜCHE (leer = gemischt)")
            ChipFlow(items: Labels.cuisines.map { ($0, $0) }, selected: cuisines) { cuisines.formSymmetricDifference([$0]) }
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
    }
}

/// Umbrechende Chips mit Mehrfach- oder Einfachauswahl.
struct ChipFlow: View {
    let items: [(String, String)]
    let selected: Set<String>
    let toggle: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.0) { item in
                FilterChip(label: item.1, selected: selected.contains(item.0)) { toggle(item.0) }
            }
        }
    }
}

/// Einfaches Umbruch-Layout für Chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var current: [Int] = [], x: CGFloat = 0, y: CGFloat = 0, height: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x + size.width > width, !current.isEmpty {
                rows.append((current, y, x - spacing, height))
                y += height + spacing
                current = []; x = 0; height = 0
            }
            current.append(index)
            x += size.width + spacing
            height = max(height, size.height)
        }
        if !current.isEmpty { rows.append((current, y, x - spacing, height)) }
        return rows
    }
}
