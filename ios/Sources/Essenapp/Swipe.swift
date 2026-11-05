import SwiftUI

// MARK: API (Phase 20, E97)

struct SwipeCardDTO: Codable, Identifiable, Hashable {
    var id: Int
    var mealType: String
    var source: String  // ki | rezept
    var recipeId: Int?
    var title: String
    var description: String
    var cuisine: String
    var prepMinutes: Int
    var imageUrl: String
    var costCents: Int  // pro Portion
    var deals: Int
    var chain: String
    var match = false
    var yes = 0
    var days = 1
    var ingredients: [String] = []
}

struct SlotCardDTO: Codable, Hashable {
    var day: Int
    var mealType: String
    var cardId: Int
}

struct SwipeDTO: Codable {
    var id: Int
    var state: String
    var loading: Bool
    var error: String
    var need: [String: Int]
    var have: [String: Int]
    var ready: Bool
    var cards: [SwipeCardDTO]  // noch zu entscheiden (für mich)
    var chosen: [SwipeCardDTO]  // gewählt, je Art Matches zuerst
    var members: [String]
    var slots: [SlotCardDTO]

    static let repeats = ["fruehstueck", "snack"]  // ein Gericht, mehrere Tage (= Backend swipe.REPEAT)

    var types: [String] { need.keys.sorted { (Labels.slotOrder.firstIndex(of: $0) ?? 9) < (Labels.slotOrder.firstIndex(of: $1) ?? 9) } }
    func done(_ m: String) -> Bool { (have[m] ?? 0) >= (need[m] ?? 0) }

    /// Auswahl je Art bis die Plätze voll sind (Frühstück/Snack zählen Tage), der Rest ist Reserve.
    var split: (picked: [String: [SwipeCardDTO]], reserve: [SwipeCardDTO]) {
        var picked: [String: [SwipeCardDTO]] = [:], reserve: [SwipeCardDTO] = [], used: [String: Int] = [:]
        for c in chosen {
            if used[c.mealType, default: 0] < need[c.mealType, default: 0] {
                picked[c.mealType, default: []].append(c)
                used[c.mealType, default: 0] += Self.repeats.contains(c.mealType) ? c.days : 1
            } else {
                reserve.append(c)
            }
        }
        return (picked, reserve)
    }
}

/// Platz der Woche als Schlüssel (Ziehen und Ablegen).
struct SwipeSlot: Hashable {
    var day: Int
    var mealType: String
    var key: String { "slot:\(day):\(mealType)" }
}

// MARK: S41 Stapel

/// Woche per Swipe (S41–S44): Vollbild aus „Woche planen“; läuft ein Stapel, geht es dort weiter.
struct SwipeView: View {
    enum Stage { case stack, selection, week(manual: Bool) }

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var deck: SwipeDTO? = Demo.screen == nil ? nil : Demo.swipe
    @State private var stage: Stage = Demo.screen == "auswahl" ? .selection : Demo.screen == "verteilen" ? .week(manual: false) : .stack
    @State private var mealType = ""  // aktiver Stapel
    @State private var error: String?
    @State private var match: SwipeCardDTO? = Demo.screen == "match" ? Demo.swipe.chosen.first { $0.match } : nil
    @State private var drag = CGSize.zero
    @State private var crossed = false
    @State private var disliking: SwipeCardDTO? = Demo.screen == "magnicht" ? Demo.swipe.cards.first : nil  // bleibt bis zur Entscheidung
    @State private var dislikeOpen = Demo.screen == "magnicht"
    @State private var days: [Int: Int] = [:]  // Frühstück/Snack: Tage je Karte
    @State private var voting = 0  // laufende Stimmen: Abfrage überschreibt dann nichts
    @State private var asked: Set<String> = []  // „mehr Karten“ je Art schon angefragt
    @State private var matches: Set<Int>?  // bekannte Matches → Banner bei neuen
    @State private var surprise = false
    @State private var planBefore: Int?
    @State private var landed: [SwipeCardDTO] = []  // nach links geschoben, Teller liegt schon (Antwort steht noch aus)
    @State private var flight: Flight?
    @State private var flying: Int?  // Karte, deren Foto gerade fliegt (ausgeblendet)
    @State private var photo = CGRect.zero
    @State private var slotFrames: [Int: CGRect] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Flight { var url: URL?; var rect: CGRect }

    private let threshold: CGFloat = 110

    var body: some View {
        ZStack {
            Theme.C.bg.ignoresSafeArea()
            switch stage {
            case .stack: stack
            case .selection:
                if let deck {
                    SwipeSelection(deck: deck, persons: store.household?.persons ?? 1, back: { go(.stack) },
                                   distribute: { go(.week(manual: false)) }, manual: { go(.week(manual: true)) })
                }
            case .week(let manual):
                if let deck {
                    SwipeWeek(deck: deck, manual: manual, persons: store.household?.persons ?? 1, back: { go(.selection) }) { dismiss() }
                }
            }
            if let match {
                MatchView(card: match, members: deck?.members ?? []) { withAnimation(Theme.spring) { self.match = nil } }
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
                    .zIndex(2)
            }
        }
        .task { await poll() }
        .sheet(isPresented: $surprise, onDismiss: { if store.plan?.id != planBefore { dismiss() } }) {
            PlanGeneratorSheet().presentationDetents([.large])
        }
    }

    private func go(_ s: Stage) { withAnimation(Theme.spring) { stage = s } }

    private var pile: [SwipeCardDTO] { deck?.cards.filter { $0.mealType == mealType } ?? [] }

    nonisolated static let space = "swipe"  // Koordinatenraum für den fliegenden Teller

