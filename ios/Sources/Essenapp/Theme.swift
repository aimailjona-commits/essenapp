import CoreText
import SwiftUI
import UIKit

/// Alle Werte aus docs/ui/redesign-v8.md (v8 „Tinte & Bogen“, E98). Views nutzen nur diese Tokens.
/// App ist fest hell, bis das Dunkel-Mockup v8 freigegeben ist (Phase 21.2).
enum Theme {
    enum C {
        // v8-Grundfarben (redesign-v8.md Abschnitt 2)
        static let bg = Color(hex: 0xF3EEE4)
        static let card = Color(hex: 0xFBF8F2)
        static let ink = Color(hex: 0x151515)
        static let ink2 = Color(hex: 0x7C776D)
        static let ink3 = Color(hex: 0xB9B3A7)
        static let line = Color(hex: 0xDCD5C7)
        static let blue = Color(hex: 0xAFC4F2)
        static let blue1 = Color(hex: 0xDCE5F8)
        static let blue3 = Color(hex: 0x7C9BE6)
        static let sage = Color(hex: 0xCFE3D2)
        static let rose = Color(hex: 0xF2CFC8)
        static let sand = Color(hex: 0xE7DCC5)
        static let warn = Color(hex: 0xF6E2B8)
        static let deal = Color(hex: 0xE0603F)
        static let navBar = Color.white  // Nav-Leiste mit Mulde
        static let onInk = Color.white
        static let scrim = ink.opacity(0.32)

        // Ältere Token-Namen, auf v8 abgebildet (fallen weg, sobald alle Screens umgebaut sind)
        static let surface = card
        static let cardTop = card
        static let text1 = ink, text2 = ink2, text3 = ink3
        static let action = ink
        static let onAction = onInk
        static let lime = blue  // „los“-Farbe → Pastellblau
        static let onLime = ink
        static let accent = ink
        static let accentSoft = blue1
        static let accentDeep = ink
        static let highlight = blue
        static let star = ink
        static let chipBorder = line
        static let chipText = ink2
        static let starEmpty = line
        static let paper = card
        static let success = Color(hex: 0x3F8F5A)
        static let successSoft = sage
        static let warning = Color(hex: 0xD9A23A)
        static let danger = deal
        static let tabInactive = ink3
        static let kcal = ink, protein = ink, carbs = ink, fat = ink
        static let kcalTint = rose, proteinTint = blue1, carbsTint = sage, fatTint = sand
        static let violet = blue1
        static let tomato = rose, sun = sand, lav = blue1, sky = blue, mint = sage, orange = warn, pink = rose
        static let day: [Color] = [blue1, sage, rose, sand, blue1, sage, rose]
        static let startSheet = bg
        static let bar = navBar
        static let barEdge = Color.clear
        static let tabActive = blue
        static let inkSheet = ink
        static let inkRaised = Color(hex: 0x2A2A2A)
        static let inkChip = Color(hex: 0x222222)
        static let inkChipLine = Color(hex: 0x333333)
        static let onInk2 = ink3
        static let onInk3 = ink3
        static let recipeFallback = blue1
        static let onPhoto2 = card
        static let imageBg = card
        static let heroDark = ink
        static let shimmer = card
        static let photoDim = Color.clear
        static let plate = Color.white  // Logos und Teller auf weißem Kreis
        static let bloom: [Color] = [blue, sage, rose, sand, blue1, warn, blue3]
        static let bloomOther = line
        static let listTints: [Color] = day
        // Nutri-Score A–E in den Originalfarben (49); Buchstabe weiß, auf C dunkel (`onBright`)
        static let nutri: [String: Color] = ["A": Color(hex: 0x038141), "B": Color(hex: 0x85BB2F), "C": Color(hex: 0xFECB02),
                                             "D": Color(hex: 0xEE8100), "E": Color(hex: 0xE63E11)]
        static let onBright = ink
        // Kochmodus (S18 v8): heller Grund wie alle Screens
        static let cookBg = bg
        static let cookText2 = ink2
        static let cookSurface = card
    }

    /// Farbe + Tönung + Emoji pro Kategorie (Angebote, Liste).
    struct Hue {
        let color: Color
        let tint: Color
        let emoji: String
    }

