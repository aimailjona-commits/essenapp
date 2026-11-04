import SwiftUI

/// Bearbeitbare Präferenzen (Einstellungen und Plan-Generator teilen sich das Formular).
struct Prefs: Equatable {
    var persons = 2
    var diet = "alles"
    var allergies: Set<String> = []
    var dislikes = ""
    var cuisines: Set<String> = []
    var mealTypes: Set<String> = ["mittag", "abend"]
    var planDays: Set<Int> = Set(0..<7)
    var budgetEuro = 60.0
    var goal = "ausgewogen"
    var maxCook = 45.0
    var productRules: [ProductRuleDTO] = []  // „Hafermilch statt Milch“ (19.2)

    init() {}

    init(_ h: HouseholdDTO) {
        persons = h.persons; diet = h.diet; allergies = Set(h.allergies)
        dislikes = h.excludedIngredients.joined(separator: ", ")
        cuisines = Set(h.cuisines); mealTypes = Set(h.mealTypes); planDays = Set(h.planDays)
        budgetEuro = Double(h.budgetFoodWeekCents) / 100; goal = h.nutritionGoal; maxCook = Double(h.maxCookMinutes)
        productRules = h.productRules ?? []
    }

    var mealTypeList: [String] { Labels.mealTypes.map(\.0).filter(mealTypes.contains) }

    var patch: HouseholdPatch {
        HouseholdPatch(persons: persons, diet: diet, allergies: Array(allergies),
                       excludedIngredients: dislikes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                       cuisines: Array(cuisines), mealTypes: mealTypeList, planDays: planDays.sorted(),
                       budgetFoodWeekCents: Int(budgetEuro) * 100, nutritionGoal: goal, maxCookMinutes: Int(maxCook),
                       productRules: productRules)
    }

    func options(wishes: String, saveAsDefault: Bool) -> PlanOptions {
        PlanOptions(cuisines: Array(cuisines), mealTypes: mealTypeList, planDays: planDays.sorted(),
                    budgetFoodWeekCents: Int(budgetEuro) * 100, nutritionGoal: goal, persons: persons,
                    maxCookMinutes: Int(maxCook), diet: diet, wishes: wishes.isEmpty ? nil : String(wishes.prefix(300)),
                    saveAsDefault: saveAsDefault)
    }
}

/// Body für POST /plans (alle Felder optional, gelten nur für diesen Plan).
struct PlanOptions: Encodable {
    var cuisines: [String]?
    var mealTypes: [String]?
    var planDays: [Int]?
    var budgetFoodWeekCents: Int?
    var nutritionGoal: String?
    var persons: Int?
    var maxCookMinutes: Int?
    var diet: String?
    var wishes: String?
    var guests: [GuestSlot]?  // „+ Gäste“ je Tag/Mahlzeit (15)
    var guestBudgetCents: Int?  // „Gäste-Budget extra“
    var special: String?  // Special-Vorlage = key aus GET /specials (25)
    var nextWeek = false  // „Plan für nächste Woche“ mit den Vorschau-Angeboten (30)
    var singleStore: String?  // „Nur ein Laden“ (41): chain eines gewählten Ladens
    var saveAsDefault = false
}

