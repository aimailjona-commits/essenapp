import EssenappShareUI
import SwiftUI
import WidgetKit

/// Demo-Screens `widget` (S39) und `liveactivity` (S40): die Ansichten der Widget-Erweiterung auf einem nachgebauten
/// Home- bzw. Sperrbildschirm, damit die CI-Screenshots sie zeigen (die Erweiterung läuft im Simulator-Build nicht mit, E34/E83).
/// Positionen in Mockup-Koordinaten (Telefon 390 × 844, oben inkl. Statusleiste).
struct WidgetGallery: View {
    var lock = false  // S39 Sperrbildschirm statt Home

    private var entry: TodayEntry {
        var e = TodayEntry.demo
        if let url = Bundle.module.url(forResource: "bowl", withExtension: "jpg"), let data = try? Data(contentsOf: url) { e.images = [1: data] }
        return e
    }

    // Mockup-Maße (e.html S39)
    private let tile: CGFloat = 158
    private let wide: CGFloat = 342
    private let widgetRadius: CGFloat = 24
    private let app: CGFloat = 60
    private let appRadius: CGFloat = 15
    private let dock = (side: CGFloat(16), bottom: CGFloat(24), height: CGFloat(92), radius: CGFloat(36))
    private let glass = 0.4  // Dock rgba(255,255,255,.4)
    private let lockGlass = 0.45  // .e-lock

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.C.blue
            if lock { lockScreen } else { home }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
    }

    // MARK: Home

    private var home: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.edgeForm(.circle, Theme.C.blue1, width: 560, height: 560, left: -160, top: 420)
            widget(TodayWidgetView(entry: entry, family: .systemSmall), width: tile).at(24, 70)
            widget(TodayWidgetView(entry: TodayEntry(date: .now, state: .signedOut, data: nil), family: .systemSmall), width: tile)
                .at(208, 70)
            widget(TodayWidgetView(entry: entry, family: .systemMedium), width: wide).at(24, 252)
            HStack(alignment: .top) {
                appIcon(.fork, "Essenapp", fill: Theme.C.ink, tint: Theme.C.onInk)
                Spacer()
                appIcon(.cal, "Kalender")
                Spacer()
                appIcon(.photo, "Fotos")
                Spacer()
                appIcon(.cam, "Kamera")
            }
            .padding(.horizontal, 30).at(0, 440)
            VStack(spacing: 0) {
                Spacer()
                Dots8(count: 2, current: 0).padding(.bottom, 132 - dock.bottom - dock.height)
                HStack {
                    ForEach([Icon8.mic, .search, .bell, .gear], id: \.self) { i in
                        squircle(i, fill: Theme.C.card, tint: Theme.C.ink)
                        if i != .gear { Spacer() }
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: dock.height)
                .background(Theme.C.onInk.opacity(glass), in: RoundedRectangle(cornerRadius: dock.radius, style: .continuous))
                .padding(.horizontal, dock.side).padding(.bottom, dock.bottom)
            }
            .accessibilityHidden(true)
        }
    }

    private func widget(_ view: some View, width: CGFloat) -> some View {
        view.frame(width: width, height: tile)
            .background(Theme.C.card)
            .clipShape(RoundedRectangle(cornerRadius: widgetRadius, style: .continuous))
            .softShadow()
    }

    private func squircle(_ icon: Icon8, fill: Color, tint: Color) -> some View {
        Icon(icon, size: 28).foregroundStyle(tint).frame(width: app, height: app)
            .background(fill, in: RoundedRectangle(cornerRadius: appRadius, style: .continuous))
    }

    private func appIcon(_ icon: Icon8, _ name: String, fill: Color = Theme.C.card, tint: Color = Theme.C.ink) -> some View {
        VStack(spacing: 5) {
            squircle(icon, fill: fill, tint: tint)
            Text(name).font(Theme.F.text(11, .bold, relativeTo: .caption2)).foregroundStyle(Theme.C.ink)
        }
        .accessibilityHidden(true)
    }

    // MARK: Sperrbildschirm

    private var lockScreen: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.edgeForm(.circle, Theme.C.blue1, width: 630, height: 630, left: -120, top: 500)
            VStack(spacing: 0) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.de)))
                    .font(Theme.F.text(17, .bold, relativeTo: .headline))
                TodayWidgetView(entry: entry, family: .accessoryInline)
                    .font(Theme.F.text(15, .bold, relativeTo: .subheadline)).padding(.top, 4)
                Text(Date.now.formatted(.dateTime.hour().minute().locale(.de)))
                    .font(Theme.F.num(112)).tracking(Theme.F.numTracking(112)).padding(.top, 6)
                TodayWidgetView(entry: entry, family: .accessoryRectangular)
                    .padding(.vertical, 10).padding(.horizontal, 14).frame(width: 204)
                    .background(Theme.C.onInk.opacity(lockGlass), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.top, 20)
            }
            .foregroundStyle(Theme.C.ink)
            .frame(maxWidth: .infinity)
            .at(0, 88)
            LockButtons(glass: Theme.C.onInk.opacity(lockGlass))
        }
    }
}