    /// Wochen-Tisch (v9 e.html A): links sieben Teller im Bogen, rechts die Rezeptkarte.
    private var stack: some View {
        VStack(alignment: .leading, spacing: 0) {
            head.padding(.horizontal, Theme.pagePadding)
            if let error, deck == nil {
                SwipeNote(ill: "binoculars", title: "Das hat nicht geklappt", text: error, button: "Erneut versuchen") { Task { await load() } }
                    .frame(maxHeight: .infinity).padding(.horizontal, Theme.pagePadding)
            } else if let deck {
                table(deck)
            } else {
                VStack(spacing: 18) { PotLoader(); Skeleton8(width: 200, height: 20) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text("Würfel = Überrasch mich: KI plant den Rest")
                .font(Theme.F.text(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                .frame(maxWidth: .infinity).padding(.top, 12).padding(.horizontal, Theme.pagePadding)
        }
        .padding(.bottom, 8)
        .coordinateSpace(.named(Self.space))
        .overlay(alignment: .topLeading) {
            if let flight {
                PlanPlate(url: flight.url, size: flight.rect.width)
                    .position(x: flight.rect.midX, y: flight.rect.midY)
                    .allowsHitTesting(false)
            }
        }
        .modifier(DislikeDialog(ingredients: disliking?.ingredients ?? [],
                                isPresented: $dislikeOpen,
                                noMood: { if let c = disliking { send(c, "mag_nicht", reason: "keine_lust") } },
                                title: disliking?.title ?? "") { reason in
            guard let c = disliking else { return }
            switch reason {
            case .ingredient(let name): send(c, "mag_nicht", reason: "zutat", ingredient: name)
            case .taste: send(c, "mag_nicht", reason: "schmeckt_nicht")
            case .other(let text): send(c, "mag_nicht", reason: "sonstiges", note: text)
            }
        })
    }

    private var week: Int { Calendar(identifier: .iso8601).component(.weekOfYear, from: .now) }

    /// „KW 45 · 2.–8. Nov“
    private var weekRange: String {
        let cal = Calendar(identifier: .iso8601)
        guard let w = cal.dateInterval(of: .weekOfYear, for: .now) else { return "KW \(week)" }
        let end = w.end.addingTimeInterval(-1)
        let month = end.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "de_DE"))).trimmingCharacters(in: .punctuationCharacters)
        return "KW \(week) · \(cal.component(.day, from: w.start)).–\(cal.component(.day, from: end)). \(month)"
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                CircleButton(icon: .back, label: "Zurück") { dismiss() }
                Spacer()
                if deck?.ready == true {
                    Button("Fertig") { Task { await refresh(); go(.selection) } }
                        .font(Theme.F.chip).foregroundStyle(Theme.C.onInk)
                        .padding(.horizontal, 16).frame(height: Theme.S.chip).background(Theme.C.ink, in: Capsule())
                        .frame(minHeight: 44).buttonStyle(PressableStyle())
                }
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(weekRange).font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                    Text("Woche \(week)").font(Theme.F.serif(32, relativeTo: .largeTitle))
                }
                Spacer(minLength: 8)
                if let members = deck?.members, !members.isEmpty {
                    HStack(spacing: 8) {
                        Text("swipen mit").font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                        HStack(spacing: -10) {
                            ForEach(Array(members.enumerated()), id: \.offset) { i, n in Initial(name: n, index: i, size: 34) }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
            .padding(.top, 4)
            if let deck { pills(deck) }
        }
    }

    /// Fortschritt je Mahlzeitart (`.e9-mt`): Chip, darunter Strich mit Anteil; aktiv = Tinte, fertig = Haken. Antippen wechselt den Stapel.
    private func pills(_ deck: SwipeDTO) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(deck.types, id: \.self) { m in
                    let on = m == mealType, n = deck.need[m] ?? 0, h = deck.have[m] ?? 0
                    Button { withAnimation(Theme.spring) { mealType = m } } label: {
                        HStack(spacing: 6) {
                            if deck.done(m) { Icon(.check, size: 14) }
                            Text(deck.done(m) ? Labels.meal(m) : "\(Labels.meal(m)) \(h)/\(n)")
                        }
                        .font(Theme.F.text(13, .bold, relativeTo: .footnote)).monospacedDigit()
                        .foregroundStyle(on ? Theme.C.onInk : Theme.C.ink2)
                        .padding(.horizontal, 15).frame(height: 32)
                        .background(on ? Theme.C.ink : .clear, in: Capsule())
                        .overlay { if !on { Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
                        .padding(.bottom, 8)
                        .overlay(alignment: .bottom) {
                            Capsule().fill(Theme.C.line).frame(height: 3)
                                .overlay {
                                    Capsule().fill(Theme.C.ink)
                                        .scaleEffect(x: min(CGFloat(h) / CGFloat(max(n, 1)), 1), y: 1, anchor: .leading)
                                }
                                .animation(.easeOut(duration: 0.4), value: h)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("\(Labels.meal(m)), \(h) von \(n)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .padding(.top, 10)
        .sensoryFeedback(.selection, trigger: mealType)
    }

    /// Ein Tagesplatz im Bogen: frei, belegt (Teller) oder der nächste freie (Ring pulsiert, wächst beim Ziehen nach links).
    private struct RailSlot { var day: Int; var open: Bool; var card: SwipeCardDTO? }

    private func rail(_ deck: SwipeDTO) -> [RailSlot] {
        let m = mealType, rep = SwipeDTO.repeats.contains(m)
        let picked = (deck.split.picked[m] ?? []).flatMap { c in Array(repeating: c, count: rep ? c.days : 1) }
        // gerade nach links geschoben, Server hat noch nicht geantwortet (bzw. Demo)
        let fresh = landed.filter { l in l.mealType == m && !deck.chosen.contains { $0.id == l.id } && !deck.cards.contains { $0.id == l.id } }
            .flatMap { c in Array(repeating: c, count: rep ? days[c.id] ?? defaultDays(c) : 1) }
        var plates = (picked + fresh).makeIterator()
        let open = Set(deck.slots.filter { $0.mealType == m }.map(\.day))
        return (0..<7).map { d in RailSlot(day: d, open: open.contains(d), card: open.contains(d) ? plates.next() : nil) }
    }

    private func table(_ deck: SwipeDTO) -> some View {
        let slots = rail(deck), next = slots.first { $0.open && $0.card == nil }?.day
        let grow = max(0, -drag.width) * 0.5, arc = 150 + grow  // Bogen wächst beim Ziehen nach links
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 8) {
                ForEach(slots, id: \.day) { s in slotView(s, next: s.day == next) }
            }
            .frame(width: 44)
            .padding(.leading, 19).padding(.top, 4)
            VStack(spacing: 0) {
                cardArea(deck).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                buttons.padding(.top, 18)
            }
            .padding(.leading, 37).padding(.trailing, 20)
        }
        .padding(.top, 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .pinned(left: -60 - arc, top: 14) {
            RoundedRectangle(cornerRadius: min(arc, 260)).fill(mealTint(mealType))
                .frame(width: arc * 2, height: 520)  // linke Hälfte liegt außerhalb: Bogen wie CSS 0 260 260 0
                .accessibilityHidden(true)
        }
        .pinned(right: -120, top: 118) {
            Ellipse().fill(Theme.C.rose).frame(width: 200, height: 300)
                .opacity(Double(min(1, max(0, drag.width) / 140)))
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func slotView(_ s: RailSlot, next: Bool) -> some View {
        VStack(spacing: 2) {
            Text(Labels.days[s.day]).font(Theme.F.text(10, .extrabold, relativeTo: .caption2)).tracking(0.6)
                .foregroundStyle(next ? Theme.C.ink : Theme.C.ink2)
            ZStack {
                if let c = s.card {
                    PlanPlate(url: mediaURL(c.imageUrl), size: 44, mini: true)
                        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.scale(scale: 0.4).combined(with: .opacity))
                } else {
                    Circle().fill(Theme.C.bg)
                        .overlay(Circle().strokeBorder(next ? Theme.C.ink : Theme.C.line, lineWidth: Theme.S.hair))
                        .background {
                            if next && !reduceMotion {
                                Circle().fill(Theme.C.ink.opacity(0.08)).padding(-7)
                                    .phaseAnimator([false, true]) { v, on in v.opacity(on ? 1 : 0) } animation: { _ in .easeInOut(duration: 0.8) }
                            }
                        }
                }
            }
            .frame(width: 44, height: 44)
            .scaleEffect(next && drag.width < 0 ? 1 + min(0.3, -drag.width / 400) : 1)
            .onGeometryChange(for: CGRect.self) { g in g.frame(in: .named(Self.space)) } action: { f in slotFrames[s.day] = f }
        }
        .opacity(s.open ? 1 : 0.35)  // Tag ohne Platz dieser Art
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Labels.days[s.day]): \(s.card?.title ?? (s.open ? "frei" : "kein Platz"))")
    }

    @ViewBuilder private func cardArea(_ deck: SwipeDTO) -> some View {
        if !deck.error.isEmpty, pile.isEmpty {
            SwipeNote(ill: "binoculars", title: "Das hat nicht geklappt", text: deck.error, button: "Erneut versuchen") { Task { await more(force: true) } }
        } else if deck.loading && deck.cards.isEmpty {
            VStack(spacing: 18) { PotLoader(); Skeleton8(width: 200, height: 20) }.frame(maxHeight: .infinity)
        } else if pile.isEmpty {
            VStack(spacing: 14) { Hop3(); SwipeNote(ill: "cookbook", title: "Stapel lädt nach …", text: "Neue Ideen aus den Angeboten") }
                .frame(maxHeight: .infinity)
        } else {
            ZStack {
                if pile.count > 1 {  // `.e9a-peek`: nächste Karte schräg dahinter
                    RoundedRectangle(cornerRadius: Theme.R.swipeCard, style: .continuous).fill(Theme.C.card)
                        .shadow(color: Theme.C.ink.opacity(0.06), radius: 9, y: 6)
                        .scaleEffect(0.97).rotationEffect(.degrees(3)).offset(x: 4, y: 6)
                        .accessibilityHidden(true)
                }
                topCard(pile[0])
            }
            .frame(maxHeight: 404)
        }
    }

    private func topCard(_ card: SwipeCardDTO) -> some View {
        let repeats = SwipeDTO.repeats.contains(card.mealType)
        let binding = Binding<Int?>(get: { repeats ? days[card.id] ?? defaultDays(card) : nil },
                                    set: { v in days[card.id] = v })
        return SwipeCardFace(card: card, days: binding, maxDays: deck?.need[card.mealType] ?? 7) { f in photo = f }
            .opacity(flying == card.id ? 0 : 1)
            .offset(drag)
            .rotationEffect(.degrees(Double(drag.width) / 18))
            .gesture(
                DragGesture()
                    .onChanged { v in
                        drag = v.translation
                        crossed = decision(v.translation) != nil
                    }
                    .onEnded { v in
                        if let d = decision(v.translation) { decide(card, d) } else { withAnimation(Theme.spring) { drag = .zero } }
                    }
            )
            .sensoryFeedback(trigger: crossed) { _, now in now ? .impact(weight: .medium) : nil }
            .accessibilityElement(children: .combine)
            .accessibilityAction(named: "Diese Woche") { decide(card, "ja") }
            .accessibilityAction(named: "Nicht") { decide(card, "nein") }
            .accessibilityAction(named: "Mag ich nicht") { decide(card, "mag_nicht") }
    }

    private func decision(_ t: CGSize) -> String? {
        // links = mag ich (E100)
        if abs(t.width) > abs(t.height) { return t.width < -threshold ? "ja" : t.width > threshold ? "nein" : nil }
        return t.height < -threshold ? "mag_nicht" : nil
    }

    private func defaultDays(_ card: SwipeCardDTO) -> Int {
        max((deck?.need[card.mealType] ?? 1) - (deck?.have[card.mealType] ?? 0), 1)
    }

    /// Links: Foto fliegt als Teller auf den nächsten freien Tag. Rechts: Karte fliegt raus.
    /// „Mag ich nicht“ federt zurück und fragt nach dem Grund.
    private func decide(_ card: SwipeCardDTO, _ kind: String) {
        if kind == "mag_nicht" {
            withAnimation(Theme.spring) { drag = .zero }
            disliking = card
            dislikeOpen = true
            return
        }
        if kind == "ja", !reduceMotion, let deck, let day = rail(deck).first(where: { $0.open && $0.card == nil })?.day,
           let to = slotFrames[day], photo != .zero {
            flight = Flight(url: mediaURL(card.imageUrl), rect: photo)
            flying = card.id
            withAnimation(.timingCurve(0.5, 0, 0.2, 1, duration: 0.55)) { flight?.rect = to }
            Task {
                try? await Task.sleep(for: .milliseconds(560))
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { landed.append(card) }
                flight = nil
                send(card, kind)
                flying = nil
            }
            return
        }
        // Woche dieser Art voll (Reserve) oder „Bewegung reduzieren“: ohne Flug
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeIn(duration: 0.22)) {
            if reduceMotion { flying = card.id } else { drag = CGSize(width: kind == "ja" ? -600 : 600, height: drag.height) }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(220))
            if kind == "ja" { landed.append(card) }
            send(card, kind)
            flying = nil
        }
    }

    /// `.e9a-btns`: Diese Woche / Nicht, darunter Zurück · Mag ich nicht … · Würfel.
    private var buttons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button { if let c = pile.first { decide(c, "ja") } } label: {
                    HStack(spacing: 8) { Icon(.arrow, size: 18).scaleEffect(x: -1, y: 1); Text("Diese Woche") }
                        .foregroundStyle(Theme.C.onInk)
                        .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.C.ink, in: Capsule())
                }
                Button { if let c = pile.first { decide(c, "nein") } } label: {
                    HStack(spacing: 8) { Text("Nicht"); Icon(.arrow, size: 18) }
                        .foregroundStyle(Theme.C.ink)
                        .padding(.horizontal, 14).frame(minHeight: 48)
                        .overlay(Capsule().strokeBorder(Theme.C.ink, lineWidth: Theme.S.hair))
                }
            }
            .font(Theme.F.text(14, .extrabold, relativeTo: .subheadline)).lineLimit(1)
            .disabled(pile.isEmpty || flying != nil)
            HStack {
                roundKnob(.back, "Rückgängig") { Task { await undo() } }
                Spacer(minLength: 6)
                Button { if let c = pile.first { decide(c, "mag_nicht") } } label: {
                    Text("Mag ich nicht …").font(Theme.F.text(14, .extrabold, relativeTo: .subheadline)).lineLimit(1)
                        .foregroundStyle(Theme.C.ink)
                        .padding(.horizontal, 18).frame(height: 44)
                        .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
                }
                .disabled(pile.isEmpty)
                Spacer(minLength: 6)
                roundKnob(.dice, "Überrasch mich", dark: true) { planBefore = store.plan?.id; surprise = true }
            }
        }
        .buttonStyle(PressableStyle())
        .disabled(deck == nil)
    }

