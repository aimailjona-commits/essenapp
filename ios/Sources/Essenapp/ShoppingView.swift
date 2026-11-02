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

/// S5 Einkauf: gemeinsame Haushaltsliste (je Laden eine Karte) + einmalige Listen; Pille „Vorrat“ → S16.
struct ShoppingView: View {
    @Environment(AppStore.self) private var store
    @State private var newItem = ""
    @State private var newListName = ""
    @State private var askNewList = false
    @State private var pantryMode = Demo.screen == "pantry"
    @State private var voiceOpen = Demo.screen == "voiceadd"

    var body: some View {
        VStack(spacing: 6) {
            PillSegment(options: [(false, "Liste"), (true, "Vorrat")], selection: $pantryMode)
                .padding(.horizontal, Theme.pagePadding)
            if pantryMode { PantryView() } else { listPage }
        }
        .overlay {
            if voiceOpen {
                VoiceAddOverlay { items in
                    withAnimation(Theme.spring) { voiceOpen = false }
                    if let id = store.householdList?.id { Task { await store.addSpoken(items, to: id) } }
                } close: { withAnimation(Theme.spring) { voiceOpen = false } }
            }
        }
    }

    @ViewBuilder private var listPage: some View {
        let items = store.listItems
        let groups = Dictionary(grouping: items, by: \.chain).sorted { ($0.key.isEmpty ? "~" : $0.key) < ($1.key.isEmpty ? "~" : $1.key) }
        let oneoffs = store.lists.filter { $0.kind == "oneoff" }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    DisplayHeader(line1: "Einkauf", line2: "\(items.filter { !$0.checked }.count) offen · gemeinsam")
                    ShareButton()
                }
                AddItemField(text: $newItem, add: add) { withAnimation(Theme.spring) { voiceOpen = true } }
                if let plan = store.plan, plan.savedCents > 0 {
                    HStack(spacing: 14) {
                        Text("💰").font(.system(size: 28)).frame(width: 54, height: 54).background(Theme.C.successSoft, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Diese Woche gespart").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                            Text(euro(plan.savedCents)).font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Theme.C.success).contentTransition(.numericText())
                        }
                        Spacer()
                    }
                    .padding(16).card().appear()
                }
                if groups.isEmpty {
                    EmptyState(emoji: "🛒", title: "Liste ist leer", text: "Sobald ein Wochenplan da ist, steht hier alles, was du kaufen musst.")
                }
                ForEach(Array(groups.enumerated()), id: \.element.key) { i, group in
                    NavigationLink { ShoppingListView(chain: group.key) } label: { ListCard(chain: group.key, items: group.value) }
                        .buttonStyle(PressableStyle())
                        .appear(delay: Double(i) * 0.05)
                }

                HStack {
                    Text("Einmalige Listen").font(Theme.F.headline)
                    Spacer()
                    Button { askNewList = true } label: { Label("Neu", systemImage: "plus").font(Theme.F.callout) }
                }
                .padding(.top, 8)
                if oneoffs.isEmpty {
                    Text("Z. B. für eine Grillparty – teilbar per Link, auch mit Leuten ohne App.")
                        .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                }
                ForEach(oneoffs) { l in
                    NavigationLink { OneOffListView(summary: l) } label: {
                        HStack(spacing: 14) {
                            Text("🎉").font(.system(size: 24)).frame(width: 52, height: 52).background(Theme.C.accentSoft, in: RoundedRectangle(cornerRadius: 15))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(l.name).font(.system(.headline, weight: .bold))
                                Text("\(l.openCount) offen · \(l.totalCount) gesamt").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.C.text3)
                        }
                        .foregroundStyle(Theme.C.text1)
                        .padding(16).card()
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu {
                        Button("Liste löschen", systemImage: "trash", role: .destructive) { Task { await store.deleteList(l.id) } }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await store.loadLists() }
        .task {
            while !Task.isCancelled {  // gemeinsames Einkaufen: Änderungen der anderen alle 10 s holen
                await store.loadLists()
                try? await Task.sleep(for: .seconds(10))
            }
        }
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

    private func add() {
        let name = newItem.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let id = store.householdList?.id else { return }
        newItem = ""
        store.flash("„\(name)“ hinzugefügt")
        Task { await store.addItem(name: name, to: id) }
    }
}

/// Listen-Karte: weiß, Händler-Logo, offene Artikel, Fortschritt, Emoji-Collage.
struct ListCard: View {
    @Environment(AppStore.self) private var store
    let chain: String
    let items: [ListItemDTO]

