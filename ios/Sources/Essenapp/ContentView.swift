import EssenappShareUI
import SwiftUI

struct ContentView: View {
    @State private var store = AppStore.shared
    @AppStorage("appearance") private var appearance = "system"  // System · Hell · Dunkel (68, ersetzt E15)

    init() {
        // Produktbilder flüssig: großer Bild-Cache statt ständigem Neuladen beim Scrollen
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
        #if DEBUG
        PendingRequest.selfTest()
        StoreReminder.selfTest()
        SavingSelfTest.run()
        Month.selfTest()
        TodayData.selfTest()
        LiveShop.selfTest()
        #endif
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
            // Banner schiebt den Inhalt nach unten (Safe-Area-Einschub statt Überlagerung), z. B. „Liste | Vorrat“
            .safeAreaInset(edge: .top, spacing: 0) {
                if !store.api.online && store.isOnboarded {
                    OfflineBanner().padding(.top, 4).padding(.bottom, 8).transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.35), value: store.isOnboarded)
            .animation(Theme.spring, value: store.api.online)

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
        .environment(\.locale, .de)  // 24-h-Uhrzeiten, Komma – auch wenn das iPhone auf Englisch steht
        .onChange(of: Demo.appearance ?? appearance, initial: true) { _, mode in Self.apply(mode) }
        .foregroundStyle(Theme.C.text1)
        .tint(Theme.C.accentDeep)
    }

    /// Erscheinungsbild für alle Fenster (auch Sheets, Menüs, Alerts). Über das Fenster statt `preferredColorScheme`,
    /// weil `preferredColorScheme(nil)` nicht zuverlässig zurück auf „System“ springt.
    static func apply(_ mode: String) {
        let style: UIUserInterfaceStyle = mode == "light" ? .light : mode == "dark" ? .dark : .unspecified
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.windows.forEach { w in w.overrideUserInterfaceStyle = style }
        }
    }
}

/// Glas-Banner oben, solange kein Netz bzw. Server nicht erreichbar ist (66).
struct OfflineBanner: View {
    var body: some View {
        let label = Label("Offline – Änderungen werden später übertragen", systemImage: "wifi.slash")
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(Theme.C.text1)
            .padding(.horizontal, 16).frame(minHeight: 40)
        Group {
            if #available(iOS 26.0, *) {
                label.glassEffect(.regular, in: Capsule())
            } else {
                label.background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: 0.5))
            }
        }
        .accessibilityAddTraits(.isStaticText)
    }
}

struct MainView: View {
    @Environment(AppStore.self) private var store
    @EnvironmentObject private var delegate: AppDelegate
    @State private var deepOffer: OfferDTO?
    @State private var deepList: String?  // Laden-Liste aus der Standort-Erinnerung (36)
    @State private var deepRecipe: Int?  // Rezept aus dem Lunchbox-Push (24)
    @State private var tab = MainView.demoTab
    @State private var resetToken = 0  // erneutes Tippen auf den aktiven Tab → zurück zum Anfang
    @State private var quickOpen = Demo.screen == "quick"
    @State private var showGenerator = ["generator", "generating", "singlestore"].contains(Demo.screen ?? "")
    @State private var showRecipeForm = false  // Schnell-Aktion „Rezept anlegen“ (S17)
    @State private var deepAchievements = false  // Push „Neuer Erfolg“ (54)
    @State private var sharedCode: String? = Demo.screen == "sharedrecipe" ? Demo.sharedRecipe.code : nil  // essenapp://import-recipe/<code> (56)

    private static var demoTab: AppTab {
        switch Demo.screen {
        case "offers", "offer", "stores", "watch", "scanner", "nextweek", "offerstock": .angebote
        case "plan", "recipe", "cooking", "sharecard", "recipes", "myrecipe", "recipeform", "imported", "importlink", "guests": .rezepte
        case "shopping", "list", "pantry", "fridgecam", "fridgereview", "cooknow", "offline", "voiceadd", "wallet", "bonus", "coupon": .einkauf
        default: .start
        }
    }

