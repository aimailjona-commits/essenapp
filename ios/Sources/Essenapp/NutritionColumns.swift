import SwiftUI

/// Rezeptdetail-Nährwerte, v9 a.html Variante C „Säulen gegen deine Woche“ (`.a9-card`):
/// kcal groß neben dem Ø der Woche, Säulen = Anteil am Tagesbedarf (Linien je 10 %, oben 50 %),
/// Strich = Ø der Woche, Gramm darunter, kurze Hinweise. Zucker und Salz fehlen im Backend → keine Säule.
struct NutritionColumns: View {
    let nutrition: NutritionDTO?  // pro Portion (1 Portion = 2000 kcal), nil = Berechnung läuft
    let who: ProfileDTO?
    let mine: Double?  // Anteil der Person an diesem Gericht, nil = isst nicht mit
    @Binding var person: Int?
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum L {
        static let radius: CGFloat = 32, pad: CGFloat = 20
        static let blob: CGFloat = 170, blobEdge: CGFloat = -70
        static let chip: CGFloat = 32, chipPad: CGFloat = 13
        static let vsTop: CGFloat = 12, vsGap: CGFloat = 16, kcal: CGFloat = 56, week: CGFloat = 30, unitBottom: CGFloat = 3
        static let pillTop: CGFloat = 10, captionTop: CGFloat = 18, colsTop: CGFloat = 6
        static let cols: CGFloat = 178, top: Double = 0.5, colGap: CGFloat = 8  // 178 pt = 50 % vom Tag
        static let barTop: CGFloat = 12, barBottom: CGFloat = 4
        static let mark: CGFloat = 2.5, markOver: CGFloat = 3, dot: CGFloat = 8
        static let labelsTop: CGFloat = 8, labelNum: CGFloat = 16
        static let legendTop: CGFloat = 14, legendGap: CGFloat = 16, swatch: CGFloat = 14, swatchLine: CGFloat = 16
        static let tagsTop: CGFloat = 14, tagGap: CGFloat = 6
    }

    private static var small12: Font { Theme.F.text(12, .semibold, relativeTo: .caption) }