    /// `.e9-cb`: 44er-Kreis, Haarlinie oder Tinte.
    private func roundKnob(_ icon: Icon8, _ label: String, dark: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: 19)
                .foregroundStyle(dark ? Theme.C.onInk : Theme.C.ink)
                .frame(width: 44, height: 44)
                .background(dark ? Theme.C.ink : Theme.C.bg, in: Circle())
                .overlay { if !dark { Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
        }
        .accessibilityLabel(label)
    }

    // MARK: Server

    /// Stapel holen bzw. anlegen, dann abfragen: schnell, solange Karten entstehen, sonst selten (Matches der anderen).
    private func poll() async {
        if store.demo { pickType(); return }
        await load()
        while !Task.isCancelled {
            let busy = deck?.loading == true || pile.isEmpty
            try? await Task.sleep(for: .seconds(busy ? 2 : 8))
            if voting == 0, case .stack = stage, let d: SwipeDTO = try? await store.api.request("GET", "/swipe", cache: false) {
                apply(d)
            }
        }
    }

    /// Rang und Matches frisch vom Server (vor der Auswahl).
    private func refresh() async {
        if !store.demo, let d: SwipeDTO = try? await store.api.request("GET", "/swipe", cache: false) { deck = d }
    }

    private func load() async {
        do {
            apply(try await store.api.request("POST", "/swipe", timeout: 30))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func apply(_ d: SwipeDTO) {
        let now = Set(d.chosen.filter(\.match).map(\.id))
        if let known = matches, match == nil, let new = d.chosen.first(where: { $0.match && !known.contains($0.id) }) {
            store.flash("♥ Match: \(new.title)")  // andere haben zugestimmt (S42 Banner)
        }
        matches = now
        if deck == nil, d.ready { stage = .selection }  // Stapel schon voll → gleich die Auswahl
        withAnimation(Theme.spring) { deck = d }
        pickType()
        if pile.isEmpty, !d.loading { Task { await more() } }
    }

    /// Aktiver Stapel: die gewählte Art, solange sie Karten hat oder nicht fertig ist, sonst die erste offene.
    private func pickType() {
        guard let deck else { return }
        if deck.types.contains(mealType), !deck.done(mealType) || !pile.isEmpty { return }
        mealType = deck.types.first { !deck.done($0) } ?? deck.types.first ?? ""
    }

    private func more(force: Bool = false) async {
        guard force || !asked.contains(mealType), !mealType.isEmpty, !store.demo else { return }
        asked.insert(mealType)
        if let d: SwipeDTO = try? await store.api.request("POST", "/swipe/more/\(mealType)") { apply(d) }
    }

    private func send(_ card: SwipeCardDTO, _ kind: String, reason: String? = nil, ingredient: String = "", note: String = "") {
        struct Body: Encodable { var vote: String; var days: Int; var reason: String?; var ingredient: String; var note: String }
        struct Result: Decodable { var match: Bool; var have: [String: Int]; var ready: Bool }
        let n = SwipeDTO.repeats.contains(card.mealType) ? days[card.id] ?? defaultDays(card) : 1
        disliking = nil
        drag = .zero
        withAnimation(Theme.spring) { deck?.cards.removeAll { $0.id == card.id } }
        if reason == "zutat" { store.flash("„\(ingredient)“ kommt nicht mehr in deine Pläne") }
        if reason == "schmeckt_nicht" || reason == "sonstiges" { store.flash("Kommt nicht mehr in deine Pläne") }
        if store.demo { return }
        voting += 1
        Task {
            defer { voting -= 1 }
            do {
                let r: Result = try await store.api.request("POST", "/swipe/cards/\(card.id)/vote",
                                                            body: Body(vote: kind, days: n, reason: reason, ingredient: ingredient, note: note))
                let wasReady = deck?.ready == true
                if kind == "ja" { deck?.chosen.append(card) }
                deck?.have = r.have
                deck?.ready = r.ready
                if r.match {
                    matches?.insert(card.id)
                    withAnimation(Theme.spring) { match = card }
                }
                pickType()
                if r.ready && !wasReady {  // gerade alle Stapel voll → Auswahl (S43) mit Rang vom Server
                    await refresh()
                    go(.selection)
                }
            } catch {
                store.flash("Nicht gespeichert: \(error.localizedDescription)")
                withAnimation(Theme.spring) { deck?.cards.insert(card, at: 0) }
            }
        }
    }

    private func undo() async {
        guard !store.demo else { return }
        do {
            let d: SwipeDTO = try await store.api.request("POST", "/swipe/undo")
            withAnimation(Theme.spring) { deck = d }
            if let first = d.cards.first { mealType = first.mealType }  // zurückgeholte Karte liegt oben in ihrer Art
        } catch {
            store.flash("Rückgängig nicht möglich: \(error.localizedDescription)")
        }
    }
}

/// Rezeptkarte Wochen-Tisch (`.e9a-card`): rosa Bogen oben, Herkunft + Markt-Logo, Teller, Titel, Zeit/Angebote, Preis pro Portion.
struct SwipeCardFace: View {
    let card: SwipeCardDTO
    @Binding var days: Int?  // Frühstück/Snack: „An wie vielen Tagen?“
    var maxDays = 7
    var photoFrame: (CGRect) -> Void = { _ in }  // Start des fliegenden Tellers

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SoftPill(text: card.source == "rezept" ? "Dein Rezept" : "KI-Idee", icon: card.source == "rezept" ? .book : .sparkle, tint: Theme.C.bg)
                Spacer()
                if !card.chain.isEmpty {
                    RemoteImage(url: Labels.logoURL(card.chain), dim: false) {
                        Text(Labels.chain(card.chain)).font(Theme.F.text(12, .extrabold, relativeTo: .caption)).foregroundStyle(Theme.C.ink)
                    }
                    .frame(height: 14)
                    .accessibilityLabel(Labels.chain(card.chain))
                }
            }
            PlanPlate(url: mediaURL(card.imageUrl), size: 160)
                .onGeometryChange(for: CGRect.self) { g in g.frame(in: .named(SwipeView.space)) } action: { f in photoFrame(f) }
                .padding(.top, 4 + Theme.S.plateRing)
            Text(card.title).font(Theme.F.serif(22, relativeTo: .title)).multilineTextAlignment(.center)
                .lineLimit(3).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14 + Theme.S.plateRing)
            HStack(spacing: 6) {
                if card.prepMinutes > 0 { Text("\(card.prepMinutes) min") }
                if card.prepMinutes > 0 && card.deals > 0 { Text("·") }
                if card.deals > 0 { Text("\(card.deals) im Angebot").font(Theme.F.text(12, .extrabold, relativeTo: .caption)).foregroundStyle(Theme.C.deal) }
            }
            .font(Theme.F.text(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2).padding(.top, 8)
            if let n = days {
                HStack {
                    Text("An wie vielen Tagen?").font(Theme.F.text(14, .bold, relativeTo: .body))
                    Spacer()
                    step("minus", n - 1, n > 1)
                    Text("\(n)×").font(Theme.F.text(15, .extrabold)).monospacedDigit().frame(minWidth: 30).contentTransition(.numericText())
                    step("plus", n + 1, n < maxDays)
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 10)
            PlanStat(label: "pro\nPortion") { BigNumber(euro(card.costCents), size: 38) }
        }
        .foregroundStyle(Theme.C.ink)
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .topLeading) {
            Ellipse().fill(Theme.C.rose).frame(width: 350, height: 290).offset(x: -40, y: -150)
        }
        .background(Theme.C.bg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.R.swipeCard, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.R.swipeCard, style: .continuous).strokeBorder(Theme.C.ink.opacity(0.04), lineWidth: 1))
        .shadow(color: Theme.C.ink.opacity(0.13), radius: 20, y: 18)
    }

    private func step(_ symbol: String, _ value: Int, _ enabled: Bool) -> some View {
        Button { withAnimation(Theme.spring) { days = value } } label: {
            Icon(symbol == "plus" ? .plus : .minus, size: 16).foregroundStyle(Theme.C.ink)
                .frame(width: Theme.S.stepperKnob, height: Theme.S.stepperKnob).background(Theme.C.card, in: Circle())
                .overlay(Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(symbol == "plus" ? "Mehr Tage" : "Weniger Tage")
    }
}

/// Kopf eines Mitglieds: Anfangsbuchstabe auf Pastell (Stapel-Kopf, Match).
struct Initial: View {
    let name: String
    var index = 0
    var size: CGFloat = 30

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(Theme.F.serif(size * 0.5)).foregroundStyle(Theme.C.ink)
            .frame(width: size, height: size)
            .background(swipeTints[(index + 1) % swipeTints.count], in: Circle())
            .overlay(Circle().strokeBorder(Theme.C.bg, lineWidth: 2.5))
            .accessibilityLabel(name)
    }
}

