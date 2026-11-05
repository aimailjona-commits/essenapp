import SwiftUI

/// Tab „Woche“ (`week: true`, S2 Wochenplan) bzw. „Rezepte“ (S12 Meine Rezepte, `MyRecipesList` in Recipes.swift).
struct RecipesTab: View {
    @Environment(AppStore.self) private var store
    @Binding var planWeek: Bool  // Woche per Swipe (20)
    @State private var mine: Bool
    @State private var filter = "alle"

    init(planWeek: Binding<Bool>, week: Bool = false) {
        _planWeek = planWeek
        _mine = State(initialValue: !week)
    }

    var body: some View {
        Group {
            if mine {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        MyRecipesList(filter: $filter) { withAnimation(Theme.spring) { mine = false } }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.bottom, Theme.S.nav)
                }
            } else {
                WeekPlanView(planWeek: $planWeek)
            }
        }
        .onAppear {  // Start-Karte „Lieblingsrezepte günstig“ → gefilterte Liste
            if let f = store.recipeFilter { mine = true; filter = f; store.recipeFilter = nil }
        }
    }
}

// MARK: Gemeinsame Bausteine Gruppe A (Start, Woche, Planen)

/// Gericht-Teller (`.plate`): Ring in `card` liegt wie CSS-box-shadow außen und nimmt keinen Platz ein; `mini` = `.a-mini` (Ring 3).
struct PlanPlate: View {
    let url: URL?
    var size: CGFloat
    var mini = false

    var body: some View {
        RemoteImage(url: url, contentMode: .fill) {
            Theme.C.blue1.overlay { Ill("pot").padding(size * 0.14) }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .background(Circle().fill(Theme.C.card).padding(mini ? -3 : -Theme.S.plateRing))
        .plateShadow()
        .accessibilityHidden(true)
    }
}

/// `.stat`: Haarlinie (Tinte, `mute` = ink3), Label 12/700 links oben, Wert rechts.
struct PlanStat<Value: View>: View {
    let label: String
    var mute = false
    var icon: Icon8?
    @ViewBuilder var value: Value

    var body: some View {
        let color = mute ? Theme.C.ink3 : Theme.C.ink
        VStack(spacing: 6) {
            Hairline(color: color)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if let icon { Icon(icon, size: 22) }
                    Text(label).font(Theme.F.text(12, .bold, relativeTo: .caption))
                }
                .foregroundStyle(color)
                Spacer(minLength: 8)
                value.foregroundStyle(color)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Knopf für kurze Aktionen (Mockup-Animation `button`): wartet blau mit drei hüpfenden Zutaten (`Hop3`).
struct PlanBusyButton: View {
    let title: String
    var icon: Icon8?
    var busy = false
    var disabled = false
    var small = false  // 38 hoch, 14/800 (S27 „Das koche ich heute“)
    var blue = false
    var busyTitle: String?  // Text neben der Lade-Animation, sonst nur Animation
    let action: () -> Void

    var body: some View {
        let light = busy || blue
        Button(action: action) {
            ZStack {
                if busy, let busyTitle {
                    HStack(spacing: 4) { Hop3().scaleEffect(0.6).frame(width: 70); Text(busyTitle).lineLimit(1) }.transition(.opacity)
                } else if busy {
                    Hop3().scaleEffect(small ? 0.8 : 1).transition(.opacity)
                } else {
                    HStack(spacing: 8) {
                        if let icon { Icon(icon, size: 20) }
                        Text(title).lineLimit(1)
                    }
                    .transition(.opacity)
                }
            }
            .font(small ? Theme.F.text(14, .extrabold, relativeTo: .subheadline) : Theme.F.button)
            .foregroundStyle(light ? Theme.C.ink : Theme.C.onInk)
            .padding(.horizontal, small ? 14 : 22)
            .frame(maxWidth: .infinity, minHeight: small ? 38 : Theme.S.button)
            .background(light ? Theme.C.blue : Theme.C.ink, in: Capsule())
            .opacity(disabled && !busy ? 0.35 : 1)
            .padding(.vertical, small ? 3 : 0)
            .contentShape(Capsule())
            .animation(.easeInOut(duration: 0.25), value: busy)
        }
        .buttonStyle(PressableStyle())
        .disabled(disabled || busy)
        .accessibilityLabel(busy ? "\(title), lädt" : title)
    }
}

/// Kreis mit Icon in Tinte (`.circle`), z. B. Abspielen 50/56, „+“ 44, Pfeil 72.
struct PlanInkCircle: View {
    let icon: Icon8
    var size: CGFloat
    var iconSize: CGFloat = 24

    var body: some View {
        Icon(icon, size: iconSize).foregroundStyle(Theme.C.onInk)
            .frame(width: size, height: size)
            .background(Theme.C.ink, in: Circle())
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Circle())
    }
}

/// Bewegung beim Tauschen von Tellern (`a1-day`, `a1-dice`): Versatz, Drehung, Deckkraft.
struct PlanFly: ViewModifier {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var deg: Double = 0
    var opacity: Double = 1

    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(deg)).offset(x: x, y: y).opacity(opacity)
    }
}

/// Kalenderwoche „2026-W45“ → Tage und Texte („KW 45“, „3.–9. Nov“, „4. Nov“).
enum PlanWeek {
    @MainActor static func current(_ store: AppStore) -> String {
        if let w = store.plan?.week { return w }
        let cal = Calendar(identifier: .iso8601)
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 2026, c.weekOfYear ?? 1)
    }

    static func kw(_ week: String) -> String { String(Int(week.suffix(2)) ?? 0) }

    static func date(_ week: String, _ day: Int) -> Date? {
        let p = week.split(separator: "-W").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        guard let monday = cal.date(from: DateComponents(weekday: 2, weekOfYear: p[1], yearForWeekOfYear: p[0])) else { return nil }
        return cal.date(byAdding: .day, value: day, to: monday)
    }

    private static func month(_ d: Date, wide: Bool) -> String {
        d.formatted(.dateTime.month(wide ? .wide : .abbreviated).locale(.de)).replacingOccurrences(of: ".", with: "")
    }

    private static func dayNum(_ d: Date) -> Int { Calendar.current.component(.day, from: d) }

    /// „4. Nov“
    static func dayDate(_ week: String, _ day: Int) -> String {
        guard let d = date(week, day) else { return "" }
        return "\(dayNum(d)). \(month(d, wide: false))"
    }

    /// „3.–9. Nov“ bzw. „27. Okt – 2. Nov“ (`wide`: „3.–9. November“)
    static func range(_ week: String, wide: Bool = false) -> String {
        guard let a = date(week, 0), let b = date(week, 6) else { return "" }
        let ma = month(a, wide: wide), mb = month(b, wide: wide)
        return ma == mb ? "\(dayNum(a)).–\(dayNum(b)). \(mb)" : "\(dayNum(a)). \(ma) – \(dayNum(b)). \(mb)"
    }

    /// Hauptgericht eines Tages (wie `AppStore.todayMeal`: Mittag vor Abend).
    static func main(_ plan: PlanDTO, _ day: Int) -> MealDTO? {
        let meals = plan.entries.filter { $0.day == day }
        return meals.first { $0.mealType == "mittag" } ?? meals.first { $0.mealType == "abend" } ?? meals.first
    }

    static func sorted(_ plan: PlanDTO?, _ day: Int) -> [MealDTO] {
        (plan?.entries ?? []).filter { $0.day == day }
            .sorted { a, b in (Labels.slotOrder.firstIndex(of: a.mealType) ?? 9) < (Labels.slotOrder.firstIndex(of: b.mealType) ?? 9) }
    }

    static func perPortion(_ m: MealDTO) -> Int { m.costCents / max(Int(m.basePortions), 1) }
    static func deals(_ m: MealDTO) -> Int { m.recipe.ingredients.filter { $0.offerId != nil }.count }
}

// MARK: S2 Wochenplan

/// S2 Wochenplan (v9 b.html, Variante A „Rad“, `WeekWheel`): Kopf, Tage zum Wischen, unten „Diese Woche“.
/// Nach Sonntag (ohne Mockup, Funktion bleibt): Budget, Reste, Wochenschnitt, neu planen, teilen.
private struct WeekPlanView: View {
    @Environment(AppStore.self) private var store
    @Binding var planWeek: Bool
    @State private var day = Demo.screen != nil ? 1 : (Calendar(identifier: .iso8601).component(.weekday, from: .now) + 5) % 7
    @State private var detail = Demo.screen == "dayDetail"
    @State private var guestsFor: MealDTO? = Demo.screen == "guests" ? Demo.plan.entries[3] : nil  // „Gäste hinzufügen“ (15)

    var body: some View {
        Group {
            if let plan = store.plan {
                VStack(alignment: .leading, spacing: 0) {
                    header(plan).frame(height: 150, alignment: .top)  // Mockup: Wisch-Fläche ab 150
                    WeekWheel(plan: plan, today: store.today, openDay: { d in day = d; detail = true }) {
                        more(plan).padding(.horizontal, Theme.pagePadding)
                    }
                    .refreshable { await store.loadAll() }
                    PlanStat(label: "Diese Woche") { BigNumber(euro(plan.totalCents), size: 30) }
                        .padding(.horizontal, Theme.pagePadding).padding(.top, 6)
                }
                .padding(.bottom, Theme.S.nav)
                .ignoresSafeArea(edges: .vertical)
            } else {
                ScrollView { PlanEmptyHero { planWeek = true } }
                    .ignoresSafeArea(edges: .top)
                    .refreshable { await store.loadAll() }
            }
        }
        .navigationDestination(isPresented: $detail) { DayDetailView(day: day) }
        .sheet(item: $guestsFor) { m in GuestsSheet(meal: m).presentationDetents([.height(466), .large]) }
    }

