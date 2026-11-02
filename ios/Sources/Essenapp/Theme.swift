import SwiftUI

/// Alle Werte aus docs/ui/design-system.md. Views nutzen nur diese Tokens.
enum Theme {
    enum C {
        static let bg = Color(hex: 0xECEBE7)
        static let surface = Color(hex: 0xF6F5F2)
        static let cardTop = Color.white
        static let cardBottom = Color(hex: 0xF3F2EE)
        static let text1 = Color(hex: 0x111111)
        static let text2 = Color(hex: 0x8C8C8C)
        static let text3 = Color(hex: 0xB8B8B4)
        static let action = Color(hex: 0x111111)
        static let onAction = Color.white
        static let accent = Color(hex: 0x9FE05A)
        static let accentDeep = Color(hex: 0x3E7B1F)
        static let deal = Color(hex: 0xFF5A36)
        static let success = Color(hex: 0x3E7B1F)
        static let warning = Color(hex: 0xF5A623)
        static let danger = Color(hex: 0xE5483B)
        static let tabInactive = Color(hex: 0xA3A3A0)
        static let kcal = Color(hex: 0x111111)
        static let protein = Color(hex: 0xE5483B)
        static let carbs = Color(hex: 0x6BBF3A)
        static let fat = Color(hex: 0xF5A623)
        static let listTints: [Color] = [0xF6DDD2, 0xDDE9D3, 0xE6DFF3, 0xF7EBC4, 0xD8E6F1, 0xF2DCE6].map { Color(hex: $0) }
    }

    /// iOS-Textstile, damit Dynamic Type funktioniert (Größen = iOS-Standard).
    enum F {
        static let display = Font.system(.largeTitle, weight: .heavy)
        static let title = Font.system(.title2, weight: .heavy)
        static let headline = Font.system(.headline, weight: .bold)
        static let body = Font.body
        static let callout = Font.system(.subheadline, weight: .semibold)
        static let caption = Font.system(.footnote, weight: .medium)
        static let micro = Font.system(.caption2, weight: .semibold)
    }

    enum R {
        static let chip: CGFloat = 14
        static let tile: CGFloat = 20
        static let card: CGFloat = 28
        static let sheet: CGFloat = 36
    }

    static let pagePadding: CGFloat = 20
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    func softShadow() -> some View { shadow(color: .black.opacity(0.07), radius: 16, y: 12) }
    func floatShadow() -> some View { shadow(color: .black.opacity(0.12), radius: 20, y: 18) }

    /// Karte: weißer Verlauf, Radius 28, weicher Schatten.
    func card(radius: CGFloat = Theme.R.card) -> some View {
        background(
            LinearGradient(colors: [Theme.C.cardTop, Theme.C.cardBottom], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
        .softShadow()
    }
}

/// Cent → "12,49 €"
func euro(_ cents: Int) -> String {
    (Double(cents) / 100).formatted(.currency(code: "EUR").locale(Locale(identifier: "de_DE")))
}
