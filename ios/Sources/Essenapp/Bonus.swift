import CoreImage
import CoreImage.CIFilterBuiltins
import PhotosUI
import SwiftUI
import Vision

// Phase 13 – Payback & Rewe Bonus (38), Rewe-Bonus-Aktionen (39), Drogerie-Coupons (59): Wallet, Kasse, Konten (E73).

// MARK: Modelle (= backend/app/schemas.py)

/// = CouponBadge am Listenartikel / Merklisten-Eintrag: „🎟 10fach“ → antippen = Kasse.
struct CouponBadgeDTO: Codable, Hashable {
    var id: Int
    var text: String
    var program: String
    var partner: String
}

/// = CouponOut.
struct CouponDTO: Codable, Identifiable, Hashable {
    var id: Int
    var partner: String
    var program: String  // payback | rewe_bonus | dm | rossmann | sonstige
    var chain: String
    var product: String
    var category: String
    var benefit: String
    var multiplier: Int?
    var bonusCents: Int?
    var percent: Int?
    var minSpendCents: Int?
    var validUntil: String?  // YYYY-MM-DD, nil = unbegrenzt
    var code: String
    var codeType: String  // "" | code128 | ean13 | ean8 | qr
    var source: String
    var badge: String
    var expired: Bool
    var daysLeft: Int?
}

/// = CouponIn (POST), CouponUpdate (PATCH) und CouponScanOut (Foto gelesen). Alle Felder werden gesendet: null = kein
/// Vorteil/Mindestumsatz/Ablauf.
struct CouponIn: Codable, Equatable {
    var partner = ""
    var program = "sonstige"
    var chain = ""
    var product = ""
    var category = ""
    var benefit = ""
    var multiplier: Int?
    var bonusCents: Int?
    var percent: Int?
    var minSpendCents: Int?
    var validUntil: String?
    var code: String?  // fehlt beim Foto-Ergebnis
    var codeType: String?
    var source: String?

    enum CodingKeys: String, CodingKey {
        case partner, program, chain, product, category, benefit, multiplier, bonusCents, percent, minSpendCents, validUntil, code, codeType, source
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(partner, forKey: .partner)
        try c.encode(program, forKey: .program)
        try c.encode(chain, forKey: .chain)
        try c.encode(product, forKey: .product)
        try c.encode(category, forKey: .category)
        try c.encode(benefit, forKey: .benefit)
        try c.encode(multiplier, forKey: .multiplier)
        try c.encode(bonusCents, forKey: .bonusCents)
        try c.encode(percent, forKey: .percent)
        try c.encode(minSpendCents, forKey: .minSpendCents)
        try c.encode(validUntil, forKey: .validUntil)
        try c.encode(code ?? "", forKey: .code)
        try c.encode(codeType ?? "", forKey: .codeType)
        try c.encode(source ?? "manuell", forKey: .source)
    }
}

extension CouponIn {
    init(_ c: CouponDTO) {
        self.init(partner: c.partner, program: c.program, chain: c.chain, product: c.product, category: c.category, benefit: c.benefit,
                  multiplier: c.multiplier, bonusCents: c.bonusCents, percent: c.percent, minSpendCents: c.minSpendCents,
                  validUntil: c.validUntil, code: c.code, codeType: c.codeType, source: c.source)
    }
}

/// = BonusAccountOut: „Payback: 1.240 °P (≈ 12,40 €)“ bzw. „Rewe Bonus: 8,50 €“.
struct BonusAccountDTO: Codable, Identifiable, Hashable {
    var program: String  // payback (°P) | rewe_bonus (Cent)
    var name: String
    var unit: String  // punkte | cent
    var balance: Int
    var valueCents: Int
    var earnedMonthCents: Int

    var id: String { program }
    var points: Bool { unit == "punkte" }
    var balanceText: String { points ? "\(num(Double(balance))) °P" : euro(balance) }
    func amountText(_ v: Int) -> String { points ? "\(num(Double(v))) °P" : euro(v) }
}

enum Coupons {
    static let programs = [("payback", "Payback"), ("rewe_bonus", "Rewe Bonus"), ("dm", "dm"), ("rossmann", "Rossmann"), ("sonstige", "Sonstige")]
    static func program(_ key: String) -> String { programs.first { p in p.0 == key }?.1 ?? key }
    static func emoji(_ program: String) -> String { ["payback": "🅿️", "rewe_bonus": "🎁", "dm": "🧴", "rossmann": "🧴"][program] ?? "🎟" }
    static let codeTypes = [("code128", "Code 128"), ("ean13", "EAN-13"), ("ean8", "EAN-8"), ("qr", "QR-Code")]

    /// „läuft heute ab“, „läuft morgen ab“, „läuft So ab“, „gültig bis 30.11.“, „abgelaufen“; nil = unbegrenzt.
    static func expiry(_ daysLeft: Int?, _ validUntil: String?) -> String? {
        guard let left = daysLeft else { return nil }
        switch left {
        case ..<0: return "abgelaufen"
        case 0: return "läuft heute ab"
        case 1: return "läuft morgen ab"
        case 2...6:
            guard let d = validUntil.flatMap({ s in try? Date(s, strategy: PantryDTO.day) }) else { return "läuft in \(left) Tagen ab" }
            return "läuft \(Labels.days[(Calendar.current.component(.weekday, from: d) + 5) % 7]) ab"
        default:
            let p = (validUntil ?? "").split(separator: "-").compactMap { s in Int(s) }
            return p.count == 3 ? "gültig bis \(p[2]).\(p[1])." : nil
        }
    }

    #if DEBUG
    static func selfTest() {
        let sunday = "2026-11-08"  // Sonntag
        assert(expiry(3, sunday) == "läuft So ab", expiry(3, sunday) ?? "nil")
        assert(expiry(0, sunday) == "läuft heute ab" && expiry(-1, sunday) == "abgelaufen" && expiry(nil, nil) == nil)
        assert(expiry(20, "2026-11-30") == "gültig bis 30.11.")
        var c = Demo.coupons[0]
        c.product = ""
        c.category = "vorrat"
        assert(c.subject == "Vorrat" && c.short == "Vorrat")
        c.category = ""
        assert(c.subject == "den ganzen Einkauf" && c.short == "Payback")
        Barcode.selfTest()
    }
    #endif
}

