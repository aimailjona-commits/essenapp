import SwiftUI

extension AppStore {
    /// Einträge der gemeinsamen Haushaltsliste (Backend, E40).
    var listItems: [ListItemDTO] { householdList?.items ?? [] }

    func offer(for item: ListItemDTO) -> OfferDTO? { item.offerId.flatMap { id in offers.first { $0.id == id } } }

    /// Plan + Einkaufsliste als Text zum Teilen (WhatsApp, Nachrichten …).
    var shareText: String {
        var lines = ["🥘 Wochenplan" + (plan.map { " KW \($0.week.suffix(2))" } ?? "")]
        for meal in plan?.entries ?? [] {
            lines.append("• \(Labels.days[meal.day]) \(Labels.meal(meal.mealType)): \(meal.recipe.title)")
        }
        lines.append("\n🛒 Einkaufsliste")
        for (chain, items) in Dictionary(grouping: listItems.filter { !$0.checked }, by: \.chain).sorted(by: { $0.key < $1.key }) {
            lines.append("\n\(chain.isEmpty ? "Überall" : Labels.chain(chain)):")
            lines += items.map { i in "◻︎ \(i.name)" + (i.amount.map { " – \(num($0, 0...2)) \(i.unit == "stk" ? "Stück" : i.unit)" } ?? "") }
        }
        if let plan { lines.append("\nGeschätzt \(euro(plan.totalCents)), davon \(euro(plan.savedCents)) gespart 💚") }
        return lines.joined(separator: "\n")
    }
}

extension View {
    /// Größere Tap-Fläche (44 pt) ohne Einfluss aufs Layout.
    func tapArea(_ p: CGFloat = 10) -> some View { padding(p).contentShape(Rectangle()).padding(-p) }
}

/// Liste | Vorrat | Coupons (`.seg`, 236 breit) oben auf allen drei Seiten des Einkauf-Tabs.
struct ShopTabs: View {
    @Binding var page: Int

    var body: some View {
        Segmented8(options: [(0, "Liste"), (1, "Vorrat"), (2, "Coupons")], selection: $page).frame(width: 236)
    }
}

/// Händler-Logo im Pastell-Kreis (`.d-row .c`): Kreis in der Laden-Farbe, echtes Logo auf weißem Plättchen (E44).
struct StoreCircle: View {
    let chain: String
    var size: CGFloat = Theme.S.rowCircle

    var body: some View {
        StoreLogo(chain: chain, size: size * 0.75)
            .frame(width: size, height: size)
            .background(Theme.storeColor(chain), in: Circle())
            .accessibilityLabel(chain.isEmpty ? "Überall" : Labels.chain(chain))
    }
}

/// S5 Einkauf: je Laden eine Zeile, Laden-Empfehlung, einmalige Listen. Segment „Vorrat“ → S16, „Coupons“ → S31.
struct ShoppingView: View {
    @Environment(AppStore.self) private var store
    @State private var page = Demo.screen == "pantry" ? 1 : ["wallet", "bonus"].contains(Demo.screen ?? "") ? 2 : 0
    @State private var openChain: String? = ["voiceadd", "offline"].contains(Demo.screen ?? "") ? "rewe" : nil  // Demo: S5b

    var body: some View {
        Group {
            switch page {
            case 1: PantryView(page: $page)
            case 2: CouponWalletView(page: $page)
            default: ShoppingOverview(page: $page)
            }
        }
        .navigationDestination(item: $openChain) { chain in ShoppingListView(chain: chain) }
    }
}

/// S5 Übersicht (redesign-v8 d.html „S5 Einkauf Übersicht“).
private struct ShoppingOverview: View {
    @Environment(AppStore.self) private var store
    @Binding var page: Int
    @State private var newItem = ""
    @State private var newListName = ""
    @State private var askNewList = false
    @State private var voiceOpen = false
    @State private var showLater = false
    @State private var lastWeekSaved: Int?

    // Mockup-Lage (S5): Kreis 200 und Tasche oben rechts
    private enum M {
        static let blob: CGFloat = 200, blobRight: CGFloat = -80, blobTop: CGFloat = 96
        static let bag: CGFloat = 100, bagRight: CGFloat = 12, bagTop: CGFloat = 116
    }

