import SwiftUI
import UIKit

// Bausteine v8 „Tinte & Bogen“ (docs/ui/redesign-v8.md Abschnitt 3). Namen ↔ CSS-Klassen des Mockups.

// MARK: Icons, Illustrationen

/// Icon aus dem Mockup (`#i-…`), Strich 1.8 auf 24er-Raster; Farbe über `foregroundStyle`.
struct Icon: View {
    let icon: Icon8
    var size: CGFloat = Theme.S.icon

    init(_ icon: Icon8, size: CGFloat = Theme.S.icon) {
        self.icon = icon
        self.size = size
    }

    var body: some View {
        ZStack {
            icon.path(.stroke).stroke(style: StrokeStyle(lineWidth: Theme.S.iconStroke, lineCap: .round, lineJoin: .round))
            icon.path(.bold).stroke(style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            icon.path(.fill).fill()
        }
        .frame(width: 24, height: 24)
        .scaleEffect(size / 24)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Tusche-Illustration aus Resources/ill (`img.ill`).
struct Ill: View {
    let name: String

    init(_ name: String) { self.name = name }

    var body: some View {
        if let image = Self.image(name) {
            Image(uiImage: image).resizable().scaledToFit().accessibilityHidden(true)
        }
    }

    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ name: String) -> UIImage? {
        if let hit = cache.object(forKey: name as NSString) { return hit }
        let url = Bundle.module.url(forResource: name, withExtension: "webp")
            ?? Bundle.module.url(forResource: name, withExtension: "webp", subdirectory: "ill")
        guard let url, let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

// MARK: Rand-Formen (.blob .arch .leaf .quarter .offer .tab)

/// Pastell-Form, die aus dem Bildschirmrand läuft. Nie als Kachel mitten auf der Seite.
struct EdgeForm: Shape {
    enum Kind {
        case circle
        case arch  // Tor-Bogen: oben voll rund, unten gerade (border-radius 999 999 0 0)
        case leaf(CGFloat)  // nur unten links rund (border-radius 0 0 0 r)
        case quarter  // Viertelkreis, Rundung unten links (border-radius 0 0 0 100%)
        case tab(CGFloat)  // Lasche: links rund (border-radius r 0 0 r)
    }

    let kind: Kind

    init(_ kind: Kind) { self.kind = kind }

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .circle:
            return Ellipse().path(in: rect)
        case .arch:
            let r = min(rect.width / 2, rect.height)
            return UnevenRoundedRectangle(topLeadingRadius: r, topTrailingRadius: r).path(in: rect)
        case .leaf(let r):
            return UnevenRoundedRectangle(bottomLeadingRadius: min(r, rect.width, rect.height)).path(in: rect)
        case .quarter:
            return Path { q in  // Viertelellipse wie border-radius 0 0 0 100 %
                q.move(to: CGPoint(x: rect.minX, y: rect.minY))
                q.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                q.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                q.addArc(center: .zero, radius: 1, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false,
                         transform: CGAffineTransform(translationX: rect.maxX, y: rect.minY).scaledBy(x: rect.width, y: rect.height))
                q.closeSubpath()
            }
        case .tab(let r):
            let r = min(r, rect.height / 2)
            return UnevenRoundedRectangle(topLeadingRadius: r, bottomLeadingRadius: r).path(in: rect)
        }
    }
}

extension View {
    /// Wie `position:absolute` im Mockup: Abstand zu den angegebenen Kanten (negativ = läuft aus dem Rand).
    /// Das gesetzte Element nimmt keinen Platz ein und liegt hinter dem Inhalt.
    func pinned<V: View>(left: CGFloat? = nil, right: CGFloat? = nil, top: CGFloat? = nil, bottom: CGFloat? = nil,
                         @ViewBuilder _ content: () -> V) -> some View {
        let alignment = Alignment(horizontal: right != nil ? .trailing : .leading, vertical: bottom != nil ? .bottom : .top)
        return background(alignment: alignment) {
            content().offset(x: right.map { -$0 } ?? (left ?? 0), y: bottom.map { -$0 } ?? (top ?? 0))
        }
    }

    /// Pastell-Form am Rand, Maße und Lage 1:1 aus dem Mockup-CSS.
    func edgeForm(_ kind: EdgeForm.Kind, _ color: Color, width: CGFloat, height: CGFloat,
                  left: CGFloat? = nil, right: CGFloat? = nil, top: CGFloat? = nil, bottom: CGFloat? = nil) -> some View {
        pinned(left: left, right: right, top: top, bottom: bottom) {
            EdgeForm(kind).fill(color).frame(width: width, height: height).accessibilityHidden(true)
        }
    }

    /// Gericht-Teller (`.plate`): Kreis, 6er-Rand in `card`, weicher Schatten.
    func plate(_ size: CGFloat) -> some View {
        frame(width: size, height: size)
            .clipShape(Circle())
            .padding(Theme.S.plateRing)
            .background(Theme.C.card, in: Circle())
            .plateShadow()
    }
}

// MARK: Linien, Zahlen, Zeilen

/// Haarlinie 1.5 (`.hr`, Zeilen-Oberkante).
struct Hairline: View {
    var color = Theme.C.line

    var body: some View { Rectangle().fill(color).frame(height: Theme.S.hair) }
}

/// Kleines Label in Großbuchstaben (`.lbl` 11/800 +0.08 em, `.sec2` 13/800 +0.06 em).
struct SectionLabel: View {
    let text: String
    var big = false

    init(_ text: String, big: Bool = false) {
        self.text = text
        self.big = big
    }

    var body: some View {
        Text(text.uppercased())
            .font(big ? Theme.F.sec2 : Theme.F.lbl)
            .tracking(big ? 13 * 0.06 : 11 * 0.08)
            .foregroundStyle(Theme.C.ink2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Große Zahl mit Haarlinie darüber, Label links oben (`.stat` + `.num`).
struct StatNumber: View {
    let label: String
    let value: String
    var unit: String?
    var size: CGFloat = 64
    var mute = false

    var body: some View {
        let color = mute ? Theme.C.ink3 : Theme.C.ink
        VStack(spacing: 6) {
            Hairline(color: color)
            HStack(alignment: .top) {
                Text(label).font(Theme.F.text(12, .bold, relativeTo: .caption)).foregroundStyle(color)
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    BigNumber(value, size: size)
                    if let unit { Text(unit).font(Theme.F.num(size * 0.38)).tracking(Theme.F.numTracking(size * 0.38)) }
                }
                .foregroundStyle(color)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Zahl in Inter Tight (`.num`): Laufweite −0.05 em, zählt bei Änderung weich hoch/runter.
struct BigNumber: View {
    let text: String
    var size: CGFloat

    init(_ text: String, size: CGFloat) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(Theme.F.num(size))
            .tracking(Theme.F.numTracking(size))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.numericText())
    }
}

/// Zeile statt Kachel (`.irow`): Kreis 48 mit Bild, Name in Serif 19, rechts frei.
struct IRow<Lead: View, Trail: View>: View {
    let name: String
    var sub: String?
    var tint: Color = Theme.C.blue1
    var line = true
    @ViewBuilder var lead: Lead
    @ViewBuilder var trail: Trail

    var body: some View {
        HStack(spacing: 14) {
            lead.frame(width: Theme.S.rowCircle, height: Theme.S.rowCircle).background(tint, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(Theme.F.rowName).lineLimit(2)
                if let sub { Text(sub).font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2).lineLimit(1) }
            }
            Spacer(minLength: 8)
            trail
        }
        .frame(minHeight: Theme.S.row)
        .overlay(alignment: .top) { if line { Hairline() } }
        .contentShape(Rectangle())
    }
}

extension IRow where Trail == EmptyView {
    init(name: String, sub: String? = nil, tint: Color = Theme.C.blue1, line: Bool = true, @ViewBuilder lead: () -> Lead) {
        self.init(name: name, sub: sub, tint: tint, line: line, lead: lead, trail: { EmptyView() })
    }
}

/// Haken-Kreis (`.ck`).
struct CheckCircle: View {
    var on: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? Theme.C.ink : Theme.C.ink3, lineWidth: 2)
                .background(Circle().fill(on ? Theme.C.ink : .clear))
            if on { Icon(.check, size: 16).foregroundStyle(Theme.C.onInk).transition(.scale.combined(with: .opacity)) }
        }
        .frame(width: Theme.S.check, height: Theme.S.check)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: on)
        .accessibilityLabel(on ? "erledigt" : "offen")
    }
}

// MARK: Knöpfe, Felder, Schalter

/// `.btn` (Tinte oder Blau) – Höhe 56, Kapsel, 16/800.
struct PrimaryButton: View {
    enum Style { case ink, blue }