extension CouponDTO {
    /// „Payback“, „Rewe Bonus“, „dm“ – bei „Sonstige“ der Partner.
    var programName: String { program == "sonstige" ? (partner.isEmpty ? "Coupon" : partner) : Coupons.program(program) }
    /// Wofür: Produkt, sonst Kategorie, sonst der ganze Einkauf.
    var subject: String { !product.isEmpty ? product : category.isEmpty ? "den ganzen Einkauf" : Labels.categoryName(category) }
    /// Kurz für Leiste und Mitteilung („Coupon Kaffee“).
    var short: String { !product.isEmpty ? product : category.isEmpty ? programName : Labels.categoryName(category) }
    var expiryText: String? { Coupons.expiry(daysLeft, validUntil) }
    var soon: Bool { (daysLeft ?? 99) <= 2 && !expired }
    var title: String { benefit.isEmpty ? badge : benefit }
}

extension Labels {
    /// „obst_gemuese“ → „Obst & Gemüse“ (ohne Emoji), sonst „Sonstiges“.
    static func categoryName(_ key: String) -> String {
        categories.first { c in c.0 == key }.map { c in String(c.1.split(separator: " ").dropFirst().joined(separator: " ")) } ?? "Sonstiges"
    }
}

// MARK: Barcode

/// Barcode für die Kasse: Code128/QR per CoreImage, EAN-13/EAN-8 selbst gezeichnet (CoreImage hat keinen EAN-Generator).
enum Barcode {
    private static let l = ["0001101", "0011001", "0010011", "0111101", "0100011", "0110001", "0101111", "0111011", "0110111", "0001011"]
    private static let parity = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG", "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"]
    private static func r(_ d: Int) -> String { String(l[d].map { c in c == "0" ? "1" : "0" }) }
    private static func g(_ d: Int) -> String { String(r(d).reversed()) }

    /// EAN-8/13 mit gültiger Prüfziffer.
    static func valid(_ code: String) -> Bool {
        let d = code.compactMap(\.wholeNumberValue)
        guard d.count == code.count, [8, 13].contains(d.count) else { return false }
        let sum = d.dropLast().reversed().enumerated().reduce(0) { s, x in s + x.element * (x.offset % 2 == 0 ? 3 : 1) }
        return (10 - sum % 10) % 10 == d.last
    }

    /// Typ für einen eingetippten Code: gültige EAN, sonst Code128.
    static func guess(_ code: String) -> String {
        valid(code) ? (code.count == 13 ? "ean13" : "ean8") : "code128"
    }

    static func type(_ s: VNBarcodeSymbology) -> String {
        s == .qr ? "qr" : s == .ean13 ? "ean13" : s == .ean8 ? "ean8" : "code128"
    }

    /// Module (true = schwarz): EAN-13 = 95, EAN-8 = 67; nil bei ungültigem Code.
    static func ean(_ code: String) -> [Bool]? {
        guard valid(code) else { return nil }
        let d = code.compactMap(\.wholeNumberValue)
        var s = "101"
        if d.count == 13 {
            let p = Array(parity[d[0]])
            for i in 1...6 { s += p[i - 1] == "L" ? l[d[i]] : g(d[i]) }
            s += "01010"
            for i in 7...12 { s += r(d[i]) }
        } else {
            for i in 0...3 { s += l[d[i]] }
            s += "01010"
            for i in 4...7 { s += r(d[i]) }
        }
        return (s + "101").map { c in c == "1" }
    }

    /// Code128 bzw. QR als scharfes Bild; nil, wenn CoreImage den Inhalt nicht kodieren kann (z. B. Umlaute in Code128).
    static func image(_ code: String, qr: Bool) -> UIImage? {
        let output: CIImage?
        if qr {
            let f = CIFilter.qrCodeGenerator()
            f.message = Data(code.utf8)
            f.correctionLevel = "M"
            output = f.outputImage
        } else {
            guard let ascii = code.data(using: .ascii) else { return nil }
            let f = CIFilter.code128BarcodeGenerator()
            f.message = ascii
            f.quietSpace = 10
            output = f.outputImage
        }
        guard let out = output?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    #if DEBUG
    static func selfTest() {
        assert(valid("4006381333931") && valid("96385074") && !valid("4006381333932") && !valid("12345"))
        assert(ean("4006381333931")?.count == 95 && ean("96385074")?.count == 67 && ean("4006381333932") == nil)
        assert(r(0) == "1110010" && g(0) == "0100111", "EAN-Tabellen")
        // 5901234123457: linke Hälfte mit Parität LGGLLG (erste Ziffer 5)
        let bits = ean("5901234123457")!.map { b in b ? "1" : "0" }.joined()
        assert(bits.hasPrefix("101" + l[9] + g(0) + g(1) + l[2] + l[3] + g(4) + "01010"), "EAN-13-Parität")
        assert(guess("4006381333931") == "ean13" && guess("96385074") == "ean8" && guess("ABC-123") == "code128")
        assert(type(.qr) == "qr" && type(.code128) == "code128")
    }
    #endif
}

/// Barcode auf weißem Grund (auch im Dunkeln – Kassenscanner brauchen Kontrast), darunter der Code als Text.
struct BarcodeView: View {
    let code: String
    let type: String
    var height: CGFloat = 130

