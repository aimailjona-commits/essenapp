import SwiftUI

// Gericht-Knöpfe (v9 f.html Abschnitt 3): überall Kochen · Tauschen · Liste · Teilen · Mehr; „Mehr“ und langes Drücken
// öffnen dasselbe Gericht-Menü. Bündelt nur vorhandene Abläufe (RerollDialog, PlanSlotSheet, GuestsSheet, RatingSheet, DislikeDialog …).

enum DishAction: Hashable {
    case cook, swap, list, share, shareLink, menu, plan, guests, lock, favorite, rate, dislike, noMood, extra(Int)
}

/// Zusatzzeile im Menü (Rezeptdetail: Bearbeiten, Löschen, Fehler melden …).
struct DishExtra {
    let title: String
    let icon: Icon8
    var red = false
    let run: () -> Void
}

/// Ein Gericht und was an diesem Ort anders läuft. `meal == nil`: KI-Karte im Swipe ohne Rezept (nur Kopf + eigene Abläufe).
struct Dish {
    var meal: MealDTO?
    var title: String
    var imageUrl: String
    var sub: String
    var hints: [DishAction: String] = [:]  // Unterzeile im Menü, z. B. „Sa · Abend“ bei Einplanen
    var custom: [DishAction: () -> Void] = [:]  // Ort-eigener Ablauf statt des Standard-Dialogs
    var openList: (() -> Void)?  // Zutaten schon drauf → Einkauf zeigen
    var extras: [DishExtra] = []

    init(meal: MealDTO?, title: String, imageUrl: String, sub: String) {
        self.meal = meal
        self.title = title
        self.imageUrl = imageUrl
        self.sub = sub
    }

    init(_ meal: MealDTO) {
        let slot = meal.id != nil && Labels.dayNames.indices.contains(meal.day)
        self.init(meal: meal, title: meal.recipe.title, imageUrl: meal.recipe.imageUrl,
                  sub: slot ? "\(Labels.dayNames[meal.day]) · \(Labels.meal(meal.mealType))"
                      : "\(meal.recipe.prepMinutes) min · \(euro(PlanWeek.perPortion(meal))) p. P.")
    }

    /// Passt die Aktion hier? Tauschen, Gäste, Fixieren nur bei Gericht im Plan.
    func can(_ a: DishAction) -> Bool {
        if custom[a] != nil { return true }
        switch a {
        case .menu, .extra: return true
        case .noMood: return false
        case .swap, .guests, .lock: return meal?.id != nil
        default: return meal != nil
        }
    }
}

extension AppStore {
    /// Plan-Gericht im aktuellen Stand (gewürfelt, fixiert, Gäste).
    func current(_ m: MealDTO) -> MealDTO { m.id.flatMap { id in plan?.entries.first { e in e.id == id } } ?? m }

    /// Zutaten (ohne Vorrat), die noch nicht auf der Einkaufsliste stehen – per Name oder Angebot.
    // shortcut: Namensvergleich exakt (ohne Groß/klein); weicht der Listen-Name ab, zählt die Zutat als fehlend
    func missingOnList(_ m: MealDTO) -> [IngredientDTO] {
        let items = householdList?.items ?? []
        let names = Set(items.map { i in i.name.lowercased() })
        return m.recipe.ingredients.filter { i in
            i.inPantry != true && !names.contains(i.name.lowercased())
                && !(i.offerId.map { id in items.contains { $0.offerId == id } } ?? false)
        }
    }
}

private enum K {
    static let large: CGFloat = 46, largeIcon: CGFloat = 19, largeWidth: CGFloat = 56
    static let small: CGFloat = 32, smallIcon: CGFloat = 15, smallGap: CGFloat = 6, tap: CGFloat = 44
    static let menuPlate: CGFloat = 48, row: CGFloat = 50, rowIcon: CGFloat = 21
}

// MARK: Leiste

/// Kochen · Tauschen · Liste · Teilen · Mehr – groß mit Beschriftung (`.f9-acts`) oder klein ohne (`.f9-mini`).
struct DishActionBar: View {
    enum Style { case large, small }
    let dish: Dish
    var style: Style = .large
    @State private var action: DishAction?

