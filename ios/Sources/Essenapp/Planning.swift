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

/// Einstellungen › Präferenzen › „Abwechslung“ (e.html): Zeilen mit Steppern, Gruppen mit Abstand, Schalter am Ende.
struct VarietyForm: View {
    @Binding var rules: VarietyDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(spacing: 0) {
                row("Pasta höchstens", "pro Woche", $rules.maxPasta, 0...14) { "\($0)×" }
                row("Reis höchstens", "pro Woche", $rules.maxRice, 0...14) { "\($0)×" }
                row("Kartoffeln höchstens", "pro Woche", $rules.maxPotato, 0...14) { "\($0)×" }
            }
            VStack(spacing: 0) {
                row("Fisch mindestens", "pro Woche", $rules.minFish, 0...3) { "\($0)×" }
                row("Vegetarische Tage", "pro Woche", $rules.veggieDays, 0...7) { $0 == 1 ? "1 Tag" : "\($0) Tage" }
                row("Rotes Fleisch höchstens", "pro Woche", $rules.maxRedMeat, 0...14) { "\($0)×" }
            }
            VStack(spacing: 0) {
                row("Gleiches Gericht", "frühestens nach", $rules.repeatWeeks, 1...12) { $0 == 1 ? "1 Wo." : "\($0) Wo." }
                Toggle(isOn: $rules.noSameCuisineRow) {
                    Text("Gleiche Küche nicht zwei Tage hintereinander").font(Theme.F.text(15, .bold, relativeTo: .body))
                        .foregroundStyle(Theme.C.ink)
                }
                .toggleStyle(.v8)
                .frame(minHeight: 52)
                .overlay(alignment: .top) { Hairline() }
                .sensoryFeedback(.selection, trigger: rules.noSameCuisineRow)
            }
        }
    }

    private func row(_ title: String, _ sub: String, _ value: Binding<Int>, _ range: ClosedRange<Int>, _ text: @escaping (Int) -> String) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.F.text(15, .bold, relativeTo: .body)).foregroundStyle(Theme.C.ink)
                Text(sub).font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
            }
            Spacer(minLength: 4)
            Stepper8(value: value, range: range, format: text)
                .accessibilityLabel(title)
        }
        .frame(minHeight: 52)
        .overlay(alignment: .top) { Hairline() }
    }
}

/// Pille im Tageskopf (S2 Tag): „✓ Abwechslung“ (sage) oder „2× Pasta“ (warn); weitere Verstöße im Menü.
struct VarietyChip: View {
    let check: VarietyCheckDTO

    var body: some View {
        let label = HStack(spacing: 5) {
            Icon(check.ok ? .check : .bell, size: 15)
            Text(check.ok ? "Abwechslung" : check.issues.first ?? "Abwechslung")
            if check.issues.count > 1 {
                Text("+\(check.issues.count - 1)").foregroundStyle(Theme.C.ink2)
            }
        }
        .font(Theme.F.text(13, .bold, relativeTo: .footnote))
        .foregroundStyle(Theme.C.ink)
        .padding(.horizontal, 12).frame(height: 30)
        .background(check.ok ? Theme.C.sage : Theme.C.warn, in: Capsule())
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        Group {
            if check.issues.count > 1 {
                Menu { ForEach(check.issues, id: \.self) { i in Text(i) } } label: { label }
            } else {
                label
            }
        }
        .accessibilityLabel(check.ok ? "Abwechslung eingehalten" : "Abwechslung: \(check.issues.joined(separator: ", "))")
        .animation(Theme.spring, value: check)
    }
}

// MARK: 19 Reste

/// Wochenplan: „Reste: 3 verplant, 1 übrig (Sahne 100 ml)“ mit Vorschlag.
struct LeftoversCard: View {
    let leftovers: LeftoversDTO
    @State private var open = false  // zu: nur 2 Hinweise

