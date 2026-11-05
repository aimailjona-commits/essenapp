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

/// Abschnitte der Präferenzen; Einstellungs-Zeilen springen direkt dorthin (S13).
enum PrefsSection: String, Hashable {
    case persons, diet, meals, cuisines, budget, goal
}

/// Formular der Präferenzen (ohne eigenes Mockup: Abschnitte mit `.lbl`, Chips, Regler, Zeilen wie S6/S13).
struct PreferencesForm: View {
    @Binding var prefs: Prefs
    var showDiet = true
    @State private var newAllergy = ""
    @State private var instead = ""
    @State private var use = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            label("Mahlzeiten & Tage").id(PrefsSection.meals)
            ChipFlow(items: Labels.mealTypes, selected: prefs.mealTypes) { prefs.mealTypes.formSymmetricDifference([$0]) }
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { d in
                    let on = prefs.planDays.contains(d)
                    Button { withAnimation(Theme.spring) { prefs.planDays.formSymmetricDifference([d]) } } label: {
                        Text(Labels.days[d]).font(Theme.F.text(13, .extrabold, relativeTo: .footnote))
                            .foregroundStyle(on ? Theme.C.onInk : Theme.C.ink3)
                            .frame(maxWidth: .infinity).frame(height: 38)
                            .background(on ? Theme.C.ink : .clear, in: Circle())
                            .overlay { if !on { Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
                            .frame(minHeight: 44).contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(Labels.dayNames[d])
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.top, 10)
            .sensoryFeedback(.selection, trigger: prefs.planDays)

            label("Küchen (leer = gemischt)").id(PrefsSection.cuisines)
            ChipFlow(items: Labels.cuisines.map { ($0, $0) }, selected: prefs.cuisines) { prefs.cuisines.formSymmetricDifference([$0]) }

            StatNumber(label: "Budget pro Woche", value: euro(Int(prefs.budgetEuro) * 100), size: 52).padding(.top, 28).id(PrefsSection.budget)
            ERange(value: $prefs.budgetEuro, range: 20...200, step: 5, label: "Budget pro Woche").padding(.top, 8)

            label("Ziel").id(PrefsSection.goal)
            Segmented8(options: Labels.goals.map { ($0.0, $0.1) }, selection: $prefs.goal)
            StatNumber(label: "Kochzeit", value: "max. \(Int(prefs.maxCook)) min", size: 40).padding(.top, 28)
            ERange(value: $prefs.maxCook, range: 10...120, step: 5, label: "Kochzeit in Minuten").padding(.top, 8)
            ERow("Personen", lead: .icon(.users), tint: Theme.C.blue1, chevron: false) {
                Stepper8(value: $prefs.persons, range: 1...20)
            }
            .padding(.top, 28).id(PrefsSection.persons)

            if showDiet {
                label("Ernährung").id(PrefsSection.diet)
                ChipFlow(items: Labels.diets.map { ($0.0, $0.1) }, selected: [prefs.diet]) { prefs.diet = $0 }
                label("Allergien")
                // feste Allergien + eigene (19.2: „Meine Allergie war nicht dabei“)
                let custom = prefs.allergies.subtracting(Labels.allergies).sorted()
                ChipFlow(items: (Labels.allergies + custom).map { ($0, $0) }, selected: prefs.allergies) { prefs.allergies.formSymmetricDifference([$0]) }
                FieldBox(icon: .plus) {
                    TextField("Andere Allergie, z. B. Senf", text: $newAllergy)
                        .submitLabel(.done)
                        .onSubmit {
                            let a = newAllergy.trimmingCharacters(in: .whitespaces)
                            if !a.isEmpty { prefs.allergies.insert(a) }
                            newAllergy = ""
                        }
                }
                .padding(.top, 10)
                label("Mag ich nicht")
                FieldBox { TextField("z. B. Koriander, Pilze", text: $prefs.dislikes) }
                label("Immer statt")
                ForEach(prefs.productRules, id: \.self) { r in
                    ERow("\(r.use) statt \(r.instead)", chevron: false) {
                        CircleButton(icon: .x, label: "Regel \(r.use) statt \(r.instead) löschen") { prefs.productRules.removeAll { $0 == r } }
                    }
                }
                HStack(spacing: 8) {
                    FieldBox { TextField("Hafermilch", text: $use) }
                    Text("statt").font(Theme.F.text(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2)
                    FieldBox { TextField("Milch", text: $instead) }
                    CircleButton(icon: .plus, filled: true, label: "Regel hinzufügen") {
                        let r = ProductRuleDTO(instead: instead.trimmingCharacters(in: .whitespaces), use: use.trimmingCharacters(in: .whitespaces))
                        if !r.instead.isEmpty, !r.use.isEmpty, !prefs.productRules.contains(r) { prefs.productRules.append(r) }
                        instead = ""; use = ""
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private func label(_ text: String) -> some View {
        SectionLabel(text).padding(.top, 28).padding(.bottom, 8)
    }
}

/// Einstellungen › Präferenzen: jederzeit änderbar, speichert als Standard. `focus` springt zum Abschnitt der Zeile.
struct PreferencesView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var focus: PrefsSection?
    @State private var prefs = Prefs()
    @State private var saving = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    EBack()
                    Text("Präferenzen").font(Theme.F.t1).padding(.top, 10)
                    Text("für deine Pläne").font(Theme.F.text(14, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2)
                    PreferencesForm(prefs: $prefs)
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.immediately)
            .onAppear {
                if let h = store.household { prefs = Prefs(h) }
                if let focus { proxy.scrollTo(focus, anchor: .top) }
            }
        }
        .ctaBar(bottom: 34) {
            PrimaryButton(title: saving ? "Speichere …" : "Speichern", disabled: saving) {
                saving = true
                Task {
                    defer { saving = false }
                    do {
                        try await store.save(prefs.patch)
                        store.flash("Präferenzen gespeichert")
                        dismiss()
                    } catch {
                        store.flash(error.localizedDescription)
                    }
                }
            }
        }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
    }
}

/// Präferenzen › Abwechslung (e.html): drei Gruppen ohne Überschrift, nur durch Luft getrennt; Werte im Stepper.
struct VarietyView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var rules = VarietyDTO()
    @State private var saving = false

    // Mockup-Maße: Kreis sage rechts −110 / oben −130, Basilikum rechts 0 / oben 26
    private let blob = (right: CGFloat(-110), top: CGFloat(-130), size: CGFloat(300))
    private let ill = (right: CGFloat(0), top: CGFloat(26), width: CGFloat(140))
    private let introWidth: CGFloat = 250
    private let rowHeight: CGFloat = 52

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EBack()
                Text("Abwechslung").font(Theme.F.t1).padding(.top, 10)
                Text("Der Planer hält diese Regeln ein – Verstöße zeigt der Plan-Kopf.")
                    .font(Theme.F.text(14, relativeTo: .subheadline)).lineSpacing(4).foregroundStyle(Theme.C.ink2)
                    .frame(maxWidth: introWidth, alignment: .leading).padding(.top, 4)
                group {
                    row("Pasta", "höchstens pro Woche", $rules.maxPasta, 0...14) { "\($0)×" }
                    row("Reis", "höchstens pro Woche", $rules.maxRice, 0...14) { "\($0)×" }
                    row("Kartoffeln", "höchstens pro Woche", $rules.maxPotato, 0...14) { "\($0)×" }
                }
                group {
                    row("Fisch", "mindestens pro Woche", $rules.minFish, 0...3) { "\($0)×" }
                    row("Vegetarische Tage", "pro Woche", $rules.veggieDays, 0...7) { "\($0)" }
                    row("Rotes Fleisch", "höchstens pro Woche", $rules.maxRedMeat, 0...14) { "\($0)×" }
                }
                group {
                    row("Gleiches Gericht", "frühestens nach Wochen", $rules.repeatWeeks, 1...12) { "\($0)" }
                    ERow("Gleiche Küche nicht zwei Tage hintereinander", chevron: false, minHeight: rowHeight) {
                        ESwitch(isOn: $rules.noSameCuisineRow, label: "Gleiche Küche nicht zwei Tage hintereinander")
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .background(alignment: .topTrailing) {
            Color.clear
                .pinned(right: ill.right, top: ill.top) { Ill("basil").frame(width: ill.width) }
                .edgeForm(.circle, Theme.C.sage, width: blob.size, height: blob.size, right: blob.right, top: blob.top)
                .ignoresSafeArea()
        }
        .ctaBar(bottom: 34) {
            PrimaryButton(title: saving ? "Speichere …" : "Speichern", disabled: saving) {
                saving = true
                Task {
                    defer { saving = false }
                    do {
                        try await store.save(HouseholdPatch(variety: rules))
                        store.flash("Abwechslung gespeichert")
                        dismiss()
                    } catch {
                        store.flash(error.localizedDescription)
                    }
                }
            }
        }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
        .onAppear { rules = store.household?.variety ?? VarietyDTO() }
    }

    private func group(@ViewBuilder _ rows: () -> some View) -> some View {
        VStack(spacing: 0) { rows() }.padding(.top, 28)
    }

    private func row(_ title: String, _ sub: String, _ value: Binding<Int>, _ range: ClosedRange<Int>,
                     _ text: @escaping (Int) -> String) -> some View {
        ERow(title, sub: sub, chevron: false, minHeight: rowHeight) {
            Stepper8(value: value, range: range, format: text)
        }
    }
}
