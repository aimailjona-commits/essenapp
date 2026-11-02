import Charts
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

    /// Urteil-Badge (Text, Farbe); nil = zu wenig Daten.
    var badge: (text: String, color: Color)? {
        switch verdict {
        case "bestpreis": ("🔥 Bestpreis", Theme.C.deal)
        case "gut": ("👍 Gutes Angebot", Theme.C.success)
        case "normal": ("😐 Normal", Theme.C.text2)
        case "kein_echtes": ("⚠️ Kein echtes Angebot", Theme.C.warning)
        default: nil
        }
    }

    /// "2026-W45" → "KW 45"
    static func kw(_ week: String) -> String { "KW \(Int(week.split(separator: "W").last ?? "") ?? 0)" }
}

extension AppStore {
    func offerHistory(_ id: Int) async throws -> OfferHistoryDTO {
        if demo { return Demo.history(for: id) }
        return try await api.request("GET", "/offers/\(id)/history")
    }
}

/// Abschnitt „Preisverlauf“: Urteil, Diagramm (Farbe = Laden, Angebotswochen als Punkte, Normalpreis gestrichelt,
/// aktuelle Woche hervorgehoben, Antippen zeigt Werte), „Zuletzt so günstig …“, „Im Schnitt alle N Wochen …“.
struct PriceHistoryCard: View {
    @Environment(AppStore.self) private var store
    let offer: OfferDTO
    @State private var data: OfferHistoryDTO?
    @State private var failed = false
    @State private var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Preisverlauf").font(Theme.F.headline)
                Spacer()
                if let badge = data?.badge {
                    Text(badge.text).font(Theme.F.micro).foregroundStyle(badge.color)
                        .padding(.horizontal, 10).frame(height: 26).background(badge.color.opacity(0.14), in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            if let h = data {
                if h.badge == nil {
                    Label("Noch zu wenig Daten (ab 3 Wochen)", systemImage: "chart.line.uptrend.xyaxis")
                        .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                } else {
                    chart(h)
                    facts(h)
                }
            } else if failed {
                HStack {
                    Text("Preisverlauf gerade nicht verfügbar.").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                    Spacer()
                    Button("Erneut versuchen") { Task { await load() } }.font(Theme.F.callout).frame(minHeight: 44)
                }
            } else {
                SkeletonCard(height: 200)
            }
        }
        .padding(16)
        .card()
        .animation(Theme.spring, value: data)
        .task(id: offer.id) { await load() }
    }

    private func load() async {
        failed = false
        do { data = try await store.offerHistory(offer.id) } catch { failed = true }
    }

    private func chart(_ h: OfferHistoryDTO) -> some View {
        let points = h.points.sorted { a, b in a.week < b.week }
        let chains = Labels.chains.map(\.key).filter { c in points.contains { p in p.chain == c } }
        let weeks = Set(points.map { p in OfferHistoryDTO.kw(p.week) })
        let cal = Calendar(identifier: .iso8601)
        let current = "KW \(cal.component(.weekOfYear, from: .now))"
        // Normalpreis: Streichpreis aus dem Prospekt, sonst Median der Wochen ohne Angebot, sonst Median
        let regular = points.filter { p in !p.isOffer }.map(\.priceCents).sorted()
        let normal = offer.regularPriceCents ?? (regular.isEmpty ? h.medianCents : regular[regular.count / 2])
        return Chart {
            if weeks.contains(current) {
                RectangleMark(x: .value("Woche", current)).foregroundStyle(Theme.C.accentSoft)
            }
            if let normal {
                RuleMark(y: .value("Normalpreis", Double(normal) / 100))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(Theme.C.text3)
                    .annotation(position: .top, alignment: .leading) {
                        Text("Normalpreis \(euro(normal))").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                    }
            }
            ForEach(points, id: \.self) { p in
                LineMark(x: .value("Woche", OfferHistoryDTO.kw(p.week)), y: .value("Preis", Double(p.priceCents) / 100))
                    .foregroundStyle(by: .value("Laden", Labels.chain(p.chain)))
                    .interpolationMethod(.stepCenter)
                if p.isOffer {
                    PointMark(x: .value("Woche", OfferHistoryDTO.kw(p.week)), y: .value("Preis", Double(p.priceCents) / 100))
                        .foregroundStyle(by: .value("Laden", Labels.chain(p.chain)))
                        .symbolSize(OfferHistoryDTO.kw(p.week) == current ? 140 : 50)
                }
            }
            if let selected {
                RuleMark(x: .value("Woche", selected)).foregroundStyle(Theme.C.text3)
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        let shown = points.filter { p in OfferHistoryDTO.kw(p.week) == selected }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected).font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                            ForEach(shown, id: \.self) { p in
                                Text("\(Labels.chain(p.chain)) \(euro(p.priceCents))\(p.isOffer ? " · Angebot" : "")")
                                    .font(.system(.caption, weight: .semibold)).monospacedDigit()
                            }
                        }
                        .padding(8)
                        .background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.chip, style: .continuous))
                    }
            }
        }
        .chartForegroundStyleScale(domain: chains.map(Labels.chain), range: chains.map(Theme.storeColor))
        .chartXSelection(value: $selected)
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(Theme.C.line)
                AxisValueLabel { if let d = v.as(Double.self) { Text(euro(Int((d * 100).rounded()))).font(Theme.F.micro) } }
            }
        }
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(Theme.F.micro) }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 220)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel("Preisverlauf der letzten 12 Wochen")
    }

    private func facts(_ h: OfferHistoryDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let m = h.medianCents { stat("Median 12 Wochen", euro(m)) }
                if let m = h.minCents { stat("Tiefstpreis", euro(m)) }
            }
            if let low = h.lastLow {
                Label("Zuletzt so günstig: \(OfferHistoryDTO.kw(low.week)) bei \(Labels.chain(low.chain)) (\(euro(low.priceCents)))",
                      systemImage: "clock.arrow.circlepath")
            }
            if let n = h.avgIntervalWeeks {
                let weeks = max(Int(n.rounded()), 1)
                Label(weeks == 1 ? "Im Schnitt jede Woche im Angebot" : "Im Schnitt alle \(weeks) Wochen im Angebot", systemImage: "repeat")
            }
        }
        .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.F.micro).foregroundStyle(Theme.C.text2)
            Text(value).font(.system(.subheadline, weight: .bold)).monospacedDigit().foregroundStyle(Theme.C.text1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.chip, style: .continuous))
    }
}
