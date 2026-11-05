import EssenappShareUI
import StoreKit
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
        ZStack(alignment: .bottom) {
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
                .padding(.horizontal, 16).padding(.bottom, 96).zIndex(1)  // `.toast`: 130 über unten
            }
        }
        .environment(store)
        .environment(store.api)
        .environment(\.locale, .de)  // 24-h-Uhrzeiten, Komma – auch wenn das iPhone auf Englisch steht
        .onChange(of: Demo.appearance ?? appearance, initial: true) { _, _ in Self.apply("light") }  // v8 fest hell bis Phase 21.2
        .foregroundStyle(Theme.C.text1)
        .tint(Theme.C.ink)
        .font(Theme.F.body)
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

/// Glas-Banner oben, solange kein Netz bzw. Server nicht erreichbar ist (66, v8 d.html): Radius 26, wifioff 22, zwei Zeilen.
struct OfflineBanner: View {
    var body: some View {
        let label = HStack(spacing: 12) {
            Icon(.wifioff, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("Offline").font(Theme.F.text(14, .extrabold))
                Text("Änderungen werden später übertragen").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
            }
        }
        .foregroundStyle(Theme.C.ink)
        .padding(.horizontal, 18).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        Group {
            if #available(iOS 26.0, *) {
                label.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            } else {
                label.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .accessibilityElement(children: .combine)
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
    @Environment(\.requestReview) private var requestReview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var allOpen = ["quick", "alles"].contains(Demo.screen ?? "")  // „Alles“ aus dem „+“ (v9 2A)
    @State private var showRecipes = false  // Meine Rezepte (unter „+“, früher eigener Tab)
    @State private var showGenerator = ["generator", "generating", "singlestore", "generatorMore"].contains(Demo.screen ?? "")  // „Überrasch mich“
    @State private var planWeek = ["swipe", "match", "auswahl", "verteilen", "magnicht", "dishmenu"].contains(Demo.screen ?? "")  // Swipe-Stapel (20)
    @State private var showRecipeForm = false  // essenapp://recipe/new (S17)
    @State private var deepAchievements = false  // Push „Neuer Erfolg“ (54)
    @State private var sharedCode: String? = Demo.screen == "sharedrecipe" ? Demo.sharedRecipe.code : nil  // essenapp://import-recipe/<code> (56)

    private static var demoTab: AppTab {
        switch Demo.screen {
        case "offers", "offer", "stores", "watch", "scanner", "nextweek", "offerstock", "drogerie", "offersfilter", "offersempty", "watchedit", "watchsearch": .angebote
        case "plan", "guests", "dayDetail": .woche
        case "shopping", "list", "pantry", "fridgecam", "fridgereview", "cooknow", "offline", "voiceadd", "wallet", "bonus", "coupon": .einkauf
        default: .start
        }
    }

    /// Demo-Screens, die in der App als Sheet bzw. in der Erweiterung ohne Tab-Leiste erscheinen.
    private static let modalDemo = ["recipeform", "fridgecam", "fridgereview", "cooknow", "shareimport", "shareresult", "importlink",
                                    "nomood", "substitute", "leftovers", "couponadd", "widget", "widgetlock", "liveactivity", "fridgeintro",
                                    "rating", "planslot", "recipeform1", "cookprep", "cookvoice", "cookdone", "cooking"]

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .start: StartView(tab: $tab, showGenerator: $showGenerator, planWeek: $planWeek, allOpen: $allOpen)
        case .woche: RecipesTab(planWeek: $planWeek, week: true)
        case .angebote: OffersView()
        case .einkauf: ShoppingView()
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.C.bg.ignoresSafeArea()

            NavigationStack {
                Group {
                    switch (Demo.screen, tab) {
                    case ("recipe", _), ("cooking", _), ("cookprep", _), ("cookvoice", _), ("cookdone", _), ("sharecard", _): RecipeDetailView(meal: Demo.plan.entries[2])
                    case ("recipes", _): RecipesTab(planWeek: $planWeek)
                    case ("myrecipe", _): SavedRecipeView(recipeId: Demo.savedRecipe.id)
                    case ("recipeform", _): RecipeFormSheet(editing: Demo.savedRecipe, page: 1)
                    case ("recipeform1", _): RecipeFormSheet(editing: Demo.savedRecipe, page: 0)
                    case ("planslot", _): PlanSlotSheet(recipeId: Demo.savedRecipe.id, title: Demo.savedRecipe.title)
                    case ("rating", _): RatingSheet(meal: Demo.plan.entries[2])
                    case ("ersparnis", _): SavingsView()
                    case ("imported", _): SavedRecipeView(recipeId: Demo.importedRecipe.id)
                    case ("instagram", _): InstagramShareView()
                    case ("widgetsetup", _): InstagramShareView(widget: true)
                    case ("widget", _): WidgetGallery()
                    case ("widgetlock", _): WidgetGallery(lock: true)
                    case ("liveactivity", _): LiveActivityGallery()
                    case ("fridgecam", _): FridgeScanSheet()
                    case ("fridgeintro", _): FridgeScanSheet(stage: .intro)
                    case ("fridgereview", _): FridgeScanSheet(stage: .review)
                    case ("cooknow", _): FridgeScanSheet(stage: .cook)
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
                    case ("variety", _): VarietyView()
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
                .navigationDestination(isPresented: $showRecipes) { RecipesTab(planWeek: $planWeek).backBar() }
            }
            .contentMargins(.bottom, Theme.S.nav - 34, for: .scrollContent)  // Ende jeder Liste über der Tab-Leiste erreichbar
            .id("\(tab)-\(resetToken)")  // Tab-Wechsel schließt offene Detailseiten
            .animation(.easeInOut(duration: 0.2), value: tab)

            if allOpen {  // „Alles“ liegt unter der Tab-Leiste, „+“ bleibt als × sichtbar (f.html 2A)
                Theme.C.scrim.ignoresSafeArea()
                    .onTapGesture { go(.close) }
                    .accessibilityLabel("Alles schließen")
                    .accessibilityAddTraits(.isButton)
                    .transition(.opacity)
                    .zIndex(1)
                AllSheet { g in go(g) }
                    .padding(.top, 36)
                    .ignoresSafeArea(edges: .bottom)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom))
                    .zIndex(2)
            }
            if !Self.modalDemo.contains(Demo.screen ?? ""), store.tabBarHiders == 0 {
                NotchTabBar(selected: $tab, badges: [.angebote: store.watchHits], plusOpen: allOpen,
                            plus: { withAnimation(reduceMotion ? nil : Theme.spring) { allOpen.toggle() } }) {
                    if allOpen { go(.close) } else { resetToken += 1 }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)  // Leiste (120 inkl. Home-Balken) bis an den Bildschirmrand
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom))
                .zIndex(3)
            }
            if !store.newAchievements.isEmpty { UnlockOverlay().zIndex(4) }  // Vollbild-Moment (54)
        }
        .sheet(isPresented: Binding(get: { store.scanning }, set: { on in store.scanning = on })) {
            FridgeScanSheet().presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet)
        }
        .fullScreenCover(isPresented: Binding(get: { store.barcode }, set: { on in store.barcode = on })) { BarcodeScanView() }
        .sheet(isPresented: $showGenerator) { PlanGeneratorSheet().presentationDetents([.large]) }
        .fullScreenCover(isPresented: $planWeek) { SwipeView() }
        .sheet(isPresented: $showRecipeForm) { RecipeFormSheet().presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
        .fullScreenCover(isPresented: Binding(get: { store.checkoutCoupon != nil }, set: { on in if !on { store.checkoutCoupon = nil } })) {
            if let id = store.checkoutCoupon { CouponCheckoutView(id: id) }
        }
        .fullScreenCover(isPresented: Binding(get: { store.review != nil }, set: { on in if !on { store.review = nil } })) {
            ReviewStoryView(week: store.review ?? "") {
                Task { try? await Task.sleep(for: .milliseconds(600)); planWeek = true }  // erst nach dem Schließen der Story
            }
        }
        .sheet(isPresented: Binding(get: { sharedCode != nil }, set: { on in if !on { sharedCode = nil } })) {
            if let code = sharedCode {
                SharedRecipeSheet(code: code) { id in
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))  // erst nach dem Schließen des Sheets
                        deepRecipe = id
                    }
                }
                .presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet)
            }
        }
        .task { await store.loadAll() }
        .task { if !store.demo { await ProStore.listen(store: store) } }  // Verlängerungen, Käufe auf anderen Geräten
        .sheet(isPresented: Binding(get: { store.api.paywall != nil }, set: { on in if !on { store.api.paywall = nil } })) {
            PaywallSheet(reason: store.api.paywall ?? "").presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet)
        }
        .onChange(of: store.askReview) { _, ask in
            if ask { requestReview(); store.askReview = false }
        }
        .onChange(of: store.api.online) { _, on in  // Netz zurück → Warteschlange senden und frisch laden (66)
            if on { Task { await store.loadAll() } }
        }
        .modifier(PushAsk(active: store.askPush))
        .onOpenURL { url in Task { await open(url) } }
        .onChange(of: store.recipeFilter) { _, f in  // Start-Karte → Meine Rezepte (RecipesTab übernimmt den Filter)
            if f != nil { showRecipes = true }
        }
        .onChange(of: tab) { _, _ in if allOpen { go(.close) } }
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
        withAnimation(Theme.spring) { allOpen = false }
        switch url.host() {
        case "start":
            withAnimation(Theme.spring) { tab = .start }
        case "generator":
            planWeek = true
        case "recipe" where url.lastPathComponent == "new":
            showRecipeForm = true
        case "recipe":  // Lunchbox-Push „für morgen vorbereiten“ (24)
            guard let id = Int(url.lastPathComponent) else { return }
            if store.plan == nil { await store.loadAll() }
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

extension MainView {
    /// Ziele aus „Alles“: Fläche schließen, dann Tab wechseln bzw. Ablauf öffnen.
    fileprivate func go(_ g: AllSheet.Go) {
        withAnimation(reduceMotion ? nil : Theme.spring) { allOpen = false }
        switch g {
        case .close: break
        case .tab(let t): withAnimation(Theme.spring) { tab = t }
        case .recipes: showRecipes = true
        case .planWeek: planWeek = true
        case .generator: showGenerator = true
        case .scan: store.scanning = true
        case .barcode: store.barcode = true
        case .review: store.review = ""
        case .recipe(let id): deepRecipe = id
        }
    }
}
