import SwiftUI

/// Eine Zeile der Einkaufsliste: aus dem Plan zusammengefasst oder selbst hinzugefügt.
struct ShoppingItem: Identifiable, Hashable {
    let id: String
    let name: String
    let amount: Double?
    let unit: String
    let chain: String  // "" = egal wo
    let offer: OfferDTO?
    var extraID: UUID?
    var priceCents: Int? { offer?.priceCents }
}

extension AppStore {
    /// shortcut: Liste wird aus dem Plan berechnet + lokale Extras, lokal abgehakt; gemeinsame Liste übers Backend in Phase 4.
    var shoppingItems: [ShoppingItem] {
        var sums: [String: (IngredientDTO, Double)] = [:]
        for meal in plan?.entries ?? [] {
            for ing in meal.recipe.ingredients where !ing.inPantry {
                let key = ing.offerId.map { "o\($0)" } ?? "\(ing.name.lowercased())|\(ing.unit)"
                sums[key, default: (ing, 0)].1 += ing.amount
            }
        }
        let fromPlan = sums.map { key, value in
            let offer = offers.first { $0.id == value.0.offerId }
            return ShoppingItem(id: key, name: offer?.title ?? value.0.name, amount: value.1, unit: value.0.unit,
                                chain: offer?.chain ?? "", offer: offer)
        }
        let planned = Set(fromPlan.compactMap { $0.offer?.id })
        let extra = extras.filter { $0.offerId.map { !planned.contains($0) } ?? true }.map { e in
            ShoppingItem(id: "x\(e.id)", name: e.name, amount: nil, unit: "", chain: e.chain,
                         offer: offers.first { $0.id == e.offerId }, extraID: e.id)
        }
        return (fromPlan + extra).sorted { $0.name < $1.name }
    }
}

/// S5 Einkauf: eine Karte pro Laden.
struct ShoppingView: View {
    @Environment(AppStore.self) private var store
    @State private var newItem = ""

    var body: some View {
        let items = store.shoppingItems
        let groups = Dictionary(grouping: items, by: \.chain).sorted { ($0.key.isEmpty ? "~" : $0.key) < ($1.key.isEmpty ? "~" : $1.key) }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    DisplayHeader(line1: "Einkauf", line2: "\(items.count) Artikel · \(groups.count) Listen")
                    ShareButton()
                }
                HStack(spacing: 10) {
                    TextField("Artikel hinzufügen …", text: $newItem)
                        .padding(.horizontal, 16).frame(height: 46)
                        .background(Theme.C.card, in: Capsule()).overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: 0.5))
                        .onSubmit(add)
                    RoundIconButton(systemName: "plus", dark: true, label: "Hinzufügen", action: add)
                }
                if let plan = store.plan, plan.savedCents > 0 {
                    HStack(spacing: 14) {
                        Text("💰").font(.system(size: 30)).frame(width: 56, height: 56).background(Theme.C.accentSoft, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Diese Woche gespart").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                            Text(euro(plan.savedCents)).font(.system(size: 28, weight: .bold, design: .rounded))
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
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func add() {
        let name = newItem.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        withAnimation(Theme.spring) { store.extras.append(ExtraItem(name: name)) }
        newItem = ""
        store.flash("„\(name)“ hinzugefügt")
    }
}

/// Große Listen-Karte (Referenz 07) mit Laden-Farbe und Emoji-Collage.
struct ListCard: View {
    @Environment(AppStore.self) private var store
    let chain: String
    let items: [ShoppingItem]

    var body: some View {
        let color = chain.isEmpty ? Theme.C.accent : Theme.storeColor(chain)
        let emojis = Array(Set(items.compactMap { $0.offer.map { Theme.hue(category: $0.category).emoji } })).prefix(3)
        let open = items.filter { !ShoppingListView.isChecked($0, plan: store.plan?.id) }.count
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(chain.isEmpty ? "Überall erhältlich" : Labels.chain(chain)).font(.system(.title2, design: .rounded, weight: .bold))
                Text(open == 0 ? "Alles erledigt ✓" : "\(open) offen").font(Theme.F.micro).foregroundStyle(.white)
                    .padding(.horizontal, 9).frame(height: 22).background(color, in: Capsule())
                Spacer(minLength: 0)
                ProgressView(value: Double(items.count - open), total: Double(max(items.count, 1))).tint(color).frame(width: 120)
            }
            Spacer()
            Text(emojis.isEmpty ? "🛍️" : emojis.joined()).font(.system(size: 34)).rotationEffect(.degrees(-8))
        }
        .foregroundStyle(Theme.C.text1)
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: Theme.R.card, style: .continuous))
    }
}

