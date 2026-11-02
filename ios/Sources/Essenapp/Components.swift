import SwiftUI

// Bausteine aus docs/ui/design-system.md (Abschnitt Komponenten, v2).

struct DisplayHeader: View {
    let line1: String
    let line2: String

    var body: some View {
        (Text(line1 + "\n").foregroundStyle(Theme.C.text1) + Text(line2).foregroundStyle(Theme.C.text3))
            .font(Theme.F.display)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder = "Suchen"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.C.text3)
            TextField(placeholder, text: $text).submitLabel(.search)
            if !text.isEmpty {
                Button { withAnimation(Theme.spring) { text = "" } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.C.text3)
                }
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Suche leeren")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(Theme.C.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: 0.5))
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
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(dark ? Theme.C.onAction : Theme.C.text1)
                .background(dark ? Theme.C.action : Theme.C.card, in: Circle())
                .overlay(Circle().strokeBorder(Theme.C.line, lineWidth: dark ? 0 : 0.5))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color = Theme.C.action

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(Theme.C.onAction)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(color, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(Theme.C.text1)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.C.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
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
        case .protein: "bolt.fill"
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
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(nutrient.color)
            .frame(width: 30, height: 30)
            .background(nutrient.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct NutrientStat: View {
    let nutrient: Nutrient
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            NutrientIcon(nutrient: nutrient)
            Text(value).font(.system(.subheadline, design: .rounded, weight: .bold)).monospacedDigit()
            Text(nutrient.label).font(Theme.F.micro).foregroundStyle(Theme.C.text2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct NutrientTile: View {
    let nutrient: Nutrient
    let value: String

    var body: some View {
        NutrientStat(nutrient: nutrient, value: value).padding(.vertical, 12).card(radius: Theme.R.tile)
    }
}

// MARK: Bilder

/// Netzbild mit weichem Einblenden; Bilder landen im URLCache (in der App vergrößert).
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fit
    @ViewBuilder let placeholder: () -> Placeholder

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: contentMode).transition(.opacity)
            } else {
                placeholder()
            }
        }
    }
}

/// Freigestelltes Tellerfoto (KI-generiert, E13). Ohne Bild: Teller mit Speisen-Farbverlauf.
struct Plate: View {
    let url: URL?
    var size: CGFloat = 120
    var seed = ""

    private static let foods: [(UInt32, UInt32, String)] = [
        (0xF6B26B, 0xB8471A, "🍛"), (0xFFD27A, 0xC07A1A, "🍲"), (0xF08A5D, 0xB8361F, "🍝"),
        (0x9CCB6B, 0x4E7F2A, "🥗"), (0xFBE29B, 0xD9542F, "🍳"), (0xFFB49A, 0x3E9BFF, "🍣"),
    ]

    var body: some View {
        let food = Self.foods[abs(seed.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % Self.foods.count]
        RemoteImage(url: url, contentMode: .fill) {
            ZStack {
                Circle().fill(.white)
                Circle().strokeBorder(Theme.C.bg, lineWidth: size * 0.025).padding(size * 0.1)
                Circle()
                    .fill(RadialGradient(colors: [Color(hex: food.0), Color(hex: food.1)], center: .init(x: 0.35, y: 0.3),
                                         startRadius: 0, endRadius: size * 0.42))
                    .padding(size * 0.16)
                Text(food.2).font(.system(size: size * 0.3))
            }
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
            .background(style == .strong ? Theme.C.deal : style == .soft ? Theme.C.deal.opacity(0.1) : Theme.C.accentSoft, in: Capsule())
    }
}

struct StoreChip: View {
    let chain: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Theme.storeColor(chain)).frame(width: 7, height: 7)
            Text(Labels.chain(chain))
        }
        .font(Theme.F.micro)
        .foregroundStyle(Theme.C.text2)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Theme.C.surface, in: Capsule())
    }
}