    var body: some View {
        DishButtons(dish: dish, style: style) { a in action = a }
            .modifier(DishHost(dish: dish, action: $action))
    }
}

private struct DishButtons: View {
    @Environment(AppStore.self) private var store
    let dish: Dish
    let style: DishActionBar.Style
    var inMenu = false
    let pick: (DishAction) -> Void

    var body: some View {
        let listed = dish.meal.map { m in store.missingOnList(m).isEmpty } ?? false
        HStack(spacing: style == .large ? 0 : K.smallGap - (K.tap - K.small)) {
            button(.play, "Kochen", .cook, go: true)
            gap
            button(.swap, "Tauschen", .swap)
            gap
            button(.bag, "Liste", .list, on: listed, label: listed ? "Zutaten stehen auf der Liste" : "Zutaten auf die Liste")
            gap
            Menu {
                Button("Als Bild teilen", systemImage: "photo") { pick(.share) }
                Button("Als Link teilen", systemImage: "link") { pick(.shareLink) }  // Feature 56
            } label: { face(.share, "Teilen") }
            .disabled(!dish.can(.share))
            .opacity(dish.can(.share) ? 1 : 0.35)
            gap
            button(.dots, "Mehr", .menu, on: inMenu, label: "Gericht-Menü")
        }
        .padding(.horizontal, style == .large ? 0 : -(K.tap - K.small) / 2)  // sichtbare Kreise bündig, Tap-Fläche 44
        .sensoryFeedback(.success, trigger: listed)
    }

    @ViewBuilder private var gap: some View { if style == .large { Spacer(minLength: 4) } }

    private func button(_ icon: Icon8, _ title: String, _ a: DishAction, go: Bool = false, on: Bool = false, label: String? = nil) -> some View {
        Button { if !(inMenu && a == .menu) { pick(a) } } label: { face(icon, title, go: go, on: on, label: label) }
            .buttonStyle(PressableStyle())
            .disabled(!dish.can(a))
            .opacity(dish.can(a) ? 1 : 0.35)
    }

