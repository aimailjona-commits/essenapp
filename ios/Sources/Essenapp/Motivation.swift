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

    private var unitLabel: String {
        ["wochen": "Wochen", "angebote": "Angebote", "tipps": "Tipps", "tage": "Tage", "pflanzen": "Pflanzen"][unit] ?? unit
    }

    /// „34“ und „ / 50 €“ (große Zahl + kleinere Einheit im Sheet).
    var progressValue: String { num(unit == "cent" ? progress / 100 : progress, 0...0) }
    var progressRest: String { unit == "cent" ? " / \(num(Double(target) / 100, 0...0)) €" : " / \(target) \(unitLabel)" }

    /// „34 / 50 €“, „2 / 4 Wochen“.
    var progressText: String { progressValue + progressRest }

    /// „16 €“, „2 Wochen“ (Rest bis zum Ziel).
    var remainingValue: String {
        let left = max(Double(target) - progress, 0)
        return unit == "cent" ? "\(num(left / 100, 0...0)) €" : "\(num(left, 0...0)) \(unitLabel)"
    }

    /// „Noch 16 € bis zum Ziel“.
    var remainingText: String { "Noch \(remainingValue) bis zum Ziel" }
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

extension AchievementDTO {
    /// „Budget-Wächter: 4 Wochen in Folge im Budget“ → Name „Budget-Wächter“, Bedingung „4 Wochen in Folge im Budget“.
    var name: String { String(title.split(separator: ":", maxSplits: 1).first ?? Substring(title)).trimmingCharacters(in: .whitespaces) }
    var detail: String? {
        let p = title.split(separator: ":", maxSplits: 1)
        return p.count == 2 ? p[1].trimmingCharacters(in: .whitespaces) : nil
    }

    /// Linien-Icon der Medaille (Mockup: Plan cal, gespart tag/trophy, Bonus gift, Budget check, Reste box, Gesundheit leaf).
    var icon: Icon8 {
        let kind = key.split(separator: "_").first.map(String.init) ?? key
        switch kind {
        case "gespart": return target < 10000 ? .tag : .trophy
        case "budget": return .check
        case "bestpreis": return .sparkle
        case "vorrat", "reste", "rest": return .box
        case "bonus": return .gift
        case "plan": return .cal
        case "protein": return .fork
        case "pflanzen": return .leaf
        case "ausgewogen": return .chart
        default: return .trophy
        }
    }

    var groupLabel: String { group == "sparen" ? "Sparen · Haushalt" : "Gesundheit" }
}

/// Medaille (`.f-m`): erreicht als Pastell-Kreis (Sparen blau, Gesundheit salbei) mit weißem Innenring,
/// gesperrt als grauer Ring, der sich mit dem Fortschritt in `blue3` füllt.
struct Medal: View {
    let a: AchievementDTO
    var size: CGFloat = 76
    var ring: CGFloat = 4  // Ringstärke gesperrt, in 76er-Einheiten (Sheet: 3)
    var lockedFill: Color = .clear