struct FilterChip: View {
    let label: String
    var count: Int?
    var color: Color = Theme.C.action
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                if let count {
                    Text("\(count)").foregroundStyle(selected ? .white.opacity(0.7) : Theme.C.text3).contentTransition(.numericText())
                }
            }
            .font(.system(.caption, weight: .semibold))
            .padding(.horizontal, 13)
            .frame(height: 34)
            .foregroundStyle(selected ? .white : Theme.C.text1)
            .background(selected ? color : Theme.C.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: selected ? 0 : 0.5))
            .animation(Theme.spring, value: selected)
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct RatingStars: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: 12) {
            ForEach(1...5, id: \.self) { star in
                Button { withAnimation(Theme.spring) { rating = star } } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.system(size: 34))
                        .foregroundStyle(star <= rating ? Theme.C.warning : Theme.C.text3)
                        .symbolEffect(.bounce, value: rating == star)
                        .scaleEffect(star <= rating ? 1.05 : 1)
                }
                .accessibilityLabel("\(star) Sterne")
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: rating)
    }
}

// MARK: Zustände

struct EmptyState: View {
    var emoji = "🍽️"
    let title: String
    let text: String
    var buttonTitle: String?
    var action: (() -> Void)?
    @State private var float = false

    var body: some View {
        VStack(spacing: 12) {
            Text(emoji).font(.system(size: 52))
                .frame(width: 104, height: 104)
                .background(Theme.C.accentSoft, in: Circle())
                .offset(y: float ? -4 : 4)
                .onAppear { withAnimation(.easeInOut(duration: 1.8).repeatForever()) { float = true } }
            Text(title).font(Theme.F.headline).padding(.top, 6)
            Text(text).font(Theme.F.caption).foregroundStyle(Theme.C.text2).multilineTextAlignment(.center)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action).buttonStyle(PrimaryButtonStyle()).padding(.top, 8).frame(maxWidth: 260)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .appear()
    }
}

struct ErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        EmptyState(emoji: "📡", title: "Das hat nicht geklappt", text: message, buttonTitle: "Erneut versuchen", action: retry)
    }
}

/// Lade-Platzhalter mit Schimmer (ein einziger animierter Verlauf).
struct SkeletonCard: View {
    var height: CGFloat = 120
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.R.card, style: .continuous)
            .fill(Theme.C.surface)
            .overlay(
                LinearGradient(colors: [.clear, .white.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
                    .offset(x: phase * 300)
                    .mask(RoundedRectangle(cornerRadius: Theme.R.card, style: .continuous))
            )
            .frame(height: height)
            .onAppear { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 } }
            .accessibilityLabel("Lädt")
    }
}

/// Kurze Bestätigung oben (z.B. „Zur Liste hinzugefügt“).
struct Toast: View {
    let text: String
    var symbol = "checkmark.circle.fill"

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.C.action, in: Capsule())
            .floatShadow()
            .transition(.move(edge: .top).combined(with: .opacity))
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
        case .start: "house.fill"
        case .angebote: "tag.fill"
        case .einkauf: "bag.fill"
        case .rezepte: "book.closed.fill"
        }
    }
}

struct TabBar: View {
    @Binding var selected: AppTab
    @Binding var quickOpen: Bool
    var reselect: () -> Void = {}
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            item(.start)
            item(.angebote)
            Button { withAnimation(Theme.spring) { quickOpen.toggle() } } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .rotationEffect(.degrees(quickOpen ? 45 : 0))
                    .foregroundStyle(Theme.C.onAction)
                    .frame(width: 60, height: 60)
                    .background(quickOpen ? Theme.C.accent : Theme.C.action, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.C.bg, lineWidth: 4))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
            }
            .buttonStyle(PressableStyle())
            .offset(y: -16)
            .padding(.horizontal, 6)
            .sensoryFeedback(.impact(weight: .medium), trigger: quickOpen)
            .accessibilityLabel("Schnell-Aktionen")
            item(.einkauf)
            item(.rezepte)
        }
        .padding(.horizontal, 8)
        .frame(height: 70)
        .background(.white, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Theme.C.line, lineWidth: 0.5))
        .floatShadow()
        .padding(.horizontal, 16)
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func item(_ tab: AppTab) -> some View {
        let on = selected == tab
        return Button {
            if selected == tab { reselect() }
            withAnimation(Theme.spring) { selected = tab; quickOpen = false }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol).font(.system(size: 18)).symbolEffect(.bounce, value: on)
                Text(tab.title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(on ? Theme.C.accentDeep : Theme.C.tabInactive)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.C.accentSoft)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
