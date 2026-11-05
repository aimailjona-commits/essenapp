import SwiftUI

// Feature 45: Einkaufsliste per Sprache – Diktat (VoiceControl aus dem Kochmodus), Zerlegung per Regeln, Vorschau-Chips.

// MARK: Zerlegung (reine Funktionen)

/// Wohin gesprochene Posten gehen (22.2b).
enum VoiceTarget: String, CaseIterable {
    case list, pantry, watch

    var name: String { ["list": "Einkaufsliste", "pantry": "Vorrat", "watch": "Merkliste"][rawValue]! }
    var example: String {
        ["list": "zwei Liter Milch, Eier und ein Brot", "pantry": "3 Tomaten, Milch bis Freitag",
         "watch": "Kaffee, Butter und Lachs"][rawValue]!
    }
}

enum ListParse {
    struct Item: Hashable {
        var name: String
        var amount: Double?
        var unit = ""
        var offer: OfferDTO?  // Laden-Zuordnung, wenn im Angebot
        var bestBefore: Date?  // Vorrat: „bis Freitag“

        var label: String {
            let until = bestBefore.map { d in " · bis \(d.formatted(.dateTime.weekday(.abbreviated).day().month()))" } ?? ""
            guard let amount else { return name + until }
            return "\(num(amount, 0...2)) \(unit == "stk" ? "Stück" : unit) \(name)\(until)"
        }

        /// Vorrat kennt nur g | ml | stk: l/kg umrechnen, Packung/Flasche … als Stück.
        var pantry: PantryIn {
            let factor: Double = unit == "l" || unit == "kg" ? 1000 : 1
            let pantryUnit = amount == nil ? "" : ["l": "ml", "kg": "g", "g": "g", "ml": "ml"][unit] ?? "stk"
            return PantryIn(name: String(name.prefix(100)), amount: amount.map { a in a * factor }, unit: pantryUnit,
                            bestBefore: bestBefore?.formatted(PantryDTO.day), isBasic: false)
        }
    }

    // Einheit → (Einzahl, Mehrzahl); der Backend-Wert ist höchstens 10 Zeichen lang
    private static let units: [(words: Set<String>, one: String, many: String)] = [
        (["l", "liter"], "l", "l"), (["ml", "milliliter"], "ml", "ml"), (["g", "gr", "gramm"], "g", "g"),
        (["kg", "kilo", "kilogramm"], "kg", "kg"), (["stück", "stk"], "stk", "stk"),
        (["packung", "packungen", "päckchen", "pack", "packs"], "Packung", "Packungen"),
        (["flasche", "flaschen"], "Flasche", "Flaschen"), (["dose", "dosen"], "Dose", "Dosen"),
        (["glas", "gläser"], "Glas", "Gläser"), (["becher"], "Becher", "Becher"), (["bund"], "Bund", "Bund"),
        (["kiste", "kisten"], "Kiste", "Kisten"),
    ]
    private static let fractions: [String: Double] = ["halb": 0.5, "halbe": 0.5, "halben": 0.5, "halbes": 0.5, "anderthalb": 1.5,
                                                      "eineinhalb": 1.5, "zweieinhalb": 2.5, "einen": 1, "einem": 1]
    private static let leading: Set = ["und", "noch", "bitte", "auch", "dann", "etwas", "mal", "außerdem", "ich", "wir", "brauche",
                                       "brauchen", "kauf", "kaufe", "kaufen", "schreib", "schreibe", "setz", "setze", "tu", "leg", "lege",
                                       "stell", "stelle", "trag", "trage", "notier", "notiere"]
    private static let trailing = ["auf die liste", "auf die einkaufsliste", "kaufen", "bitte", "mitbringen"]

