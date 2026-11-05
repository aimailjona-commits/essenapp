import SwiftUI

// Feature 28: Preisverlauf im Angebotsdetail (S9). Daten und Urteil vom Backend (`GET /offers/{id}/history`, E49).

/// = backend OfferHistoryOut.
struct OfferHistoryDTO: Codable, Hashable {
    struct Point: Codable, Hashable {
        var week: String  // "2026-W45"
        var chain: String
        var priceCents: Int
        var regularPriceCents: Int?
        var isOffer: Bool
    }

    struct Low: Codable, Hashable {
        var week: String
        var chain: String
        var priceCents: Int
    }

    var points: [Point]  // letzte 12 Wochen, je Woche + Kette der günstigste Preis
    var medianCents: Int?
    var minCents: Int?
    var verdict: String  // bestpreis | gut | normal | kein_echtes | zu_wenig_daten
    var lastLow: Low?
    var avgIntervalWeeks: Double?

    /// "2026-W45" → "KW 45"
    static func kw(_ week: String) -> String { "KW \(Int(week.split(separator: "W").last ?? "") ?? 0)" }
}

/// Urteil aus dem Preisverlauf (28) als weiche Pille (`.soft`): Bestpreis (`.c-best`), Gut (`.ok`), Normal (`.c-norm`), Kein echtes (`.warn`).
enum Verdict {
    static func pill(_ verdict: String?) -> (text: String, bg: Color, fg: Color)? {
        switch verdict {
        // shortcut: .c-best (#F7D8CE/#A8402A) fehlt in Theme – aus `deal` angenähert, bis die Hauptsession Tokens ergänzt
        case "bestpreis": ("Bestpreis", Theme.C.deal.opacity(0.22), Theme.C.deal)
        case "gut": ("Gutes Angebot", Theme.C.sage, Theme.C.ink)
        case "normal": ("Normal", Theme.C.line, Theme.C.ink2)
        case "kein_echtes": ("Kein echtes Angebot", Theme.C.warn, Theme.C.ink)
        default: nil  // zu_wenig_daten: lieber kein Urteil als ein falsches
        }
    }

    /// Alte Texte (Selbsttest in Saving.swift, Push-Texte); Anzeige nutzt `pill`.
    static func badge(_ verdict: String?) -> (text: String, color: Color)? {
        switch verdict {
        case "bestpreis": ("🔥 Bestpreis", Theme.C.deal)
        case "gut": ("👍 Gutes Angebot", Theme.C.success)
        case "normal": ("😐 Normal", Theme.C.ink2)
        case "kein_echtes": ("⚠️ Kein echtes Angebot", Theme.C.warning)
        default: nil
        }
    }
}

extension AppStore {
    func offerHistory(_ id: Int) async throws -> OfferHistoryDTO {
        if demo { return Demo.history(for: id) }
        return try await api.request("GET", "/offers/\(id)/history")
    }
}

