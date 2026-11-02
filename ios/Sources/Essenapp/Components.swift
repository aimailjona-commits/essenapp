import SwiftUI

// Bausteine aus docs/ui/design-system.md (Abschnitt Komponenten, v2).

struct DisplayHeader: View {
    let line1: String
    let line2: String

    var body: some View {
        (Text(line1 + "\n").font(Theme.F.display).foregroundStyle(Theme.C.text1)
            + Text(line2).font(Theme.F.displayLight).foregroundStyle(Theme.C.text2))
            .tracking(-0.5)
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
            StoreLogo(chain: chain, size: 16)
            Text(Labels.chain(chain))
        }
        .font(Theme.F.micro)
        .foregroundStyle(Theme.C.text2)
        .padding(.leading, 3).padding(.trailing, 9)
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

/// Kurze Bestätigung oben (z.B. „Zur Liste hinzugefügt“), optional mit Aktions-Knopf („In den Vorrat“).
struct Toast: View {
    let text: String
    var symbol = "checkmark.circle.fill"
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Label(text, systemImage: symbol).lineLimit(2)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.C.text1)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(.white, in: Capsule())
                    .buttonStyle(PressableStyle())
            }
        }
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.leading, 16).padding(.trailing, actionTitle == nil ? 16 : 6).padding(.vertical, actionTitle == nil ? 12 : 6)
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

/// Tab-Leiste: Liquid Glass ab iOS 26 (Kapsel mit Tabs + eigener Glas-Kreis für „+“), sonst dunkle Kapsel.
struct TabBar: View {
    @Binding var selected: AppTab
    @Binding var quickOpen: Bool
    var reselect: () -> Void = {}
    @Namespace private var pill

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        tabs(glass: true)
                            .padding(5)
                            .glassEffect(.regular.interactive(), in: Capsule())
                        plusButton(glass: true)
                            .glassEffect(.regular.tint(quickOpen ? Theme.C.accent : Theme.C.accent.opacity(0.85)).interactive(), in: Circle())
                    }
                }
            } else {
                HStack(spacing: 4) {
                    tabs(glass: false)
                    plusButton(glass: false).background(quickOpen ? Theme.C.accent : .white, in: Circle())
                }
                .padding(7)
                .background(Color(hex: 0x141414), in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
            }
        }
        .padding(.horizontal, 16)
        .sensoryFeedback(.selection, trigger: selected)
        .sensoryFeedback(.impact(weight: .medium), trigger: quickOpen)
    }

    private func tabs(glass: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in item(tab, glass: glass) }
        }
    }

    private func plusButton(glass: Bool) -> some View {
        Button { withAnimation(Theme.spring) { quickOpen.toggle() } } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .rotationEffect(.degrees(quickOpen ? 45 : 0))
                .foregroundStyle(glass || quickOpen ? .white : Theme.C.text1)
                .frame(width: 58, height: 58)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Schnell-Aktionen")
    }

    private func item(_ tab: AppTab, glass: Bool) -> some View {
        let on = selected == tab
        return Button {
            if selected == tab { reselect() }
            withAnimation(Theme.spring) { selected = tab; quickOpen = false }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.symbol).font(.system(size: 18, weight: .semibold)).symbolEffect(.bounce, value: on)
                Text(tab.title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(on ? Theme.C.accent : (glass ? Theme.C.text1 : Color.white.opacity(0.6)))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                if on {
                    Capsule().fill(glass ? Theme.C.accent.opacity(0.14) : Color.white.opacity(0.12))
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Großes Stimmungsfoto aus den App-Ressourcen (Resources/hero, freie Lizenz, siehe CREDITS.md).
struct HeroImage: View {
    let name: String

    var body: some View {
        // Color.clear bestimmt die Größe, das Foto füllt nur aus – sonst macht scaledToFill die ganze Seite breiter
        Color.clear.overlay {
            if let url = Bundle.module.url(forResource: name, withExtension: "jpg"), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Theme.C.accent, Theme.C.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .clipped()
    }
}

/// Offizielles Händler-Logo (zur Laufzeit von Wikimedia Commons geladen, nicht im Repo, E39). Fallback: Buchstabe.
struct StoreLogo: View {
    let chain: String
    var size: CGFloat = 36

    var body: some View {
        RemoteImage(url: Labels.logoURL(chain)) {
            Text(String(Labels.chain(chain).prefix(1)))
                .font(.system(size: size * 0.45, weight: .bold)).foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Theme.storeColor(chain))
        }
        .padding(size * 0.12)
        .frame(width: size, height: size)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(Theme.C.line, lineWidth: 0.5))
    }
}

/// Runde Kategorie-Bilder mit Unterstrich unter der Auswahl (wie DashBite).
struct CategoryCircles: View {
    let items: [(key: String, label: String, emoji: String)]
    @Binding var selected: String?
    @Namespace private var underline

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(items, id: \.key) { item in
                    let on = selected == item.key
                    Button { withAnimation(Theme.spring) { selected = on ? nil : item.key } } label: {
                        VStack(spacing: 6) {
                            Text(item.emoji).font(.system(size: 28))
                                .frame(width: 62, height: 62)
                                .background(.white, in: Circle())
                                .shadow(color: .black.opacity(on ? 0.12 : 0.05), radius: on ? 10 : 6, y: 3)
                                .scaleEffect(on ? 1.08 : 1)
                            Text(item.label).font(Theme.F.micro).foregroundStyle(on ? Theme.C.text1 : Theme.C.text2).lineLimit(1)
                            ZStack {
                                if on {
                                    Capsule().fill(Theme.C.text1).frame(width: 18, height: 3)
                                        .matchedGeometryEffect(id: "u", in: underline)
                                }
                            }
                            .frame(height: 3)
                        }
                        .frame(width: 70)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, Theme.pagePadding).padding(.vertical, 6)
        }
        .padding(.horizontal, -Theme.pagePadding)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// Pillen-Umschalter wie in den Vorlagen („All | Popular“): aktive Pille schwarz, gleitet mit.
struct PillSegment<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.0) { value, label in
                let on = selection == value
                Button { withAnimation(Theme.spring) { selection = value } } label: {
                    Text(label)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(on ? .white : Theme.C.text1)
                        .padding(.horizontal, 18).frame(height: 40)
                        .frame(maxWidth: .infinity)
                        .background {
                            if on { Capsule().fill(Theme.C.action).matchedGeometryEffect(id: "seg", in: ns) }
                            else { Capsule().fill(Theme.C.card) }
                        }
                }
                .buttonStyle(PressableStyle())
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Fester Aktionsbereich unten (CTA): liegt als Safe-Area-Einschub unter dem Scroll-Inhalt – der letzte Inhalt
/// bleibt erreichbar – mit Verlauf von transparent nach `bg`, damit nichts zwischen den Buttons durchscheint.
struct CTABar<Bar: View>: ViewModifier {
    var bottom: CGFloat
    var horizontal: CGFloat
    @ViewBuilder let bar: () -> Bar

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            bar()
                .padding(.horizontal, horizontal)
                .padding(.top, 28)
                .padding(.bottom, bottom)
                .background(
                    LinearGradient(stops: [.init(color: Theme.C.bg.opacity(0), location: 0), .init(color: Theme.C.bg, location: 0.3)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .bottom)
                )
        }
    }
}

extension View {
    /// `bottom`: Abstand nach unten (Standard: über der Tab-Leiste), `horizontal`: 0, wenn der Container schon Rand hat.
    func ctaBar<B: View>(bottom: CGFloat = Theme.ctaAboveTabBar, horizontal: CGFloat = Theme.pagePadding,
                         @ViewBuilder _ bar: @escaping () -> B) -> some View {
        modifier(CTABar(bottom: bottom, horizontal: horizontal, bar: bar))
    }
}

// MARK: Rezepte (3) & Nährwerte (2)

/// Herz für Favoriten (Rezeptdetail, Karten): hüpft beim Umschalten, mit Haptik.
struct HeartButton: View {
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: on ? "heart.fill" : "heart")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(on ? Theme.C.accent : Theme.C.text1)
                .symbolEffect(.bounce, value: on)
                .frame(width: 44, height: 44)
                .background(Theme.C.card, in: Circle())
                .overlay(Circle().strokeBorder(Theme.C.line, lineWidth: 0.5))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.impact(weight: .medium), trigger: on)
        .accessibilityLabel(on ? "Aus Favoriten entfernen" : "Als Favorit merken")
    }
}