    var body: some View {
        let p = who ?? store.profile ?? .blank
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Im Vergleich").font(Theme.F.headline).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if store.profiles.count > 1 {
                    ViewThatFits(in: .horizontal) {
                        chips(p)
                        ScrollView(.horizontal) { chips(p) }.scrollIndicators(.hidden)
                    }
                }
            }
            if let n = nutrition {
                stats(dish: n.times(mine ?? p.portionFactor), goal: NutritionMath.goals(p),
                      week: NutritionMath.weekAverage(store.plan?.entries ?? [], for: p), name: p.name)
            } else {
                Skeleton8(height: L.cols).padding(.top, L.vsTop)  // Berechnung läuft
            }
        }
        .foregroundStyle(Theme.C.ink)
        .padding(L.pad)
        .edgeForm(.circle, Theme.C.sage.opacity(0.7), width: L.blob, height: L.blob, right: L.blobEdge, top: L.blobEdge)
        .background(Theme.C.card)
        .clipShape(RoundedRectangle(cornerRadius: L.radius, style: .continuous))
        .animation(reduceMotion ? nil : Theme.spring, value: p.memberId)
        .sensoryFeedback(.selection, trigger: person)
        .onAppear {
            #if DEBUG
            NutritionMath.selfTest()
            #endif
        }
    }

    /// `.a9-who`: Kapsel 32, an = Tinte, aus = Weiß mit Haarlinie; Tap-Fläche 44.
    private func chips(_ sel: ProfileDTO) -> some View {
        HStack(spacing: 6) {
            ForEach(store.profiles) { p in
                let on = p.memberId == sel.memberId
                Button { withAnimation(Theme.spring) { person = p.memberId } } label: {
                    Text(p.name).font(Theme.F.text(13, .extrabold, relativeTo: .footnote)).lineLimit(1)
                        .foregroundStyle(on ? Theme.C.onInk : Theme.C.ink2)
                        .padding(.horizontal, L.chipPad)
                        .frame(height: L.chip)
                        .background(on ? Theme.C.ink : Theme.C.bg, in: Capsule())
                        .overlay { if !on { Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Für \(p.name)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func stats(dish: NutritionDTO, goal: NutritionDTO, week: NutritionDTO?, name: String) -> some View {
        HStack(alignment: .bottom, spacing: L.vsGap) {
            VStack(alignment: .leading, spacing: 0) {
                Text("dieses Gericht").font(Self.small12).foregroundStyle(Theme.C.ink2)
                HStack(alignment: .bottom, spacing: 6) {
                    BigNumber("\(Int(dish.kcal.rounded()))", size: L.kcal)
                    Text("kcal").font(Theme.F.text(16, .extrabold, relativeTo: .headline)).padding(.bottom, L.unitBottom)
                }
            }
            if let week {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Ø deine Woche").font(Self.small12).foregroundStyle(Theme.C.ink2)
                    BigNumber("\(Int(week.kcal.rounded()))", size: L.week).foregroundStyle(Theme.C.ink2)
                }
                .padding(.bottom, L.unitBottom)
            }
        }
        .padding(.top, L.vsTop)
        .accessibilityElement(children: .combine)
        if mine == nil {
            SoftPill(text: "\(name) isst bei diesem Gericht nicht mit", tint: Theme.C.warn).padding(.top, L.pillTop)
        } else if let week {
            let diff = Int((week.kcal - dish.kcal).rounded())
            SoftPill(text: diff == 0 ? "so viel wie sonst" : "\(abs(diff)) kcal \(diff > 0 ? "leichter" : "schwerer") als sonst",
                     tint: diff >= 0 ? Theme.C.sage : Theme.C.warn)
                .contentTransition(.numericText())
                .padding(.top, L.pillTop)
        }

        Text("Säule = Anteil am Tagesbedarf · Linien je 10 %").font(Self.small12).foregroundStyle(Theme.C.ink2).padding(.top, L.captionTop)
        let cols = columns(dish, goal, week)
        HStack(alignment: .bottom, spacing: L.colGap) {
            ForEach(cols, id: \.label) { c in column(c) }
        }
        .frame(height: L.cols)
        .background(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                ForEach(1..<5, id: \.self) { i in
                    HLine().stroke(Theme.C.gridLine, style: StrokeStyle(lineWidth: Theme.S.hair, dash: [4, 4]))
                        .frame(height: Theme.S.hair)
                        .offset(y: -L.cols * CGFloat(i) / 5)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.top, L.colsTop)
        HStack(alignment: .top, spacing: L.colGap) {
            ForEach(cols, id: \.label) { c in
                VStack(spacing: 3) {
                    Text(c.label).font(Theme.F.text(10, .extrabold, relativeTo: .caption2)).tracking(0.2).foregroundStyle(Theme.C.ink2)
                    Text(c.text).font(Theme.F.num(L.labelNum)).tracking(-0.04 * L.labelNum).contentTransition(.numericText())
                }
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)  // steckt im Label der Säule
            }
        }
        .padding(.top, L.labelsTop)

        HStack(spacing: L.legendGap) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Theme.C.blue).frame(width: L.swatch, height: L.swatch)
                Text("dieses Gericht")
            }
            if week != nil {
                HStack(spacing: 6) {
                    Rectangle().fill(Theme.C.ink).frame(width: L.swatchLine, height: L.mark)
                    Text("Ø deine Woche")
                }
            }
        }
        .font(Theme.F.text(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
        .padding(.top, L.legendTop)
        .accessibilityHidden(true)

        let hints = NutritionMath.hints(dish, goal: goal, week: week)
        if !hints.isEmpty {
            FlowLayout(spacing: L.tagGap) {
                ForEach(hints.indices, id: \.self) { i in SoftPill(text: hints[i].text, tint: hints[i].ok ? Theme.C.sage : Theme.C.warn) }
            }
            .padding(.top, L.tagsTop)
        }
    }

    private struct Column {
        let label: String, text: String, color: Color
        let share: Double, week: Double?  // Anteil am Tagesbedarf
    }

    private func columns(_ d: NutritionDTO, _ g: NutritionDTO, _ w: NutritionDTO?) -> [Column] {
        let rows: [(String, KeyPath<NutritionDTO, Double>, Color)] = [
            ("kcal", \.kcal, Theme.C.blue3), ("Protein", \.protein, Theme.C.rose), ("KH", \.carbs, Theme.C.blue),
            ("Fett", \.fat, Theme.C.sand), ("Ballast.", \.fiber, Theme.C.sage),
        ]
        return rows.map { label, k, color in
            let v = d[keyPath: k], goal = max(g[keyPath: k], 1)
            return Column(label: label, text: "\(Int(v.rounded()))\(label == "kcal" ? "" : " g")", color: color,
                          share: v / goal, week: w.map { $0[keyPath: k] / goal })
        }
    }

    /// `.a9-col`: Säule (oben rund 12, unten 4), Strich 2,5 mit Punkt rechts für den Wochenschnitt.
    private func column(_ c: Column) -> some View {
        let h = { (s: Double) in L.cols * CGFloat(min(max(s, 0), L.top) / L.top) }
        return ZStack(alignment: .bottom) {
            UnevenRoundedRectangle(topLeadingRadius: L.barTop, bottomLeadingRadius: L.barBottom,
                                   bottomTrailingRadius: L.barBottom, topTrailingRadius: L.barTop)
                .fill(c.color)
                .frame(height: h(c.share))
            if let w = c.week {
                ZStack(alignment: .trailing) {
                    Rectangle().fill(Theme.C.ink).frame(height: L.mark)
                    Circle().fill(Theme.C.ink).frame(width: L.dot, height: L.dot).offset(x: L.markOver)
                }
                .frame(height: L.mark)  // Punkt ragt über den Strich, Unterkante = Strich
                .padding(.horizontal, -L.markOver)
                .offset(y: -h(w))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .accessibilityElement()
        .accessibilityLabel("\(c.label == "Ballast." ? "Ballaststoffe" : c.label) \(c.text), \(Int((c.share * 100).rounded())) % vom Tagesbedarf"
            + (c.week.map { ", Woche \(Int(($0 * 100).rounded())) %" } ?? ""))
    }

    private struct HLine: Shape {
        func path(in r: CGRect) -> Path {
            Path { p in p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)) }
        }
    }
}

/// Tagesbedarf, Wochenschnitt und Hinweise – reine Logik, ohne UI.
enum NutritionMath {
    /// kcal und Protein aus dem Profil.
    /// shortcut: KH 50 % / Fett 30 % der kcal, Ballaststoffe 30 g (DGE-Richtwerte), bis das Profil eigene Ziele dafür hat.
    static func goals(_ p: ProfileDTO) -> NutritionDTO {
        let kcal = Double(max(p.kcal, 1))
        return NutritionDTO(kcal: kcal, protein: Double(max(p.proteinG, 1)), carbs: kcal * 0.5 / 4, fat: kcal * 0.3 / 9, fiber: 30)
    }

    /// Ø pro Gericht der Woche für diese Person (ihr Portionsanteil); Gerichte ohne sie oder ohne Nährwerte zählen nicht.
    static func weekAverage(_ meals: [MealDTO], for p: ProfileDTO) -> NutritionDTO? {
        let parts: [NutritionDTO] = meals.compactMap { m in
            let k = m.portions.isEmpty ? p.portionFactor : m.portions.first { $0.memberId == p.memberId }?.factor
            guard let n = m.recipe.nutrition, let k else { return nil }
            return n.times(k)
        }
        guard !parts.isEmpty else { return nil }
        func avg(_ k: KeyPath<NutritionDTO, Double>) -> Double { parts.map { $0[keyPath: k] }.reduce(0, +) / Double(parts.count) }
        return NutritionDTO(kcal: avg(\.kcal), protein: avg(\.protein), carbs: avg(\.carbs), fat: avg(\.fat), fiber: avg(\.fiber))
    }

    static func hints(_ d: NutritionDTO, goal g: NutritionDTO, week w: NutritionDTO?) -> [(text: String, ok: Bool)] {
        var out: [(text: String, ok: Bool)] = []
        if d.fiber / g.fiber >= 0.25 { out.append(("viele Ballaststoffe", true)) }
        if d.fat / g.fat <= 0.1 { out.append(("kaum Fett", true)) } else if d.fat / g.fat >= 0.5 { out.append(("viel Fett", false)) }
        if let wp = w?.protein, wp > 0 {
            if d.protein < wp * 0.85 { out.append(("weniger Protein als sonst", false)) }
            else if d.protein > wp * 1.15 { out.append(("mehr Protein als sonst", true)) }
        }
        return out
    }

    static func selfTest() {
        let p = ProfileDTO.blank  // 2000 kcal → Portionsfaktor 1
        let dish = NutritionDTO(kcal: 400, protein: 14, carbs: 86, fat: 2, fiber: 9)
        let rich = NutritionDTO(kcal: 700, protein: 40, carbs: 60, fat: 30, fiber: 5)
        func meal(_ n: NutritionDTO?, _ portions: [PortionDTO] = []) -> MealDTO {
            MealDTO(id: 1, day: 0, mealType: "abend", costCents: 0, locked: false,
                    recipe: RecipeDTO(id: 1, title: "", description: "", cuisine: "", mealType: "abend", servings: 2, prepMinutes: 0,
                                      ingredients: [], steps: [], imageUrl: "", nutrition: n),
                    portions: portions)
        }
        let w = weekAverage([meal(dish), meal(rich), meal(nil), meal(rich, [PortionDTO(memberId: 99, factor: 1)])], for: p)
        assert(w?.kcal == 550 && w?.protein == 27, "Ø: nur Gerichte mit Nährwerten und mit dieser Person")
        assert(weekAverage([meal(nil)], for: p) == nil)
        let h = hints(dish, goal: goals(p), week: w).map(\.text)
        assert(h == ["viele Ballaststoffe", "kaum Fett", "weniger Protein als sonst"], "Hinweise wie im Mockup: \(h)")
    }
}

extension NutritionDTO {
    func times(_ k: Double) -> NutritionDTO {
        NutritionDTO(kcal: kcal * k, protein: protein * k, carbs: carbs * k, fat: fat * k, fiber: fiber * k)
    }
}
