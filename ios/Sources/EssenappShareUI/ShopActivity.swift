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

    public static let demo = ShopAttributes(chain: "rewe", name: "Rewe", short: "R", tint: 0xFF6B4A, started: .now)
    public static let demoState = ContentState(done: 5, total: 12, next: [.init(id: 1, name: "Hähnchenbrustfilet", amount: "400 g"),
                                                                         .init(id: 3, name: "Rispentomaten", amount: "700 g"),
                                                                         .init(id: 4, name: "Feta", amount: "200 g")])
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

/// Kürzel auf der Laden-Farbe (wie `StoreLogo` ohne Logo).
public struct ShopBadge: View {
    let attributes: ShopAttributes
    var size: CGFloat = 36

    public init(attributes: ShopAttributes, size: CGFloat = 36) {
        self.attributes = attributes
        self.size = size
    }

    public var body: some View {
        Text(attributes.chain.isEmpty ? "🧺" : attributes.short)
            .font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(attributes.chain.isEmpty ? ST.surface : Color(hex: attributes.tint),
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityLabel(attributes.name)
    }
}

/// Sperrbildschirm / Mitteilungszentrale.
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ShopBadge(attributes: attributes)
                Text(attributes.name).font(ST.headline).foregroundStyle(ST.text1)
                Spacer()
                Text("\(state.done) von \(state.total)").font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                    .foregroundStyle(ST.text1).contentTransition(.numericText())
            }
            ProgressView(value: Double(state.done), total: Double(max(state.total, 1))).tint(ST.accent)
            if stale {
                Text("Einkauf vorbei? In der App beenden.").font(ST.caption).foregroundStyle(ST.text2)
            }
            ForEach(state.next, id: \.id) { item in ShopItemRow(item: item, dark: false) }
        }
        .padding(14)
        .activityBackgroundTint(ST.card)
        .activitySystemActionForegroundColor(ST.text1)
        .widgetURL(URL(string: "essenapp://list/\(attributes.chain)"))
    }
}

/// Artikel mit Abhak-Knopf (App Intent).
struct ShopItemRow: View {
    let item: ShopAttributes.ContentState.Item
    let dark: Bool

    var body: some View {
        Button(intent: CheckItemIntent(item: item.id)) {
            HStack(spacing: 8) {
                Image(systemName: "circle").font(.system(size: 17, weight: .semibold)).foregroundStyle(ST.accent)
                Text(item.name).font(ST.callout).foregroundStyle(dark ? .white : ST.text1).lineLimit(1)
                Spacer(minLength: 4)
                Text(item.amount).font(ST.caption).foregroundStyle(dark ? .white.opacity(0.6) : ST.text2)
            }
            .frame(minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name) abhaken")
    }
}

/// Teile der Dynamic Island (immer dunkler Grund).
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
                Text(attributes.name).font(ST.headline).foregroundStyle(.white).lineLimit(1)
            }
        case .trailing:
            Text("\(state.done) von \(state.total)").font(.system(.headline, design: .rounded, weight: .bold)).monospacedDigit()
                .foregroundStyle(ST.accent)
        case .bottom:
            VStack(spacing: 2) {
                ForEach(state.next, id: \.id) { item in ShopItemRow(item: item, dark: true) }
            }
        case .compactLeading:
            ShopBadge(attributes: attributes, size: 22)
        case .compactTrailing:
            Text("\(state.done)/\(state.total)").font(.system(.footnote, design: .rounded, weight: .bold)).monospacedDigit()
                .foregroundStyle(ST.accent)
        case .minimal:
            Text("\(state.total - state.done)").font(.system(.footnote, design: .rounded, weight: .bold)).monospacedDigit()
                .foregroundStyle(ST.accent)
                .accessibilityLabel("\(state.total - state.done) offen")
        }
    }
}