    private func header(_ plan: PlanDTO) -> some View {
        let filled = (0..<7).filter { d in plan.entries.contains { $0.day == d } }.count
        return HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text("KW \(PlanWeek.kw(plan.week)) · \(PlanWeek.range(plan.week))").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                Text("Deine Woche").font(Theme.F.t1)
            }
            Spacer()
            (Text("\(filled)") + Text("/7").foregroundStyle(Theme.C.ink3))
                .font(Theme.F.num(30)).tracking(Theme.F.numTracking(30))
                .accessibilityLabel("\(filled) von 7 Tagen geplant")
        }
        .padding(.horizontal, Theme.pagePadding).padding(.top, 66)
    }

    // Nach Sonntag: was die alte Woche zusätzlich zeigte („Diese Woche“ steht fest unten)
    private func more(_ plan: PlanDTO) -> some View {
        let budget = store.household?.budgetFoodWeekCents ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            if budget > 0 {
                HStack(spacing: 10) {
                    ProgressBar8(value: Double(plan.totalCents) / Double(budget), color: plan.totalCents > budget ? Theme.C.deal : Theme.C.ink)
                    Text("\(euro(plan.totalCents)) von \(euro(budget))").font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                }
            }
            if plan.savedCents > 0 {
                PlanStat(label: "Gespart", mute: true) { BigNumber(euro(plan.savedCents), size: 30).foregroundStyle(Theme.C.deal) }
                    .padding(.top, 12)
            }
            if let l = plan.leftovers, l.planned > 0 || !l.left.isEmpty { LeftoversCard(leftovers: l).padding(.top, 28) }  // Reste (19)
            weekAverage.padding(.top, 20)
            VStack(spacing: 10) {
                OutlineButton(title: "Woche neu planen", icon: .dice) { planWeek = true }
                ShareLink(item: store.shareText) {
                    HStack(spacing: 8) { Icon(.share, size: 20); Text("Plan und Liste teilen") }
                        .font(Theme.F.button2).foregroundStyle(Theme.C.ink)
                        .frame(maxWidth: .infinity, minHeight: Theme.S.button2)
                        .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
                }
            }
            .padding(.top, 28)
        }
    }

    /// Wochenschnitt pro Person (2).
    @ViewBuilder private var weekAverage: some View {
        if let n = store.nutrition, !n.members.isEmpty {
            VStack(spacing: 0) {
                ForEach(n.members) { m in
                    IRow(name: m.name, sub: "Ø \(Int(m.avgKcal.rounded())) / \(m.kcalGoal) kcal · \(Int(m.avgProtein.rounded())) / \(m.proteinGoal) g Protein pro Tag") {
                        Text(String(m.name.prefix(1))).font(Theme.F.serif(20))
                    }
                }
            }
            .animation(Theme.spring, value: n.members)
        }
    }
}

// MARK: S2 Tag im Detail

/// S2 Tag im Detail: je Mahlzeit Teller, Name, eine Zeile (Preis · Rest/Gäste) und 2×2 Aktionen; Tageswerte mit Ringen.
private struct DayDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let day: Int
    @State private var person: Int?  // „Für:“ (48), nil = ich
    @State private var noMood = false
    @State private var guestsFor: MealDTO?

    var body: some View {
        let meals = PlanWeek.sorted(store.plan, day)
        let week = PlanWeek.current(store)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button { dismiss() } label: { Icon(.back).frame(width: 44, height: 44, alignment: .leading).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Zurück")
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("KW \(PlanWeek.kw(week)) · \(PlanWeek.dayDate(week, day))").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                        Text(Labels.dayNames[day]).font(Theme.F.t1)
                    }
                    Spacer()
                    if let v = store.plan?.variety { VarietyChip(check: v).padding(.bottom, 4) }  // Abwechslung (12)
                }
                if meals.isEmpty {
                    Text("Für \(Labels.dayNames[day]) ist nichts geplant.").font(Theme.F.small).foregroundStyle(Theme.C.ink2).padding(.top, 30)
                }
                ForEach(Array(meals.enumerated()), id: \.offset) { i, m in
                    DayMealRow(meal: m) { guestsFor = m }.padding(.top, i == 0 ? 30 : 28)
                }
                DayValues(day: day, person: $person).padding(.top, 36)
                if day == store.today && !meals.isEmpty {
                    OutlineButton(title: "Keine Lust?") { noMood = true }.padding(.top, 28)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 2)
            .padding(.bottom, Theme.S.nav)
            .edgeForm(.circle, Theme.C.blue1, width: 220, height: 220, left: -110, top: 98)  // Mockup top 150 − Statusleiste 52
        }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $noMood) { NoMoodSheet().presentationDetents([.large]) }
        .sheet(item: $guestsFor) { m in GuestsSheet(meal: m).presentationDetents([.height(466), .large]) }
    }
}