    static func hue(category: String) -> Hue {
        switch category {
        case "obst_gemuese": Hue(color: C.ink, tint: C.sage, emoji: "🥦")
        case "fleisch_fisch": Hue(color: C.ink, tint: C.rose, emoji: "🥩")
        case "kuehlung": Hue(color: C.ink, tint: C.blue1, emoji: "🧀")
        case "vorrat": Hue(color: C.ink, tint: C.sand, emoji: "🥫")
        case "getraenke": Hue(color: C.ink, tint: C.blue1, emoji: "🥤")
        case "drogerie": Hue(color: C.ink, tint: C.blue, emoji: "🧴")
        case "haushalt": Hue(color: C.ink, tint: C.rose, emoji: "🧽")
        default: Hue(color: C.ink, tint: C.card, emoji: "🛒")
        }
    }

    /// Formfarbe pro Laden aus der v8-Palette (keine Markenfarben, E18/E87).
    static func storeColor(_ chain: String) -> Color { Color(hex: storeHex(chain)) }

    /// Als Zahl für die Live-Aktivität (37), die `Color` nicht speichern kann.
    static func storeHex(_ chain: String) -> UInt32 {
        let fixed: [String: UInt32] = ["lidl": 0xE7DCC5, "rewe": 0xF2CFC8, "dm": 0xDCE5F8, "": 0xCFE3D2]
        if let hex = fixed[chain] { return hex }
        let palette: [UInt32] = [0xAFC4F2, 0xF6E2B8, 0xF2CFC8, 0xCFE3D2]
        let rest = Labels.chains.map(\.key).filter { fixed[$0] == nil }
        return palette[(rest.firstIndex(of: chain) ?? 0) % palette.count]
    }

    /// Schriften (redesign-v8.md Abschnitt 2): DM Serif Display (Titel), Manrope (Text), Inter Tight (große Zahlen).
    /// Feste Schnitte (ios/tools/make_fonts.py), Größen wachsen mit Dynamic Type über `relativeTo`.
    enum F {
        enum W { case medium, semibold, bold, extrabold }

        static func serif(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
            .custom("DMSerifDisplay-Regular", size: size, relativeTo: style)
        }

        static func text(_ size: CGFloat, _ weight: W = .semibold, relativeTo style: Font.TextStyle = .body) -> Font {
            let name = switch weight {
            case .medium: "ManropeV8-Medium"
            case .semibold: "ManropeV8-SemiBold"
            case .bold: "ManropeV8-Bold"
            case .extrabold: "ManropeV8-ExtraBold"
            }
            return .custom(name, size: size, relativeTo: style)
        }

        static func num(_ size: CGFloat, medium: Bool = false, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
            .custom(medium ? "InterTightV8-Medium" : "InterTightV8-SemiBold", size: size, relativeTo: style)
        }

        /// Laufweite der großen Zahlen (−0.05 em).
        static func numTracking(_ size: CGFloat) -> CGFloat { -0.05 * size }

        // v8-Stufen aus dem Mockup-CSS
        static let t1 = serif(34, relativeTo: .largeTitle)  // .t1
        static let t2 = serif(24, relativeTo: .title)  // .t2
        static let rowName = serif(19, relativeTo: .title3)  // .irow .nm
        static let small = text(15, .semibold, relativeTo: .subheadline)  // .small
        static let lbl = text(11, .extrabold, relativeTo: .caption2)  // .lbl (+0.08 em)
        static let sec2 = text(13, .extrabold, relativeTo: .footnote)  // .sec2 (+0.06 em)
        static let button = text(16, .extrabold, relativeTo: .headline)  // .btn
        static let button2 = text(15, .extrabold, relativeTo: .headline)  // .btn2
        static let chip = text(14, .bold, relativeTo: .subheadline)  // .chip
        static let pill = text(13, .bold, relativeTo: .footnote)  // .pill
        static let deal = text(11, .extrabold, relativeTo: .caption2)  // .deal
        static let soft = text(12, .extrabold, relativeTo: .caption)  // .soft
        static let toast = text(14, .bold, relativeTo: .subheadline)  // .toast

