import SwiftUI
import UIKit

// Einkaufstaschen (v9 d.html `.d9-bag`): jede Liste ist eine Tasche. Marktlogo auf dem Etikett, große Zahl = offen,
// dunklerer Teil unten = erledigt, Kreise unten rechts = wer einkauft.

/// Taschenform, fest pro Kette; „Überall“ = Korb.
enum BagKind {
    case tote, plastic, paper, basket

    static func of(_ chain: String) -> BagKind {
        if chain.isEmpty { return .basket }
        let i = Labels.chains.firstIndex { c in c.key == chain } ?? chain.unicodeScalars.reduce(0) { s, u in s &+ Int(u.value) }
        return [BagKind.plastic, .tote, .paper][abs(i) % 3]  // Rewe Tüte, Edeka Stoffbeutel, dm Papiertüte wie im Mockup
    }

    /// Träger (`.h`): Abstand links/rechts und Höhe als Anteil, Strich als Anteil der Breite; Tüte hat ein Griffloch.
    fileprivate var handle: (inset: CGFloat, top: CGFloat, height: CGFloat, line: CGFloat)? {
        switch self {
        case .tote: (0.22, 0, 0.44, 0.04)
        case .plastic: nil
        case .paper: (0.33, 0.06, 0.26, 0.028)
        case .basket: (0.10, 0, 0.50, 0.04)
        }
    }

    /// Oberkante des Körpers (`.b` top) als Anteil der Höhe.
    fileprivate var bodyTop: CGFloat {
        switch self {
        case .tote: 0.32
        case .plastic: 0.04
        case .paper: 0.20
        case .basket: 0.34
        }
    }

    /// Ecken des Körpers oben/unten in pt bei Breite 128 (Tüte oben: eigene Ellipse).
    fileprivate var radii: (top: CGFloat, bottom: CGFloat) {
        switch self {
        case .tote: (4, 10)
        case .plastic: (0, 18)
        case .paper: (3, 8)
        case .basket: (6, 26)
        }
    }

    /// Etikett (`.lg` top) als Anteil der Körperhöhe.
    fileprivate var labelTop: CGFloat {
        switch self {
        case .tote: 0.13
        case .plastic: 0.24
        case .paper: 0.20
        case .basket: 0.12
        }
    }
}