    /// „zwei Liter Milch, Eier und ein Brot“ → [2 l Milch, Eier, 1 Stück Brot]. Trennt an Komma/Punkt (nicht in „1,5“),
    /// „und“, „sowie“, „plus“.
    static func items(_ text: String) -> [Item] {
        let split = text.replacingOccurrences(of: #"\s*(?:(?<!\d)[,.;]|[,.;](?!\d))\s*|\s+(?:und|sowie|plus)\s+"#, with: "|",
                                              options: [.regularExpression, .caseInsensitive])
        return split.split(separator: "|").compactMap { part in item(String(part)) }
    }

    static func item(_ part: String) -> Item? {
        var words = part.split(separator: " ").map(String.init)
        while let w = words.first, leading.contains(w.lowercased()) { words.removeFirst() }
        var tail = words.joined(separator: " ").lowercased()
        for t in trailing where tail.hasSuffix(" " + t) {
            words.removeLast(t.split(separator: " ").count)
            tail = words.joined(separator: " ").lowercased()
        }
        var amount: Double?
        if let w = words.first?.lowercased() {
            amount = Double(w.replacingOccurrences(of: ",", with: ".")) ?? CookParse.numberWords[w].flatMap(Double.init) ?? fractions[w]
            if amount != nil { words.removeFirst() }
        }
        if let w = words.first?.lowercased(), let f = fractions[w], f < 1 {  // „ein halbes Kilo“
            amount = amount == 1 || amount == nil ? f : (amount ?? 0) + f
            words.removeFirst()
        }
        var unit = ""
        if amount != nil, let w = words.first?.lowercased(), let u = units.first(where: { u in u.words.contains(w) }), words.count > 1 {
            unit = amount == 1 ? u.one : u.many
            words.removeFirst()
        } else if amount != nil {
            unit = "stk"  // „ein Brot“, „6 Eier“
        }
        let name = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !name.isEmpty else { return nil }
        return Item(name: name.prefix(1).uppercased() + name.dropFirst(), amount: amount, unit: unit)
    }

    /// Laden-Zuordnung: günstigstes Angebot, dessen Titel alle Wörter des Artikels nennt; genaues Wort vor Kompositum.
    static func offer(for name: String, in offers: [OfferDTO]) -> OfferDTO? {
        let words = CookParse.words(name)
        guard let head = words.last else { return nil }
        let hits = offers.filter { o in words.allSatisfy { w in CookParse.mentions(w, in: o.title) } }
        let exact = hits.filter { o in CookParse.words(o.title).contains(head) }
        return (exact.isEmpty ? hits : exact).min { a, b in a.priceCents < b.priceCents }
    }

