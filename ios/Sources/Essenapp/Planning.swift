import SwiftUI

// Clever planen (Phase 11): Abwechslung (12), Gäste (15), „Keine Lust“ (16), Generator nach Push (17), Reste (19),
// Frühstück & Snacks (23), Lunchbox (24), Feiertage & Saison (25).

// MARK: Modelle (= backend/app/schemas.py)

/// Abwechslungsregeln (12), Standardwerte laut Spezifikation.
struct VarietyDTO: Codable, Equatable {
    var maxPasta = 1
    var maxRice = 2
    var maxPotato = 2
    var minFish = 1
    var veggieDays = 2
    var maxRedMeat = 2
    var repeatWeeks = 3
    var noSameCuisineRow = true
}

struct VarietyCheckDTO: Codable, Hashable {
    var ok: Bool
    var issues: [String]  // „2× Pasta“, „kein Fisch“ …
}

struct RestBadgeDTO: Codable, Hashable {
    var name: String
    var fromDay: Int  // „♻︎ Rest von Mo“
}

struct LeftoverDTO: Codable, Hashable {
    var name: String
    var amount: Double
    var unit: String
    var untilDay: Int
    var suggestion: String
}

struct LeftoversDTO: Codable, Hashable {
    var planned: Int
    var left: [LeftoverDTO]
}

struct GuestSlot: Encodable, Hashable {
    var day: Int
    var mealType: String
    var count: Int
}

/// Erwarteter Rest nach dem Kochen (19).
struct EntryLeftoverDTO: Decodable, Hashable {
    var name: String
    var amount: Double
    var unit: String
    var bestBefore: String?
}

/// Special-Vorlage bzw. Start-Banner (25); `text` nur beim Banner.
struct SpecialDTO: Decodable, Hashable, Identifiable {
    var key: String
    var name: String
    var emoji: String
    var date: String
    var daysUntil: Int
    var template: String  // festtagsmenue | plaetzchen | grillparty
    var templateName: String
    var running: Bool
    var text: String?
    var id: String { key }
}

struct SpecialsDTO: Decodable {
    var banner: SpecialDTO?
    var specials: [SpecialDTO]
}

/// GET /plans/generator (17): KW + Top-3-Angebote; die Standards sind die des Haushalts.
struct GeneratorDTO: Decodable {
    var week: Int
    var topOffers: [OfferDTO]
    var banner: SpecialDTO?
}

struct WeeklyBasicDTO: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var amount: Double?  // Wochenmenge, nil = ohne Menge (z. B. Brot)
    var unit: String
}

/// Body für POST/PATCH /weekly-basics; `amount` immer gesendet (null = ohne Menge).
struct WeeklyBasicIn: Encodable {
    var name: String
    var amount: Double?
    var unit: String

    enum CodingKeys: String, CodingKey { case name, amount, unit }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(amount, forKey: .amount)
        try c.encode(unit, forKey: .unit)
    }
}

// MARK: Server

extension AppStore {
    /// „Gäste hinzufügen“ nachträglich (15): Mengen, Kosten und Liste neu – ohne KI.
    func setGuests(_ meal: MealDTO, _ count: Int) async -> Bool {
        guard let id = meal.id else { return false }
        struct Body: Encodable { var count: Int }
        do {
            if demo {
                if var p = plan, let i = p.entries.firstIndex(where: { e in e.id == id }) { p.entries[i].guests = count; plan = p }
            } else {
                plan = try await api.request("POST", "/plans/current/entries/\(id)/guests", body: Body(count: count), timeout: 60)
                await loadLists()
                await loadNutrition()
            }
            return true
        } catch APIError.http(422) {
            flash("Bei dieser Mahlzeit isst dann niemand mit")
        } catch {
            flash("Nicht angepasst: \(error.localizedDescription)")
        }
        return false
    }

    /// „Keine Lust“ (16): 3 Gerichte ≤ 15 min ohne Einkauf; `exclude` = schon gezeigte Titel.
    func noMood(exclude: [String]) async throws -> [CookIdeaDTO] {
        struct Body: Encodable { var exclude: [String] }
        if demo { return Demo.noMood(page: exclude.count / 3) }
        return try await api.request("POST", "/no-mood", body: Body(exclude: Array(exclude.suffix(30))), timeout: 60)
    }

    /// „Auf morgen verschieben?“: ursprüngliches Gericht auf `day`, spätere derselben Mahlzeit rücken weiter.
    func postpone(_ meal: MealDTO, to day: Int) async -> Bool {
        struct Body: Encodable { var recipeId: Int; var day: Int; var mealType: String }
        do {
            if !demo {
                plan = try await api.request("POST", "/plans/current/postpone",
                                             body: Body(recipeId: meal.recipe.id, day: day, mealType: meal.mealType), timeout: 60)
                await loadLists()
                await loadNutrition()
            }
            return true
        } catch {
            flash("Nicht verschoben: \(error.localizedDescription)")
            return false
        }
    }