/// Eine Mahlzeit im Tag: Teller fliegt beim Würfeln weg, drei Zutaten hüpfen, neues Gericht federt herein (`a1-dice`).
private struct DayMealRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let meal: MealDTO
    let guests: () -> Void
    @State private var rolling = false
    @State private var choosing = false  // Würfel → Richtung wählen (19.3)
    @State private var replacing = false  // „ersetzen durch eigenes Rezept“ → S19

    private var meta: String {
        guard meal.mealType == "lunchbox" else { return Labels.meal(meal.mealType) }
        let names = store.profiles.filter { p in meal.portions.contains { $0.memberId == p.memberId } }.map(\.name)
        return names.isEmpty ? "Lunchbox" : "Lunchbox · \(names.joined(separator: ", "))"
    }

    private var sub: String {
        var parts = [euro(PlanWeek.perPortion(meal))]
        let rests = (meal.rests ?? []).map(\.fromDay).filter { Labels.days.indices.contains($0) }.uniqued()
        parts += rests.map { "Rest von \(Labels.days[$0])" }
        if let g = meal.guests, g > 0 { parts.append("+\(g) \(g == 1 ? "Gast" : "Gäste")") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(meta.uppercased()).font(Theme.F.lbl).tracking(11 * 0.08).foregroundStyle(Theme.C.ink)
            HStack(spacing: 12) {
                NavigationLink { RecipeDetailView(meal: meal) } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            if rolling {
                                Hop3().scaleEffect(0.9).transition(.opacity)
                            } else {
                                PlanPlate(url: mediaURL(meal.recipe.imageUrl), size: 64).id(meal.recipe.id).transition(diceTransition)
                            }
                        }
                        .frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.recipe.title).font(Theme.F.serif(17, relativeTo: .headline)).lineLimit(1)
                                .foregroundStyle(Theme.C.ink).contentTransition(.opacity)
                            Text(sub).font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                                .lineLimit(1).contentTransition(.numericText())
                        }
                        .opacity(rolling ? 0 : 1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if meal.id != nil { actions }
            }
        }
        .contextMenu {
            if meal.id != nil {
                Button((meal.guests ?? 0) > 0 ? "Gäste ändern" : "Gäste hinzufügen", systemImage: "person.2", action: guests)
            }
        }
        .accessibilityAction(named: "Gäste hinzufügen", guests)
        .modifier(RerollDialog(meal: meal, isPresented: $choosing) { roll(direction: $0, wish: $1) })
        .sheet(isPresented: $replacing) { PlanSlotSheet(entry: meal).presentationDetents([.medium, .large]) }
    }

    private var diceTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: PlanFly(x: -120, deg: -240), identity: PlanFly())
                .animation(.spring(response: 0.55, dampingFraction: 0.62)),
            removal: .modifier(active: PlanFly(x: -130, deg: -120, opacity: 0), identity: PlanFly())
                .animation(.timingCurve(0.5, 0, 0.9, 0.5, duration: 0.35)))
    }

    /// 2×2 Aktionen (`.a-acts`): Kreise 34, Tap-Fläche 44.
    private var actions: some View {
        Grid(horizontalSpacing: -4, verticalSpacing: -4) {
            GridRow {
                act(.heart, on: meal.recipe.favorite, meal.recipe.favorite ? "Aus Favoriten entfernen" : "Als Favorit merken") {
                    Task { _ = await store.toggleFavorite(meal.recipe.id, current: meal.recipe.favorite) }
                }
                act(.swap, on: false, "Durch eigenes Rezept ersetzen") { replacing = true }
            }
            GridRow {
                act(.lock, on: meal.locked, meal.locked ? "Lösen" : "Fixieren") { Task { await store.setLocked(meal, !meal.locked) } }
                act(.dice, on: rolling, "Neu würfeln") { if !meal.locked, !rolling { choosing = true } }
                    .opacity(meal.locked ? 0.35 : 1)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: meal.locked)
    }

    private func act(_ icon: Icon8, on: Bool, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: 17).foregroundStyle(on ? Theme.C.onInk : Theme.C.ink)
                .frame(width: 34, height: 34)
                .background(on ? Theme.C.ink : .clear, in: Circle())
                .overlay { if !on { Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func roll(direction: String?, wish: String) {
        guard !meal.locked, !rolling else { return }
        withAnimation(.easeIn(duration: 0.35)) { rolling = true }
        Task {
            await store.reroll(meal, direction: direction, wish: wish)
            withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) { rolling = false }
        }
    }
}

/// Tageswerte (S2 Tag): Ringe je Person (gewählte groß, kcal außen Tinte, Protein innen blue3), zwei Zahlen gegen das Ziel.
private struct DayValues: View {
    @Environment(AppStore.self) private var store
    let day: Int
    @Binding var person: Int?

    var body: some View {
        if let n = store.nutrition, let d = n.days.first(where: { $0.day == day }), let first = n.members.first {
            let id = person ?? store.profile?.memberId ?? first.memberId
            let sel = n.members.first { $0.memberId == id } ?? first
            let v = d.members.first { $0.memberId == sel.memberId }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SectionLabel("Tageswerte")
                    Spacer()
                    Menu {
                        ForEach(n.members) { m in Button(m.name) { withAnimation(Theme.spring) { person = m.memberId } } }
                    } label: {
                        Text("Für: \(sel.name) ▾").font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink)
                            .frame(minHeight: 44)
                    }
                    .accessibilityLabel("Für \(sel.name), ändern")
                }
                HStack(alignment: .top, spacing: 22) {
                    HStack(alignment: .bottom, spacing: 10) {
                        ring(sel, d, big: true)
                        ForEach(n.members.filter { $0.memberId != sel.memberId }) { m in ring(m, d, big: false) }
                    }
                    .fixedSize()
                    VStack(spacing: 12) {
                        PlanStat(label: "kcal") { pair(v?.kcal ?? 0, " /\(sel.kcalGoal)") }
                        PlanStat(label: "Protein") { pair(v?.protein ?? 0, " /\(sel.proteinGoal) g") }
                    }
                }
                .padding(.top, 14)
                Text("KH \(Int((v?.carbs ?? 0).rounded())) g · Fett \(Int((v?.fat ?? 0).rounded())) g")
                    .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2).padding(.top, 12)
            }
            .animation(Theme.spring, value: sel.memberId)
            .sensoryFeedback(.selection, trigger: person)
        } else if store.nutrition == nil && store.plan != nil {
            Skeleton8(height: 120)
        }
    }

    private func pair(_ value: Double, _ goal: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            BigNumber("\(Int(value.rounded()))", size: 30)
            Text(goal).font(Theme.F.num(17)).tracking(Theme.F.numTracking(17)).foregroundStyle(Theme.C.ink3)
        }
    }

    /// Ring wie im Mockup-SVG (viewBox 88): außen r 36, innen r 26 (klein 25).
    private func ring(_ m: PlanNutritionDTO.Member, _ d: PlanNutritionDTO.Day, big: Bool) -> some View {
        let v = d.members.first { $0.memberId == m.memberId }
        let k = (v?.kcal ?? 0) / Double(max(m.kcalGoal, 1)), p = (v?.protein ?? 0) / Double(max(m.proteinGoal, 1))
        let size: CGFloat = big ? 76 : 50, lw: CGFloat = big ? 7 : 8, inner: CGFloat = big ? 18 : 19
        return Button { withAnimation(Theme.spring) { person = m.memberId } } label: {
            VStack(spacing: 4) {
                ZStack {
                    if big { Circle().fill(Theme.C.blue1) }
                    arc(1, Theme.C.line, 8, lw)
                    arc(k, Theme.C.ink, 8, lw)
                    arc(1, Theme.C.line, inner, lw)
                    arc(p, Theme.C.blue3, inner, lw)
                    Text(String(m.name.prefix(1))).font(Theme.F.serif(big ? 20 : 26))
                }
                .frame(width: 88, height: 88)
                .scaleEffect(size / 88)
                .frame(width: size, height: size)
                Text(m.name).font(Theme.F.text(12, .extrabold, relativeTo: .caption)).foregroundStyle(big ? Theme.C.ink : Theme.C.ink2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(m.name): \(Int((v?.kcal ?? 0).rounded())) von \(m.kcalGoal) kcal")
    }

    private func arc(_ f: Double, _ color: Color, _ inset: CGFloat, _ lw: CGFloat) -> some View {
        Circle().inset(by: inset).trim(from: 0, to: min(max(f, 0), 1))
            .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
}

/// Gericht als Zeile (Suche auf Start): Teller 48, Name, Zeit · Preis.
struct MealRow: View {
    let meal: MealDTO

    var body: some View {
        IRow(name: meal.recipe.title, sub: "\(meal.recipe.prepMinutes) min · \(euro(meal.costCents))", tint: .clear) {
            PlanPlate(url: mediaURL(meal.recipe.imageUrl), size: 44, mini: true)
        } trail: {
            Icon(.chev, size: 18).foregroundStyle(Theme.C.ink3)
        }
        .foregroundStyle(Theme.C.ink)
    }
}

/// S3 Rezeptdetail – Plan-Gericht oder gespeichertes Rezept (`meal.id == nil`, siehe `SavedRecipeView`).
/// v8 (b.html S3 Teil 1–3 + importiert, Kopf wie a1-fav): Bogen + Teller, große Zahlen, Zutaten-Zeilen;
/// „Für“, Nährwerte, Blüte; Portionen, Schritte, Bewertungen. Unten fest: Kochmodus bzw. Kochen + Bewerten.
struct RecipeDetailView: View {
    static let reportKinds = [("zutat_fehlt", "Zutat fehlt"), ("menge_falsch", "Menge falsch"), ("angebot_falsch", "Falsches Angebot"),
                              ("schritt_unklar", "Schritt unklar"), ("sonstiges", "Etwas anderes")]
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let given: MealDTO
    @State private var swapped: MealDTO?  // gespeichertes Rezept nach „Ersatz finden“ (7)
    @State private var substituting: Int?  // Index der Zutat für „Ersatz finden“
    @State private var alarmFor: String?  // Zutat für „Preisalarm“ (40)
    @State private var showRating = false
    @State private var openOffer: OfferDTO?
    @State private var searchIngredient: IngredientDTO?
    @State private var servings: Int?
    @State private var person: Int?  // Mitglied für „Deine Portion“ (48), nil = ich
    @State private var done: Set<Int> = []
    @State private var cooking = ["cooking", "cookprep", "cookvoice", "cookdone"].contains(Demo.screen ?? "")
    @State private var rateAfterCooking = false
    @State private var shareCard = Demo.screen == "sharecard"
    @State private var shareLink = false  // „Als Link teilen“ (56)
    @State private var reportKind: String?  // „Fehler melden“ (19.9): gewählte Art, dann Notiz
    @State private var reportNote = ""
    @State private var reporting = false
    @State private var info: RecipeDTO?  // GET /recipes/{id}: Bewertungen, Favorit, Nährwerte, falls im Plan noch null
    @State private var favorite: Bool?
    @State private var planIt = false
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var stepImages: [String]?  // nachgeladene Schritt-Bilder (9)
    @State private var imagesSettled = false  // Erzeugung fertig oder aus → leere Plätze ausblenden
    @State private var replacingDish = false  // „Ersatz“: Gericht im Plan ersetzen (S19)
    @State private var choosing = false  // „Würfeln“ im Plan-Gericht (19.3), wie auf der Tageskarte
    @State private var disliking = false  // „Mag ich nicht“ mit Grund
    @State private var rolling = false
    @State private var compact = false  // Titel aus dem Bild → Kopf wie Teil 2/3 (Name in der Mitte, Grund `bg`)
    @State private var deep = false  // Zutaten durchgescrollt → untere Leiste aus Teil 2/3 (Kochen + Bewerten)
    @State private var titleHeight: CGFloat = 0  // gemessen: langer Titel schiebt den Teller nach unten
    @Environment(\.openURL) private var openURL

    init(meal: MealDTO) { given = meal }

    /// Plan-Gericht immer im aktuellen Stand des Plans (Ersatz, Gäste, Würfeln ändern es).
    private var meal: MealDTO { swapped ?? given.id.flatMap { id in store.plan?.entries.first { e in e.id == id } } ?? given }
    private var recipe: RecipeDTO { meal.recipe }
    private var images: [String] { stepImages ?? info?.stepImages ?? recipe.stepImages ?? [] }
    /// Bildfläche für Schritt i: Bild da, oder es wird noch erzeugt (Schimmer).
    private func showsImage(_ i: Int) -> Bool {
        i < images.count && (!images[i].isEmpty || (store.stepImagesOn && !imagesSettled))
    }
    private var details: RecipeDTO { info ?? recipe }
    private var nutrition: NutritionDTO? { recipe.nutrition ?? info?.nutrition }
    private var isFavorite: Bool { favorite ?? details.favorite }
    /// Importiert (Instagram, Web) oder aus einem anderen Haushalt übernommen → Variante „Importiertes Rezept“.
    private var imported: Bool { ["instagram", "web", "shared"].contains(recipe.source) }

    var body: some View {
        let base = meal.basePortions  // Rezeptmengen gelten für so viele Portionen
        let factor = (servings.map { Double($0) / base } ?? 1) * meal.scale  // Stepper skaliert das ganze Rezept; scale = eingesetztes Rezept
        let who = store.profiles.first { $0.memberId == (person ?? store.profile?.memberId) } ?? store.profile
        // Anteil der gewählten Person; ohne Esser-Liste (gespeichertes Rezept, alter Plan) der Portionsfaktor aus dem Profil
        let mine: Double? = meal.portions.isEmpty ? (who?.portionFactor ?? 1) : meal.portions.first { $0.memberId == who?.memberId }?.factor
        ScrollView {
            page(factor: factor, who: who, mine: mine, base: base)
        }
        .background(Theme.C.bg.ignoresSafeArea())
        .overlay(alignment: .top) { header }
        .overlay(alignment: .bottom) { bottomBar }
        .modifier(RerollDialog(meal: meal, isPresented: $choosing, onReplace: { replacingDish = true }, roll: reroll))
        .modifier(DislikeDialog(meal: meal, isPresented: $disliking, roll: meal.id == nil || meal.locked ? nil : { reroll(nil, "") },
                                  store: store))
        .onChange(of: recipe.id) {  // gewürfelt oder ersetzt: Daten des alten Rezepts verwerfen
            info = nil; favorite = nil; stepImages = nil; imagesSettled = false
        }
        .confirmationDialog("Was stimmt nicht?", isPresented: $reporting, titleVisibility: .visible) {
            ForEach(Self.reportKinds, id: \.0) { kind, label in Button(label) { reportKind = kind } }
        }
        .alert("Fehler melden", isPresented: Binding(get: { reportKind != nil }, set: { if !$0 { reportKind = nil } })) {
            TextField("Was genau? (optional)", text: $reportNote)
            Button("Senden") {
                let kind = reportKind ?? "sonstiges", note = reportNote
                reportNote = ""
                Task { await store.report(recipe.id, kind: kind, note: note) }
            }
            Button("Abbrechen", role: .cancel) { reportNote = "" }
        }
        .hidesTabBar()
        .sheet(isPresented: $replacingDish) {
            PlanSlotSheet(entry: meal).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: "\(store.recipesVersion)-\(recipe.id)") { await loadInfo() }
        .task(id: recipe.id) { await pollStepImages() }
        .fullScreenCover(isPresented: $cooking, onDismiss: {
            if rateAfterCooking { rateAfterCooking = false; showRating = true }  // Abschluss → Bewertung + Vorrat (S8)
        }) {
            CookingView(meal: cookMeal, imagesLoading: store.stepImagesOn && !imagesSettled, factor: factor,
                        person: who.flatMap { w in mine.map { m in (w.emoji, m * meal.scale / base) } },
                        onFinish: {
                            rateAfterCooking = true
                            cooking = false
                        },
                        onSubstitute: { m in if let m { swapped = m } })
        }
        .sheet(isPresented: $shareCard) { ShareCardSheet(meal: meal).presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
        .sheet(isPresented: $shareLink) {
            RecipeLinkSheet(recipeId: recipe.id, title: recipe.title).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet)
        }
        .sheet(isPresented: $showRating) { RatingSheet(meal: meal).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet) }
        .sheet(isPresented: $planIt) { PlanSlotSheet(recipeId: recipe.id, title: recipe.title).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet) }
        .sheet(isPresented: $editing) { RecipeFormSheet(editing: details).presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
        .confirmationDialog("Rezept löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                let id = recipe.id
                dismiss()
                Task { await store.deleteRecipe(id) }
            }
        } message: {
            Text("„\(recipe.title)“ verschwindet aus Meine Rezepte. Steht es im Wochenplan, bleibt es dort.")
        }
        .navigationDestination(item: $openOffer) { OfferDetailView(offer: $0) }
        .sheet(isPresented: Binding(get: { alarmFor != nil }, set: { on in if !on { alarmFor = nil } })) {
            WatchSheet(ingredient: alarmFor ?? "").presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet)
        }
        .sheet(item: $searchIngredient) { IngredientOffersSheet(ingredient: $0).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet) }
        .sheet(isPresented: Binding(get: { substituting != nil }, set: { on in if !on { substituting = nil } })) {
            if let i = substituting {
                SubstituteSheet(meal: meal, index: i) { m in if let m { swapped = m } }
                    .presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet)
            }
        }
    }

    private func reroll(_ direction: String?, _ wish: String) {
        rolling = true
        Task {
            await store.reroll(meal, direction: direction, wish: wish)
            rolling = false
        }
    }

    /// Plan-Gerichte holen Bewertungen/Favorit nach; fehlen Nährwerte (Berechnung läuft), einmal nach ~3 s neu laden.
    private func loadInfo() async {
        if recipe.ratings == nil { info = (try? await store.recipe(recipe.id)) ?? info }
        guard nutrition == nil else { return }
        try? await Task.sleep(for: .seconds(3))
        if let again = try? await store.recipe(recipe.id) { withAnimation(Theme.spring) { info = again } }
    }

    /// Schritt-Bilder: anfordern (startet die Erzeugung) und mit wachsendem Abstand nachfragen, solange sie entstehen.
    private func pollStepImages() async {
        guard !store.demo else { return }  // Demo: leere Plätze schimmern weiter
        guard store.stepImagesOn, !recipe.steps.isEmpty else { imagesSettled = true; return }
        var wait = 2.0
        while !Task.isCancelled {
            if images.count == recipe.steps.count && !images.contains("") { break }
            guard let out = try? await store.stepImages(recipe.id) else { break }  // 422: aus oder nicht eingerichtet
            withAnimation(Theme.spring) { stepImages = out.stepImages }
            guard out.pending, out.stepImages.contains("") else { break }
            try? await Task.sleep(for: .seconds(wait))
            wait = min(wait * 2, 30)
        }
        imagesSettled = true
    }

    /// Kochmodus bekommt die nachgeladenen Schritt-Bilder.
    private var cookMeal: MealDTO {
        var m = meal
        m.recipe.stepImages = images
        return m
    }

    /// Animation steckt in `PlateHeart` (a1-fav), darum ohne eigenes `withAnimation`.
    private func toggleFavorite() {
        let new = !isFavorite
        favorite = new
        Task { favorite = await store.toggleFavorite(recipe.id, current: !new) }
    }
}