/// S40 Live-Aktivität (d.html): Sperrbildschirm auf Pastellblau, Aktivität als Karte, oben die Dynamic Island kompakt.
struct LiveActivityGallery: View {
    private let a = ShopAttributes.demo, s = ShopAttributes.demoState

    // Mockup-Maße (d.html S40)
    private let island = (top: CGFloat(11), width: CGFloat(176), height: CGFloat(35))
    private let cardTop: CGFloat = 500
    private let cardRadius: CGFloat = 28
    private let dim = 0.18  // rgba(21,21,21,.18)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.C.blue1
            Color.clear.edgeForm(.circle, Theme.C.blue, width: 660, height: 660, left: -170, top: 420)
            HStack {
                ShopIsland(.compactLeading, attributes: a, state: s)
                Spacer()
                ShopIsland(.compactTrailing, attributes: a, state: s)
            }
            .padding(.leading, 7).padding(.trailing, 12)
            .frame(width: island.width, height: island.height)
            .background(.black, in: Capsule())
            .frame(maxWidth: .infinity)
            .at(0, island.top)
            VStack(spacing: 0) {
                Icon(.lock, size: 20)
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.de)))
                    .font(Theme.F.text(18, .bold, relativeTo: .headline)).padding(.top, 8)
                Text(Date.now.formatted(.dateTime.hour().minute().locale(.de)))
                    .font(Theme.F.num(112)).tracking(Theme.F.numTracking(112)).padding(.top, 6)
            }
            .foregroundStyle(Theme.C.ink)
            .frame(maxWidth: .infinity)
            .at(0, 66)
            ShopLockView(attributes: a, state: s, stale: false)
                .background(Theme.C.card, in: RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
                .floatShadow()
                .padding(.horizontal, 14)
                .at(0, cardTop)
            LockButtons(glass: Theme.C.ink.opacity(dim))
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
    }
}

/// Taschenlampe und Kamera unten auf dem Sperrbildschirm (nur Kulisse).
private struct LockButtons: View {
    let glass: Color

    var body: some View {
        VStack {
            Spacer()
            HStack {
                circle(Image(systemName: "flashlight.off.fill"))
                Spacer()
                circle(Icon(.cam, size: 22))
            }
            .padding(.horizontal, 46).padding(.bottom, 52)
        }
        .foregroundStyle(Theme.C.ink)
        .accessibilityHidden(true)
    }

    private func circle(_ icon: some View) -> some View {
        icon.frame(width: 52, height: 52).background(glass, in: Circle())
    }
}

private extension View {
    /// Absolut wie im Mockup (`left`/`top` ab Telefon-Oberkante).
    func at(_ x: CGFloat, _ y: CGFloat) -> some View { padding(.leading, x).padding(.top, y) }
}
