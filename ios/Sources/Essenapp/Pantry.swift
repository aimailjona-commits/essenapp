import SwiftUI

// Vorratskammer (60): Tab Einkauf › Pille „Vorrat“ (S16).

/// = backend PantryOut. Basics: amount nil = vorhanden, 0 = leer gemeldet.
struct PantryDTO: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var ingredientKey: String
    var amount: Double?
    var unit: String  // "" | g | ml | stk
    var bestBefore: String?  // YYYY-MM-DD
    var isBasic: Bool
    var source: String
    var updatedAt: String
}

/// Body für POST /pantry.
struct PantryIn: Encodable {
    var name: String
    var amount: Double?
    var unit: String
    var bestBefore: String?
    var isBasic: Bool
    var source = "manual"  // manual | scan (Kühlschrank-Foto, 69)
}

extension PantryDTO {
    /// Datum als „YYYY-MM-DD“ in lokaler Zeit (Haltbarkeit).
    static let day = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()

    // shortcut: Kategorie per Wortliste aus dem Namen, bis das Backend eine Kategorie liefert
    static let words: [(key: String, words: [String])] = [
        ("vorrat", ["tomatenmark", "passiert", "dose", "konserve"]),
        ("fleisch_fisch", ["hähnchen", "huhn", "rind", "schwein", "hack", "wurst", "schinken", "speck", "lachs", "thunfisch",
                           "fisch", "garnele", "pute", "salami"]),
        ("kuehlung", ["milch", "joghurt", "käse", "feta", "quark", "skyr", "butter", "sahne", "eier", "mozzarella", "tofu"]),
        ("obst_gemuese", ["tomate", "gurke", "paprika", "zwiebel", "knoblauch", "kartoffel", "möhre", "karotte", "apfel", "banane",
                          "salat", "zucchini", "avocado", "zitrone", "spinat", "brokkoli", "pilz", "champignon", "beere", "birne",
                          "lauch", "kohl", "ingwer", "kürbis"]),
        ("getraenke", ["saft", "wasser", "bier", "cola", "limo", "tee", "kaffee"]),
    ]

    var category: String {
        if isBasic { return "basics" }
        let n = name.lowercased()
        return Self.words.first { entry in entry.words.contains { w in n.contains(w) } }?.key ?? "vorrat"
    }

    var emoji: String { isBasic ? "🧂" : Theme.hue(category: category).emoji }

    /// Tage bis zum Ablauf (negativ = abgelaufen).
    var daysLeft: Int? {
        guard let bestBefore, let date = try? Date(bestBefore, strategy: Self.day) else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: date).day
    }

    var amountText: String {
        guard let amount else { return "Menge offen" }
        return "\(num(amount)) \(unit == "stk" ? "Stück" : unit)"
    }
}

extension AppStore {
    func loadPantry() async throws {
        guard !demo else { return }
        pantry = try await api.request("GET", "/pantry")
    }

    func addPantry(_ new: PantryIn) async throws {
        let created: PantryDTO = demo
            ? PantryDTO(id: -(pantry.count + 1), name: new.name, ingredientKey: new.name.lowercased(), amount: new.amount, unit: new.unit,
                        bestBefore: new.bestBefore, isBasic: new.isBasic, source: "manual", updatedAt: "")
            : try await api.request("POST", "/pantry", body: new)
        withAnimation(Theme.spring) { pantry.insert(created, at: 0) }
    }

    private func replacePantry(_ item: PantryDTO) {
        if let i = pantry.firstIndex(where: { $0.id == item.id }) { pantry[i] = item } else { pantry.insert(item, at: 0) }
    }

    /// Menge setzen; nil = Basic wieder vorhanden bzw. Menge unbekannt (wird explizit als null gesendet).
    func setPantryAmount(_ item: PantryDTO, _ amount: Double?) async {
        var local = item
        local.amount = amount
        replacePantry(local)
        guard !demo, item.id > 0 else { return }
        let body: [String: Double?] = ["amount": amount]
        if let updated: PantryDTO = try? await api.request("PATCH", "/pantry/\(item.id)", body: body) { replacePantry(updated) }
    }

    func deletePantry(_ item: PantryDTO) async {
        withAnimation(Theme.spring) { pantry.removeAll { $0.id == item.id } }
        guard !demo, item.id > 0 else { return }
        _ = try? await api.send("DELETE", "/pantry/\(item.id)")
    }

    /// Basic leer melden → kommt auf die Haushaltsliste.
    func emptyBasic(_ item: PantryDTO) async {
        var local = item
        local.amount = 0
        replacePantry(local)
        if !demo {
            let entry: ListItemDTO? = try? await api.request("POST", "/pantry/basics/\(item.id)/empty")
            guard entry != nil else { replacePantry(item); flash("Das hat nicht geklappt"); return }
            await loadLists()
        }
        flash("\(item.name) steht auf der Liste")
    }

