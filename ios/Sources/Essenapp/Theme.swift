import CoreText
import SwiftUI
import UIKit

/// Alle Werte aus docs/ui/redesign-v3.md (v3 „Küchen-Pinnwand“, E87). Views nutzen nur diese Tokens.
enum Theme {
    /// Dynamische Farben: erster Wert hell, zweiter dunkel (v3, Mockup Teil 3, freigegeben 2026-11-03; Feature 68).
    enum C {
        static let bg = Color(0xF4F1EA, 0x121110)
        static let surface = Color(0xE9E5DC, 0x2A2825)
        static let card = Color(0xFFFFFF, 0x1D1C1A)
        static let cardTop = card  // Alias für ältere Stellen
        static let line = Color(light: UIColor.black.withAlphaComponent(0.07), dark: UIColor.white.withAlphaComponent(0.09))
        static let text1 = Color(0x111111, 0xF4F1EA)
        static let text2 = Color(0x7A766E, 0xA09B92)
        static let text3 = Color(0xB3AEA4, 0x6B675F)
        static let action = Color(0x111111, 0xF4F1EA)  // dunkel: Creme-Pille mit Tinten-Schrift
        static let onAction = Color(0xFFFFFF, 0x111111)
        static let lime = Color(hex: 0xDCEDA0)  // Aktionsfarbe „los“ (Mittel-Knopf, AccentButton, abgehakt, Fortschritt auf Dunkel)
        static let onLime = Color(hex: 0x111111)
        /// v3: Auswahl/Fortschritt auf hellem Grund = Tinte (Orange entfällt); auf dunklem Grund `lime` nehmen.
        static let accent = Color(0x111111, 0xF4F1EA)
        static let accentSoft = Color(hex: 0xDCEDA0)  // weiche Hervorhebung (gewählte Person, „gespart“-Pille)
        static let accentDeep = Color(hex: 0x111111)  // Schrift auf accentSoft (Limette bleibt auch dunkel hell)
        static let highlight = lime
        static let deal = Color(0xE8694A, 0xF07A5C)
        static let star = Color(hex: 0xE8B33A)
        static let chipBorder = Color(0xCFC9BD, 0x3A3733)
        static let chipText = Color(0x8A857B, 0xA09B92)  // inaktive Chips
        static let starEmpty = Color(0xDDD7CB, 0x3A3733)
        static let paper = Color(hex: 0xFFFDF7)  // Kassenbon bleibt auch dunkel Papier
        static let success = Color(0x1FA35C, 0x34C77B)
        static let successSoft = Color(0xDFF5E8, 0x12301F)
        static let warning = Color(hex: 0xF7B731)
        static let danger = Color(0xE5483B, 0xFF6B5E)
        static let tabInactive = Color(hex: 0x8C8A85)
        static let kcal = Color(hex: 0xFF8A3D)
        static let protein = Color(hex: 0xFF5A5F)
        static let carbs = Color(hex: 0x3DBE6B)
        static let fat = Color(hex: 0xF7B731)
        // Nährwert-Tönungen (NutrientStat/-Tile)
        static let kcalTint = Color(0xFFE7D6, 0x3A2621)
        static let proteinTint = Color(0xFFE0E1, 0x3A2230)
        static let carbsTint = Color(0xE4F5D9, 0x22301F)
        static let fatTint = Color(0xFFF1C9, 0x38301C)
        static let violet = Color(hex: 0xD5CDF0)  // Schnell-Aktion „Rezept anlegen“ (= Mi)
        // Pastell je Wochentag Mo…So (DayCard, Ordner, Kacheln); Schrift darauf immer text1
        static let tomato = Color(hex: 0xF2B9A8), sun = Color(hex: 0xF3DC9E), lav = Color(hex: 0xD5CDF0), sky = Color(hex: 0xBCD0F2)
        static let mint = Color(hex: 0xC3E3CF), orange = Color(hex: 0xF2CBA6), pink = Color(hex: 0xF0CADA)
        static let day: [Color] = [tomato, sun, lav, sky, mint, orange, pink]
        static let startSheet = Color(0xF4F1EA, 0x1D1C1A)  // Start: Sheet unter dem Tinten-Kopf (dunkel = card)
        static let bar = Color(0x111111, 0x000000)  // Tab-/Summen-Leiste (dunkel: Schwarz mit Kante)
        static let barEdge = Color(light: .clear, dark: UIColor.white.withAlphaComponent(0.08))
        static let tabActive = Color(0xFFFFFF, 0xDCEDA0)  // aktiver Tab: weiß, dunkel Limette
        // Dunkle Flächen (Start-Kopf, Kochmodus, Menü) – in beiden Modi gleich
        static let ink = Color(hex: 0x111111)
        static let inkSheet = Color(hex: 0x161616)
        static let inkRaised = Color(hex: 0x2A2A2A)
        static let inkChip = Color(hex: 0x222222)
        static let inkChipLine = Color(hex: 0x333333)
        static let onInk2 = Color(hex: 0x77736B)  // grauer Text auf Tinte
        static let onInk3 = Color(hex: 0x9A978F)  // Labels auf Tinte
        static let recipeFallback = Color(hex: 0x5C4038)  // Rezept-Kopf ohne Foto-Farbe
        static let onPhoto2 = Color(hex: 0xE3CFC5)
        // Flächen, die in beiden Modi dunkel bzw. hinter Fotos liegen
        static let imageBg = Color(0xF7F7F7, 0x2A2A2D)  // Produktbild-Fläche (Angebotskarte)
        static let heroDark = ink  // dunkler Kopf (Start, Angebotsdetail)
        static let scrim = Color(light: UIColor.black.withAlphaComponent(0.25), dark: UIColor.black.withAlphaComponent(0.55))
        static let shimmer = Color(light: UIColor(hex: 0xF6F3EE), dark: UIColor.white.withAlphaComponent(0.12))
        static let photoDim = Color(light: .clear, dark: UIColor.black.withAlphaComponent(0.12))  // Fotos im Dunkeln leicht abdunkeln
        static let plate = Color.white  // Logos und Teller bleiben auf weißem Plättchen (auch dunkel)
        // Blüten-Diagramm (ShareBloom): Blätter in Kartenfarben, „Sonstiges“ `bloomOther`
        static let bloom: [Color] = day
        static let bloomOther = Color(hex: 0xC9C3B6)
        static let listTints: [Color] = day
        // Nutri-Score A–E in den Originalfarben (49), in beiden Modi gleich; Buchstabe weiß, auf C dunkel (`onBright`)
        static let nutri: [String: Color] = ["A": Color(hex: 0x038141), "B": Color(hex: 0x85BB2F), "C": Color(hex: 0xFECB02),
                                             "D": Color(hex: 0xEE8100), "E": Color(hex: 0xE63E11)]
        static let onBright = Color(hex: 0x111111)
        // Kochmodus (S18): immer dunkler Grund, weiße Schrift
        static let cookBg = ink
        static let cookText2 = Color(hex: 0xC9C5BD)
        static let cookSurface = inkRaised
    }

