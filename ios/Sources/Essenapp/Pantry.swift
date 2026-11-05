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
    var location: String? = nil  // kuehlschrank | vorrat | gefrierfach (Kühlschrank-Foto), nil = unbekannt
}

/// Body für POST /pantry.
struct PantryIn: Encodable {
    var name: String
    var amount: Double?
    var unit: String
    var bestBefore: String?
    var isBasic: Bool
    var source = "manual"  // manual | scan (Kühlschrank-Foto, 69) | rest (Reste nach dem Kochen, 19)
    var location: String? = nil  // Ort aus dem Prüf-Bildschirm (S24)
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
        let id = demo ? -(pantry.count + 1) : api.newTempId()
        let local = PantryDTO(id: id, name: new.name, ingredientKey: new.name.lowercased(), amount: new.amount, unit: new.unit,
                              bestBefore: new.bestBefore, isBasic: new.isBasic, source: new.source, updatedAt: "")
        var created = local
        if !demo {
            do {
                created = try await api.request("POST", "/pantry", body: new, tempId: id)
            } catch APIError.queued {
                created = local  // offline: lokal mit vorläufiger ID, Server bekommt es später (66)
            }
        }
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
        guard !demo, item.id > 0 || API.isTemp(item.id) else { return }
        let body: [String: Double?] = ["amount": amount]
        if let updated: PantryDTO = try? await api.request("PATCH", "/pantry/\(item.id)", body: body) { replacePantry(updated) }
    }

    func deletePantry(_ item: PantryDTO) async {
        withAnimation(Theme.spring) { pantry.removeAll { $0.id == item.id } }
        guard !demo, item.id > 0 || API.isTemp(item.id) else { return }
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

extension PantryDTO {
    private static let months = ["Jan", "Feb", "März", "Apr", "Mai", "Juni", "Juli", "Aug", "Sep", "Okt", "Nov", "Dez"]

    /// „Mi, 12. Nov“ (Sheets S16, Coupon S31c).
    static func dayText(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.weekday, .day, .month], from: d)
        return "\(Labels.days[((c.weekday ?? 2) + 5) % 7]), \(c.day ?? 1). \(months[((c.month ?? 1) - 1) % 12])"
    }

    /// „bis 8.11.“, weiter weg „bis 03/2027“.
    static func untilText(_ iso: String?, days: Int?) -> String? {
        let p = (iso ?? "").split(separator: "-").compactMap { s in Int(s) }
        guard p.count == 3 else { return nil }
        return (days ?? 0) > 60 ? "bis \(String(format: "%02d", p[1]))/\(p[0])" : "bis \(p[2]).\(p[1])."
    }

    /// Haltbarkeit: bald (≤ 3 Tage) gelb, abgelaufen rot, sonst grau.
    static func expiry(_ days: Int) -> (text: String, color: Color) {
        let text = days < 0 ? "abgelaufen" : days == 0 ? "läuft heute ab" : days == 1 ? "läuft morgen ab"
            : days <= 3 ? "läuft in \(days) Tagen ab" : "noch \(days) Tage"
        return (text, days < 0 ? Theme.C.deal : days <= 3 ? Theme.C.warning : Theme.C.ink2)
    }

    static func locationName(_ key: String?) -> String? { ScanLabels.modes.first { m in m.0 == key }?.1 }
}

/// Zeichnung bzw. Icon und Kreis-Farbe (`.d-row .c`) für Vorrat, Kategorien und Prüf-Bildschirm (S16/S24).
struct PantryArt {
    var ill: String?
    var icon: Icon8 = .box
    var tint: Color

    static func of(name: String, category: String, basic: Bool = false) -> PantryArt {
        let n = name.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { w in n.contains(w) } }
        if basic { return PantryArt(icon: .leaf, tint: Theme.C.sand) }
        if has(["tomate"]) { return PantryArt(ill: "tomato", tint: Theme.C.rose) }
        if has(["basilikum", "petersilie", "kräuter", "schnittlauch", "minze", "koriander"]) { return PantryArt(ill: "basil", tint: Theme.C.sage) }
        if has(["knoblauch"]) { return PantryArt(ill: "garlic", tint: Theme.C.sand) }
        if has(["spaghetti", "nudel", "pasta", "penne", "fusilli", "lasagne"]) { return PantryArt(ill: "pasta", tint: Theme.C.blue1) }
        return Self.category(category)
    }

    static func category(_ key: String) -> PantryArt {
        switch key {
        case "obst_gemuese": PantryArt(ill: "tomato", tint: Theme.C.rose)
        case "kuehlung": PantryArt(tint: Theme.C.blue1)
        case "vorrat": PantryArt(ill: "pasta", tint: Theme.C.blue1)
        case "fleisch_fisch": PantryArt(tint: Theme.C.rose)
        case "getraenke": PantryArt(tint: Theme.C.blue1)
        case "basics": PantryArt(icon: .leaf, tint: Theme.C.sand)
        default: PantryArt(tint: Theme.C.sand)
        }
    }

    /// Kreis mit Zeichnung (Bild 40 in 48) bzw. Icon.
    func circle(_ size: CGFloat = Theme.S.rowCircle, image: CGFloat = Theme.S.rowImage) -> some View {
        Group {
            if let ill { Ill(ill).frame(width: image, height: image) } else { Icon(icon) }
        }
        .foregroundStyle(Theme.C.ink)
        .frame(width: size, height: size)
        .background(tint, in: Circle())
    }
}

