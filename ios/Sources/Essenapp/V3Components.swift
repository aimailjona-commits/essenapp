import CoreImage
import SwiftUI

// Neue Bausteine aus docs/ui/redesign-v3.md Abschnitt 5 (v3 „Küchen-Pinnwand“, E87).

// MARK: Formen

/// Prospekt-Stern: `points` Ecken abwechselnd außen/innen, erster Punkt oben.
struct BurstShape: Shape {
    var points = 28
    var inner = 0.82

    func path(in r: CGRect) -> Path {
        Path { p in
            for i in 0..<points {
                let radius = (i.isMultiple(of: 2) ? 1 : inner) * min(r.width, r.height) / 2
                let a = Double(i) / Double(points) * 2 * .pi - .pi / 2
                let pt = CGPoint(x: r.midX + radius * cos(a), y: r.midY + radius * sin(a))
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.closeSubpath()
        }
    }
}

/// Kassenbon: Rechteck mit Zackenrand oben und unten (Zahnbreite 2 × `tooth`).
struct ReceiptShape: Shape {
    var tooth: CGFloat = 9

    func path(in r: CGRect) -> Path {
        let n = max(1, Int((r.width / (tooth * 2)).rounded()))
        let w = r.width / CGFloat(n)
        return Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY + tooth))
            for i in 0..<n {  // oben: Spitzen nach oben
                p.addLine(to: CGPoint(x: r.minX + w * (CGFloat(i) + 0.5), y: r.minY))
                p.addLine(to: CGPoint(x: r.minX + w * CGFloat(i + 1), y: r.minY + tooth))
            }
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - tooth))
            for i in (0..<n).reversed() {  // unten: Spitzen nach unten
                p.addLine(to: CGPoint(x: r.minX + w * (CGFloat(i) + 0.5), y: r.maxY))
                p.addLine(to: CGPoint(x: r.minX + w * CGFloat(i), y: r.maxY - tooth))
            }
            p.closeSubpath()
        }
    }
}

/// Coupon: abgerundetes Rechteck mit halbrunden Kerben links/rechts bei `at` der Höhe.
struct CouponShape: Shape {
    var radius: CGFloat = 24
    var notch: CGFloat = 13
    var at: CGFloat = 0.64

    func path(in r: CGRect) -> Path {
        var p = Path(roundedRect: r, cornerRadius: radius, style: .continuous)
        let y = r.minY + r.height * at
        p.addEllipse(in: CGRect(x: r.minX - notch, y: y - notch, width: notch * 2, height: notch * 2))
        p.addEllipse(in: CGRect(x: r.maxX - notch, y: y - notch, width: notch * 2, height: notch * 2))
        return p
    }
}

/// Ordner: Reiter oben links (`tab` Breite/Höhe), Körper ab `bodyTop`, Ecke unter dem Reiter gerade (nahtlos).
struct FolderShape: Shape {
    var tabWidth: CGFloat = 0.56
    var tabHeight: CGFloat = 34
    var bodyTop: CGFloat = 22
    var tabRadius: CGFloat = 18
    var radius: CGFloat = 24

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.addPath(Path(roundedRect: CGRect(x: r.minX, y: r.minY, width: r.width * tabWidth, height: tabHeight + tabRadius),
                       cornerRadii: .init(topLeading: tabRadius, topTrailing: tabRadius), style: .continuous))
        p.addPath(Path(roundedRect: CGRect(x: r.minX, y: r.minY + bodyTop, width: r.width, height: r.height - bodyTop),
                       cornerRadii: .init(topLeading: 0, bottomLeading: radius, bottomTrailing: radius, topTrailing: radius), style: .continuous))
        return p
    }
}

/// Handgemalter Kreis (Pfad im 120×50-Rahmen, auf den Rahmen gestreckt).
struct ScribbleShape: Shape {
    func path(in r: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x / 120 * r.width, y: r.minY + y / 50 * r.height) }
        return Path { p in
            p.move(to: pt(22, 6))
            p.addCurve(to: pt(117, 24), control1: pt(62, 0), control2: pt(112, 4))
            p.addCurve(to: pt(42, 48), control1: pt(121, 44), control2: pt(72, 50))
            p.addCurve(to: pt(3, 22), control1: pt(10, 46), control2: pt(0, 34))
            p.addCurve(to: pt(60, 3), control1: pt(6, 10), control2: pt(30, 4))
        }
    }
}

