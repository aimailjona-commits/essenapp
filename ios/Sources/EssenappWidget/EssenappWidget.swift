import ActivityKit
import EssenappShareUI
import SwiftUI
import WidgetKit

/// Widget-Erweiterung (Features 65 + 37). Das Widget nutzt die Anmeldung der App aus dem geteilten Schlüsselbund (E102);
/// die Live-Aktivität bekommt ihre Daten von der App.
@main
struct EssenappWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        ShopLiveActivity()
    }
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { .demo }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (TodayEntry) -> Void) {
        if context.isPreview { return completion(.demo) }
        Task { completion(await TodayLoader.shared.load()) }
    }

    /// Jetzt + jeder Mahlzeitwechsel (14 Uhr, 21 Uhr, Mitternacht) mit demselben Stand; neu laden nach ~30 min.
    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<TodayEntry>) -> Void) {
        Task {
            let entry = await TodayLoader.shared.load()
            let later = TodayData.switches(after: entry.date).map { t in
                var e = entry
                e.date = t
                return e
            }
            completion(Timeline(entries: [entry] + later, policy: .after(.now.addingTimeInterval(30 * 60))))
        }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "today", provider: TodayProvider()) { entry in
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