    let title: String
    var icon: Icon8?
    var style: Style = .ink
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Icon(icon, size: 20) }
                Text(title)
            }
            .font(Theme.F.button)
            .foregroundStyle(style == .ink ? Theme.C.onInk : Theme.C.ink)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, minHeight: Theme.S.button)
            .background(style == .ink ? Theme.C.ink : Theme.C.blue, in: Capsule())
            .opacity(disabled ? 0.35 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(disabled)
    }
}

/// `.btn2` – Umriss in Tinte, Höhe 52, 15/800.
struct OutlineButton: View {
    let title: String
    var icon: Icon8?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Icon(icon, size: 20) }
                Text(title)
            }
            .font(Theme.F.button2)
            .foregroundStyle(Theme.C.ink)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: Theme.S.button2)
            .overlay(Capsule().strokeBorder(Theme.C.ink, lineWidth: Theme.S.hair))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Runder Knopf: Tinte gefüllt (`.circle`) oder mit Haarlinie (`.x`).
struct CircleButton: View {
    let icon: Icon8
    var size: CGFloat = Theme.S.close
    var filled = false
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(icon, size: size >= 44 ? 22 : 18)
                .foregroundStyle(filled ? Theme.C.onInk : Theme.C.ink)
                .frame(width: size, height: size)
                .background(filled ? Theme.C.ink : .clear, in: Circle())
                .overlay { if !filled { Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// Schließen (`.x`): 40er-Kreis mit Haarlinie.
struct CloseButton: View {
    var label = "Schließen"
    let action: () -> Void

    var body: some View { CircleButton(icon: .x, label: label, action: action) }
}

/// Eingabefeld-Look (`.field`): Kapsel, `card`, Haarlinie.
struct FieldBox<Content: View>: View {
    var icon: Icon8?
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            if let icon { Icon(icon, size: 20).foregroundStyle(Theme.C.ink2) }
            content
        }
        .font(Theme.F.text(15, .semibold, relativeTo: .body))
        .foregroundStyle(Theme.C.ink)
        .padding(.horizontal, 18)
        .frame(minHeight: Theme.S.field)
        .background(Theme.C.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
    }
}

/// Segment-Umschalter (`.seg`).
struct Segmented8<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, title in
                let on = value == selection
                Button { withAnimation(Theme.spring) { selection = value } } label: {
                    Text(title)
                        .font(Theme.F.text(13, .bold, relativeTo: .footnote))
                        .lineLimit(1)
                        .foregroundStyle(on ? Theme.C.onInk : Theme.C.ink2)
                        .frame(maxWidth: .infinity, minHeight: Theme.S.segment)
                        .background { if on { Capsule().fill(Theme.C.ink).matchedGeometryEffect(id: "seg", in: pill) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
    }
}

/// Schalter (`.sw`) 50 × 30: aus `ink3`, an Tinte.
struct Toggle8Style: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { configuration.isOn.toggle() } } label: {
            HStack {
                ToggleLabel8 { configuration.label }
                Spacer(minLength: 12)
                Capsule().fill(configuration.isOn ? Theme.C.ink : Theme.C.ink3)
                    .frame(width: Theme.S.switchSize.width, height: Theme.S.switchSize.height)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(.white).frame(width: 24, height: 24).padding(3)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "an" : "aus")
    }
}

/// Titel des `.v8`-Schalters; `.labelsHidden()` blendet ihn aus (eigene Styles beachten das sonst nicht).
private struct ToggleLabel8<L: View>: View {
    @ViewBuilder let label: L

