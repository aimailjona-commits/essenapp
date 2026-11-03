import SwiftUI

// Phase 14 – Erfolge (54), Wochenrückblick (55), Rezepte zwischen Haushalten teilen (56); Backend E75–E77.

// MARK: Modelle (= backend/app/schemas.py)

/// = AchievementOut (im Rückblick zusätzlich `member_id`).
struct AchievementDTO: Codable, Identifiable, Hashable {
    var key: String
    var group: String  // sparen | gesundheit
    var emoji: String
    var title: String
    var target: Int
    var progress: Double
    var unit: String  // cent | wochen | angebote | tipps | tage | pflanzen
    var unlockedAt: String?
    var new: Bool
    var memberId: Int? = nil

    var id: String { key }
    var unlocked: Bool { unlockedAt != nil }
    var fraction: Double { target > 0 ? min(progress / Double(target), 1) : 0 }

    /// „34 / 50 €“, „2 / 4 Wochen“.
    var progressText: String {
        if unit == "cent" { return "\(num(progress / 100, 0...0)) / \(num(Double(target) / 100, 0...0)) €" }
        let label = ["wochen": "Wochen", "angebote": "Angebote", "tipps": "Tipps", "tage": "Tage", "pflanzen": "Pflanzen"][unit] ?? unit
        return "\(num(progress, 0...0)) / \(target) \(label)"
    }

    /// „Noch 16 € bis zum Ziel“.
    var remainingText: String {
        let left = max(Double(target) - progress, 0)
        return unit == "cent" ? "Noch \(num(left / 100, 0...0)) € bis zum Ziel" : "Noch \(num(left, 0...0)) bis zum Ziel"
    }
}

/// = WeekReviewOut: Seiten cooking, money, health, pantry, achievements, next_week.
struct WeekReviewDTO: Codable, Hashable {
    struct Favorite: Codable, Hashable {
        var recipeId: Int
        var title: String
        var imageUrl: String
        var stars: Int
    }
    struct Cooking: Codable, Hashable {
        var cooked: Int
        var planned: Int
        var favorite: Favorite?
    }
    struct Money: Codable, Hashable {
        var spentCents: Int
        var estimatedCents: Int
        var savedCents: Int
        var bonusCents: Int
        var budgetCents: Int
        var budgetOk: Bool
    }
    struct Health: Codable, Hashable, Identifiable {
        var memberId: Int
        var name: String
        var emoji: String
        var avgKcal: Int
        var kcalGoal: Int
        var avgProtein: Int
        var proteinGoal: Int
        var plants: Int
        var id: Int { memberId }
    }
    struct Pantry: Codable, Hashable {
        var restsUsed: Int
        var restsLeft: Int
        var thrownAway: Int?  // null = wird nicht erfasst → Kachel fehlt
    }
    struct Deal: Codable, Hashable, Identifiable {
        var offerId: Int
        var title: String
        var chain: String
        var imageUrl: String
        var priceCents: Int
        var regularPriceCents: Int
        var savingPct: Int
        var id: Int { offerId }
    }
    var week: String
    var kw: Int
    var start: String
    var end: String
    var cooking: Cooking
    var money: Money
    var health: [Health]
    var pantry: Pantry
    var achievements: [AchievementDTO]
    var nextWeek: [Deal]

    /// „2.–8. November“ (Monatswechsel: „30. Okt.–5. Nov.“ als „30.10.–5.11.“).
    var period: String {
        let a = start.split(separator: "-").compactMap { s in Int(s) }, b = end.split(separator: "-").compactMap { s in Int(s) }
        guard a.count == 3, b.count == 3 else { return "" }
        guard a[1] == b[1] else { return "\(a[2]).\(a[1]).–\(b[2]).\(b[1])." }
        return "\(a[2]).–\(b[2]). \(Month.name(String(end.prefix(7)), year: false))"
    }
}

/// = ReviewSummary (Archiv).
struct ReviewSummaryDTO: Codable, Hashable, Identifiable {
    var week: String
    var kw: Int
    var createdAt: String
    var spentCents: Int
    var cooked: Int
    var id: String { week }
}

/// = RecipeShareOut.
struct RecipeShareDTO: Codable, Hashable {
    var code: String
    var url: String
    var appUrl: String
}

/// = SharedRecipeOut (ohne Login).
struct SharedRecipeDTO: Codable, Hashable {
    var code: String
    var title: String
    var description: String
    var imageUrl: String
    var servings: Int
    var prepMinutes: Int
    var ingredients: [IngredientDTO]
    var steps: [String]
    var fromHousehold: String
}

