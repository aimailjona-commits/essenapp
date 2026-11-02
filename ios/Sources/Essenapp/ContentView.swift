import SwiftUI

struct ContentView: View {
    @State private var store = AppStore(api: API())

    init() {
        // Produktbilder flüssig: großer Bild-Cache statt ständigem Neuladen beim Scrollen
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if store.isOnboarded {
                    MainView().transition(.opacity)
                } else {
                    OnboardingView().transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: store.isOnboarded)

            if let toast = store.toast {
                Toast(text: toast, actionTitle: store.toastAction?.title) {
                    let run = store.toastAction?.run
                    withAnimation(Theme.spring) { store.toast = nil; store.toastAction = nil }
                    run?()
                }
                .padding(.horizontal, 16).padding(.top, 8).zIndex(1)
            }
        }
        .environment(store)
        .environment(store.api)
        .preferredColorScheme(.light)  // nur heller Modus in v1 (E15); sonst wird Systemtext im Dark Mode weiß
        .foregroundStyle(Theme.C.text1)
        .tint(Theme.C.accentDeep)
    }
}

struct MainView: View {
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var delegate: AppDelegate
    @State private var deepOffer: OfferDTO?
    @State private var tab = MainView.demoTab
    @State private var resetToken = 0  // erneutes Tippen auf den aktiven Tab → zurück zum Anfang
    @State private var quickOpen = Demo.screen == "quick"
    @State private var showGenerator = ["generator", "generating"].contains(Demo.screen ?? "")

    private static var demoTab: AppTab {
        switch Demo.screen {
        case "offers", "offer", "stores": .angebote
        case "plan", "recipe", "cooking", "sharecard": .rezepte
        case "shopping", "list", "pantry": .einkauf
        default: .start
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .start: StartView(showGenerator: $showGenerator)
        case .angebote: OffersView()
        case .einkauf: ShoppingView()
        case .rezepte: RecipesTab(showGenerator: $showGenerator)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.C.bg.ignoresSafeArea()

            NavigationStack {
                Group {
                    switch (Demo.screen, tab) {
                    case ("recipe", _), ("cooking", _), ("sharecard", _): RecipeDetailView(meal: Demo.plan.entries[2])
                    case ("offer", _): OfferDetailView(offer: Demo.offers[0])
                    case ("stores", _): StoreMapView()
                    case ("list", _): ShoppingListView(chain: "rewe")
                    case ("settings", _): SettingsView()
                    case ("profile", _): ProfileView()
                    case ("notifications", _): NotificationsView()
                    default: tabContent.id(tab).transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.C.bg)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(item: $deepOffer) { OfferDetailView(offer: $0) }
            }
            .id("\(tab)-\(resetToken)")  // Tab-Wechsel schließt offene Detailseiten
            .animation(.easeInOut(duration: 0.2), value: tab)

            if quickOpen {
                Color.black.opacity(0.25).ignoresSafeArea()
                    .onTapGesture { withAnimation(Theme.spring) { quickOpen = false } }
                    .transition(.opacity)
                QuickActions { action in
                    withAnimation(Theme.spring) { quickOpen = false }
                    switch action {
                    case .plan: showGenerator = true
                    case .list: tab = .einkauf
                    case .offers: tab = .angebote
                    case .recipe: tab = .rezepte
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
                .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
            }

            TabBar(selected: $tab, quickOpen: $quickOpen) { resetToken += 1 }
        }
        .sheet(isPresented: $showGenerator) { PlanGeneratorSheet().presentationDetents([.large]) }
        .task { await store.loadAll() }
        .modifier(PushAsk(active: store.askPush))
        .onOpenURL { url in Task { await open(url) } }
        .onReceive(delegate.$pendingURL) { url in  // Mitteilung angetippt
            guard let url else { return }
            delegate.pendingURL = nil
            Task { await open(url) }
        }
    }

    /// Router für essenapp://start, essenapp://generator, essenapp://offer/<id>.
    private func open(_ url: URL) async {
        guard url.scheme == "essenapp" else { return }
        withAnimation(Theme.spring) { quickOpen = false }
        switch url.host() {
        case "start":
            withAnimation(Theme.spring) { tab = .start }
        case "generator":
            showGenerator = true
        case "offer":
            guard let id = Int(url.lastPathComponent) else { return }
            if !store.offers.contains(where: { o in o.id == id }) { await store.loadAll() }
            guard let offer = store.offers.first(where: { o in o.id == id }) else { store.flash("Angebot nicht mehr verfügbar"); return }
            withAnimation(Theme.spring) { tab = .angebote }
            try? await Task.sleep(for: .milliseconds(350))  // Tab-Wechsel baut den NavigationStack neu
            deepOffer = offer
        default:
            break
        }
    }
}

/// Schnell-Aktionen hinter dem Mittel-Button (E14).
struct QuickActions: View {
    enum Action { case plan, offers, list, recipe }
    let select: (Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Was möchtest du tun?").font(Theme.F.caption).foregroundStyle(Theme.C.text2).padding(.horizontal, 8)
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    tile(.plan, "✨", "Wochenplan erstellen", "KI plant mit den Angeboten", color: Theme.C.accent, main: true)
                    tile(.offers, "🏷️", "Angebote stöbern", "Was ist diese Woche günstig?", color: Theme.C.deal)
                }
                GridRow {
                    tile(.list, "🛒", "Einkaufsliste", "Artikel abhaken & ergänzen", color: Theme.C.kcal)
                    tile(.recipe, "📖", "Wochenplan ansehen", "Gerichte würfeln & fixieren", color: Color(hex: 0x8E7CFF))
                }
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.R.sheet, style: .continuous))
        .floatShadow()
    }

    private func tile(_ action: Action, _ emoji: String, _ title: String, _ subtitle: String, color: Color, main: Bool = false) -> some View {
        Button { select(action) } label: {
            VStack(alignment: .leading, spacing: 18) {
                Text(emoji).font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .background(main ? Color.white.opacity(0.18) : color.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.F.callout)
                    Text(subtitle).font(Theme.F.micro).foregroundStyle(main ? .white.opacity(0.75) : Theme.C.text2)
                }
            }
            .multilineTextAlignment(.leading)
            .foregroundStyle(main ? .white : Theme.C.text1)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .background(main ? AnyShapeStyle(LinearGradient(colors: [Theme.C.accent, Theme.C.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                             : AnyShapeStyle(Theme.C.surface),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}
