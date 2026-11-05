import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// Live-Aktivität beim Einkaufen (Feature 37). Attribute, Abhak-Intent und Ansichten liegen hier: die App startet und
// aktualisiert die Aktivität, die Erweiterung `EssenappWidget` zeigt sie, beide kennen den Intent-Typ (E83).

public struct ShopAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public struct Item: Codable, Hashable, Sendable {
            public var id: Int
            public var name: String
            public var amount: String  // „400 g“, leer ohne Menge

            public init(id: Int, name: String, amount: String) { self.id = id; self.name = name; self.amount = amount }
        }
        public var done: Int
        public var total: Int
        public var next: [Item]  // die nächsten 3 offenen Artikel

        public init(done: Int, total: Int, next: [Item]) { self.done = done; self.total = total; self.next = next }
    }

    public var chain: String  // "" = „Überall“
    public var name: String
    public var short: String  // Kürzel wie `StoreLogo` ohne Bild (Live-Aktivitäten laden keine Bilder aus dem Netz)
    public var tint: UInt32  // `Theme.storeColor`, keine Markenfarbe (E18)
    public var started: Date

    public init(chain: String, name: String, short: String, tint: UInt32, started: Date) {
        self.chain = chain; self.name = name; self.short = short; self.tint = tint; self.started = started
    }

    public static let demo = ShopAttributes(chain: "rewe", name: "Rewe", short: "R", tint: 0xF2CFC8, started: .now)
    public static let demoState = ContentState(done: 5, total: 12, next: [.init(id: 1, name: "Basmatireis", amount: "1 kg"),
                                                                         .init(id: 3, name: "Kaffee", amount: "500 g"),
                                                                         .init(id: 4, name: "Olivenöl", amount: "1 Flasche")])
}

/// Abhaken aus der Live-Aktivität. `LiveActivityIntent` → läuft im App-Prozess; die App setzt `handler` beim Start
/// (API-Client + Offline-Warteschlange), danach aktualisiert sie die Aktivität. Parameter als Text, weil der
/// Index-Generator nur Text-Parameter kennt (`ios/tools/appintents_index.py`).
public struct CheckItemIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Artikel abhaken"
    public static let description = IntentDescription("Hakt einen Artikel der Einkaufsliste ab.")
    public static let isDiscoverable = false

    @Parameter(title: "Artikel", description: "ID des Listen-Artikels")
    public var item: String?

    @MainActor public static var handler: (@MainActor @Sendable (Int) async -> Void)?

    public init() {}

    public init(item: Int) { self.item = String(item) }

    public func perform() async throws -> some IntentResult {
        if let id = item.flatMap(Int.init), let run = await Self.handler { await run(id) }
        return .result()
    }
}

/// Kürzel im Laden-Kreis (`.circle` in Pastell, Tinte), wie `StoreCircle` ohne Logo.
public struct ShopBadge: View {
    let attributes: ShopAttributes
    var size: CGFloat = 36

    public init(attributes: ShopAttributes, size: CGFloat = 36) {
        self.attributes = attributes
        self.size = size
    }

    public var body: some View {
        Group {
            if attributes.chain.isEmpty {
                Image(systemName: "basket").font(.system(size: size * 0.42, weight: .semibold))
            } else {
                Text(attributes.short).font(ST.text(size * 0.42, .bold))
            }
        }
        .foregroundStyle(ST.ink)
        .frame(width: size, height: size)
        .background(attributes.chain.isEmpty ? ST.blue1 : Color(hex: attributes.tint), in: Circle())
        .accessibilityLabel(attributes.name)
    }
}

/// Sperrbildschirm / Mitteilungszentrale (d.html S40): Laden, „5 von 12“, Balken, die nächsten 3 zum Abhaken.
public struct ShopLockView: View {
    let attributes: ShopAttributes
    let state: ShopAttributes.ContentState
    let stale: Bool

    public init(attributes: ShopAttributes, state: ShopAttributes.ContentState, stale: Bool) {
        self.attributes = attributes
        self.state = state
        self.stale = stale
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ShopBadge(attributes: attributes)
                Text(attributes.name).font(ST.text(17, .bold)).frame(maxWidth: .infinity, alignment: .leading)
                Text("\(state.done) von \(state.total)").font(ST.text(17, .bold)).monospacedDigit().contentTransition(.numericText())
            }
            .foregroundStyle(ST.ink)
            Capsule().fill(ST.line).frame(height: 8)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule().fill(ST.blue3).frame(width: g.size.width * Double(state.done) / Double(max(state.total, 1)))
                    }
                }
                .clipShape(Capsule())
                .padding(.top, 12)
                .accessibilityHidden(true)
            if stale {
                Text("Einkauf vorbei? In der App beenden.").font(ST.text(13)).foregroundStyle(ST.ink2).padding(.top, 6)
            }
            VStack(spacing: 0) {
                ForEach(state.next, id: \.id) { item in ShopItemRow(item: item, dark: false) }
            }
            .padding(.top, 6)
        }
        .padding(.top, 16).padding(.horizontal, 18).padding(.bottom, 10)
        .activityBackgroundTint(ST.card)
        .activitySystemActionForegroundColor(ST.ink)
        .widgetURL(URL(string: "essenapp://list/\(attributes.chain)"))
    }
}

/// Artikel mit Abhak-Knopf (App Intent): Kreis 22 in Blau, Name 15, Menge 13.
struct ShopItemRow: View {
    let item: ShopAttributes.ContentState.Item
    let dark: Bool

    var body: some View {
        Button(intent: CheckItemIntent(item: item.id)) {
            HStack(spacing: 12) {
                Circle().strokeBorder(ST.blue3, lineWidth: 2).frame(width: 22, height: 22)
                Text(item.name).font(ST.text(15)).foregroundStyle(dark ? ST.onInk : ST.ink).lineLimit(1)
                Spacer(minLength: 4)
                Text(item.amount).font(ST.text(13)).foregroundStyle(dark ? ST.onInk.opacity(0.6) : ST.ink2)
            }
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name) abhaken")
    }
}

/// Teile der Dynamic Island (immer dunkler Grund): kompakt Kürzel links, „5/12“ in Blau rechts.
public struct ShopIsland: View {
    public enum Part: Sendable { case leading, trailing, bottom, compactLeading, compactTrailing, minimal }

    let part: Part
    let attributes: ShopAttributes
    let state: ShopAttributes.ContentState

    public init(_ part: Part, attributes: ShopAttributes, state: ShopAttributes.ContentState) {
        self.part = part
        self.attributes = attributes
        self.state = state
    }

    public var body: some View {
        switch part {
        case .leading:
            HStack(spacing: 8) {
                ShopBadge(attributes: attributes, size: 30)
                Text(attributes.name).font(ST.text(17, .bold)).foregroundStyle(ST.onInk).lineLimit(1)
            }
        case .trailing:
            Text("\(state.done) von \(state.total)").font(ST.text(17, .bold)).monospacedDigit().foregroundStyle(ST.blue)
        case .bottom:
            VStack(spacing: 0) {
                ForEach(state.next, id: \.id) { item in ShopItemRow(item: item, dark: true) }
            }
        case .compactLeading:
            ShopBadge(attributes: attributes, size: 22)
        case .compactTrailing:
            Text("\(state.done)/\(state.total)").font(ST.text(14, .bold)).monospacedDigit().foregroundStyle(ST.blue)
        case .minimal:
            Text("\(state.total - state.done)").font(ST.text(14, .bold)).monospacedDigit().foregroundStyle(ST.blue)
                .accessibilityLabel("\(state.total - state.done) offen")
        }
    }
}