    /// Kreis (groß 46 mit Tinten-Rand, klein 32 mit Haarlinie); Kochen gefüllt, `on` blau (Liste schon drauf, offenes Menü).
    private func face(_ icon: Icon8, _ title: String, go: Bool = false, on: Bool = false, label: String? = nil) -> some View {
        let large = style == .large
        let d = large ? K.large : K.small
        return VStack(spacing: 5) {
            Icon(icon, size: large ? K.largeIcon : K.smallIcon)
                .foregroundStyle(go ? Theme.C.onInk : Theme.C.ink)
                .frame(width: d, height: d)
                .background(go ? Theme.C.ink : on ? Theme.C.blue : Theme.C.bg, in: Circle())
                .overlay { if !go && !on { Circle().strokeBorder(large ? Theme.C.ink : Theme.C.line, lineWidth: Theme.S.hair) } }
            if large { Text(title).font(Theme.F.text(11, .extrabold, relativeTo: .caption2)).foregroundStyle(Theme.C.ink) }
        }
        .frame(width: large ? K.largeWidth : K.tap, height: large ? nil : K.tap)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: Langes Drücken

extension View {
    /// Langes Drücken öffnet das Gericht-Menü (VoiceOver: Aktion „Gericht-Menü“).
    func dishPress(_ dish: Dish) -> some View { modifier(DishPress(dish: dish)) }

    /// Kein Gericht (freier Tag) → nichts.
    @ViewBuilder func dishPress(_ meal: MealDTO?) -> some View {
        if let meal { dishPress(Dish(meal)) } else { self }
    }

    /// Wie `dishPress`, aber der Host liegt außerhalb (Listen, Swipe): `open` lädt bei Bedarf und setzt den Host.
    func dishPress(open: @escaping () -> Void) -> some View {
        onLongPressGesture(minimumDuration: 0.5, perform: open)
            .accessibilityAction(named: "Gericht-Menü", open)
    }
}

private struct DishPress: ViewModifier {
    let dish: Dish
    @State private var action: DishAction?

    func body(content: Content) -> some View {
        content.dishPress { action = .menu }.modifier(DishHost(dish: dish, action: $action))
    }
}

// MARK: Host

/// Führt Gericht-Aktionen aus und zeigt die vorhandenen Dialoge. `action` setzen (Leiste, langes Drücken) startet sie.
struct DishHost: ViewModifier {
    @Environment(AppStore.self) private var store
    let dish: Dish?
    @Binding var action: DishAction?
    @State private var menu = false
    @State private var next: DishAction?  // im Menü gewählt → nach dem Schließen ausführen
    @State private var cooking = false
    @State private var swapping = false
    @State private var replacing = false
    @State private var shareImage = false
    @State private var shareLink = false
    @State private var planning = false
    @State private var guests = false
    @State private var rating = false
    @State private var disliking = false

    func body(content: Content) -> some View {
        content
            .onChange(of: action) { _, a in
                guard let a else { return }
                action = nil
                run(a)
            }
            .sheet(isPresented: $menu, onDismiss: {
                if let n = next { next = nil; run(n) }
            }) {
                if let dish {
                    DishMenu(dish: dish) { a in
                        next = a
                        menu = false
                    }
                }
            }
            .background { if let m = dish?.meal { dialogs(store.current(m)) } }
    }

    private func dialogs(_ m: MealDTO) -> some View {
        Color.clear
            .modifier(RerollDialog(meal: m, isPresented: $swapping, onReplace: { replacing = true }) { direction, wish in
                Task { await store.reroll(m, direction: direction, wish: wish) }
            })
            .modifier(DislikeDialog(meal: m, isPresented: $disliking, roll: m.id == nil || m.locked ? nil : {
                Task { await store.reroll(m) }
            }, store: store))
            .sheet(isPresented: $replacing) { PlanSlotSheet(entry: m).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet) }
            .sheet(isPresented: $shareImage) { ShareCardSheet(meal: m).presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
            .sheet(isPresented: $shareLink) {
                RecipeLinkSheet(recipeId: m.recipe.id, title: m.recipe.title).presentationDetents([.medium, .large])
                    .presentationCornerRadius(Theme.R.sheet)
            }
            .sheet(isPresented: $planning) {
                PlanSlotSheet(recipeId: m.recipe.id, title: m.recipe.title).presentationDetents([.medium, .large])
                    .presentationCornerRadius(Theme.R.sheet)
            }
            .sheet(isPresented: $guests) { GuestsSheet(meal: m).presentationDetents([.height(466), .large]) }
            .sheet(isPresented: $rating) { RatingSheet(meal: m).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet) }
            // Kochen: Rezept mit Kochmodus obendrauf (Bewerten + Reste danach wie gewohnt), funktioniert auch ohne NavigationStack (Swipe)
            .fullScreenCover(isPresented: $cooking) { NavigationStack { RecipeDetailView(meal: m, cook: true) } }
    }

    private func run(_ a: DishAction) {
        guard let dish else { return }
        if let custom = dish.custom[a] { custom(); return }
        if case .extra(let i) = a { if dish.extras.indices.contains(i) { dish.extras[i].run() }; return }
        guard a == .menu || dish.can(a) else { return }
        let m = dish.meal.map { m in store.current(m) }
        switch a {
        case .menu: menu = true
        case .cook: cooking = true
        case .swap: swapping = true
        case .list: if let m { toList(m, dish) }
        case .share: shareImage = true
        case .shareLink: shareLink = true
        case .plan: planning = true
        case .guests: guests = true
        case .lock: if let m { Task { await store.setLocked(m, !m.locked) } }
        case .favorite:
            if let m {
                Task {
                    let on = await store.toggleFavorite(m.recipe.id, current: m.recipe.favorite)
                    store.flash(on ? "Gemerkt" : "Nicht mehr gemerkt")
                }
            }
        case .rate: rating = true
        case .dislike: disliking = true
        case .noMood, .extra: break
        }
    }

    /// Fehlende Zutaten auf die Haushaltsliste: Angebotszutaten als Angebot (Preis, Laden), sonst per Name.
    private func toList(_ m: MealDTO, _ dish: Dish) {
        let missing = store.missingOnList(m)
        guard !missing.isEmpty else {
            if let open = dish.openList { open() } else { store.flash("Alle Zutaten stehen schon auf der Liste") }
            return
        }
        guard let list = store.householdList else { store.flash("Keine Einkaufsliste gefunden"); return }
        Task {
            for i in missing {
                if let o = store.offers.first(where: { o in o.id == i.offerId }) { store.addToList(o) } else { await store.addItem(name: i.name, to: list.id) }
            }
            store.flash(missing.count == 1 ? "1 Zutat auf der Liste" : "\(missing.count) Zutaten auf der Liste",
                        action: dish.openList.map { open in (title: "Ansehen", run: open) })
        }
    }
}

// MARK: Gericht-Menü

/// Sheet (f.html „Gericht-Menü“): Kopf mit Teller, die fünf Knöpfe, darunter Planen und Meinung.
struct DishMenu: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let dish: Dish
    let pick: (DishAction) -> Void
    @State private var height: CGFloat = 520