        // Ältere Namen, auf v8 abgebildet
        static let display = serif(46, relativeTo: .largeTitle)
        static func display(_ size: CGFloat) -> Font { serif(size, relativeTo: .largeTitle) }
        static func displayItalic(_ size: CGFloat = 46) -> Font { serif(size, relativeTo: .largeTitle) }
        static func cardTitle(_ size: CGFloat = 21) -> Font { serif(size, relativeTo: .title2) }
        static let sentence = serif(27)
        static let sentenceBold = serif(27)
        static func burst(_ size: CGFloat) -> Font { num(size, relativeTo: .headline) }
        static func mono(_ size: CGFloat = 13) -> Font { text(size, .bold, relativeTo: .footnote) }
        static func monoBold(_ size: CGFloat = 13) -> Font { text(size, .extrabold, relativeTo: .footnote) }
        static let displayLight = displayItalic()
        static let hero = serif(46, relativeTo: .largeTitle)
        static let section = t2
        static let title = t2
        static let titleLarge = t1
        static let headline = text(17, .extrabold, relativeTo: .headline)
        static let body = text(16, .semibold, relativeTo: .body)
        static let callout = text(15, .bold, relativeTo: .subheadline)
        static let caption = text(13, .semibold, relativeTo: .footnote)
        static let micro = lbl
        static let price = num(17, relativeTo: .callout)
        static let priceLarge = num(22, relativeTo: .title3)
        static let cookTitle = serif(30, relativeTo: .title)
        static let cookStep = text(19, .semibold, relativeTo: .title3)
        static let cookBody = text(19, .bold, relativeTo: .title3)
        static let cookTimer = num(22, relativeTo: .title3)
    }

    /// Radien: v8 nutzt fast nur Kapseln und Kreise; Sheet oben 36.
    enum R {
        static let chip: CGFloat = 999
        static let tile: CGFloat = 24
        static let offer: CGFloat = 56  // Lasche links
        static let rtile: CGFloat = 24
        static let card: CGFloat = 24
        static let day: CGFloat = 24
        static let sheet: CGFloat = 36
        static let skeleton: CGFloat = 12
    }

    /// Feste Größen (redesign-v8.md Abschnitt 2)
    enum S {
        static let hair: CGFloat = 1.5
        static let button: CGFloat = 56
        static let button2: CGFloat = 52
        static let field: CGFloat = 52
        static let chip: CGFloat = 36
        static let pill: CGFloat = 30
        static let dealPill: CGFloat = 22
        static let softPill: CGFloat = 24
        static let segment: CGFloat = 34
        static let close: CGFloat = 40
        static let check: CGFloat = 26
        static let row: CGFloat = 60
        static let rowCircle: CGFloat = 48
        static let rowImage: CGFloat = 40
        static let offerRow: CGFloat = 138
        static let offerTab = CGSize(width: 150, height: 112)
        static let switchSize = CGSize(width: 50, height: 30)
        static let stepper: CGFloat = 40
        static let stepperKnob: CGFloat = 30
        static let grip = CGSize(width: 40, height: 5)
        static let plateRing: CGFloat = 6
        static let bar: CGFloat = 8
        static let icon: CGFloat = 24
        static let iconStroke: CGFloat = 1.8
        static let nav: CGFloat = 120
        static let navT: CGFloat = 34  // Leisten-Oberkante
        static let navR: CGFloat = 38  // Mulden-Radius
        static let navActive: CGFloat = 58
        static let navTap: CGFloat = 44
        // Ältere Namen
        static let roundButton: CGFloat = 46
        static let roundButtonSmall: CGFloat = 40
        static let search: CGFloat = 52
        static let tabBar: CGFloat = 120
        static let tab: CGFloat = 44
        static let plus: CGFloat = 44
        static let totalBar: CGFloat = 72
        static let barSide: CGFloat = 18
        static let barBottom: CGFloat = 26
    }

    static let pagePadding: CGFloat = 24
    static let ctaAboveTabBar: CGFloat = 120  // fester Button auf Detailseiten sitzt über der Tab-Leiste
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.78)
}

extension Theme {
    /// Schriften aus Resources/fonts beim Start registrieren (kein UIAppFonts nötig, xtool).
    static func registerFonts() {
        let urls = (Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "fonts") ?? [])
        for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }
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
    /// Schatten v8: kaum genutzt; `soft` wie die Nav (y 6 / Blur 14 / 7 %), `float` wie das Telefon im Mockup.
    func softShadow() -> some View { shadow(color: Color(hex: 0x281E14).opacity(0.07), radius: 7, y: 6) }
    func floatShadow() -> some View { shadow(color: Color(hex: 0x281E14).opacity(0.14), radius: 30, y: 30) }
    /// Teller (`.plate`): y 14 / Blur 30 / 16 %.
    func plateShadow() -> some View { shadow(color: Color(hex: 0x281E14).opacity(0.16), radius: 15, y: 14) }

    /// Fläche mit Haarlinie (nur noch für Übergänge; v8 baut Zeilen statt Karten).
    func card(radius: CGFloat = Theme.R.card, fill: Color = Theme.C.card) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .strokeBorder(Theme.C.line, lineWidth: Theme.S.hair)
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