    var body: some View {
        let k = size / 76
        ZStack {
            if a.unlocked {
                Circle().fill(a.group == "gesundheit" ? Theme.C.sage : Theme.C.blue)
                Circle().strokeBorder(Theme.C.onInk.opacity(0.55), lineWidth: 5 * k)
            } else {
                Circle().fill(lockedFill)
                Circle().stroke(Theme.C.line, lineWidth: ring * k).frame(width: 70 * k, height: 70 * k)
                Circle().trim(from: 0, to: a.fraction)
                    .stroke(Theme.C.blue3, style: StrokeStyle(lineWidth: ring * k, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 70 * k, height: 70 * k)
            }
            Icon(a.icon, size: 30 * k).foregroundStyle(a.unlocked ? Theme.C.ink : Theme.C.ink3)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Profil › Erfolge (S34): „5/18“ riesig auf dem Pastell-Kreis, Sparen-Medaillen in 3 Spalten, Gesundheit als Zusammenfassungs-Zeile.
struct AchievementsView: View {
    @Environment(AppStore.self) private var store
    @State private var all: [AchievementDTO]?
    @State private var error: String?
    @State private var detail: AchievementDTO?
    @State private var health = false

    // Mockup S34: Kreis 340 bei x 190 / y −60
    private enum L { static let blob: CGFloat = 340, blobRight: CGFloat = 390 - 190 - 340, blobTop: CGFloat = -60 - 52 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackButton8()
                Text("Mein Profil").font(Theme.F.small).foregroundStyle(Theme.C.ink2).padding(.top, 34)
                Text("Erfolge").font(Theme.F.t1)
                if let all {
                    content(all)
                } else if let error {
                    ErrorBlock8(message: error) { Task { await load() } }.padding(.top, 20)
                } else {
                    Skeleton8(height: 120).padding(.top, 20)
                    grid(Array(0..<6).map { i in i }) { _ in Skeleton8(width: 76, height: 76).clipShape(Circle()) }.padding(.top, 54)
                }
            }
            .padding(.horizontal, Theme.pagePadding).padding(.top, 14).padding(.bottom, Theme.S.nav)
            .frame(maxWidth: .infinity, alignment: .leading)
            .edgeForm(.circle, Theme.C.blue1, width: L.blob, height: L.blob, right: L.blobRight, top: L.blobTop)
        }
        .scrollClipDisabled()
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $detail) { a in AchievementDetail(a: a).presentationDetents([.medium, .large]) }
    }

    @ViewBuilder private func content(_ all: [AchievementDTO]) -> some View {
        let saving = all.filter { a in a.group == "sparen" }
        let fit = all.filter { a in a.group == "gesundheit" }
        StatF(label: "Erreicht", value: "\(all.filter(\.unlocked).count)", unit: "/\(all.count)", size: 120, unitSize: 44,
              unitColor: Theme.C.ink2, roll: 0)
            .padding(.top, 20)
        if !saving.isEmpty {
            SecHead("Sparen · Haushalt").padding(.top, 36)
            grid(saving, cell).padding(.top, 18)
        }
        if !fit.isEmpty {
            Button { withAnimation(Theme.spring) { health.toggle() } } label: {
                HStack(spacing: 14) {
                    Icon(.leaf).foregroundStyle(Theme.C.ink)
                        .frame(width: Theme.S.rowCircle, height: Theme.S.rowCircle).background(Theme.C.sage, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Gesundheit · \(store.profile?.name ?? "ich")").font(Theme.F.rowName).foregroundStyle(Theme.C.ink)
                        Text("\(fit.filter(\.unlocked).count) von \(fit.count) erreicht").font(Theme.F.text(12, .semibold, relativeTo: .caption))
                            .foregroundStyle(Theme.C.ink2)
                    }
                    Spacer(minLength: 8)
                    Icon(.chev, size: 18).foregroundStyle(Theme.C.ink2).rotationEffect(.degrees(health ? 90 : 0))
                }
                .frame(minHeight: 64)
                .overlay(alignment: .top) { Hairline() }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityValue(health ? "aufgeklappt" : "zugeklappt")
            .padding(.top, 36)
            if health { grid(fit, cell).padding(.top, 18).transition(.opacity) }
        }
    }

    private func grid<T: Hashable, C: View>(_ items: [T], _ cell: @escaping (T) -> C) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), alignment: .center, spacing: 28) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, x in cell(x).appear(delay: Double(i) * 0.03) }
        }
    }

    private func cell(_ a: AchievementDTO) -> some View {
        Button { detail = a } label: {
            VStack(spacing: 0) {
                Medal(a: a)
                Text(a.name).font(Theme.F.text(13, .bold, relativeTo: .footnote)).lineSpacing(2)
                    .foregroundStyle(a.unlocked ? Theme.C.ink : Theme.C.ink3)
                    .multilineTextAlignment(.center).padding(.top, 8)
                if !a.unlocked {
                    Text(a.progressText).font(Theme.F.text(11, .extrabold, relativeTo: .caption2)).foregroundStyle(Theme.C.ink3).padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(a.title), \(a.unlocked ? "erreicht am \(shortDate(a.unlockedAt ?? ""))" : "gesperrt, \(a.progressText)")")
        .accessibilityAddTraits(.isButton)
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

/// Erfolg-Sheet (S34): Medaille 130 im Halbkreis, Name, Bedingung, „34 / 50 €“ mit dickem Balken und „Noch 16 € bis zum Ziel“.
/// Erreichte Erfolge zeigen statt Fortschritt das Datum (ohne Mockup).
struct AchievementDetail: View {
    let a: AchievementDTO
    @Environment(\.dismiss) private var dismiss

    // Mockup: Kreis 260 im Sheet bei x 65 / y −70 (über der Sheet-Kante, wird abgeschnitten)
    private enum L { static let blob: CGFloat = 260, blobTop: CGFloat = -70 - 33 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(a.groupLabel)
                Spacer()
                CloseButton { dismiss() }.background(Circle().fill(Theme.C.bg).frame(width: Theme.S.close, height: Theme.S.close))
            }
            Medal(a: a, size: 130, ring: 3, lockedFill: Theme.C.bg).frame(maxWidth: .infinity)
            Text(a.name).font(Theme.F.t2).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 22)
            if let d = a.detail {
                Text(d).font(Theme.F.text(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 4)
            }
            if let at = a.unlockedAt {
                StatF(label: "Erreicht am", value: shortDate(at), size: 48).padding(.top, 22)
            } else {
                StatF(label: "Fortschritt", value: a.progressValue, unit: a.progressRest, size: 48, unitSize: 24, unitColor: Theme.C.ink2)
                    .padding(.top, 22)
                Capsule().fill(Theme.C.line).frame(height: 12)
                    .overlay(alignment: .leading) { GeometryReader { g in Capsule().fill(Theme.C.ink).frame(width: g.size.width * a.fraction) } }
                    .clipShape(Capsule())
                    .padding(.top, 10)
                    .accessibilityHidden(true)
                (Text("Noch ") + Text(a.remainingValue).foregroundStyle(Theme.C.ink).font(Theme.F.text(14, .extrabold, relativeTo: .subheadline))
                    + Text(" bis zum Ziel"))
                    .font(Theme.F.text(14, .semibold, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2).padding(.top, 10)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .pinned(top: L.blobTop) {
            Circle().fill(Theme.C.blue1).frame(width: L.blob, height: L.blob).frame(maxWidth: .infinity).accessibilityHidden(true)
        }
        .sheet8()
    }
}

/// Vollbild-Moment beim Freischalten; danach POST /achievements/seen.
struct UnlockOverlay: View {
    @Environment(AppStore.self) private var store
    @State private var index = 0

    var body: some View {
        let list = store.newAchievements
        if list.indices.contains(index) {
            UnlockCard(a: list[index], name: store.profile?.name, step: index + 1, of: list.count) { next() }
                .id(list[index].key)  // neue Medaille → neuer Auftritt
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

/// „Neuer Erfolg“ (Mockup f.html + Animation a2-win): blauer Kreis wächst von unten (0,7 s), Medaille fällt mit halber Drehung
/// und federt (0,8 s ab 0,25 s), beim Aufprall Konfetti (2,4 s), „Neuer Erfolg!“ tippt sich ein, Texte gleiten herein.
/// Bewegung reduzieren: alles blendet in 0,3 s über, kein Konfetti.
private struct UnlockCard: View {
    let a: AchievementDTO
    let name: String?
    let step: Int
    let of: Int
    let done: () -> Void
    @State private var start = Date.now
    @State private var finished = false
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Mockup-Koordinaten (390 breit, von der Bildschirm-Oberkante); x relativ zur Mitte 195
    private enum L {
        static let blob: CGFloat = 610, blobX: CGFloat = -110, blobY: CGFloat = 190
        static let medal: CGFloat = 170, medalX: CGFloat = 110, medalY: CGFloat = 280
        static let text: CGFloat = 560, hello: CGFloat = 96, bottom: CGFloat = 40
        static let land = 0.69  // Aufprall: Konfetti, Haptik, Tippen
    }
    private static let drop = Keyframes(stops: [
        (0, [-480, -160], Bezier(x1: 0.5, y1: 0, x2: 0.9, y2: 0.5)),
        (0.55, [0, 10], Bezier(x1: 0, y1: 0, x2: 0.58, y2: 1)),
        (0.72, [-22, -4], Bezier(x1: 0.42, y1: 0, x2: 1, y2: 1)),
        (0.86, [0, 2], .ease),
        (1, [0, 0], .ease),
    ])
    private static let grow = Bezier(x1: 0.3, y1: 1.2, x2: 0.5, y2: 1)
    private static let slide = Bezier(x1: 0.3, y1: 1.4, x2: 0.5, y2: 1)
    private static let headline = "Neuer Erfolg!"

    var body: some View {
        GeometryReader { g in
            let cx = g.size.width / 2 - 195
            TimelineView(.animation(paused: finished)) { ctx in
                let t = finished ? 10 : ctx.date.timeIntervalSince(start)
                let fade = min(max(t / 0.3, 0), 1)
                ZStack(alignment: .topLeading) {
                    Theme.C.bg
                    let p = Self.grow(min(t / 0.7, 1))
                    Circle().fill(Theme.C.blue).frame(width: L.blob, height: L.blob)
                        .scaleEffect(reduceMotion ? 1 : 0.2 + 0.8 * p)
                        .offset(x: cx + L.blobX, y: L.blobY + (reduceMotion ? 0 : 430 * (1 - p)))
                        .opacity(reduceMotion ? fade : 1)
                    if !reduceMotion && t >= L.land {
                        ConfettiBurst(t: t - L.land).offset(x: cx + 195, y: 365)
                    }
                    let d = Self.drop(min(max((t - 0.25) / 0.8, 0), 1))
                    medal
                        .rotationEffect(.degrees(reduceMotion ? 0 : d[1]))
                        .offset(x: cx + L.medalX, y: L.medalY + (reduceMotion ? 0 : d[0]))
                        .opacity(reduceMotion ? fade : 1)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(name.map { n in "Glückwunsch, \(n)" } ?? "Glückwunsch").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                            .modifier(SlideIn(e: reveal(t, 0)))
                        let chars = reduceMotion ? Self.headline.count : min(max(Int((t - L.land) / 0.055) + 1, 0), Self.headline.count)
                        Text(Self.headline.prefix(chars)).font(Theme.F.serif(42, relativeTo: .largeTitle)).frame(minHeight: 47, alignment: .leading)
                            .accessibilityLabel(Self.headline)
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .offset(y: L.hello)
                    VStack(spacing: 0) {
                        SectionLabel(a.group == "sparen" ? "Sparen · Haushalt" : "Gesundheit · \(name ?? "ich")")
                            .foregroundStyle(Theme.C.ink).modifier(SlideIn(e: reveal(t, 8)))
                        Text(a.name).font(Theme.F.t1).multilineTextAlignment(.center).padding(.top, 6).modifier(SlideIn(e: reveal(t, 9)))
                        if let detail = a.detail {
                            Text(detail).font(Theme.F.text(15, .semibold, relativeTo: .subheadline)).multilineTextAlignment(.center)
                                .padding(.top, 6).modifier(SlideIn(e: reveal(t, 10)))
                        }
                    }
                    .frame(width: g.size.width - 2 * Theme.pagePadding)
                    .offset(x: Theme.pagePadding, y: L.text)
                }
                .frame(width: g.size.width, height: g.size.height + g.safeAreaInsets.top + g.safeAreaInsets.bottom, alignment: .topLeading)
                .offset(y: -g.safeAreaInsets.top)
            }
            .overlay(alignment: .bottom) {
                PrimaryButton(title: step < of ? "Weiter (\(step)/\(of))" : "Super!", action: done)
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.bottom, max(L.bottom - g.safeAreaInsets.bottom, 0))
                    .opacity(landed || reduceMotion ? 1 : 0)
                    .offset(y: landed || reduceMotion ? 0 : 26)
                    .animation(.timingCurve(0.3, 1.4, 0.5, 1, duration: 0.5).delay(0.18 + 13 * 0.05), value: landed)
            }
        }
        .foregroundStyle(Theme.C.ink)
        .sensoryFeedback(.success, trigger: landed)
        .task {
            start = .now
            try? await Task.sleep(for: .milliseconds(Int(L.land * 1000)))
            landed = true
            try? await Task.sleep(for: .seconds(3))
            finished = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var medal: some View {
        ZStack {
            Circle().fill(a.group == "gesundheit" ? Theme.C.sage : Theme.C.blue)
            Circle().strokeBorder(Theme.C.onInk.opacity(0.6), lineWidth: 9)
            Icon(a.icon, size: 72).foregroundStyle(Theme.C.ink)
        }
        .frame(width: L.medal, height: L.medal)
        .plateShadow()
    }

    /// Fortschritt eines `.a2-in`-Elements (Verzögerung 0,18 s + i · 0,05 s nach dem Aufprall); nil = sofort da.
    private func reveal(_ t: Double, _ i: Double) -> Double? {
        reduceMotion ? nil : t - L.land - 0.18 - i * 0.05
    }

    private struct SlideIn: ViewModifier {
        let e: Double?

        func body(content: Content) -> some View {
            let e = e ?? 1
            content.opacity(min(max(e / 0.3, 0), 1)).offset(y: 26 * (1 - UnlockCard.slide(min(max(e / 0.5, 0), 1))))
        }
    }
}

/// Konfetti `a2-burst` (2,4 s): kleine Pastell-Formen fliegen aus der Mitte, drehen sich und fallen sanft.
struct ConfettiBurst: View {
    let t: Double  // Sekunden seit dem Aufprall

    private struct Piece {
        let dx, dy, r, w, h: CGFloat
        let kind: EdgeForm.Kind
        let color: Color
    }
    private static let pieces: [Piece] = [
        Piece(dx: -130, dy: -120, r: 24, w: 12, h: 12, kind: .circle, color: Theme.C.ink),
        Piece(dx: 120, dy: -140, r: -30, w: 18, h: 9, kind: .arch, color: Theme.C.rose),
        Piece(dx: 150, dy: -30, r: 24, w: 16, h: 12, kind: .leaf(12), color: Theme.C.sage),
        Piece(dx: -160, dy: 10, r: 24, w: 16, h: 16, kind: .circle, color: Theme.C.sand),
        Piece(dx: -90, dy: -170, r: -20, w: 14, h: 14, kind: .quarter, color: Theme.C.card),
        Piece(dx: 60, dy: -180, r: 24, w: 8, h: 8, kind: .circle, color: Theme.C.card),
        Piece(dx: -150, dy: 90, r: 24, w: 20, h: 10, kind: .arch, color: Theme.C.sage),
        Piece(dx: 140, dy: 80, r: -24, w: 18, h: 14, kind: .leaf(12), color: Theme.C.rose),
        Piece(dx: 100, dy: 150, r: 24, w: 10, h: 10, kind: .circle, color: Theme.C.ink),
        Piece(dx: -70, dy: 150, r: 24, w: 16, h: 16, kind: .quarter, color: Theme.C.rose),
        Piece(dx: 30, dy: -200, r: -18, w: 16, h: 8, kind: .arch, color: Theme.C.sand),
        Piece(dx: 165, dy: -100, r: 24, w: 12, h: 12, kind: .circle, color: Theme.C.sage),
    ]
    private static let out = Bezier(x1: 0.2, y1: 0.8, x2: 0.3, y2: 1)
    // Werte: Weg-Anteil, Fall, Größe, Drehung-Anteil
    private static let move = Keyframes(stops: [(0, [0, 0, 0.2, 0], out), (0.4, [1, 0, 1, 1], .easeInOut), (1, [1, 140, 1, 0], .easeInOut)])
    private static let fade = Keyframes(stops: [(0, [0], out), (0.08, [1], out), (0.4, [1], .easeInOut), (1, [0], .easeInOut)])

    var body: some View {
        let q = min(max(t / 2.4, 0), 1)
        let v = Self.move(q), o = Self.fade(q)[0]
        ZStack(alignment: .topLeading) {
            ForEach(Self.pieces.indices, id: \.self) { i in
                let p = Self.pieces[i]
                EdgeForm(p.kind).fill(p.color).frame(width: p.w, height: p.h)
                    .scaleEffect(v[2]).rotationEffect(.degrees(p.r * v[3]))
                    .offset(x: p.dx * v[0], y: p.dy * v[0] + v[1])
                    .opacity(o)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: S35 Wochenrückblick (Story)

/// Seitenfarben der Story: Pastell plus dunklere Form aus dem Rand (Mockup f.html).
/// shortcut: die vier dunkleren Töne stehen nur im Mockup, nicht in Theme.swift – dorthin verschieben, sobald die Hauptsession es freigibt.
private enum StoryTint {
    static let blue = Color(hex: 0x97AFE8)
    static let sage = Color(hex: 0xB3D2B8)
    static let rose = Color(hex: 0xE8B5AB)
    static let sand = Color(hex: 0xD7C6A4)
    static let pages: [(bg: Color, form: Color)] = [
        (Theme.C.blue, blue), (Theme.C.sage, sage), (Theme.C.rose, rose),
        (Theme.C.blue1, Theme.C.blue), (Theme.C.warn, Theme.C.sand),  // Seiten 4/5 ohne Mockup
        (Theme.C.sand, sand),
    ]
}

extension WeekReviewDTO {
    /// „3.–9. Nov“ bzw. über den Monatswechsel „27. Okt – 2. Nov“.
    static func periodShort(_ a: Date, _ b: Date) -> String {
        let cal = Calendar(identifier: .iso8601)
        guard cal.component(.month, from: a) == cal.component(.month, from: b) else { return "\(Month.short(a)) – \(Month.short(b))" }
        return "\(cal.component(.day, from: a)).–\(Month.short(b))"
    }

    /// Montag und Sonntag einer ISO-Woche „2026-W45“.
    static func days(_ week: String) -> (Date, Date)? {
        let p = week.split(separator: "-W").compactMap { s in Int(s) }
        let cal = Calendar(identifier: .iso8601)
        guard p.count == 2, let mon = cal.date(from: DateComponents(weekday: 2, weekOfYear: p[1], yearForWeekOfYear: p[0])),
              let sun = cal.date(byAdding: .day, value: 6, to: mon) else { return nil }
        return (mon, sun)
    }

    var periodShort: String {
        guard let a = Month.day(start), let b = Month.day(end) else { return period }
        return Self.periodShort(a, b)
    }
}

/// Story in sechs Seiten (wischen oder links/rechts tippen): Woche, Geld, Gesundheit, Vorrat, Erfolge, nächste Woche.
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

    private enum L {
        static let content: CGFloat = 150, side: CGFloat = 24
        static let bar: CGFloat = 58 - 52, barSide: CGFloat = 20
    }

    var body: some View {
        ZStack(alignment: .top) {
            StoryTint.pages[page].bg.ignoresSafeArea().animation(.easeInOut(duration: 0.35), value: page)
            if let r = review {
                GeometryReader { geo in
                    TabView(selection: $page) {
                        ForEach(0..<6, id: \.self) { i in
                            pageView(i, r, width: geo.size.width).tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .contentShape(Rectangle())
                    .onTapGesture { p in go(p.x < geo.size.width / 3 ? -1 : 1) }
                }
                .ignoresSafeArea()
            } else if let error {
                ErrorBlock8(message: error) { Task { await load() } }
                    .padding(.horizontal, L.side).frame(maxHeight: .infinity)
            } else {
                PotLoader().frame(maxHeight: .infinity)
            }
            topBar
        }
        .foregroundStyle(Theme.C.ink)
        .sensoryFeedback(.selection, trigger: page)
        .task { await load() }
        .sheet(isPresented: $sharing) {
            if let r = review {
                ImageShareSheet(name: "Wochenrückblick KW \(r.kw)") {
                    var photo: UIImage?
                    if let url = r.cooking.favorite.flatMap({ f in mediaURL(f.imageUrl) }), let loaded = try? await URLSession.shared.data(from: url) {
                        photo = UIImage(data: loaded.0)
                    }
                    return ImageShareSheet.snapshot(ReviewShareCard(review: r, photo: photo, household: store.household?.name ?? ""))
                }
                .sheet8()
                .presentationDetents([.large])
            }
        }
    }

    /// Sechs Story-Striche, „Wochenrückblick KW 45“, Teilen und Schließen in halbweißen Kreisen (`.f-st`).
    private var topBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { i in
                    Capsule().fill(i <= page ? Theme.C.ink : Theme.C.ink.opacity(0.16)).frame(height: 4)
                }
            }
            .animation(Theme.spring, value: page)
            .accessibilityElement()
            .accessibilityLabel("Seite \(page + 1) von 6")
            HStack(spacing: 8) {
                Icon(.book, size: 20)
                Text(review.map { r in "Wochenrückblick KW \(r.kw)" } ?? "Wochenrückblick").font(Theme.F.text(14, .extrabold, relativeTo: .subheadline))
                Spacer()
                if review != nil { roundButton(.share, "Als Bild teilen") { sharing = true } }
                roundButton(.x, "Schließen") { dismiss() }
            }
        }
        .padding(.horizontal, L.barSide).padding(.top, L.bar)
    }

    private func roundButton(_ icon: Icon8, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: 18).frame(width: 40, height: 40).background(Theme.C.onInk.opacity(0.5), in: Circle())
                .frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    /// Eine Seite: Formen und feste Teile in Mockup-Koordinaten (ab Bildschirm-Oberkante), Inhalt ab y 150.
    private func pageView(_ i: Int, _ r: WeekReviewDTO, width w: CGFloat) -> some View {
        let on = page == i
        let form = StoryTint.pages[i].form
        let right = { (x: CGFloat) in w - 390 + x }  // rechts verankert
        let mid = { (x: CGFloat) in w / 2 - 195 + x }  // mittig verankert
        return ZStack(alignment: .topLeading) {
            switch i {
            case 0:
                Circle().fill(form).frame(width: 420, height: 420).offset(x: right(160), y: 470)
                favorite(r, on, x: right(192))
            case 1:
                Circle().fill(form).frame(width: 400, height: 400).offset(x: -150, y: 640)
                Ill("bag").frame(width: 170, height: 170).offset(x: 14, y: 648)
            case 2:
                Circle().fill(form).frame(width: 300, height: 300).offset(x: right(220), y: -90)
                Ill("tomato").frame(width: 126, height: 126).offset(x: right(246), y: 112)
            case 3:
                Circle().fill(form).frame(width: 360, height: 360).offset(x: -120, y: 600)
                Ill("fridge").frame(width: 160, height: 160).offset(x: 24, y: 620)
            case 4:
                Circle().fill(form).frame(width: 300, height: 300).offset(x: right(220), y: -90)
            default:
                EdgeForm(.arch).fill(form).frame(width: 200, height: 300).offset(x: mid(96), y: 586)
                Ill("cookbook").frame(width: 140, height: 140).offset(x: mid(126), y: 588)
            }
            ScrollView {
                Group {
                    switch i {
                    case 0: weekPage(r)
                    case 1: moneyPage(r, form)
                    case 2: healthPage(r.health, form, on)
                    case 3: pantryPage(r)
                    case 4: achievementsPage(r.achievements)
                    default: nextPage(r.nextWeek)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, L.side).padding(.top, L.content).padding(.bottom, 120)
                .id("\(i)-\(on)")  // beim Aufschlagen neu: Zahlen rollen ein
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            if i == 4, on, !r.achievements.isEmpty, !reduceMotion {
                ConfettiOnce().offset(x: w / 2, y: 330)
            }
            if i == 5 {
                PrimaryButton(title: "Plan erstellen", icon: .sparkle) {
                    dismiss()
                    plan()
                }
                .padding(.horizontal, L.side).padding(.bottom, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(width: w, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func head(_ small: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(small).font(Theme.F.small).foregroundStyle(Theme.C.ink)
            Text(title).font(Theme.F.t1).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func weekPage(_ r: WeekReviewDTO) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            head("KW \(r.kw) · \(r.period)", "Deine Woche")
            StatF(label: "Gekocht", value: "\(r.cooking.cooked)", size: 180, roll: 0).padding(.top, 22)
            Text("von \(r.cooking.planned) geplanten").font(Theme.F.text(17, .semibold, relativeTo: .body))
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 2)
        }
    }

    /// Lieblingsgericht: Teller 190 im dunkleren Kreis (x 192 / y 524), Text links (x 24 / y 540, 150 breit).
    @ViewBuilder private func favorite(_ r: WeekReviewDTO, _ on: Bool, x: CGFloat) -> some View {
        if let f = r.cooking.favorite {
            Plate(url: mediaURL(f.imageUrl), size: 190, seed: f.title)
                .scaleEffect(on || reduceMotion ? 1 : 0.7).opacity(on || reduceMotion ? 1 : 0)
                .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.7).delay(0.3), value: on)
                .offset(x: x - Theme.S.plateRing, y: 524 - Theme.S.plateRing)
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Lieblingsgericht").foregroundStyle(Theme.C.ink)
                Text(f.title).font(Theme.F.t2).padding(.top, 6).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 2) { ForEach(0..<f.stars, id: \.self) { _ in StarFill() } }
                    .padding(.top, 10)
                    .accessibilityElement().accessibilityLabel("\(f.stars) Sterne")
            }
            .frame(width: 150, alignment: .leading)
            .offset(x: L.side, y: 540)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Lieblingsgericht").foregroundStyle(Theme.C.ink)
                Text("Bewertet Gerichte mit „Gekocht ★“ – dann steht hier euer Lieblingsgericht.").font(Theme.F.text(15, .semibold, relativeTo: .body))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 220, alignment: .leading)
            .offset(x: L.side, y: 540)
        }
    }

    private func moneyPage(_ r: WeekReviewDTO, _ form: Color) -> some View {
        let m = r.money
        let parts = euroParts(m.spentCents)
        let over = m.spentCents - m.budgetCents
        return VStack(alignment: .leading, spacing: 0) {
            head("KW \(r.kw) · \(r.period)", "Gespart &\nausgegeben")
            StatF(label: "Ausgegeben", value: parts.0, unit: parts.1, size: 88, unitSize: 36, roll: 0).padding(.top, 22)
            if m.estimatedCents > 0 {
                Text("davon \(euro(m.estimatedCents)) geschätzt").font(Theme.F.text(14)).frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 4)
            }
            StatF(label: "Gespart", value: euro(m.savedCents + m.bonusCents), size: 40, roll: 0.15).padding(.top, 36)
            Text("\(euro(m.savedCents)) Angebote · \(euro(m.bonusCents)) Bonus").font(Theme.F.text(14))
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 6)
            if m.budgetCents > 0 {
                HStack {
                    Text("Budget \(euro(m.budgetCents))").font(Theme.F.text(16, .extrabold, relativeTo: .headline))
                    Spacer()
                    Text(m.budgetOk || over <= 0 ? "Im Budget" : "\(euro(over)) über Budget")
                        .font(Theme.F.text(12, .extrabold, relativeTo: .caption))
                        .foregroundStyle(m.budgetOk || over <= 0 ? Theme.C.ink : Theme.C.onInk)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(m.budgetOk || over <= 0 ? Theme.C.card : Theme.C.deal, in: Capsule())
                }
                .padding(.top, 44)
                GeometryReader { g in
                    let whole = CGFloat(max(m.spentCents, m.budgetCents))
                    HStack(spacing: 0) {
                        Theme.C.ink.frame(width: g.size.width * CGFloat(min(m.spentCents, m.budgetCents)) / whole)
                        if over > 0 { Theme.C.deal.frame(width: g.size.width * CGFloat(over) / whole) }
                    }
                }
                .frame(height: 30)
                .background(form)
                .clipShape(Capsule())
                .padding(.top, 10)
                .accessibilityHidden(true)
            }
        }
    }

    private func healthPage(_ health: [WeekReviewDTO.Health], _ form: Color, _ on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            head("Schnitt pro Tag", "Gesundheit")
            if health.isEmpty {
                Text("Für diese Woche gibt es noch keine Nährwerte.").font(Theme.F.text(15, .semibold, relativeTo: .body)).padding(.top, 56)
            }
            ForEach(Array(health.enumerated()), id: \.element.id) { idx, h in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Text(String(h.name.prefix(1))).font(Theme.F.serif(20, relativeTo: .title3))
                            .frame(width: 44, height: 44).background(Theme.C.card, in: Circle())
                        Text(h.name).font(Theme.F.t2).frame(maxWidth: .infinity, alignment: .leading)
                        SoftPill(text: "\(h.plants) Pflanzen", icon: .leaf, tint: Theme.C.card)
                    }
                    metric("kcal", h.avgKcal, h.kcalGoal, "", form, on)
                    metric("Protein", h.avgProtein, h.proteinGoal, " g", form, on)
                }
                .padding(.top, idx == 0 ? 56 : 72)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func metric(_ label: String, _ value: Int, _ goal: Int, _ unit: String, _ form: Color, _ on: Bool) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(Theme.F.text(14, .extrabold, relativeTo: .subheadline))
                Spacer()
                BigNumber(num(Double(value)), size: 26)
                Text(" / \(num(Double(goal)))\(unit)").font(Theme.F.num(16)).tracking(Theme.F.numTracking(16)).foregroundStyle(Theme.C.ink.opacity(0.45))
            }
            Capsule().fill(form).frame(height: 8)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule().fill(Theme.C.ink)
                            .frame(width: on || reduceMotion ? g.size.width * (goal > 0 ? min(Double(value) / Double(goal), 1) : 0) : 0)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.9).delay(0.2), value: on)
                    }
                }
                .clipShape(Capsule())
        }
        .padding(.top, 18)
    }

    /// Seite 4 (ohne Mockup): Reste wie Seite 2 als große Zahlen.
    private func pantryPage(_ r: WeekReviewDTO) -> some View {
        let p = r.pantry
        return VStack(alignment: .leading, spacing: 0) {
            head("KW \(r.kw) · \(r.period)", "Vorrat &\nReste")
            StatF(label: "Reste verwendet", value: "\(p.restsUsed)", size: 120, roll: 0).padding(.top, 22)
            StatF(label: "noch übrig", value: "\(p.restsLeft)", size: 40, roll: 0.15).padding(.top, 36)
            if let thrown = p.thrownAway { StatF(label: "weggeworfen", value: "\(thrown)", size: 40, roll: 0.3).padding(.top, 12) }
            Text(p.restsUsed > 0 ? "Angebrochenes landet im nächsten Gericht statt im Müll." : "Reste plant der Generator automatisch ein.")
                .font(Theme.F.text(15, .semibold, relativeTo: .body)).fixedSize(horizontal: false, vertical: true).padding(.top, 24)
        }
    }

    /// Seite 5 (ohne Mockup): neue Medaillen in zwei Spalten.
    private func achievementsPage(_ list: [AchievementDTO]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            head(list.isEmpty ? "diese Woche" : "\(list.count) diese Woche", "Neue Erfolge")
            if list.isEmpty {
                Text("Diese Woche kein neuer Erfolg – nächste Woche klappt’s!").font(Theme.F.text(15, .semibold, relativeTo: .body)).padding(.top, 36)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 28) {
                    ForEach(list) { a in
                        VStack(spacing: 8) {
                            Medal(a: a, size: 92)
                            Text(a.name).font(Theme.F.text(13, .bold, relativeTo: .footnote)).multilineTextAlignment(.center)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(a.title)
                    }
                }
                .padding(.top, 36)
            }
        }
    }

    private func nextPage(_ deals: [WeekReviewDTO.Deal]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            head("Angebote ab Montag", "Nächste Woche\ngünstig")
            if deals.isEmpty {
                Text("Die Prospekte für nächste Woche kommen meist ab Donnerstag.").font(Theme.F.text(15, .semibold, relativeTo: .body)).padding(.top, 22)
            }
            VStack(spacing: 0) {
                ForEach(deals) { d in
                    HStack(spacing: 14) {
                        RemoteImage(url: URL(string: d.imageUrl), contentMode: .fill) { Icon(.tag).frame(width: 64, height: 64).background(Theme.C.card) }
                            .frame(width: 64, height: 64).clipShape(Circle())
                            .background(Circle().fill(Theme.C.card).padding(-4))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(d.title).font(Theme.F.serif(19, relativeTo: .title3)).lineLimit(2)
                            HStack(spacing: 6) {
                                LogoInline(chain: d.chain, height: 11).padding(1).background(Theme.C.plate, in: RoundedRectangle(cornerRadius: 3))
                                Text(euro(d.priceCents)).font(Theme.F.text(13, .bold, relativeTo: .footnote))
                                Text("statt \(euro(d.regularPriceCents))").font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink.opacity(0.45))
                            }
                        }
                        Spacer(minLength: 4)
                        DealPill(text: "−\(d.savingPct) %")
                    }
                    .frame(minHeight: 96)
                    .overlay(alignment: .top) { Hairline(color: Theme.C.ink.opacity(0.18)) }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 22)
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

/// Konfetti einmal ab dem Erscheinen (Story-Seite „Neue Erfolge“).
private struct ConfettiOnce: View {
    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation) { ctx in ConfettiBurst(t: ctx.date.timeIntervalSince(start)) }
    }
}