    // Ziel-Signalwörter; „Bescheid, wenn … im Angebot“ behält das Dazwischen
    private static let routes: [(VoiceTarget, [String])] = [
        (.watch, [#"\b(?:sag\s+)?(?:mir\s+|uns\s+)?bescheid,?\s+wenn\b"#, #"\bim\s+angebot(?:\s+(?:ist|sind))?\b"#,
                  #"\b(?:auf\s+die\s+|zur\s+|in\s+die\s+)?merkliste\b"#, #"\bmerk(?:e|en)?(?:\s+(?:dir|mir|euch))?\b"#]),
        (.pantry, [#"\b(?:in\s+den|zum|im|ins)\s+(?:vorrat|kühlschrank|gefrierfach|tiefkühler)\b"#,
                   #"\b(?:(?:ich|wir)\s+)?(?:hab|habe|haben)\s+noch\b"#]),
    ]

    /// Ziel aus dem Satz: „merk dir …“ → Merkliste, „… in den Vorrat“/„hab noch …“ → Vorrat, sonst Einkaufsliste.
    /// Signalwörter werden entfernt.
    static func route(_ text: String) -> (target: VoiceTarget, text: String) {
        let opts: String.CompareOptions = [.regularExpression, .caseInsensitive]
        guard let hit = routes.first(where: { r in r.1.contains { p in text.range(of: p, options: opts) != nil } }) else {
            return (.list, text)
        }
        let rest = hit.1.reduce(text) { t, p in t.replacingOccurrences(of: p, with: " ", options: opts) }
        return (hit.0, rest.trimmingCharacters(in: .whitespaces))
    }

    private static let weekdays = ["sonntag", "montag", "dienstag", "mittwoch", "donnerstag", "freitag", "samstag"]

    /// Haltbarkeit am Ende des Namens: „Milch bis Freitag“, „… bis morgen“, „… in 3 Tagen“, „… in einer Woche“.
    static func expiry(_ name: String, today: Date = .now) -> (name: String, date: Date?) {
        var words = name.split(separator: " ").map(String.init)
        let low = words.map { w in w.lowercased() }
        let n = low.count
        var days: Int?
        var cut = n
        if n >= 3, low[n - 2] == "bis" {
            let wd = Calendar.current.component(.weekday, from: today)
            if let d = ["heute": 0, "morgen": 1, "übermorgen": 2][low[n - 1]] {
                days = d
            } else if let i = weekdays.firstIndex(of: low[n - 1]) {
                days = (i + 1 - wd + 7) % 7 == 0 ? 7 : (i + 1 - wd + 7) % 7
            }
            cut = n - 2
        } else if n >= 4, low[n - 3] == "in", ["tag", "tagen", "woche", "wochen"].contains(low[n - 1]),
                  let k = Int(CookParse.numberWords[low[n - 2]] ?? (low[n - 2] == "einem" ? "1" : low[n - 2])) {
            days = low[n - 1].hasPrefix("woche") ? k * 7 : k
            cut = n - 3
        }
        guard let days else { return (name, nil) }
        if cut > 1, low[cut - 1] == "haltbar" { cut -= 1 }
        words.removeLast(n - cut)
        return (words.joined(separator: " "), Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: today)))
    }

    #if DEBUG
    /// Testsätze (Abnahme 45: ≥ 9 von 10 korrekt); läuft beim Öffnen der Sprach-Eingabe in Debug-Builds.
    static func selfTest() {
        func check(_ text: String, _ expected: [String]) { assert(items(text).map(\.label) == expected, "\(text) → \(items(text).map(\.label))") }
        check("zwei Liter Milch, Eier und ein Brot", ["2 l Milch", "Eier", "1 Stück Brot"])
        check("2 l Milch, 6 Eier und 500 g Hackfleisch", ["2 l Milch", "6 Stück Eier", "500 g Hackfleisch"])
        check("1,5 Liter Apfelsaft und Butter", ["1,5 l Apfelsaft", "Butter"])
        check("ein halbes Kilo Tomaten", ["0,5 kg Tomaten"])
        check("Wir brauchen noch Käse, Gurke sowie drei Paprika", ["Käse", "Gurke", "3 Stück Paprika"])
        check("zwei Packungen Nudeln plus eine Dose Mais", ["2 Packungen Nudeln", "1 Dose Mais"])
        check("Bananen. Äpfel. Joghurt", ["Bananen", "Äpfel", "Joghurt"])
        check("Klopapier und Spülmittel auf die Liste", ["Klopapier", "Spülmittel"])
        check("eine Kiste Wasser und zwei Flaschen Cola", ["1 Kiste Wasser", "2 Flaschen Cola"])
        check("200 Gramm Feta, Oliven und anderthalb Liter Sahne", ["200 g Feta", "Oliven", "1,5 l Sahne"])
        assert(items("Liter") == [Item(name: "Liter")] && items("zwei").isEmpty)
        let milk = Demo.offer(9, "rewe", "Weihenstephan H-Milch", "kuehlung", 119, nil, 1, "l", 119)
        let choc = Demo.offer(10, "lidl", "Milchschokolade", "vorrat", 79, nil, 100, "g", 790)
        assert(offer(for: "Milch", in: [choc, milk])?.id == 9 && offer(for: "Brot", in: [milk]) == nil)

        func checkRoute(_ text: String, _ target: VoiceTarget, _ expected: [String]) {
            let r = route(text)
            assert(r.target == target && items(r.text).map(\.label) == expected, "\(text) → \(r.target) \(items(r.text).map(\.label))")
        }
        checkRoute("Merk dir Kaffee, Butter und Lachs", .watch, ["Kaffee", "Butter", "Lachs"])
        checkRoute("Sag mir Bescheid, wenn Lachs im Angebot ist", .watch, ["Lachs"])
        checkRoute("Kaffee auf die Merkliste", .watch, ["Kaffee"])
        checkRoute("Ich habe noch 3 Tomaten und Milch", .pantry, ["3 Stück Tomaten", "Milch"])
        checkRoute("Tu zwei Joghurt in den Kühlschrank", .pantry, ["2 Stück Joghurt"])
        checkRoute("zwei Liter Milch und Brot", .list, ["2 l Milch", "Brot"])
        checkRoute("Milch im Kühlschrank", .pantry, ["Milch"])

        let thu = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 5))!  // Donnerstag
        func expires(_ name: String, _ rest: String, _ days: Int?) {
            let e = expiry(name, today: thu)
            let got = e.date.map { d in Calendar.current.dateComponents([.day], from: thu, to: d).day! }
            assert(e.name == rest && got == days, "\(name) → \(e.name) \(String(describing: got))")
        }
        expires("Milch bis Freitag", "Milch", 1)
        expires("Feta bis Donnerstag", "Feta", 7)
        expires("Joghurt bis morgen", "Joghurt", 1)
        expires("Hack in 3 Tagen", "Hack", 3)
        expires("Käse haltbar in einer Woche", "Käse", 7)
        expires("Brot", "Brot", nil)
        expires("bis morgen", "bis morgen", nil)
        let tomatoes = Item(name: "Tomaten", amount: 1.5, unit: "kg").pantry
        assert(tomatoes.amount == 1500 && tomatoes.unit == "g" && Item(name: "Nudeln", amount: 2, unit: "Packungen").pantry.unit == "stk")
    }
    #endif
}

