import SwiftUI

// Ältere Bausteine, optisch auf v8 umgestellt (docs/ui/redesign-v8.md). Neue v8-Bausteine: V8Components.swift.

struct DisplayHeader: View {
    let line1: String
    var line2 = ""
    var size: CGFloat = 34  // v8 `.t1`
    var onDark = false
    var color: Color?  // z. B. Tinte auf Pastell (Listenkopf)

    var body: some View {
        VStack(alignment: .leading, spacing: -size * 0.1) {  // Zeilenhöhe 1.1
            Text(line1).font(Theme.F.display(size)).foregroundStyle(color ?? (onDark ? .white : Theme.C.text1))
            if !line2.isEmpty {
                Text(line2).font(Theme.F.displayItalic(size)).foregroundStyle(onDark ? Theme.C.tabInactive : Theme.C.text3)
            }
        }
        .lineLimit(2).minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder = "Suchen"

    var body: some View {
        HStack(spacing: 10) {
            Icon(.search, size: 20).foregroundStyle(Theme.C.ink2)
            TextField(placeholder, text: $text).submitLabel(.search).font(Theme.F.text(15))
            if !text.isEmpty {
                Button { withAnimation(Theme.spring) { text = "" } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.C.text3)
                }
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Suche leeren")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: Theme.S.search)
        .background(Theme.C.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
    }
}

struct RoundIconButton: View {
    let systemName: String
    var dark = false
    var fill: Color?  // v3: `surface` (Standard), `card` auf farbigen Köpfen, `lime`
    var small = false
    var label: String
    let action: () -> Void

    var body: some View {
        let size = small ? Theme.S.roundButtonSmall : Theme.S.roundButton
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: small ? 14 : 18, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(dark ? Theme.C.onInk : Theme.C.ink)
                .background(dark ? Theme.C.ink : fill ?? .clear, in: Circle())
                .overlay { if !dark && fill == nil { Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }  // v8 `.x`
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color = Theme.C.action

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.F.button)
            .foregroundStyle(color == Theme.C.lime ? Theme.C.onLime : color == Theme.C.action ? Theme.C.onAction : .white)
            .frame(maxWidth: .infinity, minHeight: Theme.S.button)
            .padding(.horizontal, 26)
            .background(color, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// v3: Limetten-Knopf „jetzt loslegen“ – höchstens einmal pro Screen.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonStyle(color: Theme.C.lime).makeBody(configuration: configuration)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.F.button2)
            .foregroundStyle(Theme.C.ink)
            .frame(maxWidth: .infinity, minHeight: Theme.S.button2)
            .padding(.horizontal, 20)
            .overlay(Capsule().strokeBorder(Theme.C.ink, lineWidth: Theme.S.hair))  // v8 `.btn2`
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

    var tint: Color {
        switch self {
        case .kcal: Theme.C.kcalTint
        case .protein: Theme.C.proteinTint
        case .carbs: Theme.C.carbsTint
        case .fat: Theme.C.fatTint
        }
    }

    var emoji: String {
        switch self {
        case .kcal: "🔥"
        case .protein: "💪"
        case .carbs: "🌾"
        case .fat: "🧈"
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
        Text(nutrient.emoji)
            .font(.system(size: 17))
            .frame(width: 34, height: 34)
            .background(nutrient.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct NutrientStat: View {
    let nutrient: Nutrient
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            NutrientIcon(nutrient: nutrient)
            Text(value).font(.system(.callout, weight: .heavy)).monospacedDigit()
            Text(nutrient.label).font(.caption).foregroundStyle(Theme.C.text2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Getönte Kachel: große Zahl, Bezeichnung (Rezept, Angebot).
struct NutrientTile: View {
    let nutrient: Nutrient
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title2, weight: .black)).tracking(-0.6).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(nutrient.label).font(.system(.caption, weight: .bold)).opacity(0.7)
        }
        .foregroundStyle(Theme.C.text1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14).padding(.horizontal, 12)
        .background(nutrient.tint, in: RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Bilder

/// Netzbild mit weichem Einblenden; Bilder landen im URLCache (in der App vergrößert).
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fit
    var dim = true  // Fotos im Dunkeln leicht abdunkeln (68), Logos nicht
    @ViewBuilder let placeholder: () -> Placeholder

    var body: some View {
        // Offline (66): schon gesehene Bilder direkt aus dem URLCache – AsyncImage nutzt ohne Netz keinen Cache
        if API.offline, let url, let data = URLCache.shared.cachedResponse(for: URLRequest(url: url))?.data, let ui = UIImage(data: data) {
            photo(Image(uiImage: ui))
        } else {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                if let image = phase.image {
                    photo(image).transition(.opacity)
                } else {
                    placeholder()
                }
            }
        }
    }

    private func photo(_ image: Image) -> some View {
        image.resizable().aspectRatio(contentMode: contentMode).overlay(dim ? Theme.C.photoDim : .clear)
    }
}

/// Tellerfoto (v8 `.plate`): Kreis, 6er-Rand in `card`, Teller-Schatten. Ohne Bild: Speisen-Emoji auf `card`.
struct Plate: View {
    let url: URL?
    var size: CGFloat = 120
    var seed = ""
    var emoji: String?

    private static let foods = ["🍛", "🍲", "🍝", "🥗", "🍳", "🍣"]

    var body: some View {
        let food = emoji ?? Self.foods[abs(seed.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % Self.foods.count]
        RemoteImage(url: url, contentMode: .fill) {
            Text(food).font(.system(size: size * 0.54)).frame(width: size, height: size).background(Theme.C.plate)  // Teller bleibt weiß
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .padding(Theme.S.plateRing)
        .background(Theme.C.card, in: Circle())
        .plateShadow()
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
            .font(style == .strong ? Theme.F.deal : Theme.F.soft)
            .lineLimit(1)
            .padding(.horizontal, style == .strong ? 8 : 10)
            .frame(height: style == .strong ? Theme.S.dealPill : Theme.S.softPill)
            .foregroundStyle(style == .strong ? .white : Theme.C.ink)
            .background(style == .strong ? Theme.C.deal : style == .soft ? Theme.C.blue1 : Theme.C.sage, in: Capsule())  // v8 `.deal` / `.soft` / `.ok`
    }
}

/// Laden-Pille: Farbpunkt in der Ordnerfarbe + Name. `onDark` für den Start-Kopf.
struct StoreChip: View {
    let chain: String
    var onDark = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.storeColor(chain)).frame(width: 8, height: 8)
            Text(chain.isEmpty ? "Überall" : Labels.chain(chain)).lineLimit(1)
        }
        .font(Theme.F.soft)
        .foregroundStyle(onDark ? Theme.C.onInk : Theme.C.ink)
        .padding(.horizontal, 10)
        .frame(height: Theme.S.softPill)
        .background(onDark ? Theme.C.inkChip : .clear, in: Capsule())
        .overlay(Capsule().strokeBorder(onDark ? Theme.C.inkChipLine : Theme.C.line, lineWidth: Theme.S.hair))
    }
}

/// v3: umrandete Pille mit Zahl-Kapsel. `filled` = Schalter-Filter (an: schwarz mit Limetten-Zahl).
struct FilterChip: View {
    let label: String
    var count: Int?
    var color: Color = Theme.C.action
    var filled = false
    var countHighlight = false  // Merkliste: Zahl in `deal`
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label).lineLimit(1)
                if let count {
                    Text("\(count)")
                        .font(.system(.caption, weight: .bold)).monospacedDigit()
                        .padding(.horizontal, 7).frame(minWidth: 24, minHeight: 24)
                        .foregroundStyle(countHighlight ? .white : Theme.C.ink)
                        .background(countHighlight ? Theme.C.deal : selected ? Theme.C.blue : Theme.C.blue1, in: Capsule())
                        .contentTransition(.numericText())
                }
            }
            .font(Theme.F.chip)
            .padding(.horizontal, 15)
            .frame(height: Theme.S.chip)
            .foregroundStyle(selected ? Theme.C.onInk : Theme.C.ink2)
            .background(selected ? Theme.C.ink : .clear, in: Capsule())  // v8 `.chip.on`
            .overlay { if !selected { Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
            .frame(minHeight: 44)
            .contentShape(Capsule())
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
                    Icon(.star, size: 34)
                        .foregroundStyle(star <= rating ? Theme.C.ink : Theme.C.ink3)
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

    var body: some View {
        VStack(spacing: 4) {
            Ill(Self.illustration(emoji)).frame(width: 150, height: 150)  // v8: Tusche-Zeichnung statt Emoji
                .background(Circle().fill(Theme.C.blue1).frame(width: 130, height: 130))
            Text(title).font(Theme.F.t2).padding(.top, 6).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Text(text).font(Theme.F.small).foregroundStyle(Theme.C.ink2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)  // mehrzeilig, nie abgeschnitten (Erklär-Sheets)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action).buttonStyle(PrimaryButtonStyle()).fixedSize().padding(.top, 14)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .appear()
    }

    /// Passende Zeichnung zum bisherigen Emoji.
    static func illustration(_ emoji: String) -> String {
        switch emoji {
        case "🛒", "🧺", "🛍️": "bag"
        case "🔎", "🔍", "👀": "binoculars"
        case "🥶", "🧊", "❄️": "fridge"
        case "📖", "📚": "cookbook"
        case "😴", "💤": "lying"
        case "🍝": "pasta"
        default: "pot"
        }
    }
}

/// v3: Pille mit Satz + „Erneut“.
struct ErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(message).font(Theme.F.text(14, .bold)).foregroundStyle(Theme.C.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Erneut", action: retry)
                .font(Theme.F.text(14, .extrabold)).foregroundStyle(Theme.C.onInk)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(Theme.C.ink, in: Capsule())
                .buttonStyle(PressableStyle())
        }
        .padding(.leading, 18).padding(.trailing, 6).padding(.vertical, 6)
        .background(Theme.C.warn, in: Capsule())
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
                LinearGradient(colors: [.clear, Theme.C.shimmer, .clear], startPoint: .leading, endPoint: .trailing)
                    .offset(x: phase * 300)
                    .mask(RoundedRectangle(cornerRadius: Theme.R.card, style: .continuous))
            )
            .frame(height: height)
            .onAppear { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 } }
            .accessibilityLabel("Lädt")
    }
}

/// Kurze Bestätigung (`.toast` v8): Tinten-Kapsel 14/700, optional Aktions-Knopf („In den Vorrat“).
struct Toast: View {
    let text: String
    var symbol = "checkmark"
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Text(text).lineLimit(2)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(Theme.F.toast)
                    .foregroundStyle(Theme.C.ink)
                    .padding(.horizontal, 14).frame(minHeight: 36)
                    .background(Theme.C.blue, in: Capsule())
                    .buttonStyle(PressableStyle())
            }
        }
        .font(Theme.F.toast)
        .foregroundStyle(Theme.C.onInk)
        .padding(.leading, 18).padding(.trailing, actionTitle == nil ? 18 : 6)
        .padding(.vertical, actionTitle == nil ? 12 : 6)
        .background(Theme.C.ink, in: Capsule())
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: Tab-Bar

/// Tabs der Nav v8 (Mockup: Start, Woche, Angebote, Einkauf, Rezepte).
enum AppTab: CaseIterable {
    case start, woche, angebote, einkauf, rezepte

    var title: String {
        switch self {
        case .start: "Start"
        case .woche: "Woche"
        case .angebote: "Angebote"
        case .einkauf: "Einkauf"
        case .rezepte: "Rezepte"
        }
    }

    var icon: Icon8 {
        switch self {
        case .start: .home
        case .woche: .cal
        case .angebote: .tag
        case .einkauf: .bag
        case .rezepte: .book
        }
    }
}

/// Großes Stimmungsfoto aus den App-Ressourcen (Resources/hero, freie Lizenz, siehe CREDITS.md).
struct HeroImage: View {
    let name: String

    var body: some View {
        // Color.clear bestimmt die Größe, das Foto füllt nur aus – sonst macht scaledToFill die ganze Seite breiter
        Color.clear.overlay {
            if let url = Bundle.module.url(forResource: name, withExtension: "jpg"), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill().overlay(Theme.C.photoDim)
            } else {
                LinearGradient(colors: [Theme.C.accent, Theme.C.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .clipped()
    }
}

/// Offizielles Händler-Logo auf weißem Plättchen, immer ganz sichtbar (Wikimedia, nur verlinkt, E44). Fallback: Kürzel bzw. 🧺.
struct StoreLogo: View {
    let chain: String
    var size: CGFloat = 36

    var body: some View {
        RemoteImage(url: Labels.logoURL(chain), dim: false) {
            Text(chain.isEmpty ? "🧺" : String(Labels.chain(chain).prefix(1)))
                .font(.system(size: size * 0.42, weight: .heavy)).foregroundStyle(Theme.C.ink)
        }
        .padding(size * 0.12)
        .frame(width: size, height: size)
        .background(Theme.C.plate)  // Logos auf weißem Plättchen, auch im Dunkeln (68)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
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
                                .background(Theme.C.card, in: Circle())
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

/// Segment v8 (`.seg`): Haarlinie, Innenabstand 4, aktive Pille Tinte (gleitet mit).
struct PillSegment<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, label in
                let on = selection == value
                Button { withAnimation(Theme.spring) { selection = value } } label: {
                    Text(label)
                        .font(Theme.F.text(13, .bold, relativeTo: .footnote))
                        .foregroundStyle(on ? Theme.C.onInk : Theme.C.ink2)
                        .lineLimit(1).minimumScaleFactor(0.75)  // „Kühlschrank“ nicht umbrechen
                        .padding(.horizontal, 12).frame(minHeight: Theme.S.segment)
                        .frame(maxWidth: .infinity)
                        .background { if on { Capsule().fill(Theme.C.action).matchedGeometryEffect(id: "seg", in: ns) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
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

/// Herz für Favoriten (v8 `a1-fav`): Umriss Tinte, gemerkt füllt es sich von unten rosé und springt kurz.
struct HeartButton: View {
    let on: Bool
    var fill: Color = .clear
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Icon8.heart.path(.stroke).fill(Theme.C.rose)
                    .frame(width: 24, height: 24)
                    .mask(alignment: .bottom) { Rectangle().frame(height: on ? 24 : 0) }
                Icon(.heart)
            }
            .scaleEffect(on ? 1 : 0.94)
            .animation(.spring(response: 0.4, dampingFraction: 0.5), value: on)
            .foregroundStyle(Theme.C.ink)
            .frame(width: Theme.S.roundButton, height: Theme.S.roundButton)
            .background(fill, in: Circle())
            .overlay { if fill == .clear { Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
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
        .foregroundStyle(Theme.C.ink)
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
                Text("Für:").font(Theme.F.callout).foregroundStyle(Theme.C.ink2)
                Menu {
                    ForEach(store.profiles) { p in
                        Button("\(p.emoji) \(p.name)") { withAnimation(Theme.spring) { person = p.memberId } }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("\(who.emoji) \(who.name)")
                        Icon(.chev, size: 14).rotationEffect(.degrees(90))
                    }
                    .font(Theme.F.chip).foregroundStyle(Theme.C.ink)
                    .padding(.horizontal, 15).frame(height: Theme.S.chip)
                    .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
                    .frame(minHeight: 44)
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
                    let color = part.name == "Sonstiges" ? Theme.C.bloomOther : Theme.C.bloom[i % Theme.C.bloom.count]
                    let delay = reduceMotion ? 0 : Double(i) * 0.09
                    Petal()
                        .fill(LinearGradient(colors: [color.opacity(0.45), color], startPoint: .bottom, endPoint: .top))
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
                LinearGradient(colors: [.clear, Theme.C.shimmer, .clear], startPoint: .leading, endPoint: .trailing)
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