/// Gefüllter Stern 18 (`#i-star` mit fill).
private struct StarFill: View {
    var body: some View {
        ZStack {
            Icon8.star.path(.stroke).fill()
            Icon8.star.path(.stroke).stroke(style: StrokeStyle(lineWidth: Theme.S.iconStroke, lineJoin: .round))
        }
        .frame(width: 24, height: 24).scaleEffect(18.0 / 24).frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

/// Bildkarte „Meine Woche“ (Teilen-Sheet S35): Mockup-Karte 272 × 340, als Bild 360 × 450 pt (× 3 = 1080 × 1350 px).
struct ReviewShareCard: View {
    let review: WeekReviewDTO
    let photo: UIImage?
    var household = ""

    private enum L { static let w: CGFloat = 272, h: CGFloat = 340, out: CGFloat = 360 }

    var body: some View {
        card
            .scaleEffect(L.out / L.w, anchor: .topLeading)
            .frame(width: L.out, height: L.out * L.h / L.w, alignment: .topLeading)
            .environment(\.dynamicTypeSize, .large)
            .environment(\.colorScheme, .light)
    }

    private var card: some View {
        let r = review
        let year = r.end.prefix(4)
        return ZStack(alignment: .topLeading) {
            Theme.C.card
            Circle().fill(Theme.C.blue).frame(width: 200, height: 200).offset(x: 140, y: -74)
            Group {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                } else {
                    Ill("pot").padding(10).background(Theme.C.plate)
                }
            }
            .frame(width: 78, height: 78).clipShape(Circle())
            .background(Circle().fill(Theme.C.card).padding(-4))
            .offset(x: 178, y: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text("Meine Woche").font(Theme.F.serif(20))
                Text("KW \(r.kw) · \(r.periodShort) \(year)").font(Theme.F.text(11)).foregroundStyle(Theme.C.ink2).padding(.top, 2)
                if let f = r.cooking.favorite {
                    Text("LIEBLINGSGERICHT").font(Theme.F.text(9, .extrabold)).tracking(9 * 0.08).foregroundStyle(Theme.C.ink2).padding(.top, 20)
                    Text(f.title).font(Theme.F.text(13, .extrabold)).lineLimit(2).padding(.top, 2)
                }
            }
            .frame(width: 130, alignment: .leading)
            .offset(x: 18, y: 20)
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    tile("Gekocht", "\(r.cooking.cooked)")
                    tile("Gespart", euro(r.money.savedCents + r.money.bonusCents))
                }
                GridRow {
                    tile("Pflanzen", "\(r.health.map(\.plants).max() ?? 0)")
                    tile(r.achievements.count == 1 ? "Neuer Erfolg" : "Neue Erfolge", "\(r.achievements.count)")
                }
            }
            .frame(width: L.w - 36)
            .offset(x: 18, y: 150)
            HStack {
                HStack(spacing: 5) { Icon(.fork, size: 14); Text("Mit Kochpilot geplant") }
                Spacer()
                if !household.isEmpty { Text(household).foregroundStyle(Theme.C.ink2) }
            }
            .font(Theme.F.text(11, .extrabold))
            .frame(width: L.w - 36)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 16)
            .offset(x: 18)
        }
        .frame(width: L.w, height: L.h)
        .clipped()
        .foregroundStyle(Theme.C.ink)
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(Theme.F.text(10, .bold))
            BigNumber(value, size: 34).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.top, 4)
        .overlay(alignment: .top) { Hairline(color: Theme.C.ink) }
    }
}

