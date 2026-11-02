import SwiftUI

/// Design v3 für die Teilen-Erweiterung. Die Erweiterung kann das App-Modul nicht importieren, darum stehen die
/// benötigten Werte hier noch einmal – gleiche Werte wie `ios/Sources/Essenapp/Theme.swift` (E58).
enum ST {
    static let bg = Color(hex: 0xF3F3F3)
    static let surface = Color(hex: 0xEAEAEA)
    static let card = Color.white
    static let line = Color.black.opacity(0.06)
    static let text1 = Color(hex: 0x111111)
    static let text2 = Color(hex: 0x8A8A8E)
    static let text3 = Color(hex: 0xB4B4B8)
    static let action = Color(hex: 0x111111)
    static let accent = Color(hex: 0xFF5B2E)
    static let accentSoft = Color(hex: 0xFFE9E1)
    static let accentDeep = Color(hex: 0xE0461C)
    static let warning = Color(hex: 0xF7B731)
    static let danger = Color(hex: 0xE5483B)
    static let success = Color(hex: 0x1FA35C)
    static let successSoft = Color(hex: 0xDFF5E8)

    static let title = Font.system(.title2, weight: .bold)
    static let headline = Font.system(.headline, weight: .bold)
    static let callout = Font.system(.subheadline, weight: .semibold)
    static let caption = Font.system(.footnote, weight: .medium)
    static let micro = Font.system(.caption2, weight: .semibold)

    static let tile: CGFloat = 16
    static let card24: CGFloat = 24
    static let page: CGFloat = 20
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    func stCard(radius: CGFloat = ST.card24) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(ST.card).shadow(color: .black.opacity(0.05), radius: 10, y: 4))
    }
}

/// Schwarzer bzw. farbiger Pill-Button (wie `PrimaryButtonStyle` der App).
struct STPrimary: ButtonStyle {
    var color = ST.action

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(color, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Weißer Pill-Button mit Haarlinie (wie `SecondaryButtonStyle`).
struct STSecondary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(ST.text1)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(ST.card, in: Capsule())
            .overlay(Capsule().strokeBorder(ST.line, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