/// Mockup-Maße S3 (px = pt). y ab Safe-Area-Oberkante = Mockup-y − 52 (Statusleiste).
private enum S3Layout {
    static let headTop: CGFloat = 4  // Kopf-Icons mittig auf 66 + 12 − 52, Tap-Fläche 44
    static let compactAt: CGFloat = headTop + 44  // Titel unter dem Kopf verschwunden → kompakter Kopf
    static let iconGap: CGFloat = 18  // a1-fav: Herz, Punkte, Teilen
    static let titleTop: CGFloat = 54  // .t1 margin-top 16 unter der 24er-Kopfzeile: 66 + 24 + 16 − 52
    static let titleSize: CGFloat = 38
    static let blobLeft: CGFloat = -60, blobTop: CGFloat = -80 - 52, blobSize: CGFloat = 430
    static let plateRight: CGFloat = -50, plateTop: CGFloat = 200 - 52, plateSize: CGFloat = 230, plateGap: CGFloat = 8
    static let importedPlateRight: CGFloat = -40, importedPlateTop: CGFloat = 246 - 52, importedPlateSize: CGFloat = 166
    static let statsTop: CGFloat = 30, statsWidth: CGFloat = 140, statSize: CGFloat = 34, statGap: CGFloat = 10
    // Quelle-Zeile: Chip 32 hoch, Pille mit 44er-Tap-Fläche → je 6 oben/unten mehr, darum Abstände um 6 kleiner
    static let sourceTop: CGFloat = 14 - 6, importedStatsTop: CGFloat = 32 - 6
    static let importedStatsWidth: CGFloat = 150, importedStatSize: CGFloat = 44, sourceChip: CGFloat = 32
    static let ingredientsTop: CGFloat = 34, importedIngredientsTop: CGFloat = 68
    static let deepAt: CGFloat = 420  // Zutaten-Ende höher als das → untere Leiste aus Teil 2/3
    static let sectionTop: CGFloat = 40  // Teil 1 → Teil 2 (im Mockup getrennte Bildschirme)
    static let portionsTop: CGFloat = 28, stepsTop: CGFloat = 32, stepsBottom: CGFloat = 8
    static let stepNum: CGFloat = 22, stepNumWidth: CGFloat = 34, stepText: CGFloat = 15, stepLine: CGFloat = 15 * 0.45 - 3
    static let ratingsTop: CGFloat = 32, ratingsListTop: CGFloat = 10, ratingNum: CGFloat = 34, star: CGFloat = 14
    static let fixBottom: CGFloat = 30, cookCircle: CGFloat = 64, cookIcon: CGFloat = 22, fixCircle: CGFloat = 56, fixGap: CGFloat = 10
    // Mockup 160 bzw. 120; 200, damit der volle `bg`-Teil (ab 45 %) über die Oberkante der Leiste (30 + 64) reicht
    static let fade: CGFloat = 200

    static var head: Font { Theme.F.text(16, .extrabold, relativeTo: .headline) }  // font-weight 800 (16)
    static var small13: Font { Theme.F.text(13, .semibold, relativeTo: .footnote) }
    static var amount: Font { Theme.F.text(16, .bold, relativeTo: .body) }  // <b>
    /// Kreisfarben der Zutaten ohne eigene Zeichnung, Reihenfolge wie im Mockup.
    static var tints: [Color] { [Theme.C.rose, Theme.C.sage, Theme.C.blue1, Theme.C.sand] }
}

extension RecipeDetailView {
    // MARK: Seite

