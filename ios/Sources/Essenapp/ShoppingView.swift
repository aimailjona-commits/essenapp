import SwiftUI

/// Eine Zeile der Einkaufsliste, aus dem Plan zusammengefasst.
struct ShoppingItem: Identifiable, Hashable {
    let id: String
    let name: String
    let amount: Double
    let unit: String
    let chain: String  // "" = egal wo
    let offer: OfferDTO?
}

extension AppStore {
    /// shortcut: Liste wird aus dem Plan berechnet und lokal abgehakt; gemeinsame Liste über das Backend in Phase 4.
    var shoppingItems: [ShoppingItem] {
        var sums: [String: (IngredientDTO, Double)] = [:]
        for meal in plan?.entries ?? [] {
            for ing in meal.recipe.ingredients where !ing.inPantry {
                let key = ing.offerId.map { "o\($0)" } ?? "\(ing.name.lowercased())|\(ing.unit)"
                sums[key, default: (ing, 0)].1 += ing.amount
            }
        }
        return sums.map { key, value in
            let offer = offers.first { $0.id == value.0.offerId }
            return ShoppingItem(id: key, name: offer?.title ?? value.0.name, amount: value.1, unit: value.0.unit,
                                chain: offer?.chain ?? "", offer: offer)
        }
        .sorted { $0.name < $1.name }
    }
}

/// S5 Einkauf: eine Karte pro Laden.
struct ShoppingView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let groups = Dictionary(grouping: store.shoppingItems, by: \.chain).sorted { ($0.key.isEmpty ? "~" : $0.key) < ($1.key.isEmpty ? "~" : $1.key) }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DisplayHeader(line1: "Einkauf", line2: "\(store.shoppingItems.count) Artikel in \(groups.count) Listen")
                if let plan = store.plan, plan.savedCents > 0 {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Diese Woche gespart").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                            Text(euro(plan.savedCents)).font(.system(size: 30, weight: .heavy)).foregroundStyle(Theme.C.success).monospacedDigit()
                            Text("gegenüber Normalpreis").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                        }
                        Spacer()
                    }
                    .padding(18).card()
                }
                if groups.isEmpty {
                    EmptyState(symbol: "bag", title: "Liste ist leer", text: "Sobald ein Wochenplan da ist, steht hier alles, was du kaufen musst.")
                }
                ForEach(Array(groups.enumerated()), id: \.offset) { i, group in
                    NavigationLink { ShoppingListView(chain: group.key) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.key.isEmpty ? "Überall erhältlich" : Labels.chain(group.key)).font(.system(.title2, weight: .heavy))
                            Text("\(group.value.count) Artikel").font(Theme.F.micro).foregroundStyle(.white)
                                .padding(.horizontal, 8).frame(height: 22).background(Theme.C.action, in: Capsule())
                        }
                        .foregroundStyle(Theme.C.text1)
                        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                        .padding(18)
                        .background(Theme.C.listTints[i % Theme.C.listTints.count], in: RoundedRectangle(cornerRadius: Theme.R.card, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
        }
    }
}

/// S5b Einkaufsliste eines Ladens, offline abhakbar.
struct ShoppingListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let chain: String
    @AppStorage("checkedItems") private var checkedRaw = ""

    private var checked: Set<String> { Set(checkedRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        let items = store.shoppingItems.filter { $0.chain == chain }
        let key = { (item: ShoppingItem) in "\(store.plan?.id ?? 0):\(item.id)" }
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                DisplayHeader(line1: chain.isEmpty ? "Überall" : Labels.chain(chain), line2: "\(items.count) Artikel").padding(.bottom, 10)
                ForEach(items.sorted { checked.contains(key($0)) == checked.contains(key($1)) ? $0.name < $1.name : !checked.contains(key($0)) }) { item in
                    let done = checked.contains(key(item))
                    Button {
                        var set = checked
                        if done { set.remove(key(item)) } else { set.insert(key(item)) }
                        checkedRaw = set.sorted().joined(separator: ",")
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 24))
                                .foregroundStyle(done ? Theme.C.accent : Color(hex: 0xCFCFCB))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.system(.body, weight: .semibold)).strikethrough(done)
                                    .foregroundStyle(done ? Theme.C.text3 : Theme.C.text1)
                                Text("\(item.amount.formatted()) \(item.unit == "stk" ? "Stück" : item.unit)").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                            }
                            Spacer()
                            if let offer = item.offer {
                                Text(euro(offer.priceCents)).font(.system(.subheadline, weight: .bold)).monospacedDigit()
                                    .foregroundStyle(done ? Theme.C.text3 : Theme.C.text1)
                            }
                        }
                        .padding(14)
                        .background(done ? .clear : Theme.C.cardTop, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
        }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// S13 Einstellungen (Grundversion: Server, Haushalt, Abmelden).
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var api = store.api
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                DisplayHeader(line1: "Einstellungen", line2: store.household?.name ?? "")
                if let h = store.household {
                    VStack(alignment: .leading, spacing: 10) {
                        row("Ort", h.plz)
                        row("Läden", h.stores.filter(\.enabled).map { Labels.chain($0.chain) }.joined(separator: ", "))
                        row("Personen", "\(h.persons)")
                        row("Budget", "\(euro(h.budgetFoodWeekCents)) / Woche")
                        row("Ernährung", ([h.diet] + h.allergies).joined(separator: " · "))
                    }
                    .padding(16).card(radius: 24)
                }
                Text("SERVER").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                TextField("http://…", text: $api.baseURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(14).background(Theme.C.cardTop, in: RoundedRectangle(cornerRadius: Theme.R.chip))
                Text("Die App muss alle 7 Tage neu installiert werden (kostenlose Apple-ID).")
                    .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                Button("Abmelden & neu einrichten") { api.token = nil; store.plan = nil; store.household = nil }
                    .foregroundStyle(Theme.C.danger).padding(.top, 10)
            }
            .padding(.horizontal, Theme.pagePadding)
        }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title).font(.system(.body, weight: .semibold)); Spacer(); Text(value).foregroundStyle(Theme.C.text2).lineLimit(1) }
    }
}