/// Kleine Sterne-Anzeige (Durchschnitt, halbe Sterne).
struct StarsView: View {
    let value: Double
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                let v = value - Double(i - 1)
                Image(systemName: v >= 0.75 ? "star.fill" : v >= 0.25 ? "star.leadinghalf.filled" : "star")
            }
        }
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(Theme.C.warning)
        .accessibilityElement()
        .accessibilityLabel("\(num(value)) von 5 Sternen")
    }
}

/// „Für: 🧑‍🍳 Jona ▾“ – Mitglied wählen (Rezept, Tagesansicht; 48).
struct PersonPicker: View {
    @Environment(AppStore.self) private var store
    @Binding var person: Int?

    var body: some View {
        let who = store.profiles.first { $0.memberId == (person ?? store.profile?.memberId) } ?? store.profile
        if let who {
            HStack(spacing: 8) {
                Text("Für:").font(Theme.F.callout).foregroundStyle(Theme.C.text2)
                Menu {
                    ForEach(store.profiles) { p in
                        Button("\(p.emoji) \(p.name)") { withAnimation(Theme.spring) { person = p.memberId } }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("\(who.emoji) \(who.name)")
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                    }
                    .font(Theme.F.callout).foregroundStyle(Theme.C.text1)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Theme.C.surface, in: Capsule())
                }
                .accessibilityLabel("Für \(who.name), ändern")
            }
            .sensoryFeedback(.selection, trigger: person)
        }
    }
}

/// Anteile für das Blüten-Diagramm: unter 3 % → „Sonstiges“, ganze Prozent mit Summe genau 100.
enum Bloom {
    struct Part: Equatable {
        var name: String
        var percent: Int
    }

