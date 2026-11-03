import EssenappShareUI
import SwiftUI
import WidgetKit

/// Demo-Screens `widget` (S39) und `liveactivity` (S40): die Ansichten der Widget-Erweiterung in Rahmen wie auf dem
/// iPhone, damit die CI-Screenshots sie zeigen (die Erweiterung selbst läuft im Simulator-Build nicht mit, E34/E83).
struct WidgetGallery: View {
    private var entry: TodayEntry {
        var e = TodayEntry.demo
        if let url = Bundle.module.url(forResource: "bowl", withExtension: "jpg"), let data = try? Data(contentsOf: url) { e.images = [1: data] }
        return e
    }

    var body: some View {
        var stale = entry
        stale.stale = true
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DisplayHeader(line1: "Widget", line2: "Heute")
                HStack(spacing: 16) {
                    tile(TodayWidgetView(entry: entry, family: .systemSmall), width: 158)
                    tile(TodayWidgetView(entry: TodayEntry(date: .now, state: .unpaired(nil), data: nil), family: .systemSmall), width: 158)
                }
                tile(TodayWidgetView(entry: stale, family: .systemMedium), width: 338)
                Text("Sperrbildschirm").font(Theme.F.headline).padding(.top, 4)
                VStack(alignment: .leading, spacing: 14) {
                    TodayWidgetView(entry: entry, family: .accessoryInline).font(.system(.subheadline, weight: .semibold))
                    TodayWidgetView(entry: entry, family: .accessoryRectangular).frame(width: 170, height: 72)
                }
                .foregroundStyle(.white)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.C.heroDark, in: RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 40)
        }
    }

    private func tile(_ view: some View, width: CGFloat) -> some View {
        view.frame(width: width, height: 158)
            .background(Theme.C.card)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .floatShadow()
    }
}

struct LiveActivityGallery: View {
    private let a = ShopAttributes.demo, s = ShopAttributes.demoState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DisplayHeader(line1: "Live-Aktivität", line2: "Einkauf")
                ShopLockView(attributes: a, state: s, stale: false)
                    .background(Theme.C.card)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .floatShadow()
                Text("Dynamic Island").font(Theme.F.headline).padding(.top, 4)
                HStack {  // kompakt: links Kürzel, rechts Stand
                    ShopIsland(.compactLeading, attributes: a, state: s)
                    Spacer()
                    ShopIsland(.compactTrailing, attributes: a, state: s)
                }
                .padding(.horizontal, 14).frame(width: 250, height: 37).background(.black, in: Capsule())
                .frame(maxWidth: .infinity)
                ShopIsland(.minimal, attributes: a, state: s).frame(width: 37, height: 37).background(.black, in: Circle())
                    .frame(maxWidth: .infinity)
                VStack(spacing: 8) {  // ausgeklappt
                    HStack {
                        ShopIsland(.leading, attributes: a, state: s)
                        Spacer()
                        ShopIsland(.trailing, attributes: a, state: s)
                    }
                    ShopIsland(.bottom, attributes: a, state: s)
                }
                .padding(18)
                .background(.black, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 40)
        }
    }
}