/// Eine Einkaufstasche (`.d9-bag`), Breite `width`, Höhe 1,12 × Breite.
struct ShopBag: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let kind: BagKind
    let color: Color
    var width: CGFloat = 128
    var open = 0
    var done = 0
    var chain: String?  // Logo der Kette auf dem Etikett ("" = Überall-Symbol)
    var title: String?  // eigene Liste: Name auf dem Etikett
    var peeks: [String] = []  // Zeichnungen, die oben herausschauen
    var who: [String] = []  // wer einkauft
    var hole = Theme.C.bg  // Grund dahinter: Griffloch der Tüte, Ring um die Kreise
    var plain = false  // Mini-Tasche ohne Etikett und Zahl

    var body: some View {
        let w = width, h = width * 1.12, s = min(1, width / 128)
        let top = h * kind.bodyTop, bh = h - top
        let dark = color.mixed(Theme.C.ink, 0.66)
        let p = open + done == 0 ? 0 : CGFloat(done) / CGFloat(open + done)
        let shape = kind == .plastic
            ? BagShape(top: CGSize(width: w * 0.4, height: bh * 0.22), bottom: 18 * s)
            : BagShape(top: CGSize(width: kind.radii.top * s, height: kind.radii.top * s), bottom: kind.radii.bottom * s)
        ZStack(alignment: .topLeading) {
            ForEach(Array(peeks.prefix(2).enumerated()), id: \.offset) { i, name in
                Ill(name).frame(width: w * (i == 0 ? 0.54 : 0.40))
                    .rotationEffect(.degrees(i == 0 ? 0 : 14))
                    .offset(x: w * (i == 0 ? 0.14 : 0.44), y: h * (i == 0 ? 0.02 : 0.04))
            }
            if let g = kind.handle {
                let lw = w * g.line
                BagShape(arch: true).stroke(dark, lineWidth: lw)
                    .padding(lw / 2)
                    .frame(width: w * (1 - 2 * g.inset), height: h * g.height)
                    .offset(x: w * g.inset, y: h * g.top)
            }
            ZStack(alignment: .topLeading) {
                layers(w: w, bh: bh, s: s, dark: dark, p: p)
            }
            .frame(width: w, height: bh, alignment: .topLeading)
            .clipShape(shape)
            .offset(y: top)
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            if !who.isEmpty { whoCircles.offset(x: 6, y: 6) }
        }
        .accessibilityElement(children: .ignore)
    }

    @ViewBuilder private func layers(w: CGFloat, bh: CGFloat, s: CGFloat, dark: Color, p: CGFloat) -> some View {
        if kind == .basket {
            Path { q in  // geflochten: repeating-linear-gradient(0deg, c 0 10px, dunkler 10px 12px)
                var y = bh - 10 * s
                while y > 0 {
                    q.addRect(CGRect(x: 0, y: y - 2 * s, width: w, height: 2 * s))
                    y -= 12 * s
                }
            }
            .fill(color.mixed(Theme.C.ink, 0.86))
            .background(color)
        } else {
            color
        }
        if kind == .tote {  // Naht oben
            Path { q in
                q.move(to: CGPoint(x: w * 0.05, y: bh * 0.06))
                q.addLine(to: CGPoint(x: w * 0.95, y: bh * 0.06))
            }
            .stroke(color.mixed(.white, 0.55), style: StrokeStyle(lineWidth: 2 * s, dash: [6 * s, 4 * s]))
        }
        if kind == .paper {  // Umschlag oben
            Rectangle().fill(color.mixed(.white, 0.70))
                .frame(width: w, height: bh * 0.13)
                .overlay(alignment: .bottom) { Rectangle().fill(color.mixed(Theme.C.ink, 0.80)).frame(height: Theme.S.hair) }
        }
        Rectangle().fill(dark.opacity(0.22))  // Füllstand = erledigt
            .frame(width: w, height: bh * p)
            .frame(width: w, height: bh, alignment: .bottom)
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.6), value: p)
        if !plain {
            label(w: w, bh: bh)
                .padding(.vertical, 3 * s).padding(.horizontal, 6 * s)
                .frame(width: w * 0.6, height: bh * 0.3)
                .background(Theme.C.plate, in: RoundedRectangle(cornerRadius: 9 * s, style: .continuous))
                .offset(x: w * 0.2, y: bh * kind.labelTop)
            VStack(spacing: 2 * s) {
                BigNumber("\(open)", size: w * 0.25)
                Text("offen").font(Theme.F.text(w * 0.085, .extrabold, relativeTo: .caption2))
                    .foregroundStyle(color.mixed(Theme.C.ink, 0.30))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.C.ink)
            .frame(width: w, height: bh * 0.9, alignment: .bottom)
        }
        if kind == .plastic {  // Griffloch
            Capsule().fill(hole).frame(width: w * 0.28, height: bh * 0.08).offset(x: w * 0.36, y: bh * 0.06)
        }
    }

    @ViewBuilder private func label(w: CGFloat, bh: CGFloat) -> some View {
        if let title {
            labelText(title, w)
        } else if let chain, !chain.isEmpty {
            RemoteImage(url: Labels.logoURL(chain), dim: false) { labelText(Labels.chain(chain), w) }
        } else {
            Icon(.bag, size: bh * 0.3 * 0.6).foregroundStyle(Theme.C.ink)
        }
    }

    private func labelText(_ t: String, _ w: CGFloat) -> some View {
        Text(t).font(Theme.F.serif(w * 0.13, relativeTo: .caption)).foregroundStyle(Theme.C.ink).lineLimit(1).minimumScaleFactor(0.5)
    }

    /// `.d9-who`: Kreise 28 mit Anfangsbuchstabe, Ring in der Grundfarbe.
    private var whoCircles: some View {
        HStack(spacing: -8) {
            ForEach(Array(who.prefix(3)), id: \.self) { n in
                Text(String(n.prefix(1)).uppercased())
                    .font(Theme.F.text(12, .extrabold, relativeTo: .caption2))
                    .foregroundStyle(Theme.C.onInk)
                    .frame(width: 28, height: 28)
                    .background([Theme.C.blue3, Theme.C.ink, Theme.C.deal][n.unicodeScalars.reduce(0) { s, u in s &+ Int(u.value) } % 3], in: Circle())
                    .background(Circle().fill(hole).padding(-3))
            }
        }
    }

    /// Wer einkauft: wer in dieser Tasche schon abgehakt hat (das Backend kennt keine feste Zuordnung Liste ↔ Person).
    static func shoppers(_ items: [ListItemDTO]) -> [String] {
        items.filter(\.checked).map(\.checkedBy).filter { n in !n.isEmpty }.reduce(into: [String]()) { r, n in if !r.contains(n) { r.append(n) } }
    }
}