    fileprivate func page(factor: Double, who: ProfileDTO?, mine: Double?, base: Double) -> some View {
        let cents = Int(Double(meal.costCents) * (who == nil ? 1 : mine ?? 1) / base)
        let kcal = nutrition.map { n in Int((n.kcal * (mine ?? 1)).rounded()) }
        let plateTop = imported ? S3Layout.importedPlateTop : S3Layout.plateTop
        // Titel reicht bis unter den Teller → Teller (und Zutaten) um so viel tiefer, nie Text unter dem Bild
        let shift = max(0, S3Layout.titleTop + titleHeight + S3Layout.plateGap - plateTop)
        return VStack(alignment: .leading, spacing: 0) {
            // Teil 1: Titel, Zahlen, Zutaten (Gruppen nur gegen die ViewBuilder-Grenze)
            Group {
                Text(recipe.title)
                    .font(Theme.F.serif(S3Layout.titleSize, relativeTo: .largeTitle))
                    .lineLimit(3).minimumScaleFactor(0.7)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { titleHeight = $0 }
                    .padding(.top, S3Layout.titleTop)
                    .accessibilityAddTraits(.isHeader)
                    .onGeometryChange(for: Bool.self) { p in p.frame(in: .scrollView).maxY < S3Layout.compactAt } action: { v in
                        withAnimation(.easeOut(duration: 0.2)) { compact = v }
                    }
                if imported {
                    sourceRow.padding(.top, S3Layout.sourceTop)
                    importedStat(cents: cents, kcal: kcal).padding(.top, S3Layout.importedStatsTop)
                } else {
                    stats(cents: cents, kcal: kcal).padding(.top, S3Layout.statsTop)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("Zutaten").font(S3Layout.head)
                    Spacer()
                    Text("für \(num(servings.map { Double($0) } ?? base, 0...2)) · \(recipe.ingredients.count) Stück")
                        .font(S3Layout.small13).foregroundStyle(Theme.C.ink2).contentTransition(.numericText())
                }
                .padding(.top, (imported ? S3Layout.importedIngredientsTop : S3Layout.ingredientsTop) + shift)
                .padding(.bottom, 6)
                ingredients(factor: factor, who: who, mine: mine, base: base)
                Color.clear.frame(height: 0)
                    .onGeometryChange(for: Bool.self) { p in p.frame(in: .scrollView).minY < S3Layout.deepAt } action: { v in
                        withAnimation(Theme.spring) { deep = v }
                    }
            }

            // Teil 2: Nährwerte im Vergleich (v9 a.html Variante C, Personen-Umschalter in der Karte)
            NutritionColumns(nutrition: nutrition, who: who, mine: mine, person: $person).padding(.top, S3Layout.sectionTop)

            // Teil 3: Portionen, Zubereitung, Bewertungen
            Group {
                portionsRow(base: base).padding(.top, S3Layout.portionsTop)
                Text("Zubereitung").font(S3Layout.head).padding(.top, S3Layout.stepsTop).padding(.bottom, S3Layout.stepsBottom)
                    .accessibilityAddTraits(.isHeader)
                if !recipe.description.isEmpty {
                    Text(recipe.description).font(S3Layout.small13).foregroundStyle(Theme.C.ink2).padding(.bottom, 12)
                }
                steps
                if let ratings = details.ratings, !ratings.isEmpty { ratingsSection(ratings) }
            }
        }
        .foregroundStyle(Theme.C.ink)
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, S3Layout.fade)  // Platz für feste Leiste + Verlauf, letzte Zeile bleibt lesbar
        .frame(maxWidth: .infinity, alignment: .leading)
        .pinned(right: imported ? S3Layout.importedPlateRight : S3Layout.plateRight, top: plateTop + shift) {
            let size = imported ? S3Layout.importedPlateSize : S3Layout.plateSize
            PlatePhoto(url: mediaURL(recipe.imageUrl), size: size)
        }
        .edgeForm(.circle, imported ? Theme.C.blue1 : Theme.C.blue, width: S3Layout.blobSize, height: S3Layout.blobSize,
                  left: S3Layout.blobLeft, top: S3Layout.blobTop)
    }

    // MARK: Kopf

    /// a1-fav: Zurück links, rechts Herz (füllt sich Rosé), Punkte, Teilen; gescrollt: Name in der Mitte (Teil 2/3).
    fileprivate var header: some View {
        HStack(spacing: 0) {
            Button { dismiss() } label: {
                Icon(.back).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Zurück")
            Text(recipe.title).font(S3Layout.head).lineLimit(1).frame(maxWidth: .infinity)
                .opacity(compact ? 1 : 0).accessibilityHidden(!compact)
            HStack(spacing: S3Layout.iconGap - 20) {
                PlateHeart(on: isFavorite, bare: true) { toggleFavorite() }
                moreMenu
                shareMenu
            }
        }
        .foregroundStyle(Theme.C.ink)
        .padding(.horizontal, Theme.pagePadding - 10)  // Icon 24 in Tap-Fläche 44 → Icon-Kante auf 24
        .padding(.top, S3Layout.headTop)
        .background { if compact { Theme.C.bg.ignoresSafeArea(edges: .top).transition(.opacity) } }
    }

    fileprivate var shareMenu: some View {
        Menu {
            Button("Als Bild teilen", systemImage: "photo") { shareCard = true }
            Button("Als Link teilen", systemImage: "link") { shareLink = true }  // Feature 56
        } label: {
            Icon(.share).foregroundStyle(Theme.C.ink).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("Rezept teilen")
    }

    /// Alles ohne eigenen Platz im Mockup: Einplanen, Würfeln, Mag ich nicht, Bewerten, Liste, Bearbeiten/Löschen, Nie-Liste, Fehler.
    fileprivate var moreMenu: some View {
        Menu {
            Button("Einplanen", systemImage: "calendar.badge.plus") { planIt = true }
            if meal.id != nil {  // Plan-Gericht: Würfeln bzw. Ersatz (19.3)
                Button(rolling ? "Würfelt …" : "Ändern", systemImage: "dice") { choosing = true }.disabled(rolling)
            }
            Button("Mag ich nicht", systemImage: "hand.thumbsdown") { disliking = true }
            Button("Gekocht – bewerten", systemImage: "star") { showRating = true }
            Button("Angebotszutaten zur Liste", systemImage: "bag") {
                let offers = recipe.ingredients.compactMap { ing in store.offers.first { $0.id == ing.offerId } }
                withAnimation(Theme.spring) { offers.forEach { o in store.addToList(o) } }
                if offers.isEmpty { store.flash("Keine Angebotszutaten") }
            }
            if recipe.source != "ai" {  // eigene und importierte Rezepte
                Button("Bearbeiten", systemImage: "pencil") { editing = true }
                Button("Löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
            if details.hidden == true {  // 19.9: Nie-Liste zurücknehmen (R15)
                Button("Wieder vorschlagen", systemImage: "arrow.uturn.backward") {
                    Task { if let r = await store.unhide(recipe.id) { info = r } }
                }
            }
            Button("Fehler melden", systemImage: "exclamationmark.bubble") { reporting = true }  // R13
        } label: {
            Icon(.dots).foregroundStyle(Theme.C.ink).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("Weitere Aktionen")
    }

    // MARK: Teil 1

    /// Zeit, Preis pro Portion, kcal als Zahlen 34 in einer Spalte 140 breit.
    fileprivate func stats(cents: Int, kcal: Int?) -> some View {
        VStack(spacing: S3Layout.statGap) {
            StatNumber(label: "Zeit", value: "\(recipe.prepMinutes)′", size: S3Layout.statSize)
                .accessibilityLabel("Zeit \(recipe.prepMinutes) Minuten")
            StatNumber(label: "p. P.", value: euroPlain(cents), size: S3Layout.statSize)
                .accessibilityLabel("Preis pro Portion \(euro(cents))")
            StatNumber(label: "kcal", value: kcal.map { "\($0)" } ?? "–", size: S3Layout.statSize, mute: kcal == nil)
                .accessibilityLabel(kcal.map { "\($0) Kilokalorien" } ?? "Kilokalorien werden berechnet")
        }
        .frame(width: S3Layout.statsWidth)
    }

    /// Importiert: nur der Live-Preis groß („p. P. / heute“), Zeit und kcal klein darunter.
    fileprivate func importedStat(cents: Int, kcal: Int?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 6) {
                Hairline(color: Theme.C.ink)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("p. P.")
                        Text("heute").foregroundStyle(Theme.C.blue3)
                    }
                    .font(Theme.F.text(12, .bold, relativeTo: .caption))
                    Spacer(minLength: 8)
                    BigNumber(euroPlain(cents), size: S3Layout.importedStatSize)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preis pro Portion heute \(euro(cents))")
            Text((["\(recipe.prepMinutes) min"] + [kcal.map { "\($0) kcal" }].compactMap { $0 }).joined(separator: " · "))
                .font(S3Layout.small13).foregroundStyle(Theme.C.ink2)
        }
        .frame(width: S3Layout.importedStatsWidth)
    }

    /// Quelle-Chip „Instagram · @autor“ + Tinten-Pille „▶ Original-Reel“ (öffnet Instagram-App bzw. Safari, 5/9).
    fileprivate var sourceRow: some View {
        let insta = recipe.source == "instagram"
        let host = URL(string: recipe.sourceUrl)?.host()?.replacingOccurrences(of: "www.", with: "") ?? ""
        let text = recipe.source == "shared" ? "von \(recipe.sourceAuthor)"  // übernommen aus einem anderen Haushalt (56)
            : "\(insta ? "Instagram" : "Web") · \(recipe.sourceAuthor.isEmpty ? host : recipe.sourceAuthor)"
        return HStack(spacing: 8) {
            Text(text).font(Theme.F.text(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2).lineLimit(1)
                .padding(.horizontal, 12).frame(height: S3Layout.sourceChip)
                .background(Theme.C.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
            if insta, let url = URL(string: recipe.sourceUrl), !recipe.sourceUrl.isEmpty {
                Button { openURL(url) } label: {
                    Pill8(text: "Original-Reel", icon: .play).frame(minHeight: 44).contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Original-Reel öffnen")
            }
        }
        .frame(minHeight: 44)
    }

    /// Zutaten als Zeilen (`.irow`): Kreis mit Zeichnung, Name, rechts höchstens ein Badge; Menge fett (importiert: zweite Zeile).
    fileprivate func ingredients(factor: Double, who: ProfileDTO?, mine: Double?, base: Double) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(recipe.ingredients.enumerated()), id: \.offset) { index, ing in
                let offer = store.offers.first { $0.id == ing.offerId }
                let rest = meal.rests?.first { r in r.name.localizedCaseInsensitiveCompare(ing.name) == .orderedSame }
                let amount = qty(ing.amount * factor, ing.unit)
                // Feature 1: Zutat antippen → Angebot (oder passende Angebote)
                Button { if let offer { openOffer = offer } else { searchIngredient = ing } } label: {
                    // wie `IRow`; lange Namen zweizeilig statt kleiner, damit alle Zeilen gleich groß bleiben
                    HStack(spacing: 14) {
                        ingredientArt(ing.name).frame(width: Theme.S.rowCircle, height: Theme.S.rowCircle)
                            .background(ingredientTint(ing.name, offer: offer, index: index), in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ing.name).font(Theme.F.rowName).lineLimit(2)
                            if imported {
                                Text(amount).font(S3Layout.small13).foregroundStyle(Theme.C.ink2).lineLimit(1)
                                    .contentTransition(.numericText())
                            }
                        }
                        .layoutPriority(1)
                        Spacer(minLength: 8)
                        ingredientBadge(ing, offer: offer, rest: rest).fixedSize()
                        if !imported {
                            Text(amount).font(S3Layout.amount).lineLimit(1).fixedSize().contentTransition(.numericText())
                        }
                    }
                    .frame(minHeight: Theme.S.row)
                    .overlay(alignment: .top) { Hairline() }
                    .contentShape(Rectangle())
                    .foregroundStyle(Theme.C.ink)
                }
                .buttonStyle(PressableStyle())
                .contextMenu {  // lange drücken → Ersatz (7)
                    Button("Ersatz finden", systemImage: "arrow.left.arrow.right") { substituting = index }
                    Button("Preisalarm", systemImage: "bell.badge") { alarmFor = ing.name }
                    Button("Mag ich nicht", systemImage: "hand.thumbsdown") { Task { await store.dislike(ing.name) } }  // 19.2
                }
                .accessibilityAction(named: "Ersatz finden") { substituting = index }
                .accessibilityAction(named: "Mag ich nicht") { Task { await store.dislike(ing.name) } }
                .accessibilityAction(named: "Preisalarm") { alarmFor = ing.name }
                .accessibilityHint(who.flatMap { w in mine.map { m in "Portion \(w.name): \(qty(ing.amount * m * meal.scale / base, ing.unit))" } } ?? "")
            }
        }
        .animation(Theme.spring, value: servings)
    }

    @ViewBuilder fileprivate func ingredientArt(_ name: String) -> some View {
        if let ill = OfferArt.ill(name) {
            Ill(ill).frame(width: Theme.S.rowImage, height: Theme.S.rowImage)
        } else {
            Icon(.leaf, size: 22).foregroundStyle(Theme.C.ink)
        }
    }

    fileprivate func ingredientTint(_ name: String, offer: OfferDTO?, index: Int) -> Color {
        OfferArt.ill(name) != nil ? OfferArt.tint(name, category: offer?.category ?? "") : S3Layout.tints[index % S3Layout.tints.count]
    }

    /// Höchstens ein Badge: Rabatt, sonst „im Vorrat“, „Rest von Mo“ (19) oder „Menge geschätzt“ (Import, 5).
    @ViewBuilder fileprivate func ingredientBadge(_ ing: IngredientDTO, offer: OfferDTO?, rest: RestBadgeDTO?) -> some View {
        if let offer {
            DealPill(text: offer.discount.map { "−\($0) %" } ?? "Angebot")
                .accessibilityLabel("Im Angebot bei \(Labels.chain(offer.chain))")
        } else if ing.inPantry == true {
            SoftPill(text: "im Vorrat", tint: Theme.C.sage)
        } else if let rest, Labels.days.indices.contains(rest.fromDay) {
            SoftPill(text: "Rest von \(Labels.days[rest.fromDay])", icon: .refresh)
        } else if ing.estimated == true {
            SoftPill(text: "Menge geschätzt", tint: Theme.C.warn)
        }
    }

    // MARK: Teil 3

    /// `.irow` „Portionen / Mengen passen sich an“ + Stepper, Linie oben und unten.
    fileprivate func portionsRow(base: Double) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Portionen").font(S3Layout.head)
                Text("Mengen passen sich an").font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
            }
            Spacer(minLength: 8)
            Stepper8(value: Binding(get: { servings ?? max(Int(base.rounded()), 1) }, set: { servings = $0 }), range: 1...12)
                .accessibilityLabel("Portionen")
        }
        .frame(minHeight: Theme.S.row)
        .overlay(alignment: .top) { Hairline() }
        .overlay(alignment: .bottom) { Hairline() }
    }

    /// `.b-step`: Nummer 22 in ink2 (34 breit) + Text 15; antippen = erledigt. Schritt-Bilder (9) unter dem Text.
    fileprivate var steps: some View {
        VStack(spacing: 0) {
            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, step in
                let isDone = done.contains(i)
                Button {
                    withAnimation(Theme.spring) { if done.remove(i) == nil { done.insert(i) } }
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 14) {
                            Text(String(format: "%02d", i + 1))
                                .font(Theme.F.num(S3Layout.stepNum)).tracking(Theme.F.numTracking(S3Layout.stepNum))
                                .foregroundStyle(isDone ? Theme.C.ink3 : Theme.C.ink2)
                                .frame(width: S3Layout.stepNumWidth, alignment: .leading)
                                .padding(.top, 1)
                            Text(step).font(Theme.F.text(S3Layout.stepText, .semibold, relativeTo: .subheadline))
                                .lineSpacing(S3Layout.stepLine)
                                .strikethrough(isDone)
                                .foregroundStyle(isDone ? Theme.C.ink3 : Theme.C.ink)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if showsImage(i) {
                            StepImage(path: images[i]).opacity(isDone ? 0.5 : 1)
                                .padding(.leading, S3Layout.stepNumWidth + 14).transition(.opacity)
                        }
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { Hairline() }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: isDone)
                .accessibilityLabel("Schritt \(i + 1): \(step)")
                .accessibilityAddTraits(isDone ? .isSelected : [])
            }
        }
        .animation(Theme.spring, value: images)
    }

    /// „Bewertungen“ + Sterne + Schnitt 34; je Bewertung Name und Sterne, darunter Datum · wieder kochen · Notiz.
    fileprivate func ratingsSection(_ ratings: [RatingDTO]) -> some View {
        let avg = details.avgStars ?? Double(ratings.map(\.stars).reduce(0, +)) / Double(ratings.count)
        return VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                Text("Bewertungen").font(S3Layout.head).accessibilityAddTraits(.isHeader)
                Spacer()
                HStack(spacing: 8) {
                    DetailStars(value: avg)
                    BigNumber(num(avg, 1...1), size: S3Layout.ratingNum)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Schnitt \(num(avg, 1...1)) von 5 Sternen")
            }
            VStack(spacing: 0) {
                ForEach(ratings) { r in
                    let again = Labels.again.first { $0.0 == r.again }?.1 ?? r.again
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(r.memberName).font(Theme.F.text(16, .bold))
                            Spacer()
                            DetailStars(value: Double(r.stars))
                        }
                        Text(([Self.dayMonth(r.cookedAt), "\(again) wieder"] + (r.note.isEmpty ? [] : [r.note])).joined(separator: " · "))
                            .font(S3Layout.small13).foregroundStyle(Theme.C.ink2)
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { Hairline() }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, S3Layout.ratingsListTop)
        }
        .padding(.top, S3Layout.ratingsTop)
    }

    /// "2026-11-02T18:30:00" → "2. Nov"
    fileprivate static func dayMonth(_ iso: String) -> String {
        let p = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        let months = ["Jan", "Feb", "März", "Apr", "Mai", "Juni", "Juli", "Aug", "Sep", "Okt", "Nov", "Dez"]
        guard p.count == 3, (1...12).contains(p[1]) else { return shortDate(iso) }
        return "\(p[2]). \(months[p[1] - 1])"
    }

    // MARK: Untere Leiste

    /// Teil 1: „Kochmodus / 5 Schritte“ + Tinten-Kreis 64. Importiert: „Diese Woche einplanen“ + Kreis 56.
    /// Teil 2/3 (gescrollt): blauer Kreis 56 + „★ Gekocht – bewerten“. Darüber Verlauf in `bg`.
    fileprivate var bottomBar: some View {
        ZStack(alignment: .bottom) {
            // Verlauf immer (auch Teil 1), damit Zeilen nicht unter der Leiste durchscheinen; voll `bg` ab 45 %
            LinearGradient(stops: [.init(color: Theme.C.bg.opacity(0), location: 0), .init(color: Theme.C.bg, location: 0.45)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)  // vor `frame`: wächst bis an den Bildschirmrand (Home-Balken)
                .frame(height: S3Layout.fade)
                .allowsHitTesting(false)
            Group {
                if deep {
                    HStack(spacing: S3Layout.fixGap) {
                        RoundIcon(icon: .play, size: S3Layout.fixCircle, fill: Theme.C.blue, label: "Kochmodus starten") { cooking = true }
                        PrimaryButton(title: "Gekocht – bewerten", icon: .star) { showRating = true }
                    }
                } else if imported {
                    HStack(spacing: S3Layout.fixGap) {
                        OutlineButton(title: "Diese Woche einplanen") { planIt = true }
                        RoundIcon(icon: .play, filled: true, size: S3Layout.fixCircle, label: "Kochmodus starten") { cooking = true }
                    }
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Kochmodus").font(S3Layout.head)
                            Text(recipe.steps.count == 1 ? "1 Schritt" : "\(recipe.steps.count) Schritte")
                                .font(S3Layout.small13).foregroundStyle(Theme.C.ink2)
                        }
                        .accessibilityHidden(true)
                        Spacer()
                        RoundIcon(icon: .play, filled: true, size: S3Layout.cookCircle, iconSize: S3Layout.cookIcon,
                                  label: "Kochmodus starten, \(recipe.steps.count) Schritte") { cooking = true }
                    }
                }
            }
            .foregroundStyle(Theme.C.ink)
            .transition(.opacity)
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, S3Layout.fixBottom)
        }
    }
}