// MARK: S42 Match

struct MatchView: View {
    let card: SwipeCardDTO
    let members: [String]
    let close: () -> Void
    @State private var pop = false

    var body: some View {
        ZStack {
            Theme.C.bg  // Kreis als Overlay: sprengt das Layout nicht
                .overlay { Circle().fill(Theme.C.blue).frame(width: 560, height: 560).offset(y: -90) }
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Spacer()
                Text(members.count > 2 ? "IHR ALLE WOLLT" : "IHR BEIDE WOLLT").font(Theme.F.lbl).tracking(11 * 0.08)
                Text("Match!").font(Theme.F.serif(52, relativeTo: .largeTitle))
                PlanPlate(url: mediaURL(card.imageUrl), size: 250)
                    .overlay(alignment: .bottom) {
                        HStack {
                            ForEach(Array(members.prefix(2).enumerated()), id: \.offset) { i, n in
                                if i == 1 { Spacer() }
                                Initial(name: n, index: i, size: 54)
                            }
                        }
                        .offset(y: 8)
                    }
                    .scaleEffect(pop ? 1 : 0.6).opacity(pop ? 1 : 0)
                    .padding(.vertical, 10)
                Text(card.title).font(Theme.F.serif(26, relativeTo: .title)).multilineTextAlignment(.center)
                Text("\(euro(card.costCents)) p. P. · \(card.prepMinutes) min · \(card.deals) Zutaten im Angebot")
                    .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                Spacer()
                PrimaryButton(title: "Weiter swipen", action: close)
                Text("Matches kommen zuerst in den Plan").font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
            }
            .foregroundStyle(Theme.C.ink)
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 12)
        }
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) { pop = true } }
        .sensoryFeedback(.success, trigger: pop)
    }
}