// MARK: Server

extension AppStore {
    /// Alle Erfolge; neu Freigeschaltetes (`new`) → Vollbild-Moment.
    func achievements() async throws -> [AchievementDTO] {
        let all: [AchievementDTO] = demo ? Demo.achievements : try await api.request("GET", "/achievements")
        let fresh = all.filter(\.new)
        if !fresh.isEmpty, newAchievements.isEmpty { newAchievements = fresh }
        return all
    }

    func loadAchievements() async { _ = try? await achievements() }

    /// Nach dem Vollbild-Moment: nicht noch einmal zeigen.
    func achievementsSeen(_ keys: [String]) async {
        struct Body: Encodable { var keys: [String] }
        guard !demo, !keys.isEmpty else { return }
        _ = try? await api.send("POST", "/achievements/seen", body: Body(keys: keys))
    }

    /// Rückblick einer Woche ("" = aktuelle; legt ihn beim ersten Öffnen an).
    func review(_ week: String) async throws -> WeekReviewDTO {
        if demo { return Demo.review }
        return try await api.request("GET", week.isEmpty ? "/reviews/current" : "/reviews/\(week)", timeout: 60)
    }

    func reviews() async throws -> [ReviewSummaryDTO] {
        demo ? Demo.reviews : try await api.request("GET", "/reviews")
    }

    func shareRecipe(_ id: Int) async throws -> RecipeShareDTO {
        demo ? Demo.recipeShare : try await api.request("POST", "/recipes/\(id)/share")
    }

    func sharedRecipe(_ code: String) async throws -> SharedRecipeDTO {
        demo ? Demo.sharedRecipe : try await api.request("GET", "/shared-recipes/\(code)")
    }

    /// „Übernehmen“: Kopie im eigenen Haushalt (schon übernommen/eigenes → das vorhandene).
    func importShared(_ code: String) async throws -> RecipeDTO {
        let r: RecipeDTO = demo ? Demo.savedRecipe : try await api.request("POST", "/shared-recipes/\(code)/import", timeout: 60)
        recipesVersion += 1
        return r
    }

    /// Code aus dem Deep-Link prüfen (Vertrauensgrenze: kommt von außen).
    nonisolated static func validShareCode(_ code: String) -> Bool {
        (1...16).contains(code.count) && code.allSatisfy { c in c.isASCII && (c.isLetter || c.isNumber) }
    }
}

// MARK: S34 Erfolge

/// Medaille: freigeschaltet Orange-Verlauf, gesperrt grau mit Fortschrittsring.
struct Medal: View {
    let a: AchievementDTO
    var size: CGFloat = 76