// MARK: Bausteine

/// Rabatt als schräger Stern (−8°). Größen 58 / 66 / 100.
struct PriceBurst: View {
    let percent: Int
    var size: CGFloat = 58
    var fill = Theme.C.deal
    var ink: Color = .white

    var body: some View {
        let font: CGFloat = size >= 100 ? 25 : size >= 66 ? 17 : 15
        (Text("−\(percent)") + Text("%").font(Theme.F.burst(font * 0.62)))
            .font(Theme.F.burst(font))
            .tracking(-0.5)
            .lineLimit(1).minimumScaleFactor(0.6)
            .foregroundStyle(ink)
            .frame(width: size * 0.7)
            .frame(width: size, height: size)
            .background(BurstShape().fill(fill))
            .rotationEffect(.degrees(-8))
            .accessibilityLabel("minus \(percent) Prozent")
    }
}

/// Handkreis um einen Betrag; zeichnet sich beim Erscheinen selbst (bei „Bewegung reduzieren“ sofort).
struct Scribble<Content: View>: View {
    var color = Theme.C.lime
    @ViewBuilder let content: () -> Content
    @State private var drawn: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content()
            .padding(.horizontal, 3)
            .overlay {
                ScribbleShape().trim(from: 0, to: drawn)
                    .stroke(color, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                    .padding(.horizontal, -12).padding(.vertical, -9)
                    .allowsHitTesting(false)
            }
            .onAppear {
                if reduceMotion { drawn = 1 } else { withAnimation(.easeOut(duration: 0.6).delay(0.2)) { drawn = 1 } }
            }
    }
}

/// Runde Knöpfe in einer Gruppe (GoodNotes-Leiste). `compact` = Karten-Variante (34, Schwarz 8 %).
struct ActionCluster: View {
    struct Item: Identifiable {
        let symbol: String
        let label: String
        var main = false
        let action: () -> Void
        var id: String { symbol + label }
    }

    let items: [Item]
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 6 : 2) {
            ForEach(items) { item in
                let size: CGFloat = compact ? 34 : item.main ? 56 : 48
                Button(action: item.action) {
                    Image(systemName: item.symbol)
                        .font(.system(size: compact ? 14 : 18, weight: .semibold))
                        .foregroundStyle(item.main ? Theme.C.onAction : Theme.C.text1)
                        .frame(width: size, height: size)
                        .background(item.main ? Theme.C.action : compact ? Color.black.opacity(0.08) : .clear, in: Circle())
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(item.label)
            }
        }
        .padding(compact ? 0 : 4)
        .background(compact ? .clear : Theme.C.surface, in: Capsule())
    }
}

/// Foto-Sticker im Tages-Satz: Kreis 46, weißer Rand 3, leicht gedreht.
struct PhotoSticker: View {
    let url: URL?
    var emoji = "🍽️"
    var angle: Double = -8

    var body: some View {
        Plate(url: url, size: 40, emoji: emoji)
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .frame(width: 46, height: 46)
            .shadow(color: .black.opacity(0.25), radius: 7, y: 6)
            .rotationEffect(.degrees(angle))
    }
}

/// Summen-Leiste unten (ersetzt den festen Aktionsbereich): Label + Wert, „››››“, Limetten-Knopf.
struct TotalBar<Value: View>: View {
    let label: String
    @ViewBuilder let value: () -> Value
    let buttonTitle: String
    var symbol = "bag"
    let action: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(.caption2, weight: .semibold)).foregroundStyle(Theme.C.onInk3)
                value().font(.system(.title3, weight: .heavy)).tracking(-0.4).foregroundStyle(.white)
            }
            Spacer(minLength: 8)
            Text("››››").font(.system(.headline, weight: .heavy)).tracking(-2).foregroundStyle(Theme.C.lime).padding(.trailing, 12)
                .accessibilityHidden(true)
            Button(action: action) { Label(buttonTitle, systemImage: symbol) }
                .buttonStyle(AccentButtonStyle()).fixedSize()
        }
        .padding(.leading, 24).padding(.trailing, 8)
        .frame(height: Theme.S.totalBar)
        .background(Theme.C.bar, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.C.barEdge, lineWidth: 1))
        .floatShadow()
        .padding(.horizontal, Theme.S.barSide)
    }
}