    var body: some View {
        if #available(iOS 18.0, *) { Visible(label: label) } else { label }  // shortcut: iOS 17 zeigt den Titel weiter
    }

    @available(iOS 18.0, *)
    private struct Visible: View {
        let label: L
        @Environment(\.labelsVisibility) private var visibility
        var body: some View { if visibility != .hidden { label } }
    }
}

extension ToggleStyle where Self == Toggle8Style {
    static var v8: Toggle8Style { Toggle8Style() }
}

/// Mengen-Stepper (`.stepper`).
struct Stepper8: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...99
    var format: (Int) -> String = { "\($0)" }

    var body: some View {
        HStack(spacing: 12) {
            knob(.minus, "weniger") { value = max(range.lowerBound, value - 1) }
            Text(format(value)).font(Theme.F.text(15, .extrabold)).monospacedDigit().contentTransition(.numericText())
            knob(.plus, "mehr") { value = min(range.upperBound, value + 1) }
        }
        .padding(.horizontal, 5)
        .frame(height: Theme.S.stepper)
        .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
        .sensoryFeedback(.selection, trigger: value)
    }

    private func knob(_ icon: Icon8, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button { withAnimation(Theme.spring) { action() } } label: {
            Icon(icon, size: 16).frame(width: Theme.S.stepperKnob, height: Theme.S.stepperKnob)
                .background(Theme.C.card, in: Circle())
                .frame(minWidth: 44, minHeight: 44).contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

// MARK: Chips, Pillen

/// Filter-Chip (`.chip`): Haarlinie, an = Tinte.
struct Chip8: View {
    let title: String
    var on = false
    var icon: Icon8?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Icon(icon, size: 16) }
                Text(title).lineLimit(1)
            }
            .font(Theme.F.chip)
            .foregroundStyle(on ? Theme.C.onInk : Theme.C.ink2)
            .padding(.horizontal, 15)
            .frame(height: Theme.S.chip)
            .background(on ? Theme.C.ink : .clear, in: Capsule())
            .overlay { if !on { Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Tinten-Pille (`.pill`) 30 hoch.
struct Pill8: View {
    let text: String
    var icon: Icon8?

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Icon(icon, size: 15) }
            Text(text)
        }
        .font(Theme.F.pill)
        .foregroundStyle(Theme.C.onInk)
        .padding(.horizontal, 12)
        .frame(height: Theme.S.pill)
        .background(Theme.C.ink, in: Capsule())
    }
}

/// Rabatt (`.deal`) 22 hoch.
struct DealPill: View {
    let text: String