    var body: some View {
        let items = store.listItems.filter { i in i.nextWeek != true }
        let later = store.listItems.filter { i in i.nextWeek == true }  // Gruppe „Nächste Woche“ (30)
        let groups = Dictionary(grouping: items, by: \.chain).sorted { ($0.key.isEmpty ? "~" : $0.key) < ($1.key.isEmpty ? "~" : $1.key) }
        let oneoffs = store.lists.filter { $0.kind == "oneoff" }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ShopTabs(page: $page)
                Text("KW \(week) · \(items.filter { !$0.checked }.count) offen").font(Theme.F.small).foregroundStyle(Theme.C.ink2).padding(.top, 16)
                Text("Einkauf").font(Theme.F.t1).accessibilityAddTraits(.isHeader)
                VStack(spacing: 10) {
                    NavigationLink { SavingsView() } label: {  // S11 Ersparnis
                        StatNumber(label: "Diese Woche\ngespart", value: euro(store.plan?.savedCents ?? 0), size: 40)
                    }
                    .buttonStyle(PressableStyle())
                    if let lastWeekSaved { StatNumber(label: "Letzte Woche", value: euro(lastWeekSaved), size: 26, mute: true) }
                }
                .frame(width: 218)
                .padding(.top, 16)

                if groups.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Liste ist leer").font(Theme.F.t2)
                        Text("Sobald ein Wochenplan da ist, steht hier alles, was du kaufen musst.").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                    }
                    .padding(.top, 30)
                }
                VStack(spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.key) { i, group in
                        NavigationLink { ShoppingListView(chain: group.key) } label: { storeRow(group.key, group.value) }
                            .buttonStyle(PressableStyle())
                            .appear(delay: Double(i) * 0.05)
                    }
                }
                .padding(.top, 30)

                if let id = store.householdList?.id { StoreAdviceRows(listId: id).padding(.top, 28) }  // Laden-Empfehlung (42)

                // Nicht im Mockup, Funktion bleibt: Nächste Woche, einmalige Listen, Artikel ohne Laden
                VStack(spacing: 0) {
                    if !later.isEmpty { NextWeekRow(count: later.count) { showLater = true } }
                    ForEach(oneoffs) { l in
                        NavigationLink { OneOffListView(summary: l) } label: { oneoffRow(l) }
                            .buttonStyle(PressableStyle())
                            .contextMenu {
                                Button("Liste löschen", systemImage: "trash", role: .destructive) { Task { await store.deleteList(l.id) } }
                            }
                    }
                    Button { askNewList = true } label: {
                        HStack(spacing: 14) {
                            Icon(.plus)
                            Text("Neue Liste, z. B. Grillparty").font(Theme.F.text(16))
                            Spacer()
                        }
                        .foregroundStyle(Theme.C.ink3)
                        .frame(minHeight: Theme.S.row)
                        .overlay(alignment: .top) { Hairline() }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    AddItemField(text: $newItem, add: add) { withAnimation(Theme.spring) { voiceOpen = true } }
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, Theme.S.nav)
        }
        .backdrop8 {
            Color.clear
                .pinned(right: M.bagRight, top: M.bagTop) { Ill("bag").frame(width: M.bag) }
                .edgeForm(.circle, Theme.C.blue, width: M.blob, height: M.blob, right: M.blobRight, top: M.blobTop)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await store.loadLists() }
        .task {
            while !Task.isCancelled {  // gemeinsames Einkaufen: Änderungen der anderen alle 10 s holen
                await store.loadLists()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .task { lastWeekSaved = await savedLastWeek() }
        .overlay {
            if voiceOpen {
                VoiceAddOverlay { spoken in
                    withAnimation(Theme.spring) { voiceOpen = false }
                    if let id = store.householdList?.id { Task { await store.addSpoken(spoken, to: id) } }
                } close: { withAnimation(Theme.spring) { voiceOpen = false } }
            }
        }
        .sheet(isPresented: $showLater) { NextWeekSheet(chain: nil) }
        .alert("Neue Liste", isPresented: $askNewList) {
            TextField("z. B. Grillparty", text: $newListName)
            Button("Anlegen") {
                let name = newListName.trimmingCharacters(in: .whitespaces)
                newListName = ""
                if !name.isEmpty { Task { await store.createList(name) } }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private var week: String {
        store.plan.map { String($0.week.suffix(2)) } ?? String(Calendar(identifier: .iso8601).component(.weekOfYear, from: .now))
    }

    /// `.d-row` je Laden: Logo im Pastell-Kreis, Name, Avatare, „3 offen“.
    private func storeRow(_ chain: String, _ items: [ListItemDTO]) -> some View {
        let names = items.map(\.addedBy).filter { n in !n.isEmpty }.reduce(into: [String]()) { r, n in if !r.contains(n) { r.append(n) } }
        return HStack(spacing: 14) {
            StoreCircle(chain: chain)
            VStack(alignment: .leading, spacing: 3) {
                Text(chain.isEmpty ? "Überall" : Labels.chain(chain)).font(Theme.F.serif(20, relativeTo: .title3))
                if !names.isEmpty {
                    HStack(spacing: -6) { ForEach(names.prefix(4), id: \.self) { n in Avatar8(name: n) } }
                        .padding(.leading, 6)
                        .accessibilityElement().accessibilityLabel("Von \(names.joined(separator: ", "))")
                }
            }
            Spacer(minLength: 8)
            Text("\(items.filter { !$0.checked }.count) offen").font(Theme.F.text(16, .extrabold))
        }
        .foregroundStyle(Theme.C.ink)
        .padding(.vertical, 7)
        .overlay(alignment: .top) { Hairline() }
        .contentShape(Rectangle())
    }

    private func oneoffRow(_ l: ListSummaryDTO) -> some View {
        HStack(spacing: 14) {
            Icon(.users).frame(width: Theme.S.rowCircle, height: Theme.S.rowCircle).background(Theme.C.sand, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(l.name).font(Theme.F.rowName).lineLimit(1)
                Text("\(l.openCount) offen · \(l.totalCount) gesamt").font(Theme.F.text(12)).foregroundStyle(Theme.C.ink2)
            }
            Spacer()
            Icon(.chev, size: 18).foregroundStyle(Theme.C.ink3)
        }
        .foregroundStyle(Theme.C.ink)
        .padding(.vertical, 7)
        .overlay(alignment: .top) { Hairline() }
        .contentShape(Rectangle())
    }

    private func add() {
        let name = newItem.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let id = store.householdList?.id else { return }
        newItem = ""
        store.flash("„\(name)“ hinzugefügt")
        Task { await store.addItem(name: name, to: id) }
    }

    /// „Letzte Woche gespart“: Ersparnis der in der Vorwoche abgehakten Artikel (Ausgaben 34).
    private func savedLastWeek() async -> Int? {
        let cal = Calendar(identifier: .iso8601)
        guard let start = cal.dateInterval(of: .weekOfYear, for: .now)?.start,
              let from = cal.date(byAdding: .day, value: -7, to: start) else { return nil }
        let day = PantryDTO.day
        let months = Set([from, start.addingTimeInterval(-1)].map { d in String(d.formatted(day).prefix(7)) })
        var sum = 0, found = false
        for m in months {
            guard let s = try? await store.spending(m) else { continue }
            found = true
            sum += s.items.filter { p in
                guard let d = try? Date(String(p.boughtAt.prefix(10)), strategy: day) else { return false }
                return d >= from && d < start
            }.map(\.savedCents).reduce(0, +)
        }
        return found ? sum : nil
    }
}

/// Kleiner Personen-Kreis mit Anfangsbuchstabe (`.d-av`).
struct Avatar8: View {
    let name: String

    var body: some View {
        let colors = [Theme.C.blue, Theme.C.sage, Theme.C.rose, Theme.C.sand]
        Text(String(name.prefix(1)).uppercased())
            .font(Theme.F.text(11, .extrabold, relativeTo: .caption2))
            .foregroundStyle(Theme.C.ink)
            .frame(width: 24, height: 24)
            .background(colors[abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % colors.count], in: Circle())
            .background(Circle().fill(Theme.C.bg).padding(-2))
    }
}

/// Zusammenfassungs-Zeile „Nächste Woche · 1 Artikel ›“.
private struct NextWeekRow: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Icon(.cal)
                Text("Nächste Woche").font(Theme.F.text(16, .bold))
                Spacer()
                Text(count == 1 ? "1 Artikel" : "\(count) Artikel").font(Theme.F.text(13)).foregroundStyle(Theme.C.ink2)
                Icon(.chev, size: 18)
            }
            .foregroundStyle(Theme.C.ink2)
            .frame(minHeight: Theme.S.row)
            .overlay(alignment: .top) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Sheet: Artikel der Gruppe „Nächste Woche“ – zurückholen oder entfernen.
private struct NextWeekSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let chain: String?
    @State private var height: CGFloat = 300

    var body: some View {
        let items = store.listItems.filter { i in i.nextWeek == true && (chain == nil || i.chain == chain) }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Nächste Woche").font(Theme.F.t2)
                    Spacer()
                    CloseButton { dismiss() }
                }
                .padding(.bottom, 16)
                ForEach(items) { item in
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.name).font(Theme.F.text(16, .bold))
                            if !item.amountText.isEmpty { Text(item.amountText).font(Theme.F.text(12)).foregroundStyle(Theme.C.ink2) }
                        }
                        Spacer()
                        Chip8(title: "Diese Woche") { Task { await store.undoNextWeek(item) } }
                    }
                    .frame(minHeight: Theme.S.row)
                    .overlay(alignment: .top) { Hairline() }
                    .contextMenu {
                        Button("Entfernen", systemImage: "trash", role: .destructive) { Task { await store.deleteItem(item) } }
                    }
                    .accessibilityAction(named: "Entfernen") { Task { await store.deleteItem(item) } }
                }
                if items.isEmpty { Text("Nichts mehr für nächste Woche.").font(Theme.F.small).foregroundStyle(Theme.C.ink2) }
            }
            .padding(.horizontal, Theme.pagePadding).padding(.bottom, 40)
            .onGeometryChange(for: CGFloat.self) { g in g.size.height } action: { h in height = h }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(height + 33), .large])
        .sheet8()
    }
}