// MARK: S43 Auswahl

struct SwipeSelection: View {
    let deck: SwipeDTO
    let persons: Int
    let back: () -> Void
    let distribute: () -> Void
    let manual: () -> Void

    var body: some View {
        let (picked, reserve) = deck.split
        let units = picked.values.joined().map { c in (c, SwipeDTO.repeats.contains(c.mealType) ? c.days : 1) }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CircleButton(icon: .back, label: "Weiter swipen", action: back)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Alle Stapel voll").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                    Text("Eure Woche").font(Theme.F.serif(46, relativeTo: .largeTitle))
                }
                HStack(alignment: .top, spacing: 28) {
                    stat("\(deck.need.values.reduce(0, +))", "GERICHTE")
                    stat("\(deck.chosen.filter(\.match).count)", "MATCHES", Theme.C.deal)
                    stat(euro(units.reduce(0) { $0 + $1.0.costCents * $1.1 } * persons), "GESCHÄTZT")
                }
                ForEach(deck.types, id: \.self) { m in
                    SectionLabel("\(Labels.meal(m)) · \(deck.need[m] ?? 0)", big: true)
                        .padding(.top, 6)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(picked[m] ?? []) { c in
                                VStack(spacing: 6) {
                                    PlanPlate(url: mediaURL(c.imageUrl), size: 64)
                                    Text(c.title).font(Theme.F.text(12, .bold, relativeTo: .caption)).multilineTextAlignment(.center).lineLimit(2)
                                    if c.match {
                                        Text("♥ MATCH").font(Theme.F.lbl).foregroundStyle(Theme.C.deal)
                                    } else if SwipeDTO.repeats.contains(m) {
                                        Text("\(c.days)×").font(Theme.F.lbl).foregroundStyle(Theme.C.deal)
                                    }
                                }
                                .frame(width: 84)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .scrollClipDisabled()  // Teller-Schatten nicht abschneiden
                    .contentMargins(.horizontal, Theme.pagePadding, for: .scrollContent)
                    .padding(.horizontal, -Theme.pagePadding)  // Reihe läuft bis zum Bildschirmrand
                }
                if !reserve.isEmpty {
                    (Text("RESERVE · \(reserve.count)  ").font(Theme.F.lbl).foregroundStyle(Theme.C.ink2)
                        + Text("mehr gemocht als Plätze").font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink3))
                        .tracking(0.5)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
        }
        .clipped()  // nicht unter die Statusleiste scrollen
        .ctaBar(bottom: 8) {
            VStack(spacing: 10) {
                PrimaryButton(title: "Verteilen", icon: .swap, action: distribute)
                OutlineButton(title: "Selbst eintragen", action: manual)
            }
        }
    }

    private func stat(_ value: String, _ label: String, _ color: Color = Theme.C.ink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            BigNumber(value, size: 30).foregroundStyle(color)
            SectionLabel(label)
        }
    }
}

