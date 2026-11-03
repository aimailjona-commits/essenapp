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
                Text(code).font(.system(.title3, design: .monospaced, weight: .semibold)).foregroundStyle(Theme.C.onBright)
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

/// Partner-Logo: Laden-Logo, sonst Programm-Emoji im getönten Quadrat (Payback, Aral …).
struct CouponLogo: View {
    let chain: String
    let program: String
    var size: CGFloat = 44

    var body: some View {
        if !chain.isEmpty {
            StoreLogo(chain: chain, size: size)
        } else {
            Text(Coupons.emoji(program)).font(.system(size: size * 0.48))
                .frame(width: size, height: size)
                .background(Theme.C.accentSoft, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

/// Badge „🎟 10fach“ am Artikel / Merklisten-Eintrag; antippen = Kassen-Vollbild.
struct CouponTag: View {
    @Environment(AppStore.self) private var store
    let coupon: CouponBadgeDTO

    var body: some View {
        Button { store.checkoutCoupon = coupon.id } label: { DealBadge(text: coupon.text, style: .ok) }
            .buttonStyle(PressableStyle())
            .padding(.vertical, 11).contentShape(Rectangle()).padding(.vertical, -11)  // Tap-Fläche 44 pt ohne größere Zeile
            .accessibilityLabel("Coupon \(coupon.partner.isEmpty ? Coupons.program(coupon.program) : coupon.partner) an der Kasse zeigen")
    }
}

/// Coupon-Leiste oben in der Laden-Liste (38d): passende gültige Coupons, antippen = Kasse.
struct CouponBar: View {
    @Environment(AppStore.self) private var store
    let coupons: [CouponDTO]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(coupons) { c in
                    Button { store.checkoutCoupon = c.id } label: {
                        HStack(spacing: 8) {
                            Text(c.badge).font(Theme.F.callout).foregroundStyle(Theme.C.accentDeep)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(c.short).font(Theme.F.micro).foregroundStyle(Theme.C.text1).lineLimit(1)
                                if let e = c.expiryText { Text(e).font(Theme.F.micro).foregroundStyle(c.soon ? Theme.C.deal : Theme.C.text2) }
                            }
                        }
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .background(Theme.C.accentSoft, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("\(c.programName)-Coupon \(c.short) an der Kasse zeigen")
                }
            }
            .padding(.horizontal, Theme.pagePadding)
        }
        .padding(.horizontal, -Theme.pagePadding)
        .appear()
    }
}

/// Zeile im Wallet: Logo, Vorteil, Programm · wofür, Ablauf, Mindestumsatz.
struct CouponRow: View {
    let coupon: CouponDTO

    var body: some View {
        HStack(spacing: 12) {
            CouponLogo(chain: coupon.chain, program: coupon.program)
            VStack(alignment: .leading, spacing: 3) {
                Text(coupon.title).font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(Theme.C.text1).lineLimit(1)
                Text("\(coupon.programName) · \(coupon.subject)").font(Theme.F.caption).foregroundStyle(Theme.C.text2).lineLimit(1)
                HStack(spacing: 6) {
                    if let e = coupon.expiryText {
                        if coupon.soon { DealBadge(text: e, style: .soft) } else { Text(e).font(Theme.F.micro).foregroundStyle(Theme.C.text2) }
                    }
                    if let m = coupon.minSpendCents { Text("ab \(euro(m)) Einkauf").font(Theme.F.micro).foregroundStyle(Theme.C.text2) }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: coupon.code.isEmpty ? "chevron.right" : coupon.codeType == "qr" ? "qrcode" : "barcode")
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.C.text3)
        }
        .padding(12)
        .card(radius: Theme.R.tile)
        .grayscale(coupon.expired ? 1 : 0)
        .opacity(coupon.expired ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: S31 Coupons (Wallet)

/// Einkauf › Pille „Coupons“: Bonus-Konten, gültige Coupons (bald ablaufende oben), „Abgelaufen“ grau.
struct CouponWalletView: View {
    @Environment(AppStore.self) private var store
    @State private var loaded = false
    @State private var error: String?
    @State private var adding = false
    @State private var editing: CouponDTO?
    @State private var account: BonusAccountDTO? = Demo.screen == "bonus" ? Demo.bonus[0] : nil

    var body: some View {
        let active = store.coupons.filter { c in !c.expired }
        let expired = store.coupons.filter(\.expired)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    DisplayHeader(line1: "Coupons", line2: "\(active.count) gültig")
                    RoundIconButton(systemName: "plus", dark: true, label: "Coupon hinzufügen") { adding = true }
                }
                if !store.bonusAccounts.isEmpty {
                    HStack(spacing: 12) { ForEach(store.bonusAccounts) { a in bonusCard(a) } }.appear()
                }
                if store.coupons.isEmpty {
                    if !loaded {
                        ForEach(0..<3, id: \.self) { _ in SkeletonCard(height: 76) }
                    } else if let error {
                        ErrorState(message: error) { Task { await load() } }
                    } else {
                        EmptyState(emoji: "🎟", title: "Noch keine Coupons",
                                   text: "Fotografiere Payback-, Rewe- oder dm-Coupons – an der Kasse zeigst du hier den Barcode.",
                                   buttonTitle: "Coupon hinzufügen") { adding = true }
                    }
                }
                ForEach(Array(active.enumerated()), id: \.element.id) { i, c in row(c).appear(delay: Double(i) * 0.04) }
                if !expired.isEmpty {
                    Label { Text("Abgelaufen").font(Theme.F.headline) } icon: { Text("⌛️") }.padding(.top, 8)
                    ForEach(expired) { c in row(c) }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
            .animation(Theme.spring, value: store.coupons)
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $adding) { CouponAddSheet().presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
        .sheet(item: $editing) { c in CouponAddSheet(editing: c).presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
        .sheet(item: $account) { a in BonusSheet(account: a).presentationCornerRadius(Theme.R.sheet) }
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

    /// Karte „Payback 1.240 °P ≈ 12,40 €“ / „Rewe Bonus 8,50 €“ → Plus/Minus-Sheet.
    private func bonusCard(_ a: BonusAccountDTO) -> some View {
        Button { account = a } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(Coupons.emoji(a.program)).font(.system(size: 18))
                        .frame(width: 34, height: 34).background(Theme.C.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer()
                    Image(systemName: "plus.forwardslash.minus").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.C.text3)
                }
                Text(a.name).font(Theme.F.caption).foregroundStyle(Theme.C.text2).padding(.top, 4)
                Text(a.balanceText).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7).contentTransition(.numericText()).foregroundStyle(Theme.C.text1)
                Text(a.points ? "≈ \(euro(a.valueCents))" : a.earnedMonthCents > 0 ? "+\(euro(a.earnedMonthCents)) im Monat" : " ")
                    .font(Theme.F.micro).foregroundStyle(a.points ? Theme.C.text2 : Theme.C.success)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(radius: Theme.R.tile)
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

// MARK: Kasse

/// Kassen-Vollbild: Barcode neu gerendert auf weißem Plättchen, maximale Helligkeit, Partner-Logo.
struct CouponCheckoutView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let id: Int
    @State private var failed = false
    @State private var editing: CouponDTO?
    @State private var brightness: CGFloat?

    private var screen: UIScreen? { UIApplication.shared.connectedScenes.compactMap { s in (s as? UIWindowScene)?.screen }.first }

    var body: some View {
        let coupon = store.coupons.first { c in c.id == id }
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Text("An der Kasse zeigen").font(Theme.F.headline)
                    Spacer()
                    RoundIconButton(systemName: "xmark", label: "Schließen") { dismiss() }
                }
                if let c = coupon {
                    plate(c).appear()
                    if c.code.isEmpty {
                        Text("Kein Barcode gespeichert – zeig den Coupon in der \(c.programName)-App oder scanne ihn hier ein.")
                            .font(Theme.F.caption).foregroundStyle(Theme.C.text2).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Button { editing = c } label: { Label("Barcode ergänzen", systemImage: "barcode.viewfinder") }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                } else if failed {
                    EmptyState(emoji: "🎟", title: "Coupon nicht gefunden", text: "Er wurde vielleicht gelöscht.")
                } else {
                    SkeletonCard(height: 360)
                }
            }
            .padding(Theme.pagePadding)
        }
        .background(Theme.C.bg)
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
        .sheet(item: $editing) { c in CouponAddSheet(editing: c).presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
    }

    /// Immer hell (Kontrast für den Scanner), auch im Dunkelmodus.
    private func plate(_ c: CouponDTO) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                CouponLogo(chain: c.chain, program: c.program, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.partner.isEmpty ? c.programName : c.partner).font(Theme.F.title).lineLimit(1)
                    Text(c.programName).font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 4) {
                Text(c.title).font(.system(.largeTitle, design: .rounded, weight: .heavy)).multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                Text("für \(c.subject)").font(Theme.F.callout).foregroundStyle(Theme.C.text2)
            }
            if !c.code.isEmpty { BarcodeView(code: c.code, type: c.codeType) }
            HStack(spacing: 8) {
                if let e = c.expiryText { DealBadge(text: e, style: c.soon || c.expired ? .strong : .ok) }
                if let m = c.minSpendCents { DealBadge(text: "ab \(euro(m)) Einkauf", style: .ok) }
            }
        }
        .foregroundStyle(Theme.C.text1)
        .padding(20)
        .background(Theme.C.plate, in: RoundedRectangle(cornerRadius: Theme.R.card, style: .continuous))
        .floatShadow()
        .environment(\.colorScheme, .light)
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
        var benefit = c.benefit.trimmingCharacters(in: .whitespaces)
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

/// Coupon hinzufügen: Foto (KI liest), Barcode (VisionKit) oder manuell → Prüfen/Bearbeiten → Speichern.
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

    init(editing: CouponDTO? = nil) {
        self.editing = editing
        let demo = Demo.screen == "couponadd"
        _stage = State(initialValue: editing != nil || demo ? .form : .choose)
        _form = State(initialValue: CouponForm(editing.map(CouponIn.init) ?? (demo ? Demo.couponScan : CouponIn())))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(editing != nil ? "Coupon bearbeiten" : form.c.source == "foto" ? "Coupon prüfen" : "Neuer Coupon").font(Theme.F.title)
                        if stage == .form, form.c.source == "foto", editing == nil {
                            Text("Aus dem Foto gelesen – bitte kurz prüfen.").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                        }
                    }
                    Spacer()
                    RoundIconButton(systemName: "xmark", label: "Schließen") { dismiss() }
                }
                switch stage {
                case .choose: choosePage
                case .reading:
                    SkeletonCard(height: 180)
                    Label("Coupon wird gelesen …", systemImage: "text.viewfinder").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                case .failed:
                    EmptyState(emoji: "📸", title: "Das hat nicht geklappt", text: readError)
                    Button("Anderes Foto") { withAnimation(Theme.spring) { stage = .choose } }.buttonStyle(PrimaryButtonStyle())
                    Button("Manuell eingeben") { withAnimation(Theme.spring) { stage = .form } }.buttonStyle(SecondaryButtonStyle())
                case .form: formPage
                }
            }
            .padding(Theme.pagePadding)
            .animation(Theme.spring, value: stage)
        }
        .scrollDismissesKeyboard(.immediately)
        .presentationBackground(Theme.C.bg)
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

