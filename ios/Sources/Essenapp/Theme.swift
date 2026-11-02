import SwiftUI
import UIKit

/// Alle Werte aus docs/ui/design-system.md (v3, E38). Views nutzen nur diese Tokens.
enum Theme {
    /// Dynamische Farben: erster Wert hell, zweiter dunkel (Dark Mode, Feature 68; Werte in docs/ui/design-system.md).
    enum C {
        static let bg = Color(0xF3F3F3, 0x0F0F10)
        static let surface = Color(0xEAEAEA, 0x2C2C2E)
        static let card = Color(0xFFFFFF, 0x1C1C1E)
        static let cardTop = card  // Alias für ältere Stellen
        static let line = Color(light: UIColor.black.withAlphaComponent(0.06), dark: UIColor.white.withAlphaComponent(0.1))
        static let text1 = Color(0x111111, 0xF5F5F5)
        static let text2 = Color(0x8A8A8E, 0xA0A0A5)
        static let text3 = Color(0xB4B4B8, 0x8A8A8E)
        static let action = Color(0x111111, 0xF5F5F5)  // dunkel: helle Pille mit dunkler Schrift
        static let onAction = Color(0xFFFFFF, 0x111111)
        static let accent = Color(hex: 0xFF5B2E)  // Orange: Marke, Auswahl, Preise-Akzent (v3), bleibt im Dunkeln
        static let accentSoft = Color(0xFFE9E1, 0x3A1E14)
        static let accentDeep = Color(0xE0461C, 0xFF7A52)
        static let highlight = Color(hex: 0xFFB199)  // helles Orange für kleine Akzente
        static let deal = Color(hex: 0xFF5A36)
        static let success = Color(0x1FA35C, 0x34C77B)
        static let successSoft = Color(0xDFF5E8, 0x12301F)
        static let warning = Color(hex: 0xF7B731)
        static let danger = Color(0xE5483B, 0xFF6B5E)
        static let tabInactive = Color(0xA9ACB2, 0x6C6C70)
        static let kcal = Color(hex: 0xFF8A3D)
        static let protein = Color(hex: 0xFF5A5F)
        static let carbs = Color(hex: 0x3DBE6B)
        static let fat = Color(hex: 0xF7B731)
        static let violet = Color(hex: 0x8E7CFF)  // Schnell-Aktion „Rezept anlegen“
        // Flächen, die in beiden Modi dunkel bzw. hinter Fotos liegen
        static let imageBg = Color(0xF7F7F7, 0x2A2A2D)  // Produktbild-Fläche (Angebotskarte)
        static let heroDark = Color(0x141414, 0x1C1C1E)  // dunkler Kopf im Angebotsdetail, Tab-Leiste ohne Glas
        static let scrim = Color(light: UIColor.black.withAlphaComponent(0.25), dark: UIColor.black.withAlphaComponent(0.55))
        static let shimmer = Color(light: UIColor.white.withAlphaComponent(0.7), dark: UIColor.white.withAlphaComponent(0.12))
        static let photoDim = Color(light: .clear, dark: UIColor.black.withAlphaComponent(0.12))  // Fotos im Dunkeln leicht abdunkeln
        static let plate = Color.white  // Logos und Teller bleiben auf weißem Plättchen (auch dunkel)
        // Blüten-Diagramm (ShareBloom): Blätter der Reihe nach, „Sonstiges“ in text3
        static let bloom: [Color] = [0xFF5B2E, 0x3DBE6B, 0xF7B731, 0x3E9BFF, 0x8E7CFF, 0xFF5DA2, 0x22B5C9, 0xFF8A3D].map { Color(hex: $0) }
        static let listTints: [Color] = ([(0xFFE8E2, 0x3A2420), (0xE3F6EA, 0x1E3326), (0xEEEBFF, 0x2A2640), (0xFFF4D6, 0x3A3320),
                                          (0xE3F0FF, 0x1E2A3A), (0xFFE6F1, 0x3A2030)] as [(UInt32, UInt32)]).map { t in Color(t.0, t.1) }
        // Kochmodus (S18): immer dunkler Grund, weiße Schrift
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
        case "obst_gemuese": Hue(color: Color(hex: 0x3DBE6B), tint: Color(0xE3F6EA, 0x1E3326), emoji: "🥦")
        case "fleisch_fisch": Hue(color: Color(hex: 0xFF6B4A), tint: Color(0xFFE8E2, 0x3A2420), emoji: "🥩")
        case "kuehlung": Hue(color: Color(hex: 0x3E9BFF), tint: Color(0xE3F0FF, 0x1E2A3A), emoji: "🧀")
        case "vorrat": Hue(color: Color(hex: 0xF7B731), tint: Color(0xFFF4D6, 0x3A3320), emoji: "🥫")
        case "getraenke": Hue(color: Color(hex: 0x22B5C9), tint: Color(0xDFF6F9, 0x1A3236), emoji: "🥤")
        case "drogerie": Hue(color: Color(hex: 0x8E7CFF), tint: Color(0xEEEBFF, 0x2A2640), emoji: "🧴")
        case "haushalt": Hue(color: Color(hex: 0xFF5DA2), tint: Color(0xFFE6F1, 0x3A2030), emoji: "🧽")
        default: Hue(color: Color(hex: 0x8A8F98), tint: Color(0xF0F0EE, 0x2C2C2E), emoji: "🛒")
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

    /// Hell/Dunkel-Paar, folgt dem Erscheinungsbild (System · Hell · Dunkel) – ohne .xcassets (xtool).
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { trait in trait.userInterfaceStyle == .dark ? dark : light })
    }

    init(_ light: UInt32, _ dark: UInt32) { self.init(light: UIColor(hex: light), dark: UIColor(hex: dark)) }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
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

extension Locale {
    static let de = Locale(identifier: "de_DE")  // App ist deutsch, unabhängig von der Gerätesprache
}

/// Zahl im deutschen Format: 2,25 / 2 (Nachkommastellen nur, wenn nötig).
func num(_ value: Double, _ digits: ClosedRange<Int> = 0...1) -> String {
    value.formatted(.number.precision(.fractionLength(digits)).locale(.de))
}

/// Cent → "12,49 €"
func euro(_ cents: Int) -> String {
    (Double(cents) / 100).formatted(.currency(code: "EUR").locale(Locale(identifier: "de_DE")))
}