    var body: some View {
        Text(text).font(Theme.F.deal).foregroundStyle(.white)
            .padding(.horizontal, 8).frame(height: Theme.S.dealPill)
            .background(Theme.C.deal, in: Capsule())
    }
}

/// Weiche Pille (`.soft`, `.ok` = sage, `.warn`).
struct SoftPill: View {
    let text: String
    var icon: Icon8?
    var tint = Theme.C.blue1

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Icon(icon, size: 14) }
            Text(text)
        }
        .font(Theme.F.soft)
        .foregroundStyle(Theme.C.ink)
        .padding(.horizontal, 10)
        .frame(height: Theme.S.softPill)
        .background(tint, in: Capsule())
    }
}

// MARK: Fortschritt, Laden

/// Balken (`.bar`) 8 hoch.
struct ProgressBar8: View {
    var value: Double  // 0…1
    var color = Theme.C.ink

    var body: some View {
        Capsule().fill(Theme.C.line).frame(height: Theme.S.bar)
            .overlay(alignment: .leading) {
                GeometryReader { g in Capsule().fill(color).frame(width: g.size.width * min(max(value, 0), 1)) }
            }
            .clipShape(Capsule())
            .animation(Theme.spring, value: value)
            .accessibilityValue("\(Int(value * 100)) Prozent")
    }
}

/// Schritt-Striche (`.prog`).
struct StepBars: View {
    let count: Int
    let current: Int  // 0-basiert, bis einschließlich aktiv

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule().fill(i <= current ? Theme.C.ink : Theme.C.line).frame(height: 4)
            }
        }
        .animation(Theme.spring, value: current)
        .accessibilityLabel("Schritt \(current + 1) von \(count)")
    }
}

/// Seiten-Punkte (`.dots`).
struct Dots8: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Circle().fill(i == current ? Theme.C.ink : Theme.C.ink3).frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Platzhalter beim Laden (`.sk`): Verlauf line → card → line.
struct Skeleton8: View {
    var width: CGFloat?
    var height: CGFloat
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.R.skeleton, style: .continuous)
            .fill(LinearGradient(colors: [Theme.C.line, Theme.C.card, Theme.C.line],
                                 startPoint: UnitPoint(x: phase, y: 0.5), endPoint: UnitPoint(x: phase + 1, y: 0.5)))
            .frame(width: width, height: height)
            .onAppear { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 } }
            .accessibilityLabel("Lädt")
    }
}

// MARK: Sheet

