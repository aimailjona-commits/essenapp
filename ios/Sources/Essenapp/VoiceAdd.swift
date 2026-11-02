import SwiftUI

// Feature 45: Einkaufsliste per Sprache – Diktat (VoiceControl aus dem Kochmodus), Zerlegung per Regeln, Vorschau-Chips.

// MARK: Zerlegung (reine Funktionen)

enum ListParse {
    struct Item: Hashable {
        var name: String
        var amount: Double?
        var unit = ""
        var offer: OfferDTO?  // Laden-Zuordnung, wenn im Angebot

        var label: String {
            guard let amount else { return name }
            return "\(num(amount, 0...2)) \(unit == "stk" ? "Stück" : unit) \(name)"
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
                                       "brauchen", "kauf", "kaufe", "kaufen", "schreib", "schreibe", "setz", "setze"]
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
    }
    #endif
}

// MARK: Oberfläche

/// „Artikel hinzufügen“-Feld mit Mikrofon-Knopf (Haushaltsliste und einmalige Listen).
struct AddItemField: View {
    @Binding var text: String
    let add: () -> Void
    let voice: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                TextField("Artikel hinzufügen …", text: $text).onSubmit(add)
                Button(action: voice) {
                    Image(systemName: "mic.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.C.text2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Per Sprache hinzufügen")
            }
            .padding(.leading, 16).padding(.trailing, 2).frame(height: 46)
            .background(Theme.C.card, in: Capsule())
            RoundIconButton(systemName: "plus", dark: true, label: "Hinzufügen", action: add)
        }
    }
}

/// Glas-Overlay der Sprach-Eingabe: Pegel, erkannter Text, Vorschau-Chips (antippen = entfernen), „Hinzufügen“.
struct VoiceAddOverlay: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    let add: ([ListParse.Item]) -> Void
    let close: () -> Void
    @State private var voice = VoiceControl()
    @State private var earlier = ""  // Text vor einem Neustart des Mikrofons
    @State private var removed: Set<String> = []

    private var spoken: String { [earlier, voice.transcript].filter { t in !t.isEmpty }.joined(separator: ", ") }
    private var preview: [ListParse.Item] {
        ListParse.items(spoken).filter { i in !removed.contains(i.label) }.map { i in
            var hit = i
            hit.offer = ListParse.offer(for: i.name, in: store.offers)
            return hit
        }
    }

    var body: some View {
        let items = preview
        ZStack(alignment: .bottom) {
            Theme.C.scrim.ignoresSafeArea().onTapGesture(perform: close).transition(.opacity)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    if voice.listening || voice.note != nil {
                        VoicePill(voice: voice)
                    } else {
                        Button {
                            earlier = spoken
                            voice.transcript = ""
                            Task { await voice.toggle() }
                        } label: { Label("Weiter sprechen", systemImage: "mic.fill").font(Theme.F.callout) }
                        .buttonStyle(PressableStyle())
                        .padding(.horizontal, 16).frame(minHeight: 44).glass(Capsule())
                    }
                    Spacer()
                    RoundIconButton(systemName: "xmark", label: "Schließen", action: close)
                }
                Text(spoken.isEmpty ? "Sag z. B. „zwei Liter Milch, Eier und ein Brot“" : "„\(spoken)“")
                    .font(Theme.F.body).foregroundStyle(spoken.isEmpty ? Theme.C.text2 : Theme.C.text1)
                    .fixedSize(horizontal: false, vertical: true)
                if !items.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, entry in
                            Button { withAnimation(Theme.spring) { _ = removed.insert(entry.label) } } label: {
                                HStack(spacing: 6) {
                                    Text(entry.label)
                                    if let o = entry.offer { Text(Labels.chain(o.chain)).foregroundStyle(Theme.C.text2) }
                                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.C.text3)
                                }
                                .font(.system(.caption, weight: .semibold))
                                .padding(.horizontal, 13).frame(minHeight: 34)
                                .background(Theme.C.card, in: Capsule())
                                .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: 0.5))
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("\(entry.label) entfernen")
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                Button(items.isEmpty ? "Hinzufügen" : "\(items.count) hinzufügen") {
                    voice.stop()
                    add(items)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(items.isEmpty)
                .opacity(items.isEmpty ? 0.5 : 1)
            }
            .foregroundStyle(Theme.C.text1)
            .padding(18)
            .glass(RoundedRectangle(cornerRadius: Theme.R.sheet, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.bottom, Theme.ctaAboveTabBar)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(Theme.spring, value: items)
        .animation(Theme.spring, value: voice.listening)
        .sensoryFeedback(.selection, trigger: removed)
        .onChange(of: scenePhase) { if scenePhase != .active { voice.stop() } }
        .onAppear {
            #if DEBUG
            ListParse.selfTest()
            #endif
            voice.dictation = true
            voice.hints = ["Liter", "Gramm", "Kilo", "Packung", "Flasche", "Dose", "Stück"]
            if store.demo {
                voice.transcript = "zwei Liter Milch, Eier und ein Brot"
                voice.listening = true
                voice.level = 0.6
            } else {
                Task { await voice.toggle() }
            }
        }
        .onDisappear { voice.stop() }
    }
}

extension AppStore {
    /// Gesprochene Artikel nacheinander anlegen (offline → Warteschlange, 66) und kurz bestätigen.
    func addSpoken(_ items: [ListParse.Item], to listID: Int) async {
        flash(items.count == 1 ? "„\(items[0].name)“ hinzugefügt" : "\(items.count) Sachen hinzugefügt")
        for i in items {
            await addItem(name: i.name, amount: i.amount, unit: i.unit, chain: i.offer?.chain ?? "", offerId: i.offer?.id, to: listID)
        }
    }
}