    var body: some View {
        VStack(spacing: 8) {
            if (type == "ean13" || type == "ean8"), let bars = Barcode.ean(code) {
                Canvas { g, size in
                    let m = max(1, (size.width / CGFloat(bars.count)).rounded(.down))  // ganze Pixel je Modul, sonst verschwimmen Balken
                    let x0 = ((size.width - m * CGFloat(bars.count)) / 2).rounded(.down)
                    for (i, on) in bars.enumerated() where on {
                        g.fill(Path(CGRect(x: x0 + CGFloat(i) * m, y: 0, width: m, height: size.height)), with: .color(.black))
                    }
                }
                .frame(height: height)
                .padding(.horizontal, 12)  // Ruhezone
            } else if let image = Barcode.image(code, qr: type == "qr") {
                if type == "qr" {
                    Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(width: height * 1.6, height: height * 1.6)
                } else {
                    Image(uiImage: image).interpolation(.none).resizable().frame(height: height)
                }
            }
            if type != "qr" {
                Text(code).font(Theme.F.text(15, .semibold)).tracking(2).foregroundStyle(Theme.C.ink)
                    .lineLimit(2).minimumScaleFactor(0.6).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement()
        .accessibilityLabel("Barcode \(code)")
    }
}

// MARK: Server

extension AppStore {
    func loadCoupons() async throws {
        coupons = demo ? Demo.coupons : try await api.request("GET", "/coupons")
    }

    /// Coupon-Leiste im Laden (38d): gültige Coupons dieser Kette.
    func storeCoupons(_ chain: String) async -> [CouponDTO] {
        if demo { return Demo.coupons.filter { c in c.chain == chain && !c.expired } }
        return (try? await api.request("GET", "/coupons?chain=\(chain)")) ?? []
    }

    /// Coupon-Foto → gelesene Felder (speichert nichts).
    func scanCoupon(_ jpeg: Data) async throws -> CouponIn {
        if demo { return Demo.couponScan }
        return try await api.upload("/coupons/scan", files: [jpeg], fields: [:], field: "file", timeout: 60) { _ in }
    }

    func saveCoupon(_ body: CouponIn, id: Int?) async -> Bool {
        do {
            if !demo {
                let _: CouponDTO = try await api.request(id == nil ? "POST" : "PATCH", id.map { i in "/coupons/\(i)" } ?? "/coupons", body: body)
                try? await loadCoupons()  // Reihenfolge (bald ablaufende oben) macht der Server
            }
            flash(id == nil ? "Coupon gespeichert" : "Gespeichert")
            return true
        } catch {
            flash("Nicht gespeichert: \(error.localizedDescription)")
            return false
        }
    }

    func deleteCoupon(_ c: CouponDTO) async {
        let before = coupons
        withAnimation(Theme.spring) { coupons.removeAll { x in x.id == c.id } }
        do {
            if !demo { try await api.send("DELETE", "/coupons/\(c.id)") }
            flash("Coupon gelöscht")
        } catch {
            coupons = before
            flash("Nicht gelöscht: \(error.localizedDescription)")
        }
    }

    func loadBonus() async throws {
        bonusAccounts = demo ? Demo.bonus : try await api.request("GET", "/bonus")
    }

    /// Plus/Minus (`delta`) oder Kontostand korrigieren (`set`); Payback in °P, Rewe Bonus in Cent.
    func updateBonus(_ program: String, delta: Int?, set: Int?) async -> Bool {
        struct Body: Encodable { var delta: Int?; var set: Int? }
        do {
            var a: BonusAccountDTO
            if demo {
                a = bonusAccounts.first { x in x.program == program } ?? Demo.bonus[0]
                a.balance = set ?? a.balance + (delta ?? 0)
                a.valueCents = a.balance
            } else {
                a = try await api.request("POST", "/bonus/\(program)", body: Body(delta: delta, set: set))
            }
            if let i = bonusAccounts.firstIndex(where: { x in x.program == program }) {
                withAnimation(Theme.spring) { bonusAccounts[i] = a }
            }
            flash("\(a.name): \(a.balanceText)")
            return true
        } catch APIError.http(422) {
            flash("Kontostand darf nicht negativ werden")
        } catch {
            flash("Nicht gespeichert: \(error.localizedDescription)")
        }
        return false
    }
}

// MARK: Bausteine

/// Partner im Kreis (`.d-row .c` / `.d-p`): Payback und Programme ohne Laden als Serif-Buchstabe auf Pastellblau,
/// sonst echtes Laden-Logo im Pastell-Kreis.
struct CouponLogo: View {
    let chain: String
    let program: String
    var name = ""
    var size: CGFloat = Theme.S.rowCircle

    var body: some View {
        if program == "payback" || chain.isEmpty {
            Text(program == "payback" ? "P" : String((name.isEmpty ? Coupons.program(program) : name).prefix(1)).uppercased())
                .font(Theme.F.serif(size * 0.5))
                .foregroundStyle(Theme.C.ink)
                .frame(width: size, height: size)
                .background(Theme.C.blue1, in: Circle())
                .accessibilityHidden(true)
        } else {
            StoreCircle(chain: chain, size: size)
        }
    }
}

/// Weiche Pille mit eigener Text-Farbe bzw. nur Umriss (`.soft` mit `style`): „läuft So ab“, „ziemlich“.
struct SoftTag: View {
    let text: String
    var icon: Icon8?
    var tint: Color? = Theme.C.blue1  // nil = nur Haarlinie
    var color = Theme.C.ink

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Icon(icon, size: 12) }
            Text(text)
        }
        .font(Theme.F.soft)
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .frame(height: Theme.S.softPill)
        .background(tint ?? .clear, in: Capsule())
        .overlay { if tint == nil { Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
    }
}

/// Coupon am Artikel / Merklisten-Eintrag (`.soft` mit Barcode „10fach“); antippen = Kassen-Vollbild.
struct CouponTag: View {
    @Environment(AppStore.self) private var store
    let coupon: CouponBadgeDTO

    var body: some View {
        Button { store.checkoutCoupon = coupon.id } label: {
            SoftTag(text: coupon.text.replacingOccurrences(of: "🎟", with: "").trimmingCharacters(in: .whitespaces), icon: .barcode)
        }
        .buttonStyle(PressableStyle())
        .padding(.vertical, 10).contentShape(Rectangle()).padding(.vertical, -10)  // Tap-Fläche 44 pt ohne größere Zeile
        .accessibilityLabel("Coupon \(coupon.partner.isEmpty ? Coupons.program(coupon.program) : coupon.partner) an der Kasse zeigen")
    }
}

/// Coupon-Zeile (`.d-row`): Partner im Kreis, Vorteil, „Programm · Produkt · Ablauf“; rechts Ablauf-Hinweis (bald) oder Code-Symbol.
struct CouponRow: View {
    let coupon: CouponDTO

