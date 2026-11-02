import SwiftUI

// Bausteine aus docs/ui/design-system.md (Abschnitt Komponenten).

struct DisplayHeader: View {
    let line1: String
    let line2: String

    var body: some View {
        (Text(line1 + "\n").foregroundStyle(Theme.C.text1) + Text(line2).foregroundStyle(Theme.C.text2))
            .font(Theme.F.display)
            .tracking(-0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder = "Suchen"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.C.text3)
            TextField(placeholder, text: $text)
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(Theme.C.cardTop, in: Capsule())
        .softShadow()
    }
}

struct RoundIconButton: View {
    let systemName: String
    var dark = false
    var label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(dark ? Theme.C.onAction : Theme.C.text1)
                .background(dark ? Theme.C.action : Theme.C.cardTop, in: Circle())
                .softShadow()
        }
        .accessibilityLabel(label)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(Theme.C.onAction)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.C.action, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: Nährwerte

enum Nutrient: CaseIterable {
    case kcal, protein, carbs, fat

    var color: Color {
        switch self {
        case .kcal: Theme.C.kcal
        case .protein: Theme.C.protein
        case .carbs: Theme.C.carbs
        case .fat: Theme.C.fat
        }
    }

    var symbol: String {
        switch self {
        case .kcal: "flame.fill"
        case .protein: "cube.fill"
        case .carbs: "leaf.fill"
        case .fat: "drop.fill"
        }
    }

    var label: String {
        switch self {
        case .kcal: "kcal"
        case .protein: "Protein"
        case .carbs: "Kohlenh."
        case .fat: "Fett"
        }
    }
}

struct NutrientIcon: View {
    let nutrient: Nutrient

    var body: some View {
        Image(systemName: nutrient.symbol)
            .font(.system(size: 13))
            .foregroundStyle(nutrient.color)
            .frame(width: 30, height: 30)
            .background(nutrient.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Kleiner Wert unter Gericht-Karten.
struct NutrientStat: View {
    let nutrient: Nutrient
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            NutrientIcon(nutrient: nutrient)
            Text(value).font(.system(.subheadline, weight: .bold)).monospacedDigit()
            Text(nutrient.label).font(Theme.F.micro).foregroundStyle(Theme.C.text2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Große Kachel auf der Rezeptseite.
struct NutrientTile: View {
    let nutrient: Nutrient
    let value: String

    var body: some View {
        NutrientStat(nutrient: nutrient, value: value)
            .padding(.vertical, 12)
            .background(Theme.C.cardTop, in: RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
            .softShadow()
    }
}

// MARK: Bilder

/// Freigestelltes Tellerfoto (KI-generiert, E13). Ohne Bild: leerer Teller.
struct Plate: View {
    let url: URL?
    var size: CGFloat = 120

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Circle()
                .fill(RadialGradient(colors: [.white, Theme.C.surface], center: .center, startRadius: size * 0.3, endRadius: size * 0.5))
                .overlay(Circle().strokeBorder(Theme.C.bg, lineWidth: size * 0.02).padding(size * 0.18))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .floatShadow()
        .accessibilityHidden(true)
    }
}

// MARK: Chips & Badges

struct DealBadge: View {
    enum Style { case strong, soft, ok }
    let text: String
    var style = Style.strong

    var body: some View {
        Text(text)
            .font(Theme.F.micro)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .foregroundStyle(style == .strong ? .white : style == .soft ? Theme.C.deal : Theme.C.accentDeep)
            .background(
                style == .strong ? Theme.C.deal : style == .soft ? Theme.C.deal.opacity(0.12) : Theme.C.accentDeep.opacity(0.12),
                in: Capsule()
            )
    }
}

struct StoreChip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(Theme.F.micro)
            .foregroundStyle(Color(hex: 0x555555))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Theme.C.surface, in: Capsule())
    }
}

struct FilterChip: View {
    let label: String
    var count: Int?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                if let count { Text("\(count)").foregroundStyle(selected ? Color(hex: 0xBDBDBD) : Theme.C.text2) }
            }
            .font(.system(.caption, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .foregroundStyle(selected ? Theme.C.onAction : Theme.C.text1)
            .background(selected ? Theme.C.action : Theme.C.cardTop, in: Capsule())
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct RatingStars: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach(1...5, id: \.self) { star in
                Button { rating = star } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: 34))
                        .foregroundStyle(star <= rating ? Theme.C.warning : Theme.C.text3)
                }
                .accessibilityLabel("\(star) Sterne")
            }
        }
    }
}

// MARK: Zustände

struct EmptyState: View {
    let symbol: String
    let title: String
    let text: String
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 44)).foregroundStyle(Theme.C.text3)
            Text(title).font(Theme.F.headline)
            Text(text).font(Theme.F.caption).foregroundStyle(Theme.C.text2).multilineTextAlignment(.center)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action).buttonStyle(PrimaryButtonStyle()).padding(.top, 8)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

struct ErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        EmptyState(symbol: "wifi.exclamationmark", title: "Das hat nicht geklappt", text: message,
                   buttonTitle: "Erneut versuchen", action: retry)
    }
}

/// Platzhalter-Karte beim Laden (kein Spinner auf leerem Screen).
struct SkeletonCard: View {
    var height: CGFloat = 120
    @State private var dim = false

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.R.card, style: .continuous)
            .fill(Theme.C.cardTop.opacity(dim ? 0.5 : 1))
            .frame(height: height)
            .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { dim = true } }
            .accessibilityLabel("Lädt")
    }
}

// MARK: Tab-Bar

enum AppTab: CaseIterable {
    case start, angebote, einkauf, rezepte

    var title: String {
        switch self {
        case .start: "Start"
        case .angebote: "Angebote"
        case .einkauf: "Einkauf"
        case .rezepte: "Rezepte"
        }
    }

    var symbol: String {
        switch self {
        case .start: "house"
        case .angebote: "tag"
        case .einkauf: "bag"
        case .rezepte: "book.closed"
        }
    }
}

struct TabBar: View {
    @Binding var selected: AppTab
    @Binding var quickOpen: Bool

    var body: some View {
        HStack {
            item(.start)
            item(.angebote)
            Button { withAnimation(.spring(duration: 0.3)) { quickOpen.toggle() } } label: {
                Image(systemName: quickOpen ? "xmark" : "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.C.onAction)
                    .frame(width: 64, height: 64)
                    .background(Theme.C.action, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.C.bg, lineWidth: 5))
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 12)
            }
            .offset(y: -18)
            .accessibilityLabel("Schnell-Aktionen")
            item(.einkauf)
            item(.rezepte)
        }
        .padding(.horizontal, 6)
        .frame(height: 72)
        .background(.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .floatShadow()
        .padding(.horizontal, 16)
    }

    private func item(_ tab: AppTab) -> some View {
        Button { selected = tab; quickOpen = false } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.symbol).font(.system(size: 20))
                Text(tab.title).font(.system(size: 10, weight: .semibold))
                Circle().fill(selected == tab ? Theme.C.accent : .clear).frame(width: 5, height: 5)
            }
            .foregroundStyle(selected == tab ? Theme.C.text1 : Theme.C.tabInactive)
            .frame(maxWidth: .infinity)
        }
        .accessibilityAddTraits(selected == tab ? .isSelected : [])
    }
}