/// Sterne 70 × 14 (`.b-st`): gefüllt bis zum Schnitt (4,5 → 4), Rest als Umriss.
private struct DetailStars: View {
    let value: Double

    var body: some View {
        let full = Int((value + 0.25).rounded(.down))
        HStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { i in
                Group {
                    if i < full { FilledIcon(icon: .star, size: S3Layout.star) } else { Icon(.star, size: S3Layout.star) }
                }
                .frame(width: S3Layout.star, height: S3Layout.star)
            }
        }
        .foregroundStyle(Theme.C.ink)
        .accessibilityElement()
        .accessibilityLabel("\(num(value)) von 5 Sternen")
    }
}

/// Menge mit Einheit, z. B. „400 g“, „1 Stück“ (Rezept, Kochmodus, Bildkarte).
func qty(_ amount: Double, _ unit: String) -> String {
    "\(num(amount)) \(Labels.unit(unit))"
}

/// Eckrahmen wie Referenz 02.
struct CornerFrame: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let l: CGFloat = 42
        p.move(to: CGPoint(x: r.minX, y: r.minY + l)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.minY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + l))
        p.move(to: CGPoint(x: r.minX, y: r.maxY - l)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX + l, y: r.maxY))
        p.move(to: CGPoint(x: r.maxX - l, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - l))
        return p
    }
}


/// S8 Bewertung: Sterne, „Wieder kochen?“, Notiz → POST /recipes/{id}/rate (wer/wann setzt das Backend), dann Vorrat abziehen.
struct RatingSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let meal: MealDTO
    @State private var rating = 0
    @State private var again = "bald"
    @State private var note = ""
    @State private var saving = false
    @State private var consumed: [PantryDTO]?  // nach „Speichern“: vom Vorrat abgezogene Einträge (editierbar)
    @State private var rests: [RestRow]?  // danach: tatsächliche Reste bestätigen (19)
    @State private var nextRests: [RestRow] = []
    var demoRests = false  // Demo „leftovers“: direkt die Reste-Abfrage

    var body: some View {
        Group {
            if let rests {
                RestsConfirmView(rows: rests) { dismiss() }
            } else if let consumed {
                consumedList(consumed)
            } else {
                ratingForm
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet8()
        .onAppear { if demoRests && rests == nil { rests = Demo.entryLeftovers.map(RestRow.init) } }
    }

    /// Rückfrage-Liste: was abgezogen wurde, Mengen hier korrigierbar.
    private func consumedList(_ items: [PantryDTO]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("Vom Vorrat abgezogen").font(Theme.F.t2)
                Spacer()
                CloseButton { dismiss() }
            }
            Text("Stimmt etwas nicht? Menge hier korrigieren.").font(Theme.F.text(14, .semibold, relativeTo: .subheadline))
                .foregroundStyle(Theme.C.ink2).padding(.top, 4)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(items) { c in
                        if let p = store.pantry.first(where: { p in p.id == c.id }) {
                            PantryRow(item: p)
                        } else {
                            IRow(name: c.name, sub: "aufgebraucht", tint: Theme.C.line) { Icon(.box, size: 22) }
                        }
                    }
                }
                .padding(.top, 14)
            }
            PrimaryButton(title: nextRests.isEmpty ? "Fertig" : "Weiter") {
                if nextRests.isEmpty { dismiss() } else { withAnimation(Theme.spring) { rests = nextRests } }
            }
            .padding(.vertical, 18)
        }
        .padding(.horizontal, Theme.pagePadding)
        .transition(.opacity)
    }

    private var cookedWhen: String {
        let day = meal.day == store.today ? "Heute" : Labels.dayNames[max(0, min(meal.day, 6))]
        return "\(day) \(Labels.meal(meal.mealType)) gekocht"
    }

    private var ratingForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    PlanPlate(url: mediaURL(meal.recipe.imageUrl), size: 56, mini: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cookedWhen).font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                        Text(meal.recipe.title).font(Theme.F.serif(22, relativeTo: .title2)).lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    CloseButton { dismiss() }
                }
                Text("Wie war's?").font(Theme.F.serif(30, relativeTo: .largeTitle)).padding(.top, 22)
                stars.padding(.top, 10)
                SectionLabel("Wieder kochen?", big: true).padding(.top, 22).padding(.bottom, 4)
                Segmented8(options: Labels.again, selection: $again)
                FieldBox(icon: .edit) {
                    TextField("Notiz (optional)", text: $note)
                }
                .padding(.top, 14)
                PlanBusyButton(title: "Speichern", busy: saving, disabled: rating == 0, action: save).padding(.top, 18)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    /// Fünf Sterne 46 (gefüllt Tinte, sonst Umriss ink3).
    private var stars: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { i in
                let on = i <= rating
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { rating = i } } label: {
                    ZStack {
                        if on {
                            Icon8.star.path(.stroke).fill(Theme.C.ink)  // Pfad im 24er-Raster wie `Icon`
                                .frame(width: 24, height: 24).scaleEffect(46 / 24)
                        }
                        Icon(.star, size: 46).foregroundStyle(on ? Theme.C.ink : Theme.C.ink3)
                    }
                    .frame(width: 46, height: 46)
                    .scaleEffect(on ? 1 : 0.92)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(i) \(i == 1 ? "Stern" : "Sterne")")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            guard await store.rate(meal.recipe.id, stars: rating, again: again, note: note) else { return }
            store.flash(rating >= 4 ? "Gespeichert – kommt öfter" : "Danke für deine Bewertung")
            let changed = await store.consume(meal)
            nextRests = await store.entryLeftovers(meal).map(RestRow.init)  // erwartete Reste angebrochener Packungen
            if changed.isEmpty {
                if nextRests.isEmpty { dismiss() } else { withAnimation(Theme.spring) { rests = nextRests } }
                return
            }
            store.flash("Vorrat aktualisiert")
            withAnimation(Theme.spring) { consumed = changed }
        }
    }
}

/// Schieberegler (`.a-sl`): Spur 4 in `line`, Füllung Tinte, Knopf 26 Tinte mit 4er-Ring in `bg`.
struct PlanSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var label = ""

    var body: some View {
        GeometryReader { g in
            let f = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = (g.size.width - 26) * f
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.C.line).frame(height: 4)
                Capsule().fill(Theme.C.ink).frame(width: x + 13, height: 4)
                Circle().fill(Theme.C.ink).frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.C.bg).padding(-4))
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { d in
                let p = min(max((d.location.x - 13) / max(g.size.width - 26, 1), 0), 1)
                let v = range.lowerBound + p * (range.upperBound - range.lowerBound)
                value = (v / step).rounded() * step
            })
        }
        .frame(height: 44)
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value))")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }
}