    private var choosePage: some View {
        VStack(spacing: 12) {
            option("📸", "Coupon fotografieren", "Wir lesen Partner, Vorteil, Mindestumsatz und Gültigkeit") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true } else { store.flash("Keine Kamera – wähle ein Foto aus") }
            }
            PhotosPicker(selection: $pick, matching: .images) {
                Label("Foto aus der Mediathek", systemImage: "photo.on.rectangle").font(Theme.F.callout)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.C.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: 0.5))
            }
            option("▦", "Barcode scannen", "Code 128, EAN oder QR – wird an der Kasse neu angezeigt") { scanner = true }
            option("✏️", "Manuell eingeben", "Partner und Vorteil selbst eintragen") {
                form.c.source = "manuell"
                withAnimation(Theme.spring) { stage = .form }
            }
        }
    }

    private func option(_ emoji: String, _ title: String, _ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(emoji).font(.system(size: 24)).frame(width: 52, height: 52)
                    .background(Theme.C.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.F.callout).foregroundStyle(Theme.C.text1)
                    Text(text).font(Theme.F.micro).foregroundStyle(Theme.C.text2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.C.text3)
            }
            .padding(14).card(radius: Theme.R.tile)
        }
        .buttonStyle(PressableStyle())
    }

    @ViewBuilder private var formPage: some View {
        let household = Labels.chains.filter { c in store.household?.stores.contains { s in s.chain == c.key && s.enabled } ?? true }
        section("🏷️", "Partner") {
            ChipFlow(items: Coupons.programs, selected: [form.c.program], color: Theme.C.accent) { p in
                form.c.program = p
                let known = ["rewe_bonus": ("REWE", "rewe"), "dm": ("dm", "dm"), "rossmann": ("Rossmann", "rossmann")][p]
                if let known, form.c.partner.isEmpty { form.c.partner = known.0; form.c.chain = known.1 }
            }
            field("Partner, z. B. REWE oder Aral", $form.c.partner)
            HStack {
                Text("Laden").font(Theme.F.callout).foregroundStyle(Theme.C.text2)
                Spacer()
                Picker("Laden", selection: $form.c.chain) {
                    Text("Kein bestimmter").tag("")
                    ForEach(household, id: \.key) { c in Text(c.name).tag(c.key) }
                }
                .pickerStyle(.menu).tint(Theme.C.text1)
            }
            Text("Im passenden Laden erinnern wir an den Coupon und zeigen ihn oben in der Liste.")
                .font(Theme.F.micro).foregroundStyle(Theme.C.text2)
        }
        section("🎁", "Vorteil") {
            Picker("Art", selection: $form.kind) {
                Text("Xfach").tag("fach"); Text("€ Bonus").tag("bonus"); Text("% Rabatt").tag("prozent"); Text("Sonstiges").tag("")
            }
            .pickerStyle(.segmented)
            if !form.kind.isEmpty {
                HStack(spacing: 10) {
                    TextField(form.kind == "fach" ? "10" : form.kind == "bonus" ? "0,50" : "20", text: $form.value)
                        .keyboardType(form.kind == "bonus" ? .decimalPad : .numberPad)
                        .font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                        .padding(.horizontal, 14).frame(height: 44).background(Theme.C.surface, in: Capsule())
                    Text(form.kind == "fach" ? "fach Punkte" : form.kind == "bonus" ? "€ Bonus" : "% Rabatt").font(Theme.F.callout)
                }
            }
            field("Text, z. B. 10fach Punkte auf Kaffee", $form.c.benefit)
            field("Produkt oder Marke (leer = ganzer Einkauf)", $form.c.product)
            HStack {
                Text("Kategorie").font(Theme.F.callout).foregroundStyle(Theme.C.text2)
                Spacer()
                Picker("Kategorie", selection: $form.c.category) {
                    Text("Keine").tag("")
                    ForEach(Labels.categories, id: \.0) { c in Text(c.1).tag(c.0) }
                }
                .pickerStyle(.menu).tint(Theme.C.text1)
            }
            HStack(spacing: 10) {
                Text("Mindestumsatz").font(Theme.F.callout).foregroundStyle(Theme.C.text2)
                Spacer()
                TextField("optional", text: $form.minSpend).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .padding(.horizontal, 14).frame(width: 120, height: 44).background(Theme.C.surface, in: Capsule())
                Text("€").font(Theme.F.callout)
            }
        }
        section("📅", "Gültigkeit") {
            Toggle("Gültig bis", isOn: $form.expires.animation(Theme.spring)).font(Theme.F.callout).tint(Theme.C.accent)
            if form.expires { DatePicker("Datum", selection: $form.until, displayedComponents: .date) }
            Text("2 Tage vor Ablauf kommt eine Erinnerung.").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
        }
        section("▦", "Barcode") {
            let code = form.c.code ?? ""
            if !code.isEmpty {
                BarcodeView(code: code, type: (form.c.codeType ?? "").isEmpty ? Barcode.guess(code) : form.c.codeType ?? "", height: 70)
                    .padding(12)
                    .background(Theme.C.plate, in: RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
                Picker("Typ", selection: Binding(get: { (form.c.codeType ?? "").isEmpty ? Barcode.guess(code) : form.c.codeType ?? "" },
                                                 set: { t in form.c.codeType = t })) {
                    ForEach(Coupons.codeTypes, id: \.0) { t in Text(t.1).tag(t.0) }
                }
                .pickerStyle(.segmented)
            }
            field("Code eintippen (optional)", Binding(get: { form.c.code ?? "" }, set: { v in form.c.code = v; form.c.codeType = nil }))
                .keyboardType(.asciiCapable).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button { scanner = true } label: { Label(code.isEmpty ? "Barcode scannen" : "Neu scannen", systemImage: "barcode.viewfinder") }
                .buttonStyle(SecondaryButtonStyle())
        }
        Button(action: save) { Text(saving ? "Speichere …" : "Speichern") }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!form.valid || saving).opacity(form.valid ? 1 : 0.5)
        if let c = editing {
            Button("Löschen", role: .destructive) { Task { await store.deleteCoupon(c); dismiss() } }
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private func field(_ placeholder: String, _ text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .padding(12).background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.chip))
    }

    private func section(_ emoji: String, _ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label { Text(title).font(Theme.F.headline) } icon: { Text(emoji) }
            content()
        }
        .padding(16).card()
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

