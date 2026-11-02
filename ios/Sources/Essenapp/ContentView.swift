import SwiftUI

struct ContentView: View {
    @State private var api = API()
    @State private var tab = AppTab.start
    @State private var quickOpen = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.C.bg.ignoresSafeArea()

            Group {
                switch tab {
                case .start: ComponentDemoView()
                case .angebote: EmptyState(symbol: "tag", title: "Angebote", text: "Kommt in Phase 2.")
                case .einkauf: EmptyState(symbol: "bag", title: "Einkauf", text: "Kommt in Phase 3.")
                case .rezepte: EmptyState(symbol: "book.closed", title: "Rezepte", text: "Kommt in Phase 3.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if quickOpen {
                Theme.C.bg.opacity(0.6).background(.ultraThinMaterial).ignoresSafeArea()
                    .onTapGesture { quickOpen = false }
                QuickActions { quickOpen = false }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            TabBar(selected: $tab, quickOpen: $quickOpen)
        }
        .environment(api)
    }
}

/// Schnell-Aktionen hinter dem Mittel-Button (E14).
struct QuickActions: View {
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Was möchtest du tun?").font(Theme.F.caption).foregroundStyle(Theme.C.text2).padding(.horizontal, 8)
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    tile("sparkles", "Wochenplan erstellen", "KI plant mit den Angeboten", main: true)
                    tile("barcode.viewfinder", "Barcode scannen", "Produkt merken oder prüfen")
                }
                GridRow {
                    tile("text.badge.plus", "Zur Einkaufsliste", "Artikel schnell hinzufügen")
                    tile("square.and.pencil", "Rezept anlegen", "Eigenes Rezept speichern")
                }
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: Theme.R.sheet, style: .continuous))
        .floatShadow()
    }

    private func tile(_ symbol: String, _ title: String, _ subtitle: String, main: Bool = false) -> some View {
        Button(action: close) {
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

/// Phase 1: zeigt alle Bausteine und den Backend-Status.
struct ComponentDemoView: View {
    @Environment(API.self) private var api
    @State private var backendOK: Bool?
    @State private var search = ""
    @State private var rating = 4
    @State private var chip = 0

    var body: some View {
        @Bindable var api = api
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DisplayHeader(line1: "Was kochen wir", line2: "diese Woche?")
                SearchField(text: $search, placeholder: "Gericht oder Angebot suchen")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Backend").font(Theme.F.headline)
                    TextField("http://192.168.…:8000", text: $api.baseURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(14).background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.chip))
                    HStack {
                        Text(backendOK == nil ? "Backend: …" : backendOK! ? "Backend: ok" : "Backend: nicht erreichbar")
                            .font(Theme.F.callout)
                            .foregroundStyle(backendOK == true ? Theme.C.success : Theme.C.text2)
                        Spacer()
                        Button("Prüfen") { Task { backendOK = await api.health() } }.font(Theme.F.callout)
                    }
                }
                .padding(18).card()

                VStack(spacing: 14) {
                    Plate(url: nil, size: 150).padding(.top, -60)
                    Text("Chicken Tikka Masala").font(Theme.F.title)
                    Text("35 min · \(euro(245)) pro Portion").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                    HStack {
                        NutrientStat(nutrient: .kcal, value: "640")
                        NutrientStat(nutrient: .protein, value: "42 g")
                        NutrientStat(nutrient: .carbs, value: "58 g")
                        NutrientStat(nutrient: .fat, value: "18 g")
                    }
                }
                .padding(18).frame(maxWidth: .infinity).card().padding(.top, 60)

                HStack(spacing: 8) {
                    DealBadge(text: "−33 %")
                    DealBadge(text: "2 Zutaten im Angebot", style: .soft)
                    DealBadge(text: "im Vorrat", style: .ok)
                    StoreChip(name: "Rewe")
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(["Alle", "Rewe", "Aldi Süd", "Lidl"].enumerated()), id: \.offset) { i, name in
                            FilterChip(label: name, count: [214, 86, 72, 41][i], selected: chip == i) { chip = i }
                        }
                    }
                }

                HStack(spacing: 8) {
                    ForEach(Nutrient.allCases, id: \.self) { NutrientTile(nutrient: $0, value: "42") }
                }

                RatingStars(rating: $rating).frame(maxWidth: .infinity)
                SkeletonCard(height: 80)
                Button("Plan erstellen") {}.buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
        }
        .task { backendOK = await api.health() }
    }
}