// MARK: Oberfläche

/// „Artikel hinzufügen …“ als `.irow` (Haushaltsliste und einmalige Listen): Plus, Eingabe, Mikrofon.
struct AddItemField: View {
    @Binding var text: String
    let add: () -> Void
    let voice: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: add) { Icon(.plus).tapArea() }
                .buttonStyle(.plain)
                .foregroundStyle(text.isEmpty ? Theme.C.ink3 : Theme.C.ink)
                .accessibilityLabel("Hinzufügen")
            TextField("", text: $text, prompt: Text("Artikel hinzufügen …").foregroundStyle(Theme.C.ink3))
                .font(Theme.F.text(16))
                .foregroundStyle(Theme.C.ink)
                .submitLabel(.done)
                .onSubmit(add)
            Button(action: voice) { Icon(.mic).foregroundStyle(Theme.C.ink).tapArea() }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Per Sprache hinzufügen")
        }
        .frame(minHeight: Theme.S.row)
        .overlay(alignment: .top) { Hairline() }
    }
}

extension View {
    /// Glas-Fläche (`.d-glass`): Creme 74 % über Weichzeichner, weicher Schatten.
    func glass8<S: Shape>(_ shape: S) -> some View {
        background(Theme.C.card.opacity(0.74), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .shadow(color: Theme.C.ink.opacity(0.12), radius: 15, y: 10)
    }
}

/// Sprach-Eingabe (d.html „Sprach-Eingabe“): Glas-Fläche unten, Pille „hört zu …“ mit Pegel, erkannter Satz,
/// Vorschau-Chips (✕ entfernt), „3 hinzufügen“.
struct VoiceAddOverlay: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    /// Ziel der Posten; `switchable` zeigt den Umschalter und belegt das Ziel aus dem Satz vor („Alles“ › Per Sprache).
    var target: Binding<VoiceTarget> = .constant(.list)
    var switchable = false
    let add: ([ListParse.Item]) -> Void
    let close: () -> Void
    @State private var voice = VoiceControl()
    @State private var earlier = ""  // Text vor einem Neustart des Mikrofons
    @State private var removed: Set<String> = []
    @State private var picked = false  // Ziel von Hand gewählt → nicht mehr aus dem Satz übernehmen

