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
    @State private var page = Demo.screen == "pantry" ? 1 : ["wallet", "bonus"].contains(Demo.screen ?? "") ? 2 : 0  // Liste | Vorrat | Coupons
    @State private var voiceOpen = Demo.screen == "voiceadd"

    private var segment: some View {
        PillSegment(options: [(0, "Liste"), (1, "Vorrat"), (2, "Coupons")], selection: $page)
    }

    var body: some View {
        VStack(spacing: 6) {
            if page != 0 { segment.padding(.horizontal, Theme.pagePadding) }  // Liste: Segment unter dem Kopf (v3)
            switch page {
            case 1: PantryView()
            case 2: CouponWalletView()
            default: listPage
            }
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
        let items = store.listItems.filter { i in i.nextWeek != true }
        let later = store.listItems.filter { i in i.nextWeek == true }  // Gruppe „Nächste Woche“ (30)
        let groups = Dictionary(grouping: items, by: \.chain).sorted { ($0.key.isEmpty ? "~" : $0.key) < ($1.key.isEmpty ? "~" : $1.key) }
        let oneoffs = store.lists.filter { $0.kind == "oneoff" }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    DisplayHeader(line1: "Einkauf")
                    HStack(spacing: 8) {
                        Text(groups.count + oneoffs.count == 1 ? "1 Liste" : "\(groups.count + oneoffs.count) Listen")
                            .font(.system(.subheadline, weight: .semibold))
                        RoundIconButton(systemName: "plus", label: "Neue Liste") { askNewList = true }
                    }
                    .padding(.top, 4)
                }
                segment.padding(.top, 2)
                if groups.isEmpty {
                    EmptyState(emoji: "🛒", title: "Liste ist leer", text: "Sobald ein Wochenplan da ist, steht hier alles, was du kaufen musst.")
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
                    ForEach(Array(groups.enumerated()), id: \.element.key) { i, group in
                        NavigationLink { ShoppingListView(chain: group.key) } label: {
                            FolderCard(chain: group.key, title: group.key.isEmpty ? "Überall" : Labels.chain(group.key),
                                       subtitle: group.value.count == 1 ? "1 Artikel" : "\(group.value.count) Artikel",
                                       avatar: avatar(group.value))
                        }
                        .buttonStyle(PressableStyle())
                        .appear(delay: Double(i) * 0.05)
                    }
                }
                if let plan = store.plan, plan.savedCents > 0 {
                    NavigationLink { SpendingView() } label: {
                        HStack {
                            Text("Diese Woche gespart").font(.system(.callout, weight: .semibold))
                            Spacer()
                            Text(euro(plan.savedCents)).font(.system(.title3, weight: .heavy)).foregroundStyle(Theme.C.lime)
                                .contentTransition(.numericText())
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
                                .frame(width: 38, height: 38).background(Theme.C.inkRaised, in: Circle())
                        }
                        .foregroundStyle(.white)
                        .padding(.leading, 22).padding(.trailing, 8).frame(height: 60)
                        .background(Theme.C.ink, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.top, 2)
                }
                // Ab hier noch nicht gemockt (redesign-v3.md 7, Gruppe D)
                AddItemField(text: $newItem, add: add) { withAnimation(Theme.spring) { voiceOpen = true } }
                if let id = store.householdList?.id { StoreAdviceCard(listId: id) }  // Laden-Empfehlung (42)
                if !later.isEmpty {
                    Label { Text("Nächste Woche").font(Theme.F.headline) } icon: { Text("📅") }.padding(.top, 8)
                    ForEach(later) { item in
                        Button { Task { await store.toggle(item) } } label: { ItemRow(item: item, offer: store.offer(for: item)) }
                            .buttonStyle(PressableStyle())
                            .contextMenu {
                                Button("Doch diese Woche", systemImage: "arrow.uturn.backward") { Task { await store.undoNextWeek(item) } }
                                Button("Entfernen", systemImage: "trash", role: .destructive) { Task { await store.deleteItem(item) } }
                            }
                            .accessibilityAction(named: "Doch diese Woche") { Task { await store.undoNextWeek(item) } }
                    }
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

    /// Emoji der Person, die zuletzt etwas auf die Laden-Liste gesetzt hat.
    private func avatar(_ items: [ListItemDTO]) -> String? {
        let names = items.map(\.addedBy).filter { !$0.isEmpty }
        return names.last.flatMap { n in store.profiles.first { $0.name == n }?.emoji }
    }

    private func add() {
        let name = newItem.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let id = store.householdList?.id else { return }
        newItem = ""
        store.flash("„\(name)“ hinzugefügt")
        Task { await store.addItem(name: name, to: id) }
    }
}

/// S5b Einkaufsliste eines Ladens (gemeinsam abhaken).
struct ShoppingListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let chain: String
    @State private var coupons: [CouponDTO] = []  // Coupon-Leiste (38d)
    @State private var live = false  // Live-Aktivität läuft für diesen Laden (37)
    @State private var newItem = ""
    @State private var voiceOpen = false

    var body: some View {
        let items = store.listItems.filter { $0.chain == chain && $0.nextWeek != true }
            .sorted { $0.checked == $1.checked ? $0.name < $1.name : !$0.checked }
        let open = items.filter { !$0.checked }
        let total = open.compactMap { store.offer(for: $0)?.priceCents }.reduce(0, +)
        let saved = open.compactMap { store.offer(for: $0) }.map { o in max(0, (o.regularPriceCents ?? o.priceCents) - o.priceCents) }.reduce(0, +)
        let color = Theme.storeColor(chain)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(open: open, total: total, saved: saved, color: color)
                VStack(alignment: .leading, spacing: 14) {
                    receipt(items, total: total, saved: saved)
                    // Ab hier noch nicht gemockt (redesign-v3.md 7, Gruppe D)
                    AddItemField(text: $newItem, add: add) { voiceOpen = true }
                    if !coupons.isEmpty { CouponBar(coupons: coupons) }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, -30)
                .padding(.bottom, 120)
            }
        }
        .background(Theme.C.bg)
        .overlay(alignment: .bottom) {
            TotalBar(label: "Noch offen", value: { Text(euro(total)).monospacedDigit() },
                     buttonTitle: live ? "Einkauf beenden" : "Einkauf starten", symbol: live ? "stop.fill" : "bag") {
                if live {
                    LiveShop.end()
                } else if store.demo || LiveShop.available {
                    do { try LiveShop.start(chain: chain, list: store.householdList) } catch { store.flash("Live-Aktivität nicht möglich"); return }
                } else {
                    store.flash("Live-Aktivität ist auf diesem iPhone aus"); return
                }
                withAnimation(Theme.spring) { live.toggle() }
            }
            .sensoryFeedback(.impact, trigger: live)
            .padding(.bottom, 2)
        }
        .hidesTabBar()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            live = LiveShop.running(chain)
            if !chain.isEmpty { coupons = await store.storeCoupons(chain) }
        }
    }

    private func header(open: [ListItemDTO], total: Int, saved: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                RoundIconButton(systemName: "chevron.left", fill: Theme.C.card, label: "Zurück") { dismiss() }
                Spacer()
                if !store.profiles.isEmpty {
                    Text("Geteilt mit").font(.system(.subheadline, weight: .bold))
                    HStack(spacing: -10) {
                        ForEach(store.profiles.prefix(3)) { p in
                            Text(p.emoji).font(.system(size: 18)).frame(width: 36, height: 36)
                                .background(Theme.C.card, in: Circle()).overlay(Circle().strokeBorder(color, lineWidth: 2))
                        }
                    }
                    .accessibilityElement().accessibilityLabel("Geteilt mit \(store.profiles.map(\.name).joined(separator: ", "))")
                }
                ShareButton(small: true)
            }
            HStack(spacing: 14) {
                StoreLogo(chain: chain, size: 60)
                DisplayHeader(line1: chain.isEmpty ? "Überall" : Labels.chain(chain), size: 56)
            }
            .padding(.top, 22)
            HStack {
                Text(total > 0 ? "\(open.count) offen · \(euro(total))" : "\(open.count) offen").font(.system(.callout, weight: .bold))
                Spacer()
                if saved > 0 {
                    (Text("−\(euro(saved))").foregroundStyle(Theme.C.lime) + Text(" gespart").foregroundStyle(.white))
                        .font(.system(.footnote, weight: .bold)).padding(.horizontal, 10).frame(height: 30)
                        .background(Theme.C.ink, in: Capsule())
                }
            }
            .padding(.top, 8)
        }
        .foregroundStyle(Theme.C.ink)
        .padding(.horizontal, Theme.pagePadding).padding(.top, 8).padding(.bottom, 64)
        .background { UnevenRoundedRectangle(bottomLeadingRadius: 40, bottomTrailingRadius: 40, style: .continuous).fill(color).ignoresSafeArea(edges: .top) }

    }

    private func receipt(_ items: [ListItemDTO], total: Int, saved: Int) -> some View {
        ReceiptPaper {
            Text("\(chain.isEmpty ? "Überall" : Labels.chain(chain)) · \(storeName)\nKW \(week) · \(items.count) Artikel".uppercased())
                .font(Theme.F.monoBold(12)).tracking(1).foregroundStyle(Color(hex: 0x555555))
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            ReceiptRule()
            if items.isEmpty {
                Text("Noch nichts auf der Liste.").foregroundStyle(Theme.C.chipText).padding(.vertical, 6)
            }
            ForEach(items) { item in
                let offer = store.offer(for: item)
                ReceiptRow(name: item.name,
                           amount: item.amount.map { "\(num($0, 0...2)) \(item.unit == "stk" ? "St" : item.unit)" },
                           discount: offer?.discount.map { "−\($0)%" },
                           price: offer.map { euro($0.priceCents).replacingOccurrences(of: " €", with: "") },
                           checked: item.checked) { Task { await store.toggle(item) } }
                    .contextMenu {
                        if let c = item.coupon {
                            Button("Coupon zeigen", systemImage: "barcode") { store.checkoutCoupon = c.id }
                        }
                        Button("Entfernen", systemImage: "trash", role: .destructive) { Task { await store.deleteItem(item) } }
                    }
            }
            ReceiptRule()
            HStack {
                Text("SUMME"); Spacer(); Text(euro(total))
            }
            .font(Theme.F.monoBold(16))
            if saved > 0 {
                HStack {
                    Text("davon gespart"); Spacer()
                    Scribble(color: Theme.C.deal) { Text(euro(saved)).font(Theme.F.monoBold()).foregroundStyle(Theme.C.deal) }
                }
                .padding(.top, 8)
            }
        }
        .animation(Theme.spring, value: items.map(\.checked))
    }

    private var storeName: String {
        store.household?.stores.first { $0.chain == chain && $0.enabled && !$0.storeName.isEmpty }?.storeName ?? "Filiale"
    }

    private var week: String {
        store.plan.map { String($0.week.suffix(2)) } ?? String(Calendar(identifier: .iso8601).component(.weekOfYear, from: .now))
    }

    private func add() {
        let name = newItem.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let id = store.householdList?.id else { return }
        newItem = ""
        store.flash("„\(name)“ hinzugefügt")
        Task { await store.addItem(name: name, chain: chain, to: id) }
    }
}

/// Teilen-Knopf (rund, wie die anderen Kopf-Buttons).
struct ShareButton: View {
    @Environment(AppStore.self) private var store
    var small = false

    var body: some View {
        ShareLink(item: store.shareText) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: small ? 14 : 18, weight: .semibold))
                .frame(width: small ? Theme.S.roundButtonSmall : Theme.S.roundButton, height: small ? Theme.S.roundButtonSmall : Theme.S.roundButton)
                .foregroundStyle(Theme.C.text1)
                .background(small ? Theme.C.card : Theme.C.surface, in: Circle())
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Plan und Liste teilen")
    }
}
