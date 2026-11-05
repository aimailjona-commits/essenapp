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

/// S5 Einkauf (v9 d.html): Listen als Einkaufstaschen, Laden-Empfehlung in „Sparen“. Segment „Vorrat“ → S16, „Coupons“ → S31.
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

/// S5 Übersicht v9 (d.html Variante B „Taschen-Reihe“): Taschen zum Wischen, unter der mittleren ihre nächsten Artikel
/// und „Öffnen“, darunter die Gruppe „Sparen“. „Artikel hinzufügen“ schwebt über der Leiste.
private struct ShoppingOverview: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var page: Int
    @State private var newItem = ""
    @FocusState private var typing: Bool
    @State private var newListName = ""
    @State private var askNewList = false
    @State private var voiceOpen = false
    @State private var showLater = false
    @State private var lastWeekSaved: Int?
    @State private var current: String?  // Tasche in der Mitte
    @State private var carWidth: CGFloat = 390
    @State private var openChain: String?
    @State private var openList: ListSummaryDTO?
    @State private var oneoffItems: [Int: [ListItemDTO]] = [:]  // Artikel eigener Listen, geholt sobald sie in der Mitte stehen

    // Mockup-Lage (d.html B1): Ellipse 630 × 330 hinter den Taschen (ab Statusleiste), Taschen 190, Nachbarn 0,72
    private enum M {
        static let blob = CGSize(width: 630, height: 330), blobLeft: CGFloat = -120, blobTop: CGFloat = 98
        static let bag: CGFloat = 190, side: CGFloat = 0.72, overlap: CGFloat = -38  // gap 6, margin 0 -22
        static let addSide: CGFloat = 16, addBottom: CGFloat = 128, scrollBottom: CGFloat = 180
    }

    /// Eine Tasche: Laden der Haushaltsliste oder eigene Liste.
    private struct Bag: Identifiable {
        var id: String
        var chain = ""
        var oneoff: ListSummaryDTO?
        var items: [ListItemDTO]

        var name: String { oneoff?.name ?? (chain.isEmpty ? "Überall" : Labels.chain(chain)) }
        var open: [ListItemDTO] { items.filter { i in !i.checked }.sorted { a, b in a.name < b.name } }
        var openCount: Int { oneoff?.openCount ?? open.count }
        var total: Int { oneoff?.totalCount ?? items.count }
    }

    private var bags: [Bag] {
        let items = store.listItems.filter { i in i.nextWeek != true }
        let chains = Dictionary(grouping: items, by: \.chain).sorted { a, b in (a.key.isEmpty ? "~" : a.key) < (b.key.isEmpty ? "~" : b.key) }
        return chains.map { c in Bag(id: "c:" + c.key, chain: c.key, items: c.value) }
            + store.lists.filter { l in l.kind == "oneoff" }.map { l in Bag(id: "l:\(l.id)", oneoff: l, items: oneoffItems[l.id] ?? []) }
    }

    var body: some View {
        let bags = self.bags
        let cur = bags.first { b in b.id == current } ?? bags.first
        let later = store.listItems.filter { i in i.nextWeek == true }  // Gruppe „Nächste Woche“ (30)
        let oneoffId = cur?.oneoff?.id
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ShopTabs(page: $page)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("KW \(week) · \(bags.map(\.openCount).reduce(0, +)) offen").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                        Text("Einkauf").font(Theme.F.t1).accessibilityAddTraits(.isHeader)
                    }
                    Spacer(minLength: 8)
                    Button { askNewList = true } label: {
                        Icon(.plus, size: 20).foregroundStyle(Theme.C.onInk)
                            .frame(width: 44, height: 44)
                            .background(Theme.C.ink, in: Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.bottom, 4)
                    .accessibilityLabel("Neue Liste, z. B. Grillparty")
                }
                .padding(.top, 16)

                if let cur {
                    carousel(bags, sel: cur.id)
                    dots(bags, sel: cur.id)
                    info(cur).padding(.top, 18)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Liste ist leer").font(Theme.F.t2)
                        Text("Sobald ein Wochenplan da ist, steht hier alles, was du kaufen musst.").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                    }
                    .padding(.top, 30)
                }

                SavingsGroup(listId: store.householdList?.id, week: week, lastWeekSaved: lastWeekSaved).padding(.top, 28)
                if !later.isEmpty { NextWeekRow(count: later.count) { showLater = true }.padding(.top, 14) }  // nicht im Mockup, Funktion bleibt
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, M.scrollBottom)
            .pinned(left: M.blobLeft, top: M.blobTop) {
                Ellipse().fill(Theme.C.blue1).frame(width: M.blob.width, height: M.blob.height).accessibilityHidden(true)
            }
        }
        .backdrop8 { Color.clear }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await store.loadLists() }
        .task {
            while !Task.isCancelled {  // gemeinsames Einkaufen: Änderungen der anderen alle 10 s holen
                await store.loadLists()
                try? await Task.sleep(for: .seconds(10))
            }
        }
        .task { lastWeekSaved = await savedLastWeek() }
        .task(id: oneoffId) {
            if let oneoffId, !store.demo { oneoffItems[oneoffId] = (try? await store.list(oneoffId))?.items }
        }
        .overlay(alignment: .bottom) {
            if !voiceOpen {  // `.d9-add`: schwebt über der Leiste, beim Tippen über der Tastatur
                AddField9(text: $newItem, focus: $typing, floating: true, add: add) {
                    typing = false
                    withAnimation(Theme.spring) { voiceOpen = true }
                }
                .padding(.horizontal, M.addSide)
                .padding(.bottom, typing ? 12 : M.addBottom)
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .overlay {
            if voiceOpen {
                VoiceAddOverlay { spoken in
                    withAnimation(Theme.spring) { voiceOpen = false }
                    if let id = store.householdList?.id { Task { await store.addSpoken(spoken, to: id) } }
                } close: { withAnimation(Theme.spring) { voiceOpen = false } }
            }
        }
        .navigationDestination(item: $openChain) { chain in ShoppingListView(chain: chain) }
        .navigationDestination(item: $openList) { l in OneOffListView(summary: l) }
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

    /// `.d9b-car`: Taschen nebeneinander, die mittlere groß; Antippen holt eine Tasche in die Mitte bzw. öffnet sie.
    private func carousel(_ bags: [Bag], sel: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: M.overlap) {
                ForEach(bags) { b in
                    let on = b.id == sel
                    Button {
                        if on { open(b) } else { withAnimation(reduceMotion ? nil : Theme.spring) { current = b.id } }
                    } label: { bag(b) }
                    .buttonStyle(PressableStyle())
                    .scaleEffect(on ? 1 : M.side)
                    .opacity(on ? 1 : 0.55)
                    .zIndex(on ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: on)
                    .accessibilityLabel("\(b.name), \(b.openCount) offen, \(b.total - b.openCount) von \(b.total) drin")
                    .accessibilityHint(on ? "Öffnet die Liste" : "In die Mitte holen")
                    .contextMenu {
                        if let l = b.oneoff {
                            Button("Liste löschen", systemImage: "trash", role: .destructive) { Task { await store.deleteList(l.id) } }
                        }
                    }
                }
            }
            .scrollTargetLayout()
            .padding(.top, 10)
            .padding(.bottom, 18)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $current)
        .contentMargins(.horizontal, max(0, (carWidth - M.bag) / 2), for: .scrollContent)
        .onGeometryChange(for: CGFloat.self) { g in g.size.width } action: { w in carWidth = w }
        .padding(.horizontal, -Theme.pagePadding)
        .padding(.top, 14)
        .sensoryFeedback(.selection, trigger: current)
    }

    private func bag(_ b: Bag) -> some View {
        ShopBag(kind: b.oneoff == nil ? BagKind.of(b.chain) : .tote,
                color: b.oneoff == nil ? Theme.storeColor(b.chain) : Theme.C.blue,
                width: M.bag, open: b.openCount, done: b.total - b.openCount,
                chain: b.oneoff == nil ? b.chain : nil, title: b.oneoff?.name,
                peeks: Array(store.bagPeeks(b.open).prefix(1)), who: ShopBag.shoppers(b.items), hole: Theme.C.blue1)
    }

    /// `.d9b-dots`: Punkt je Tasche, der aktuelle breit.
    private func dots(_ bags: [Bag], sel: String) -> some View {
        HStack(spacing: 6) {
            ForEach(bags) { b in
                Capsule().fill(b.id == sel ? Theme.C.ink : Theme.C.ink3).frame(width: b.id == sel ? 18 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: sel)
        .accessibilityHidden(true)
    }

    /// Name, wer einkauft, „8 von 20 drin“, „Öffnen ›“ und die nächsten drei Artikel der mittleren Tasche.
    private func info(_ b: Bag) -> some View {
        let who = ShopBag.shoppers(b.items)
        let parts: [String?] = [b.oneoff != nil ? "eigene Liste" : b.chain.isEmpty ? "egal wo" : nil,
                                who.isEmpty ? nil : who.joined(separator: " & ") + (who.count == 1 ? " kauft ein" : " kaufen ein"),
                                "\(b.total - b.openCount) von \(b.total) drin"]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(b.name).font(Theme.F.t2).lineLimit(1)
                    Text(parts.compactMap { p in p }.joined(separator: " · ")).font(Theme.F.text(13, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                }
                Spacer(minLength: 8)
                Button { open(b) } label: {
                    HStack(spacing: 6) {
                        Text("Öffnen")
                        Icon(.chev, size: 15)
                    }
                    .font(Theme.F.pill)
                    .foregroundStyle(Theme.C.onInk)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Theme.C.ink, in: Capsule())
                    .tapArea(4)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("\(b.name) öffnen")
            }
            VStack(spacing: 0) {
                ForEach(b.open.prefix(3)) { item in nextRow(item, checkable: b.oneoff == nil) }
            }
            .padding(.top, 10)
            .animation(reduceMotion ? nil : Theme.spring, value: b.open.map(\.id))
        }
    }

    /// `.d9-it` (46 hoch): Haken, Name, Menge, Rabatt; Antippen hakt ab (Haushaltsliste).
    @ViewBuilder private func nextRow(_ item: ListItemDTO, checkable: Bool) -> some View {
        let offer = store.offer(for: item)
        let row = HStack(spacing: 12) {
            CheckCircle(on: item.checked)
            VStack(alignment: .leading, spacing: 0) {
                Text(offer?.title ?? item.name).font(Theme.F.text(16, .bold)).lineLimit(1)
                if !item.amountText.isEmpty { Text(item.amountText).font(Theme.F.text(12)).foregroundStyle(Theme.C.ink2) }
            }
            Spacer(minLength: 8)
            if let d = offer?.discount { DealPill(text: "−\(d) %") }
        }
        .foregroundStyle(Theme.C.ink)
        .frame(minHeight: 46)
        .overlay(alignment: .top) { Hairline() }
        .contentShape(Rectangle())
        if checkable {
            Button { Task { await store.toggle(item) } } label: { row }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.name) abhaken")
        } else {
            row
        }
    }

    private func open(_ b: Bag) {
        if let l = b.oneoff { openList = l } else { openChain = b.chain }
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

/// Gruppe „Sparen“ (d.html B1): zwei Flächen nebeneinander, „Gespart“ (→ S11) und „Aufteilen“ (Laden-Empfehlung 42),
/// darunter die andere Möglichkeit mit „So aufteilen“. Antippen von „Aufteilen“ zeigt Weg und Hinweise („Mehr“).
private struct SavingsGroup: View {
    @Environment(AppStore.self) private var store
    let listId: Int?
    let week: String
    let lastWeekSaved: Int?
    @State private var combos: [StoreComboDTO]?
    @State private var failed = false
    @State private var picked: [String]?
    @State private var more = false
    @State private var assigning = false

    private enum M {
        static let radius: CGFloat = 26, pad: CGFloat = 16, minHeight: CGFloat = 150, row: CGFloat = 52, pill: CGFloat = 34
    }

    var body: some View {
        let open = store.listItems.filter { i in !i.checked && i.nextWeek != true }
        let advice = (combos?.count ?? 0) > 1 && !open.isEmpty ? combos : nil
        let main = advice.map { cs in cs.first { c in c.chains == picked } ?? cs[0] }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sparen").font(Theme.F.serif(22)).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("KW \(week)").font(Theme.F.text(13, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
            }
            .padding(.bottom, 14)
            HStack(spacing: 10) {
                NavigationLink { SavingsView() } label: { savedTile }  // S11 Ersparnis
                    .buttonStyle(PressableStyle())
                if let main {
                    Button { withAnimation(Theme.spring) { more.toggle() } } label: { splitTile(main) }
                        .buttonStyle(PressableStyle())
                        .accessibilityHint(more ? "Details ausblenden" : "Details zeigen")
                        .transition(.opacity)
                } else if combos == nil, !failed, !open.isEmpty, listId != nil {
                    Skeleton8(height: M.minHeight).frame(maxWidth: .infinity)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if let advice, let main {
                adviceRow(advice, main)
            } else if failed {
                HStack {
                    Text("Laden-Empfehlung gerade nicht verfügbar.").font(Theme.F.text(13)).foregroundStyle(Theme.C.ink2)
                    Spacer()
                    Button("Erneut") { Task { await load() } }.font(Theme.F.text(13, .bold)).frame(minHeight: 44)
                }
                .frame(minHeight: M.row)
                .overlay(alignment: .top) { Hairline() }
                .padding(.top, 14)
            }
        }
        .foregroundStyle(Theme.C.ink)
        .animation(Theme.spring, value: combos)
        .animation(Theme.spring, value: more)
        .task(id: open.map(\.id).hashValue ^ open.map(\.chain).hashValue) { await load() }
    }

    private func load() async {
        guard let listId else { return }
        do {
            combos = try await store.storeCombos(listId)
            failed = false
        } catch {
            failed = combos == nil
        }
    }

    private static func title(_ c: StoreComboDTO) -> String { c.name.prefix(1).uppercased() + c.name.dropFirst() + " · " + euro(c.totalCents) }

    private func tile<V: View>(_ color: Color, @ViewBuilder _ content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .foregroundStyle(Theme.C.ink)
            .padding(M.pad)
            .frame(maxWidth: .infinity, minHeight: M.minHeight, maxHeight: .infinity, alignment: .topLeading)
            .background(color, in: RoundedRectangle(cornerRadius: M.radius, style: .continuous))
            .accessibilityElement(children: .combine)
    }

    private var savedTile: some View {
        tile(Theme.C.card) {
            Text("GESPART").font(Theme.F.lbl).tracking(11 * 0.08)
            Spacer(minLength: 12)
            BigNumber(euro(store.plan?.savedCents ?? 0), size: 34)
            if let lastWeekSaved {
                Text("Letzte Woche \(euro(lastWeekSaved))").font(Theme.F.text(12, relativeTo: .caption)).foregroundStyle(Theme.C.ink2).padding(.top, 6)
            }
        }
    }

    private func splitTile(_ c: StoreComboDTO) -> some View {
        tile(Theme.C.sage) {
            Text("AUFTEILEN").font(Theme.F.lbl).tracking(11 * 0.08)
            Text(c.chains.map(Labels.chain).joined(separator: " + ")).font(Theme.F.text(14, .extrabold, relativeTo: .subheadline))
                .lineLimit(2).padding(.top, 6)
            Spacer(minLength: 12)
            BigNumber(euro(c.totalCents), size: 28)
            if c.savedCents > 0 {
                Text("−" + euro(c.savedCents)).font(Theme.F.text(12, .extrabold, relativeTo: .caption)).foregroundStyle(Theme.C.savedOnSage).padding(.top, 4)
            }
        }
    }

    /// `.hr` 52: die andere Möglichkeit (antippen = als Vorschlag wählen) und „So aufteilen“; darunter „Mehr“.
    private func adviceRow(_ combos: [StoreComboDTO], _ main: StoreComboDTO) -> some View {
        let single = combos.first { c in c.chains.count == 1 }
        let pair = combos.first { c in c.chains.count == 2 && c.savedCents > 0 }
        let other = [pair, single].compactMap { c in c }.first { c in c.chains != main.chains }
        let km = main.chains.count > 1 ? main.extraKm.map { k in "+1 Laden · +\(num(k, 1...1)) km" } : main.distanceKm.map { k in "\(num(k, 1...1)) km Weg" }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let other {
                    Button { withAnimation(Theme.spring) { picked = other.chains } } label: {
                        Text(Self.title(other)).font(Theme.F.text(13, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Als Vorschlag wählen")
                }
                Spacer(minLength: 8)
                Button {
                    assigning = true
                    Task {
                        if let listId, await store.assignStores(listId, main.chains) { await load() }
                        assigning = false
                    }
                } label: {
                    Group {
                        if assigning {
                            Hop3().frame(width: 60)
                        } else {
                            Text("So aufteilen").font(Theme.F.pill).foregroundStyle(Theme.C.onInk)
                                .padding(.horizontal, 12).frame(height: M.pill)
                                .background(Theme.C.ink, in: Capsule())
                                .fixedSize()
                        }
                    }
                    .tapArea(5)
                }
                .buttonStyle(PressableStyle())
                .disabled(assigning)
                .sensoryFeedback(.success, trigger: assigning)
            }
            .frame(minHeight: M.row)
            .overlay(alignment: .top) { Hairline() }
            .padding(.top, 14)
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

/// S5b geöffnete Tasche v9 (d.html Variante A): dieselbe Tasche groß oben rechts, Artikel nach Abteilung gruppiert,
/// Erledigtes zugeklappt in „In der Tasche · 8“. Abhaken wie Animation a1-shop.
struct ShoppingListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let chain: String
    @State private var coupons: [CouponDTO] = []  // Coupons für diesen Laden (38d)
    @State private var live = false  // Live-Aktivität läuft für diesen Laden (37)
    @State private var newItem = ""
    @FocusState private var typing: Bool
    @State private var voiceOpen = Demo.screen == "voiceadd"
    @State private var settling: Set<Int> = []  // gerade abgehakt: bleibt kurz an ihrem Platz, dann wandert sie in die Tasche
    @State private var showCoupons = false
    @State private var showLater = false
    @State private var showDone = false

    // Mockup-Lage (d.html A2): Kreis 300 oben rechts, Tasche 150; offline Tasche 60 tiefer, Inhalt unter dem Banner
    private enum M {
        static let blob: CGFloat = 300, blobRight: CGFloat = -128, blobTop: CGFloat = -30
        static let bag: CGFloat = 150, bagRight: CGFloat = 24, bagTop: CGFloat = 70, offlineShift: CGFloat = 60, topOffline: CGFloat = 72
        static let miniBag: CGFloat = 30, row: CGFloat = 54
    }

    var body: some View {
        let items = store.listItems.filter { $0.chain == chain && $0.nextWeek != true }
        let later = store.listItems.filter { $0.chain == chain && $0.nextWeek == true }
        let open = items.filter { !$0.checked }
        let total = open.compactMap { store.offer(for: $0)?.priceCents }.reduce(0, +)
        let shown = items.filter { i in i.checked == settling.contains(i.id) }  // offen (oder gerade abgehakt)
        let done = items.filter { i in i.checked != settling.contains(i.id) }.sorted { $0.name < $1.name }
        let order = Labels.categories.map { c in c.0 }
        let depts = Dictionary(grouping: shown) { i in store.department(i) }
            .sorted { a, b in (order.firstIndex(of: a.key) ?? order.count) < (order.firstIndex(of: b.key) ?? order.count) }
        let offline = !store.api.online
        let who = ShopBag.shoppers(items)
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
                Text(who.isEmpty ? (open.count == 1 ? "1 offen" : "\(open.count) offen")
                    : who.joined(separator: " & ") + (who.count == 1 ? " kauft ein" : " kaufen ein"))
                    .font(Theme.F.small).foregroundStyle(Theme.C.ink2).padding(.top, 12)
                    .contentTransition(.numericText())
                Text(chain.isEmpty ? "Überall" : Labels.chain(chain)).font(Theme.F.t1).accessibilityAddTraits(.isHeader)
                VStack(spacing: 10) {
                    StatNumber(label: "Offen", value: euro(total), size: 36)
                    StatNumber(label: "Drin", value: "\(items.count - open.count) / \(items.count)", size: 26, mute: true)
                }
                .frame(width: 180)
                .padding(.top, 16)
                HStack(spacing: 10) {
                    startButton
                    if !coupons.isEmpty { couponPill }
                }
                .padding(.top, 22)
                AddField9(text: $newItem, focus: $typing, add: add) {
                    typing = false
                    withAnimation(Theme.spring) { voiceOpen = true }
                }
                .padding(.top, 18)
                ForEach(depts, id: \.key) { d in
                    HStack {
                        Text(Labels.categoryName(d.key).uppercased())
                        Spacer()
                        Text("\(d.value.count)")
                    }
                    .font(Theme.F.lbl).tracking(11 * 0.08).foregroundStyle(Theme.C.ink2)
                    .padding(.top, 22).padding(.bottom, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    ForEach(d.value.sorted { a, b in a.name < b.name }) { item in itemRow(item) }
                }
                if !done.isEmpty {
                    inBagRow(done, open: open.count)
                    if showDone { ForEach(done) { item in itemRow(item) } }
                }
                if !later.isEmpty { NextWeekRow(count: later.count) { showLater = true } }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: items.filter(\.checked).count)
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, offline ? M.topOffline : 14)  // offline unter dem Glas-Banner (Mockup y 124)
            .padding(.bottom, 40)
        }
        .backdrop8 {
            Color.clear
                .pinned(right: M.bagRight, top: M.bagTop + (offline ? M.offlineShift : 0)) {
                    ShopBag(kind: BagKind.of(chain), color: Theme.storeColor(chain), width: M.bag, open: open.count, done: items.count - open.count,
                            chain: chain, peeks: Array(store.bagPeeks(open).prefix(2)), who: who, hole: Theme.C.blue1)
                        .accessibilityHidden(true)
                }
                .edgeForm(.circle, Theme.C.blue1, width: M.blob, height: M.blob, right: M.blobRight, top: M.blobTop)
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

    /// „In der Tasche · 8“: Mini-Tasche, die ersten Namen, zugeklappt; Antippen klappt das Erledigte auf.
    private func inBagRow(_ done: [ListItemDTO], open: Int) -> some View {
        Button { withAnimation(reduceMotion ? nil : Theme.spring) { showDone.toggle() } } label: {
            HStack(spacing: 12) {
                ShopBag(kind: BagKind.of(chain), color: Theme.storeColor(chain), width: M.miniBag, open: open, done: done.count, plain: true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("In der Tasche").font(Theme.F.text(16, .bold))
                    Text(done.prefix(3).map(\.name).joined(separator: ", ") + (done.count > 3 ? " …" : "")).font(Theme.F.text(12)).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("\(done.count)").font(Theme.F.text(13, relativeTo: .footnote))
                Icon(.chev, size: 18).rotationEffect(.degrees(showDone ? 90 : 0))
            }
            .foregroundStyle(Theme.C.ink2)
            .frame(minHeight: M.row)
            .overlay(alignment: .top) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("In der Tasche, \(done.count) erledigt")
        .accessibilityHint(showDone ? "Zuklappen" : "Aufklappen")
        .accessibilityAddTraits(.isButton)
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

    /// `.soft` 40 hoch: „2 Coupons“ → Kasse (ein Coupon) bzw. Auswahl.
    private var couponPill: some View {
        Button {
            if coupons.count == 1 { store.checkoutCoupon = coupons[0].id } else { showCoupons = true }
        } label: {
            HStack(spacing: 5) {
                Icon(.barcode, size: 15)
                Text(coupons.count == 1 ? "1 Coupon" : "\(coupons.count) Coupons")
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

    /// `.d9-it` (54 hoch) mit Haken; rechts höchstens ein Zusatz (Rabatt, Coupon oder „bald leer“).
    private func itemRow(_ item: ListItemDTO) -> some View {
        let offer = store.offer(for: item)
        let done = item.checked
        let sub = [item.amountText, item.source == "stockup" ? "Vorratskauf" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(spacing: 12) {
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
        .frame(minHeight: M.row)
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