    private static let bars: [CGFloat] = [6, 14, 20, 10, 16, 7]  // Pegel-Striche aus dem Mockup

    private var spoken: String { [earlier, voice.transcript].filter { t in !t.isEmpty }.joined(separator: ", ") }
    private var preview: [ListParse.Item] {
        let goal = target.wrappedValue
        return ListParse.items(ListParse.route(spoken).text).map { i in
            var hit = i
            switch goal {
            case .list: hit.offer = ListParse.offer(for: i.name, in: store.offers)
            case .pantry:
                let e = ListParse.expiry(i.name)
                hit.name = e.name
                hit.bestBefore = e.date
            case .watch:  // Merk-Begriffe ohne Menge
                hit.amount = nil
                hit.unit = ""
            }
            return hit
        }
        .filter { i in !removed.contains(i.label) }
    }

    var body: some View {
        let items = preview
        let shape = UnevenRoundedRectangle(topLeadingRadius: Theme.R.sheet, topTrailingRadius: Theme.R.sheet, style: .continuous)
        ZStack(alignment: .bottom) {
            Theme.C.scrim.ignoresSafeArea().onTapGesture(perform: close).transition(.opacity)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    pill
                    Spacer()
                    CloseButton(action: close)
                }
                Text(spoken.isEmpty ? "Sag z. B. „\(target.wrappedValue.example)“" : "„\(spoken)“")
                    .font(Theme.F.t2)
                    .foregroundStyle(spoken.isEmpty ? Theme.C.ink2 : Theme.C.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)
                if switchable { targets.padding(.top, 18) }
                if !items.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, entry in chip(entry) }
                    }
                    .padding(.top, 18)
                }
                PrimaryButton(title: buttonTitle(items.count), disabled: items.isEmpty) {
                    voice.stop()
                    add(items)
                }
                .padding(.top, 24)
            }
            .padding(.top, 22).padding(.horizontal, Theme.pagePadding).padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass8(shape)
            .ignoresSafeArea(edges: .bottom)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .hidesTabBar()
        .animation(Theme.spring, value: items)
        .animation(Theme.spring, value: voice.listening)
        .sensoryFeedback(.selection, trigger: removed)
        .onChange(of: scenePhase) { if scenePhase != .active { voice.stop() } }
        .onChange(of: spoken) { if switchable && !picked { target.wrappedValue = ListParse.route(spoken).target } }
        .onAppear {
            #if DEBUG
            ListParse.selfTest()
            #endif
            voice.dictation = true
            voice.hints = ["Liter", "Gramm", "Kilo", "Packung", "Flasche", "Dose", "Stück", "Vorrat", "Kühlschrank", "Merkliste"]
            if store.demo {
                voice.transcript = target.wrappedValue.example
                voice.listening = true
                voice.level = 0.6
            } else {
                Task { await voice.toggle() }
            }
        }
        .onDisappear { voice.stop() }
    }

    private func buttonTitle(_ n: Int) -> String {
        guard n > 0 else { return "Hinzufügen" }
        switch target.wrappedValue {
        case .list: return "\(n) hinzufügen"
        case .pantry: return "\(n) in den Vorrat"
        case .watch: return "\(n) merken"
        }
    }

    /// Ziel-Umschalter im Chip-Stil: Einkaufsliste | Vorrat | Merkliste, gewählt = Tinte.
    private var targets: some View {
        HStack(spacing: 8) {
            ForEach(VoiceTarget.allCases, id: \.self) { t in
                let on = target.wrappedValue == t
                Button {
                    picked = true
                    withAnimation(Theme.spring) { target.wrappedValue = t }
                } label: {
                    Text(t.name)
                        .font(Theme.F.chip)
                        .foregroundStyle(on ? Theme.C.onInk : Theme.C.ink)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 14)
                        .frame(minHeight: Theme.S.chip)
                        .background(on ? Theme.C.ink : Theme.C.card, in: Capsule())
                        .overlay { if !on { Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
                        .tapArea(4)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Ziel \(t.name)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: target.wrappedValue)
    }

    /// Tinten-Pille 44 hoch: „hört zu …“ mit weißem Pegel; sonst Hinweis bzw. „Weiter sprechen“.
    private var pill: some View {
        Button {
            guard !voice.listening else { return }
            earlier = spoken
            voice.transcript = ""
            Task { await voice.toggle() }
        } label: {
            HStack(spacing: 6) {
                Icon(.mic, size: 18)
                if voice.listening {
                    Text("hört zu …")
                    HStack(spacing: 3) {
                        ForEach(Self.bars.indices, id: \.self) { i in
                            Capsule().fill(Theme.C.onInk).frame(width: 3, height: max(3, Self.bars[i] * CGFloat(0.4 + voice.level)))
                        }
                    }
                    .frame(height: 22)
                    .padding(.leading, 4)
                    .animation(.easeOut(duration: 0.1), value: voice.level)
                } else {
                    Text(voice.note ?? "Weiter sprechen").lineLimit(2)
                }
            }
            .font(Theme.F.text(15, .bold, relativeTo: .subheadline))
            .foregroundStyle(Theme.C.onInk)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(Theme.C.ink, in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(voice.listening ? "Hört zu" : "Weiter sprechen")
    }

    /// `.d-chip`: Artikel, Laden grau, ✕ entfernt.
    private func chip(_ entry: ListParse.Item) -> some View {
        Button { withAnimation(Theme.spring) { _ = removed.insert(entry.label) } } label: {
            HStack(spacing: 6) {
                Text(entry.label).foregroundStyle(Theme.C.ink)
                if let o = entry.offer { Text(Labels.chain(o.chain)).foregroundStyle(Theme.C.ink2) }
                Icon(.x, size: 15).foregroundStyle(Theme.C.ink2)
            }
            .font(Theme.F.chip)
            .padding(.leading, 14).padding(.trailing, 10)
            .frame(minHeight: Theme.S.chip)
            .background(Theme.C.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
            .tapArea(4)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(entry.label) entfernen")
        .transition(.scale.combined(with: .opacity))
    }
}

extension AppStore {
    /// Gesprochene Artikel nacheinander anlegen (offline → Warteschlange, 66) und kurz bestätigen.
    /// `chain`: Laden für Artikel ohne passendes Angebot (Laden-Liste S5b).
    /// Gesprochene Posten an ihr Ziel: Einkaufsliste (Haushalt), Vorrat oder Merkliste (22.2b).
    func addSpoken(_ items: [ListParse.Item], target: VoiceTarget) async {
        switch target {
        case .list:
            guard let id = householdList?.id else { flash("Einkaufsliste nicht geladen"); return }
            await addSpoken(items, to: id)
        case .pantry:
            do {
                for i in items { try await addPantry(i.pantry) }
                flash(items.count == 1 ? "„\(items[0].name)“ im Vorrat" : "\(items.count) Sachen im Vorrat")
            } catch {
                flash("Nicht gespeichert: \(error.localizedDescription)")
            }
        case .watch:
            for i in items { await addWatch(WatchIn(label: String(i.name.prefix(200)))) }
        }
    }

    func addSpoken(_ items: [ListParse.Item], to listID: Int, chain: String = "") async {
        flash(items.count == 1 ? "„\(items[0].name)“ hinzugefügt" : "\(items.count) Sachen hinzugefügt")
        for i in items {
            await addItem(name: i.name, amount: i.amount, unit: i.unit, chain: i.offer?.chain ?? chain, offerId: i.offer?.id, to: listID)
        }
    }
}