    var body: some View {
        ZStack {
            if a.unlocked {
                Circle().fill(LinearGradient(colors: [Theme.C.highlight, Theme.C.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().strokeBorder(Theme.C.plate.opacity(0.6), lineWidth: size * 0.04).padding(size * 0.07)
            } else {
                Circle().fill(Theme.C.surface)
                GoalRing(fraction: a.fraction, color: Theme.C.accent, lineWidth: size * 0.06).padding(size * 0.04)
            }
            Text(a.emoji).font(.system(size: size * 0.42)).grayscale(a.unlocked ? 0 : 1).opacity(a.unlocked ? 1 : 0.45)
        }
        .frame(width: size, height: size)
        .shadow(color: a.unlocked ? Theme.C.accent.opacity(0.3) : .clear, radius: 8, y: 4)
        .accessibilityHidden(true)
    }
}

/// Profil › Erfolge: Raster Sparen (Haushalt) + Gesundheit (ich), Detail mit Datum bzw. Fortschritt.
struct AchievementsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var all: [AchievementDTO]?
    @State private var error: String?
    @State private var detail: AchievementDTO?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                DisplayHeader(line1: "Erfolge", line2: all.map { a in "\(a.filter(\.unlocked).count) von \(a.count) erreicht" } ?? "Sparen & Gesundheit")
                if let all {
                    ForEach([("sparen", "💰 Sparen · Haushalt"), ("gesundheit", "💪 Gesundheit · \(store.profile?.name ?? "ich")")], id: \.0) { g in
                        let items = all.filter { a in a.group == g.0 }
                        if !items.isEmpty {
                            Text(g.1).font(Theme.F.headline).padding(.top, 4)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), alignment: .center, spacing: 18) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { i, a in
                                    Button { detail = a } label: { cell(a) }
                                        .buttonStyle(PressableStyle())
                                        .appear(delay: Double(i) * 0.03)
                                }
                            }
                        }
                    }
                } else if let error {
                    ErrorState(message: error) { Task { await load() } }
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 18) {
                        ForEach(0..<9, id: \.self) { _ in SkeletonCard(height: 120) }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
        }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $detail) { a in AchievementDetail(a: a).presentationDetents([.medium]).presentationCornerRadius(Theme.R.sheet) }
    }

    private func cell(_ a: AchievementDTO) -> some View {
        VStack(spacing: 6) {
            Medal(a: a)
            Text(a.title).font(Theme.F.micro).foregroundStyle(a.unlocked ? Theme.C.text1 : Theme.C.text2)
                .multilineTextAlignment(.center).lineLimit(3).frame(minHeight: 40, alignment: .top)
            Text(a.unlockedAt.map(shortDate) ?? a.progressText).font(Theme.F.micro).monospacedDigit()
                .foregroundStyle(a.unlocked ? Theme.C.accentDeep : Theme.C.text3)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(a.title), \(a.unlocked ? "erreicht am \(shortDate(a.unlockedAt ?? ""))" : "gesperrt, \(a.progressText)")")
    }

    private func load() async {
        do {
            let a = try await store.achievements()
            withAnimation(Theme.spring) { all = a }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Detail: große Medaille, Datum bzw. Fortschritt.
struct AchievementDetail: View {
    let a: AchievementDTO

    var body: some View {
        VStack(spacing: 14) {
            Medal(a: a, size: 130).padding(.top, 24)
            Text(a.title).font(Theme.F.title).multilineTextAlignment(.center)
            if let at = a.unlockedAt {
                Label("Erreicht am \(shortDate(at))", systemImage: "checkmark.seal.fill").font(Theme.F.callout).foregroundStyle(Theme.C.success)
            } else {
                ProgressView(value: a.fraction).tint(Theme.C.accent).padding(.horizontal, 40)
                Text(a.progressText).font(.system(.headline, design: .rounded, weight: .bold)).monospacedDigit()
                Text(a.remainingText).font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.pagePadding)
        .frame(maxWidth: .infinity)
        .presentationBackground(Theme.C.bg)
    }
}

/// Vollbild-Moment beim Freischalten: Konfetti, Medaille fliegt ein, Haptik; danach POST /achievements/seen.
struct UnlockOverlay: View {
    @Environment(AppStore.self) private var store
    @State private var index = 0

    var body: some View {
        let list = store.newAchievements
        if list.indices.contains(index) {
            UnlockCard(a: list[index], step: index + 1, of: list.count) { next() }
                .id(list[index].key)  // neue Medaille → neuer Flug
                .transition(.opacity)
        }
    }

    private func next() {
        if index + 1 < store.newAchievements.count {
            withAnimation(Theme.spring) { index += 1 }
        } else {
            let keys = store.newAchievements.map(\.key)
            withAnimation(.easeOut(duration: 0.3)) { store.newAchievements = [] }
            Task { await store.achievementsSeen(keys) }
        }
    }
}

private struct UnlockCard: View {
    let a: AchievementDTO
    let step: Int
    let of: Int
    let done: () -> Void
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.C.heroDark.opacity(0.94).ignoresSafeArea()
            if !reduceMotion { Confetti().ignoresSafeArea().allowsHitTesting(false) }
            VStack(spacing: 14) {
                Text("Neuer Erfolg!").font(Theme.F.callout).foregroundStyle(.white.opacity(0.7))
                Medal(a: a, size: 170)
                    .scaleEffect(landed ? 1 : 0.2)
                    .rotationEffect(.degrees(landed ? 0 : -200))
                    .offset(y: landed ? 0 : -460)
                    .padding(.vertical, 10)
                Text(a.title).font(Theme.F.title).foregroundStyle(.white).multilineTextAlignment(.center)
                    .opacity(landed ? 1 : 0)
                Text(a.group == "sparen" ? "Sparen" : "Gesundheit").font(Theme.F.caption).foregroundStyle(.white.opacity(0.7))
                Button(step < of ? "Weiter (\(step)/\(of))" : "Super!", action: done)
                    .buttonStyle(AccentButtonStyle())
                    .padding(.top, 24)
            }
            .padding(Theme.pagePadding)
        }
        .sensoryFeedback(.success, trigger: landed)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.75, dampingFraction: 0.62).delay(0.15)) { landed = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: S35 Wochenrückblick (Story)

/// Zahl, die beim Erscheinen der Seite hochzählt.
struct CountUp: View {
    let value: Int
    let active: Bool
    var format: (Int) -> String = { n in "\(n)" }
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(format(shown)).monospacedDigit().contentTransition(.numericText(value: Double(shown)))
            .onChange(of: active, initial: true) { _, on in
                guard on else { shown = 0; return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 1).delay(0.2)) { shown = value }
            }
            .accessibilityLabel(format(value))
    }
}

/// Story-Seiten (wischen oder links/rechts tippen): Woche, Geld, Gesundheit, Vorrat, Erfolge, nächste Woche.
struct ReviewStoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let week: String
    var plan: () -> Void = {}
    @State private var review: WeekReviewDTO?
    @State private var error: String?
    @State private var page = 0
    @State private var sharing = false
    private let backgrounds = [Theme.C.accent, Theme.C.success, Theme.C.heroDark, Theme.C.accentDeep, Theme.C.heroDark, Theme.C.accent]

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [backgrounds[page], backgrounds[page].opacity(0.82)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.35), value: page)
            if let r = review {
                GeometryReader { geo in
                    TabView(selection: $page) {
                        ForEach(0..<6, id: \.self) { i in
                            pageView(i, r).tag(i)
                                .padding(.horizontal, 24).padding(.top, 96).padding(.bottom, 32)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .contentShape(Rectangle())
                    .onTapGesture { p in go(p.x < geo.size.width / 3 ? -1 : 1) }
                }
                .ignoresSafeArea(edges: .bottom)
            } else if let error {
                VStack(spacing: 14) {
                    Text("📡").font(.system(size: 52))
                    Text("Das hat nicht geklappt").font(Theme.F.headline)
                    Text(error).font(Theme.F.caption).opacity(0.8).multilineTextAlignment(.center)
                    Button("Erneut versuchen") { Task { await load() } }.buttonStyle(PrimaryButtonStyle())
                }
                .padding(32).frame(maxHeight: .infinity)
            } else {
                ProgressView().tint(.white).controlSize(.large).frame(maxHeight: .infinity)
            }
            topBar
        }
        .foregroundStyle(.white)
        .sensoryFeedback(.selection, trigger: page)
        .task { await load() }
        .sheet(isPresented: $sharing) {
            if let r = review {
                ImageShareSheet(name: "Wochenrückblick KW \(r.kw)") {
                    var photo: UIImage?
                    if let url = r.cooking.favorite.flatMap({ f in mediaURL(f.imageUrl) }), let loaded = try? await URLSession.shared.data(from: url) {
                        photo = UIImage(data: loaded.0)
                    }
                    return ImageShareSheet.snapshot(ReviewShareCard(review: r, photo: photo))
                }
                .presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet)
            }
        }
    }

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(0..<6, id: \.self) { i in
                    Capsule().fill(.white.opacity(i <= page ? 0.95 : 0.3)).frame(height: 3)
                }
            }
            .animation(Theme.spring, value: page)
            .accessibilityElement()
            .accessibilityLabel("Seite \(page + 1) von 6")
            HStack(spacing: 10) {
                Text(review.map { r in "📖 Wochenrückblick KW \(r.kw)" } ?? "📖 Wochenrückblick").font(Theme.F.callout)
                Spacer()
                if review != nil { roundButton("square.and.arrow.up", "Als Bild teilen") { sharing = true } }
                roundButton("xmark", "Schließen") { dismiss() }
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private func roundButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44).background(.white.opacity(0.18), in: Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    @ViewBuilder private func pageView(_ i: Int, _ r: WeekReviewDTO) -> some View {
        let on = page == i
        VStack(alignment: .leading, spacing: 16) {
            switch i {
            case 0: weekPage(r, on)
            case 1: moneyPage(r.money, on)
            case 2: healthPage(r.health, on)
            case 3: pantryPage(r.pantry, on)
            case 4: achievementsPage(r.achievements, on)
            default: nextPage(r.nextWeek)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func title(_ line1: String, _ line2: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(line1).font(Theme.F.display)
            Text(line2).font(Theme.F.callout).opacity(0.8)
        }
    }

    private func big(_ value: Int, _ on: Bool, format: @escaping (Int) -> String = { n in "\(n)" }) -> some View {
        CountUp(value: value, active: on, format: format)
            .font(.system(size: 84, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.5)
    }

    private func glassTile(_ emoji: String, _ value: Int, _ label: String, _ on: Bool, format: @escaping (Int) -> String = { n in "\(n)" }) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(emoji).font(.system(size: 26))
            CountUp(value: value, active: on, format: format).font(.system(.title, design: .rounded, weight: .bold))
            Text(label).font(Theme.F.caption).opacity(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func weekPage(_ r: WeekReviewDTO, _ on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Deine Woche", "KW \(r.kw) · \(r.period)")
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                big(r.cooking.cooked, on)
                Text(r.cooking.cooked == 1 ? "Gericht\ngekocht" : "Gerichte\ngekocht").font(Theme.F.headline)
            }
            Text("von \(r.cooking.planned) geplanten").font(Theme.F.callout).opacity(0.8)
            if let f = r.cooking.favorite {
                VStack(spacing: 8) {
                    Plate(url: mediaURL(f.imageUrl), size: 150, seed: f.title)
                        .scaleEffect(on ? 1 : 0.7).opacity(on ? 1 : 0)
                        .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.7).delay(0.3), value: on)
                    Text("Lieblingsgericht").font(Theme.F.micro).opacity(0.8)
                    Text(f.title).font(Theme.F.title).multilineTextAlignment(.center)
                    HStack(spacing: 2) { ForEach(0..<f.stars, id: \.self) { _ in Image(systemName: "star.fill") } }
                        .font(.system(size: 16)).foregroundStyle(Theme.C.warning)
                        .accessibilityLabel("\(f.stars) Sterne")
                }
                .frame(maxWidth: .infinity).padding(.top, 8)
            } else {
                Text("Bewertet Gerichte mit „Gekocht ★“ – dann steht hier euer Lieblingsgericht.").font(Theme.F.callout).opacity(0.85)
            }
        }
    }

    private func moneyPage(_ m: WeekReviewDTO.Money, _ on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Gespart &", "ausgegeben")
            Text("Ausgegeben").font(Theme.F.callout).opacity(0.8)
            big(m.spentCents, on, format: euro)
            if m.estimatedCents > 0 { Text("davon \(euro(m.estimatedCents)) geschätzt").font(Theme.F.caption).opacity(0.8) }
            HStack(spacing: 12) {
                glassTile("🏷️", m.savedCents, "durch Angebote", on, format: euro)
                glassTile("🎁", m.bonusCents, "Bonus", on, format: euro)
            }
            Label(m.budgetOk ? "Im Budget (\(euro(m.budgetCents)))" : "\(euro(m.spentCents - m.budgetCents)) über Budget",
                  systemImage: m.budgetOk ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(Theme.F.callout)
                .padding(.horizontal, 14).frame(minHeight: 40)
                .background(.white.opacity(0.18), in: Capsule())
        }
    }

    private func healthPage(_ health: [WeekReviewDTO.Health], _ on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Gesundheit", "Schnitt pro Tag")
            if health.isEmpty {
                Text("Für diese Woche gibt es noch keine Nährwerte.").font(Theme.F.callout).opacity(0.85)
            }
            ForEach(health) { h in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text(h.emoji).font(.system(size: 30))
                        Text(h.name).font(Theme.F.headline)
                        Spacer()
                        Text("🥦 \(h.plants) Pflanzen").font(Theme.F.callout)
                    }
                    bar("kcal", h.avgKcal, h.kcalGoal, Theme.C.kcal, on)
                    bar("g Protein", h.avgProtein, h.proteinGoal, Theme.C.protein, on)
                }
                .padding(16)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func bar(_ unit: String, _ value: Int, _ goal: Int, _ color: Color, _ on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ø \(num(Double(value))) / \(num(Double(goal))) \(unit)").font(Theme.F.caption).monospacedDigit()
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(color).frame(width: on && goal > 0 ? g.size.width * min(Double(value) / Double(goal), 1) : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.9).delay(0.2), value: on)
                }
            }
            .frame(height: 8)
        }
    }

    private func pantryPage(_ p: WeekReviewDTO.Pantry, _ on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Vorrat &", "Reste")
            HStack(spacing: 12) {
                glassTile("♻︎", p.restsUsed, "Reste verwendet", on)
                glassTile("🧊", p.restsLeft, "noch übrig", on)
            }
            if let thrown = p.thrownAway { glassTile("🗑️", thrown, "weggeworfen", on) }
            Text(p.restsUsed > 0 ? "Angebrochenes landet im nächsten Gericht statt im Müll." : "Reste plant der Generator automatisch ein.")
                .font(Theme.F.callout).opacity(0.85)
        }
    }

    private func achievementsPage(_ list: [AchievementDTO], _ on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Neue Erfolge", list.isEmpty ? "diese Woche" : "\(list.count) diese Woche")
            if list.isEmpty {
                Text("🏅").font(.system(size: 64))
                Text("Diese Woche kein neuer Erfolg – nächste Woche klappt’s!").font(Theme.F.callout).opacity(0.85)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, a in
                        VStack(spacing: 8) {
                            Medal(a: a, size: 92)
                                .scaleEffect(on ? 1 : 0.3).opacity(on ? 1 : 0)
                                .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.6).delay(0.15 + Double(i) * 0.12), value: on)
                            Text(a.title).font(Theme.F.micro).multilineTextAlignment(.center).lineLimit(3)
                        }
                    }
                }
            }
        }
        .overlay { if on && !list.isEmpty && !reduceMotion { Confetti().allowsHitTesting(false).padding(-40) } }
    }

    private func nextPage(_ deals: [WeekReviewDTO.Deal]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            title("Nächste Woche", "günstig")
            if deals.isEmpty {
                Text("Die Prospekte für nächste Woche kommen meist ab Donnerstag.").font(Theme.F.callout).opacity(0.85)
            }
            ForEach(deals) { d in
                HStack(spacing: 12) {
                    RemoteImage(url: URL(string: d.imageUrl)) { Text("🏷️").font(.system(size: 24)) }
                        .padding(6).frame(width: 52, height: 52).background(Theme.C.plate, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(d.title).font(Theme.F.callout).lineLimit(2)
                        HStack(spacing: 6) {
                            StoreLogo(chain: d.chain, size: 18)
                            Text("\(euro(d.priceCents)) statt \(euro(d.regularPriceCents))").font(Theme.F.micro).monospacedDigit().opacity(0.85)
                        }
                    }
                    Spacer(minLength: 4)
                    Text("−\(d.savingPct) %").font(.system(.subheadline, design: .rounded, weight: .bold))
                        .padding(.horizontal, 10).frame(height: 28).background(.white.opacity(0.2), in: Capsule())
                }
                .padding(12)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
                .accessibilityElement(children: .combine)
            }
            Button {
                dismiss()
                plan()
            } label: { Label("Plan erstellen", systemImage: "sparkles") }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 8)
        }
    }

    private func go(_ n: Int) {
        let target = page + n
        guard (0..<6).contains(target) else { return }
        withAnimation(Theme.spring) { page = target }
    }

    private func load() async {
        do {
            let r = try await store.review(week)
            withAnimation(Theme.spring) { review = r }
            error = nil
        } catch APIError.http(404) {
            error = "Für diese Woche gibt es keinen Rückblick."
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Bildkarte des Rückblicks (immer hell, 1080×1350 px wie Feature 10).
struct ReviewShareCard: View {
    let review: WeekReviewDTO
    let photo: UIImage?

    var body: some View {
        let r = review
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Meine Woche").font(.system(.title2, weight: .bold))
                Text("KW \(r.kw) · \(r.period)").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            }
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    tile("🍳", "\(r.cooking.cooked)", "gekocht")
                    tile("💰", euro(r.money.savedCents + r.money.bonusCents), "gespart")
                }
                GridRow {
                    tile("🥦", "\(r.health.map(\.plants).max() ?? 0)", "Pflanzen")
                    tile("🏅", "\(r.achievements.count)", r.achievements.count == 1 ? "neuer Erfolg" : "neue Erfolge")
                }
            }
            if let f = r.cooking.favorite {
                HStack(spacing: 12) {
                    Group {
                        if let photo {
                            Image(uiImage: photo).resizable().scaledToFill().frame(width: 72, height: 72).clipShape(Circle())
                        } else {
                            Plate(url: nil, size: 72, seed: f.title)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lieblingsgericht").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                        Text(f.title).font(Theme.F.callout).lineLimit(2)
                        Text(String(repeating: "★", count: f.stars)).font(Theme.F.micro).foregroundStyle(Theme.C.warning)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).card(radius: Theme.R.tile)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                AppIconMark()
                Text("Mit Kochpilot geplant").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            }
        }
        .padding(22)
        .frame(width: 360, height: 450)
        .background(Theme.C.bg)
        .foregroundStyle(Theme.C.text1)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.colorScheme, .light)
    }

    private func tile(_ emoji: String, _ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(emoji).font(.system(size: 20))
            Text(value).font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(Theme.F.micro).foregroundStyle(Theme.C.text2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .card(radius: Theme.R.tile)
    }
}