/// Laden-Empfehlung (42) als Zeilen: „Rewe + Lidl · 39,50 €“ mit „So aufteilen“, darunter die zweite Möglichkeit und „Mehr“.
private struct StoreAdviceRows: View {
    @Environment(AppStore.self) private var store
    let listId: Int
    @State private var combos: [StoreComboDTO]?
    @State private var failed = false
    @State private var picked: [String]?
    @State private var more = false
    @State private var assigning = false

    var body: some View {
        let open = store.listItems.filter { i in !i.checked && i.nextWeek != true }
        VStack(alignment: .leading, spacing: 0) {
            if let combos, combos.count > 1, !open.isEmpty {
                rows(combos).transition(.opacity)
            } else if failed {
                HStack {
                    Text("Laden-Empfehlung gerade nicht verfügbar.").font(Theme.F.text(13)).foregroundStyle(Theme.C.ink2)
                    Spacer()
                    Button("Erneut") { Task { await load() } }.font(Theme.F.text(13, .bold)).frame(minHeight: 44)
                }
                .overlay(alignment: .top) { Hairline() }
            } else if combos == nil && !open.isEmpty {
                Skeleton8(height: 60)
            }
        }
        .animation(Theme.spring, value: combos)
        .animation(Theme.spring, value: more)
        .task(id: open.map(\.id).hashValue ^ open.map(\.chain).hashValue) { await load() }
    }