    /// Erwartete Reste nach dem Kochen eines Plan-Gerichts (19).
    func entryLeftovers(_ meal: MealDTO) async -> [EntryLeftoverDTO] {
        guard let id = meal.id else { return [] }
        if demo { return Demo.entryLeftovers }
        return (try? await api.request("GET", "/plans/current/entries/\(id)/leftovers")) ?? []
    }

    func generatorInfo() async -> GeneratorDTO? {
        demo ? Demo.generator : try? await api.request("GET", "/plans/generator", timeout: 30)
    }

    func specials() async -> SpecialsDTO? {
        demo ? Demo.specials : try? await api.request("GET", "/specials")
    }

    // Frühstück & Snacks (23a)

    func weeklyBasics() async throws -> [WeeklyBasicDTO] {
        demo ? Demo.weeklyBasics : try await api.request("GET", "/weekly-basics")
    }

    func saveWeeklyBasic(id: Int?, _ body: WeeklyBasicIn) async throws {
        guard !demo else { return }
        let _: WeeklyBasicDTO = try await api.request(id == nil ? "POST" : "PATCH", id.map { i in "/weekly-basics/\(i)" } ?? "/weekly-basics", body: body)
    }

    func deleteWeeklyBasic(_ id: Int) async throws {
        if !demo { try await api.send("DELETE", "/weekly-basics/\(id)") }
    }

    /// Sofort auf die Haushaltsliste (sonst montags 06:30 automatisch).
    func basicsToList() async {
        do {
            if !demo { try await api.send("POST", "/weekly-basics/to-list", timeout: 30) }
            await loadLists()
            flash("Basics stehen auf der Liste")
        } catch {
            flash("Nicht auf die Liste: \(error.localizedDescription)")
        }
    }
}

// MARK: 12 Abwechslung

/// Einstellungen › Präferenzen › „Abwechslung“: Karten mit Steppern/Schalter.
struct VarietyForm: View {
    @Binding var rules: VarietyDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label { Text("Abwechslung").font(Theme.F.headline) } icon: { Text("🔄") }
                Text("Der Planer hält diese Regeln ein – Verstöße zeigt der Plan-Kopf.").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            }
            .padding(.top, 6)
            card("🍝", "Beilagen pro Woche") {
                row("Pasta höchstens", $rules.maxPasta, 0...14) { n in "\(n)×" }
                row("Reis höchstens", $rules.maxRice, 0...14) { n in "\(n)×" }
                row("Kartoffeln höchstens", $rules.maxPotato, 0...14) { n in "\(n)×" }
            }
            card("🐟", "Fisch, Fleisch, Gemüse") {
                row("Fisch mindestens", $rules.minFish, 0...3) { n in "\(n)×" }
                row("Vegetarische Tage", $rules.veggieDays, 0...7) { n in n == 1 ? "1 Tag" : "\(n) Tage" }
                row("Rotes Fleisch höchstens", $rules.maxRedMeat, 0...14) { n in "\(n)×" }
            }
            card("🔁", "Wiederholungen") {
                row("Gleiches Gericht frühestens nach", $rules.repeatWeeks, 1...12) { n in n == 1 ? "1 Woche" : "\(n) Wochen" }
                Toggle("Gleiche Küche nicht zwei Tage hintereinander", isOn: $rules.noSameCuisineRow)
                    .font(Theme.F.callout).tint(Theme.C.accent)
                    .sensoryFeedback(.selection, trigger: rules.noSameCuisineRow)
            }
        }
    }

    private func card(_ emoji: String, _ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label { Text(title).font(Theme.F.callout).foregroundStyle(Theme.C.text2) } icon: { Text(emoji) }
            content()
        }
        .padding(16)
        .card()
    }

    private func row(_ title: String, _ value: Binding<Int>, _ range: ClosedRange<Int>, _ text: @escaping (Int) -> String) -> some View {
        HStack(spacing: 10) {
            Text(title).font(Theme.F.callout)
            Spacer(minLength: 4)
            Text(text(value.wrappedValue)).font(.system(.headline, design: .rounded, weight: .bold)).monospacedDigit()
                .contentTransition(.numericText())
            Stepper(title, value: value, in: range).labelsHidden()
        }
        .animation(Theme.spring, value: value.wrappedValue)
        .sensoryFeedback(.selection, trigger: value.wrappedValue)
    }
}

/// Chip im Plan-Kopf: „✓ Abwechslung“ oder „⚠ 2× Pasta“ (weitere Verstöße im Menü).
struct VarietyChip: View {
    let check: VarietyCheckDTO