/// Start-Zeile „Wochenrückblick KW 44 / 31,90 € · 9,80 € gespart“ → Story; Archiv per langem Drücken.
/// Ab Sonntag beim ersten Öffnen einmal automatisch.
struct ReviewCard: View {
    @Environment(AppStore.self) private var store
    @State private var r: WeekReviewDTO?
    @State private var archive = false

    var body: some View {
        VStack(spacing: 0) {
            if let r {
                Button { store.review = r.week } label: {
                    HStack(spacing: 14) {
                        Icon(.book).foregroundStyle(Theme.C.ink)
                            .frame(width: Theme.S.rowCircle, height: Theme.S.rowCircle).background(Theme.C.blue1, in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Wochenrückblick KW \(r.kw)").font(Theme.F.serif(17, relativeTo: .body)).foregroundStyle(Theme.C.ink)
                            Text("\(euro(r.money.spentCents)) · \(euro(r.money.savedCents + r.money.bonusCents)) gespart")
                                .font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                        }
                        Spacer(minLength: 8)
                        Icon(.chev, size: 18).foregroundStyle(Theme.C.ink3)
                    }
                    .frame(minHeight: Theme.S.row)
                    .overlay(alignment: .top) { Hairline() }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .contextMenu { Button { archive = true } label: { Label("Alle Rückblicke", systemImage: "book") } }
                .accessibilityAction(named: "Alle Rückblicke") { archive = true }
                .transition(.opacity)
            }
        }
        .navigationDestination(isPresented: $archive) { ReviewArchiveView() }
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

/// Archiv aller Rückblicke (S35b): KW groß links, Ausgaben als Zahl, „gekocht · Zeitraum“, Chevron; Kochbuch im Kreis oben.
struct ReviewArchiveView: View {
    @Environment(AppStore.self) private var store
    @State private var rows: [ReviewSummaryDTO]?
    @State private var error: String?

    // Mockup S35b: Kreis 310 bei x 206 / y −110, Kochbuch 124 bei x 246 / y 40
    private enum L {
        static let blob: CGFloat = 310, blobRight: CGFloat = 390 - 206 - 310, blobTop: CGFloat = -110 - 52
        static let ill: CGFloat = 124, illRight: CGFloat = 390 - 246 - 124, illTop: CGFloat = 40 - 52
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                BackButton8()
                Text(rows.map { r in r.count == 1 ? "1 Woche" : "\(r.count) Wochen" } ?? "Archiv").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                    .padding(.top, 34)
                Text("Rückblicke").font(Theme.F.t1)
                if let rows {
                    if rows.isEmpty {
                        EmptyBlock8(ill: "cookbook", title: "Noch kein Rückblick", text: "Der erste kommt am Sonntag um 19 Uhr.").padding(.top, 34)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                                line(row, first: i == 0).appear(delay: Double(i) * 0.04)
                            }
                        }
                        .overlay(alignment: .bottom) { Hairline() }
                        .padding(.top, 34)
                        Text("Der nächste Rückblick kommt am Sonntag um 19 Uhr.").font(Theme.F.text(13, .semibold, relativeTo: .footnote))
                            .foregroundStyle(Theme.C.ink2).padding(.top, 20)
                    }
                } else if let error {
                    ErrorBlock8(message: error) { Task { await load() } }.padding(.top, 34)
                } else {
                    VStack(spacing: 14) { ForEach(0..<3, id: \.self) { _ in Skeleton8(height: 90) } }.padding(.top, 34)
                }
            }
            .padding(.horizontal, Theme.pagePadding).padding(.top, 14).padding(.bottom, Theme.S.nav)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pinned(right: L.illRight, top: L.illTop) { Ill("cookbook").frame(width: L.ill, height: L.ill) }
            .edgeForm(.circle, Theme.C.blue1, width: L.blob, height: L.blob, right: L.blobRight, top: L.blobTop)
        }
        .scrollClipDisabled()
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await load() }
        .task { await load() }
    }

    private func line(_ row: ReviewSummaryDTO, first: Bool) -> some View {
        let days = WeekReviewDTO.days(row.week)
        let year = row.week.prefix(4)
        let period = days.map { d in WeekReviewDTO.periodShort(d.0, d.1) + (first ? " \(year)" : "") } ?? ""
        return Button { store.review = row.week } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("KW")
                    BigNumber("\(row.kw)", size: 56)
                }
                .frame(width: 62, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    BigNumber(euro(row.spentCents), size: 30)
                    Text("\(row.cooked) gekocht\(period.isEmpty ? "" : " · \(period)")").font(Theme.F.text(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Theme.C.ink2)
                }
                Spacer(minLength: 8)
                Icon(.chev, size: 18)
            }
            .foregroundStyle(Theme.C.ink)
            .frame(minHeight: 104)
            .overlay(alignment: .top) { Hairline(color: first ? Theme.C.ink : Theme.C.line) }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("KW \(row.kw), \(euro(row.spentCents)) ausgegeben, \(row.cooked) gekocht")
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