/// S16 Vorrat (d.html „S16 Vorrat“).
struct PantryView: View {
    @Environment(AppStore.self) private var store
    @Binding var page: Int
    @State private var query = ""
    @State private var category: String?
    @State private var loaded = false
    @State private var error: String?
    @State private var adding = false
    @State private var voiceOpen = false

    // Mockup-Lage (S16): Salbei-Kreis oben rechts mit Kühlschrank
    private enum M {
        static let blob: CGFloat = 240, blobRight: CGFloat = -112, blobTop: CGFloat = -56
        static let fridge: CGFloat = 116, fridgeRight: CGFloat = 6, fridgeTop: CGFloat = 50
    }

    private static let catNames = ["obst_gemuese": "Gemüse", "fleisch_fisch": "Fleisch", "kuehlung": "Kühlung", "vorrat": "Vorrat",
                                   "getraenke": "Getränke", "drogerie": "Drogerie", "haushalt": "Haushalt", "basics": "Basics"]

    var body: some View {
        let shown = store.pantry.filter { p in
            (category == nil || p.category == category) && (query.isEmpty || p.name.localizedCaseInsensitiveContains(query))
        }
        let keys = Set(store.pantry.map(\.category))
        let cats = (Labels.categories.map(\.0) + ["basics"]).filter { k in keys.contains(k) }
        List {
            VStack(alignment: .leading, spacing: 0) {
                ShopTabs(page: $page)
                Text("\(store.pantry.count) Sachen zu Hause").font(Theme.F.small).foregroundStyle(Theme.C.ink2).padding(.top, 16)
                HStack(spacing: 14) {
                    Text("Vorrat").font(Theme.F.t1).accessibilityAddTraits(.isHeader)
                    CircleButton(icon: .plus, size: 44, filled: true, label: "Zum Vorrat hinzufügen") { adding = true }
                    CircleButton(icon: .mic, size: 44, label: "Per Sprache zum Vorrat hinzufügen") {
                        withAnimation(Theme.spring) { voiceOpen = true }
                    }
                }
                if !store.pantry.isEmpty {
                    search.padding(.top, 16)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            catButton(nil, "Alle")
                            ForEach(cats, id: \.self) { k in catButton(k, Self.catNames[k] ?? Labels.categoryName(k)) }
                        }
                        .padding(.horizontal, Theme.pagePadding)
                    }
                    .padding(.horizontal, -Theme.pagePadding)
                    .padding(.top, 16)
                    .sensoryFeedback(.selection, trigger: category)
                }
                if store.pantry.isEmpty {
                    if !loaded {
                        VStack(spacing: 12) { ForEach(0..<4, id: \.self) { _ in Skeleton8(height: 54) } }.padding(.top, 28)
                    } else if let error {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Vorrat nicht geladen").font(Theme.F.t2)
                            Text(error).font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                            OutlineButton(title: "Erneut versuchen", icon: .refresh) { Task { await load() } }.padding(.top, 8)
                        }
                        .padding(.top, 28)
                    } else {
                        VStack(spacing: 8) {  // ohne Mockup: Leer-Zustand mit Zeichnung
                            Ill("fridge").frame(width: 160, height: 160)
                            Text("Noch nichts im Vorrat").font(Theme.F.t2)
                            Text("Fotografiere Kühlschrank, Vorrat oder Gefrierfach – wir erkennen, was da ist.")
                                .font(Theme.F.small).foregroundStyle(Theme.C.ink2).multilineTextAlignment(.center)
                            PrimaryButton(title: "Kühlschrank fotografieren", icon: .cam) { store.scanning = true }.padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                    }
                } else if shown.isEmpty {
                    Text("Nichts gefunden – anderen Begriff oder andere Kategorie probieren.")
                        .font(Theme.F.small).foregroundStyle(Theme.C.ink2).padding(.top, 28)
                }
            }
            .padding(.top, 14)
            .padding(.bottom, shown.isEmpty ? 0 : 28)
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
            Color.clear.frame(height: Theme.S.nav).pantryRow()  // Platz für die Nav
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .environment(\.defaultMinListRowHeight, 0)
        .backdrop8 {
            Color.clear
                .pinned(right: M.fridgeRight, top: M.fridgeTop) { Ill("fridge").frame(width: M.fridge) }
                .edgeForm(.circle, Theme.C.sage, width: M.blob, height: M.blob, right: M.blobRight, top: M.blobTop)
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $adding) { PantryAddSheet() }
        .overlay {
            if voiceOpen {
                VoiceAddOverlay(target: .constant(.pantry)) { spoken in
                    withAnimation(Theme.spring) { voiceOpen = false }
                    Task { await store.addSpoken(spoken, target: .pantry) }
                } close: { withAnimation(Theme.spring) { voiceOpen = false } }
            }
        }
    }

    /// Suche (`.field` 44 hoch).
    private var search: some View {
        HStack(spacing: 10) {
            Icon(.search, size: 20).foregroundStyle(Theme.C.ink2)
            TextField("", text: $query, prompt: Text("Suchen").foregroundStyle(Theme.C.ink2)).submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: { Icon(.x, size: 18).foregroundStyle(Theme.C.ink2).tapArea() }
                    .buttonStyle(.plain).accessibilityLabel("Suche leeren")
            }
        }
        .font(Theme.F.text(15))
        .foregroundStyle(Theme.C.ink)
        .padding(.horizontal, 18)
        .frame(minHeight: 44)
        .background(Theme.C.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
    }

    /// Kategorie-Kreis (`.d-cat`): 56er-Kreis mit Zeichnung, Label 12/700; „Alle“ aktiv = Tinte.
    private func catButton(_ key: String?, _ label: String) -> some View {
        let on = category == key
        let art = key.map(PantryArt.category)
        return Button { withAnimation(Theme.spring) { category = key } } label: {
            VStack(spacing: 6) {
                Group {
                    if let art {
                        art.circle(56, image: 46)
                            .overlay { if on { Circle().strokeBorder(Theme.C.ink, lineWidth: 2) } }
                    } else {
                        Icon(.box).foregroundStyle(on ? Theme.C.onInk : Theme.C.ink)
                            .frame(width: 56, height: 56)
                            .background(on ? Theme.C.ink : Theme.C.card, in: Circle())
                            .overlay { if !on { Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
                    }
                }
                Text(label).font(Theme.F.text(12, .bold, relativeTo: .caption)).foregroundStyle(on ? Theme.C.ink : Theme.C.ink2).lineLimit(1)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
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
        listRowInsets(EdgeInsets(top: 0, leading: Theme.pagePadding, bottom: 0, trailing: Theme.pagePadding))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// Zeile im Vorrat (`.d-row`): Zeichnung im Farb-Kreis, Name, Haltbarkeit bzw. Ort, rechts Stepper oder Basic-Schalter.
struct PantryRow: View {
    @Environment(AppStore.self) private var store
    let item: PantryDTO

    private var sub: (text: String, color: Color)? {
        let loc = PantryDTO.locationName(item.location)
        if item.isBasic {
            return item.amount == 0 ? ("leer – steht auf der Liste", Theme.C.deal) : (["Basic", loc].compactMap { $0 }.joined(separator: " · "), Theme.C.ink2)
        }
        if let d = item.daysLeft, d <= 3 { return PantryDTO.expiry(d) }
        let parts = [loc, PantryDTO.untilText(item.bestBefore, days: item.daysLeft)].compactMap { $0 }
        return parts.isEmpty ? nil : (parts.joined(separator: " · "), Theme.C.ink2)
    }

    private var amountLabel: String {
        guard let a = item.amount else { return "–" }
        return ["stk", ""].contains(item.unit) ? num(a) : "\(num(a)) \(item.unit)"
    }

    var body: some View {
        HStack(spacing: 14) {
            PantryArt.of(name: item.name, category: item.category, basic: item.isBasic).circle()
            VStack(alignment: .leading, spacing: 0) {
                Text(item.name).font(Theme.F.serif(19, relativeTo: .title3)).lineLimit(1)
                if let sub { Text(sub.text).font(Theme.F.text(12)).foregroundStyle(sub.color).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if item.isBasic {
                Toggle(isOn: Binding(get: { item.amount != 0 }, set: { on in
                    Task { if on { await store.setPantryAmount(item, nil) } else { await store.emptyBasic(item) } }
                })) { EmptyView() }
                .toggleStyle(.v8)
                .fixedSize()
                .accessibilityLabel("\(item.name) vorhanden")
            } else {
                HStack(spacing: 6) {
                    knob(.minus, "weniger \(item.name)") { change(-1) }
                    Text(amountLabel).font(Theme.F.text(16, .extrabold)).monospacedDigit().contentTransition(.numericText())
                    knob(.plus, "mehr \(item.name)") { change(+1) }
                }
                .padding(.horizontal, 4)
                .frame(height: 36)
                .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
            }
        }
        .foregroundStyle(Theme.C.ink)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Hairline() }
        .animation(Theme.spring, value: item.amount)
        .sensoryFeedback(.selection, trigger: item.amount)
    }

    private func knob(_ icon: Icon8, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: 14).frame(width: 28, height: 28).background(Theme.C.card, in: Circle()).tapArea(8)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
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

/// Haltbarkeit als Text (S16 zweite Zeile): bald gelb, abgelaufen rot, sonst grau.
struct ExpiryChip: View {
    let days: Int

    var body: some View {
        let e = PantryDTO.expiry(days)
        Text(e.text).font(Theme.F.text(12)).foregroundStyle(e.color)
    }
}

/// „+“ im Vorrat (d.html „S16 + Sheet“): Name, Menge mit Einheit, Haltbarkeit (optional), Basic.
struct PantryAddSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var unit = "g"
    @State private var hasDate = false
    @State private var showCal = false
    @State private var date = Date.now.addingTimeInterval(7 * 86400)
    @State private var basic = false
    @State private var saving = false
    @State private var height: CGFloat = 520

    private var trimmed: String { String(name.trimmingCharacters(in: .whitespaces).prefix(100)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Neu im Vorrat").font(Theme.F.t2)
                    Spacer()
                    CloseButton { dismiss() }
                }
                SectionLabel("Name").padding(.top, 18).padding(.leading, 4).padding(.bottom, 6)
                FieldBox { TextField("z. B. Joghurt", text: $name) }
                if !basic {
                    SectionLabel("Menge · optional").padding(.top, 16).padding(.leading, 4).padding(.bottom, 6)
                    HStack(spacing: 10) {
                        FieldBox { TextField("500", text: $amount).keyboardType(.decimalPad) }.frame(width: 96)
                        Segmented8(options: [("g", "g"), ("ml", "ml"), ("stk", "Stück"), ("", "ohne")], selection: $unit)
                    }
                }
                SectionLabel("Haltbarkeit · optional").padding(.top, 16).padding(.leading, 4).padding(.bottom, 6)
                FieldBox {
                    Button {
                        hasDate = true
                        withAnimation(Theme.spring) { showCal.toggle() }
                    } label: {
                        Text(hasDate ? "bis \(PantryDTO.dayText(date))" : "Datum wählen")
                            .foregroundStyle(hasDate ? Theme.C.ink : Theme.C.ink2)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if hasDate {
                        Button { hasDate = false; showCal = false } label: { Icon(.x, size: 18).foregroundStyle(Theme.C.ink2).tapArea() }
                            .buttonStyle(.plain).accessibilityLabel("Haltbarkeit entfernen")
                    }
                }
                if showCal && hasDate {
                    DatePicker("Haltbar bis", selection: $date, displayedComponents: .date).datePickerStyle(.graphical).tint(Theme.C.ink)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Basic").font(Theme.F.text(16, .extrabold))
                        Text("immer da – leer kommt auf die Liste").font(Theme.F.text(12)).foregroundStyle(Theme.C.ink2)
                    }
                    Spacer()
                    Toggle(isOn: $basic.animation(Theme.spring)) { EmptyView() }.toggleStyle(.v8).fixedSize()
                        .accessibilityLabel("Basic")
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Hairline() }
                .padding(.top, 18)
                PrimaryButton(title: saving ? "Speichere …" : "Hinzufügen", disabled: trimmed.isEmpty || saving, action: save).padding(.top, 20)
            }
            .padding(.horizontal, Theme.pagePadding).padding(.bottom, 40)
            .onGeometryChange(for: CGFloat.self) { g in g.size.height } action: { h in height = h }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.immediately)
        .presentationDetents([.height(height + 33), .large])
        .sheet8()
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