    var body: some View {
        let color = check.ok ? Theme.C.success : Theme.C.warning
        let label = HStack(spacing: 4) {
            Text(check.ok ? "✓ Abwechslung" : "⚠ \(check.issues.first ?? "Abwechslung")")
            if check.issues.count > 1 {
                Text("+\(check.issues.count - 1)").foregroundStyle(Theme.C.text2)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
        }
        .font(Theme.F.micro)
        .foregroundStyle(check.ok ? Theme.C.success : Theme.C.text1)
        .padding(.horizontal, 10).frame(height: 28)
        .background(color.opacity(0.16), in: Capsule())
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        Group {
            if check.issues.count > 1 {
                Menu { ForEach(check.issues, id: \.self) { i in Text("⚠ \(i)") } } label: { label }
            } else {
                label
            }
        }
        .accessibilityLabel(check.ok ? "Abwechslung eingehalten" : "Abwechslung: \(check.issues.joined(separator: ", "))")
        .animation(Theme.spring, value: check)
    }
}

// MARK: 19 Reste

/// Plan-Kopf: „Reste: 3 verplant, 1 übrig (Sahne 100 ml)“ mit Vorschlag.
struct LeftoversCard: View {
    let leftovers: LeftoversDTO

    var body: some View {
        let left = leftovers.left
        let rest = left.isEmpty ? "nichts übrig" : "\(left.count) übrig (\(left.map { l in "\(l.name) \(qty(l.amount, l.unit))" }.joined(separator: ", ")))"
        HStack(alignment: .top, spacing: 12) {
            Text("♻︎").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.C.success)
                .frame(width: 40, height: 40)
                .background(Theme.C.successSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Reste: \(leftovers.planned) verplant, \(rest)").font(Theme.F.callout)
                ForEach(left, id: \.self) { l in
                    Text("\(l.name): \(l.suggestion)").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .card(radius: Theme.R.tile)
        .accessibilityElement(children: .combine)
    }
}

/// Zeile im Vorrats-Dialog „Reste in den Vorrat?“.
struct RestRow: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var amount: String
    var unit: String
    var bestBefore: String?
    var checked = true

    init(_ r: EntryLeftoverDTO) {
        name = r.name
        amount = num(r.amount, 0...2).replacingOccurrences(of: ".", with: "")  // ohne Tausenderpunkt
        unit = ["", "g", "ml", "stk"].contains(r.unit) ? r.unit : ""
        bestBefore = r.bestBefore
    }
}

/// S30 Nach dem Kochen (im Bewertungs-Sheet): tatsächliche Reste bestätigen → Vorrat (`source: rest`).
struct RestsConfirmView: View {
    @Environment(AppStore.self) private var store
    @State private var rows: [RestRow]
    @State private var saving = false
    let done: () -> Void

    init(rows: [RestRow], done: @escaping () -> Void) {
        _rows = State(initialValue: rows)
        self.done = done
    }

    var body: some View {
        let chosen = rows.filter { r in r.checked && !r.name.trimmingCharacters(in: .whitespaces).isEmpty }
        VStack(alignment: .leading, spacing: 12) {
            Text("Reste in den Vorrat?").font(Theme.F.title)
            Text("Von angebrochenen Packungen bleibt etwas übrig – Menge prüfen, dann übernehmen.")
                .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach($rows) { $r in row($r).appear() }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            Button(action: save) {
                Text(saving ? "Übernehme …" : chosen.isEmpty ? "Nichts ausgewählt" : "\(chosen.count) in den Vorrat").contentTransition(.numericText())
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(chosen.isEmpty || saving).opacity(chosen.isEmpty ? 0.5 : 1)
            Button("Nichts übrig", action: done).buttonStyle(SecondaryButtonStyle())
        }
        .padding(Theme.pagePadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.C.bg)
        .transition(.opacity)
    }

    private func row(_ r: Binding<RestRow>) -> some View {
        let probe = PantryDTO(id: 0, name: r.wrappedValue.name, ingredientKey: "", amount: nil, unit: "", bestBefore: r.wrappedValue.bestBefore,
                              isBasic: false, source: "rest", updatedAt: "")
        return HStack(spacing: 10) {
            Button { withAnimation(Theme.spring) { r.wrappedValue.checked.toggle() } } label: {
                Image(systemName: r.wrappedValue.checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24)).foregroundStyle(r.wrappedValue.checked ? Theme.C.accent : Theme.C.text3)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PressableStyle())
            .sensoryFeedback(.selection, trigger: r.wrappedValue.checked)
            .accessibilityLabel(r.wrappedValue.checked ? "\(r.wrappedValue.name) übernehmen" : "\(r.wrappedValue.name) nicht übernehmen")
            Text(probe.emoji).font(.system(size: 20))
                .frame(width: 40, height: 40)
                .background(Theme.hue(category: probe.category).tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(r.wrappedValue.name).font(.system(.body, weight: .semibold)).lineLimit(1)
                if let d = probe.daysLeft { ExpiryChip(days: d) }
            }
            Spacer(minLength: 4)
            TextField("Menge", text: r.amount).keyboardType(.decimalPad)
                .font(Theme.F.callout).monospacedDigit().multilineTextAlignment(.center)
                .frame(width: 64, height: 36).background(Theme.C.surface, in: Capsule())
            Text(r.wrappedValue.unit.isEmpty ? "" : Labels.unit(r.wrappedValue.unit)).font(Theme.F.caption).foregroundStyle(Theme.C.text2)
        }
        .padding(10)
        .card(radius: Theme.R.tile)
        .opacity(r.wrappedValue.checked ? 1 : 0.6)
    }