    private var sub: String {
        let until = (coupon.validUntil ?? "").split(separator: "-").compactMap { s in Int(s) }
        let parts: [String?] = [
            coupon.programName,
            coupon.product.isEmpty && coupon.category.isEmpty ? nil : coupon.subject,
            coupon.minSpendCents.map { m in "ab \(euro(m))" },
            coupon.expired ? "abgelaufen" : coupon.soon || until.count != 3 ? nil : "bis \(until[2]).\(until[1]).",
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 14) {
            CouponLogo(chain: coupon.chain, program: coupon.program, name: coupon.programName)
            VStack(alignment: .leading, spacing: 0) {
                Text(coupon.title).font(Theme.F.text(16, .extrabold)).lineLimit(1)
                Text(sub).font(Theme.F.text(12)).foregroundStyle(Theme.C.ink2).lineLimit(1)
            }
            Spacer(minLength: 8)
            if coupon.soon, let e = coupon.expiryText {
                SoftTag(text: e, tint: Theme.C.rose, color: Theme.C.deal)
            } else if !coupon.expired {
                Icon(coupon.code.isEmpty ? .chev : coupon.codeType == "qr" ? .qr : .barcode)
            }
        }
        .foregroundStyle(coupon.expired ? Theme.C.ink3 : Theme.C.ink)
        .opacity(coupon.expired ? 0.6 : 1)
        .padding(.vertical, 7)
        .overlay(alignment: .top) { Hairline() }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: S31 Coupons (Wallet)

/// Einkauf › „Coupons“ (d.html S31): Bonus-Konten als große Zahlen, Coupons als Zeilen, Abgelaufene in einer Zusammenfassung.
struct CouponWalletView: View {
    @Environment(AppStore.self) private var store
    @Binding var page: Int
    @State private var loaded = false
    @State private var error: String?
    @State private var adding = false
    @State private var editing: CouponDTO?
    @State private var showExpired = false
    @State private var account: BonusAccountDTO? = Demo.screen == "bonus" ? Demo.bonus[0] : nil

    // Mockup-Lage (S31): Blatt oben rechts mit Tasche
    private enum M {
        static let leaf = CGSize(width: 126, height: 210), leafRadius: CGFloat = 100
        static let bag: CGFloat = 104, bagRight: CGFloat = 10, bagTop: CGFloat = 62
    }

    var body: some View {
        let active = store.coupons.filter { c in !c.expired }
        let expired = store.coupons.filter(\.expired)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ShopTabs(page: $page)
                Text("\(active.count) gültig").font(Theme.F.small).foregroundStyle(Theme.C.ink2).padding(.top, 16)
                HStack(spacing: 14) {
                    Text("Coupons").font(Theme.F.t1).accessibilityAddTraits(.isHeader)
                    CircleButton(icon: .plus, size: 44, filled: true, label: "Coupon hinzufügen") { adding = true }
                }
                if !store.bonusAccounts.isEmpty {
                    VStack(spacing: 10) { ForEach(store.bonusAccounts) { a in bonusStat(a) } }.padding(.top, 22)
                }
                if store.coupons.isEmpty {
                    if !loaded {
                        VStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in Skeleton8(height: 54) } }.padding(.top, 28)
                    } else if let error {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Coupons nicht geladen").font(Theme.F.t2)
                            Text(error).font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                            OutlineButton(title: "Erneut versuchen", icon: .refresh) { Task { await load() } }.padding(.top, 8)
                        }
                        .padding(.top, 28)
                    } else {
                        VStack(spacing: 8) {  // ohne Mockup: Leer-Zustand mit Zeichnung
                            Ill("bag").frame(width: 140, height: 140)
                            Text("Noch keine Coupons").font(Theme.F.t2)
                            Text("Fotografiere Payback-, Rewe- oder dm-Coupons – an der Kasse zeigst du hier den Barcode.")
                                .font(Theme.F.small).foregroundStyle(Theme.C.ink2).multilineTextAlignment(.center)
                            PrimaryButton(title: "Coupon hinzufügen", icon: .plus) { adding = true }.padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(active.enumerated()), id: \.element.id) { i, c in row(c).appear(delay: Double(i) * 0.04) }
                    if !expired.isEmpty {
                        Button { withAnimation(Theme.spring) { showExpired.toggle() } } label: {
                            HStack(spacing: 14) {
                                Icon(.clock).frame(width: Theme.S.rowCircle, height: Theme.S.rowCircle)
                                    .overlay(Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
                                Text("Abgelaufen").font(Theme.F.text(16, .bold))
                                Spacer()
                                Text(expired.count == 1 ? "1 Coupon" : "\(expired.count) Coupons").font(Theme.F.text(13))
                                Icon(.chev, size: 18).rotationEffect(.degrees(showExpired ? 90 : 0))
                            }
                            .foregroundStyle(Theme.C.ink3)
                            .padding(.vertical, 7)
                            .overlay(alignment: .top) { Hairline() }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if showExpired { ForEach(expired) { c in row(c) } }
                    }
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, Theme.S.nav)
            .animation(Theme.spring, value: store.coupons)
        }
        .backdrop8 {
            Color.clear
                .pinned(right: M.bagRight, top: M.bagTop) { Ill("bag").frame(width: M.bag) }
                .edgeForm(.leaf(M.leafRadius), Theme.C.blue1, width: M.leaf.width, height: M.leaf.height, right: 0, top: 0)
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $adding) { CouponAddSheet() }
        .sheet(item: $editing) { c in CouponAddSheet(editing: c) }
        .sheet(item: $account) { a in BonusSheet(account: a) }
    }

    private func row(_ c: CouponDTO) -> some View {
        Button { store.checkoutCoupon = c.id } label: { CouponRow(coupon: c) }
            .buttonStyle(PressableStyle())
            .contextMenu {
                Button("An der Kasse zeigen", systemImage: "barcode") { store.checkoutCoupon = c.id }
                Button("Bearbeiten", systemImage: "pencil") { editing = c }
                Button("Löschen", systemImage: "trash", role: .destructive) { Task { await store.deleteCoupon(c) } }
            }
            .accessibilityAction(named: "Bearbeiten") { editing = c }
    }

    /// „Payback ± 1.240 °P ≈ 12,40 €“ als große Zahl → Plus/Minus-Sheet.
    private func bonusStat(_ a: BonusAccountDTO) -> some View {
        Button { account = a } label: {
            VStack(alignment: .trailing, spacing: 4) {
                StatNumber(label: "\(a.name) ±", value: a.balanceText, size: 40)
                if a.points {
                    Text("≈ \(euro(a.valueCents))").font(Theme.F.text(12)).foregroundStyle(Theme.C.ink2)
                } else if a.earnedMonthCents > 0 {
                    Text("+\(euro(a.earnedMonthCents)) im Monat").font(Theme.F.text(12)).foregroundStyle(Theme.C.success)
                }
            }
            .foregroundStyle(Theme.C.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(a.name): \(a.balanceText), Punkte oder Guthaben ändern")
    }

    private func load() async {
        do {
            try await store.loadCoupons()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        try? await store.loadBonus()
        loaded = true
    }
}

// MARK: S31b Kasse

/// Kassen-Vollbild (d.html S31b): weißes Plättchen auf großem Kreis, Vorteil riesig, Barcode, Ablauf, Mindestumsatz.
struct CouponCheckoutView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: Int
    @State private var failed = false
    @State private var editing: CouponDTO?
    @State private var brightness: CGFloat?

    // Mockup-Lage (S31b): Kreis 510 unten
    private enum M { static let blob: CGFloat = 510, blobLeft: CGFloat = -60, blobTop: CGFloat = 440, plateTop: CGFloat = 34 }

    private var screen: UIScreen? { UIApplication.shared.connectedScenes.compactMap { s in (s as? UIWindowScene)?.screen }.first }

    var body: some View {
        let coupon = store.coupons.first { c in c.id == id }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("An der Kasse zeigen").font(Theme.F.t2)
                    Spacer()
                    CloseButton { dismiss() }
                }
                Group {
                    if let c = coupon {
                        plate(c).appear()
                        if c.code.isEmpty {
                            VStack(spacing: 12) {
                                Text("Kein Barcode gespeichert – zeig den Coupon in der \(c.programName)-App oder scanne ihn hier ein.")
                                    .font(Theme.F.small).foregroundStyle(Theme.C.ink2).multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                OutlineButton(title: "Barcode ergänzen", icon: .barcode) { editing = c }
                            }
                            .padding(.top, 20)
                        }
                    } else if failed {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Coupon nicht gefunden").font(Theme.F.t2)
                            Text("Er wurde vielleicht gelöscht.").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                        }
                    } else {
                        Skeleton8(height: 360)
                    }
                }
                .padding(.top, M.plateTop)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .backdrop8 { Color.clear.edgeForm(.circle, Theme.C.blue1, width: M.blob, height: M.blob, left: M.blobLeft, top: M.blobTop) }
        .task {
            guard coupon == nil else { return }
            try? await store.loadCoupons()
            failed = !store.coupons.contains { c in c.id == id }
        }
        .onAppear {
            guard !store.demo, let screen else { return }
            brightness = screen.brightness
            screen.brightness = 1  // Kassenscanner lesen hell besser
        }
        .onDisappear { if let brightness { screen?.brightness = brightness } }
        .sheet(item: $editing) { c in CouponAddSheet(editing: c) }
    }

    private static func big(_ c: CouponDTO) -> (String, String) {
        if let m = c.multiplier { return ("\(m)fach", "Punkte für \(c.subject)") }
        if let b = c.bonusCents { return (euro(b), "Bonus für \(c.subject)") }
        if let p = c.percent { return ("\(p) %", "Rabatt auf \(c.subject)") }
        return (c.title, "für \(c.subject)")
    }

    /// Immer weiß (Kontrast für den Scanner).
    private func plate(_ c: CouponDTO) -> some View {
        let big = Self.big(c)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                CouponLogo(chain: c.chain, program: c.program, name: c.programName, size: 44)
                VStack(alignment: .leading, spacing: 0) {
                    Text(c.partner.isEmpty || c.program != "sonstige" ? c.programName : c.partner).font(Theme.F.text(16, .extrabold))
                    Text(c.chain.isEmpty || c.chain == c.program ? "Coupon" : "bei \(Labels.chain(c.chain)) · Coupon")
                        .font(Theme.F.text(12)).foregroundStyle(Theme.C.ink2)
                }
            }
            BigNumber(big.0, size: 80).padding(.top, 24)
            Text(big.1).font(Theme.F.text(17, .bold)).padding(.top, 8)
            if !c.code.isEmpty { BarcodeView(code: c.code, type: c.codeType, height: 120).padding(.top, 26) }
            HStack(spacing: 8) {
                if let e = c.expiryText {
                    if c.soon || c.expired { SoftTag(text: e, tint: Theme.C.rose, color: Theme.C.deal) } else { SoftTag(text: e, tint: nil) }
                }
                if let m = c.minSpendCents { SoftTag(text: "ab \(euro(m)) Einkauf", tint: nil) }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
        }
        .foregroundStyle(Theme.C.ink)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {  // Schatten nur am Plättchen, nicht an Barcode und Text
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.C.plate)
                .shadow(color: Theme.C.ink.opacity(0.16), radius: 25, y: 24)
        }
    }
}

// MARK: Coupon erfassen

/// Formular-Zustand (Zahlen als Text) ↔ CouponIn.
struct CouponForm: Equatable {
    var c: CouponIn
    var kind = ""  // "" (nur Text) | fach | bonus | prozent
    var value = ""
    var minSpend = ""
    var expires = false
    var until = Date.now.addingTimeInterval(7 * 86400)