/// S5b Einkaufsliste eines Ladens, offline abhakbar.
struct ShoppingListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let chain: String
    @AppStorage("checkedItems") private var checkedRaw = ""

    static func key(_ item: ShoppingItem, plan: Int?) -> String { "\(plan ?? 0):\(item.id)" }

    static func isChecked(_ item: ShoppingItem, plan: Int?) -> Bool {
        (UserDefaults.standard.string(forKey: "checkedItems") ?? "").split(separator: ",").contains { $0 == key(item, plan: plan) }
    }

    private var checked: Set<String> { Set(checkedRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        let items = store.shoppingItems.filter { $0.chain == chain }
        let planID = store.plan?.id
        let sorted = items.sorted {
            let a = checked.contains(Self.key($0, plan: planID)), b = checked.contains(Self.key($1, plan: planID))
            return a == b ? $0.name < $1.name : !a
        }
        let total = items.compactMap(\.priceCents).reduce(0, +)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                DisplayHeader(line1: chain.isEmpty ? "Überall" : Labels.chain(chain),
                              line2: total > 0 ? "\(items.count) Artikel · \(euro(total))" : "\(items.count) Artikel")
                    .padding(.bottom, 10)
                ForEach(sorted) { item in
                    let done = checked.contains(Self.key(item, plan: planID))
                    Button { toggle(item, planID) } label: { row(item, done: done) }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            if let id = item.extraID {
                                Button("Entfernen", systemImage: "trash", role: .destructive) {
                                    withAnimation(Theme.spring) { store.extras.removeAll { $0.id == id } }
                                }
                            }
                        }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
            .animation(Theme.spring, value: checkedRaw)
        }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.success, trigger: checkedRaw)
    }

    private func toggle(_ item: ShoppingItem, _ planID: Int?) {
        var set = checked
        let key = Self.key(item, plan: planID)
        if set.remove(key) == nil { set.insert(key) }
        checkedRaw = set.sorted().joined(separator: ",")
    }

    private func row(_ item: ShoppingItem, done: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24))
                .foregroundStyle(done ? Theme.C.accent : Theme.C.text3)
                .contentTransition(.symbolEffect(.replace))
            Text(item.offer.map { Theme.hue(category: $0.category).emoji } ?? "📝").font(.system(size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(.body, weight: .semibold)).strikethrough(done)
                    .foregroundStyle(done ? Theme.C.text3 : Theme.C.text1)
                if let amount = item.amount {
                    Text("\(amount.formatted()) \(item.unit == "stk" ? "Stück" : item.unit)").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                }
            }
            Spacer()
            if let price = item.priceCents {
                Text(euro(price)).font(.system(.subheadline, design: .rounded, weight: .bold)).monospacedDigit()
                    .foregroundStyle(done ? Theme.C.text3 : Theme.C.text1)
            }
        }
        .padding(14)
        .background(done ? Color.clear : Theme.C.card, in: RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous).strokeBorder(Theme.C.line, lineWidth: done ? 0 : 0.5))
    }
}

extension AppStore {
    /// Plan + Einkaufsliste als Text zum Teilen (WhatsApp, Nachrichten …).
    var shareText: String {
        var lines = ["🥘 Wochenplan" + (plan.map { " KW \($0.week.suffix(2))" } ?? "")]
        for meal in plan?.entries ?? [] {
            lines.append("• \(Labels.days[meal.day]) \(Labels.meal(meal.mealType)): \(meal.recipe.title)")
        }
        let groups = Dictionary(grouping: shoppingItems, by: \.chain).sorted { $0.key < $1.key }
        lines.append("\n🛒 Einkaufsliste")
        for (chain, items) in groups {
            lines.append("\n\(chain.isEmpty ? "Überall" : Labels.chain(chain)):")
            lines += items.map { item in
                "◻︎ \(item.name)" + (item.amount.map { " – \($0.formatted()) \(item.unit == "stk" ? "Stück" : item.unit)" } ?? "")
            }
        }
        if let plan { lines.append("\nGeschätzt \(euro(plan.totalCents)), davon \(euro(plan.savedCents)) gespart 💚") }
        return lines.joined(separator: "\n")
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
                .overlay(Circle().strokeBorder(Theme.C.line, lineWidth: 0.5))
        }
        .accessibilityLabel("Plan und Liste teilen")
    }
}