/// Mengenwahl: klein (Preis-Pille hinter schwarzer Kapsel) oder groß (− Zahl +).
struct QtyStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...20
    var large = false
    var price: String?

    var body: some View {
        if large {
            HStack {
                button("minus", -1, size: 56, fill: Theme.C.surface, ink: Theme.C.text1)
                Spacer()
                Text("\(value)").font(.system(size: 68, weight: .black)).tracking(-3).monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                button("plus", 1, size: 56, fill: Theme.C.surface, ink: Theme.C.text1)
            }
            .padding(.horizontal, 18)
        } else {
            HStack(spacing: 0) {
                if let price {
                    Text(price).font(.system(.callout, weight: .heavy)).monospacedDigit()
                        .padding(.leading, 18).padding(.trailing, 70).frame(height: 48)
                        .background(Theme.C.surface, in: Capsule())
                        .padding(.trailing, -62)
                }
                HStack(spacing: 4) {
                    button("minus", -1, size: 36, fill: .clear, ink: .white)
                    Text("\(value)").font(.system(.subheadline, weight: .bold)).monospacedDigit()
                        .frame(width: 28, height: 28).background(.white, in: Circle()).foregroundStyle(Theme.C.ink)
                        .contentTransition(.numericText())
                    button("plus", 1, size: 36, fill: .clear, ink: .white)
                }
                .padding(.horizontal, 6).frame(height: 48)
                .background(Theme.C.ink, in: Capsule())
            }
        }
    }

    private func button(_ symbol: String, _ step: Int, size: CGFloat, fill: Color, ink: Color) -> some View {
        Button { withAnimation(Theme.spring) { value = min(range.upperBound, max(range.lowerBound, value + step)) } } label: {
            Image(systemName: symbol).font(.system(size: size > 40 ? 22 : 14, weight: .bold)).foregroundStyle(ink)
                .frame(width: size, height: size).background(fill, in: Circle())
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(PressableStyle())
        .disabled(!range.contains(value + step))
        .accessibilityLabel(step > 0 ? "Mehr" : "Weniger")
        .sensoryFeedback(.selection, trigger: value)
    }
}

/// Kochschritte als Punkte: erledigt ✓ (`lime`), aktiv gefüllt, Ziel 🏁.
struct StepDots: View {
    let count: Int
    let current: Int
    var dark = true

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0...count, id: \.self) { i in
                let done = i < current, on = i == current, goal = i == count
                Text(goal ? "🏁" : done ? "✓" : "\(i + 1)")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(done ? Theme.C.onLime : on ? (dark ? Theme.C.ink : .white) : dark ? Color(hex: 0x888888) : Theme.C.chipText)
                    .frame(width: 32, height: 32)
                    .background(done ? Theme.C.lime : on ? (dark ? Color.white : Theme.C.ink) : .clear, in: Circle())
                    .overlay(Circle().strokeBorder(done || on ? .clear : dark ? Color(hex: 0x555555) : Theme.C.chipBorder, lineWidth: 1.5))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Schritt \(current + 1) von \(count)")
    }
}

/// Kassenbon-Papier mit Zackenrand und Schatten; Inhalt bekommt den Innenabstand 22/18.
struct ReceiptPaper<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .font(Theme.F.mono())
            .foregroundStyle(Color(hex: 0x222222))
            .padding(.vertical, 22).padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ReceiptShape().fill(Theme.C.paper).shadow(color: .black.opacity(0.09), radius: 7, y: 10))
    }
}

