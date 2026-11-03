import ActivityKit
import AppIntents
import EssenappShareUI
import SwiftUI
import WidgetKit

/// Widget-Erweiterung (Features 65 + 37). Kein geteilter Speicher mit der App (E48): das Widget koppelt sich selbst
/// über Server-Adresse + Kopplungscode aus „Widget bearbeiten“; die Live-Aktivität bekommt ihre Daten von der App.
@main
struct EssenappWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        ShopLiveActivity()
    }
}

/// „Widget bearbeiten“: beide Werte stehen in der App unter Einstellungen › Widget einrichten.
struct TodayIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Kochpilot koppeln"
    static let description = IntentDescription("Server-Adresse und Kopplungscode aus Kochpilot › Einstellungen › Widget einrichten.")

    @Parameter(title: "Server-Adresse", description: "z. B. http://192.168.0.10:8000")
    var server: String?

    @Parameter(title: "Kopplungscode", description: "6 Ziffern, 10 Minuten gültig")
    var code: String?
}

struct TodayProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { .demo }

    func snapshot(for configuration: TodayIntent, in context: Context) async -> TodayEntry {
        context.isPreview ? .demo : await TodayLoader.shared.load(server: configuration.server, code: configuration.code)
    }

    /// Jetzt + jeder Mahlzeitwechsel (14 Uhr, 21 Uhr, Mitternacht) mit demselben Stand; neu laden nach ~30 min.
    func timeline(for configuration: TodayIntent, in context: Context) async -> Timeline<TodayEntry> {
        let entry = await TodayLoader.shared.load(server: configuration.server, code: configuration.code)
        let later = TodayData.switches(after: entry.date).map { t in
            var e = entry
            e.date = t
            return e
        }
        return Timeline(entries: [entry] + later, policy: .after(.now.addingTimeInterval(30 * 60)))
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "today", intent: TodayIntent.self, provider: TodayProvider()) { entry in
            TodayContent(entry: entry)
        }
        .configurationDisplayName("Heute")
        .description("Heutiges Gericht, nächste Mahlzeit und offene Artikel.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct TodayContent: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View { TodayWidgetView(entry: entry, family: family) }
}

struct ShopLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShopAttributes.self) { context in
            ShopLockView(attributes: context.attributes, state: context.state, stale: context.isStale)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { ShopIsland(.leading, attributes: context.attributes, state: context.state) }
                DynamicIslandExpandedRegion(.trailing) { ShopIsland(.trailing, attributes: context.attributes, state: context.state) }
                DynamicIslandExpandedRegion(.bottom) { ShopIsland(.bottom, attributes: context.attributes, state: context.state) }
            } compactLeading: {
                ShopIsland(.compactLeading, attributes: context.attributes, state: context.state)
            } compactTrailing: {
                ShopIsland(.compactTrailing, attributes: context.attributes, state: context.state)
            } minimal: {
                ShopIsland(.minimal, attributes: context.attributes, state: context.state)
            }
            .widgetURL(URL(string: "essenapp://list/\(context.attributes.chain)"))
        }
    }
}