extension View {
    /// Sheet-Look v8 (`.sheet`): Grund `bg`, Radius 36 oben, eigener Griff 40 × 5 in `ink3`.
    func sheet8() -> some View {
        self
            .padding(.top, 33)  // 12 + Griff 5 + 16 wie im Mockup
            .overlay(alignment: .top) {
                Capsule().fill(Theme.C.ink3).frame(width: Theme.S.grip.width, height: Theme.S.grip.height).padding(.top, 12)
                    .accessibilityHidden(true)
            }
            .presentationCornerRadius(Theme.R.sheet)
            .presentationBackground(Theme.C.bg)
            .presentationDragIndicator(.hidden)
    }
}

// MARK: Bewegung (animationen-v8.html)

/// CSS-Kurve `cubic-bezier(x1,y1,x2,y2)` für Keyframe-Abschnitte.
struct Bezier {
    let x1, y1, x2, y2: Double
    static let linear = Bezier(x1: 0, y1: 0, x2: 1, y2: 1)
    static let ease = Bezier(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
    static let easeInOut = Bezier(x1: 0.42, y1: 0, x2: 0.58, y2: 1)

    func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        func bx(_ t: Double) -> Double { 3 * (1 - t) * (1 - t) * t * x1 + 3 * (1 - t) * t * t * x2 + t * t * t }
        func by(_ t: Double) -> Double { 3 * (1 - t) * (1 - t) * t * y1 + 3 * (1 - t) * t * t * y2 + t * t * t }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<24 {  // Bisektion reicht für Animationen
            if bx(t) < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return by(t)
    }
}

/// Keyframes wie in CSS: Stopps (Anteil 0…1, Werte), Kurve gilt ab dem jeweiligen Stopp.
struct Keyframes {
    let stops: [(at: Double, values: [Double], curve: Bezier)]