/// Gestrichelte Trennlinie im Bon.
struct ReceiptRule: View {
    var body: some View {
        Line().stroke(Theme.C.chipBorder, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .frame(height: 1.5).padding(.vertical, 10)
    }

    struct Line: Shape {
        func path(in r: CGRect) -> Path { Path { p in p.move(to: CGPoint(x: r.minX, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY)) } }
    }
}

/// Zeile im Bon: Kästchen, Name, Menge, Rabatt, Preis. Abgehakt: Limette + Haken, grau durchgestrichen.
struct ReceiptRow: View {
    let name: String
    var amount: String?
    var discount: String?
    var price: String?
    let checked: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(checked ? Color(hex: 0x222222) : .clear)
                    .frame(width: 20, height: 20)
                    .background(checked ? Theme.C.lime : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color(hex: 0x222222), lineWidth: 1.8))
                Text(name).strikethrough(checked).lineLimit(2)
                if let amount { Text(amount).foregroundStyle(checked ? Color(hex: 0xA9A398) : Theme.C.chipText) }
                if let discount, !checked { Text(discount).font(Theme.F.monoBold(11)).foregroundStyle(Theme.C.deal) }
                Spacer(minLength: 4)
                if let price { Text(price).font(Theme.F.monoBold()) }
            }
            .foregroundStyle(checked ? Color(hex: 0xA9A398) : Color(hex: 0x222222))
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
        .sensoryFeedback(.success, trigger: checked)
    }
}

/// Liste als Ordner: Reiter + Körper in einer Farbe, Logo oben links, Name/Anzahl unten, Avatar unten rechts.
struct FolderCard: View {
    let chain: String
    let title: String
    let subtitle: String
    var avatar: String?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            FolderShape().fill(Theme.storeColor(chain))
            StoreLogo(chain: chain, size: 64).padding(14).padding(.top, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(.title3, weight: .heavy)).tracking(-0.4).lineLimit(1).minimumScaleFactor(0.7)
                Text(subtitle).font(.system(.footnote, weight: .semibold)).opacity(0.65)
            }
            .foregroundStyle(Theme.C.ink)
            .padding(.horizontal, 16).padding(.bottom, 14)
            .padding(.trailing, avatar == nil ? 0 : 36)
            if let avatar {
                Text(avatar).font(.system(size: 16)).frame(width: 30, height: 30).background(.white, in: Circle())
                    .padding(14).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 172)
        .compositingGroup()
        .shadow(color: .black.opacity(0.07), radius: 7, y: 8)
        .accessibilityElement(children: .combine)
    }
}

/// Feines Papierkorn über allem (multiply, nicht antippbar). Kachel aus Resources/grain.png.
struct PaperGrain: View {
    private static let tile: UIImage? = Bundle.module.url(forResource: "grain", withExtension: "png")
        .flatMap { UIImage(contentsOfFile: $0.path) }

