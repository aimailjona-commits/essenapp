import SwiftUI

/// S1 Start (a.html): Begrüßung, Tisch-Illustration auf blauem Kreis, heutiges Gericht, Woche und Ersparnis.
/// Weiter unten (S1 gescrollt): Budget-Rest, Ausgaben, weitere Spar-Tipps, Wochenrückblick.
struct StartView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showGenerator: Bool
    @Binding var planWeek: Bool  // Woche per Swipe (20)
    @Binding var quickOpen: Bool  // Schnell-Aktionen hinter dem „+“ im Kopf
    @State private var search = ""
    @State private var banner: SpecialDTO?  // Feiertag/Saison in ≤ 14 Tagen (25)
    @State private var noMood = false  // „Keine Lust“ (16)
    @State private var shown = false  // Auftritt `a1-num`
    @State private var tips = 0  // weitere Spar-Tipps (30, 31)
    @State private var showTips = false

    // Maße aus dem Mockup (Bildschirm-Oberkante = 0)
    private enum K {
        static let top: CGFloat = 66
        static let mealTop: CGFloat = 380, mealWidth: CGFloat = 190
        static let statsTop: CGFloat = 578
        static let hero: CGFloat = 724  // 844 − Nav 120
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if store.plan == nil {
                    PlanEmptyHero { planWeek = true }
                        .overlay(alignment: .topTrailing) { avatarRow.padding(.top, K.top).padding(.trailing, Theme.pagePadding) }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        hero.zIndex(1)  // Kreis des Spar-Bereichs liegt hinter „Gespart“, nicht darüber
                        more.id("savings")
                    }
                }
            }
            .ignoresSafeArea(edges: .top)
            .onAppear {  // Demo: Spar-Bereich (43/30/31) im Bild
                if ["savings", "budgetover"].contains(Demo.screen ?? "") { proxy.scrollTo("savings", anchor: .top) }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable {
            await store.loadAll()
            banner = await store.specials()?.banner
        }
        .task { banner = await store.specials()?.banner }
        .task(id: store.plan?.id) {
            let a = (try? await store.nextWeekDeals())?.count ?? 0
            let b = (try? await store.stockups())?.count ?? 0
            tips = min(a, 3) + min(b, 3)
        }
        .onAppear {
            guard !shown else { return }
            if reduceMotion { shown = true } else { withAnimation(.timingCurve(0.3, 1.25, 0.5, 1, duration: 0.6)) { shown = true } }
        }
        .sheet(isPresented: $noMood) { NoMoodSheet().presentationDetents([.large]) }
        .sheet(isPresented: $showTips) { TipsSheet().presentationDetents([.large]) }
    }

    // MARK: Kopf

    private var name: String { store.profile?.name ?? store.household?.name ?? "" }

    /// Avatar (→ Einstellungen) und „+“ (→ Schnell-Aktionen).
    private var avatarRow: some View {
        HStack(spacing: 10) {
            NavigationLink { SettingsView() } label: {
                Text(String(name.prefix(1)).uppercased()).font(Theme.F.serif(20)).foregroundStyle(Theme.C.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.C.sand, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Einstellungen")
            Button { withAnimation(Theme.spring) { quickOpen = true } } label: { PlanInkCircle(icon: .plus, size: 44, iconSize: 22) }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Schnell-Aktionen")
        }
    }

    private var hero: some View {
        let meal = store.todayMeal
        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "Hey," : "Hey \(name),").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                Text("Was kochen\nwir heute?").font(Theme.F.t1)
            }
            .padding(.leading, Theme.pagePadding).padding(.top, K.top)

            todayBlock(meal)
                .frame(width: K.mealWidth, alignment: .leading)
                .padding(.leading, Theme.pagePadding).padding(.top, K.mealTop)
                .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 14)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.45).delay(0.2), value: shown)

            if let plan = store.plan {
                VStack(spacing: 12) {
                    StatF(label: "Diese Woche", value: euro(plan.totalCents), size: 52, roll: 0.15)
                    if plan.savedCents > 0 {
                        NavigationLink { SavingsView() } label: {  // S11 Ersparnis
                            StatF(label: "Gespart", value: euro(plan.savedCents), size: 40, valueColor: Theme.C.deal, mute: true, roll: 0.3)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, Theme.pagePadding).padding(.top, K.statsTop)
            }
        }
        .frame(maxWidth: .infinity, minHeight: K.hero, alignment: .topLeading)
        .overlay(alignment: .topTrailing) { avatarRow.padding(.top, K.top).padding(.trailing, Theme.pagePadding) }
        .pinned(left: 150, top: 190) {
            Ill("table").frame(width: 250)
                .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 14)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.35).delay(0.2), value: shown)
        }
        .pinned(left: 130, top: 150) {
            Circle().fill(Theme.C.blue1).frame(width: 400, height: 400)
                .scaleEffect(shown ? 1 : 0.001, anchor: .trailing)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private func todayBlock(_ meal: MealDTO?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let meal {
                Text("Heute \(Labels.meal(meal.mealType))".uppercased())
                    .font(Theme.F.lbl).tracking(11 * 0.08).foregroundStyle(Theme.C.blue3)
                NavigationLink { RecipeDetailView(meal: meal) } label: {
                    Text(meal.recipe.title).font(Theme.F.serif(28, relativeTo: .title)).foregroundStyle(Theme.C.ink)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                Text("\(meal.recipe.prepMinutes) min · \(euro(PlanWeek.perPortion(meal))) p. P.")
                    .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2).padding(.top, 4)
                HStack(spacing: 10) {
                    NavigationLink { RecipeDetailView(meal: meal) } label: { PlanInkCircle(icon: .play, size: 56, iconSize: 20) }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("\(meal.recipe.title) öffnen")
                    Button { noMood = true } label: {
                        Text("Keine Lust?").font(Theme.F.text(14, .extrabold, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink)
                            .lineLimit(1)
                            .padding(.horizontal, 16).frame(height: 44)
                            .overlay(Capsule().strokeBorder(Theme.C.ink, lineWidth: Theme.S.hair))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(.top, 14)
            } else {
                Text("HEUTE").font(Theme.F.lbl).tracking(11 * 0.08).foregroundStyle(Theme.C.blue3)
                Text("Nichts geplant").font(Theme.F.serif(28, relativeTo: .title)).padding(.top, 4)
                Text("Heute ist frei.").font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2).padding(.top, 4)
            }
        }
    }

    // MARK: Weiter unten (S1 gescrollt)

    private var more: some View {
        VStack(alignment: .leading, spacing: 0) {
            BudgetHintCard()  // Budget-Rest / über Budget (43, Saving.swift)
            SpendingCard().padding(.top, 36)  // Ausgaben des Monats (34, Spending.swift)
            VStack(spacing: 0) {
                if tips > 0 {
                    Button { showTips = true } label: {
                        StartRow(icon: .tag, tint: Theme.C.sand, name: tips == 1 ? "1 weiterer Spar-Tipp" : "\(tips) weitere Spar-Tipps",
                                 sub: "Nächste Woche günstiger · Vorrat anlegen")
                    }
                    .buttonStyle(PressableStyle())
                }
                ReviewRow()  // Wochenrückblick (55)
                if let banner {
                    SpecialBanner(banner: banner) {
                        store.generatorSpecial = banner.key
                        showGenerator = true
                    }
                }
            }
            .padding(.top, 36)
            FavoriteDealsCard().padding(.top, 28)  // Lieblingsrezepte günstig (Recipes.swift)
            FieldBox(icon: .search) {
                TextField("Gericht oder Angebot suchen", text: $search)
                if !search.isEmpty {
                    Button { search = "" } label: { Icon(.x, size: 18).frame(width: 44, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel("Suche leeren")
                }
            }
            .padding(.top, 36)
            if !search.isEmpty { searchResults.padding(.top, 14) }
            // Kochbuch unter den Zeilen (Mockup: Bild links 10, sandfarbener Kreis 80 weiter links, 60 tiefer) – im Fluss, damit nichts überdeckt
            Ill("cookbook").frame(width: 200)
                .edgeForm(.circle, Theme.C.sand, width: 330, height: 330, left: -80, top: 60)
                .padding(.leading, 10 - Theme.pagePadding).padding(.top, 24)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 64)
        .padding(.bottom, Theme.S.nav)
        .frame(maxWidth: .infinity, alignment: .leading)
        .edgeForm(.circle, Theme.C.blue1, width: 240, height: 240, left: 250, top: -70)
    }

    private var searchResults: some View {
        let meals = store.plan?.entries.filter { $0.recipe.title.localizedCaseInsensitiveContains(search) } ?? []
        let offers = store.offers.filter { $0.title.localizedCaseInsensitiveContains(search) }.prefix(20)
        return VStack(alignment: .leading, spacing: 0) {
            if !meals.isEmpty { SectionLabel("Gerichte").padding(.bottom, 6) }
            ForEach(meals, id: \.self) { meal in
                NavigationLink { RecipeDetailView(meal: meal) } label: { MealRow(meal: meal) }.buttonStyle(PressableStyle())
            }
            if !offers.isEmpty { SectionLabel("Angebote").padding(.top, 18).padding(.bottom, 6) }
            ForEach(Array(offers)) { offer in
                NavigationLink { OfferDetailView(offer: offer) } label: {
                    IRow(name: offer.title, sub: "\(Labels.chain(offer.chain)) · \(euro(offer.priceCents))",
                         tint: Theme.hue(category: offer.category).tint) {
                        RemoteImage(url: URL(string: offer.imageUrl)) { Icon(.tag, size: 22) }.padding(6).clipShape(Circle())
                    } trail: {
                        if let d = offer.discount { DealPill(text: "−\(d) %") }
                    }
                    .foregroundStyle(Theme.C.ink)
                }
                .buttonStyle(PressableStyle())
            }
            if meals.isEmpty && offers.isEmpty {
                VStack(spacing: 8) {
                    Ill("binoculars").frame(width: 120)
                    Text("Nichts gefunden").font(Theme.F.t2)
                    Text("Versuch einen anderen Begriff.").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Zeile im Start (S1 gescrollt): Kreis 48 mit Icon, Name Serif 17, Unterzeile 12, Chevron.
private struct StartRow: View {
    let icon: Icon8
    let tint: Color
    let name: String
    let sub: String

    var body: some View {
        HStack(spacing: 14) {
            Icon(icon).foregroundStyle(Theme.C.ink)
                .frame(width: Theme.S.rowCircle, height: Theme.S.rowCircle).background(tint, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(Theme.F.serif(17, relativeTo: .body)).lineLimit(2)
                Text(sub).font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2).lineLimit(1)
            }
            .foregroundStyle(Theme.C.ink)
            Spacer(minLength: 8)
            Icon(.chev, size: 18).foregroundStyle(Theme.C.ink3)
        }
        .frame(minHeight: Theme.S.row)
        .overlay(alignment: .top) { Hairline() }
        .contentShape(Rectangle())
    }
}

/// „Wochenrückblick KW 44“ → Story; lange drücken → Archiv; ab Sonntag beim ersten Öffnen einmal automatisch (55).
private struct ReviewRow: View {
    @Environment(AppStore.self) private var store
    @State private var r: WeekReviewDTO?
    @State private var archive = false

    var body: some View {
        VStack(spacing: 0) {
            if let r {
                Button { store.review = r.week } label: {
                    StartRow(icon: .book, tint: Theme.C.blue1, name: "Wochenrückblick KW \(r.kw)",
                             sub: "\(euro(r.money.spentCents)) · \(euro(r.money.savedCents + r.money.bonusCents)) gespart")
                }
                .buttonStyle(PressableStyle())
                .contextMenu { Button("Alle Wochenrückblicke", systemImage: "book") { archive = true } }
                .accessibilityAction(named: "Alle Wochenrückblicke") { archive = true }
                .transition(.opacity)
            }
        }
        .animation(Theme.spring, value: r)
        .navigationDestination(isPresented: $archive) { ReviewArchiveView() }
        .task {
            guard let fresh = try? await store.review("") else { return }
            r = fresh
            let sunday = Calendar.current.component(.weekday, from: .now) == 1
            if sunday, !store.demo, UserDefaults.standard.string(forKey: "reviewShown") != fresh.week {
                UserDefaults.standard.set(fresh.week, forKey: "reviewShown")
                store.review = fresh.week
            }
        }
    }
}

/// „N weitere Spar-Tipps“: nächste Woche günstiger (30) und Vorrat anlegen (31).
private struct TipsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .top) {
                        Text("Spar-Tipps").font(Theme.F.t2)
                        Spacer()
                        CloseButton { dismiss() }
                    }
                    NextWeekCard()
                    StockupCard()
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 24)
            }
            .background(Theme.C.bg)
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet8()
    }
}

/// S1 Leer (auch Woche ohne Plan): Figur liegt auf dem Hügel, „Plan erstellen“ mit Pfeil (`a2-empty`).
/// Während der Erstellung bzw. bei Fehler zeigt dieselbe Fläche Topf bzw. Fehler.
struct PlanEmptyHero: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if store.generating {
                VStack(spacing: 0) {
                    PotLoader().padding(.top, 140)
                    Text("Dein Plan entsteht …").font(Theme.F.t2).padding(.top, 30)
                    Text("Dauert meist unter einer Minute").font(Theme.F.text(14, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(Theme.C.ink2).padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
            } else if let error = store.error {
                VStack(spacing: 10) {
                    Ill("binoculars").frame(width: 180).padding(.top, 160)
                    Text("Das hat nicht geklappt").font(Theme.F.t2)
                    Text(error).font(Theme.F.text(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2)
                        .multilineTextAlignment(.center)
                    PrimaryButton(title: "Erneut versuchen", icon: .refresh) { Task { await store.loadAll() } }.padding(.top, 8)
                }
                .padding(.horizontal, Theme.pagePadding)
                .frame(maxWidth: .infinity)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .containerRelativeFrame(.vertical, alignment: .top)
    }

    private var empty: some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
            let breathe = reduceMotion ? 0 : (1 - cos(2 * .pi * t / 4)) / 2  // 4 s hin und zurück
            let nudge = Self.nudge(reduceMotion ? 1 : t.truncatingRemainder(dividingBy: 4) / 0.6)
            // Kreis, Figur und „z“ als Hintergrund/Overlay: nehmen keinen Platz ein (510er-Kreis machte die Seite sonst breiter)
            VStack(alignment: .leading, spacing: 8) {
                Text("Noch nichts\ngeplant.").font(Theme.F.serif(42, relativeTo: .largeTitle))
                Text("Kein Stress – in 30 Sekunden steht dein Plan.").font(Theme.F.text(17, .medium, relativeTo: .body))
                    .foregroundStyle(Theme.C.ink2)
            }
            .padding(.horizontal, Theme.pagePadding).padding(.top, 66 + 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .topLeading) {
                if !reduceMotion {
                    zzz(t, delay: 0, size: 24, x: 300, y: 458)
                    zzz(t, delay: 2.25, size: 18, x: 304, y: 466)
                }
            }
            .pinned(left: 14, top: 330) {
                Ill("lying").frame(width: 360)
                    .scaleEffect(x: 1 + 0.012 * breathe, y: 1 + 0.025 * breathe, anchor: UnitPoint(x: 0.5, y: 0.85))
            }
            .pinned(left: -60, top: 470) {
                Circle().fill(Theme.C.blue1).frame(width: 510, height: 510).accessibilityHidden(true)
            }
            .overlay(alignment: .bottom) {
                Button(action: action) {
                    HStack {
                        Text("Plan erstellen").font(Theme.F.text(17, .extrabold, relativeTo: .headline)).foregroundStyle(Theme.C.ink)
                        Spacer()
                        Icon(.arrow).foregroundStyle(Theme.C.onInk).offset(x: 5 * nudge.arrow)
                            .frame(width: 72, height: 72)
                            .background(Theme.C.ink, in: Circle())
                            .scaleEffect(nudge.scale).offset(y: nudge.y)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 124)
                .accessibilityLabel("Plan erstellen")
            }
        }
        .clipped()
    }

    /// Knopf stupst alle 4 s an: hoch −10 (1,04), kurz +2, zurück; Pfeil 5 nach rechts.
    private static func nudge(_ k: Double) -> (y: CGFloat, scale: CGFloat, arrow: CGFloat) {
        guard k < 1 else { return (0, 1, 0) }
        let y: Double = k < 0.4 ? -10 * Bezier.easeInOut(k / 0.4) : k < 0.7 ? -10 + 12 * Bezier.easeInOut((k - 0.4) / 0.3) : 2 - 2 * Bezier.easeInOut((k - 0.7) / 0.3)
        let up = max(0, -y / 10)
        return (CGFloat(y), CGFloat(1 + 0.04 * up), CGFloat(up))
    }

    /// „z“ steigt auf, wächst und verblasst (4,5 s).
    private func zzz(_ t: Double, delay: Double, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        let raw = ((t - delay) / 4.5).truncatingRemainder(dividingBy: 1)
        let p = raw < 0 ? raw + 1 : raw
        return Text("z").font(Theme.F.serif(size)).foregroundStyle(Theme.C.ink)
            .scaleEffect(0.6 + 0.5 * p)
            .opacity(sin(.pi * p))
            .offset(x: x + 26 * p, y: y - 72 * p)
            .accessibilityHidden(true)
    }
}

/// Schnell-Aktionen (a.html): Sheet aus dem „+“ im Start-Kopf. Für ContentView als Ersatz der alten `QuickActions`.
struct QuickActionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let select: (QuickActions.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("Schnell-Aktionen").font(Theme.F.t2)
                Spacer()
                CloseButton { dismiss() }
            }
            VStack(spacing: 0) {
                row(.sparkle, "Wochenplan erstellen", .plan)
                row(.barcode, "Barcode scannen", .barcode)
                row(.bag, "Zur Einkaufsliste", .list)
                row(.edit, "Rezept anlegen", .recipe)
            }
            .padding(.top, 14)
            PrimaryButton(title: "Kühlschrank scannen", icon: .cam) { pick(.scan) }.padding(.top, 18)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 16)
        .sheet8()
    }

    private func pick(_ a: QuickActions.Action) {
        dismiss()
        select(a)
    }

    private func row(_ icon: Icon8, _ title: String, _ a: QuickActions.Action) -> some View {
        Button { pick(a) } label: {
            IRow(name: title) {
                Icon(icon).foregroundStyle(Theme.C.ink)
            } trail: {
                Icon(.chev, size: 18).foregroundStyle(Theme.C.ink3)
            }
            .foregroundStyle(Theme.C.ink)
        }
        .buttonStyle(PressableStyle())
    }
}