    /// Demo-Screens, die in der App als Sheet bzw. in der Erweiterung ohne Tab-Leiste erscheinen.
    private static let modalDemo = ["recipeform", "fridgecam", "fridgereview", "cooknow", "sharepair", "shareimport", "shareresult", "importlink",
                                    "nomood", "substitute", "leftovers", "couponadd", "widget", "liveactivity"]

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
                    case ("myrecipe", _): SavedRecipeView(recipeId: Demo.savedRecipe.id)
                    case ("recipeform", _): RecipeFormSheet(editing: Demo.savedRecipe, page: 1)
                    case ("imported", _): SavedRecipeView(recipeId: Demo.importedRecipe.id)
                    case ("instagram", _): InstagramShareView()
                    case ("widgetsetup", _): InstagramShareView(widget: true)
                    case ("widget", _): WidgetGallery()
                    case ("liveactivity", _): LiveActivityGallery()
                    case ("fridgecam", _): FridgeScanSheet()
                    case ("fridgereview", _): FridgeScanSheet(stage: .review)
                    case ("cooknow", _): FridgeScanSheet(stage: .cook)
                    case ("sharepair", _): ShareFlowView(input: nil, session: nil, demo: .pair) {}
                    case ("shareimport", _): ShareFlowView(input: nil, session: nil, demo: .importing) {}
                    case ("shareresult", _): ShareFlowView(input: nil, session: nil, demo: .result) {}
                    case ("importlink", _): ShareFlowView(input: nil, session: nil, demo: .link, onOpen: { _ in }) {}
                    case ("offer", _): OfferDetailView(offer: Demo.offers[0])
                    case ("offerstock", _): OfferDetailView(offer: Demo.offers[6])  // Vorratstipp + Bio/Nutri (31/49)
                    case ("stores", _): StoreMapView()
                    case ("list", _): ShoppingListView(chain: "rewe")
                    case ("settings", _): SettingsView()
                    case ("profile", _): ProfileView()
                    case ("notifications", _), ("storeask", _): NotificationsView()
                    case ("nomood", _): NoMoodSheet()
                    case ("substitute", _): SubstituteSheet(meal: Demo.plan.entries[2], index: 3)
                    case ("leftovers", _): RatingSheet(meal: Demo.plan.entries[2], demoRests: true)
                    case ("basics", _): WeeklyBasicsView()
                    case ("variety", _): PreferencesView()
                    case ("couponadd", _): CouponAddSheet()
                    case ("spending", _): SpendingView()
                    case ("achievements", _), ("unlock", _): AchievementsView()
                    case ("reviews", _): ReviewArchiveView()
                    case ("recipelink", _): RecipeLinkSheet(recipeId: Demo.savedRecipe.id, title: Demo.savedRecipe.title)
                    default: tabContent.id(tab).transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.C.bg)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(item: $deepOffer) { OfferDetailView(offer: $0) }
                .navigationDestination(item: $deepList) { chain in ShoppingListView(chain: chain) }
                .navigationDestination(item: $deepRecipe) { id in
                    if let meal = store.plan?.entries.first(where: { e in e.recipe.id == id }) {
                        RecipeDetailView(meal: meal)  // im Plan: Mengen des Slots
                    } else {
                        SavedRecipeView(recipeId: id)
                    }
                }
                .navigationDestination(isPresented: $deepAchievements) { AchievementsView() }
            }
            .id("\(tab)-\(resetToken)")  // Tab-Wechsel schließt offene Detailseiten
            .animation(.easeInOut(duration: 0.2), value: tab)

            if quickOpen {
                Theme.C.scrim.ignoresSafeArea()
                    .onTapGesture { withAnimation(Theme.spring) { quickOpen = false } }
                    .transition(.opacity)
                QuickActions { action in
                    withAnimation(Theme.spring) { quickOpen = false }
                    switch action {
                    case .plan: showGenerator = true
                    case .list: tab = .einkauf
                    case .barcode: store.barcode = true
                    case .recipe: showRecipeForm = true
                    case .scan: store.scanning = true
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
                .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
            }

            if !Self.modalDemo.contains(Demo.screen ?? "") {
                TabBar(selected: $tab, quickOpen: $quickOpen, badges: [.angebote: store.watchHits]) { resetToken += 1 }
            }

            if !store.newAchievements.isEmpty { UnlockOverlay().zIndex(2) }  // Vollbild-Moment (54)
        }
        .sheet(isPresented: Binding(get: { store.scanning }, set: { on in store.scanning = on })) {
            FridgeScanSheet().presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet)
        }
        .fullScreenCover(isPresented: Binding(get: { store.barcode }, set: { on in store.barcode = on })) { BarcodeScanView() }
        .sheet(isPresented: $showGenerator) { PlanGeneratorSheet().presentationDetents([.large]) }
        .sheet(isPresented: $showRecipeForm) { RecipeFormSheet().presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
        .fullScreenCover(isPresented: Binding(get: { store.checkoutCoupon != nil }, set: { on in if !on { store.checkoutCoupon = nil } })) {
            if let id = store.checkoutCoupon { CouponCheckoutView(id: id) }
        }
        .fullScreenCover(isPresented: Binding(get: { store.review != nil }, set: { on in if !on { store.review = nil } })) {
            ReviewStoryView(week: store.review ?? "") {
                Task { try? await Task.sleep(for: .milliseconds(600)); showGenerator = true }  // erst nach dem Schließen der Story
            }
        }
        .sheet(isPresented: Binding(get: { sharedCode != nil }, set: { on in if !on { sharedCode = nil } })) {
            if let code = sharedCode {
                SharedRecipeSheet(code: code) { id in
                    Task {
                        withAnimation(Theme.spring) { tab = .rezepte }
                        try? await Task.sleep(for: .milliseconds(450))  // Sheet zu, Tab-Wechsel baut den NavigationStack neu
                        deepRecipe = id
                    }
                }
                .presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet)
            }
        }
        .task { await store.loadAll() }
        .onChange(of: store.api.online) { _, on in  // Netz zurück → Warteschlange senden und frisch laden (66)
            if on { Task { await store.loadAll() } }
        }
        .modifier(PushAsk(active: store.askPush))
        .onOpenURL { url in Task { await open(url) } }
        .onChange(of: store.recipeFilter) { _, f in  // Start-Karte → Rezepte-Tab (RecipesTab übernimmt den Filter)
            if f != nil { withAnimation(Theme.spring) { tab = .rezepte } }
        }
        .onReceive(delegate.$pendingURL) { url in  // Mitteilung angetippt
            guard let url else { return }
            delegate.pendingURL = nil
            Task { await open(url) }
        }
    }

    /// Router für essenapp://start, essenapp://generator, essenapp://offer/<id>, essenapp://recipe/new, essenapp://recipe/<id>,
    /// essenapp://list/<kette>, essenapp://coupon/<id>, essenapp://review/<woche>, essenapp://achievements,
    /// essenapp://import-recipe/<code>.
    private func open(_ url: URL) async {
        guard url.scheme == "essenapp" else { return }
        withAnimation(Theme.spring) { quickOpen = false }
        switch url.host() {
        case "start":
            withAnimation(Theme.spring) { tab = .start }
        case "generator":
            showGenerator = true
        case "recipe" where url.lastPathComponent == "new":
            showRecipeForm = true
        case "recipe":  // Lunchbox-Push „für morgen vorbereiten“ (24)
            guard let id = Int(url.lastPathComponent) else { return }
            if store.plan == nil { await store.loadAll() }
            withAnimation(Theme.spring) { tab = .rezepte }
            try? await Task.sleep(for: .milliseconds(350))  // Tab-Wechsel baut den NavigationStack neu
            deepRecipe = id
        case "offer":
            guard let id = Int(url.lastPathComponent) else { return }
            if !store.offers.contains(where: { o in o.id == id }) { await store.loadAll() }
            guard let offer = store.offers.first(where: { o in o.id == id }) else { store.flash("Angebot nicht mehr verfügbar"); return }
            withAnimation(Theme.spring) { tab = .angebote }
            try? await Task.sleep(for: .milliseconds(350))  // Tab-Wechsel baut den NavigationStack neu
            deepOffer = offer
        case "list":
            let chain = url.lastPathComponent
            withAnimation(Theme.spring) { tab = .einkauf }
            try? await Task.sleep(for: .milliseconds(350))
            deepList = chain
        case "coupon":  // Ablauf-Push (38a) → Kasse
            guard let id = Int(url.lastPathComponent) else { return }
            store.checkoutCoupon = id
        case "review":  // Wochenrückblick-Push So 19:00 (55)
            let week = url.lastPathComponent
            store.review = week.count == 8 && week.dropFirst(4).hasPrefix("-W") && week.filter(\.isNumber).count == 6 ? week : ""  // „2026-W45“
        case "achievements":  // „Neuer Erfolg“ (54)
            withAnimation(Theme.spring) { tab = .start }
            try? await Task.sleep(for: .milliseconds(350))
            deepAchievements = true
        case "import-recipe":  // geteiltes Rezept (56)
            let code = url.lastPathComponent
            guard AppStore.validShareCode(code) else { store.flash("Rezept-Link ungültig"); return }
            sharedCode = code
        default:
            break
        }
    }
}

/// Schnell-Aktionen hinter dem Mittel-Button (E14).
struct QuickActions: View {
    enum Action { case plan, barcode, list, recipe, scan }
    let select: (Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Was möchtest du tun?").font(Theme.F.caption).foregroundStyle(Theme.C.text2).padding(.horizontal, 8)
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    tile(.plan, "✨", "Wochenplan erstellen", "KI plant mit den Angeboten", color: Theme.C.accent, main: true)
                    tile(.barcode, "🔎", "Barcode scannen", "Produkt auf die Merkliste", color: Theme.C.deal)
                }
                GridRow {
                    tile(.list, "🛒", "Einkaufsliste", "Artikel abhaken & ergänzen", color: Theme.C.kcal)
                    tile(.recipe, "📝", "Rezept anlegen", "Eigenes Rezept speichern", color: Theme.C.violet)
                }
                GridRow {
                    tile(.scan, "📸", "Kühlschrank scannen", "Fotos → Vorrat & Kochideen", color: Theme.C.carbs).gridCellColumns(2)
                }
            }
        }
        .padding(14)
        .background(Theme.C.card, in: RoundedRectangle(cornerRadius: Theme.R.sheet, style: .continuous))
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