    var body: some View {
        let left = leftovers.left
        let rest = left.isEmpty ? "nichts übrig" : "\(left.count) übrig"
        VStack(alignment: .leading, spacing: 0) {
            IRow(name: "Reste: \(leftovers.planned) verplant, \(rest)", sub: left.isEmpty ? nil : left.map { "\($0.name) \(qty($0.amount, $0.unit))" }.joined(separator: ", "),
                 tint: Theme.C.sage) {
                Icon(.refresh, size: 22).foregroundStyle(Theme.C.ink)
            }
            ForEach(open ? left : Array(left.prefix(2)), id: \.self) { l in
                Text("\(l.name): \(l.suggestion)").font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                    .lineLimit(open ? nil : 1)
                    .padding(.leading, Theme.S.rowCircle + 14).padding(.bottom, 6)
            }
            if left.count > 2 {
                Button { withAnimation(Theme.spring) { open.toggle() } } label: {
                    Text(open ? "weniger anzeigen" : "alle \(left.count) anzeigen")
                        .font(Theme.F.text(13, .extrabold, relativeTo: .footnote)).foregroundStyle(Theme.C.blue3)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .padding(.leading, Theme.S.rowCircle + 14)
            }
        }
        .accessibilityElement(children: .contain)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("Reste in den Vorrat?").font(Theme.F.t2)
                Spacer()
                CloseButton(action: done)
            }
            Text("Von angebrochenen Packungen bleibt etwas übrig – Menge prüfen, dann übernehmen.")
                .font(Theme.F.text(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2)
                .lineSpacing(14 * 0.45 - 4).padding(.trailing, 20).padding(.top, 4)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach($rows) { $r in row($r) }
                }
                .padding(.top, 14)
            }
            .scrollDismissesKeyboard(.immediately)
            PlanBusyButton(title: chosen.isEmpty ? "Nichts ausgewählt" : "\(chosen.count) in den Vorrat", busy: saving, disabled: chosen.isEmpty, action: save)
                .padding(.top, 18)
            OutlineButton(title: "Nichts übrig", action: done).padding(.top, 10).padding(.bottom, 18)
        }
        .padding(.horizontal, Theme.pagePadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .edgeForm(.quarter, Theme.C.sage, width: 130, height: 130, right: 0, top: -33)
        .transition(.opacity)
    }

    /// Illustration für bekannte Zutaten, sonst Box-Icon.
    private func ill(_ name: String) -> String? {
        let n = name.lowercased()
        let map = [("tomate", "tomato"), ("knoblauch", "garlic"), ("basilikum", "basil"), ("spaghetti", "pasta"), ("pasta", "pasta"), ("nudel", "pasta")]
        return map.first { n.contains($0.0) }?.1
    }

    private func row(_ r: Binding<RestRow>) -> some View {
        let v = r.wrappedValue
        let probe = PantryDTO(id: 0, name: v.name, ingredientKey: "", amount: nil, unit: "", bestBefore: v.bestBefore,
                              isBasic: false, source: "rest", updatedAt: "")
        return HStack(spacing: 12) {
            Button { withAnimation(Theme.spring) { r.wrappedValue.checked.toggle() } } label: {
                CheckCircle(on: v.checked).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: v.checked)
            .accessibilityLabel(v.checked ? "\(v.name) übernehmen" : "\(v.name) nicht übernehmen")
            ZStack {
                if let i = ill(v.name) { Ill(i).frame(width: 46, height: 46) } else { Icon(.box, size: 20) }
            }
            .frame(width: 42, height: 42)
            .background(Theme.hue(category: probe.category).tint, in: Circle())
            .opacity(v.checked ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 3) {
                Text(v.name).font(Theme.F.text(15, .bold, relativeTo: .body)).lineLimit(1)
                if let d = probe.daysLeft {
                    Text(d >= 365 ? "\(d / 365) \(d >= 730 ? "Jahre" : "Jahr")" : d == 1 ? "1 Tag" : "\(d) Tage")
                        .font(Theme.F.text(11, .bold, relativeTo: .caption2)).foregroundStyle(Theme.C.ink)
                        .padding(.horizontal, 8).frame(height: 20)
                        .background(d <= 3 ? Theme.C.warn : Theme.C.sage, in: Capsule())
                }
            }
            .foregroundStyle(v.checked ? Theme.C.ink : Theme.C.ink3)
            Spacer(minLength: 4)
            HStack(spacing: 3) {
                TextField("Menge", text: r.amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .fixedSize()
                if !v.unit.isEmpty { Text(Labels.unit(v.unit)) }
            }
            .font(Theme.F.text(14, .bold, relativeTo: .subheadline)).monospacedDigit()
            .foregroundStyle(v.checked ? Theme.C.ink : Theme.C.ink3)
            .padding(.horizontal, 14).frame(minWidth: 76, minHeight: 38)
            .background(Theme.C.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
        }
        .frame(minHeight: 64)
        .overlay(alignment: .top) { Hairline() }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("Gäste hinzufügen").font(Theme.F.t2)
                    Spacer()
                    CloseButton { dismiss() }
                }
                Text("\(Labels.dayNames[max(0, min(meal.day, 6))]) · \(Labels.meal(meal.mealType)): „\(meal.recipe.title)“")
                    .font(Theme.F.text(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2).lineLimit(2)
                PlanStat(label: "Gäste", icon: .users) { BigNumber("+\(count)", size: 96) }.padding(.top, 26)
                HStack {
                    Text("0 bis 20").font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                    Spacer()
                    bigStepper
                }
                .padding(.top, 16)
                Text("Mengen, Kosten und Einkaufsliste werden angepasst – ohne neue KI-Planung.")
                    .font(Theme.F.text(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2)
                    .lineSpacing(14 * 0.5 - 4).padding(.top, 18)
                PlanBusyButton(title: "Übernehmen", busy: saving, disabled: count == (meal.guests ?? 0)) {
                    saving = true
                    Task {
                        defer { saving = false }
                        guard await store.setGuests(meal, count) else { return }
                        store.flash(count == 0 ? "Gäste entfernt" : "Für +\(count) \(count == 1 ? "Gast" : "Gäste") angepasst")
                        dismiss()
                    }
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 24)
        }
        .edgeForm(.circle, Theme.C.blue1, width: 250, height: 250, right: -90, top: 63)  // Mockup top 96 − 33
        .sheet8()
        .animation(Theme.spring, value: count)
    }

    /// Großer Stepper (S28): Höhe 48, Knöpfe 38, Zahl 18.
    private var bigStepper: some View {
        HStack(spacing: 20) {
            knob(.minus, "weniger Gäste") { count = max(0, count - 1) }
            Text("\(count)").font(Theme.F.text(18, .extrabold, relativeTo: .title3)).monospacedDigit().contentTransition(.numericText())
            knob(.plus, "mehr Gäste") { count = min(20, count + 1) }
        }
        .padding(.horizontal, 5)
        .frame(height: 48)
        .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
        .sensoryFeedback(.selection, trigger: count)
        .accessibilityElement(children: .contain)
    }

    private func knob(_ icon: Icon8, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(Theme.spring) { action() } } label: {
            Icon(icon, size: 18).frame(width: 38, height: 38).background(Theme.C.card, in: Circle())
                .frame(minWidth: 44, minHeight: 44).contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// Plan-Generator › Mehr Optionen › Gäste: Tageskreise mit „+4“, je Mahlzeit Stepper, „Gäste-Budget extra“.
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { d in
                    if d > 0 { Spacer(minLength: 2) }
                    dayCircle(d, selected: selected)
                }
            }
            .sensoryFeedback(.selection, trigger: selected)
            ForEach(meals, id: \.self) { m in
                let k = Self.key(selected, m)
                HStack {
                    Text("\(Labels.dayNames[selected]) · \(Labels.meal(m))").font(Theme.F.text(15, .bold, relativeTo: .body))
                    Spacer()
                    Stepper8(value: Binding(get: { guests[k] ?? 0 }, set: { v in guests[k] = v }), range: 0...20) { $0 == 0 ? "0" : "+\($0)" }
                        .accessibilityLabel("Gäste \(Labels.dayNames[selected]) \(Labels.meal(m))")
                }
                .frame(minHeight: Theme.S.row)
            }
            if total > 0 {
                Toggle(isOn: Binding(get: { extraEuro != nil }, set: { on in withAnimation(Theme.spring) { extraEuro = on ? 20 : nil } })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Gäste-Budget extra").font(Theme.F.text(15, .bold, relativeTo: .body)).foregroundStyle(Theme.C.ink)
                        Text(extraEuro.map { "\(euro(Int($0) * 100)) zusätzlich" } ?? "aus dem Wochenbudget")
                            .font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                            .contentTransition(.numericText())
                    }
                }
                .toggleStyle(.v8)
                .frame(minHeight: Theme.S.row)
                .overlay(alignment: .top) { Hairline() }
                if let e = extraEuro {
                    HStack {
                        Text("Betrag").font(Theme.F.text(15, .bold, relativeTo: .body))
                        Spacer()
                        Stepper8(value: Binding(get: { Int(e) / 5 }, set: { v in extraEuro = Double(v * 5) }), range: 1...20) { "\($0 * 5) €" }
                            .accessibilityLabel("Gäste-Budget")
                    }
                    .frame(minHeight: Theme.S.row)
                    .transition(.opacity)
                }
            }
        }
        .animation(Theme.spring, value: total)
    }

    private func dayCircle(_ d: Int, selected: Int) -> some View {
        let on = d == selected
        let active = days.contains(d)
        let n = meals.map { m in guests[Self.key(d, m)] ?? 0 }.reduce(0, +)
        return Button { withAnimation(Theme.spring) { day = d } } label: {
            Text(Labels.days[d]).font(Theme.F.text(13, .extrabold, relativeTo: .footnote))
                .foregroundStyle(on ? Theme.C.onInk : Theme.C.ink2)
                .frame(width: 38, height: 38)
                .background(on ? Theme.C.ink : .clear, in: Circle())
                .overlay { if !on { Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
                .overlay(alignment: .topTrailing) {
                    if n > 0 && active {
                        Text("+\(n)").font(Theme.F.text(10, .extrabold, relativeTo: .caption2)).foregroundStyle(Theme.C.ink)
                            .padding(.horizontal, 5).frame(height: 18)
                            .background(Theme.C.blue, in: Capsule())
                            .offset(x: 9, y: -7)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(minWidth: 40, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!active).opacity(active ? 1 : 0.4)
        .accessibilityLabel("\(Labels.dayNames[d])\(n > 0 ? ", \(n) Gäste" : "")")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: 25 Specials, Start-Banner

/// Plan-Generator: Beschreibung der Special-Vorlagen (Festtagsmenü, Plätzchen-Back-Plan, Grillparty).
enum SpecialPicker {
    static let templates = ["festtagsmenue": "Vorspeise, Hauptgang und Dessert am Tag des Anlasses",
                            "plaetzchen": "Backen am Samstag und Sonntag",
                            "grillparty": "Grillgut mit Beilagen am Samstagabend"]
}

/// Start-Zeile 14 Tage vor einem Anlass (25): „Weihnachten in 12 Tagen – Menü planen?“ → Generator mit Vorlage.
struct SpecialBanner: View {
    let banner: SpecialDTO
    let open: () -> Void

    var body: some View {
        let text = banner.text ?? banner.name
        let title = text.hasPrefix(banner.emoji) ? String(text.dropFirst(banner.emoji.count)).trimmingCharacters(in: .whitespaces) : text
        Button(action: open) {
            IRow(name: title, sub: "\(banner.templateName) im Plan-Generator", tint: Theme.C.sand) {
                Icon(.star, size: 22).foregroundStyle(Theme.C.ink)
            } trail: {
                Icon(.chev, size: 18).foregroundStyle(Theme.C.ink3)
            }
            .foregroundStyle(Theme.C.ink)
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

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keine Lust?").font(Theme.F.t2)
                        Text("Schnell & ohne Einkauf · höchstens 15 min").font(Theme.F.text(14, .semibold, relativeTo: .subheadline))
                            .foregroundStyle(Theme.C.ink2)
                    }
                    Spacer()
                    CloseButton { dismiss() }
                }
                .padding(.horizontal, Theme.pagePadding)
                if pages.isEmpty {
                    first.padding(.horizontal, Theme.pagePadding).padding(.top, 20)
                } else {
                    TabView(selection: $page) {
                        ForEach(pages.indices, id: \.self) { i in
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(pages[i]) { idea in card(idea) }
                                }
                                .padding(.horizontal, Theme.pagePadding).padding(.top, 14)
                            }
                            .tag(i)
                        }
                        more.padding(.horizontal, Theme.pagePadding).tag(pages.count)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    HStack(spacing: 12) {
                        Dots8(count: pages.count + 1, current: page)
                        Text(page < pages.count ? "Wischen für 3 weitere ›" : "‹ zurück zu den Ideen")
                            .font(Theme.F.text(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .overlay(alignment: .top) { Hairline() }
                    .padding(.horizontal, Theme.pagePadding).padding(.bottom, 12)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .edgeForm(.circle, Theme.C.blue1, width: 230, height: 230, left: -100, top: 63)  // Mockup top 96 − 33
            .background(Theme.C.bg)
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet8()
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
            PlanSlotSheet(recipeId: r.id, title: r.title).presentationDetents([.medium, .large])
        }
    }

    private var moveTitle: String {
        moveDay == (moved?.day ?? -2) + 1 ? "Auf morgen verschieben?" : "Auf \(Labels.dayNames[max(0, min(moveDay, 6))]) verschieben?"
    }

    /// Leer/Fehler (v8): Illustration, t2, Text, Knopf.
    private func note(_ ill: String, _ title: String, _ text: String, button: String? = nil, _ action: @escaping () -> Void = {}) -> some View {
        VStack(spacing: 10) {
            Ill(ill).frame(width: 150, height: 150)
            Text(title).font(Theme.F.t2).multilineTextAlignment(.center)
            Text(text).font(Theme.F.text(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2).multilineTextAlignment(.center)
            if let button { PrimaryButton(title: button, action: action).padding(.top, 8) }
        }
        .frame(maxWidth: .infinity)
    }

    /// Erste Seite: Laden, Fehler, leer.
    @ViewBuilder private var first: some View {
        if empty {
            note("fridge", "Vorrat ist leer", "Trag ein, was du zu Hause hast – dann finden wir schnelle Ideen ohne Einkauf.")
        } else if let error {
            note("binoculars", "Das hat nicht geklappt", error, button: "Erneut versuchen") { Task { await load() } }
        } else if exhausted {
            note("binoculars", "Keine passende Idee", "Mit dem, was da ist, geht gerade nichts in 15 Minuten.")
        } else {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 16) {
                        Circle().fill(Theme.C.line).frame(width: 92, height: 92)
                        VStack(alignment: .leading, spacing: 8) {
                            Skeleton8(width: 160, height: 20)
                            Skeleton8(width: 120, height: 12)
                            Hop3().scaleEffect(0.8).frame(width: 110, alignment: .leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 14)
                    .overlay(alignment: .top) { Hairline() }
                }
            }
        }
    }

    /// Letzte Seite beim Wischen: lädt 3 weitere.
    @ViewBuilder private var more: some View {
        VStack(spacing: 14) {
            if let error {
                note("binoculars", "Das hat nicht geklappt", error, button: "Erneut versuchen") { Task { await load() } }
            } else if exhausted {
                note("binoculars", "Mehr fällt uns gerade nicht ein", "Wisch zurück und nimm eine der Ideen.")
            } else {
                Hop3().padding(.top, 40)
                Text("Weitere Ideen …").font(Theme.F.text(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2)
            }
        }
        .padding(.top, 20)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func card(_ idea: CookIdeaDTO) -> some View {
        let r = idea.recipe
        return HStack(spacing: 16) {
            NavigationLink { SavedRecipeView(recipeId: r.id) } label: {
                PlanPlate(url: mediaURL(r.imageUrl), size: 92)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("\(r.title) ansehen")
            VStack(alignment: .leading, spacing: 4) {
                Text(r.title).font(Theme.F.serif(21, relativeTo: .title3)).foregroundStyle(Theme.C.ink).lineLimit(2)
                Text("\(r.prepMinutes) min · \(r.servings) Portionen · alles da")
                    .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                PlanBusyButton(title: "Das koche ich heute", busy: busy == r.id, disabled: busy != nil && busy != r.id, small: true, blue: true) {
                    Task { await choose(r) }
                }
                .fixedSize()
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Hairline() }
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

    /// Nächster Montag („Mo, 10. Nov“).
    private var nextMonday: String {
        let cal = Calendar(identifier: .iso8601)
        let d = cal.nextDate(after: .now, matching: DateComponents(weekday: 2), matchingPolicy: .nextTime) ?? .now
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(.de)).replacingOccurrences(of: ".", with: "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { dismiss() } label: { Icon(.back).frame(width: 44, height: 44, alignment: .leading).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Zurück")
                    Spacer()
                    CircleButton(icon: .plus, size: 44, filled: true, label: "Basic hinzufügen") { adding = true }
                }
                Text("Frühstück\n& Snacks").font(Theme.F.t1).padding(.top, 8)
                Text("Kommt jeden Montag auf die Liste – im Angebot, wenn es günstiger ist; Vorrat wird abgezogen.")
                    .font(Theme.F.text(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2)
                    .frame(maxWidth: 220, alignment: .leading).padding(.top, 8)
                VStack(spacing: 0) {
                    if let basics {
                        if basics.isEmpty {
                            VStack(spacing: 10) {
                                Ill("bag").frame(width: 150, height: 150)
                                Text("Noch keine Basics").font(Theme.F.t2)
                                Text("Z. B. Haferflocken 1.000 g, Joghurt 1.000 g, Brot, Bananen 6 Stück.")
                                    .font(Theme.F.text(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2).multilineTextAlignment(.center)
                                PrimaryButton(title: "Basic hinzufügen", icon: .plus) { adding = true }.padding(.top, 8)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        ForEach(basics) { b in row(b) }
                    } else if let error {
                        VStack(spacing: 10) {
                            Ill("binoculars").frame(width: 150, height: 150)
                            Text("Nicht geladen").font(Theme.F.t2)
                            Text(error).font(Theme.F.text(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2).multilineTextAlignment(.center)
                            PrimaryButton(title: "Erneut versuchen", icon: .refresh) { Task { await load() } }.padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(0..<4, id: \.self) { _ in Skeleton8(height: 52).padding(.vertical, 4) }
                    }
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 180)
            .edgeForm(.circle, Theme.C.sand, width: 300, height: 300, right: -110, top: -152)  // Mockup top −100 − Statusleiste 52
            .pinned(right: -26, top: 14) { Ill("pot").frame(width: 190).accessibilityHidden(true) }
        }
        .background(Theme.C.bg)
        .refreshable { await load() }
        .ctaBar(bottom: 40) {
            if basics?.isEmpty == false {
                VStack(spacing: 14) {
                    Text("Nächstes Mal automatisch: \(nextMonday)")
                        .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                    PlanBusyButton(title: "Jetzt auf die Liste", icon: .bag, busy: sending) {
                        sending = true
                        Task { await store.basicsToList(); sending = false }
                    }
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
            IRow(name: b.name, sub: b.amount.map { a in "\(qty(a, b.unit.isEmpty ? "stk" : b.unit)) pro Woche" } ?? "ohne Menge · jede Woche",
                 tint: Theme.hue(category: probe.category).tint) {
                Icon(.box, size: 22).foregroundStyle(Theme.C.ink)
            } trail: {
                Icon(.chev, size: 18).foregroundStyle(Theme.C.ink3)
            }
            .foregroundStyle(Theme.C.ink)
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
                HStack(alignment: .top) {
                    Text(basic == nil ? "Neues Basic" : "Basic ändern").font(Theme.F.t2)
                    Spacer()
                    CloseButton { dismiss() }
                }
                FieldBox(icon: .edit) { TextField("Name, z. B. Haferflocken", text: $name) }
                FieldBox(icon: .box) { TextField("Menge pro Woche (optional)", text: $amount).keyboardType(.decimalPad) }
                Segmented8(options: ScanLabels.units.map { ($0.0, $0.1) }, selection: $unit)
                PlanBusyButton(title: basic == nil ? "Hinzufügen" : "Speichern", busy: saving, disabled: trimmed.isEmpty, action: save)
                    .padding(.top, 4)
                if let basic {
                    Button {
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
                    } label: {
                        HStack(spacing: 8) { Icon(.trash, size: 20); Text("Löschen") }
                            .font(Theme.F.button2).foregroundStyle(Theme.C.deal)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .sheet8()
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