    init(_ c: CouponIn = CouponIn()) {
        self.c = c
        if let m = c.multiplier { kind = "fach"; value = "\(m)" }
        else if let b = c.bonusCents { kind = "bonus"; value = num(Double(b) / 100, 2...2) }
        else if let p = c.percent { kind = "prozent"; value = "\(p)" }
        minSpend = c.minSpendCents.map { m in num(Double(m) / 100, 2...2) } ?? ""
        if let d = c.validUntil.flatMap({ s in try? Date(s, strategy: PantryDTO.day) }) { expires = true; until = d }
    }

    private static func number(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")) }

    /// Zahl im erlaubten Bereich (Backend: Xfach 1–100, Bonus 1 ct–1.000 €, Prozent 1–100), sonst nil.
    private var amount: Int? {
        guard let n = Self.number(value) else { return nil }
        let v = kind == "bonus" ? Int((n * 100).rounded()) : Int(n.rounded())
        return (kind == "bonus" ? 1...100_000 : 1...100).contains(v) ? v : nil
    }

    var valid: Bool {
        (!c.partner.trimmingCharacters(in: .whitespaces).isEmpty || c.program != "sonstige") && (kind.isEmpty || amount != nil)
            && (minSpend.isEmpty || (Self.number(minSpend) ?? 0) > 0)
    }

    var body: CouponIn {
        var out = c
        out.partner = String(c.partner.trimmingCharacters(in: .whitespaces).prefix(50))
        out.product = String(c.product.trimmingCharacters(in: .whitespaces).prefix(100))
        out.multiplier = kind == "fach" ? amount : nil
        out.bonusCents = kind == "bonus" ? amount : nil
        out.percent = kind == "prozent" ? amount : nil
        out.minSpendCents = Self.number(minSpend).map { e in Int((e * 100).rounded()) }.flatMap { m in m > 0 ? m : nil }
        out.validUntil = expires ? until.formatted(PantryDTO.day) : nil
        // Vorteil-Text: bei Xfach/Bonus/Rabatt aus der Zahl (S31c hat kein Textfeld mehr), sonst der eingegebene Text
        var benefit = kind.isEmpty ? c.benefit.trimmingCharacters(in: .whitespaces) : ""
        if benefit.isEmpty, let a = amount {  // „10fach Punkte“, „0,50 € Bonus“, „20 % Rabatt“
            benefit = kind == "fach" ? "\(a)fach Punkte" : kind == "bonus" ? "\(euro(a)) Bonus" : "\(a) % Rabatt"
        }
        out.benefit = String(benefit.prefix(100))
        let code = (c.code ?? "").trimmingCharacters(in: .whitespaces)
        out.code = String(code.prefix(200))
        out.codeType = code.isEmpty ? "" : (c.codeType ?? "").isEmpty ? Barcode.guess(code) : c.codeType
        return out
    }
}

/// Coupon hinzufügen (S31c): Foto (KI liest), Barcode (VisionKit) oder manuell → Prüfen/Bearbeiten → Speichern.
struct CouponAddSheet: View {
    enum Stage { case choose, reading, failed, form }
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let editing: CouponDTO?
    @State private var stage: Stage
    @State private var form: CouponForm
    @State private var camera = false
    @State private var pick: PhotosPickerItem?
    @State private var scanner = false
    @State private var readError = ""
    @State private var saving = false
    @State private var height: CGFloat = 360
    @State private var open: String?  // aufgeklappte Zeile: datum | minimum | barcode

