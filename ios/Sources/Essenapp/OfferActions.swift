import SwiftUI

// Feste Angebots-Knöpfe (v9 f.html Abschnitt 3 „Angebot – Merken, Auf Liste, Rezepte damit“):
// überall gleich auf Start, in der Suche („Alles“), in den Angebots-Kacheln und (als „Passt zu“) im Detail.

extension AppStore {
    /// Gerichte im Wochenplan, die dieses Angebot als Zutat nutzen („Rezepte damit“).
    // shortcut: nur Plan-Gerichte; „Meine Rezepte“ bräuchten Zutaten bzw. Angebots-Treffer in GET /recipes
    func meals(using offer: OfferDTO) -> [MealDTO] {
        plan?.entries.filter { m in m.recipe.ingredients.contains { i in i.offerId == offer.id } } ?? []
    }
}

/// `.f9-mini`: Herz (Merkliste, gemerkt = Blau) · „+“ (Einkaufsliste, danach grüner Haken) · Buch (Rezepte damit).
/// Kreise 32, Tap-Fläche 44.
struct OfferActions: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let offer: OfferDTO
    var ring: Color?  // Kachel: Kreise sitzen auf der Bildkante und bekommen einen Rand in Kartenfarbe
    var onAdd: (() -> Void)?  // nach „Auf Liste“, z. B. Flug der Zeichnung zur Nav
    @State private var recipes = false

    private enum L {
        static let mini: CGFloat = 32
        static let icon: CGFloat = 15
        static let gap: CGFloat = 6
        static let ring: CGFloat = 3
    }

    var body: some View {
        let watched = store.watch(for: offer) != nil
        let listed = store.isOnList(offer)
        HStack(spacing: L.gap) {
            Button { Task { await store.toggleWatch(offer) } } label: {
                mini(.heart, fg: Theme.C.ink, bg: watched ? Theme.C.blue : Theme.C.bg, line: !watched)
            }
            .accessibilityLabel(watched ? "Von der Merkliste entfernen" : "Merken")
            Button {
                guard !listed else { return }
                store.addToList(offer)
                onAdd?()
            } label: {
                mini(listed ? .check : .plus, fg: listed ? Theme.C.ink : Theme.C.onInk, bg: listed ? Theme.C.sage : Theme.C.ink, line: false)
                    .keyframeAnimator(initialValue: 1.0, trigger: listed) { v, s in v.scaleEffect(s) } keyframes: { _ in
                        KeyframeTrack {
                            LinearKeyframe(reduceMotion ? 1 : 0.7, duration: 0.01)
                            CubicKeyframe(reduceMotion ? 1 : 1.15, duration: 0.2)
                            CubicKeyframe(1, duration: 0.14)
                        }
                    }
            }
            .sensoryFeedback(.success, trigger: listed)
            .accessibilityLabel(listed ? "Auf der Einkaufsliste" : "Auf die Einkaufsliste")
            Button { recipes = true } label: { mini(.book, fg: Theme.C.ink, bg: Theme.C.bg, line: true) }
                .accessibilityLabel("Rezepte damit")
        }
        .buttonStyle(PressableStyle())
        .sheet(isPresented: $recipes) {
            NavigationStack {
                ScrollView { OfferRecipes(offer: offer).padding(Theme.pagePadding) }
                    .background(Theme.C.bg.ignoresSafeArea())
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func mini(_ icon: Icon8, fg: Color, bg: Color, line: Bool) -> some View {
        Icon(icon, size: L.icon)
            .foregroundStyle(fg)
            .frame(width: L.mini, height: L.mini)
            .background(bg, in: Circle())
            .overlay { if line { Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
            .overlay { if let ring { Circle().stroke(ring, lineWidth: L.ring).padding(-L.ring / 2) } }
            .padding(6).contentShape(Rectangle()).padding(-6)
    }
}

/// „Rezepte mit …“ (`.f9-card`): Teller 44 mit Name und wann geplant, zwei nebeneinander.
struct OfferRecipes: View {
    @Environment(AppStore.self) private var store
    let offer: OfferDTO

    private enum L {
        static let radius: CGFloat = 28
        static let pad: CGFloat = 14
        static let plate: CGFloat = 44
        static let plateRing: CGFloat = 3
        static let gap: CGFloat = 10
    }

    var body: some View {
        let meals = store.meals(using: offer)
        let name = offer.title.split(separator: ",").first.map(String.init) ?? offer.title
        VStack(alignment: .leading, spacing: L.gap) {
            Text("Rezepte mit \(name)".uppercased())
                .font(Theme.F.lbl).tracking(11 * 0.08).foregroundStyle(Theme.C.ink)
                .accessibilityAddTraits(.isHeader)
            if meals.isEmpty {
                // ohne Mockup: Leer-Zustand
                Text("Noch in keinem Gericht deiner Woche.").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: L.gap, alignment: .leading), count: 2),
                          alignment: .leading, spacing: L.gap) {
                    ForEach(meals, id: \.self) { meal in
                        NavigationLink { RecipeDetailView(meal: meal) } label: { row(meal) }
                            .buttonStyle(PressableStyle())
                    }
                }
            }
        }
        .padding(L.pad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.C.card, in: RoundedRectangle(cornerRadius: L.radius, style: .continuous))
    }

    private func row(_ meal: MealDTO) -> some View {
        HStack(spacing: L.gap) {
            RemoteImage(url: mediaURL(meal.recipe.imageUrl), contentMode: .fill) { Theme.C.card }
                .frame(width: L.plate, height: L.plate)
                .clipShape(Circle())
                .padding(L.plateRing)
                .background(Theme.C.bg, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(meal.recipe.title).font(Theme.F.text(13, .extrabold, relativeTo: .footnote)).lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(meal.day == store.today ? "heute geplant" : "\(Labels.days[meal.day]) geplant")
                    .font(Theme.F.text(11, .semibold, relativeTo: .caption2)).foregroundStyle(Theme.C.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Theme.C.ink)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