/// S9 „Preisverlauf“: Urteil, Stufenlinien der letzten 12 Wochen je Laden, diese Woche im blauen Band, Normalpreis gestrichelt;
/// Antippen zeigt Werte. Darunter Median und Tiefstpreis; „Zuletzt so günstig“ und „alle N Wochen“ hinter „Mehr ›“.
struct PriceHistoryCard: View {
    @Environment(AppStore.self) private var store
    let offer: OfferDTO
    @State private var data: OfferHistoryDTO?
    @State private var failed = false
    @State private var more = false
    @State private var selected: Int?
    @State private var width: CGFloat = 342

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Preisverlauf").font(Theme.F.t2)
                Spacer()
                if let v = Verdict.pill(data?.verdict) {
                    TintPill(text: v.text, bg: v.bg, fg: v.fg).transition(.scale.combined(with: .opacity))
                }
            }
            if let h = data {
                if Verdict.pill(h.verdict) == nil {
                    Text("Noch zu wenig Daten (ab 3 Wochen).").font(Theme.F.text(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Theme.C.ink2).padding(.top, 8)
                } else {
                    let model = Model(h, offer: offer)
                    chart(model).padding(.top, 14)
                    legend(model).padding(.top, 8)
                    if more { facts(h).padding(.top, 8) }
                    HStack(alignment: .top, spacing: 18) {
                        if let m = h.medianCents { StatNumber(label: "Median\n12 Wo.", value: euro(m), size: 30, mute: true).frame(maxWidth: .infinity) }
                        if let m = h.minCents { StatNumber(label: "Tiefst-\npreis", value: euro(m), size: 30).frame(maxWidth: .infinity) }
                    }
                    .padding(.top, 28)
                }
            } else if failed {
                HStack {
                    Text("Preisverlauf gerade nicht verfügbar.").font(Theme.F.text(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Theme.C.ink2)
                    Spacer()
                    Button("Erneut versuchen") { Task { await load() } }
                        .font(Theme.F.text(13, .extrabold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink).frame(minHeight: 44)
                }
                .padding(.top, 8)
            } else {
                Skeleton8(height: 192).padding(.top, 14)
            }
        }
        .animation(Theme.spring, value: data)
        .task(id: offer.id) { await load() }
    }

    private func load() async {
        failed = false
        do { data = try await store.offerHistory(offer.id) } catch { failed = true }
    }

    /// Daten für die Zeichnung (Mockup-Raster 342 × 192, Wochen ab x 30, Stufe 26).
    struct Model {
        let weeks: [String]
        let chains: [String]  // Laden des Angebots zuerst
        let price: [String: [String: Int]]  // Kette → Woche → Cent
        let offerWeeks: [String: Set<String>]
        let lo: Double, hi: Double
        let normal: Int?
        let current: Int?  // Index der laufenden Woche

        static let colors = [Theme.C.ink, Theme.C.blue3, Theme.C.ink3]

        init(_ h: OfferHistoryDTO, offer: OfferDTO) {
            weeks = Array(Set(h.points.map(\.week)).sorted().suffix(12))
            let present = Set(h.points.map(\.chain))
            chains = Array(([offer.chain] + Labels.chains.map(\.key)).filter { present.contains($0) }.reduce(into: [String]()) { r, c in
                if !r.contains(c) { r.append(c) }
            }.prefix(Self.colors.count))
            var price: [String: [String: Int]] = [:], offers: [String: Set<String>] = [:]
            for p in h.points {
                price[p.chain, default: [:]][p.week] = p.priceCents
                if p.isOffer { offers[p.chain, default: []].insert(p.week) }
            }
            self.price = price
            offerWeeks = offers
            // Normalpreis: Streichpreis aus dem Prospekt, sonst Median der Wochen ohne Angebot, sonst Median
            let regular = h.points.filter { p in !p.isOffer }.map(\.priceCents).sorted()
            normal = offer.regularPriceCents ?? (regular.isEmpty ? h.medianCents : regular[regular.count / 2])
            let all = h.points.map { Double($0.priceCents) / 100 } + [normal.map { Double($0) / 100 }].compactMap { $0 }
            lo = max(0, ((all.min() ?? 0) + 0.05).rounded(.down))
            hi = max(((all.max() ?? 1) - 0.05).rounded(.up), lo + 1)
            let cal = Calendar(identifier: .iso8601)
            let now = String(format: "%d-W%02d", cal.component(.yearForWeekOfYear, from: .now), cal.component(.weekOfYear, from: .now))
            current = weeks.firstIndex(of: now)
        }

        func y(_ cents: Int) -> CGFloat { 145 - CGFloat((Double(cents) / 100 - lo) / (hi - lo)) * 100 }
    }

    private func chart(_ m: Model) -> some View {
        let n = max(m.weeks.count, 1)
        let w = (342 - 30) / CGFloat(n)
        return Canvas { ctx, size in
            let sx = size.width / 342
            func x(_ v: CGFloat) -> CGFloat { v * sx }
            if let c = m.current {  // diese Woche im blauen Band
                ctx.fill(Path(roundedRect: CGRect(x: x(30 + w * CGFloat(c)), y: 10, width: w * sx, height: 160), cornerRadius: w * sx / 2),
                         with: .color(Theme.C.blue1))
            }
            for (v, yy) in [(m.hi, CGFloat(45)), (m.lo, CGFloat(145))] {
                ctx.stroke(Path { p in p.move(to: CGPoint(x: x(22), y: yy)); p.addLine(to: CGPoint(x: size.width, y: yy)) },
                           with: .color(Theme.C.line), lineWidth: 1)
                ctx.draw(Text("\(Int(v)) €").font(Theme.F.text(10, .bold, relativeTo: .caption2)).foregroundStyle(Theme.C.ink3),
                         at: CGPoint(x: 0, y: yy), anchor: .leading)
            }
            if let normal = m.normal {
                let ny = m.y(normal)
                ctx.stroke(Path { p in p.move(to: CGPoint(x: x(30), y: ny)); p.addLine(to: CGPoint(x: size.width, y: ny)) },
                           with: .color(Theme.C.ink2), style: StrokeStyle(lineWidth: 1.4, dash: [4, 4]))
            }
            for (ci, chain) in m.chains.enumerated() {
                let color = Model.colors[ci]
                var path = Path(), last: CGFloat?
                for (i, week) in m.weeks.enumerated() {
                    guard let cents = m.price[chain]?[week] else { last = nil; continue }
                    let x0 = x(30 + w * CGFloat(i)), yy = m.y(cents)
                    if last == nil { path.move(to: CGPoint(x: x0, y: yy)) } else { path.addLine(to: CGPoint(x: x0, y: yy)) }
                    path.addLine(to: CGPoint(x: x0 + w * sx, y: yy))
                    last = yy
                }
                ctx.stroke(path, with: .color(color), lineWidth: 2.2)
                for (i, week) in m.weeks.enumerated() where m.offerWeeks[chain]?.contains(week) == true {
                    guard let cents = m.price[chain]?[week] else { continue }
                    let c = CGPoint(x: x(30 + w * (CGFloat(i) + 0.5)), y: m.y(cents))
                    let big = ci == 0 && i == m.current
                    let r: CGFloat = big ? 7 : 4
                    let dot = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                    ctx.fill(dot, with: .color(color))
                    if big { ctx.stroke(dot, with: .color(Theme.C.onInk), lineWidth: 2.5) }
                }
            }
            // Wochen: erste links, alle 4 Wochen mittig, letzte rechts in Tinte
            for i in Swift.stride(from: 0, to: n - 2, by: 4) {
                let label = Text(OfferHistoryDTO.kw(m.weeks[i])).font(Theme.F.text(10, .bold, relativeTo: .caption2)).foregroundStyle(Theme.C.ink2)
                ctx.draw(label, at: CGPoint(x: x(i == 0 ? 30 : 30 + w * (CGFloat(i) + 0.5)), y: 184), anchor: i == 0 ? .leading : .center)
            }
            if let lastWeek = m.weeks.last {
                ctx.draw(Text(OfferHistoryDTO.kw(lastWeek)).font(Theme.F.text(10, .bold, relativeTo: .caption2)).foregroundStyle(Theme.C.ink),
                         at: CGPoint(x: size.width, y: 184), anchor: .trailing)
            }
        }
        .frame(height: 192)
        .onGeometryChange(for: CGFloat.self) { g in g.size.width } action: { v in width = v }
        .overlay(alignment: .topTrailing) {
            if let normal = m.normal {  // Beschriftung über der gestrichelten Linie, rechts
                Text("Normalpreis \(euro(normal))").font(Theme.F.text(10.5, .bold, relativeTo: .caption2)).foregroundStyle(Theme.C.ink)
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(Theme.C.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: 1))
                    .padding(.trailing, 4)
                    .offset(y: max(10, m.y(normal) - 46))
            }
        }
        .overlay(alignment: .topLeading) {
            if let s = selected, s < m.weeks.count {
                let shown = m.chains.compactMap { c in m.price[c]?[m.weeks[s]].map { "\(Labels.chain(c)) \(euro($0))" } }
                Text(([OfferHistoryDTO.kw(m.weeks[s])] + shown).joined(separator: " · "))
                    .font(Theme.F.text(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.C.onInk)
                    .padding(.horizontal, 12).frame(height: 26)
                    .background(Theme.C.ink, in: Capsule())
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
            selected = min(max(Int((v.location.x * 342 / max(width, 1) - 30) / w), 0), n - 1)
        }.onEnded { _ in
            Task { try? await Task.sleep(for: .seconds(2)); withAnimation { selected = nil } }
        })
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityElement()
        .accessibilityLabel("Preisverlauf der letzten 12 Wochen")
        .accessibilityValue(m.chains.compactMap { c in m.weeks.last.flatMap { m.price[c]?[$0] }.map { "\(Labels.chain(c)) zuletzt \(euro($0))" } }
            .joined(separator: ", "))
    }

    private func legend(_ m: Model) -> some View {
        HStack(spacing: 16) {
            ForEach(Array(m.chains.enumerated()), id: \.element) { i, c in
                HStack(spacing: 6) {
                    Capsule().fill(Model.colors[i]).frame(width: 16, height: 2.5)
                    Text(Labels.chain(c))
                }
            }
            Spacer()
            Button(more ? "Weniger ‹" : "Mehr ›") { withAnimation(Theme.spring) { more.toggle() } }
                .font(Theme.F.text(12, .extrabold, relativeTo: .caption)).foregroundStyle(Theme.C.ink)
                .frame(minHeight: 44)
        }
        .font(Theme.F.text(12, .semibold, relativeTo: .caption))
        .foregroundStyle(Theme.C.ink2)
    }

    private func facts(_ h: OfferHistoryDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let low = h.lastLow {
                Text("Zuletzt so günstig: \(OfferHistoryDTO.kw(low.week)) bei \(Labels.chain(low.chain)) (\(euro(low.priceCents)))")
            }
            if let n = h.avgIntervalWeeks {
                let weeks = max(Int(n.rounded()), 1)
                Text(weeks == 1 ? "Im Schnitt jede Woche im Angebot" : "Im Schnitt alle \(weeks) Wochen im Angebot")
            }
        }
        .font(Theme.F.text(13, .semibold, relativeTo: .footnote))
        .foregroundStyle(Theme.C.ink2)
        .fixedSize(horizontal: false, vertical: true)
    }
}