    init(editing: CouponDTO? = nil) {
        self.editing = editing
        let demo = Demo.screen == "couponadd"
        _stage = State(initialValue: editing != nil || demo ? .form : .choose)
        _form = State(initialValue: CouponForm(editing.map(CouponIn.init) ?? (demo ? Demo.couponScan : CouponIn())))
    }

    private var title: String {
        editing != nil ? "Coupon bearbeiten" : stage == .form ? (form.c.source == "foto" ? "Coupon prüfen" : "Neuer Coupon") : "Coupon hinzufügen"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(Theme.F.t2)
                        if stage == .form, form.c.source == "foto", editing == nil {
                            Text("Aus dem Foto gelesen – bitte kurz prüfen.").font(Theme.F.text(13)).foregroundStyle(Theme.C.ink2)
                        }
                    }
                    Spacer()
                    CloseButton { dismiss() }
                }
                switch stage {
                case .choose: choosePage.padding(.top, 16)
                case .reading:
                    VStack(spacing: 14) {
                        Hop3(names: ["tomato", "bag", "basil"]).frame(height: 60)
                        Text("Coupon wird gelesen …").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                case .failed:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Das hat nicht geklappt").font(Theme.F.t2)
                        Text(readError).font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                        PrimaryButton(title: "Anderes Foto") { withAnimation(Theme.spring) { stage = .choose } }.padding(.top, 8)
                        OutlineButton(title: "Manuell eingeben") { withAnimation(Theme.spring) { stage = .form } }
                    }
                    .padding(.top, 20)
                case .form: formPage
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 40)
            .animation(Theme.spring, value: stage)
            .onGeometryChange(for: CGFloat.self) { g in g.size.height } action: { h in height = h }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.immediately)
        .presentationDetents(stage == .form ? [.large] : [.height(height + 33)])
        .sheet8()
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { image in
                camera = false
                if let image { read(image) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { read(image) }
                pick = nil
            }
        }
        .fullScreenCover(isPresented: $scanner) {
            BarcodeScanView(coupon: { code, type in
                form.c.code = code
                form.c.codeType = type
                if form.c.source == nil || form.c.source == "manuell" { form.c.source = "barcode" }
                withAnimation(Theme.spring) { stage = .form }
            })
        }
    }

    /// Drei Wege als `.irow` (68 hoch) mit Farb-Kreis.
    private var choosePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            option(.cam, Theme.C.blue, "Coupon fotografieren") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true } else { store.flash("Keine Kamera – wähle ein Foto aus") }
            }
            PhotosPicker(selection: $pick, matching: .images) {
                HStack(spacing: 6) {
                    Icon(.photo, size: 16)
                    Text("Foto aus der Mediathek")
                }
                .font(Theme.F.text(13, .bold, relativeTo: .footnote))
                .foregroundStyle(Theme.C.ink2)
                .padding(.horizontal, 15)
                .frame(height: 32)
                .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
            }
            .tapArea(6)  // außerhalb des Labels: PhotosPicker-Label ist nonisolated
            .padding(.leading, 62).padding(.bottom, 14)
            option(.barcode, Theme.C.sand, "Barcode scannen") { scanner = true }
            option(.edit, Theme.C.sage, "Manuell eingeben") {
                form.c.source = "manuell"
                withAnimation(Theme.spring) { stage = .form }
            }
        }
    }

    private func option(_ icon: Icon8, _ tint: Color, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Icon(icon).frame(width: Theme.S.rowCircle, height: Theme.S.rowCircle).background(tint, in: Circle())
                Text(title).font(Theme.F.rowName)
                Spacer()
                Icon(.chev).foregroundStyle(Theme.C.ink3)
            }
            .foregroundStyle(Theme.C.ink)
            .frame(minHeight: 68)
            .overlay(alignment: .top) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    /// Zusammenfassungs-Zeile (`.row.between.hr`) mit Chevron, klappt Inhalt auf.
    private func summary(_ key: String, _ title: String, sub: String? = nil, value: String? = nil, minHeight: CGFloat = 60) -> some View {
        Button { withAnimation(Theme.spring) { open = open == key ? nil : key } } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(Theme.F.text(16, .bold))
                    if let sub { Text(sub).font(Theme.F.text(12)).foregroundStyle(Theme.C.ink2) }
                }
                Spacer()
                if let value { Text(value).foregroundStyle(Theme.C.ink2) }
                Icon(.chev, size: 18).foregroundStyle(Theme.C.ink3).rotationEffect(.degrees(open == key ? 90 : 0))
            }
            .foregroundStyle(Theme.C.ink)
            .frame(minHeight: minHeight)
            .overlay(alignment: .top) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var formPage: some View {
        let household = Labels.chains.filter { c in store.household?.stores.contains { s in s.chain == c.key && s.enabled } ?? true }
        let code = form.c.code ?? ""
        let codeType = (form.c.codeType ?? "").isEmpty ? Barcode.guess(code) : form.c.codeType ?? ""
        // Gruppe 1: Partner und Laden
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Coupons.programs, id: \.0) { p in
                    Chip8(title: p.1, on: form.c.program == p.0) {
                        form.c.program = p.0
                        let known = ["rewe_bonus": ("REWE", "rewe"), "dm": ("dm", "dm"), "rossmann": ("Rossmann", "rossmann")][p.0]
                        if let known, form.c.partner.isEmpty { form.c.partner = known.0; form.c.chain = known.1 }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
        }
        .padding(.horizontal, -Theme.pagePadding)
        .padding(.top, 24)
        if form.c.program == "sonstige" {
            FieldBox { TextField("Partner, z. B. Aral", text: $form.c.partner) }.padding(.top, 10)
        }
        Menu {
            Picker("Laden", selection: $form.c.chain) {
                Text("Kein bestimmter").tag("")
                ForEach(household, id: \.key) { c in Text(c.name).tag(c.key) }
            }
        } label: {
            HStack(spacing: 2) {
                Text("Laden").font(Theme.F.text(16, .bold)).foregroundStyle(Theme.C.ink)
                Spacer()
                Text(form.c.chain.isEmpty ? "Kein bestimmter" : Labels.chain(form.c.chain)).foregroundStyle(Theme.C.ink2)
                Icon(.chev, size: 18).foregroundStyle(Theme.C.ink3)
            }
            .frame(minHeight: 48)
            .overlay(alignment: .top) { Hairline() }
            .contentShape(Rectangle())
        }
        .padding(.top, 12)
        .accessibilityHint("Im passenden Laden erinnern wir an den Coupon und zeigen ihn in der Liste.")

        // Gruppe 2: Vorteil
        Segmented8(options: [("fach", "Xfach"), ("bonus", "€ Bonus"), ("prozent", "% Rabatt"), ("", "Sonstiges")], selection: $form.kind)
            .padding(.top, 28)
        if form.kind.isEmpty {
            FieldBox { TextField("Vorteil, z. B. Gratis-Kaffee", text: $form.c.benefit) }.padding(.top, 10)
        }
        HStack(spacing: 8) {
            if !form.kind.isEmpty {
                FieldBox {
                    TextField(form.kind == "fach" ? "10" : form.kind == "bonus" ? "0,50" : "20", text: $form.value)
                        .keyboardType(form.kind == "bonus" ? .decimalPad : .numberPad)
                }
                .frame(width: 82)
            }
            FieldBox { TextField("Produkt (leer = ganzer Einkauf)", text: $form.c.product) }
        }
        .padding(.top, 10)

        // Gruppe 3: Gültigkeit, Mindestumsatz, Barcode
        VStack(alignment: .leading, spacing: 0) {
            if form.c.product.trimmingCharacters(in: .whitespaces).isEmpty {
                Menu {
                    Picker("Kategorie", selection: $form.c.category) {
                        Text("Keine").tag("")
                        ForEach(Labels.categories, id: \.0) { c in Text(Labels.categoryName(c.0)).tag(c.0) }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text("Kategorie").font(Theme.F.text(16, .bold)).foregroundStyle(Theme.C.ink)
                        Spacer()
                        Text(form.c.category.isEmpty ? "Keine" : Labels.categoryName(form.c.category)).foregroundStyle(Theme.C.ink2)
                        Icon(.chev, size: 18).foregroundStyle(Theme.C.ink3)
                    }
                    .frame(minHeight: 52)
                    .overlay(alignment: .top) { Hairline() }
                    .contentShape(Rectangle())
                }
            }
            HStack {
                Button {
                    if form.expires { withAnimation(Theme.spring) { open = open == "datum" ? nil : "datum" } }
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(form.expires ? "Gültig bis \(PantryDTO.dayText(form.until))" : "Ohne Ablaufdatum").font(Theme.F.text(16, .bold))
                        if form.expires { Text("Erinnerung 2 Tage vorher").font(Theme.F.text(12)).foregroundStyle(Theme.C.ink2) }
                    }
                    .foregroundStyle(Theme.C.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Toggle(isOn: $form.expires.animation(Theme.spring)) { EmptyView() }.toggleStyle(.v8).fixedSize()
                    .accessibilityLabel("Gültig bis")
            }
            .frame(minHeight: 60)
            .overlay(alignment: .top) { Hairline() }
            if form.expires && open == "datum" {
                DatePicker("Gültig bis", selection: $form.until, displayedComponents: .date).datePickerStyle(.graphical).tint(Theme.C.ink)
            }
            summary("minimum", "Mindestumsatz", value: form.minSpend.isEmpty ? "keiner" : "\(form.minSpend) €", minHeight: 52)
            if open == "minimum" {
                FieldBox {
                    TextField("z. B. 20,00", text: $form.minSpend).keyboardType(.decimalPad)
                    Text("€").foregroundStyle(Theme.C.ink2)
                }
                .padding(.bottom, 10)
            }
            summary("barcode", "Barcode", sub: code.isEmpty ? "Noch keiner" : "\(Coupons.codeTypes.first { t in t.0 == codeType }?.1 ?? codeType) · \(code)")
            if open == "barcode" {
                VStack(spacing: 10) {
                    if !code.isEmpty {
                        BarcodeView(code: code, type: codeType, height: 70)
                            .padding(12)
                            .background(Theme.C.plate, in: RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
                        Segmented8(options: Coupons.codeTypes, selection: Binding(get: { codeType }, set: { t in form.c.codeType = t }))
                    }
                    FieldBox {
                        TextField("Code eintippen (optional)", text: Binding(get: { form.c.code ?? "" }, set: { v in form.c.code = v; form.c.codeType = nil }))
                            .keyboardType(.asciiCapable).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    OutlineButton(title: code.isEmpty ? "Barcode scannen" : "Neu scannen", icon: .barcode) { scanner = true }
                }
                .padding(.bottom, 10)
            }
        }
        .padding(.top, 28)
        PrimaryButton(title: saving ? "Speichere …" : "Speichern", disabled: !form.valid || saving, action: save).padding(.top, 24)
        if let c = editing {
            Button("Coupon löschen", role: .destructive) { Task { await store.deleteCoupon(c); dismiss() } }
                .font(Theme.F.button2).foregroundStyle(Theme.C.deal)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.top, 8)
        }
    }

    /// Foto → JPEG (≤ 5 MB, Backend-Grenze) → KI liest die Felder.
    private func read(_ image: UIImage) {
        withAnimation(Theme.spring) { stage = .reading }
        Task {
            do {
                guard let jpeg = image.jpeg(maxBytes: 5_000_000, maxSide: 2000) else { throw APIError.http(422) }
                var read = try await store.scanCoupon(jpeg)
                read.code = form.c.code  // schon gescannten Barcode behalten
                read.codeType = form.c.codeType
                read.source = "foto"
                form = CouponForm(read)
                withAnimation(Theme.spring) { stage = .form }
            } catch APIError.http(422) {
                readError = "Das Foto konnte nicht gelesen werden – näher ran und scharf fotografieren."
                withAnimation(Theme.spring) { stage = .failed }
            } catch APIError.http(502) {
                readError = "Die Erkennung ist gerade nicht erreichbar – trag den Coupon von Hand ein."
                withAnimation(Theme.spring) { stage = .failed }
            } catch {
                readError = error.localizedDescription
                withAnimation(Theme.spring) { stage = .failed }
            }
        }
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            if await store.saveCoupon(form.body, id: editing?.id) { dismiss() }
        }
    }
}