    /// Abgehakten Listen-Artikel in den Vorrat übernehmen.
    func toPantry(_ item: ListItemDTO) async {
        if demo {
            replacePantry(PantryDTO(id: -(pantry.count + 1), name: item.name, ingredientKey: item.name.lowercased(), amount: item.amount,
                                    unit: item.unit, bestBefore: nil, isBasic: false, source: "list", updatedAt: ""))
        } else {
            guard let p: PantryDTO = try? await api.request("POST", "/items/\(item.id)/to-pantry") else {
                flash("Das hat nicht geklappt"); return
            }
            replacePantry(p)
        }
        flash("„\(item.name)“ ist im Vorrat")
    }

    /// „Gekocht“: zieht die Mengen des Plan-Gerichts vom Vorrat ab; gibt die geänderten Einträge zurück (0 = aufgebraucht).
    func consume(_ meal: MealDTO) async -> [PantryDTO] {
        var changed: [PantryDTO] = []
        if demo {
            for ing in meal.recipe.ingredients {
                guard let i = pantry.firstIndex(where: { p in !p.isBasic && p.name.lowercased() == ing.name.lowercased() && p.unit == ing.unit }),
                      let have = pantry[i].amount else { continue }
                pantry[i].amount = max(have - ing.amount, 0)
                changed.append(pantry[i])
            }
        } else {
            // Plan-Gericht: ganze Menge des Slots; gespeichertes Rezept (ohne Slot): Rezeptmenge
            struct Body: Encodable { var entryId: Int?; var recipeId: Int? }
            let body = meal.id.map { id in Body(entryId: id) } ?? Body(recipeId: meal.recipe.id)
            changed = (try? await api.request("POST", "/pantry/consume", body: body)) ?? []
            changed.forEach(replacePantry)
        }
        withAnimation(Theme.spring) { pantry.removeAll { $0.amount == 0 && !$0.isBasic } }  // Backend löscht aufgebrauchte Einträge
        return changed
    }
}

/// S16 Vorrat.
struct PantryView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var category: String?
    @State private var loaded = false
    @State private var error: String?
    @State private var adding = false

    var body: some View {
        let shown = store.pantry.filter { p in
            (category == nil || p.category == category) && (query.isEmpty || p.name.localizedCaseInsensitiveContains(query))
        }
        let keys = Set(store.pantry.map(\.category))
        let all: [(key: String, label: String, emoji: String)] = Labels.categories.map { c in
            (key: c.0, label: String(c.1.split(separator: " ").dropFirst().joined(separator: " ")), emoji: Theme.hue(category: c.0).emoji)
        } + [(key: "basics", label: "Basics", emoji: "🧂")]
        List {
            Group {
                HStack(alignment: .bottom) {
                    DisplayHeader(line1: "Vorrat", line2: "\(store.pantry.count) Sachen zu Hause")
                    RoundIconButton(systemName: "plus", dark: true, label: "Zum Vorrat hinzufügen") { adding = true }
                }
                if !store.pantry.isEmpty {
                    SearchField(text: $query, placeholder: "Vorrat durchsuchen")
                    CategoryCircles(items: all.filter { keys.contains($0.key) }, selected: $category)
                }
                if store.pantry.isEmpty {
                    if !loaded {
                        ForEach(0..<4, id: \.self) { _ in SkeletonCard(height: 68) }
                    } else if let error {
                        ErrorState(message: error) { Task { await load() } }
                    } else {
                        EmptyState(emoji: "📸", title: "Kühlschrank fotografieren",
                                   text: "Noch nichts im Vorrat. Fotografiere Kühlschrank, Vorrat oder Gefrierfach – wir erkennen, was da ist.",
                                   buttonTitle: "📸 Kühlschrank fotografieren") { store.scanning = true }
                    }
                } else if shown.isEmpty {
                    EmptyState(emoji: "🔍", title: "Nichts gefunden", text: "Anderen Begriff oder andere Kategorie probieren.")
                }
            }
            .pantryRow()
            ForEach(shown) { p in
                PantryRow(item: p)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Löschen", systemImage: "trash", role: .destructive) { Task { await store.deletePantry(p) } }
                    }
                    .contextMenu {
                        Button("Löschen", systemImage: "trash", role: .destructive) { Task { await store.deletePantry(p) } }
                    }
                    .pantryRow()
            }
            Color.clear.frame(height: 100).pantryRow()  // Platz für die Tab-Leiste
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .environment(\.defaultMinListRowHeight, 0)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $adding) { PantryAddSheet().presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
    }

    private func load() async {
        do {
            try await store.loadPantry()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }
}