    func callAsFunction(_ t: Double) -> [Double] {
        guard let first = stops.first else { return [] }
        if t <= first.at { return first.values }
        for (a, b) in zip(stops, stops.dropFirst()) where t <= b.at {
            let k = a.curve((t - a.at) / max(b.at - a.at, 0.0001))
            return zip(a.values, b.values).map { $0 + ($1 - $0) * k }
        }
        return stops.last!.values
    }
}

/// Lange Aktionen (`.potld`): Zutaten hüpfen nacheinander in den Topf, Deckel klappert, Dampf steigt.
/// Ohne Bewegung (Bedienungshilfen) steht der Topf still.
struct PotLoader: View {
    var ingredients = ["tomato", "garlic", "basil", "pasta"]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // potld-hop 5 s linear; Abschnitte ab 0 % und 20 % mit eigener Kurve. Werte: x, y, Drehung, Größe
    private static let hop = Keyframes(stops: [
        (0, [-150, 60, 0, 0.9], Bezier(x1: 0.2, y1: 0.7, x2: 0.4, y2: 1)),
        (0.20, [-55, -95, 140, 1], Bezier(x1: 0.6, y1: 0, x2: 0.9, y2: 0.6)),
        (0.34, [0, 10, 260, 0.85], .linear),
        (0.40, [0, 60, 280, 0.6], .linear),
        (1, [0, 60, 280, 0.6], .linear),
    ])
    // Deckkraft eigene Stopps: 0 % → 4 % sichtbar, bis 40 % sichtbar, 41 % weg
    private static let hopOpacity = Keyframes(stops: [(0, [0], .linear), (0.04, [1], .linear), (0.40, [1], .linear), (0.41, [0], .linear), (1, [0], .linear)])
    private static let lid = Keyframes(stops: [
        (0, [0, 0], .ease), (0.26, [0, 0], .ease), (0.34, [-26, -12], .ease), (0.44, [0, 0], .ease),
        (0.48, [-7, -3], .ease), (0.52, [0, 0], .ease), (1, [0, 0], .ease),
    ])
    private static let squash = Keyframes(stops: [
        (0, [1, 1, 0], .ease), (0.38, [1, 1, 0], .ease), (0.46, [1.05, 0.95, 5], .ease), (0.54, [0.98, 1.03, 0], .ease),
        (0.62, [1, 1, 0], .ease), (1, [1, 1, 0], .ease),
    ])

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            let t = reduceMotion ? 0 : ctx.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                Circle().fill(Theme.C.blue1).frame(width: 240, height: 240)
                    .scaleEffect(1 + 0.04 * sin(.pi * (t.truncatingRemainder(dividingBy: 3) / 3)))  // potld-breathe
                if !reduceMotion {
                    ForEach(Array(ingredients.prefix(4).enumerated()), id: \.offset) { i, name in
                        let p = ((t - Double(i) * 1.25) / 5).truncatingRemainder(dividingBy: 1)
                        let q = p < 0 ? p + 1 : p
                        let v = Self.hop(q)
                        let s: Double = i % 2 == 0 ? 1 : -1  // nth-of-type ungerade → +1
                        Ill(name).frame(width: 140, height: 140)
                            .scaleEffect(v[3]).rotationEffect(.degrees(s * v[2]))
                            .offset(x: s * v[0], y: v[1]).opacity(Self.hopOpacity(q)[0])
                            .offset(x: 50, y: 6)
                    }
                }
                let sq = Self.squash((t / 1.25).truncatingRemainder(dividingBy: 1))
                Ill("pot-body").frame(width: 240, height: 240)
                    .scaleEffect(x: sq[0], y: sq[1]).offset(y: sq[2])
                    .offset(y: 16)
                let l = Self.lid((t / 1.25).truncatingRemainder(dividingBy: 1))
                Ill("pot-lid").frame(width: 240, height: 240)
                    .rotationEffect(.degrees(l[1]), anchor: UnitPoint(x: 0.3, y: 0.5)).offset(y: l[0])
                    .offset(y: 16)
                if !reduceMotion { Steam(t: t).frame(width: 60, height: 70).offset(x: 90, y: -36) }
            }
            .frame(width: 240, height: 240)
        }
        .accessibilityElement()
        .accessibilityLabel("Lädt")
    }

    /// Drei Dampf-Wellen (`.steam`), jede 2,4 s, um 0,8 s versetzt.
    private struct Steam: View {
        let t: Double

        var body: some View {
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let p = ((t - Double(i) * 0.8) / 2.4).truncatingRemainder(dividingBy: 1)
                    let q = p < 0 ? p + 1 : p
                    let offset = 60 - 120 * Bezier.easeInOut(q)  // stroke-dashoffset 60 → −60 bei Strich 60
                    let length = 62.0  // ungefähre Pfadlänge
                    wave(i)
                        .trim(from: min(1, max(0, -offset / length)), to: min(1, max(0, (60 - offset) / length)))
                        .stroke(Theme.C.ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .opacity(q < 0.3 ? Bezier.easeInOut(q / 0.3) : 1 - Bezier.easeInOut((q - 0.3) / 0.7))
                }
            }
        }

        private func wave(_ i: Int) -> Path {
            // M12 66c-8-10 8-16 0-28s8-16 0-28 · M30 60c-8-10 8-16 0-28s8-14 0-24 · M48 66c…
            let x: CGFloat = [12, 30, 48][i], y: CGFloat = i == 1 ? 60 : 66
            var p = Path()
            p.move(to: CGPoint(x: x, y: y))
            p.addCurve(to: CGPoint(x: x, y: y - 28), control1: CGPoint(x: x - 8, y: y - 10), control2: CGPoint(x: x + 8, y: y - 16))
            let top: CGFloat = i == 1 ? 24 : 28
            p.addCurve(to: CGPoint(x: x, y: y - 28 - top), control1: CGPoint(x: x - 8, y: y - 28 - 12), control2: CGPoint(x: x + 8, y: y - 28 - (i == 1 ? 14 : 16)))
            return p
        }
    }
}

/// Wochentage füllen sich beim Plan-Erstellen (`.potdays`).
struct PotDays: View {
    let done: Int  // so viele Tage fertig (on)
    var labels = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, day in
                let on = i < done, now = i == done
                Text(day)
                    .font(Theme.F.text(13, .extrabold, relativeTo: .footnote))
                    .foregroundStyle(on ? Theme.C.onInk : now ? Theme.C.ink : Theme.C.ink3)
                    .frame(width: 38, height: 38)
                    .background(on ? Theme.C.ink : .clear, in: Circle())
                    .overlay { if !on { Circle().strokeBorder(now ? Theme.C.ink : Theme.C.line, lineWidth: now ? 2 : Theme.S.hair) } }
                    .scaleEffect(now && pulse ? 1.12 : 1)
                    .transition(.scale(scale: 0.4))
                    .animation(.spring(response: 0.5, dampingFraction: 0.55), value: on)
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.625).repeatForever()) { pulse = true } }
        .accessibilityLabel("\(done) von \(labels.count) Tagen fertig")
    }
}