/// Rechteck mit elliptischen Ecken oben und runden Ecken unten (border-radius der Taschen); `arch` = oben ganz rund.
struct BagShape: Shape {
    var top: CGSize = .zero
    var bottom: CGFloat = 0
    var arch = false

    func path(in r: CGRect) -> Path {
        let b = min(bottom, r.width / 2, r.height / 2)
        let a = arch ? min(r.width / 2, r.height) : 0
        let t = arch ? CGSize(width: a, height: a) : CGSize(width: min(top.width, r.width / 2), height: min(top.height, r.height - b))
        let k: CGFloat = 0.4477  // 1 − 0,5523: Bézier-Näherung des Viertelkreises
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + t.height))
        p.addCurve(to: CGPoint(x: r.minX + t.width, y: r.minY), control1: CGPoint(x: r.minX, y: r.minY + t.height * k),
                   control2: CGPoint(x: r.minX + t.width * k, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - t.width, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + t.height), control1: CGPoint(x: r.maxX - t.width * k, y: r.minY),
                   control2: CGPoint(x: r.maxX, y: r.minY + t.height * k))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - b))
        p.addCurve(to: CGPoint(x: r.maxX - b, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.maxY - b * k),
                   control2: CGPoint(x: r.maxX - b * k, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + b, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.maxY - b), control1: CGPoint(x: r.minX + b * k, y: r.maxY),
                   control2: CGPoint(x: r.minX, y: r.maxY - b * k))
        if arch { return p }  // Träger: unten offen
        p.closeSubpath()
        return p
    }
}

/// „Artikel hinzufügen …“: als Feld (`.field`, 48 hoch) bzw. schwebend über der Leiste (`.d9-add`, Glas, Mikrofon im Tinten-Kreis).
struct AddField9: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var floating = false
    let add: () -> Void
    let voice: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: add) { Icon(.plus).tapArea() }
                .buttonStyle(.plain)
                .foregroundStyle(text.isEmpty ? Theme.C.ink2 : Theme.C.ink)
                .accessibilityLabel("Hinzufügen")
            TextField("", text: $text, prompt: Text("Artikel hinzufügen …").foregroundStyle(Theme.C.ink2))
                .font(Theme.F.text(15))
                .foregroundStyle(Theme.C.ink)
                .submitLabel(.done)
                .onSubmit(add)
                .focused(focus)
            Button(action: voice) {
                Icon(.mic, size: floating ? 18 : Theme.S.icon)
                    .foregroundStyle(floating ? Theme.C.onInk : Theme.C.ink)
                    .frame(width: 38, height: 38)
                    .background(floating ? Theme.C.ink : .clear, in: Circle())
                    .tapArea(3)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Per Sprache hinzufügen")
        }
        .padding(.leading, 18)
        .padding(.trailing, floating ? 8 : 11)
        .frame(height: floating ? 52 : 48)
        .background {
            if floating {
                Color.clear.glass8(Capsule())
            } else {
                Capsule().fill(Theme.C.card).overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
            }
        }
    }
}

extension AppStore {
    /// Abteilung eines Artikels: Kategorie des Angebots, sonst per Wortliste aus dem Namen ("" = Sonstiges).
    func department(_ item: ListItemDTO) -> String {
        if let c = offer(for: item)?.category, !c.isEmpty { return c }
        let n = item.name.lowercased()
        return PantryDTO.words.first { e in e.words.contains { w in n.contains(w) } }?.key ?? ""
    }

    /// Zeichnungen, die aus der Tasche schauen, aus den offenen Artikeln (ohne Doppelte).
    func bagPeeks(_ items: [ListItemDTO]) -> [String] {
        items.compactMap { i in PantryArt.of(name: i.name, category: department(i)).ill }
            .reduce(into: [String]()) { r, n in if !r.contains(n) { r.append(n) } }
    }
}

extension Color {
    /// CSS `color-mix(in srgb, self p, other)`.
    func mixed(_ other: Color, _ p: CGFloat) -> Color {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(red: r1 * p + r2 * (1 - p), green: g1 * p + g2 * (1 - p), blue: b1 * p + b2 * (1 - p), opacity: a1 * p + a2 * (1 - p))
    }
}