private extension View {
    func pantryRow() -> some View {
        listRowInsets(EdgeInsets(top: 5, leading: Theme.pagePadding, bottom: 5, trailing: Theme.pagePadding))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// Zeile im Vorrat: Emoji, Name, Menge mit Stepper bzw. Basic-Schalter, Haltbarkeits-Chip.
struct PantryRow: View {
    @Environment(AppStore.self) private var store
    let item: PantryDTO

    var body: some View {
        HStack(spacing: 12) {
            Text(item.emoji).font(.system(size: 22))
                .frame(width: 44, height: 44)
                .background(Theme.hue(category: item.category).tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.system(.body, weight: .semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.isBasic ? (item.amount == 0 ? "leer" : "vorhanden") : item.amountText)
                        .font(Theme.F.micro).monospacedDigit()
                        .foregroundStyle(item.isBasic && item.amount == 0 ? Theme.C.danger : Theme.C.text2)
                        .contentTransition(.numericText())
                    if let d = item.daysLeft { ExpiryChip(days: d) }
                }
            }
            Spacer(minLength: 0)
            if item.isBasic {
                Toggle("\(item.name) vorhanden", isOn: Binding(get: { item.amount != 0 }, set: { on in
                    Task { if on { await store.setPantryAmount(item, nil) } else { await store.emptyBasic(item) } }
                }))
                .labelsHidden()
                .tint(Theme.C.success)
            } else {
                Stepper("Menge \(item.name)", onIncrement: { change(+1) }, onDecrement: { change(-1) }).labelsHidden()
            }
        }
        .padding(12)
        .card(radius: Theme.R.tile)
        .animation(Theme.spring, value: item.amount)
        .sensoryFeedback(.selection, trigger: item.amount)
    }

    /// Schritte je Einheit: g/ml in 10ern (ab 100 in 50ern), Stück einzeln. 0 → Eintrag weg.
    private func change(_ dir: Double) {
        guard dir > 0 || item.amount != nil else { return }
        let have = item.amount ?? 0
        let step = ["g", "ml"].contains(item.unit) ? (have >= (dir > 0 ? 100 : 150) ? 50.0 : 10.0) : 1.0
        let new = max(have + dir * step, 0)
        Task {
            if new == 0 {
                await store.deletePantry(item)
                store.flash("„\(item.name)“ aufgebraucht")
            } else {
                await store.setPantryAmount(item, new)
            }
        }
    }
}

/// Haltbarkeit: bald (≤ 3 Tage) orange, abgelaufen rot, sonst grau.
struct ExpiryChip: View {
    let days: Int

    var body: some View {
        let text = days < 0 ? "abgelaufen" : days == 0 ? "läuft heute ab" : days == 1 ? "läuft morgen ab"
            : days <= 3 ? "läuft in \(days) Tagen ab" : "noch \(days) Tage"
        let color = days < 0 ? Theme.C.danger : days <= 3 ? Theme.C.accent : Theme.C.text2
        Text(text).font(Theme.F.micro).foregroundStyle(color)
            .padding(.horizontal, 8).frame(height: 22)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// „+“ im Vorrat: Name, Menge, Einheit, Haltbarkeit (optional), Basic.
struct PantryAddSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var unit = "g"
    @State private var hasDate = false
    @State private var date = Date.now.addingTimeInterval(7 * 86400)
    @State private var basic = false
    @State private var saving = false

    private var trimmed: String { String(name.trimmingCharacters(in: .whitespaces).prefix(100)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Zum Vorrat").font(Theme.F.title)
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Name, z. B. Reis", text: $name)
                        .padding(12).background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.chip))
                    if !basic {
                        TextField("Menge (optional)", text: $amount).keyboardType(.decimalPad)
                            .padding(12).background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.chip))
                        Picker("Einheit", selection: $unit) {
                            Text("g").tag("g"); Text("ml").tag("ml"); Text("Stück").tag("stk"); Text("ohne").tag("")
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(16).card()
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Haltbarkeit angeben", isOn: $hasDate.animation(Theme.spring)).tint(Theme.C.accent)
                    if hasDate { DatePicker("Haltbar bis", selection: $date, displayedComponents: .date) }
                    Toggle("Basic (Salz, Öl, Gewürze …)", isOn: $basic.animation(Theme.spring)).tint(Theme.C.accent)
                    Text("Basics gelten als vorhanden, bis du sie leer meldest – dann kommen sie auf die Liste.")
                        .font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                }
                .padding(16).card()
                Button(action: save) { Text(saving ? "Speichere …" : "Hinzufügen") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(trimmed.isEmpty || saving).opacity(trimmed.isEmpty ? 0.5 : 1)
            }
            .padding(Theme.pagePadding)
        }
        .scrollDismissesKeyboard(.immediately)
        .presentationBackground(Theme.C.bg)
    }

    private func save() {
        let qty = Double(amount.replacingOccurrences(of: ",", with: ".")).map { min(max($0, 0), 100_000) }
        let new = PantryIn(name: trimmed, amount: basic ? nil : qty, unit: basic ? "" : unit,
                           bestBefore: hasDate ? date.formatted(PantryDTO.day) : nil, isBasic: basic)
        saving = true
        Task {
            defer { saving = false }
            do {
                try await store.addPantry(new)
                store.flash("„\(new.name)“ im Vorrat")
                dismiss()
            } catch {
                store.flash(error.localizedDescription)
            }
        }
    }
}