// MARK: Plus/Minus-Sheet

/// Nach dem Einkauf: „Heute bekommen: +60 °P“, eingelöst oder Kontostand korrigieren.
struct BonusSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let account: BonusAccountDTO
    @State private var mode = "plus"  // plus | minus | set
    @State private var value = ""
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
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label { Text(current.name).font(Theme.F.title) } icon: { Text(Coupons.emoji(current.program)) }
                    Spacer()
                    RoundIconButton(systemName: "xmark", label: "Schließen") { dismiss() }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.balanceText).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                    if current.points { Text("≈ \(euro(current.valueCents))").font(Theme.F.caption).foregroundStyle(Theme.C.text2) }
                }
                PillSegment(options: [("plus", "Bekommen"), ("minus", "Eingelöst"), ("set", "Korrigieren")], selection: $mode)
                HStack(spacing: 10) {
                    Text(mode == "plus" ? "+" : mode == "minus" ? "−" : "=").font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(mode == "plus" ? Theme.C.success : Theme.C.text1)
                    TextField(account.points ? "60" : "0,50", text: $value)
                        .keyboardType(account.points ? .numberPad : .decimalPad)
                        .font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                        .padding(.horizontal, 16).frame(height: 52).background(Theme.C.surface, in: Capsule())
                    Text(account.points ? "°P" : "€").font(Theme.F.headline)
                }
                if mode != "set" {
                    HStack(spacing: 8) {
                        ForEach(account.points ? ["10", "50", "100", "500"] : ["0,50", "1,00", "2,00", "5,00"], id: \.self) { v in
                            FilterChip(label: account.points ? "\(v) °P" : "\(v) €", selected: value == v) { value = v }
                        }
                    }
                }
                Button(action: save) { Text(saving ? "Speichere …" : title) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(amount == nil || saving).opacity(amount == nil ? 0.5 : 1)
                Text(mode == "plus" ? "Zählt als Ersparnis „Bonus“ im Monats-Dashboard und bei den Erfolgen."
                                    : mode == "set" ? "Korrektur zählt nicht als Ersparnis." : "Eingelöstes zieht vom Konto ab.")
                    .font(Theme.F.micro).foregroundStyle(Theme.C.text2)
            }
            .padding(Theme.pagePadding)
            .onGeometryChange(for: CGFloat.self) { g in g.size.height } action: { h in height = h }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.immediately)
        .presentationDetents([.height(height), .large])
        .presentationBackground(Theme.C.bg)
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
