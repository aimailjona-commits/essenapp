import SwiftUI
import UIKit

/// Design v3 für die Teilen-Erweiterung. Die Erweiterung kann das App-Modul nicht importieren, darum stehen die
/// benötigten Werte hier noch einmal – gleiche Werte (hell/dunkel) wie `ios/Sources/Essenapp/Theme.swift` (E58, Dark Mode 68).
/// Die Erweiterung folgt dem System-Erscheinungsbild (die App-Einstellung kann sie ohne App Group nicht lesen).
enum ST {
    static let bg = Color(0xF3F3F3, 0x0F0F10)
    static let surface = Color(0xEAEAEA, 0x2C2C2E)
    static let card = Color(0xFFFFFF, 0x1C1C1E)
    static let line = Color(light: UIColor.black.withAlphaComponent(0.06), dark: UIColor.white.withAlphaComponent(0.1))
    static let text1 = Color(0x111111, 0xF5F5F5)
    static let text2 = Color(0x8A8A8E, 0xA0A0A5)
    static let text3 = Color(0xB4B4B8, 0x8A8A8E)
    static let action = Color(0x111111, 0xF5F5F5)
    static let onAction = Color(0xFFFFFF, 0x111111)
    static let pasteTint = Color(0x111111, 0xFF5B2E)  // System-PasteButton hat immer weiße Schrift → dunkel Orange statt heller Pille
    static let accent = Color(hex: 0xFF5B2E)
    static let accentSoft = Color(0xFFE9E1, 0x3A1E14)
    static let accentDeep = Color(0xE0461C, 0xFF7A52)
    static let warning = Color(hex: 0xF7B731)
    static let danger = Color(0xE5483B, 0xFF6B5E)
    static let success = Color(0x1FA35C, 0x34C77B)
    static let successSoft = Color(0xDFF5E8, 0x12301F)

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

/// Hintergrund der Erweiterung, bevor SwiftUI steht (ShareViewController).
public let shareBackground = UIColor { t in t.userInterfaceStyle == .dark ? UIColor(hex: 0x0F0F10) : UIColor(hex: 0xF3F3F3) }

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

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
            .foregroundStyle(color == ST.action ? ST.onAction : .white)
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