/// S7 Plan-Generator: Tage, Mahlzeiten, Budget, drei Unterseiten; danach S7 Laden (Topf, Tage füllen sich).
struct PlanGeneratorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var started = Demo.screen == "generating"
    @State private var done = Demo.screen == "generating" ? 3 : 0  // fertige Tage (Anzeige)
    @State private var finished = false
    @State private var prefs = Prefs()
    @State private var wishes = ""
    @State private var saveAsDefault = false
    @State private var info: GeneratorDTO?  // KW + „Diese Woche im Angebot“ (17)
    @State private var specials: [SpecialDTO] = []  // Vorlagen (25)
    @State private var special: String?
    @State private var guests: [String: Int] = [:]  // „+ Gäste“ (15)
    @State private var guestEuro: Double?
    @State private var nextWeek = Demo.screen == "singlestore"  // „Plan für nächste Woche“ (30)
    @State private var singleStore: String? = Demo.screen == "singlestore" ? "lidl" : nil  // „Nur ein Laden“ (41)
    @State private var page: Page? = Demo.screen == "singlestore" ? .stores : Demo.screen == "generatorMore" ? .more : nil

    private enum Page { case stores, kitchen, more }

    var body: some View {
        ZStack {
            if started {
                loading.transition(.opacity)
            } else if let page {
                subpage(page).transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                main.transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .edgeForm(.quarter, Theme.C.blue1, width: 150, height: 150, right: 0, top: -33)
        .sheet8()
        .animation(Theme.spring, value: started)
        .animation(Theme.spring, value: page)
        .onAppear { if let h = store.household { prefs = Prefs(h) } }
        .task {
            if let s = store.generatorSpecial { special = s; store.generatorSpecial = nil }  // Start-Banner (25)
            info = await store.generatorInfo()
            specials = await store.specials()?.specials ?? []
            if store.demo && special == nil { special = info?.banner?.key }
        }
    }

    // MARK: Hauptseite

    private var weekKey: String {
        let cal = Calendar(identifier: .iso8601)
        let d = nextWeek ? cal.date(byAdding: .weekOfYear, value: 1, to: .now) ?? .now : .now
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)
        return String(format: "%04d-W%02d", c.yearForWeekOfYear ?? 2026, c.weekOfYear ?? 1)
    }

    private var main: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("Wochenplan erstellen").font(Theme.F.t2)
                    Spacer()
                    CloseButton { dismiss() }
                }
                Text("KW \(PlanWeek.kw(weekKey)) · \(PlanWeek.range(weekKey, wide: true))")
                    .font(Theme.F.text(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2)
                    .contentTransition(.numericText())
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { d in
                        if d > 0 { Spacer(minLength: 2) }
                        dayCircle(d)
                    }
                }
                .padding(.top, 32)
                FlowLayout(spacing: 8) {
                    ForEach(Labels.mealTypes, id: \.0) { m in
                        Chip8(title: m.1, on: prefs.mealTypes.contains(m.0)) {
                            withAnimation(Theme.spring) { if !prefs.mealTypes.insert(m.0).inserted { prefs.mealTypes.remove(m.0) } }
                        }
                    }
                }
                .padding(.top, 14)
                PlanStat(label: "Budget\npro Woche") { BigNumber("\(Int(prefs.budgetEuro)) €", size: 56) }.padding(.top, 34)
                PlanSlider(value: $prefs.budgetEuro, range: 20...200, step: 5, label: "Budget pro Woche").padding(.top, 10)
                if let top = info?.topOffers, !top.isEmpty {
                    Text("Im Angebot: \(top.map(\.title).joined(separator: ", "))")
                        .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2).padding(.top, 8)
                }
                VStack(spacing: 0) {
                    pageRow("Läden & Woche", storesSub) { page = .stores }
                    pageRow("Küche & Ziel", kitchenSub) { page = .kitchen }
                    pageRow("Mehr Optionen", moreSub) { page = .more }
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 24)
        }
        .ctaBar(bottom: 0) { createButton }
    }

    private var createButton: some View {
        PrimaryButton(title: "Plan erstellen", icon: .sparkle, disabled: prefs.mealTypes.isEmpty || prefs.planDays.isEmpty) { start() }
    }

    private func dayCircle(_ d: Int) -> some View {
        let on = prefs.planDays.contains(d)
        return Button {
            withAnimation(Theme.spring) { if !prefs.planDays.insert(d).inserted { prefs.planDays.remove(d) } }
        } label: {
            Text(Labels.days[d]).font(Theme.F.text(13, .extrabold, relativeTo: .footnote))
                .foregroundStyle(on ? Theme.C.onInk : Theme.C.ink2)
                .frame(width: 38, height: 38)
                .background(on ? Theme.C.ink : .clear, in: Circle())
                .overlay { if !on { Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
                .frame(minWidth: 40, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityLabel(Labels.dayNames[d])
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func pageRow(_ title: String, _ sub: String, _ open: @escaping () -> Void) -> some View {
        Button(action: open) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.F.text(16, .extrabold, relativeTo: .body)).foregroundStyle(Theme.C.ink)
                    Text(sub).font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2).lineLimit(1)
                }
                Spacer(minLength: 8)
                Icon(.chev, size: 18).foregroundStyle(Theme.C.ink3)
            }
            .frame(minHeight: Theme.S.row)
            .overlay(alignment: .top) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var enabledChains: [String] {
        Labels.chains.map(\.key).filter { c in store.household?.stores.contains { s in s.chain == c && s.enabled } ?? false }
    }

    private var storesSub: String {
        let shops = singleStore.map { [Labels.chain($0)] } ?? enabledChains.map(Labels.chain)
        return "\(shops.isEmpty ? "Alle Läden" : shops.joined(separator: " + ")) · \(nextWeek ? "nächste Woche" : "diese Woche")"
    }

    private var kitchenSub: String {
        let goal = Labels.goals.first { $0.0 == prefs.goal }?.1 ?? prefs.goal
        let kitchen = prefs.cuisines.isEmpty ? "Alle Küchen" : prefs.cuisines.sorted().joined(separator: ", ")
        return "\(kitchen) · \(goal)"
    }

    private var moreSub: String {
        let n = GuestPlanner.slots(guests, days: prefs.planDays.sorted(), meals: prefs.mealTypeList).map(\.count).reduce(0, +)
        var parts: [String] = []
        if !wishes.isEmpty { parts.append("Wünsche") }
        if let s = specials.first(where: { $0.key == special }) { parts.append(s.templateName) }
        if n > 0 { parts.append("+\(n) \(n == 1 ? "Gast" : "Gäste")") }
        return parts.isEmpty ? "Wünsche, Special, Gäste" : parts.joined(separator: " · ")
    }

    // MARK: Unterseiten

    private func subpage(_ p: Page) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Button { page = nil } label: { Icon(.back).frame(width: 44, height: 44, alignment: .leading).contentShape(Rectangle()) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Zurück")
                    Text(p == .stores ? "Läden & Woche" : p == .kitchen ? "Küche & Ziel" : "Mehr Optionen").font(Theme.F.t2)
                    Spacer()
                }
                switch p {
                case .stores: storesPage
                case .kitchen: kitchenPage
                case .more: morePage
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .ctaBar(bottom: 0) { createButton }
    }

    private func switchRow(_ title: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(title).font(Theme.F.text(15, .bold, relativeTo: .body)).foregroundStyle(Theme.C.ink) }
            .toggleStyle(.v8)
            .frame(minHeight: 52)
    }

    private var storesPage: some View {
        let chains = enabledChains
        let preview = store.nextOffers.count
        return VStack(alignment: .leading, spacing: 0) {
            switchRow("Plan für nächste Woche", $nextWeek.animation(Theme.spring))
                .disabled(preview == 0 && !nextWeek)
            Text(preview == 0 ? "Noch keine Prospekte für nächste Woche – meist ab Donnerstag oder Freitag."
                              : "Nutzt die Vorschau-Angebote (\(preview)) der nächsten Woche.")
                .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
            Hairline().padding(.top, 16)
            switchRow("Nur ein Laden", Binding(get: { singleStore != nil }, set: { on in
                withAnimation(Theme.spring) { singleStore = on ? chains.first : nil }
            }))
            .disabled(chains.count < 2 && singleStore == nil)
            if let picked = singleStore {
                HStack(spacing: 12) {
                    ForEach(chains, id: \.self) { c in
                        let on = c == picked
                        Button { withAnimation(Theme.spring) { singleStore = c } } label: {
                            StoreLogo(chain: c, size: 44)
                                .padding(4)
                                .overlay(Circle().strokeBorder(on ? Theme.C.ink : .clear, lineWidth: 2))
                                .opacity(on ? 1 : 0.5)
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel(Labels.chain(c))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .sensoryFeedback(.selection, trigger: picked)
                .padding(.top, 8)
                Text("Einkauf komplett bei \(Labels.chain(picked)) – Zutaten ohne Angebot zum Normalpreis von \(Labels.chain(picked)).")
                    .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .padding(.top, 24)
    }

    private var kitchenPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Küche", big: true)
            FlowLayout(spacing: 8) {
                ForEach(Labels.cuisines, id: \.self) { c in
                    Chip8(title: c, on: prefs.cuisines.contains(c)) {
                        withAnimation(Theme.spring) { if !prefs.cuisines.insert(c).inserted { prefs.cuisines.remove(c) } }
                    }
                }
            }
            .padding(.top, 8)
            Text(prefs.cuisines.isEmpty ? "Keine Auswahl = alle Küchen" : " ")
                .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2).padding(.top, 4)
            SectionLabel("Ziel", big: true).padding(.top, 28)
            Segmented8(options: Labels.goals.map { ($0.0, $0.1) }, selection: $prefs.goal).padding(.top, 8)
            PlanStat(label: "Kochzeit\nhöchstens") { BigNumber("\(Int(prefs.maxCook)) min", size: 40) }.padding(.top, 32)
            PlanSlider(value: $prefs.maxCook, range: 15...90, step: 5, label: "Kochzeit höchstens").padding(.top, 10)
            HStack {
                Text("Personen").font(Theme.F.text(15, .bold, relativeTo: .body))
                Spacer()
                Stepper8(value: $prefs.persons, range: 1...12)
            }
            .frame(minHeight: Theme.S.row)
            .overlay(alignment: .top) { Hairline() }
            .padding(.top, 24)
        }
        .padding(.top, 24)
    }

    private var morePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            switchRow("Als Standard speichern", $saveAsDefault)
            FieldBox(icon: .edit) {
                TextField("Wünsche, z. B. mehr Fisch", text: $wishes, axis: .vertical).lineLimit(1...3)
            }
            .padding(.top, 8)
            if !specials.isEmpty {
                SectionLabel("Special", big: true).padding(.top, 32)
                FlowLayout(spacing: 8) {
                    specialChip("Ohne", on: special == nil) { special = nil }
                    ForEach(specials) { s in specialChip(s.templateName, on: special == s.key) { special = s.key } }
                }
                .padding(.top, 8)
                if let s = specials.first(where: { $0.key == special }) {
                    Text("\(s.name) · \(SpecialPicker.templates[s.template] ?? s.templateName)")
                        .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                        .padding(.top, 8)
                        .transition(.opacity)
                }
            }
            SectionLabel("Gäste", big: true).padding(.top, 32)
            GuestPlanner(guests: $guests, extraEuro: $guestEuro, days: prefs.planDays.sorted(), meals: prefs.mealTypeList).padding(.top, 10)
        }
        .padding(.top, 24)
        .animation(Theme.spring, value: special)
    }

    /// Special-Chip: an = blau mit Tinte (Mockup S7 Mehr Optionen).
    private func specialChip(_ title: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(Theme.spring) { action() } } label: {
            Text(title).font(Theme.F.chip).lineLimit(1)
                .foregroundStyle(on ? Theme.C.ink : Theme.C.ink2)
                .padding(.horizontal, 15).frame(height: Theme.S.chip)
                .background(on ? Theme.C.blue : .clear, in: Capsule())
                .overlay { if !on { Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
                .frame(minHeight: 44).contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: S7 Laden

    private var dayLabels: [String] {
        let days = prefs.planDays.sorted()
        return (days.isEmpty ? Array(0..<7) : days).map { Labels.days[$0] }
    }

    /// Schritt-Texte (Mockup `plan`) mit echten Daten.
    private var steps: [(String, String)] {
        let chains = (singleStore.map { [$0] } ?? enabledChains).map(Labels.chain)
        let shops = chains.count > 1 ? chains.dropLast().joined(separator: ", ") + " und " + chains.last! : chains.first ?? "deinen Läden"
        let offers = (nextWeek ? store.nextOffers : store.offers).count
        let pasta = store.household?.variety?.maxPasta ?? VarietyDTO().maxPasta
        let names = store.profiles.map(\.name)
        let eaters = names.count > 1 ? names.dropLast().joined(separator: ", ") + " und " + names.last! : names.first ?? "\(prefs.persons) Personen"
        return [("Angebote auswerten …", "\(offers) Angebote bei \(shops)"),
                ("Lieblingsrezepte prüfen …", "Gut Bewertetes kommt öfter"),
                ("Gerichte planen …", "Abwechslung: max. \(pasta)× Pasta"),
                ("Preise & Nährwerte rechnen …", "für \(eaters)")]
    }

    private var loading: some View {
        let step = steps[min(3, done / 2)]
        let failed = store.error != nil && !store.generating && !store.demo
        return VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text("Wochenplan").font(Theme.F.t2)
                Spacer()
                CloseButton { dismiss() }
            }
            .padding(.horizontal, Theme.pagePadding)
            PotLoader().opacity(finished || failed ? 0.25 : 1).padding(.top, 34)
            Group {
                if failed {
                    Text("Das hat nicht geklappt")
                } else if finished {
                    Text("Dein Plan steht!").id("fertig")
                } else {
                    Text(step.0).id(step.0)
                }
            }
            .font(Theme.F.t2).multilineTextAlignment(.center)
            .frame(minHeight: 58).padding(.top, 30)
            .transition(.opacity)
            Text(failed ? store.error ?? "" : finished ? finishText : step.1)
                .font(Theme.F.text(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
            if failed {
                PrimaryButton(title: "Erneut versuchen", icon: .refresh) { start() }.padding(.top, 28)
            } else {
                PotDays(done: finished ? dayLabels.count : done, labels: dayLabels).padding(.top, 28)
                Text("Dauert meist unter einer Minute")
                    .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2).padding(.top, 26)
            }
        }
        .padding(.horizontal, failed ? Theme.pagePadding : 0)
        .animation(.easeInOut(duration: 0.25), value: done)
        .animation(.easeInOut(duration: 0.25), value: finished)
    }

    private var finishText: String {
        guard let p = store.plan else { return "" }
        return "\(p.entries.count) Gerichte · \(euro(p.totalCents)) · \(euro(p.savedCents)) gespart"
    }

    private func start() {
        withAnimation(Theme.spring) { started = true; done = 0; finished = false }
        guard !store.demo else { done = 3; return }
        Task {
            var options = prefs.options(wishes: wishes, saveAsDefault: saveAsDefault)
            let slots = GuestPlanner.slots(guests, days: prefs.planDays.sorted(), meals: prefs.mealTypeList)
            options.guests = slots.isEmpty ? nil : slots
            options.guestBudgetCents = slots.isEmpty ? nil : guestEuro.map { e in Int(e) * 100 }
            options.special = special
            options.nextWeek = nextWeek
            options.singleStore = singleStore
            let body = options
            let ticker = Task {  // Fortschritt ist nur Anzeige, das Backend arbeitet in einem Aufruf
                while !Task.isCancelled && done < dayLabels.count - 1 {
                    try? await Task.sleep(for: .seconds(7))
                    if store.generating && !Task.isCancelled { done += 1 }
                }
            }
            await store.generatePlan(body)
            ticker.cancel()
            guard store.error == nil else { return }
            finished = true
            store.flash("Dein Wochenplan ist fertig")
            try? await Task.sleep(for: .seconds(1.6))
            dismiss()
        }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } }
}

/// „Neues Gericht – wie soll es sein?“ (19.3): Richtung, eigener Wunsch oder „nie wieder“; Tageskarte und Rezeptdetail.
struct RerollDialog: ViewModifier {
    @Environment(AppStore.self) private var store
    let meal: MealDTO
    @Binding var isPresented: Bool
    var onReplace: (() -> Void)?  // „Durch eigenes Rezept ersetzen“ (Rezeptdetail)
    let roll: (_ direction: String?, _ wish: String) -> Void
    @State private var disliking = false
    @State private var wishing = false
    @State private var wish = ""

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Neues Gericht – wie soll es sein?", isPresented: $isPresented, titleVisibility: .visible) {
                if !meal.locked {
                    Button("Einfach anders") { roll(nil, "") }
                    ForEach(Labels.rerollDirections, id: \.0) { d in Button(d.1) { roll(d.0, "") } }
                    Button("Eigener Wunsch …") { wish = ""; wishing = true }
                }
                if let onReplace { Button("Durch eigenes Rezept ersetzen", action: onReplace) }
                Button("Mag ich nicht …", role: .destructive) { disliking = true }
                Button("Abbrechen", role: .cancel) {}
            }
            .alert("Was hättest du gern?", isPresented: $wishing) {
                TextField("z. B. mit Reis, etwas Asiatisches", text: $wish)
                Button("Würfeln") { roll(nil, wish) }
                Button("Abbrechen", role: .cancel) {}
            }
            .modifier(DislikeDialog(meal: meal, isPresented: $disliking, roll: meal.locked ? nil : { roll(nil, "") }, store: store))
    }
}