    private func load() async {
        do {
            combos = try await store.storeCombos(listId)
            failed = false
        } catch {
            failed = combos == nil
        }
    }

    private static func title(_ c: StoreComboDTO) -> String { c.name.prefix(1).uppercased() + c.name.dropFirst() + " · " + euro(c.totalCents) }

    private func rows(_ combos: [StoreComboDTO]) -> some View {
        let single = combos.first { c in c.chains.count == 1 }
        let pair = combos.first { c in c.chains.count == 2 && c.savedCents > 0 }
        let main = combos.first { c in c.chains == picked } ?? combos[0]
        let other = [pair, single].compactMap { c in c }.first { c in c.chains != main.chains }
        let km = main.chains.count > 1 ? main.extraKm.map { k in "+1 Laden · +\(num(k, 1...1)) km" } : main.distanceKm.map { k in "\(num(k, 1...1)) km Weg" }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Icon(.trophy).frame(width: Theme.S.rowCircle, height: Theme.S.rowCircle).background(Theme.C.blue1, in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.title(main)).font(Theme.F.text(16, .extrabold)).lineLimit(1).minimumScaleFactor(0.8)
                    if main.savedCents > 0 {
                        Text("\(euro(main.savedCents)) gespart").font(Theme.F.text(12)).foregroundStyle(Theme.C.success)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    assigning = true
                    Task {
                        if await store.assignStores(listId, main.chains) { await load() }
                        assigning = false
                    }
                } label: {
                    Group { if assigning { Hop3().frame(width: 60) } else { Pill8(text: "So aufteilen").fixedSize() } }.tapArea(7)
                }
                .buttonStyle(PressableStyle())
                .disabled(assigning)
                .sensoryFeedback(.success, trigger: assigning)
            }
            .padding(.vertical, 7)
            .overlay(alignment: .top) { Hairline() }
            HStack {
                if let other {
                    Button { withAnimation(Theme.spring) { picked = other.chains } } label: {
                        Text(Self.title(other)).font(Theme.F.text(13)).foregroundStyle(Theme.C.ink2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Als Vorschlag wählen")
                }
                Spacer()
                Button { more.toggle() } label: {
                    HStack(spacing: 0) {
                        Text(more ? "Weniger" : "Mehr").font(Theme.F.text(13, .bold))
                        Icon(.chev, size: 16).rotationEffect(.degrees(more ? 90 : 0))
                    }
                    .foregroundStyle(Theme.C.ink)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 44)
            .overlay(alignment: .top) { Hairline() }
            if more {
                VStack(alignment: .leading, spacing: 4) {
                    if let km { Text(km) }
                    if main.unpriced > 0 {
                        Text(main.unpriced == 1 ? "1 Artikel ohne bekannten Preis zählt nicht mit." : "\(main.unpriced) Artikel ohne bekannten Preis zählen nicht mit.")
                    }
                    Text("„So aufteilen“ ordnet jeden offenen Artikel dem günstigsten der Läden zu.")
                }
                .font(Theme.F.text(12)).foregroundStyle(Theme.C.ink2)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
    }
}

/// S5b Einkaufsliste eines Ladens (gemeinsam abhaken). Abhaken wie Animation a1-shop.
struct ShoppingListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let chain: String
    @State private var coupons: [CouponDTO] = []  // Coupons für diesen Laden (38d)
    @State private var live = false  // Live-Aktivität läuft für diesen Laden (37)
    @State private var newItem = ""
    @State private var voiceOpen = Demo.screen == "voiceadd"
    @State private var settling: Set<Int> = []  // gerade abgehakt: bleibt kurz an ihrem Platz, dann rutscht sie ans Ende
    @State private var showCoupons = false
    @State private var showLater = false

    // Mockup-Lage (S5b): Blatt oben rechts mit Einkäufer; offline 30 höher, Figur 60 tiefer (Banner oben)
    private enum M {
        static let leaf = CGSize(width: 166, height: 270), leafOffline: CGFloat = 300, leafRadius: CGFloat = 110
        static let shopper: CGFloat = 144, shopperRight: CGFloat = 6, shopperTop: CGFloat = 44, shopperTopOffline: CGFloat = 104, topOffline: CGFloat = 72
    }

    private enum Line: Identifiable, Equatable {
        case item(ListItemDTO), add
        var id: Int { if case .item(let i) = self { i.id } else { Int.min } }
    }

    var body: some View {
        let items = store.listItems.filter { $0.chain == chain && $0.nextWeek != true }
        let later = store.listItems.filter { $0.chain == chain && $0.nextWeek == true }
        let open = items.filter { !$0.checked }
        let total = open.compactMap { store.offer(for: $0)?.priceCents }.reduce(0, +)
        let saved = open.compactMap { store.offer(for: $0) }.map { o in max(0, (o.regularPriceCents ?? o.priceCents) - o.priceCents) }.reduce(0, +)
        let shown = items.filter { i in i.checked == settling.contains(i.id) }.sorted { $0.name < $1.name }  // offen (oder gerade abgehakt)
        let done = items.filter { i in i.checked != settling.contains(i.id) }.sorted { $0.name < $1.name }
        let lines = shown.map(Line.item) + [.add] + done.map(Line.item)
        let offline = !store.api.online
        let names = store.profiles.map(\.name).filter { !$0.isEmpty }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button { dismiss() } label: {
                    HStack(spacing: 2) {
                        Icon(.back)
                        Text("Einkauf").font(Theme.F.small)
                    }
                    .foregroundStyle(Theme.C.ink)
                    .tapArea()
                }
                .buttonStyle(.plain)
                .padding(.leading, -6)
                .accessibilityLabel("Zurück zu Einkauf")
                Text(([open.count == 1 ? "1 offen" : "\(open.count) offen"] + (names.isEmpty ? [] : [names.joined(separator: ", ")])).joined(separator: " · "))
                    .font(Theme.F.small).foregroundStyle(Theme.C.ink2).padding(.top, 12)
                    .contentTransition(.numericText())
                Text(chain.isEmpty ? "Überall" : Labels.chain(chain)).font(Theme.F.t1).accessibilityAddTraits(.isHeader)
                VStack(spacing: 10) {
                    StatNumber(label: "Offen", value: euro(total), size: 40)
                    StatNumber(label: "Gespart", value: euro(saved), size: 28, mute: true)
                }
                .frame(width: 190)
                .padding(.top, 16)
                HStack(spacing: 10) {
                    startButton
                    if !coupons.isEmpty { couponPill }
                }
                .padding(.top, 28)
                VStack(spacing: 0) {
                    ForEach(lines) { line in
                        switch line {
                        case .item(let item): itemRow(item)
                        case .add: AddItemField(text: $newItem, add: add) { withAnimation(Theme.spring) { voiceOpen = true } }
                        }
                    }
                    if !later.isEmpty { NextWeekRow(count: later.count) { showLater = true } }
                }
                .padding(.top, 28)
                .sensoryFeedback(.impact(weight: .light), trigger: items.filter(\.checked).count)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, offline ? M.topOffline : 14)  // offline unter dem Glas-Banner (Mockup y 124)
            .padding(.bottom, 40)
        }
        .backdrop8 {
            Color.clear
                .pinned(right: M.shopperRight, top: offline ? M.shopperTopOffline : M.shopperTop) { Ill("shopper").frame(width: M.shopper) }
                .edgeForm(.leaf(M.leafRadius), Theme.C.blue, width: M.leaf.width, height: offline ? M.leafOffline : M.leaf.height, right: 0, top: 0)
        }
        .scrollDismissesKeyboard(.immediately)
        .overlay {
            if voiceOpen {
                VoiceAddOverlay { spoken in
                    withAnimation(Theme.spring) { voiceOpen = false }
                    if let id = store.householdList?.id { Task { await store.addSpoken(spoken, to: id, chain: chain) } }
                } close: { withAnimation(Theme.spring) { voiceOpen = false } }
            }
        }
        .sheet(isPresented: $showCoupons) { CouponPickSheet(coupons: coupons) }
        .sheet(isPresented: $showLater) { NextWeekSheet(chain: chain) }
        .hidesTabBar()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            live = LiveShop.running(chain)
            if !chain.isEmpty { coupons = await store.storeCoupons(chain) }
        }
    }

    /// `.btn2` klein (40 hoch): „Einkauf starten“ bzw. „Einkauf beenden“ (Live-Aktivität 37).
    private var startButton: some View {
        Button {
            if live {
                LiveShop.end()
            } else if store.demo || LiveShop.available {
                do { try LiveShop.start(chain: chain, list: store.householdList) } catch { store.flash("Live-Aktivität nicht möglich"); return }
            } else {
                store.flash("Live-Aktivität ist auf diesem iPhone aus"); return
            }
            withAnimation(Theme.spring) { live.toggle() }
        } label: {
            HStack(spacing: 8) {
                Icon(live ? .pause : .play, size: 16)
                Text(live ? "Einkauf beenden" : "Einkauf starten")
            }
            .font(Theme.F.text(14, .extrabold, relativeTo: .subheadline))
            .foregroundStyle(Theme.C.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .overlay(Capsule().strokeBorder(Theme.C.ink, lineWidth: Theme.S.hair))
            .contentShape(Capsule())
            .tapArea(2)
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.impact, trigger: live)
    }

    /// `.soft` 40 hoch: „2 Coupons ›“ → Kasse (ein Coupon) bzw. Auswahl.
    private var couponPill: some View {
        Button {
            if coupons.count == 1 { store.checkoutCoupon = coupons[0].id } else { showCoupons = true }
        } label: {
            HStack(spacing: 5) {
                Icon(.barcode, size: 15)
                Text(coupons.count == 1 ? "1 Coupon" : "\(coupons.count) Coupons")
                Icon(.chev, size: 14)
            }
            .font(Theme.F.text(13, .extrabold, relativeTo: .footnote))
            .foregroundStyle(Theme.C.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(Theme.C.blue1, in: Capsule())
            .tapArea(2)
        }
        .buttonStyle(PressableStyle())
    }

    /// `.irow` mit Haken; rechts höchstens ein Zusatz (Rabatt, Coupon oder „bald leer“).
    private func itemRow(_ item: ListItemDTO) -> some View {
        let offer = store.offer(for: item)
        let done = item.checked
        let sub = [item.amountText, item.source == "stockup" ? "Vorratskauf" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(spacing: 14) {
            Button { toggle(item) } label: { CheckCircle(on: done).tapArea(9) }
                .buttonStyle(.plain)
                .accessibilityLabel(done ? "\(item.name) wieder offen" : "\(item.name) abhaken")
            VStack(alignment: .leading, spacing: 0) {
                Text(offer?.title ?? item.name).font(Theme.F.text(16, .bold))
                    .foregroundStyle(done ? Theme.C.ink3 : Theme.C.ink)
                    .overlay {
                        InkStrike()
                            .trim(from: 0, to: done ? 1 : 0)
                            .stroke(Theme.C.ink3, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                            .frame(height: 10).padding(.horizontal, -3)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3).delay(0.18), value: done)
                    }
                if !done, !sub.isEmpty { Text(sub).font(Theme.F.text(12)).foregroundStyle(Theme.C.ink2) }
            }
            Spacer(minLength: 8)
            if !done {
                if let d = offer?.discount {
                    DealPill(text: "−\(d) %")
                } else if let c = item.coupon {
                    CouponTag(coupon: c)
                } else if item.source == "rhythm" {
                    SoftPill(text: "bald leer")  // 58
                }
            }
        }
        .frame(minHeight: Theme.S.row)
        .overlay(alignment: .top) { Hairline() }
        .contentShape(Rectangle())
        .onTapGesture { toggle(item) }
        .contextMenu {
            if let c = item.coupon {
                Button("Coupon zeigen", systemImage: "barcode") { store.checkoutCoupon = c.id }
            }
            Button("Entfernen", systemImage: "trash", role: .destructive) { Task { await store.deleteItem(item) } }
        }
    }

    /// a1-shop: Haken ploppt, Strich zieht sich durch (0,3 s), nach 0,5 s rutscht die Zeile federnd ans Ende.
    private func toggle(_ item: ListItemDTO) {
        settling.insert(item.id)
        Task { await store.toggle(item) }
        Task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.05 : 0.5))
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.7)) { _ = settling.remove(item.id) }
        }
    }

    private func add() {
        let name = newItem.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let id = store.householdList?.id else { return }
        newItem = ""
        store.flash("„\(name)“ hinzugefügt")
        Task { await store.addItem(name: name, chain: chain, to: id) }
    }
}