    var body: some View {
        let m = dish.meal.map { m in store.current(m) }
        let locked = m?.locked ?? false
        let favorite = m?.recipe.favorite ?? false
        let guests = m?.guests ?? 0
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    PlanPlate(url: mediaURL(dish.imageUrl), size: K.menuPlate, mini: true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(dish.title).font(Theme.F.serif(19, relativeTo: .headline)).lineLimit(1)
                        Text(dish.sub).font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                    }
                    Spacer(minLength: 0)
                    CloseButton { dismiss() }
                }
                DishButtons(dish: dish, style: .large, inMenu: true, pick: pick).padding(.top, 16)
                group("Planen") {
                    row(.plan, .cal, "Einplanen")
                    row(.guests, .users, guests > 0 ? "Gäste ändern" : "Gäste dazu", hint: guests > 0 ? "+\(guests)" : nil)
                    row(.lock, .lock, locked ? "Lösen" : "Fixieren", on: locked)
                    row(.noMood, .clock, "Keine Lust?")
                }
                group("Meinung") {
                    row(.favorite, .heart, favorite ? "Gemerkt" : "Merken", on: favorite)
                    row(.rate, .star, "Bewerten")
                    row(.dislike, .x, "Mag ich nicht", hint: "nie mehr vorschlagen", red: true)
                }
                if !dish.extras.isEmpty {
                    group("Rezept") {
                        ForEach(Array(dish.extras.enumerated()), id: \.offset) { i, e in row(.extra(i), e.icon, e.title, red: e.red) }
                    }
                }
            }
            .foregroundStyle(Theme.C.ink)
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 24)
            .onGeometryChange(for: CGFloat.self) { g in g.size.height } action: { h in height = h }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(height + 33), .large])
        .sheet8()
    }

    private func group<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(Theme.F.lbl).tracking(11 * 0.08).foregroundStyle(Theme.C.ink)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { rows() }.padding(.top, 6)
        }
        .padding(.top, 16)
    }

    /// Zeile `.f9-mr`: Icon 21, Titel 15/800, Hinweis rechts; nicht passende Aktionen fallen weg (Einplanen/Mag ich nicht grau).
    @ViewBuilder private func row(_ a: DishAction, _ icon: Icon8, _ title: String, hint: String? = nil, on: Bool = false, red: Bool = false) -> some View {
        let ok = dish.can(a)
        if ok || a == .plan || a == .dislike || a == .favorite || a == .rate {
            Button { pick(a) } label: {
                HStack(spacing: 14) {
                    if on && icon == .heart { FilledIcon(icon: icon, size: K.rowIcon) } else { Icon(icon, size: K.rowIcon) }
                    Text(title).font(Theme.F.text(15, .extrabold, relativeTo: .body))
                    Spacer(minLength: 8)
                    if let h = dish.hints[a] ?? hint {
                        Text(h).font(Theme.F.text(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                    }
                }
                .foregroundStyle(red ? Theme.C.deal : Theme.C.ink)
                .frame(height: K.row)
                .overlay(alignment: .top) { if a != .plan && a != .favorite && !isFirstExtra(a) { Hairline() } }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .disabled(!ok)
            .opacity(ok ? 1 : 0.35)
            .accessibilityAddTraits(on ? .isSelected : [])
        }
    }

    private func isFirstExtra(_ a: DishAction) -> Bool { a == .extra(0) }
}
