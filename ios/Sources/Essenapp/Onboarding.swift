import SwiftUI

/// S6 Onboarding (e.html): Willkommen → Ort & Läden → Haushalt & Ernährung → Budget & Ziel.
/// Fortschritt als vier Striche oben, Weiter immer unten. Umkreis und Karte gibt es danach unter Einstellungen › Ort & Läden.
struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var step = 0
    @State private var plz = ""
    @State private var plzSaved = ""
    @State private var nearby: [NearbyStore] = []
    @State private var picked: [String: String] = [:]  // chain → osmId der gewählten Filiale; fehlt = aus
    @State private var persons = 2
    @State private var diet = "alles"
    @State private var allergies: Set<String> = []
    @State private var newAllergy = ""
    @State private var dislikes = ""
    @State private var budgetEuro = 60.0
    @State private var goal = "ausgewogen"
    @State private var mealTypes: Set<String> = ["mittag", "abend"]
    @State private var cuisines: Set<String> = []
    @State private var sheet: Sheet?
    @State private var showServer = false
    @State private var busy = false
    @State private var searching = false
    @State private var error: String?

    private enum Sheet: String, Identifiable { case allergies, dislikes, cuisines; var id: String { rawValue } }

    // Mockup-Maße (e.html S6): Inhalt ab Safe Area (Mockup-y − 52), Knöpfe ab Unterkante
    private let contentTop: CGFloat = 14
    private let barBottom: CGFloat = 40
    private let welcomeBottom: CGFloat = 50
    private let welcomeSide: CGFloat = 28
    private let progressWidth: CGFloat = 140
    private let plzWidth: CGFloat = 220

    var body: some View {
        ZStack {
            backdrop.ignoresSafeArea()
            if step == 0 { welcome.transition(.opacity) } else { form.transition(.move(edge: .trailing).combined(with: .opacity)) }
        }
        .background(Theme.C.bg)
        .animation(Theme.spring, value: step)
        .sheet(item: $sheet) { s in sheetContent(s).sheet8().presentationDetents([.medium, .large]) }
    }

    // MARK: Hintergrund je Schritt (Rand-Form + Zeichnung, Mockup-Koordinaten ab Bildschirm-Oberkante)

    @ViewBuilder private var backdrop: some View {
        switch step {
        case 0:
            Color.clear.pinned(left: 40, top: 80) { Ill("shopper").frame(width: 320) }
                .edgeForm(.circle, Theme.C.blue, width: 580, height: 580, left: -150, top: -150)
        case 1:
            Color.clear.pinned(right: 14, top: 64) { Ill("binoculars").frame(width: 130) }
                .edgeForm(.circle, Theme.C.blue1, width: 330, height: 330, right: -120, top: -110)
        case 2:
            Color.clear.pinned(right: 4, top: 78) { Ill("table").frame(width: 150) }
                .edgeForm(.circle, Theme.C.sage, width: 320, height: 320, right: -130, top: -120)
        default:
            Color.clear.pinned(right: 10, top: 50) { Ill("bag").frame(width: 120) }
                .edgeForm(.quarter, Theme.C.blue, width: 190, height: 200, right: 0, top: 0)
        }
    }

    // MARK: S6.1 Willkommen

    private var welcome: some View {
        @Bindable var api = store.api
        let needsServer = showServer || API.defaultServer.isEmpty && api.baseURL.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Text("Wenn du magst").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
            Text("Kochen nach Angebot – jede Woche günstig.").font(Theme.F.t1).padding(.top, 8)
                .onLongPressGesture { showServer = true }  // Entwicklung: eigenen Server eintragen
                .padding(.bottom, needsServer ? 16 : 68)
            if needsServer {
                FieldBox(icon: .gear) {
                    TextField("Server, z. B. http://192.168.178.20:8000", text: $api.baseURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .padding(.bottom, 16)
            }
            HStack {
                Dots8(count: 4, current: 0)
                Spacer()
                Button { step = 1 } label: {
                    HStack(spacing: 14) {
                        Text("Los geht's").font(Theme.F.text(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.C.ink)
                        Icon(.fork, size: 28).foregroundStyle(Theme.C.onInk)
                            .frame(width: 72, height: 72).background(Theme.C.ink, in: Circle())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .disabled(api.baseURL.isEmpty)
                .opacity(api.baseURL.isEmpty ? 0.35 : 1)
            }
        }
        .padding(.horizontal, welcomeSide)
        .padding(.bottom, welcomeBottom)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    // MARK: Schritte 2–4

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                StepBars(count: 4, current: step).frame(width: progressWidth)
                switch step {
                case 1: placeStep
                case 2: householdStep
                default: budgetStep
                }
                if let error { Text(error).font(Theme.F.text(13, relativeTo: .footnote)).foregroundStyle(Theme.C.deal).padding(.top, 14) }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, contentTop)
            .padding(.bottom, 130)
        }
        .scrollDismissesKeyboard(.immediately)
        .overlay(alignment: .bottom) { bottomBar }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            CircleButton(icon: .back, size: Theme.S.button, label: "Zurück") { error = nil; step -= 1 }
            Button(action: next) {
                HStack(spacing: 8) {
                    if busy {
                        Hop3()
                    } else {
                        if step == 3 { Icon(.sparkle, size: 20) }
                        Text(step == 3 ? "Ersten Plan erstellen" : "Weiter")
                        if step < 3 { Icon(.arrow, size: 20) }
                    }
                }
                .font(Theme.F.button).foregroundStyle(Theme.C.onInk)
                .frame(maxWidth: .infinity, minHeight: Theme.S.button)
                .background(Theme.C.ink, in: Capsule())
                .opacity(canContinue ? 1 : 0.35)
                .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .disabled(!canContinue || busy)
            .accessibilityLabel(busy ? "Einen Moment" : step == 3 ? "Ersten Plan erstellen" : "Weiter")
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, barBottom)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var canContinue: Bool {
        step != 1 || (plzSaved == plz && !picked.isEmpty && !searching)
    }

    private func next() {
        error = nil
        switch step {
        case 1:
            let stores = picked.values.compactMap { id in nearby.first { $0.id == id } }.map {
                StoreDTO(chain: $0.chain, storeName: $0.name, osmId: $0.osmId, lat: $0.lat, lng: $0.lng, address: $0.address)
            }
            busy = true
            Task {
                defer { busy = false }
                do {
                    if !store.demo { try await store.save(HouseholdPatch(radiusKm: store.household?.radiusKm ?? 5, stores: stores)) }
                    step = 2
                    Task { await store.refreshOffers() }  // 19.7: Angebote laden, während weiter gefragt wird
                } catch {
                    self.error = error.localizedDescription
                }
            }
        case 3:
            busy = true
            Task {
                defer { busy = false }
                do {
                    let excluded = dislikes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    try await store.save(HouseholdPatch(persons: persons, diet: diet, allergies: Array(allergies), excludedIngredients: excluded,
                                                        cuisines: Array(cuisines), mealTypes: Labels.mealTypes.map(\.0).filter(mealTypes.contains),
                                                        budgetFoodWeekCents: Int(budgetEuro) * 100, nutritionGoal: goal))
                    store.onboarded = true
                    Task {
                        store.generating = true  // Start zeigt den Lader, bis Angebote + Plan da sind
                        if store.offers.isEmpty { await store.refreshOffers() }
                        await store.generatePlan()
                    }
                } catch {
                    self.error = error.localizedDescription
                }
            }
        default:
            step += 1
        }
    }

    // MARK: S6.2 Ort & Läden

    private var chains: [(chain: String, stores: [NearbyStore])] {
        Dictionary(grouping: nearby, by: \.chain)
            .map { (chain: $0.key, stores: $0.value.sorted { $0.distanceKm < $1.distanceKm }) }
            .sorted { $0.stores[0].distanceKm < $1.stores[0].distanceKm }
    }

    private var placeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Wo kaufst\ndu ein?").font(Theme.F.t1).padding(.top, 24)
            VStack(spacing: 6) {
                Hairline(color: Theme.C.ink)
                HStack(alignment: .top) {
                    Text("PLZ").font(Theme.F.text(12, .bold, relativeTo: .caption))
                    Spacer(minLength: 8)
                    TextField("12345", text: $plz)
                        .font(Theme.F.num(56)).tracking(Theme.F.numTracking(56))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad).textContentType(.postalCode)
                        .onChange(of: plz) { _, new in
                            let digits = String(new.filter(\.isNumber).prefix(5))
                            if digits != new { plz = digits }
                        }
                        .accessibilityLabel("Postleitzahl")
                }
            }
            .frame(width: plzWidth)
            .padding(.top, 28)
            Group {
                if searching {
                    Text("Läden werden gesucht …")
                } else if plzSaved == plz, !nearby.isEmpty {
                    Text("\(plz) · \(chains.count) Läden in der Nähe")
                } else {
                    Text("Wir suchen die Läden in deiner Nähe und laden ihre Prospekte.")
                }
            }
            .font(Theme.F.text(13, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2).padding(.top, 6)
            if searching {
                VStack(spacing: 10) { ForEach(0..<4, id: \.self) { _ in Skeleton8(height: 48) } }.padding(.top, 28)
            } else if plzSaved == plz, plz.count == 5, nearby.isEmpty {
                Text("Keine Läden gefunden – den Umkreis stellst du später unter Einstellungen › Ort & Läden ein.")
                    .font(Theme.F.small).foregroundStyle(Theme.C.ink2).padding(.top, 28)
            } else {
                VStack(spacing: 0) {
                    ForEach(chains, id: \.chain) { c in chainRow(c.chain, c.stores) }
                }
                .padding(.top, 28)
            }
        }
        .task(id: plz) {
            guard plz.count == 5, plz != plzSaved else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await lookup()
        }
    }

    private func chainRow(_ chain: String, _ stores: [NearbyStore]) -> some View {
        let on = Binding(get: { picked[chain] != nil }, set: { v in withAnimation(Theme.spring) { picked[chain] = v ? stores[0].id : nil } })
        let current = stores.first { $0.id == picked[chain] } ?? stores[0]
        return VStack(spacing: 0) {
            IRow(name: Labels.chain(chain), tint: Theme.C.plate) {
                RemoteImage(url: Labels.logoURL(chain), dim: false) {
                    Text(String(Labels.chain(chain).prefix(1))).font(Theme.F.text(17, .extrabold))
                }
                .frame(width: 34, height: 34)
            } trail: {
                ESwitch(isOn: on, label: Labels.chain(chain))
            }
            if on.wrappedValue, stores.count > 1 {
                Menu {
                    Picker("Filiale", selection: Binding(get: { current.id }, set: { picked[chain] = $0 })) {
                        ForEach(stores) { s in Text("\(s.address.isEmpty ? s.name : s.address) · \(distance(s.distanceKm))").tag(s.id) }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Filiale wählen").font(Theme.F.text(14, .bold, relativeTo: .subheadline))
                            Text("\(current.address.isEmpty ? current.name : current.address) · \(distance(current.distanceKm))")
                                .font(Theme.F.text(12, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                        }
                        Spacer()
                        Icon(.chev, size: 18).foregroundStyle(Theme.C.ink3)
                    }
                    .foregroundStyle(Theme.C.ink)
                    .frame(height: 44)
                    .padding(.leading, 62)
                    .contentShape(Rectangle())
                }
                .padding(.top, -6)
            }
        }
    }

    private func distance(_ km: Double) -> String { km < 1 ? "\(Int((km * 1000 / 50).rounded() * 50)) m" : "\(num(km, 1...1)) km" }

    private func lookup() async {
        searching = true
        error = nil
        defer { searching = false }
        do {
            if store.demo {
                nearby = Demo.nearby
            } else {
                if store.api.token == nil { try await store.createHousehold(name: "Zuhause", memberName: "Ich") }
                try await store.save(HouseholdPatch(plz: plz))
                nearby = try await store.nearbyStores(radiusKm: store.household?.radiusKm ?? 5)
            }
            plzSaved = plz
            picked = Dictionary(uniqueKeysWithValues: chains.map { ($0.chain, $0.stores[0].id) })  // nächste Filiale je Laden
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: S6.3 Haushalt & Ernährung

    private var householdStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Wer isst\nmit?").font(Theme.F.t1).padding(.top, 24)
            VStack(spacing: 6) {
                Hairline(color: Theme.C.ink)
                HStack {
                    Text("Personen").font(Theme.F.text(12, .bold, relativeTo: .caption))
                    Spacer()
                    HStack(spacing: 14) {
                        CircleButton(icon: .minus, label: "Eine Person weniger") { persons = max(1, persons - 1) }
                        BigNumber("\(persons)", size: 64)
                        CircleButton(icon: .plus, filled: true, label: "Eine Person mehr") { persons = min(20, persons + 1) }
                    }
                }
            }
            .padding(.top, 34)
            .animation(Theme.spring, value: persons)
            .sensoryFeedback(.selection, trigger: persons)
            label("Ernährung")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Labels.diets, id: \.0) { d in smallChip(d.1, on: diet == d.0) { diet = d.0 } }
                }
                .padding(.trailing, Theme.pagePadding)
            }
            .padding(.trailing, -Theme.pagePadding)
            VStack(spacing: 0) {
                Button { sheet = .allergies } label: {
                    ERow("Allergien", value: allergies.isEmpty ? "keine" : allergies.sorted().joined(separator: ", "), lead: .extra(.alert), tint: Theme.C.rose)
                }
                Button { sheet = .dislikes } label: {
                    ERow("Mag ich nicht", value: dislikes.isEmpty ? "nichts" : dislikes, lead: .extra(.nope), tint: Theme.C.sand)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 28)
        }
    }

    // MARK: S6.4 Budget & Ziel

    private var budgetStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Was darf's\nkosten?").font(Theme.F.t1).padding(.top, 24)
            VStack(spacing: 6) {
                Hairline(color: Theme.C.ink)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Budget").font(Theme.F.text(12, .bold, relativeTo: .caption))
                        Text("pro Woche").font(Theme.F.text(12, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                    }
                    Spacer()
                    BigNumber("\(Int(budgetEuro)) €", size: 84)
                }
            }
            .padding(.top, 30)
            ERange(value: $budgetEuro, range: 20...200, step: 5, label: "Budget pro Woche").padding(.top, 14)
            HStack {
                Text("20 €")
                Spacer()
                Text("200 €")
            }
            .font(Theme.F.text(12, relativeTo: .caption)).foregroundStyle(Theme.C.ink2).padding(.top, 4)
            if Int(budgetEuro) < persons * 20 {  // 19.7 (R8): ehrliche Spanne statt Sperre
                Text("Sehr knapp für \(persons) \(persons == 1 ? "Person" : "Personen"): meist reichen \(persons * 25)–\(persons * 40) €.")
                    .font(Theme.F.text(12, relativeTo: .caption)).foregroundStyle(Theme.C.deal).padding(.top, 6)
            }
            label("Ziel")
            ForEach(ProfileView.goals, id: \.0) { g in
                Button { withAnimation(Theme.spring) { goal = g.0 } } label: {
                    ERow(g.1, serif: true, chevron: false) { CheckCircle(on: goal == g.0) }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(goal == g.0 ? .isSelected : [])
            }
            .sensoryFeedback(.selection, trigger: goal)
            FlowLayout(spacing: 8) {
                ForEach(Labels.mealTypes, id: \.0) { m in
                    smallChip(m.1, on: mealTypes.contains(m.0)) { mealTypes.formSymmetricDifference([m.0]) }
                }
            }
            .padding(.top, 28)
            Button { sheet = .cuisines } label: {
                ERow("Küchen", value: cuisines.isEmpty ? "alle" : cuisines.sorted().joined(separator: ", "))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
    }

    // MARK: Teile

    private func label(_ text: String) -> some View {
        SectionLabel(text).padding(.top, 28).padding(.bottom, 4)
    }

    /// Kleiner Chip (`.e-sm .chip`): 32 hoch, 13 pt.
    private func smallChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button { withAnimation(Theme.spring) { action() } } label: {
            Text(title).font(Theme.F.text(13, .bold, relativeTo: .footnote)).lineLimit(1)
                .foregroundStyle(on ? Theme.C.onInk : Theme.C.ink2)
                .padding(.horizontal, 12).frame(height: 32)
                .background(on ? Theme.C.ink : .clear, in: Capsule())
                .overlay { if !on { Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
                .frame(minHeight: 44).contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private func sheetContent(_ s: Sheet) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(s == .allergies ? "Allergien" : s == .dislikes ? "Mag ich nicht" : "Küchen").font(Theme.F.t2)
                Spacer()
                CloseButton { sheet = nil }
            }
            switch s {
            case .allergies:
                let custom = allergies.subtracting(Labels.allergies).sorted()
                ChipFlow(items: (Labels.allergies + custom).map { ($0, $0) }, selected: allergies) { allergies.formSymmetricDifference([$0]) }
                FieldBox(icon: .plus) {
                    TextField("Andere Allergie, z. B. Senf", text: $newAllergy)
                        .submitLabel(.done)
                        .onSubmit {
                            let a = newAllergy.trimmingCharacters(in: .whitespaces)
                            if !a.isEmpty { allergies.insert(a) }
                            newAllergy = ""
                        }
                }
            case .dislikes:
                FieldBox { TextField("z. B. Koriander, Rosenkohl", text: $dislikes) }
                Text("Mit Komma trennen. Ziele und mehr stellst du später unter Präferenzen ein.")
                    .font(Theme.F.text(13, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
            case .cuisines:
                Text("Leer = alle Küchen gemischt.").font(Theme.F.text(13, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                ChipFlow(items: Labels.cuisines.map { ($0, $0) }, selected: cuisines) { cuisines.formSymmetricDifference([$0]) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.pagePadding)
    }
}

/// Umbrechende Chips (`.chip`) mit Mehrfach- oder Einfachauswahl.
struct ChipFlow: View {
    let items: [(String, String)]
    let selected: Set<String>
    var color: Color = Theme.C.ink  // v8: aktive Chips immer Tinte; bleibt für bestehende Aufrufer
    let toggle: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.0) { item in
                Chip8(title: item.1, on: selected.contains(item.0)) {
                    withAnimation(Theme.spring) { toggle(item.0) }
                }
            }
        }
    }
}