    var body: some View {
        let emojis = Array(Set(items.compactMap { store.offer(for: $0).map { Theme.hue(category: $0.category).emoji } })).prefix(3)
        let open = items.filter { !$0.checked }.count
        let total = items.compactMap { store.offer(for: $0)?.priceCents }.reduce(0, +)
        HStack(spacing: 14) {
            if chain.isEmpty {
                Text("🧺").font(.system(size: 26)).frame(width: 52, height: 52).background(Theme.C.surface, in: RoundedRectangle(cornerRadius: 15))
            } else {
                StoreLogo(chain: chain, size: 52)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(chain.isEmpty ? "Überall erhältlich" : Labels.chain(chain)).font(.system(.headline, weight: .bold))
                HStack(spacing: 8) {
                    Text(open == 0 ? "Erledigt ✓" : "\(open) offen").font(Theme.F.micro)
                        .foregroundStyle(open == 0 ? Theme.C.success : Theme.C.accent)
                        .padding(.horizontal, 9).frame(height: 22)
                        .background(open == 0 ? Theme.C.successSoft : Theme.C.accentSoft, in: Capsule())
                    if total > 0 { Text(euro(total)).font(Theme.F.micro).foregroundStyle(Theme.C.text2) }
                }
                ProgressView(value: Double(items.count - open), total: Double(max(items.count, 1)))
                    .tint(open == 0 ? Theme.C.success : Theme.C.accent)
            }
            Spacer(minLength: 0)
            Text(emojis.isEmpty ? "🛍️" : emojis.joined()).font(.system(size: 22))
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.C.text3)
        }
        .foregroundStyle(Theme.C.text1)
        .padding(16)
        .card()
    }
}

/// S5b Einkaufsliste eines Ladens (gemeinsam abhaken).
struct ShoppingListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let chain: String

    var body: some View {
        let items = store.listItems.filter { $0.chain == chain }
            .sorted { $0.checked == $1.checked ? $0.name < $1.name : !$0.checked }
        let total = items.filter { !$0.checked }.compactMap { store.offer(for: $0)?.priceCents }.reduce(0, +)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                    Spacer()
                    if !chain.isEmpty { StoreLogo(chain: chain, size: 44) }
                }
                DisplayHeader(line1: chain.isEmpty ? "Überall" : Labels.chain(chain),
                              line2: total > 0 ? "\(items.filter { !$0.checked }.count) offen · \(euro(total))" : "\(items.filter { !$0.checked }.count) offen")
                    .padding(.bottom, 10)
                ForEach(items) { item in
                    Button { Task { await store.toggle(item) } } label: { ItemRow(item: item, offer: store.offer(for: item)) }
                        .buttonStyle(PressableStyle())
                        .sensoryFeedback(.success, trigger: item.checked)
                        .contextMenu {
                            Button("Entfernen", systemImage: "trash", role: .destructive) { Task { await store.deleteItem(item) } }
                        }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
            .animation(Theme.spring, value: items.map(\.checked))
        }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Teilen-Knopf (rund, wie die anderen Kopf-Buttons).
struct ShareButton: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ShareLink(item: store.shareText) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(Theme.C.text1)
                .background(Theme.C.card, in: Circle())
        }
        .accessibilityLabel("Plan und Liste teilen")
    }
}