/// Kleiner Lader für Knöpfe und Zeilen (`.hop3`): drei Zutaten hüpfen nacheinander.
struct Hop3: View {
    var names = ["tomato", "garlic", "basil"]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let jump = Keyframes(stops: [(0, [0, 0], .easeInOut), (0.25, [-12, -14], .easeInOut), (0.6, [0, 0], .easeInOut), (1, [0, 0], .easeInOut)])

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: -32) {
                ForEach(Array(names.prefix(3).enumerated()), id: \.offset) { i, name in
                    let p = ((t - Double(i) * 0.15) / 1.1).truncatingRemainder(dividingBy: 1)
                    let v = reduceMotion ? [0.0, 0.0] : Self.jump(p < 0 ? p + 1 : p)
                    Ill(name).frame(width: 62, height: 62).rotationEffect(.degrees(v[1])).offset(y: v[0])
                }
            }
            .frame(height: 30)
        }
        .accessibilityLabel("Lädt")
    }
}

// MARK: Nav mit Mulde

/// Leiste mit Mulde unter dem aktiven Symbol (Mockup-Skript in redesign-v8.html). `center` = x der Mulde, animierbar.
struct NotchShape: Shape {
    var center: CGFloat

    var animatableData: CGFloat {
        get { center }
        set { center = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let t = Theme.S.navT, r = Theme.S.navR, c = center
        var p = Path()
        p.move(to: CGPoint(x: 0, y: t))
        p.addLine(to: CGPoint(x: c - r - 16, y: t))
        p.addQuadCurve(to: CGPoint(x: c - r, y: t + 12), control: CGPoint(x: c - r, y: t))
        p.addArc(center: CGPoint(x: c, y: t + 12), radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        p.addQuadCurve(to: CGPoint(x: c + r + 16, y: t), control: CGPoint(x: c + r, y: t))
        p.addLine(to: CGPoint(x: rect.maxX, y: t))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: 0, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Nav v8: nur Icons, weiße Leiste mit Mulde, aktives Symbol schwebt im blauen 58er-Kreis. Mulde gleitet beim Wechsel.
struct NotchTabBar: View {
    @Binding var selected: AppTab
    var badges: [AppTab: Int] = [:]  // z. B. Merklisten-Treffer am Angebote-Tab (27)
    var reselect: () -> Void = {}

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, step = w / 5
            let x = { (i: Int) in step / 2 + step * CGFloat(i) }  // 390 breit: 39 + 78 · i
            let on = AppTab.allCases.firstIndex(of: selected) ?? 0
            ZStack(alignment: .topLeading) {
                NotchShape(center: x(on))
                    .fill(Theme.C.navBar)
                    .shadow(color: Color(hex: 0x281E14).opacity(0.07), radius: 7, y: -6)
                Circle().fill(Theme.C.blue)
                    .frame(width: Theme.S.navActive, height: Theme.S.navActive)
                    .position(x: x(on), y: Theme.S.navT + 12)
                ForEach(Array(AppTab.allCases.enumerated()), id: \.offset) { i, tab in
                    item(tab, active: i == on).position(x: x(i), y: i == on ? Theme.S.navT + 12 : Theme.S.navT + 34)
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.78), value: selected)
        }
        .frame(height: Theme.S.nav)
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func item(_ tab: AppTab, active: Bool) -> some View {
        Button {
            if selected == tab { reselect() }
            selected = tab
        } label: {
            Icon(tab.icon)
                .foregroundStyle(active ? Theme.C.ink : Theme.C.ink3)
                .frame(width: active ? Theme.S.navActive : Theme.S.navTap, height: active ? Theme.S.navActive : Theme.S.navTap)
                .overlay(alignment: .topTrailing) {
                    if let n = badges[tab], n > 0, !active {
                        Text("\(n)").font(Theme.F.text(10, .extrabold, relativeTo: .caption2)).foregroundStyle(.white)
                            .padding(.horizontal, 4).frame(minWidth: 18, minHeight: 18)
                            .background(Theme.C.deal, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.C.navBar, lineWidth: 2))
                            .offset(x: 2, y: -2)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(badges[tab].map { n in n > 0 ? "\(tab.title), \(n) Treffer" : tab.title } ?? tab.title)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
