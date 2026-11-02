import SwiftUI

struct ContentView: View {
    @State private var store = AppStore(api: API())

    var body: some View {
        Group {
            if store.isOnboarded {
                MainView()
            } else {
                OnboardingView()
            }
        }
        .environment(store)
        .environment(store.api)
        .preferredColorScheme(.light)  // nur heller Modus in v1 (E15); sonst wird Systemtext im Dark Mode weiß
        .foregroundStyle(Theme.C.text1)
        .tint(Theme.C.text1)
    }
}

struct MainView: View {
    @Environment(AppStore.self) private var store
    @State private var tab = AppTab.start
    @State private var quickOpen = false
    @State private var showGenerator = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.C.bg.ignoresSafeArea()

            NavigationStack {
                Group {
                    switch tab {
                    case .start: StartView(showGenerator: $showGenerator)
                    case .angebote: OffersView()
                    case .einkauf: ShoppingView()
                    case .rezepte: RecipesTab(showGenerator: $showGenerator)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.C.bg)
                .toolbar(.hidden, for: .navigationBar)
            }

            if quickOpen {
                Theme.C.bg.opacity(0.6).background(.ultraThinMaterial).ignoresSafeArea()
                    .onTapGesture { quickOpen = false }
                QuickActions { action in
                    quickOpen = false
                    switch action {
                    case .plan: showGenerator = true
                    case .list: tab = .einkauf
                    case .scan, .recipe: break  // Phase 4/5
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            TabBar(selected: $tab, quickOpen: $quickOpen)
        }
        .sheet(isPresented: $showGenerator) { PlanGeneratorSheet().presentationDetents([.large]) }
        .task { await store.loadAll() }
    }
}

/// Schnell-Aktionen hinter dem Mittel-Button (E14).
struct QuickActions: View {
    enum Action { case plan, scan, list, recipe }
    let select: (Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Was möchtest du tun?").font(Theme.F.caption).foregroundStyle(Theme.C.text2).padding(.horizontal, 8)
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    tile(.plan, "sparkles", "Wochenplan erstellen", "KI plant mit den Angeboten", main: true)
                    tile(.scan, "barcode.viewfinder", "Barcode scannen", "Produkt merken oder prüfen")
                }
                GridRow {
                    tile(.list, "text.badge.plus", "Zur Einkaufsliste", "Artikel schnell hinzufügen")
                    tile(.recipe, "square.and.pencil", "Rezept anlegen", "Eigenes Rezept speichern")
                }
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.R.sheet, style: .continuous))
        .floatShadow()
    }

    private func tile(_ action: Action, _ symbol: String, _ title: String, _ subtitle: String, main: Bool = false) -> some View {
        Button { select(action) } label: {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.C.text1)
                    .frame(width: 42, height: 42)
                    .background(main ? Theme.C.accent : .white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.F.callout)
                    Text(subtitle).font(Theme.F.micro).foregroundStyle(main ? Color(hex: 0xBDBDBD) : Theme.C.text2)
                }
            }
            .multilineTextAlignment(.leading)
            .foregroundStyle(main ? Theme.C.onAction : Theme.C.text1)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .background(main ? Theme.C.action : Theme.C.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}