// MARK: S44 Woche verteilen

struct SwipeWeek: View {
    let deck: SwipeDTO
    let manual: Bool
    let persons: Int
    let back: () -> Void
    let finished: () -> Void
    @Environment(AppStore.self) private var store
    @State private var assign: [SwipeSlot: Int] = [:]
    @State private var fixed: Set<SwipeSlot> = []  // selbst gesetzt: bleibt beim Neu-Mischen
    @State private var seed = 0
    @State private var target: SwipeSlot?
    @State private var busy = false

    private var cards: [Int: SwipeCardDTO] { Dictionary(deck.chosen.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    private var slots: [SwipeSlot] { deck.slots.map { SwipeSlot(day: $0.day, mealType: $0.mealType) } }
    private var rows: [SwipeSlot] { slots.filter { !SwipeDTO.repeats.contains($0.mealType) } }  // Frühstück/Snack: Zeile unten

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    CircleButton(icon: .back, label: "Zurück", action: back)
                    Spacer()
                    Button { seed += 1; Task { await distribute() } } label: { HStack(spacing: 6) { Icon(.swap, size: 20); Text("Neu mischen") } }
                        .font(Theme.F.text(15, .bold, relativeTo: .body)).foregroundStyle(Theme.C.ink).frame(minHeight: 44)
                        .disabled(busy || store.generating)
                }
                Text("So sieht's aus").font(Theme.F.serif(40, relativeTo: .largeTitle)).padding(.top, 6)
                Text("Halten und ziehen zum Tauschen").font(Theme.F.small).foregroundStyle(Theme.C.ink2).padding(.bottom, 10)
                ForEach(Array(Set(rows.map(\.day))).sorted(), id: \.self) { d in
                    HStack(alignment: .top, spacing: 10) {
                        Text(Labels.days[d]).font(Theme.F.serif(22, relativeTo: .title2)).frame(width: 44, alignment: .leading).padding(.top, 12)
                        VStack(spacing: 6) {
                            ForEach(rows.filter { $0.day == d }.sorted { order($0) < order($1) }, id: \.self) { s in slot(s) }
                        }
                    }
                    .padding(.vertical, 9)
                    .overlay(alignment: .top) { Hairline() }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
        }
        .clipped()  // nicht unter die Statusleiste scrollen
        .ctaBar(bottom: 8) {
            VStack(spacing: 10) {
                if !spare.isEmpty { spareBar }
                if let e = store.error, !store.generating, !busy {
                    Text(e).font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.deal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Text(summary).font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2).lineLimit(2)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        BigNumber(euro(total), size: 30)
                        SectionLabel("GESCHÄTZT")
                    }
                }
                PlanBusyButton(title: store.error == nil ? "Plan übernehmen" : "Erneut versuchen", busy: store.generating,
                               disabled: assign.count < slots.count, busyTitle: "Plan wird erstellt …", action: finish)
            }
            .background(Theme.C.bg.padding(.horizontal, -Theme.pagePadding))  // Liste scheint nicht durch die Leiste
        }
        .task { await distribute() }
    }

    private func order(_ s: SwipeSlot) -> Int { Labels.slotOrder.firstIndex(of: s.mealType) ?? 9 }

    @ViewBuilder private func slot(_ s: SwipeSlot) -> some View {
        let on = target == s
        Group {
            if on {
                Text("↓ hier ablegen").font(Theme.F.text(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.C.blue1, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.C.blue3, style: StrokeStyle(lineWidth: Theme.S.hair, dash: [5, 4])))
            } else if let c = assign[s].flatMap({ cards[$0] }) {
                HStack(spacing: 10) {
                    PlanPlate(url: mediaURL(c.imageUrl), size: 38, mini: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.title).font(Theme.F.serif(17, relativeTo: .body)).lineLimit(1)
                        HStack(spacing: 6) {
                            SoftPill(text: Labels.meal(s.mealType))
                            if c.match { Text("♥ Match").font(Theme.F.lbl).foregroundStyle(Theme.C.deal) }
                        }
                    }
                    Spacer(minLength: 0)
                    Icon(.dots, size: 20).foregroundStyle(Theme.C.ink3).accessibilityHidden(true)
                }
                .frame(minHeight: 50)
                .contentShape(Rectangle())
                .draggable(s.key) { PlanPlate(url: mediaURL(c.imageUrl), size: 54) }
                .accessibilityElement(children: .combine)
            } else {
                Text("\(Labels.meal(s.mealType)) – hierher ziehen").font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink3)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .overlay(Capsule().strokeBorder(Theme.C.ink3, style: StrokeStyle(lineWidth: Theme.S.hair, dash: [5, 4])))
            }
        }
        .dropDestination(for: String.self) { items, _ in drop(items.first ?? "", on: s) } isTargeted: { t in
            withAnimation(Theme.spring) { target = t ? s : (target == s ? nil : target) }
        }
    }

    /// Ablegen: Slot auf Slot tauscht (gleiche Mahlzeitart), Karte aus der Leiste setzt den Slot.
    private func drop(_ payload: String, on s: SwipeSlot) -> Bool {
        let parts = payload.split(separator: ":")
        if parts.first == "slot", parts.count == 3, let d = Int(parts[1]) {
            let from = SwipeSlot(day: d, mealType: String(parts[2]))
            guard from.mealType == s.mealType, from != s else { return false }
            let moved = assign[from]
            withAnimation(Theme.spring) { assign[from] = assign[s]; assign[s] = moved }
            fixed.formUnion([from, s].filter { assign[$0] != nil })
            return true
        }
        guard parts.first == "card", parts.count == 2, let id = Int(parts[1]), cards[id]?.mealType == s.mealType else { return false }
        withAnimation(Theme.spring) { assign[s] = id }
        fixed.insert(s)
        return true
    }

    /// Gewählte Karten mit freien Einsätzen (Reserve bzw. beim Selbst-Eintragen die ganze Auswahl), ohne Frühstück/Snack.
    private var spare: [SwipeCardDTO] {
        deck.chosen.filter { c in !SwipeDTO.repeats.contains(c.mealType) && !assign.values.contains(c.id) }
    }

    private var spareBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(manual ? "Deine Auswahl" : "Reserve")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(spare) { c in
                        HStack(spacing: 8) {
                            PlanPlate(url: mediaURL(c.imageUrl), size: 34, mini: true)
                            Text(c.title).font(Theme.F.text(12, .bold, relativeTo: .caption)).lineLimit(1)
                                .frame(maxWidth: 190, alignment: .leading)  // lange Namen enden mit „…“
                        }
                        .padding(.leading, 4).padding(.trailing, 12).frame(height: 44)
                        .background(Theme.C.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
                        .draggable("card:\(c.id)") { PlanPlate(url: mediaURL(c.imageUrl), size: 54) }
                        .accessibilityLabel("\(c.title), \(Labels.meal(c.mealType))")
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
            .contentMargins(.horizontal, Theme.pagePadding, for: .scrollContent)
            .padding(.horizontal, -Theme.pagePadding)  // Leiste über volle Breite
        }
    }

    /// „Frühstück: Müsli Mo–Fr, Rührei Sa+So“
    private var summary: String {
        deck.types.filter { SwipeDTO.repeats.contains($0) }.map { m in
            var byCard: [(Int, [Int])] = []
            for s in slots.filter({ $0.mealType == m }).sorted(by: { $0.day < $1.day }) {
                guard let id = assign[s] else { continue }
                if let i = byCard.firstIndex(where: { $0.0 == id }) { byCard[i].1.append(s.day) } else { byCard.append((id, [s.day])) }
            }
            let parts = byCard.map { id, ds in
                let name = cards[id]?.title ?? ""
                let span = ds.count > 2 && ds.last! - ds.first! == ds.count - 1 ? "\(Labels.days[ds.first!])–\(Labels.days[ds.last!])"
                    : ds.map { Labels.days[$0] }.joined(separator: "+")
                return "\(name) \(span)"
            }
            return "\(Labels.meal(m)): \(parts.joined(separator: ", "))"
        }.joined(separator: " · ")
    }

    private var total: Int { assign.values.reduce(0) { $0 + (cards[$1]?.costCents ?? 0) } * persons }

    private var assignment: [SlotCardDTO] { assign.map { s, id in SlotCardDTO(day: s.day, mealType: s.mealType, cardId: id) } }

    /// „Verteilen“ / „Neu mischen“ im Code (ohne KI); selbst gesetzte Plätze bleiben. Selbst eintragen: nur Frühstück/Snack vorbelegt.
    private func distribute() async {
        struct Body: Encodable { var fixed: [SlotCardDTO]; var seed: Int }
        struct Result: Decodable { var assignment: [SlotCardDTO]; var reserve: [Int] }
        let keep = assign.filter { fixed.contains($0.key) }.map { s, id in SlotCardDTO(day: s.day, mealType: s.mealType, cardId: id) }
        busy = true
        defer { busy = false }
        var out: [SwipeSlot: Int]
        if store.demo {
            out = Demo.swipeAssign(deck)
        } else {
            do {
                let r: Result = try await store.api.request("POST", "/swipe/distribute", body: Body(fixed: keep, seed: seed))
                out = Dictionary(r.assignment.map { (SwipeSlot(day: $0.day, mealType: $0.mealType), $0.cardId) }, uniquingKeysWith: { a, _ in a })
            } catch {
                store.flash("Verteilen nicht möglich: \(error.localizedDescription)")
                return
            }
        }
        if manual && fixed.isEmpty { out = out.filter { SwipeDTO.repeats.contains($0.key.mealType) } }
        withAnimation(Theme.spring) { assign = out }
    }

    private func finish() {
        struct Body: Encodable { var assignment: [SlotCardDTO] }
        guard !store.demo else { return }
        store.error = nil
        let body = Body(assignment: assignment)
        Task {
            await store.runPlanJob { try await store.api.request("POST", "/swipe/finish", body: body) }
            if store.error == nil {
                store.flash("Dein Wochenplan ist fertig")
                finished()
            }
        }
    }
}

/// Bogen-Farbe je Mahlzeitart (Mockup: Abend blau, Mittag grün; übrige abgeleitet).
private func mealTint(_ m: String) -> Color {
    switch m {
    case "mittag", "lunchbox": Theme.C.sage
    case "fruehstueck": Theme.C.sand
    case "snack", "dessert": Theme.C.rose
    default: Theme.C.blue1
    }
}

/// Pastell-Kreise der Swipe-Karten und Köpfe (v8-Töne).
private let swipeTints = [Theme.C.blue1, Theme.C.sand, Theme.C.rose, Theme.C.sage]

/// Leer/Fehler im Swipe (v8): Illustration, t2, Text, optional Knopf.
private struct SwipeNote: View {
    let ill: String
    let title: String
    let text: String
    var button: String?
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            Ill(ill).frame(width: 150)
            Text(title).font(Theme.F.t2).multilineTextAlignment(.center)
            Text(text).font(Theme.F.small).foregroundStyle(Theme.C.ink2).multilineTextAlignment(.center)
            if let button { PrimaryButton(title: button, action: action).padding(.top, 8) }
        }
        .frame(maxWidth: .infinity)
    }
}