    var body: some View {
        if let tile = Self.tile {
            Image(uiImage: tile).resizable(resizingMode: .tile)
                .blendMode(.multiply).opacity(0.55)
                .ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

// MARK: Tages-Satz (S1)

/// Zeilenumbruch für beliebige Views (Chips, Wörter + Sticker im Tages-Satz), Zeilen vertikal zentriert.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat?  // Standard: wie `spacing`

    private func rows(_ width: CGFloat, _ subviews: Subviews) -> [(range: Range<Int>, height: CGFloat, width: CGFloat)] {
        var rows: [(Range<Int>, CGFloat, CGFloat)] = []
        var start = 0, x: CGFloat = 0, h: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + spacing + s.width > width {
                rows.append((start..<i, h, x)); start = i; x = 0; h = 0
            }
            x += (x > 0 ? spacing : 0) + s.width
            h = max(h, s.height)
        }
        if start < subviews.count { rows.append((start..<subviews.count, h, x)) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let r = rows(width, subviews)
        let height = r.map(\.height).reduce(0, +) + (lineSpacing ?? spacing) * CGFloat(max(r.count - 1, 0))
        return CGSize(width: proposal.width ?? (r.map(\.width).max() ?? 0), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(bounds.width, subviews) {
            var x = bounds.minX
            for i in row.range {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - s.height) / 2), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += row.height + (lineSpacing ?? spacing)
        }
    }
}

/// `SentenceHero`: grauer kursiver Satz, Hervorhebungen weiß, Tellerfotos als Sticker, Betrag mit Handkreis.
struct SentenceHero: View {
    enum Part {
        case text(String)
        case bold(String)
        case sticker(URL?, String, Double)
        case amount(String)
        case emoji(String)
        case glue(String)  // Satzzeichen direkt hinter dem vorigen Teil
    }

    let parts: [Part]

    private enum Token { case word(String, Bool), sticker(URL?, String, Double), amount(String), emoji(String) }

    private var tokens: [Token] {
        var out: [Token] = []
        for part in parts {
            switch part {
            case .text(let s): out += s.split(separator: " ").map { .word(String($0), false) }
            case .bold(let s): out += s.split(separator: " ").map { .word(String($0), true) }
            case .sticker(let url, let emoji, let angle): out.append(.sticker(url, emoji, angle))
            case .amount(let s): out.append(.amount(s))
            case .emoji(let e): out.append(.emoji(e))
            case .glue(let s):
                if case .word(let w, let b) = out.last { out[out.count - 1] = .word(w + s, b) } else { out.append(.word(s, false)) }
            }
        }
        return out
    }

    private var spoken: String {
        parts.compactMap { p -> String? in
            switch p {
            case .text(let s), .bold(let s), .amount(let s), .glue(let s): s
            default: nil
            }
        }.joined(separator: " ")
    }

    var body: some View {
        FlowLayout(spacing: 7, lineSpacing: 0) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                switch token {
                case .word(let w, let bold):
                    Text(w).font(bold ? Theme.F.sentenceBold : Theme.F.sentence).tracking(-0.27)
                        .foregroundStyle(bold ? .white : Theme.C.onInk2)
                        .frame(minHeight: 36)  // Zeilenhöhe 1.32
                case .sticker(let url, let emoji, let angle):
                    PhotoSticker(url: url, emoji: emoji, angle: angle).padding(.top, -8)
                case .amount(let a):
                    Scribble(color: Theme.C.lime) { Text(a).font(Theme.F.sentenceBold).foregroundStyle(.white) }
                case .emoji(let e):
                    Text(e).font(.system(size: 34)).rotationEffect(.degrees(-10)).shadow(color: .black.opacity(0.3), radius: 4, y: 6)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

// MARK: Tab-Leiste ausblenden, Foto-Farbe

/// Detail-Screens mit `TotalBar` blenden die Tab-Leiste aus (Zähler: Push auf Push bleibt ausgeblendet).
struct HidesTabBar: ViewModifier {
    @Environment(AppStore.self) private var store

    func body(content: Content) -> some View {
        content
            .onAppear { withAnimation(Theme.spring) { store.tabBarHiders += 1 } }
            .onDisappear { withAnimation(Theme.spring) { store.tabBarHiders = max(0, store.tabBarHiders - 1) } }
    }
}

extension View {
    func hidesTabBar() -> some View { modifier(HidesTabBar()) }

    /// Runder Glas-Knopf auf Fotos (Schwarz 28 % + Blur).
    func glassDark() -> some View {
        background(.ultraThinMaterial.opacity(0.6), in: Circle()).background(Color.black.opacity(0.28), in: Circle())
            .environment(\.colorScheme, .dark)
    }
}

/// Dunkle Hauptfarbe eines Fotos für den Rezept-Kopf: Durchschnittsfarbe, Helligkeit auf 27 %. Cache je URL.
enum PhotoColor {
    @MainActor private static var cache: [URL: Color] = [:]

    @MainActor static func of(_ url: URL?) async -> Color? {
        guard let url else { return nil }
        if let hit = cache[url] { return hit }
        guard let data = try? await URLSession.shared.data(from: url).0, let image = CIImage(data: data) else { return nil }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: image.extent)])
        var px = [UInt8](repeating: 0, count: 4)
        guard let out = filter?.outputImage else { return nil }
        CIContext(options: [.workingColorSpace: NSNull()])
            .render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
            .getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
        let color = Color(hue: hue, saturation: min(sat * 1.1, 0.7), brightness: 0.27)
        cache[url] = color
        return color
    }
}