// MARK: S31d Plus/Minus-Sheet

/// Nach dem Einkauf (d.html S31d): „Heute bekommen: +60 °P“, eingelöst oder Kontostand korrigieren.
struct BonusSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let account: BonusAccountDTO
    @State private var mode = "plus"  // plus | minus | set
    @State private var value = Demo.screen == "bonus" ? "60" : ""
    @State private var saving = false
    @State private var height: CGFloat = 480

    /// Payback in °P (ganzzahlig), Rewe Bonus in Cent.
    private var amount: Int? {
        guard let n = Double(value.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")), n >= 0 else { return nil }
        let v = account.points ? Int(n.rounded()) : Int((n * 100).rounded())
        return v <= 10_000_000 && (mode == "set" || v > 0) ? v : nil
    }

    var body: some View {
        let current = store.bonusAccounts.first { a in a.program == account.program } ?? account
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 12) {
                        CouponLogo(chain: current.program == "rewe_bonus" ? "rewe" : "", program: current.program, name: current.name, size: 40)
                        Text(current.name).font(Theme.F.t2)
                    }
                    Spacer()
                    CloseButton { dismiss() }
                }
                StatNumber(label: "Kontostand", value: current.balanceText, size: 56).padding(.top, 20)
                if current.points {
                    Text("≈ \(euro(current.valueCents))").font(Theme.F.text(13)).foregroundStyle(Theme.C.ink2)
                        .frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 6)
                }
                Segmented8(options: [("plus", "Bekommen"), ("minus", "Eingelöst"), ("set", "Korrigieren")], selection: $mode).padding(.top, 16)
                FieldBox {
                    Text(mode == "plus" ? "+" : mode == "minus" ? "−" : "=").font(Theme.F.num(28)).foregroundStyle(Theme.C.ink)
                    TextField(account.points ? "60" : "0,50", text: $value)
                        .keyboardType(account.points ? .numberPad : .decimalPad)
                        .font(Theme.F.text(20, .bold))
                    Text(account.points ? "°P" : "€").foregroundStyle(Theme.C.ink2)
                }
                .padding(.top, 12)
                if mode != "set" {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(account.points ? ["10", "50", "100", "500"] : ["0,50", "1,00", "2,00", "5,00"], id: \.self) { v in
                                Chip8(title: account.points ? "\(v) °P" : "\(v) €", on: value == v) { value = v }
                            }
                        }
                    }
                    .padding(.top, 12)
                }
                PrimaryButton(title: saving ? "Speichere …" : title, disabled: amount == nil || saving, action: save).padding(.top, 18)
                Text(mode == "minus" ? "Eingelöstes zieht vom Konto ab." : "Bekommen zählt als Ersparnis „Bonus“, Korrektur nicht.")
                    .font(Theme.F.text(12)).foregroundStyle(Theme.C.ink2)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
            .padding(.horizontal, Theme.pagePadding).padding(.bottom, 40)
            .onGeometryChange(for: CGFloat.self) { g in g.size.height } action: { h in height = h }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.immediately)
        .presentationDetents([.height(height + 33), .large])
        .sheet8()
        .sensoryFeedback(.selection, trigger: mode)
    }

    private var title: String {
        guard let a = amount else { return mode == "set" ? "Kontostand setzen" : "Betrag eingeben" }
        switch mode {
        case "plus": return "Heute bekommen: +\(account.amountText(a))"
        case "minus": return "Eingelöst: −\(account.amountText(a))"
        default: return "Kontostand: \(account.amountText(a))"
        }
    }

    private func save() {
        guard let a = amount else { return }
        saving = true
        Task {
            defer { saving = false }
            let ok = await store.updateBonus(account.program, delta: mode == "set" ? nil : (mode == "plus" ? a : -a), set: mode == "set" ? a : nil)
            if ok { dismiss() }
        }
    }
}
