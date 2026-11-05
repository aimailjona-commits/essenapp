import SwiftUI

// Maße aus dem Mockup (Oberkante der Wisch-Fläche = 0, Seite 530 hoch)
private enum WK {
    static let cy: CGFloat = 170, row: CGFloat = 62, wheel: CGFloat = 150
    static let railX: CGFloat = 33, itemX: CGFloat = 27, dotX: CGFloat = 24, dot: CGFloat = 21, threadX: CGFloat = 44, thread: CGFloat = 120
    static let blob: CGFloat = 400, blobX: CGFloat = 150, blobY: CGFloat = -40
    static let plate: CGFloat = 180, plateX: CGFloat = 172, plateY: CGFloat = 60
    static let textX: CGFloat = 150, textTop: CGFloat = 262, right: CGFloat = 22
    static let ab: CGFloat = 62, abBottom: CGFloat = 36, abPlate: CGFloat = 44
    static let turn: Double = 80  // Grad Tellerdrehung pro Tag
}

/// S2 „Deine Woche“ als Rad (v9 `b.html`, Variante A): jeder Wisch rastet einen Tag weiter. Der große Punkt bleibt auf fester Höhe,
/// die Zeitleiste links läuft darunter durch und füllt sich schwarz; Tagesname und Teller liegen auf einer geraden Linie.
/// Nach Sonntag läuft `more` (Budget, Reste, Neu planen …) frei weiter.
struct WeekWheel<More: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let plan: PlanDTO
    let today: Int
    let openDay: (Int) -> Void
    let more: More
    @State private var page: Int?
    @State private var offset: CGFloat = 0
    @State private var pageH: CGFloat = 530

    init(plan: PlanDTO, today: Int, openDay: @escaping (Int) -> Void, @ViewBuilder more: () -> More) {
        self.plan = plan
        self.today = today
        self.openDay = openDay
        self.more = more()
        _page = State(initialValue: today)
    }

    static var dayColors: [Color] { [Theme.C.sage, Theme.C.rose, Theme.C.sand, Theme.C.blue, Theme.C.blue1, Theme.C.rose, Theme.C.sage] }

    var body: some View {
        let p = offset / max(pageH, 1)  // Tag als Kommazahl
        let wp = min(max(p, 0), 6)
        let rest = max(0, offset - 6 * pageH)  // hinter Sonntag: Rad scrollt mit weg
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { d in dayPage(d, p).containerRelativeFrame(.vertical).id(d) }
                    more.padding(.top, 28).padding(.bottom, 40)
                        .frame(maxWidth: .infinity, minHeight: pageH, alignment: .top).id(7)
                }
                .scrollTargetLayout()
                .onGeometryChange(for: CGFloat.self) { g in -g.frame(in: .scrollView).minY } action: { y in offset = y }
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(WeekSnap())
            .scrollPosition(id: $page)
            .onGeometryChange(for: CGFloat.self) { g in g.size.height } action: { h in pageH = h }

            wheel(wp).offset(y: -rest)
            Rectangle().fill(Theme.C.ink).frame(width: WK.thread, height: Theme.S.hair)
                .offset(x: WK.threadX, y: WK.cy - rest).allowsHitTesting(false)
            Circle().fill(Theme.C.ink).frame(width: WK.dot, height: WK.dot)
                .background(Circle().fill(Theme.C.bg).padding(-5))
                .offset(x: WK.dotX, y: WK.cy - WK.dot / 2 - rest)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .clipped()
        .sensoryFeedback(.selection, trigger: Int(wp.rounded()))
    }

    // MARK: Rad links

    private func wheel(_ p: CGFloat) -> some View {
        let on = Int(p.rounded())
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Theme.C.line).frame(width: Theme.S.hair, height: 6 * WK.row).offset(x: WK.railX, y: WK.cy)
            Rectangle().fill(Theme.C.ink).frame(width: Theme.S.hair, height: p * WK.row).offset(x: WK.railX, y: WK.cy)
            ForEach(0..<7, id: \.self) { d in
                item(d, on: d == on, past: CGFloat(d) < p - 0.01)
                    .opacity(max(0.2, 1 - abs(CGFloat(d) - p) * 0.22))
                    .offset(x: WK.itemX, y: WK.cy + CGFloat(d) * WK.row)
            }
        }
        .offset(y: -p * WK.row)
        .frame(width: WK.wheel, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .mask { LinearGradient(stops: [.init(color: .black, location: 0.7), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom) }
        .allowsHitTesting(false)
        .accessibilityHidden(true)  // VoiceOver liest die Tage auf den Seiten
    }

    /// Punkt auf der Leiste, Tag darüber, Gericht bzw. Datum darunter (`.b9-it`); Ursprung = Mitte der Leiste.
    private func item(_ d: Int, on: Bool, past: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Circle().fill(past ? Theme.C.ink : Theme.C.bg)
                .overlay(Circle().strokeBorder(past ? Theme.C.ink : Theme.C.ink3, lineWidth: 2))
                .frame(width: 13, height: 13).offset(y: -6)
            Text(on ? Labels.dayNames[d] : Labels.days[d])
                .font(on ? Theme.F.serif(20, relativeTo: .title3) : Theme.F.text(15, .bold))
                .foregroundStyle(on ? Theme.C.ink : Theme.C.ink2)
                .fixedSize()
                .frame(height: 30, alignment: .bottomLeading)
                .offset(x: 22, y: -34)
            Text(on ? date(d) : PlanWeek.main(plan, d)?.recipe.title ?? "frei")
                .font(Theme.F.text(12, .bold, relativeTo: .caption))
                .foregroundStyle(on ? Theme.C.ink : Theme.C.ink3)
                .lineLimit(1)
                .frame(width: WK.wheel - WK.itemX - 22, alignment: .leading)
                .offset(x: 22, y: 5)
        }
    }

    private func date(_ d: Int) -> String { PlanWeek.dayDate(plan.week, d) + (d == today ? " · heute" : "") }

    // MARK: Seite pro Tag

    private func dayPage(_ d: Int, _ p: CGFloat) -> some View {
        let meals = PlanWeek.sorted(plan, d)
        let main = PlanWeek.main(plan, d)
        let second = main.flatMap { m in meals.first { $0.mealType != m.mealType } }
        return ZStack(alignment: .topLeading) {
            Color.clear.edgeForm(.circle, Self.dayColors[d], width: WK.blob, height: WK.blob, left: WK.blobX, top: WK.blobY)

            Button { openDay(d) } label: {
                Group {
                    if let main {
                        PlanPlate(url: mediaURL(main.recipe.imageUrl), size: WK.plate)
                    } else {
                        Circle().fill(Theme.C.card).overlay { Ill("pot").padding(36) }.frame(width: WK.plate, height: WK.plate)
                    }
                }
                .rotationEffect(.degrees(reduceMotion ? 0 : (Double(d) - Double(p)) * WK.turn))
            }
            .buttonStyle(PressableStyle())
            .padding(.leading, WK.plateX).padding(.top, WK.plateY)
            .accessibilityLabel("\(Labels.dayNames[d]), \(date(d)), Tag im Detail")

            info(main).padding(.leading, WK.textX).padding(.trailing, WK.right).padding(.top, WK.textTop)

            secondRow(d, main: main, second: second)
                .padding(.leading, WK.textX).padding(.trailing, WK.right).padding(.bottom, WK.abBottom)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func info(_ m: MealDTO?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let m {
                let deals = PlanWeek.deals(m)
                Text("\(Labels.meal(m.mealType)) · \(m.recipe.prepMinutes) min".uppercased())
                    .font(Theme.F.lbl).tracking(11 * 0.08).foregroundStyle(Theme.C.ink)
                Text(m.recipe.title).font(Theme.F.serif(23)).lineLimit(3).padding(.top, 4)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        BigNumber(euro(PlanWeek.perPortion(m)), size: 38)
                        (Text("p. P.") + Text(deals > 0 ? " · " : "") + Text(deals > 0 ? "\(deals) im Angebot" : "").foregroundStyle(Theme.C.deal))
                            .font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink)
                    }
                    Spacer(minLength: 8)
                    NavigationLink { RecipeDetailView(meal: m) } label: { PlanInkCircle(icon: .play, size: 46, iconSize: 16) }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("\(m.recipe.title) öffnen")
                }
                .padding(.top, 10)
            } else {
                Text("FREI").font(Theme.F.lbl).tracking(11 * 0.08).foregroundStyle(Theme.C.ink)
                Text("Nichts geplant").font(Theme.F.serif(23)).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Zweite Mahlzeit als Zeile (`.b9-ab`), sonst „+ Abend dazuplanen“.
    @ViewBuilder private func secondRow(_ d: Int, main: MealDTO?, second: MealDTO?) -> some View {
        if let second {
            NavigationLink { RecipeDetailView(meal: second) } label: {
                HStack(spacing: 12) {
                    PlanPlate(url: mediaURL(second.recipe.imageUrl), size: WK.abPlate, mini: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(Labels.meal(second.mealType)) · \(second.recipe.prepMinutes) min".uppercased())
                            .font(Theme.F.lbl).tracking(11 * 0.08).foregroundStyle(Theme.C.ink2)
                        Text(second.recipe.title).font(Theme.F.text(14, .bold)).foregroundStyle(Theme.C.ink).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    BigNumber(euro(PlanWeek.perPortion(second)), size: 18).foregroundStyle(Theme.C.ink)
                }
                .frame(height: WK.ab)
                .overlay(alignment: .top) { Hairline() }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if let main {
            // shortcut: es gibt keinen Endpunkt „Gericht in freien Slot“, daher öffnet die Zeile den Tag
            Button { openDay(d) } label: {
                HStack(spacing: 12) {
                    Text("+").font(Theme.F.text(20, .semibold))
                        .frame(width: WK.abPlate, height: WK.abPlate)
                        .overlay(Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
                    Text("\(main.mealType == "abend" ? "Mittag" : "Abend") dazuplanen").font(Theme.F.text(14, .bold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.C.ink3)
                .frame(height: WK.ab)
                .overlay(alignment: .top) { Hairline() }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Rastet pro Wisch genau einen Tag weiter (`scroll-snap-stop: always`); ab Sonntag läuft der Rest frei.
struct WeekSnap: ScrollTargetBehavior {
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let h = context.containerSize.height
        guard h > 0 else { return }
        let last = 6 * h, from = context.originalTarget.rect.minY, y = target.rect.minY
        if y > last && from >= last - 1 { return }
        target.rect.origin.y = Self.snap(y, from: from, page: h)
    }

    /// Zieltag: nächster Tag, höchstens einer weiter als der Start, 0…6.
    static func snap(_ y: CGFloat, from: CGFloat, page h: CGFloat) -> CGFloat {
        let start = (min(from, 6 * h) / h).rounded()
        return min(max((y / h).rounded(), start - 1, 0), start + 1, 6) * h
    }
}