/// Tinten-Strich durch den Namen (a1-shop: `M0 6Q25 3 50 5.5T100 4.5` in 100 × 10).
private struct InkStrike: Shape {
    func path(in r: CGRect) -> Path {
        let x = { (v: CGFloat) in r.minX + v / 100 * r.width }, y = { (v: CGFloat) in r.minY + v / 10 * r.height }
        var p = Path()
        p.move(to: CGPoint(x: x(0), y: y(6)))
        p.addQuadCurve(to: CGPoint(x: x(50), y: y(5.5)), control: CGPoint(x: x(25), y: y(3)))
        p.addQuadCurve(to: CGPoint(x: x(100), y: y(4.5)), control: CGPoint(x: x(75), y: y(8)))
        return p
    }
}

/// Auswahl bei mehreren Coupons für den Laden → Kasse.
private struct CouponPickSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let coupons: [CouponDTO]
    @State private var height: CGFloat = 300

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("An der Kasse zeigen").font(Theme.F.t2)
                    Spacer()
                    CloseButton { dismiss() }
                }
                .padding(.bottom, 16)
                ForEach(coupons) { c in
                    Button {
                        dismiss()
                        store.checkoutCoupon = c.id
                    } label: { CouponRow(coupon: c) }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, Theme.pagePadding).padding(.bottom, 40)
            .onGeometryChange(for: CGFloat.self) { g in g.size.height } action: { h in height = h }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(height + 33), .large])
        .sheet8()
    }
}

/// Teilen-Knopf (`.x`-Look: Kreis 40 mit Haarlinie).
struct ShareButton: View {
    @Environment(AppStore.self) private var store
    var small = false

    var body: some View {
        ShareLink(item: store.shareText) {
            Icon(.share, size: small ? 18 : 20)
                .foregroundStyle(Theme.C.ink)
                .frame(width: Theme.S.close, height: Theme.S.close)
                .overlay(Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Plan und Liste teilen")
    }
}