/// „Mag ich nicht“ mit Grund: Zutat → „Mag nicht“-Liste (19.2), schmeckt nicht/Sonstiges → Nie-Liste (Bewertung „nie“,
/// E96), keine Lust → nur diese Woche. Im Plan wird danach neu gewürfelt (`roll`), sonst bleibt es beim Merken.
enum DislikeReason {
    case ingredient(String), taste, other(String)

    var note: String {
        switch self {
        case .ingredient(let name): name
        case .taste: "schmeckt nicht"
        case .other(let text): text.isEmpty ? "sonstiges" : text
        }
    }
}

/// „Mag ich nicht“ mit Grund (Sheet, Mockup v9 e.html D): Rezeptdetail und Würfel-Dialog (19.2), Swipe-Stapel (20).
struct DislikeDialog: ViewModifier {
    let ingredients: [String]
    @Binding var isPresented: Bool
    let noMood: (() -> Void)?  // „Keine Lust (nur diese Woche)“
    var title = ""  // Gericht unter der Überschrift
    let choose: (DislikeReason) -> Void

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            DislikeSheet(title: title, ingredients: ingredients, noMood: noMood, choose: choose)
        }
    }
}

/// Gründe als Haken-Zeilen; „Eine Zutat“ klappt die Zutaten als Chips auf, „Sonstiges“ ein Freitextfeld.
private struct DislikeSheet: View {
    enum Pick { case ingredient, taste, mood, other }

    let title: String
    let ingredients: [String]
    let noMood: (() -> Void)?
    let choose: (DislikeReason) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pick: Pick
    @State private var ingredient: String?
    @State private var note = ""
    @State private var height: CGFloat = 420

    init(title: String, ingredients: [String], noMood: (() -> Void)?, choose: @escaping (DislikeReason) -> Void) {
        self.title = title
        self.ingredients = ingredients
        self.noMood = noMood
        self.choose = choose
        _pick = State(initialValue: ingredients.isEmpty ? .taste : .ingredient)
        _ingredient = State(initialValue: ingredients.first)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mag ich nicht").font(Theme.F.t2)
                        if !title.isEmpty {
                            Text(title).font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                        }
                    }
                    Spacer()
                    CloseButton { dismiss() }
                }
                VStack(spacing: 0) {
                    if !ingredients.isEmpty {
                        option(.ingredient, "Eine Zutat", "kommt auf deine Mag-nicht-Liste") {
                            // shortcut: eine Zutat je Mal – Vote/Abneigung nehmen nur einen Namen, bei Bedarf Liste im Backend
                            FlowLayout(spacing: 6, lineSpacing: 0) {  // Chips haben 44er Tap-Rahmen
                                ForEach(ingredients, id: \.self) { name in
                                    Chip8(title: name, on: ingredient == name) { ingredient = name }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    option(.taste, "Schmeckt mir nicht", "Gericht nie wieder vorschlagen") { EmptyView() }
                    if noMood != nil { option(.mood, "Keine Lust", "nur diese Woche raus") { EmptyView() } }
                    option(.other, "Sonstiges", "kurz sagen, warum") {
                        FieldBox { TextField("z. B. zu scharf für die Kinder", text: $note) }.padding(.top, 8)
                    }
                }
                .padding(.top, 14)
                PrimaryButton(title: "Raus damit", disabled: pick == .ingredient && ingredient == nil, action: done)
                    .padding(.top, 14)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 40)
            .animation(Theme.spring, value: pick)
            .onGeometryChange(for: CGFloat.self) { g in g.size.height } action: { h in height = h }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.immediately)
        .presentationDetents([.height(height + 33), .large])
        .sheet8()
    }

    /// Zeile `.opt`: Haken-Kreis, Titel 15, Unterzeile 12; Zusatz nur, wenn gewählt.
    private func option<Extra: View>(_ p: Pick, _ head: String, _ sub: String, @ViewBuilder extra: () -> Extra) -> some View {
        let on = pick == p
        return HStack(alignment: .top, spacing: 12) {
            CheckCircle(on: on).padding(.top, 1).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(head).font(Theme.F.text(15, .extrabold, relativeTo: .body))
                Text(sub).font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                if on { extra() }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .overlay(alignment: .top) { Hairline() }
        .contentShape(Rectangle())
        .onTapGesture { pick = p }
        .accessibilityElement(children: on ? .contain : .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private func done() {
        switch pick {
        case .ingredient: if let ingredient { choose(.ingredient(ingredient)) }
        case .taste: choose(.taste)
        case .mood: noMood?()
        case .other: choose(.other(note))
        }
        dismiss()
    }
}

extension DislikeDialog {
    /// Plan-Gericht: Zutat → Abneigungen, sonst Nie-Liste; danach ggf. neu würfeln.
    init(meal: MealDTO, isPresented: Binding<Bool>, roll: (() -> Void)?, store: AppStore) {
        self.init(ingredients: meal.recipe.ingredients.filter { $0.inPantry != true }.map(\.name).uniqued(),
                  isPresented: isPresented, noMood: roll, title: meal.recipe.title) { reason in
            Task {
                if case .ingredient(let name) = reason {
                    await store.dislike(name)
                    roll?()
                } else if await store.rate(meal.recipe.id, stars: 1, again: "nie", note: "Mag ich nicht: \(reason.note)") {
                    if let roll { roll() } else { store.flash("Kommt nicht mehr in deine Pläne") }
                }
            }
        }
    }
}