/// Rezept › Teilen › „Als Link teilen“ (S36): Link als Zeile im blauen Kreis, „Teilen“ und „Link kopieren“.
struct RecipeLinkSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let recipeId: Int
    let title: String
    @State private var link: RecipeShareDTO?
    @State private var error: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Als Link teilen").font(Theme.F.t2)
                Spacer()
                CloseButton { dismiss() }
            }
            Text("Wer den Link öffnet, sieht Foto, Zutaten und Schritte – mit Kochpilot lässt sich „\(title)“ in die eigenen Rezepte übernehmen.")
                .font(Theme.F.text(15, .semibold, relativeTo: .body)).lineSpacing(4).foregroundStyle(Theme.C.ink2)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            if let link, let url = URL(string: link.url) {
                HStack(spacing: 14) {
                    Icon(.link).frame(width: Theme.S.rowCircle, height: Theme.S.rowCircle).background(Theme.C.blue, in: Circle())
                    Text(link.url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: ""))
                        .font(.system(size: 15, weight: .medium, design: .monospaced)).lineLimit(2).textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 64)
                .overlay(alignment: .top) { Hairline() }
                .overlay(alignment: .bottom) { Hairline() }
                .padding(.top, 16)
                .transition(.opacity)
                ShareLink(item: url, subject: Text(title), message: Text("Rezept „\(title)“ aus unserem Kochpilot:")) {
                    HStack(spacing: 8) { Icon(.share, size: 20); Text("Teilen") }
                        .font(Theme.F.button).foregroundStyle(Theme.C.onInk)
                        .frame(maxWidth: .infinity, minHeight: Theme.S.button).background(Theme.C.ink, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 20)
                OutlineButton(title: copied ? "Kopiert" : "Link kopieren", icon: copied ? .check : .copy) {
                    UIPasteboard.general.string = link.url
                    withAnimation(Theme.spring) { copied = true }
                }
                .sensoryFeedback(.success, trigger: copied)
                .padding(.top, 10)
            } else if let error {
                ErrorBlock8(message: error) { Task { await load() } }.padding(.top, 16)
            } else {
                Skeleton8(height: 64).padding(.top, 16)
                Skeleton8(height: Theme.S.button).padding(.top, 20)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.pagePadding).padding(.bottom, 40)
        .sheet8()
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