    static func parts(_ items: [CompositionItem]) -> [Part] {
        let total = items.map(\.share).reduce(0, +)
        guard total > 0 else { return [] }
        var groups = items.map { ($0.name, $0.share / total) }.filter { $0.1 >= 0.03 }.sorted { $0.1 > $1.1 }
        let rest = 1 - groups.map(\.1).reduce(0, +)
        if rest > 0.0001 { groups.append(("Sonstiges", rest)) }
        // größte Reste bekommen die fehlenden Prozentpunkte
        let raw = groups.map { $0.1 * 100 }
        var pct = raw.map { Int($0) }
        let order = raw.indices.sorted { raw[$0] - Double(pct[$0]) > raw[$1] - Double(pct[$1]) }
        for i in order.prefix(max(0, 100 - pct.reduce(0, +))) { pct[i] += 1 }
        return zip(groups, pct).map { g, p in Part(name: g.0, percent: p) }.filter { $0.percent > 0 }
    }

    static func selfTest() {
        let p = parts([.init(name: "Reis", grams: 160, share: 0.333), .init(name: "Huhn", grams: 160, share: 0.333),
                       .init(name: "Sauce", grams: 150, share: 0.314), .init(name: "Salz", grams: 2, share: 0.01),
                       .init(name: "Öl", grams: 2, share: 0.01)])
        assert(p.map(\.percent).reduce(0, +) == 100, "Blüte summiert nicht 100 %")
        assert(p.count == 4 && p.last?.name == "Sonstiges", "Anteile < 3 % nicht gruppiert")
        assert(parts([]).isEmpty)
    }
}

/// Blütenblatt: Tropfen von unten (Mitte der Blüte) nach oben (Spitze).
struct Petal: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY),
                   control1: CGPoint(x: r.minX - r.width * 0.15, y: r.maxY - r.height * 0.45),
                   control2: CGPoint(x: r.minX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
                   control1: CGPoint(x: r.maxX, y: r.minY),
                   control2: CGPoint(x: r.maxX + r.width * 0.15, y: r.maxY - r.height * 0.45))
        p.closeSubpath()
        return p
    }
}

/// `ShareBloom`: Zutatenanteile nach Gewicht als Blüte, Tellerfoto in der Mitte; Blätter wachsen nacheinander auf.
struct ShareBloom: View {
    let items: [CompositionItem]
    var photo: URL?
    var seed = ""
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let parts = Bloom.parts(items)
        let top = Double(parts.map(\.percent).max() ?? 1)
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let inner = size * 0.17, outer = size * 0.32
            let width = min(size * 0.2, 2 * .pi * inner * 1.5 / Double(max(parts.count, 1)))
            ZStack {
                ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                    let angle = Double(i) / Double(parts.count) * 2 * .pi
                    let length = inner + (outer - inner) * (0.3 + 0.7 * Double(part.percent) / top)
                    let color = part.name == "Sonstiges" ? Theme.C.text3 : Theme.C.bloom[i % Theme.C.bloom.count]
                    let delay = reduceMotion ? 0 : Double(i) * 0.09
                    Petal()
                        .fill(LinearGradient(colors: [color.opacity(0.3), color], startPoint: .bottom, endPoint: .top))
                        .frame(width: width, height: length)
                        .scaleEffect(grown ? 1 : 0.01, anchor: .bottom)
                        .offset(y: -length / 2)
                        .rotationEffect(.radians(angle))
                        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(delay), value: grown)
                    VStack(spacing: 0) {
                        Text("\(part.percent) %").font(.system(.footnote, design: .rounded, weight: .bold)).monospacedDigit()
                        Text(part.name).font(Theme.F.micro).foregroundStyle(Theme.C.text2).lineLimit(2).multilineTextAlignment(.center)
                    }
                    .frame(width: 66)
                    .offset(x: sin(angle) * (length + 24), y: -cos(angle) * (length + 24))
                    .opacity(grown ? 1 : 0)
                    .animation(.easeOut(duration: 0.3).delay(delay + 0.25), value: grown)
                    .accessibilityElement(children: .combine)
                }
                Plate(url: photo, size: inner * 2 + 8, seed: seed)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 320)
        .onAppear {
            #if DEBUG
            Bloom.selfTest()
            #endif
            grown = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zusammensetzung nach Gewicht")
    }
}

/// Ring gegen ein Ziel (Tagesringe, 2).
struct GoalRing: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(fraction, 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(Theme.spring, value: fraction)
    }
}

/// Schimmer über einem Inhalt, solange Werte noch berechnet werden.
struct Shimmer: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                LinearGradient(colors: [.clear, .white.opacity(0.8), .clear], startPoint: .leading, endPoint: .trailing)
                    .offset(x: phase * 120)
                    .onAppear { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 } }
                    .allowsHitTesting(false)
                    .accessibilityLabel("Wird berechnet")
            }
        }
        .clipped()
    }
}

/// "2026-11-02T18:30:00" → "2.11.2026"
func shortDate(_ iso: String) -> String {
    let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
    return parts.count == 3 ? "\(parts[2]).\(parts[1]).\(parts[0])" : iso
}