/// Abschnitte des Formulars, einzeln ein-/ausblendbar.
struct PreferencesForm: View {
    @Binding var prefs: Prefs
    var showDiet = true
    @State private var newAllergy = ""
    @State private var instead = ""
    @State private var use = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("🍽️", "Mahlzeiten & Tage") {
                ChipFlow(items: Labels.mealTypes, selected: prefs.mealTypes, color: Theme.C.kcal) { prefs.mealTypes.formSymmetricDifference([$0]) }
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { d in
                        let on = prefs.planDays.contains(d)
                        Button { withAnimation(Theme.spring) { prefs.planDays.formSymmetricDifference([d]) } } label: {
                            Text(Labels.days[d]).font(.system(.caption, design: .rounded, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .foregroundStyle(on ? Theme.C.onAction : Theme.C.text1)
                                .background(on ? Theme.C.action : Theme.C.surface, in: Circle())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .sensoryFeedback(.selection, trigger: prefs.planDays)
            }
            section("🌍", "Küche (leer = gemischt)") {
                ChipFlow(items: Labels.cuisines.map { ($0, $0) }, selected: prefs.cuisines, color: Theme.C.accent) { prefs.cuisines.formSymmetricDifference([$0]) }
            }
            section("💶", "Budget pro Woche") {
                HStack {
                    Text(euro(Int(prefs.budgetEuro) * 100)).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                        .contentTransition(.numericText()).animation(Theme.spring, value: prefs.budgetEuro)
                    Spacer()
                }
                Slider(value: $prefs.budgetEuro, in: 20...200, step: 5).tint(Theme.C.accent)
            }
            section("🎯", "Ziel") {
                Picker("Ziel", selection: $prefs.goal) {
                    ForEach(Labels.goals, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)
            }
            section("⏱️", "Kochzeit & Personen") {
                HStack {
                    Text("max. \(Int(prefs.maxCook)) min").font(Theme.F.callout).contentTransition(.numericText())
                    Spacer()
                    Stepper("", value: $prefs.persons, in: 1...20).labelsHidden()
                    Text("\(prefs.persons) Pers.").font(Theme.F.callout).contentTransition(.numericText()).frame(width: 64, alignment: .trailing)
                }
                Slider(value: $prefs.maxCook, in: 10...120, step: 5).tint(Theme.C.kcal)
            }
            if showDiet {
                section("🥗", "Ernährung & Allergien") {
                    ChipFlow(items: Labels.diets.map { ($0.0, $0.1) }, selected: [prefs.diet]) { prefs.diet = $0 }
                    // feste Allergien + eigene (19.2: „Meine Allergie war nicht dabei“)
                    let custom = prefs.allergies.subtracting(Labels.allergies).sorted()
                    ChipFlow(items: (Labels.allergies + custom).map { ($0, $0) }, selected: prefs.allergies, color: Theme.C.protein) { prefs.allergies.formSymmetricDifference([$0]) }
                    TextField("Andere Allergie, z.B. Senf", text: $newAllergy)
                        .submitLabel(.done)
                        .onSubmit {
                            let a = newAllergy.trimmingCharacters(in: .whitespaces)
                            if !a.isEmpty { prefs.allergies.insert(a) }
                            newAllergy = ""
                        }
                        .padding(12).background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.chip))
                    TextField("Mag ich nicht, z.B. Koriander, Pilze", text: $prefs.dislikes)
                        .padding(12).background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.chip))
                }
                section("🔁", "Immer statt") {
                    ForEach(prefs.productRules, id: \.self) { r in
                        HStack {
                            Text("\(r.use) statt \(r.instead)").font(Theme.F.callout)
                            Spacer()
                            Button {
                                prefs.productRules.removeAll { $0 == r }
                            } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.C.text3).frame(minWidth: 44, minHeight: 44) }
                            .accessibilityLabel("Regel \(r.use) statt \(r.instead) löschen")
                        }
                    }
                    HStack(spacing: 8) {
                        TextField("Hafermilch", text: $use)
                            .padding(12).background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.chip))
                        Text("statt").font(Theme.F.callout)
                        TextField("Milch", text: $instead)
                            .padding(12).background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.chip))
                        Button {
                            let r = ProductRuleDTO(instead: instead.trimmingCharacters(in: .whitespaces), use: use.trimmingCharacters(in: .whitespaces))
                            if !r.instead.isEmpty, !r.use.isEmpty, !prefs.productRules.contains(r) { prefs.productRules.append(r) }
                            instead = ""; use = ""
                        } label: { Image(systemName: "plus.circle.fill").font(.title2).frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Regel hinzufügen")
                    }
                }
            }
        }
    }

    private func section(_ emoji: String, _ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label { Text(title).font(Theme.F.headline) } icon: { Text(emoji) }
            content()
        }
        .padding(16)
        .card()
    }
}

/// Einstellungen › Präferenzen: jederzeit änderbar, speichert als Standard.
struct PreferencesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var prefs = Prefs()
    @State private var variety = VarietyDTO()  // Abwechslung (12)
    @State private var saving = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.C.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                    DisplayHeader(line1: "Präferenzen", line2: "für deine Pläne")
                    PreferencesForm(prefs: $prefs)
                    VarietyForm(rules: $variety)
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 16)
            }
            .defaultScrollAnchor(Demo.screen == "variety" ? .bottom : .top)  // Demo: Abwechslung im Bild
            .scrollDismissesKeyboard(.immediately)
            .ctaBar {
            Button {
                saving = true
                Task {
                    defer { saving = false }
                    do {
                        var patch = prefs.patch
                        patch.variety = variety
                        try await store.save(patch)
                        store.flash("Präferenzen gespeichert")
                        dismiss()
                    } catch {
                        store.flash(error.localizedDescription)
                    }
                }
            } label: { Text(saving ? "Speichere …" : "Speichern") }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(saving)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if let h = store.household { prefs = Prefs(h); variety = h.variety ?? VarietyDTO() }
        }
    }
}