    /// Farbe + Tönung + Emoji pro Kategorie (Angebote, Liste).
    struct Hue {
        let color: Color
        let tint: Color
        let emoji: String
    }

    static func hue(category: String) -> Hue {
        switch category {
        case "obst_gemuese": Hue(color: Color(hex: 0x3DBE6B), tint: Color(0xE4F5D9, 0x22301F), emoji: "🥦")
        case "fleisch_fisch": Hue(color: Color(hex: 0xFF6B4A), tint: Color(0xFFE3DB, 0x3A2621), emoji: "🥩")
        case "kuehlung": Hue(color: Color(hex: 0x3E9BFF), tint: Color(0xDFE9FF, 0x1F2838), emoji: "🧀")
        case "vorrat": Hue(color: Color(hex: 0xF7B731), tint: Color(0xFFF1C9, 0x38301C), emoji: "🥫")
        case "getraenke": Hue(color: Color(hex: 0x22B5C9), tint: Color(0xE9E5DC, 0x2A2825), emoji: "🥤")
        case "drogerie": Hue(color: Color(hex: 0x8E7CFF), tint: Color(0xECE6FF, 0x2A2638), emoji: "🧴")
        case "haushalt": Hue(color: Color(hex: 0xFF5DA2), tint: Color(0xFFE4EF, 0x3A2230), emoji: "🧽")
        default: Hue(color: Color(hex: 0x8A8F98), tint: Color(0xE9E5DC, 0x2A2825), emoji: "🛒")
        }
    }

    /// Ordner-/Punktfarbe pro Laden aus der v3-Palette (keine Markenfarben, E18/E87).
    static func storeColor(_ chain: String) -> Color { Color(hex: storeHex(chain)) }

    /// Als Zahl für die Live-Aktivität (37), die `Color` nicht speichern kann.
    static func storeHex(_ chain: String) -> UInt32 {
        let fixed: [String: UInt32] = ["lidl": 0xF3DC9E, "rewe": 0xF2B9A8, "dm": 0xD5CDF0, "": 0xC3E3CF]
        if let hex = fixed[chain] { return hex }
        let palette: [UInt32] = [0xBCD0F2, 0xF2CBA6, 0xF0CADA, 0xC3E3CF]
        let rest = Labels.chains.map(\.key).filter { fixed[$0] == nil }
        return palette[(rest.firstIndex(of: chain) ?? 0) % palette.count]
    }