/// Deep-Link essenapp://import-recipe/<code> (S37): Teller vor einem Kreis, Name, „von Familie Müller“, Zutaten als Zeilen,
/// unten fest „Übernehmen“ (Kopie mit Quelle).
struct SharedRecipeSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let code: String
    let opened: (Int) -> Void
    @State private var recipe: SharedRecipeDTO?
    @State private var error: String?
    @State private var notFound = false
    @State private var saving = false

    // Mockup S37: Kreis 320 im Sheet bei x 180 / y 30 (Sheet-Innenseite, Griff 33 eingerechnet)
    private enum L { static let blob: CGFloat = 320, blobRight: CGFloat = 390 - 180 - 320, blobTop: CGFloat = 30 - 33 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Geteiltes Rezept").font(Theme.F.t2)
                    Spacer()
                    CloseButton { dismiss() }
                }
                if let r = recipe {
                    Plate(url: mediaURL(r.imageUrl), size: 180, seed: r.title).frame(maxWidth: .infinity).padding(.top, 18).appear()
                    Text(r.title).font(Theme.F.serif(28, relativeTo: .title)).padding(.top, 24).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) { Icon(.users, size: 18); Text("von \(r.fromHousehold)") }
                        .font(Theme.F.chip).foregroundStyle(Theme.C.ink2)
                        .padding(.horizontal, 15).frame(height: Theme.S.chip)
                        .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
                        .padding(.top, 10)
                    Text("\(r.prepMinutes) min · \(r.servings) Portionen · \(r.steps.count) Schritte").font(Theme.F.text(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Theme.C.ink2).padding(.top, 8)
                    if !r.description.isEmpty {
                        Text(r.description).font(Theme.F.text(15, .semibold, relativeTo: .body)).lineSpacing(4).foregroundStyle(Theme.C.ink2)
                            .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                    }
                    SecHead("Zutaten").padding(.top, 28).padding(.bottom, 6)
                    ForEach(Array(r.ingredients.enumerated()), id: \.offset) { _, ing in
                        HStack {
                            Text(ing.name).font(Theme.F.text(16, .bold, relativeTo: .body))
                            Spacer()
                            Text(qty(ing.amount, ing.unit)).font(Theme.F.text(16, .semibold, relativeTo: .body)).foregroundStyle(Theme.C.ink2)
                        }
                        .frame(minHeight: 50)
                        .overlay(alignment: .top) { Hairline() }
                    }
                } else if notFound {
                    EmptyBlock8(ill: "cookbook", title: "Rezept-Link ungültig", text: "Der Link stimmt nicht oder das Rezept wurde gelöscht.").padding(.top, 24)
                } else if let error {
                    ErrorBlock8(message: error) { Task { await load() } }.padding(.top, 24)
                } else {
                    Skeleton8(width: 180, height: 180).clipShape(Circle()).frame(maxWidth: .infinity).padding(.top, 18)
                    Skeleton8(height: 30).padding(.top, 24)
                    Skeleton8(height: 160).padding(.top, 20)
                }
            }
            .padding(.horizontal, Theme.pagePadding).padding(.bottom, 140)
            .frame(maxWidth: .infinity, alignment: .leading)
            .edgeForm(.circle, Theme.C.blue1, width: L.blob, height: L.blob, right: L.blobRight, top: L.blobTop)
        }
        .overlay(alignment: .bottom) {
            if let r = recipe {
                PrimaryButton(title: saving ? "Übernehme …" : "Übernehmen", disabled: saving) { take(r) }
                    .padding(.horizontal, Theme.pagePadding).padding(.bottom, 34).padding(.top, 60)
                    .background(LinearGradient(stops: [.init(color: Theme.C.bg.opacity(0), location: 0), .init(color: Theme.C.bg, location: 0.45)],
                                               startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
            }
        }
        .sheet8()
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
