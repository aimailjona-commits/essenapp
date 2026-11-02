import SwiftUI

/// Alle Werte aus docs/ui/design-system.md (v3, E38). Views nutzen nur diese Tokens.
enum Theme {
    enum C {
        static let bg = Color(hex: 0xF3F3F3)
        static let surface = Color(hex: 0xEAEAEA)
        static let card = Color.white
        static let cardTop = Color.white  // Alias für ältere Stellen
        static let line = Color.black.opacity(0.06)
        static let text1 = Color(hex: 0x111111)
        static let text2 = Color(hex: 0x8A8A8E)
        static let text3 = Color(hex: 0xB4B4B8)
        static let action = Color(hex: 0x111111)
        static let onAction = Color.white
        static let accent = Color(hex: 0xFF5B2E)  // Orange: Marke, Auswahl, Preise-Akzent (v3)
        static let accentSoft = Color(hex: 0xFFE9E1)
        static let accentDeep = Color(hex: 0xE0461C)
        static let highlight = Color(hex: 0xFFB199)  // helles Orange für kleine Akzente
        static let deal = Color(hex: 0xFF5A36)
        static let success = Color(hex: 0x1FA35C)
        static let successSoft = Color(hex: 0xDFF5E8)
        static let warning = Color(hex: 0xF7B731)
        static let danger = Color(hex: 0xE5483B)
        static let tabInactive = Color(hex: 0xA9ACB2)
        static let kcal = Color(hex: 0xFF8A3D)
        static let protein = Color(hex: 0xFF5A5F)
        static let carbs = Color(hex: 0x3DBE6B)
        static let fat = Color(hex: 0xF7B731)
        static let listTints: [Color] = [0xFFE8E2, 0xE3F6EA, 0xEEEBFF, 0xFFF4D6, 0xE3F0FF, 0xFFE6F1].map { Color(hex: $0) }
        // Kochmodus (S18): dunkler Grund, weiße Schrift
        static let cookBg = Color(hex: 0x111111)
        static let cookText2 = Color.white.opacity(0.6)
        static let cookSurface = Color.white.opacity(0.1)
    }

    /// Farbe + Tönung + Emoji pro Kategorie (Angebote, Liste).
    struct Hue {
        let color: Color
        let tint: Color
        let emoji: String
    }

    static func hue(category: String) -> Hue {
        switch category {
        case "obst_gemuese": Hue(color: Color(hex: 0x3DBE6B), tint: Color(hex: 0xE3F6EA), emoji: "🥦")
        case "fleisch_fisch": Hue(color: Color(hex: 0xFF6B4A), tint: Color(hex: 0xFFE8E2), emoji: "🥩")
        case "kuehlung": Hue(color: Color(hex: 0x3E9BFF), tint: Color(hex: 0xE3F0FF), emoji: "🧀")
        case "vorrat": Hue(color: Color(hex: 0xF7B731), tint: Color(hex: 0xFFF4D6), emoji: "🥫")
        case "getraenke": Hue(color: Color(hex: 0x22B5C9), tint: Color(hex: 0xDFF6F9), emoji: "🥤")
        case "drogerie": Hue(color: Color(hex: 0x8E7CFF), tint: Color(hex: 0xEEEBFF), emoji: "🧴")
        case "haushalt": Hue(color: Color(hex: 0xFF5DA2), tint: Color(hex: 0xFFE6F1), emoji: "🧽")
        default: Hue(color: Color(hex: 0x8A8F98), tint: Color(hex: 0xF0F0EE), emoji: "🛒")
        }
    }

    /// Eigene, neutrale Farbe pro Laden (keine Markenfarben, E18).
    static func storeColor(_ chain: String) -> Color {
        let palette: [UInt32] = [0xFF6B4A, 0x3DBE6B, 0x3E9BFF, 0xF7B731, 0x8E7CFF, 0xFF5DA2, 0x22B5C9, 0x15804F, 0xB0703C, 0x5B6CF0]
        let keys = Labels.chains.map(\.key)
        return Color(hex: palette[(keys.firstIndex(of: chain) ?? 0) % palette.count])
    }

    /// iOS-Textstile (Dynamic Type). Überschriften und Zahlen „rounded“ für einen freundlichen, modernen Look.
    enum F {
        static let display = Font.system(.largeTitle, weight: .bold)
        static let displayLight = Font.system(.largeTitle, weight: .regular)
        static let hero = Font.system(size: 44, weight: .black).width(.condensed)  // „HEY, JONA.“
        static let title = Font.system(.title2, weight: .bold)
        static let headline = Font.system(.headline, weight: .bold)
        static let body = Font.body
        static let callout = Font.system(.subheadline, weight: .semibold)
        static let caption = Font.system(.footnote, weight: .medium)
        static let micro = Font.system(.caption2, weight: .semibold)
        static let price = Font.system(.title3, weight: .bold)
        static let cookTitle = Font.system(.largeTitle, weight: .bold)
        static let cookStep = Font.system(.title, weight: .semibold)  // 28 pt, wächst mit Dynamic Type
        static let cookBody = Font.system(.title3, weight: .semibold)
        static let cookTimer = Font.system(.title3, design: .rounded, weight: .bold)
    }

    enum R {
        static let chip: CGFloat = 12
        static let tile: CGFloat = 16
        static let card: CGFloat = 24
        static let sheet: CGFloat = 32
    }

    static let pagePadding: CGFloat = 20
    static let ctaAboveTabBar: CGFloat = 96  // fester Button auf Detailseiten sitzt über der Tab-Leiste
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    /// Leichter Schatten: kleiner Radius, damit Scrollen flüssig bleibt.
    func softShadow() -> some View { shadow(color: .black.opacity(0.06), radius: 6, y: 3) }
    func floatShadow() -> some View { shadow(color: .black.opacity(0.12), radius: 12, y: 8) }

    /// Karte: weiß, Radius 24, ohne Rand, sehr weicher Schatten (v3).
    func card(radius: CGFloat = Theme.R.card) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.C.card)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        )
    }

    /// Erscheinen mit Versatz (für Listen: delay = index * 0.04).
    func appear(delay: Double = 0) -> some View { modifier(AppearModifier(delay: delay)) }
}

struct AppearModifier: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear { withAnimation(Theme.spring.delay(min(delay, 0.4))) { shown = true } }
    }
}

/// Antipp-Feedback: leicht kleiner werden, federnd zurück.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Cent → "12,49 €"
func euro(_ cents: Int) -> String {
    (Double(cents) / 100).formatted(.currency(code: "EUR").locale(Locale(identifier: "de_DE")))
}
