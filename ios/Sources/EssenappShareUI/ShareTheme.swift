import SwiftUI
import UIKit

/// Design v8 „Tinte & Bogen“ für Teilen-Erweiterung, Widget und Live-Aktivität. Dieses Modul sieht `Theme` der App nicht,
/// darum stehen die Werte hier noch einmal – gleich wie `ios/Sources/Essenapp/Theme.swift` (redesign-v8.md Abschnitt 2).
/// Fest hell wie die App, bis das Dunkel-Mockup v8 freigegeben ist.
public enum ST {
    // Farben (= Theme.C)
    public static let bg = Color(hex: 0xF3EEE4)
    public static let card = Color(hex: 0xFBF8F2)
    public static let ink = Color(hex: 0x151515)
    public static let ink2 = Color(hex: 0x7C776D)
    public static let ink3 = Color(hex: 0xB9B3A7)
    public static let line = Color(hex: 0xDCD5C7)
    public static let blue = Color(hex: 0xAFC4F2)
    public static let blue1 = Color(hex: 0xDCE5F8)
    public static let blue3 = Color(hex: 0x7C9BE6)
    public static let sage = Color(hex: 0xCFE3D2)
    public static let rose = Color(hex: 0xF2CFC8)
    public static let sand = Color(hex: 0xE7DCC5)
    public static let warn = Color(hex: 0xF6E2B8)
    public static let deal = Color(hex: 0xE0603F)
    public static let onInk = Color.white
    public static let plate = Color.white  // Logos und Teller auf weißem Kreis
    public static let scrim = ink.opacity(0.32)
    public static let shadow = Color(hex: 0x281E14)  // Schatten-Ton des Mockups (rgba 40,30,20)

    // Ältere Namen, auf v8 abgebildet (ShopActivity, bis Gruppe D umgebaut hat)
    public static let surface = card
    public static let text1 = ink, text2 = ink2, text3 = ink3
    public static let action = ink
    public static let onAction = onInk
    public static let accent = blue3  // Balken und Haken der Live-Aktivität (S40)
    public static let accentSoft = blue1
    public static let accentDeep = ink
    public static let warning = warn
    public static let danger = deal
    public static let success = Color(hex: 0x3F8F5A)
    public static let successSoft = sage

    /// Schriften wie `Theme.F`. Die App registriert sie beim Start; in den Erweiterungen fehlen die Dateien (keine
    /// Ressourcen im Modul) – dann nimmt iOS still die Systemschrift.
    public enum W { case medium, semibold, bold, extrabold }

    public static func serif(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("DMSerifDisplay-Regular", size: size, relativeTo: style)
    }

    public static func text(_ size: CGFloat, _ weight: W = .semibold, relativeTo style: Font.TextStyle = .body) -> Font {
        let name = switch weight {
        case .medium: "ManropeV8-Medium"
        case .semibold: "ManropeV8-SemiBold"
        case .bold: "ManropeV8-Bold"
        case .extrabold: "ManropeV8-ExtraBold"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    public static func num(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom("InterTightV8-SemiBold", size: size, relativeTo: style)
    }

    public static func numTracking(_ size: CGFloat) -> CGFloat { -0.05 * size }

    public static let t1 = serif(34, relativeTo: .largeTitle)
    public static let t2 = serif(24, relativeTo: .title)
    public static let rowName = serif(19, relativeTo: .title3)
    public static let small = text(15, .semibold, relativeTo: .subheadline)
    public static let lbl = text(11, .extrabold, relativeTo: .caption2)  // + Laufweite 0.08 em
    public static let button = text(16, .extrabold, relativeTo: .headline)
    public static let button2 = text(15, .extrabold, relativeTo: .headline)
    public static let pill = text(13, .bold, relativeTo: .footnote)
    public static let soft = text(12, .extrabold, relativeTo: .caption)
    public static let mono = Font.system(size: 12, weight: .medium, design: .monospaced)  // `.e-mono`

    // Ältere Schrift-Namen
    public static let title = t2
    public static let headline = text(17, .extrabold, relativeTo: .headline)
    public static let callout = text(15, .bold, relativeTo: .subheadline)
    public static let caption = text(13, .semibold, relativeTo: .footnote)
    public static let micro = lbl

    // Maße
    public static let hair: CGFloat = 1.5
    public static let buttonHeight: CGFloat = 56
    public static let button2Height: CGFloat = 52
    public static let field: CGFloat = 52
    public static let close: CGFloat = 40
    public static let check: CGFloat = 26
    public static let row: CGFloat = 60
    public static let rowCircle: CGFloat = 48
    public static let softPill: CGFloat = 24
    public static let bar: CGFloat = 8
    public static let sheetRadius: CGFloat = 36
    public static let grip = CGSize(width: 40, height: 5)
    public static let plateRing: CGFloat = 6
    public static let widgetRadius: CGFloat = 24  // `.e-w`
    public static let page: CGFloat = 24
    public static let tile: CGFloat = 24
    public static let card24: CGFloat = 24
    public static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)
}

/// Hintergrund der Erweiterung, bevor SwiftUI steht (ShareViewController).
public let shareBackground = UIColor(hex: 0xF3EEE4)

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension View {
    /// Fläche mit Haarlinie (nur für Übergänge; v8 baut Zeilen statt Karten).
    func stCard(radius: CGFloat = ST.card24) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(ST.card)
            .strokeBorder(ST.line, lineWidth: ST.hair))
    }

    /// Kleines Label in Großbuchstaben (`.lbl`).
    func stLabel() -> some View { font(ST.lbl).tracking(11 * 0.08).foregroundStyle(ST.ink2) }
}

/// `.btn` (Tinte, `blue` = `.btn.blue`) – Höhe 56, Kapsel, 16/800.
struct STPrimary: ButtonStyle {
    var color = ST.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ST.button)
            .foregroundStyle(color == ST.ink ? ST.onInk : ST.ink)
            .frame(maxWidth: .infinity, minHeight: ST.buttonHeight)
            .background(color, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// `.btn2` – Umriss in Tinte, Höhe 52, 15/800.
struct STSecondary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ST.button2)
            .foregroundStyle(ST.ink)
            .frame(maxWidth: .infinity, minHeight: ST.button2Height)
            .overlay(Capsule().strokeBorder(ST.ink, lineWidth: ST.hair))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Haken-Kreis (`.ck`).
struct STCheck: View {
    var on: Bool
    var size: CGFloat = ST.check
    var ring = ST.ink3

    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? ST.ink : ring, lineWidth: 2).background(Circle().fill(on ? ST.ink : .clear))
            if on { Image(systemName: "checkmark").font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(ST.onInk) }
        }
        .frame(width: size, height: size)
    }
}

/// Weiche Pille (`.soft`, `.ok`, `.warn`).
struct STSoft: View {
    let text: String
    var symbol: String?
    var tint = ST.blue1

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
            Text(text)
        }
        .font(ST.soft).foregroundStyle(ST.ink)
        .padding(.horizontal, 10).frame(height: ST.softPill)
        .background(tint, in: Capsule())
    }
}

/// Bilder der App für Erweiterungs-Ansichten (Topf-Lader, Hop3, Illustrationen). Die App setzt sie beim Start;
/// in den Erweiterungen bleiben sie leer (keine Ressourcen im Modul) und die Ansichten zeigen einen ruhigen Ersatz.
@MainActor public enum ShareArt {
    public static var potLoader: (() -> AnyView)?
    public static var hop: (() -> AnyView)?
    public static var ill: ((String) -> AnyView)?
}