    /// Schriften (redesign-v3.md Abschnitt 3). Fraunces/JetBrains Mono als feste Schnitte (ios/tools/make_fonts.py),
    /// Größen wachsen mit Dynamic Type über `relativeTo`. SF Pro über Textstile (nächster Stil zur v3-Größe).
    enum F {
        static let display = Font.custom("FrauncesV3-Display", size: 46, relativeTo: .largeTitle)
        static func display(_ size: CGFloat) -> Font { .custom("FrauncesV3-Display", size: size, relativeTo: .largeTitle) }
        static func displayItalic(_ size: CGFloat = 46) -> Font { .custom("FrauncesV3-Italic", size: size, relativeTo: .largeTitle) }
        static func cardTitle(_ size: CGFloat = 21) -> Font { .custom("FrauncesV3-Title", size: size, relativeTo: .title2) }
        static let sentence = Font.custom("FrauncesV3-TextItalic", size: 27, relativeTo: .title)
        static let sentenceBold = Font.custom("FrauncesV3-Bold", size: 27, relativeTo: .title)
        static func burst(_ size: CGFloat) -> Font { .custom("FrauncesV3-Black", size: size, relativeTo: .headline) }
        static func mono(_ size: CGFloat = 13) -> Font { .custom("JetBrainsMonoV3-Medium", size: size, relativeTo: .footnote) }
        static func monoBold(_ size: CGFloat = 13) -> Font { .custom("JetBrainsMonoV3-Bold", size: size, relativeTo: .footnote) }
        static let displayLight = displayItalic()
        static let hero = display(52)
        static let section = Font.system(.title2, weight: .heavy)  // 22/800 „Diese Woche“
        static let title = Font.system(.title2, weight: .black)  // Angebot 24/900
        static let titleLarge = Font.system(.largeTitle, weight: .black)  // Rezept-Kopf 34/900
        static let headline = Font.system(.headline, weight: .bold)
        static let body = Font.body
        static let callout = Font.system(.subheadline, weight: .bold)
        static let caption = Font.system(.footnote, weight: .medium)
        static let micro = Font.system(.caption2, weight: .heavy)
        static let price = Font.system(.callout, weight: .heavy).monospacedDigit()
        static let priceLarge = Font.system(.title3, weight: .heavy).monospacedDigit()
        static let cookTitle = Font.system(.title, weight: .black)  // „Schritt 2“ 30/900
        static let cookStep = Font.system(.title3, weight: .regular)  // 19 / 1.45
        static let cookBody = Font.system(.title3, weight: .semibold)
        static let cookTimer = Font.system(.title3, design: .rounded, weight: .bold)
    }

    enum R {
        static let chip: CGFloat = 16
        static let tile: CGFloat = 22
        static let offer: CGFloat = 26
        static let rtile: CGFloat = 28
        static let card: CGFloat = 30
        static let day: CGFloat = 34
        static let sheet: CGFloat = 40
    }

    /// Feste Größen (redesign-v3.md Abschnitt 4)
    enum S {
        static let roundButton: CGFloat = 46
        static let roundButtonSmall: CGFloat = 38
        static let button: CGFloat = 56
        static let chip: CGFloat = 42
        static let search: CGFloat = 54
        static let tabBar: CGFloat = 70
        static let tab: CGFloat = 52
        static let plus: CGFloat = 56
        static let totalBar: CGFloat = 72
        static let barSide: CGFloat = 18
        static let barBottom: CGFloat = 26
    }

    static let pagePadding: CGFloat = 20
    static let ctaAboveTabBar: CGFloat = 110  // fester Button auf Detailseiten sitzt über der Tab-Leiste
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
    /// Schatten v3: `soft` y 10 / Blur 28 / 8 %, `float` y 18 / Blur 40 / 22 %.
    func softShadow() -> some View { shadow(color: Color(hex: 0x111111).opacity(0.08), radius: 14, y: 10) }
    func floatShadow() -> some View { shadow(color: Color(hex: 0x111111).opacity(0.22), radius: 20, y: 18) }
    /// Teller/Foto-Sticker: y 12 / Blur 24 / 18 %.
    func plateShadow() -> some View { shadow(color: .black.opacity(0.18), radius: 12, y: 12) }

    /// Karte v3: `card` mit Haarlinie, ohne Schatten, Radius 30.
    func card(radius: CGFloat = Theme.R.card, fill: Color = Theme.C.card) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .strokeBorder(Theme.C.line, lineWidth: 1)
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