/// Start-Karte „📖 Wochenrückblick KW 45“ → Story; „Archiv“; ab Sonntag beim ersten Öffnen einmal automatisch.
struct ReviewCard: View {
    @Environment(AppStore.self) private var store
    @State private var r: WeekReviewDTO?

    var body: some View {
        VStack(spacing: 0) {
            if let r {
                HStack(spacing: 10) {
                    Button { store.review = r.week } label: {
                        HStack(spacing: 14) {
                            Text("📖").font(.system(size: 26)).frame(width: 52, height: 52)
                                .background(Theme.C.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Wochenrückblick KW \(r.kw)").font(Theme.F.callout).foregroundStyle(Theme.C.text1)
                                Text("\(r.cooking.cooked) gekocht · \(euro(r.money.savedCents + r.money.bonusCents)) gespart")
                                    .font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    NavigationLink { ReviewArchiveView() } label: {
                        Text("Archiv").font(Theme.F.callout).foregroundStyle(Theme.C.accentDeep)
                            .padding(.horizontal, 12).frame(minHeight: 44)
                    }
                    .accessibilityLabel("Alle Wochenrückblicke")
                }
                .padding(16)
                .card()
                .transition(.opacity)
            }
        }
        .animation(Theme.spring, value: r)
        .task {
            guard let fresh = try? await store.review("") else { return }
            r = fresh
            // ab Sonntag (55): beim ersten Öffnen der Woche die Story einmal von selbst
            let sunday = Calendar.current.component(.weekday, from: .now) == 1
            if sunday, !store.demo, UserDefaults.standard.string(forKey: "reviewShown") != fresh.week {
                UserDefaults.standard.set(fresh.week, forKey: "reviewShown")
                store.review = fresh.week
            }
        }
    }
}

/// Archiv aller Rückblicke (Push aus der Start-Karte).
struct ReviewArchiveView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [ReviewSummaryDTO]?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                DisplayHeader(line1: "Rückblicke", line2: rows.map { r in "\(r.count) Wochen" } ?? "Archiv")
                if let rows {
                    if rows.isEmpty {
                        EmptyState(emoji: "📖", title: "Noch kein Rückblick", text: "Der erste kommt am Sonntag um 19 Uhr.")
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        Button { store.review = row.week } label: {
                            HStack(spacing: 14) {
                                Text("KW\n\(row.kw)").font(.system(.subheadline, design: .rounded, weight: .bold)).multilineTextAlignment(.center)
                                    .foregroundStyle(Theme.C.accentDeep)
                                    .frame(width: 52, height: 52).background(Theme.C.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Woche \(row.kw) · \(String(row.week.prefix(4)))").font(Theme.F.callout).foregroundStyle(Theme.C.text1)
                                    Text("\(row.cooked) gekocht · \(euro(row.spentCents)) ausgegeben").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.C.text3)
                            }
                            .padding(12).card(radius: Theme.R.tile)
                        }
                        .buttonStyle(PressableStyle())
                        .appear(delay: Double(i) * 0.04)
                    }
                } else if let error {
                    ErrorState(message: error) { Task { await load() } }
                } else {
                    ForEach(0..<4, id: \.self) { _ in SkeletonCard(height: 76) }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
        }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            let r = try await store.reviews()
            withAnimation(Theme.spring) { rows = r }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: S36/S37 Rezept als Link teilen, geteiltes Rezept übernehmen

/// Rezept › Teilen › „Als Link teilen“: Link /r/<code> erzeugen, teilen oder kopieren.
struct RecipeLinkSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let recipeId: Int
    let title: String
    @State private var link: RecipeShareDTO?
    @State private var error: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Als Link teilen").font(Theme.F.title)
                Spacer()
                RoundIconButton(systemName: "xmark", label: "Schließen") { dismiss() }
            }
            Text("Wer den Link öffnet, sieht Foto, Zutaten und Schritte – mit Kochpilot lässt sich „\(title)“ in die eigenen Rezepte übernehmen.")
                .font(Theme.F.caption).foregroundStyle(Theme.C.text2).fixedSize(horizontal: false, vertical: true)
            if let link, let url = URL(string: link.url) {
                Label { Text(link.url).font(.system(.footnote, design: .monospaced)).lineLimit(2).textSelection(.enabled) } icon: {
                    Image(systemName: "link").foregroundStyle(Theme.C.accent)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).card(radius: Theme.R.tile)
                .transition(.opacity)
                ShareLink(item: url, subject: Text(title), message: Text("Rezept „\(title)“ aus unserem Kochpilot:")) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle())
                Button {
                    UIPasteboard.general.string = link.url
                    withAnimation(Theme.spring) { copied = true }
                } label: { Label(copied ? "Kopiert ✓" : "Link kopieren", systemImage: copied ? "checkmark" : "doc.on.doc") }
                .buttonStyle(SecondaryButtonStyle())
                .sensoryFeedback(.success, trigger: copied)
            } else if let error {
                ErrorState(message: error) { Task { await load() } }
            } else {
                SkeletonCard(height: 56)
                SkeletonCard(height: 54)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.pagePadding)
        .presentationBackground(Theme.C.bg)
        .task { await load() }
    }

    private func load() async {
        do {
            let l = try await store.shareRecipe(recipeId)
            withAnimation(Theme.spring) { link = l }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Deep-Link essenapp://import-recipe/<code>: Vorschau + „Übernehmen“ (Kopie mit Quelle „von Familie Müller“).
struct SharedRecipeSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let code: String
    let opened: (Int) -> Void
    @State private var recipe: SharedRecipeDTO?
    @State private var error: String?
    @State private var notFound = false
    @State private var saving = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text("Geteiltes Rezept").font(Theme.F.headline)
                    Spacer()
                    RoundIconButton(systemName: "xmark", label: "Schließen") { dismiss() }
                }
                if let r = recipe {
                    Plate(url: mediaURL(r.imageUrl), size: 180, seed: r.title).padding(.vertical, 6).appear()
                    Text(r.title).font(Theme.F.title).multilineTextAlignment(.center)
                    Label("von \(r.fromHousehold)", systemImage: "person.2.fill").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                        .padding(.horizontal, 10).frame(height: 28).background(Theme.C.surface, in: Capsule())
                    HStack(spacing: 14) {
                        Label("\(r.prepMinutes) min", systemImage: "clock")
                        Label("\(r.servings) Portionen", systemImage: "person.2")
                        Label("\(r.steps.count) Schritte", systemImage: "list.number")
                    }
                    .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                    if !r.description.isEmpty {
                        Text(r.description).font(Theme.F.body).foregroundStyle(Theme.C.text2).multilineTextAlignment(.center)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Zutaten").font(Theme.F.headline)
                        ForEach(Array(r.ingredients.enumerated()), id: \.offset) { _, ing in
                            HStack {
                                Text(ing.name)
                                Spacer()
                                Text(qty(ing.amount, ing.unit)).monospacedDigit().foregroundStyle(Theme.C.text2)
                            }
                            .font(Theme.F.body)
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
                } else if notFound {
                    EmptyState(emoji: "🤷", title: "Rezept-Link ungültig", text: "Der Link stimmt nicht oder das Rezept wurde gelöscht.")
                } else if let error {
                    ErrorState(message: error) { Task { await load() } }
                } else {
                    SkeletonCard(height: 200)
                    SkeletonCard(height: 160)
                }
            }
            .padding(.horizontal, Theme.pagePadding).padding(.top, Theme.pagePadding)
        }
        .background(Theme.C.bg)
        .ctaBar(bottom: 16) {
            if let r = recipe {
                Button { take(r) } label: { Label(saving ? "Übernehme …" : "Übernehmen", systemImage: "tray.and.arrow.down.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(saving)
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let r = try await store.sharedRecipe(code)
            withAnimation(Theme.spring) { recipe = r }
            error = nil
        } catch APIError.http(404) {
            notFound = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func take(_ r: SharedRecipeDTO) {
        saving = true
        Task {
            defer { saving = false }
            do {
                let copy = try await store.importShared(code)
                store.flash("„\(r.title)“ liegt jetzt in deinen Rezepten")
                dismiss()
                opened(copy.id)
            } catch {
                store.flash("Nicht übernommen: \(error.localizedDescription)")
            }
        }
    }
}