    private func save() {
        let body = rows.filter { r in r.checked && !r.name.trimmingCharacters(in: .whitespaces).isEmpty }.map { r in
            PantryIn(name: String(r.name.prefix(100)), amount: Double(r.amount.replacingOccurrences(of: ",", with: ".")).map { a in min(max(a, 0), 100_000) },
                     unit: r.unit, bestBefore: r.bestBefore, isBasic: false, source: "rest")
        }
        saving = true
        Task {
            defer { saving = false }
            do {
                try await store.addPantryBulk(body)
                store.flash(body.count == 1 ? "1 Rest im Vorrat" : "\(body.count) Reste im Vorrat")
                done()
            } catch {
                store.flash("Nicht übernommen: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: Badges am Gericht (15, 19, 24)

/// Unter einem Plan-Gericht: „🥡 Lunchbox · Jona“, „♻︎ Rest von Mo“, „+4 Gäste“ (antippen → Gäste-Sheet).
struct MealBadges: View {
    @Environment(AppStore.self) private var store
    let meal: MealDTO
    var onGuests: (() -> Void)?

    var body: some View {
        let days = (meal.rests ?? []).map(\.fromDay).filter { d in Labels.days.indices.contains(d) }.uniqued()
        let guests = meal.guests ?? 0
        let lunch = meal.mealType == "lunchbox"
        if lunch || !days.isEmpty || guests > 0 || onGuests != nil {
            let names = store.profiles.filter { p in meal.portions.contains { x in x.memberId == p.memberId } }.map(\.name)
            FlowLayout(spacing: 6) {
                if lunch { DealBadge(text: names.isEmpty ? "🥡 Lunchbox" : "🥡 Lunchbox · \(names.joined(separator: ", "))", style: .ok) }
                ForEach(days, id: \.self) { d in DealBadge(text: "♻︎ Rest von \(Labels.days[d])", style: .ok) }
                if let onGuests {
                    Button(action: onGuests) {
                        Label(guests > 0 ? "+\(guests) Gäste" : "Gäste", systemImage: "person.badge.plus")
                            .font(Theme.F.micro).foregroundStyle(guests > 0 ? Theme.C.accentDeep : Theme.C.text1)
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(guests > 0 ? Theme.C.accentSoft : Theme.C.surface, in: Capsule())
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(guests > 0 ? "\(guests) Gäste, ändern" : "Gäste hinzufügen")
                } else if guests > 0 {
                    DealBadge(text: "+\(guests) Gäste", style: .soft)
                }
            }
        }
    }
}

// MARK: 15 Gäste

/// S28 „Gäste hinzufügen“ (aus dem Wochenplan): Stepper 0–20, Mengen + Liste werden ohne KI angepasst.
struct GuestsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let meal: MealDTO
    @State private var count: Int
    @State private var saving = false

    init(meal: MealDTO) {
        self.meal = meal
        _count = State(initialValue: meal.guests ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gäste hinzufügen").font(Theme.F.title)
                    Text("\(Labels.dayNames[max(0, min(meal.day, 6))]) · \(Labels.meal(meal.mealType)): „\(meal.recipe.title)“")
                        .font(Theme.F.caption).foregroundStyle(Theme.C.text2).lineLimit(2)
                }
                Spacer()
                RoundIconButton(systemName: "xmark", label: "Schließen") { dismiss() }
            }
            HStack(spacing: 12) {
                Text("👥").font(.system(size: 26)).frame(width: 52, height: 52)
                    .background(Theme.C.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("+\(count)").font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    Text(count == 1 ? "Gast" : "Gäste").font(Theme.F.callout).foregroundStyle(Theme.C.text2)
                }
                Spacer()
                Stepper("Gäste", value: $count, in: 0...20).labelsHidden()
            }
            .padding(16)
            .card()
            .animation(Theme.spring, value: count)
            .sensoryFeedback(.selection, trigger: count)
            Text("Mengen, Kosten und Einkaufsliste werden angepasst – ohne neue KI-Planung.")
                .font(Theme.F.micro).foregroundStyle(Theme.C.text2)
            Button(saving ? "Passe an …" : "Übernehmen") {
                saving = true
                Task {
                    defer { saving = false }
                    guard await store.setGuests(meal, count) else { return }
                    store.flash(count == 0 ? "Gäste entfernt" : "Für +\(count) \(count == 1 ? "Gast" : "Gäste") angepasst")
                    dismiss()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(saving || count == (meal.guests ?? 0))
            .opacity(count == (meal.guests ?? 0) ? 0.5 : 1)
        }
        .padding(Theme.pagePadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.C.bg)
    }
}

/// Plan-Generator: „+ Gäste“ je Tag/Mahlzeit; Tagespillen zeigen „+4“. Optional „Gäste-Budget extra“.
struct GuestPlanner: View {
    @Binding var guests: [String: Int]  // "Tag|Mahlzeit" → Anzahl
    @Binding var extraEuro: Double?  // nil = aus dem Wochenbudget
    let days: [Int]
    let meals: [String]
    @State private var day: Int?

    static func key(_ day: Int, _ meal: String) -> String { "\(day)|\(meal)" }

    /// Nur Slots, die im Plan vorkommen (abgewählte Tage/Mahlzeiten fallen weg).
    static func slots(_ guests: [String: Int], days: [Int], meals: [String]) -> [GuestSlot] {
        days.flatMap { d in meals.compactMap { m in
            let n = guests[key(d, m)] ?? 0
            return n > 0 ? GuestSlot(day: d, mealType: m, count: n) : nil
        } }
    }

    var body: some View {
        let selected = day.flatMap { d in days.contains(d) ? d : nil } ?? days.last ?? 0
        let total = Self.slots(guests, days: days, meals: meals).map(\.count).reduce(0, +)
        VStack(alignment: .leading, spacing: 10) {
            Label { Text("Gäste").font(Theme.F.headline) } icon: { Text("👥") }
            Text("Tag wählen, dann „+ Gäste“ je Mahlzeit – Mengen und Kosten wachsen mit.")
                .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { d in
                    let on = d == selected
                    let active = days.contains(d)
                    let n = meals.map { m in guests[Self.key(d, m)] ?? 0 }.reduce(0, +)
                    Button { withAnimation(Theme.spring) { day = d } } label: {
                        Text(Labels.days[d]).font(.system(.caption, design: .rounded, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .foregroundStyle(on ? Theme.C.onAction : Theme.C.text1)
                            .background(on ? Theme.C.action : Theme.C.surface, in: Circle())
                            .overlay(alignment: .topTrailing) {
                                if n > 0 && active {
                                    Text("+\(n)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                        .padding(.horizontal, 5).frame(height: 18)
                                        .background(Theme.C.accent, in: Capsule())
                                        .offset(x: 6, y: -6)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(!active).opacity(active ? 1 : 0.35)
                    .accessibilityLabel("\(Labels.dayNames[d])\(n > 0 ? ", \(n) Gäste" : "")")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: selected)
            ForEach(meals, id: \.self) { m in
                let k = Self.key(selected, m)
                let n = guests[k] ?? 0
                HStack(spacing: 10) {
                    Text(Labels.meal(m)).font(Theme.F.callout)
                    Spacer()
                    Text(n == 0 ? "keine Gäste" : "+\(n) \(n == 1 ? "Gast" : "Gäste")")
                        .font(Theme.F.caption).monospacedDigit().foregroundStyle(n == 0 ? Theme.C.text3 : Theme.C.accentDeep)
                        .contentTransition(.numericText())
                    Stepper("Gäste \(Labels.meal(m))", value: Binding(get: { n }, set: { v in guests[k] = v }), in: 0...20).labelsHidden()
                }
                .animation(Theme.spring, value: n)
                .sensoryFeedback(.selection, trigger: n)
            }
            if total > 0 {
                Divider()
                Toggle("Gäste-Budget extra", isOn: Binding(get: { extraEuro != nil }, set: { on in
                    withAnimation(Theme.spring) { extraEuro = on ? 20 : nil }
                }))
                .font(Theme.F.callout).tint(Theme.C.accent)
                if let euroValue = extraEuro {
                    HStack {
                        Text("+ \(euro(Int(euroValue) * 100))").font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                            .contentTransition(.numericText())
                        Spacer()
                    }
                    Slider(value: Binding(get: { euroValue }, set: { v in extraEuro = v }), in: 5...100, step: 5).tint(Theme.C.accent)
                } else {
                    Text("Ohne Extra-Budget zahlen die Gäste aus dem Wochenbudget.").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                }
            }
        }
        .padding(16)
        .card()
        .animation(Theme.spring, value: total)
    }
}

// MARK: 17 + 25 Generator-Zusätze, Start-Banner

/// Plan-Generator: „Diese Woche im Angebot: …“ (Top-3, 17).
struct TopOffersHint: View {
    let offers: [OfferDTO]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label { Text("Diese Woche im Angebot").font(Theme.F.headline) } icon: { Text("🏷️") }
            Text("Diese Woche im Angebot: \(offers.map(\.title).joined(separator: ", "))")
                .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(offers) { o in
                        MiniOffer(offer: o).overlay(alignment: .topLeading) {
                            if let d = o.discount { DealBadge(text: "−\(d) %").padding(6) }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(16)
        .card()
    }
}

/// Plan-Generator: Special-Vorlage wählen (Festtagsmenü, Plätzchen-Back-Plan, Grillparty).
struct SpecialPicker: View {
    let specials: [SpecialDTO]
    @Binding var selected: String?

    static let templates = ["festtagsmenue": "Vorspeise, Hauptgang und Dessert am Tag des Anlasses",
                            "plaetzchen": "Backen am Samstag und Sonntag",
                            "grillparty": "Grillgut mit Beilagen am Samstagabend"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label { Text("Special").font(Theme.F.headline) } icon: { Text("✨") }
            ChipFlow(items: [("", "Ohne")] + specials.map { s in (s.key, "\(s.emoji) \(s.templateName)") },
                     selected: [selected ?? ""], color: Theme.C.accent) { k in selected = k.isEmpty ? nil : k }
            if let s = specials.first(where: { s in s.key == selected }) {
                Text("\(s.name) · \(Self.templates[s.template] ?? s.templateName)")
                    .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .card()
        .animation(Theme.spring, value: selected)
    }
}

/// Start-Banner 14 Tage vor einem Anlass (25): „🎄 Weihnachten in 12 Tagen – Menü planen?“ → Generator mit Vorlage.
struct SpecialBanner: View {
    let banner: SpecialDTO
    let open: () -> Void

    var body: some View {
        let text = banner.text ?? banner.name
        let title = text.hasPrefix(banner.emoji) ? String(text.dropFirst(banner.emoji.count)).trimmingCharacters(in: .whitespaces) : text
        Button(action: open) {
            HStack(spacing: 14) {
                Text(banner.emoji).font(.system(size: 26))
                    .frame(width: 52, height: 52)
                    .background(Theme.C.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.F.callout).multilineTextAlignment(.leading)
                    Text("\(banner.templateName) im Plan-Generator").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.C.text3)
            }
            .foregroundStyle(Theme.C.text1)
            .padding(16)
            .card()
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(text)
    }
}

// MARK: 16 „Keine Lust“

/// S27 „Keine Lust?“: 3 Ideen ≤ 15 min ohne Einkauf, wischen für 3 weitere; Auswahl ersetzt das heutige Gericht,
/// danach „Auf morgen verschieben?“ für das ursprüngliche.
struct NoMoodSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var pages: [[CookIdeaDTO]] = []
    @State private var page = 0
    @State private var loading = false
    @State private var error: String?
    @State private var empty = false  // Vorrat leer (422)
    @State private var exhausted = false  // keine weiteren Ideen
    @State private var busy: Int?
    @State private var planFor: RecipeDTO?
    @State private var moved: MealDTO?  // ursprüngliches Gericht → „Auf morgen verschieben?“
    @State private var moveDay = 0
    @State private var spin = false
    @State private var step = 0

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Keine Lust?").font(Theme.F.title)
                        Text("Schnell & ohne Einkauf · höchstens 15 min").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                    }
                    Spacer()
                    RoundIconButton(systemName: "xmark", label: "Schließen") { dismiss() }
                }
                .padding(.horizontal, Theme.pagePadding).padding(.top, 20)
                if pages.isEmpty {
                    first.padding(.horizontal, Theme.pagePadding)
                } else {
                    TabView(selection: $page) {
                        ForEach(pages.indices, id: \.self) { i in
                            ScrollView {
                                VStack(spacing: 12) {
                                    ForEach(Array(pages[i].enumerated()), id: \.element.id) { j, idea in card(idea).appear(delay: Double(j) * 0.08) }
                                }
                                .padding(.horizontal, Theme.pagePadding).padding(.bottom, 12)
                            }
                            .tag(i)
                        }
                        more.padding(.horizontal, Theme.pagePadding).tag(pages.count)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    Text(page < pages.count ? "Wischen für 3 weitere  ›" : "‹  zurück zu den Ideen")
                        .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                        .frame(maxWidth: .infinity).padding(.bottom, 12)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.C.bg)
            .toolbar(.hidden, for: .navigationBar)
        }
        .sensoryFeedback(.selection, trigger: page)
        .task { if pages.isEmpty && !loading { await load() } }
        .onChange(of: page) { _, p in
            if p == pages.count && !loading && !exhausted { Task { await load() } }
        }
        .confirmationDialog(moveTitle, isPresented: Binding(get: { moved != nil }, set: { on in if !on { moved = nil } }),
                            titleVisibility: .visible, presenting: moved) { m in
            Button(moveTitle.replacingOccurrences(of: "?", with: "")) {
                Task {
                    if await store.postpone(m, to: moveDay) { store.flash("„\(m.recipe.title)“ → \(Labels.dayNames[moveDay])") }
                    dismiss()
                }
            }
            Button("Nein, danke", role: .cancel) { dismiss() }
        } message: { m in
            Text("„\(m.recipe.title)“ – die Zutaten sind schon da. Spätere Gerichte rücken einen Tag weiter.")
        }
        .sheet(item: $planFor) { r in
            PlanSlotSheet(recipeId: r.id, title: r.title).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet)
        }
    }

    private var moveTitle: String {
        moveDay == (moved?.day ?? -2) + 1 ? "Auf morgen verschieben?" : "Auf \(Labels.dayNames[max(0, min(moveDay, 6))]) verschieben?"
    }

    /// Erste Seite: Laden, Fehler, leer.
    @ViewBuilder private var first: some View {
        if empty {
            EmptyState(emoji: "🧺", title: "Vorrat ist leer", text: "Trag ein, was du zu Hause hast – dann finden wir schnelle Ideen ohne Einkauf.")
        } else if let error {
            ErrorState(message: error) { Task { await load() } }
        } else if exhausted {
            EmptyState(emoji: "🤔", title: "Keine passende Idee", text: "Mit dem, was da ist, geht gerade nichts in 15 Minuten.")
        } else {
            let steps = ["Vorrat ansehen", "Ideen sammeln", "Prüfen, ob alles da ist"]
            VStack(spacing: 18) {
                Plate(url: nil, size: 140, seed: "keine lust")
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .onAppear { withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { spin = true } }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                        Label(s, systemImage: i < step ? "checkmark.circle.fill" : "circle.dotted")
                            .font(Theme.F.callout).foregroundStyle(i <= step ? Theme.C.text1 : Theme.C.text3)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
            }
            .padding(.top, 12)
            .task {
                while !Task.isCancelled && step < 2 {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation(Theme.spring) { step += 1 }
                }
            }
        }
    }

    /// Letzte Seite beim Wischen: lädt 3 weitere.
    @ViewBuilder private var more: some View {
        VStack(spacing: 14) {
            if let error {
                ErrorState(message: error) { Task { await load() } }
            } else if exhausted {
                EmptyState(emoji: "🤔", title: "Mehr fällt uns gerade nicht ein", text: "Wisch zurück und nimm eine der Ideen.")
            } else {
                SkeletonCard(height: 150)
                SkeletonCard(height: 150)
                Text("Weitere Ideen …").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func card(_ idea: CookIdeaDTO) -> some View {
        let r = idea.recipe
        return VStack(alignment: .leading, spacing: 12) {
            NavigationLink { SavedRecipeView(recipeId: r.id) } label: {
                HStack(spacing: 14) {
                    Plate(url: mediaURL(r.imageUrl), size: 76, seed: r.title)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.title).font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(Theme.C.text1)
                            .multilineTextAlignment(.leading)
                        Text("\(r.prepMinutes) min · \(r.servings) Portionen").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                        DealBadge(text: "Alles da ✓", style: .ok)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.C.text3)
                }
            }
            .buttonStyle(PressableStyle())
            Button { Task { await choose(r) } } label: {
                if busy == r.id { ProgressView().tint(.white) } else { Label("Das koche ich heute", systemImage: "flame.fill") }
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.C.accent))
            .disabled(busy != nil)
        }
        .padding(14)
        .card()
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let found = try await store.noMood(exclude: pages.flatMap { p in p.map(\.recipe.title) })
            if found.isEmpty { exhausted = true } else { withAnimation(Theme.spring) { pages.append(found) } }
        } catch APIError.http(422) {
            empty = true
        } catch APIError.http(502) {
            error = "Die Ideen-Suche ist gerade nicht erreichbar."
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Ersetzt das heutige Gericht; gibt es später noch einen freien Slot derselben Mahlzeit → „Auf morgen verschieben?“.
    private func choose(_ r: RecipeDTO) async {
        guard let original = store.todayMeal else { planFor = r; return }
        busy = r.id
        let ok = await store.replace(original, with: r.id)
        busy = nil
        guard ok else { return }
        store.flash("Heute: \(r.title)")
        let later = store.plan?.entries.filter { e in e.mealType == original.mealType && e.day > original.day && !e.locked }.map(\.day).min()
        guard let later else { dismiss(); return }
        moveDay = later
        moved = original
    }
}

// MARK: 23 Frühstück & Snacks

/// S29 Einstellungen › „Frühstück & Snacks“: feste Basics mit Wochenmenge, jeden Montag auf die Liste.
struct WeeklyBasicsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var basics: [WeeklyBasicDTO]?
    @State private var error: String?
    @State private var editing: WeeklyBasicDTO?
    @State private var adding = false
    @State private var sending = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.C.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                    HStack(alignment: .bottom) {
                        DisplayHeader(line1: "Frühstück", line2: "& Snacks")
                        RoundIconButton(systemName: "plus", dark: true, label: "Basic hinzufügen") { adding = true }
                    }
                    Text("Deine Basics kommen jeden Montag automatisch auf die Haushaltsliste – im Angebot, wenn es in deinen Läden günstiger ist; was im Vorrat ist, wird abgezogen.")
                        .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                    if let basics {
                        if basics.isEmpty {
                            EmptyState(emoji: "🥣", title: "Noch keine Basics",
                                       text: "Z. B. Haferflocken 1.000 g, Joghurt 1.000 g, Brot, Bananen 6 Stück.",
                                       buttonTitle: "Basic hinzufügen") { adding = true }
                        }
                        ForEach(Array(basics.enumerated()), id: \.element.id) { i, b in row(b).appear(delay: Double(i) * 0.04) }
                    } else if let error {
                        ErrorState(message: error) { Task { await load() } }
                    } else {
                        ForEach(0..<4, id: \.self) { _ in SkeletonCard(height: 68) }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 16)
            }
            .refreshable { await load() }
            .ctaBar {
                if basics?.isEmpty == false {
                    Button {
                        sending = true
                        Task { await store.basicsToList(); sending = false }
                    } label: { Label(sending ? "Kommt auf die Liste …" : "Jetzt auf die Liste", systemImage: "cart.badge.plus") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(sending)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .sheet(isPresented: $adding) { WeeklyBasicSheet(basic: nil) { Task { await load() } }.presentationDetents([.medium, .large]) }
        .sheet(item: $editing) { b in WeeklyBasicSheet(basic: b) { Task { await load() } }.presentationDetents([.medium, .large]) }
    }

    private func row(_ b: WeeklyBasicDTO) -> some View {
        let probe = PantryDTO(id: b.id, name: b.name, ingredientKey: "", amount: b.amount, unit: b.unit, bestBefore: nil, isBasic: false,
                              source: "", updatedAt: "")
        return Button { editing = b } label: {
            HStack(spacing: 12) {
                Text(probe.emoji).font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .background(Theme.hue(category: probe.category).tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(b.name).font(.system(.body, weight: .semibold)).foregroundStyle(Theme.C.text1).lineLimit(1)
                    Text(b.amount.map { a in "\(qty(a, b.unit.isEmpty ? "stk" : b.unit)) pro Woche" } ?? "ohne Menge · jede Woche")
                        .font(Theme.F.micro).monospacedDigit().foregroundStyle(Theme.C.text2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.C.text3)
            }
            .padding(12)
            .card(radius: Theme.R.tile)
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button("Löschen", systemImage: "trash", role: .destructive) { Task { await delete(b) } }
        }
    }

    private func load() async {
        do {
            let found = try await store.weeklyBasics()
            withAnimation(Theme.spring) { basics = found }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ b: WeeklyBasicDTO) async {
        do {
            try await store.deleteWeeklyBasic(b.id)
            withAnimation(Theme.spring) { basics?.removeAll { x in x.id == b.id } }
            store.flash("„\(b.name)“ entfernt")
        } catch {
            store.flash("Nicht gelöscht: \(error.localizedDescription)")
        }
    }
}

/// Basic anlegen/ändern: Name, Wochenmenge (optional), Einheit.
struct WeeklyBasicSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let basic: WeeklyBasicDTO?
    let changed: () -> Void
    @State private var name: String
    @State private var amount: String
    @State private var unit: String
    @State private var saving = false

    init(basic: WeeklyBasicDTO?, changed: @escaping () -> Void) {
        self.basic = basic
        self.changed = changed
        _name = State(initialValue: basic?.name ?? "")
        _amount = State(initialValue: basic?.amount.map { a in num(a, 0...2).replacingOccurrences(of: ".", with: "") } ?? "")
        _unit = State(initialValue: basic?.unit ?? "g")
    }

    private var trimmed: String { String(name.trimmingCharacters(in: .whitespaces).prefix(100)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(basic == nil ? "Neues Basic" : "Basic ändern").font(Theme.F.title)
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Name, z. B. Haferflocken", text: $name)
                        .padding(12).background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.chip))
                    TextField("Menge pro Woche (optional)", text: $amount).keyboardType(.decimalPad)
                        .padding(12).background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.chip))
                    Picker("Einheit", selection: $unit) {
                        ForEach(ScanLabels.units, id: \.0) { u in Text(u.1).tag(u.0) }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(16).card()
                Button(action: save) { Text(saving ? "Speichere …" : basic == nil ? "Hinzufügen" : "Speichern") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(trimmed.isEmpty || saving).opacity(trimmed.isEmpty ? 0.5 : 1)
                if let basic {
                    Button("Löschen", role: .destructive) {
                        Task {
                            do {
                                try await store.deleteWeeklyBasic(basic.id)
                                store.flash("„\(basic.name)“ entfernt")
                                changed()
                                dismiss()
                            } catch {
                                store.flash("Nicht gelöscht: \(error.localizedDescription)")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(Theme.pagePadding)
        }
        .scrollDismissesKeyboard(.immediately)
        .presentationBackground(Theme.C.bg)
        .presentationCornerRadius(Theme.R.sheet)
    }

    private func save() {
        let qty = Double(amount.replacingOccurrences(of: ",", with: ".")).map { a in min(max(a, 0), 100_000) }
        saving = true
        Task {
            defer { saving = false }
            do {
                try await store.saveWeeklyBasic(id: basic?.id, WeeklyBasicIn(name: trimmed, amount: qty, unit: unit))
                store.flash(basic == nil ? "„\(trimmed)“ kommt jede Woche auf die Liste" : "Gespeichert")
                changed()
                dismiss()
            } catch {
                store.flash("Nicht gespeichert: \(error.localizedDescription)")
            }
        }
    }
}

extension MealDTO: Identifiable {}  // Plan-Gerichte (id gesetzt) für `.sheet(item:)`
