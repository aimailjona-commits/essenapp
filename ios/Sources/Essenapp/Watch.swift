import AVFoundation
import SwiftUI
import Vision
import VisionKit

// Merkliste mit Alarm (27), Preisalarm für Zutaten (40), Verbrauchsrhythmus (58) – Server `/watch` (E67).

// MARK: Modelle (= backend/app/schemas.py)

/// = WatchOut. `hits` = aktuelle Treffer (erfüllen den Alarm), günstigste zuerst.
struct WatchDTO: Codable, Identifiable, Hashable {
    var id: Int
    var kind: String  // produkt | zutat
    var label: String
    var brand: String
    var ean: String
    var imageUrl: String
    var category: String
    var maxPriceCents: Int?
    var maxBasePriceCents: Int?
    var baseUnit: String  // "" | kg | l | stk
    var chains: [String]  // leer = alle Läden
    var lastsWeeks: Double?
    var lastsWeeksSuggestion: Double?
    var lastBought: String?  // YYYY-MM-DD
    var emptyOn: String?
    var hits: [OfferDTO]
    var coupon: CouponBadgeDTO? = nil  // passender Drogerie-Coupon (59)
    var lastOfferWeek: String? = nil  // „2026-W44“: zuletzt im Angebot
    var lastOfferChain: String? = nil
    var lastOfferPriceCents: Int? = nil

    /// „zuletzt im Angebot: KW 44 bei Lidl (1,99 €)“; nil = nie gesehen.
    var lastOfferText: String? {
        guard let w = lastOfferWeek else { return nil }
        return "zuletzt im Angebot: KW \(w.suffix(2))" + (lastOfferChain.map { c in " bei \(Labels.chain(c))" } ?? "")
            + (lastOfferPriceCents.map { p in " (\(euro(p)))" } ?? "")
    }

    /// „Alarm unter 2,00 €“ bzw. „unter 7,00 €/kg“; nil = kein Wunschpreis.
    var alarmText: String? {
        if let c = maxBasePriceCents { return "unter \(euro(c))/\(WatchDTO.baseLabel(baseUnit))" }
        return maxPriceCents.map { c in "unter \(euro(c))" }
    }

    static func baseLabel(_ unit: String) -> String { unit == "stk" ? "Stück" : unit }
}

/// = WatchIn: Herz (offerId), Barcode (ean …), Freitext oder Preisalarm für eine Zutat.
struct WatchIn: Encodable {
    var kind = "produkt"
    var offerId: Int?
    var label: String?
    var brand = ""
    var ean = ""
    var imageUrl = ""
    var category = ""
    var maxPriceCents: Int?
    var maxBasePriceCents: Int?
    var baseUnit = ""
}

/// = WatchUpdate; alle Felder werden gesendet (null = Wunschpreis/Rhythmus aus).
struct WatchPatch: Encodable {
    var maxPriceCents: Int?
    var maxBasePriceCents: Int?
    var baseUnit: String
    var chains: [String]
    var lastsWeeks: Double?
    var lastBought: String?

    enum CodingKeys: String, CodingKey { case maxPriceCents, maxBasePriceCents, baseUnit, chains, lastsWeeks, lastBought }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(maxPriceCents, forKey: .maxPriceCents)
        try c.encode(maxBasePriceCents, forKey: .maxBasePriceCents)
        try c.encode(baseUnit, forKey: .baseUnit)
        try c.encode(chains, forKey: .chains)
        try c.encode(lastsWeeks, forKey: .lastsWeeks)
        try c.encode(lastBought, forKey: .lastBought)
    }
}

/// = EanProductOut (Barcode → Open Food Facts).
struct EanProductDTO: Codable, Hashable, Identifiable {
    var ean: String
    var found: Bool
    var name: String
    var brand: String
    var imageUrl: String
    var nutriScore: String?
    var id: String { ean }
}

// MARK: Server

extension AppStore {
    func loadWatch() async {
        guard !demo else { return }
        await migrateWatchlist()
        if let w: [WatchDTO] = try? await api.request("GET", "/watch") { watches = w }
    }

    /// Früher lokal gemerkte Angebote (bis Phase 11) einmalig auf den Server übertragen.
    private func migrateWatchlist() async {
        guard let old: Set<Int> = Persist.load("watchlist"), !old.isEmpty else { return }
        var ok = true
        for id in old where offers.contains(where: { o in o.id == id }) {
            do { let _: WatchDTO = try await api.request("POST", "/watch", body: WatchIn(offerId: id)) } catch { ok = false }
        }
        if ok { UserDefaults.standard.removeObject(forKey: "watchlist") }
    }

    /// Eintrag, der dieses Angebot beobachtet (Treffer oder gleicher Titel/Marke).
    func watch(for offer: OfferDTO) -> WatchDTO? {
        watches.first { w in
            w.kind == "produkt" && (w.hits.contains { h in h.id == offer.id } || (w.label == offer.title && w.brand == offer.brand))
        }
    }

    /// Merklisten-Treffer der Woche (Badge am Angebote-Tab).
    var watchHits: Int { watches.filter { w in !w.hits.isEmpty }.count }

    func toggleWatch(_ offer: OfferDTO) async {
        if let w = watch(for: offer) { await deleteWatch(w) } else { _ = await addWatch(WatchIn(offerId: offer.id), demoOffer: offer) }
    }

    @discardableResult
    func addWatch(_ body: WatchIn, demoOffer: OfferDTO? = nil) async -> Bool {
        do {
            let w: WatchDTO = demo
                ? WatchDTO(id: (watches.map(\.id).max() ?? 0) + 1, kind: body.kind, label: body.label ?? demoOffer?.title ?? "",
                           brand: body.brand.isEmpty ? demoOffer?.brand ?? "" : body.brand, ean: body.ean, imageUrl: body.imageUrl,
                           category: demoOffer?.category ?? body.category, maxPriceCents: body.maxPriceCents,
                           maxBasePriceCents: body.maxBasePriceCents, baseUnit: body.baseUnit, chains: [], lastsWeeks: nil,
                           lastsWeeksSuggestion: nil, lastBought: nil, emptyOn: nil, hits: demoOffer.map { o in [o] } ?? [])
                : try await api.request("POST", "/watch", body: body)
            withAnimation(Theme.spring) { watches.append(w) }
            flash(body.kind == "zutat" ? "Preisalarm angelegt" : "Auf der Merkliste")
            return true
        } catch {
            flash("Nicht gemerkt: \(error.localizedDescription)")
            return false
        }
    }

    func updateWatch(_ id: Int, _ patch: WatchPatch) async -> Bool {
        do {
            if !demo {
                let w: WatchDTO = try await api.request("PATCH", "/watch/\(id)", body: patch)
                if let i = watches.firstIndex(where: { x in x.id == id }) { watches[i] = w }
            }
            flash("Gespeichert")
            return true
        } catch {
            flash("Nicht gespeichert: \(error.localizedDescription)")
            return false
        }
    }

    func deleteWatch(_ w: WatchDTO) async {
        let before = watches
        withAnimation(Theme.spring) { watches.removeAll { x in x.id == w.id } }
        do {
            if !demo { try await api.send("DELETE", "/watch/\(w.id)") }
            flash(w.kind == "zutat" ? "Preisalarm gelöscht" : "Von der Merkliste entfernt")
        } catch {
            watches = before
            flash("Nicht entfernt: \(error.localizedDescription)")
        }
    }

    func product(ean: String) async throws -> EanProductDTO {
        demo ? Demo.eanProduct : try await api.request("GET", "/products/ean/\(ean)", timeout: 20)
    }
}

// MARK: S10 Merkliste

/// Tab „Angebote“, Segment „Merkliste“: „Diese Woche günstig“, „Beobachtet“, „Preisalarme“; unten „Suchen“ + „Barcode scannen“.
struct WatchListView: View {
    @Environment(AppStore.self) private var store
    let showOffers: () -> Void  // Segment „Angebote“
    @State private var loaded = false
    @State private var error: String?
    @State private var editing: WatchDTO? = Demo.screen == "watchedit" ? Demo.watches[2] : nil
    @State private var searching = Demo.screen == "watchsearch"
    @State private var newAlarm = false

    private enum L {
        static let top: CGFloat = 14  // .scr 66 − 52
        static let segWidth: CGFloat = 230
        static let buttons: CGFloat = 100  // Knopf-Reihe über der Nav (bottom 100)
    }

    var body: some View {
        let cheap = store.watches.filter { w in w.kind == "produkt" && !w.hits.isEmpty }
        let watched = store.watches.filter { w in w.kind == "produkt" && w.hits.isEmpty }
        let alarms = store.watches.filter { w in w.kind == "zutat" }
        GeometryReader { g in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(store.watches.count) beobachtet").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                    Text("Merkliste").font(Theme.F.t1).accessibilityAddTraits(.isHeader)
                    Segmented8(options: [(false, "Angebote"), (true, "Merkliste · \(store.watches.count)")],
                               selection: Binding(get: { true }, set: { on in if !on { showOffers() } }))
                        .frame(width: L.segWidth)
                        .padding(.top, 14)

                    if store.watches.isEmpty { state }
                    if !cheap.isEmpty {
                        header(.tag, "Diese Woche günstig")
                        ForEach(cheap) { w in hitRow(w) }
                    }
                    if !watched.isEmpty {
                        header(.eye, "Beobachtet")
                        ForEach(watched) { w in watchRow(w) }
                    }
                    HStack(spacing: 6) {
                        Icon(.bell, size: 16)
                        SectionLabel("Preisalarme", big: true)
                        Spacer()
                        Button { newAlarm = true } label: {
                            HStack(spacing: 6) { Icon(.plus, size: 14); Text("Zutat") }
                                .font(Theme.F.text(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.C.onInk)
                                .padding(.horizontal, 12).frame(height: 26)
                                .background(Theme.C.ink, in: Capsule())
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("Preisalarm für eine Zutat anlegen")
                    }
                    .foregroundStyle(Theme.C.ink2)
                    .padding(.top, 18)
                    if alarms.isEmpty {
                        Text("Z. B. „Butter unter 1,49 €“ oder „Hähnchenbrust unter 7 €/kg“ – auch per langem Druck auf eine Rezept-Zutat.")
                            .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(alarms) { w in alarmRow(w) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, g.safeAreaInsets.top + L.top)
                .padding(.bottom, L.buttons + Theme.S.button2 + 24)
                .pinned(left: 268, top: 44) { Ill("bag").frame(width: 104) }
                .edgeForm(.quarter, Theme.C.sage, width: 180, height: 180, right: 0, top: 0)
            }
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 10) {
                OutlineButton(title: "Suchen", icon: .search) { searching = true }
                    .fixedSize(horizontal: true, vertical: false)
                    .background(Theme.C.bg, in: Capsule())
                Button { store.barcode = true } label: {
                    HStack(spacing: 8) { Icon(.barcode, size: 20); Text("Barcode scannen") }
                        .font(Theme.F.button).foregroundStyle(Theme.C.onInk)
                        .frame(maxWidth: .infinity, minHeight: Theme.S.button2)
                        .background(Theme.C.ink, in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, L.buttons)
            .ignoresSafeArea(edges: .bottom)
        }
        .animation(Theme.spring, value: store.watches)
        .task { await load() }
        .sheet(item: $editing) { w in WatchSheet(watch: w).presentationDetents([.large]) }
        .sheet(isPresented: $newAlarm) { WatchSheet(ingredient: "").presentationDetents([.large]) }
        .sheet(isPresented: $searching) { WatchSearchSheet().presentationDetents([.large]) }
    }

    /// Laden / Fehler / Leer (ohne Mockup, mit v8-Bausteinen).
    @ViewBuilder private var state: some View {
        if !loaded && !store.demo {
            VStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in Skeleton8(height: 56) } }.padding(.top, 28)
        } else if let error {
            VStack(alignment: .leading, spacing: 0) {
                Text("Merkliste nicht geladen").font(Theme.F.t2)
                Text(error).font(Theme.F.text(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.C.ink2).padding(.top, 6)
                OutlineButton(title: "Erneut versuchen", icon: .refresh) { Task { await load() } }
                    .fixedSize(horizontal: true, vertical: false).padding(.top, 16)
            }
            .padding(.top, 40)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("Noch nichts gemerkt").font(Theme.F.t2)
                Text("Merk dir Lieblingsprodukte – wir sagen Bescheid, wenn sie im Angebot sind.")
                    .font(Theme.F.text(15, .semibold, relativeTo: .body)).foregroundStyle(Theme.C.ink2)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            }
            .padding(.top, 40)
        }
    }

    private func load() async {
        guard !store.demo else { loaded = true; return }
        do {
            store.watches = try await store.api.request("GET", "/watch")
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loaded = true
    }

    private func header(_ icon: Icon8, _ title: String) -> some View {
        HStack(spacing: 6) { Icon(icon, size: 16); SectionLabel(title, big: true) }
            .foregroundStyle(Theme.C.ink2)
            .padding(.top, 28).padding(.bottom, 4)
    }

    /// Zeile `.c-r2`: zwei Textzeilen, höchstens ein Zusatz rechts.
    private func row(_ title: String, _ sub: Text, lead: AnyView? = nil, trail: AnyView? = nil, pad: CGFloat = 8) -> some View {
        HStack(spacing: 14) {
            if let lead { lead }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.F.text(16, .bold, relativeTo: .body)).foregroundStyle(Theme.C.ink).lineLimit(1)
                sub.font(Theme.F.text(12, .semibold, relativeTo: .caption)).lineLimit(2).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trail { trail }
        }
        .padding(.vertical, pad)
        .frame(minHeight: 44)
        .overlay(alignment: .top) { Hairline() }
        .contentShape(Rectangle())
    }

    /// „Diese Woche günstig“: Zeichnung bzw. Logo, „0,99 € bei Rewe“, Rabatt → Angebot.
    private func hitRow(_ w: WatchDTO) -> some View {
        let o = w.hits[0]
        let lead: AnyView = OfferArt.ill(w.label) != nil
            ? AnyView(OfferArt(title: w.label, url: "").frame(width: 60, height: 60).frame(width: 48, height: 48)
                .background(OfferArt.tint(w.label, category: w.category), in: Circle()).clipShape(Circle()))
            : AnyView(LogoCircle(chain: o.chain))
        return NavigationLink { OfferDetailView(offer: o) } label: {
            row(w.label, Text("\(euro(o.priceCents)) bei \(Labels.chain(o.chain))").foregroundStyle(Theme.C.ink2), lead: lead,
                trail: AnyView(HStack(spacing: 6) {
                    DealPill(text: o.discount.map { d in "−\(d) %" } ?? "Angebot")
                    if let c = w.coupon { couponPill(c) }
                }), pad: 2)
        }
        .buttonStyle(PressableStyle())
        .contextMenu { menu(w) }
    }

    /// „Beobachtet“: Wunschpreis + zuletzt im Angebot; Rhythmus steht im Bearbeiten-Sheet.
    private func watchRow(_ w: WatchDTO) -> some View {
        let last = w.lastOfferWeek.map { wk in
            "zuletzt KW \(wk.suffix(2))" + (w.lastOfferChain.map { c in " bei \(Labels.chain(c))" } ?? "")
                + (w.lastOfferPriceCents.map { p in " (\(euro(p)))" } ?? "")
        }
        let parts = [w.alarmText, last].compactMap { $0 }
        return Button { editing = w } label: {
            row(w.brand.isEmpty ? w.label : "\(w.label) · \(w.brand)",
                Text(parts.isEmpty ? "gerade nicht im Angebot" : parts.joined(separator: " · ")).foregroundStyle(Theme.C.ink2),
                trail: w.coupon.map { c in AnyView(couponPill(c)) })
        }
        .buttonStyle(PressableStyle())
        .contextMenu { menu(w) }
    }

    /// „Preisalarme“ (Zutat): „Butter unter 1,49 €“, greift → grün.
    private func alarmRow(_ w: WatchDTO) -> some View {
        Button { editing = w } label: {
            row("\(w.label) \(w.alarmText ?? "")", w.hits.first.map { o in
                Text("greift: \(euro(o.priceCents)) bei \(Labels.chain(o.chain)) – \(o.title)")
                    .font(Theme.F.text(12, .extrabold, relativeTo: .caption)).foregroundStyle(Theme.C.success)
            } ?? Text("wartet auf ein passendes Angebot").foregroundStyle(Theme.C.ink2))
        }
        .buttonStyle(PressableStyle())
        .contextMenu { menu(w) }
    }

    /// Coupon (59) als weiche Pille; antippen = Kassen-Vollbild.
    private func couponPill(_ c: CouponBadgeDTO) -> some View {
        Button { store.checkoutCoupon = c.id } label: {
            SoftPill(text: "Coupon \(c.text.replacingOccurrences(of: "🎟", with: "").trimmingCharacters(in: .whitespaces))")
                .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Coupon \(c.partner.isEmpty ? Coupons.program(c.program) : c.partner) an der Kasse zeigen")
    }

    @ViewBuilder private func menu(_ w: WatchDTO) -> some View {
        Button("Bearbeiten", systemImage: "slider.horizontal.3") { editing = w }
        Button("Entfernen", systemImage: "trash", role: .destructive) { Task { await store.deleteWatch(w) } }
    }
}

// MARK: Eintrag bearbeiten / Preisalarm anlegen (S10 Bearbeiten)

/// Wunschpreis groß + Einheit im Segment, Läden und Verbrauchsrhythmus (58) als aufklappbare Zusammenfassungs-Zeilen.
/// Ohne `watch`: neuer Preisalarm für eine Zutat (40), Name aus `ingredient`.
struct WatchSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let watch: WatchDTO?
    @State private var name: String
    @State private var price: String
    @State private var basis: String  // "" = Packung, sonst kg | l | stk
    @State private var chains: Set<String>
    @State private var rhythm: Bool
    @State private var weeks: Int
    @State private var bought: Bool
    @State private var boughtDate: Date
    @State private var saving = false
    @State private var open: String?  // aufgeklappte Zeile: "laeden" | "rhythmus"

    init(watch: WatchDTO) {
        self.watch = watch
        _name = State(initialValue: watch.label)
        let cents = watch.maxBasePriceCents ?? watch.maxPriceCents
        _price = State(initialValue: cents.map { c in num(Double(c) / 100, 2...2) } ?? "")
        _basis = State(initialValue: watch.maxBasePriceCents != nil ? watch.baseUnit : "")
        _chains = State(initialValue: Set(watch.chains))
        _rhythm = State(initialValue: watch.lastsWeeks != nil)
        _weeks = State(initialValue: Int((watch.lastsWeeks ?? watch.lastsWeeksSuggestion ?? 4).rounded()))
        _bought = State(initialValue: watch.lastBought != nil)
        _boughtDate = State(initialValue: watch.lastBought.flatMap { d in try? Date(d, strategy: PantryDTO.day) } ?? .now)
    }

    init(ingredient: String) {
        watch = nil
        _name = State(initialValue: ingredient)
        _price = State(initialValue: "")
        _basis = State(initialValue: "")
        _chains = State(initialValue: [])
        _rhythm = State(initialValue: false)
        _weeks = State(initialValue: 4)
        _bought = State(initialValue: false)
        _boughtDate = State(initialValue: .now)
    }

    private var cents: Int? {
        Double(price.replacingOccurrences(of: ",", with: ".")).map { e in Int((min(max(e, 0), 10_000) * 100).rounded()) }.flatMap { c in c > 0 ? c : nil }
    }
    private var trimmed: String { String(name.trimmingCharacters(in: .whitespaces).prefix(200)) }
    private var valid: Bool { watch != nil || (!trimmed.isEmpty && cents != nil) }

    var body: some View {
        let isProduct = watch?.kind == "produkt"
        let household = Labels.chains.map(\.key).filter { c in store.household?.stores.contains { s in s.chain == c && s.enabled } ?? false }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(watch?.label ?? "Preisalarm").font(Theme.F.t2).lineLimit(2)
                        Text(isProduct ? (watch!.brand.isEmpty ? "Merkliste" : watch!.brand) : "Für eine Zutat – jede passende Marke und Packung")
                            .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                    }
                    Spacer()
                    CloseButton { dismiss() }
                }
                if watch == nil {  // ohne Mockup: Name der Zutat
                    FieldBox(icon: .search) { TextField("Zutat, z. B. Butter", text: $name) }.padding(.top, 16)
                }
                // Wunschpreis als große Zahl (`.stat`), direkt eintippbar
                VStack(spacing: 6) {
                    Hairline(color: Theme.C.ink)
                    HStack(alignment: .top) {
                        Text("Wunschpreis\nunter").font(Theme.F.text(12, .bold, relativeTo: .caption))
                        Spacer(minLength: 8)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            TextField(isProduct ? "–" : "1,49", text: $price)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(Theme.F.num(64)).tracking(Theme.F.numTracking(64))
                                .minimumScaleFactor(0.5)
                            Text("€").font(Theme.F.num(64)).tracking(Theme.F.numTracking(64))
                        }
                    }
                }
                .foregroundStyle(Theme.C.ink)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Wunschpreis unter, Euro")
                .padding(.top, 28)
                Segmented8(options: [("", "Packung"), ("kg", "pro kg"), ("l", "pro l"), ("stk", "pro Stück")], selection: $basis)
                    .padding(.top, 14)
                Text(basis.isEmpty ? "Alarm, wenn eine Packung darunter im Angebot ist."
                                   : "Grundpreis-Alarm gilt für jede Packungsgröße.")
                    .font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2).padding(.top, 8)

                VStack(spacing: 0) {
                    summary("laeden", "Läden", chains.isEmpty ? "Alle Läden" : Labels.chains.map(\.key).filter(chains.contains).map(Labels.chain).joined(separator: ", "))
                    if open == "laeden" {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Chip8(title: "Alle", on: chains.isEmpty) { chains = [] }
                                ForEach(household, id: \.self) { c in
                                    Chip8(title: Labels.chain(c), on: chains.contains(c)) { chains.formSymmetricDifference([c]) }
                                }
                            }
                            .padding(.horizontal, Theme.pagePadding)
                        }
                        .padding(.horizontal, -Theme.pagePadding)
                        .padding(.bottom, 8)
                    }
                    if isProduct, let w = watch {
                        summary("rhythmus", "Verbrauchsrhythmus", rhythmText(w))
                        if open == "rhythmus" { rhythmEditor(w) }
                    }
                }
                .padding(.top, 28)

                PrimaryButton(title: saving ? "Speichere …" : watch == nil ? "Preisalarm anlegen" : "Speichern", disabled: !valid || saving,
                              action: save)
                    .padding(.top, 28)
                if let w = watch {
                    Button { Task { await store.deleteWatch(w); dismiss() } } label: {
                        Text("Entfernen").font(Theme.F.text(15, .extrabold, relativeTo: .body)).foregroundStyle(Theme.C.deal)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.immediately)
        .sheet8()
    }

    /// Zusammenfassungs-Zeile mit Pfeil (antippen = aufklappen).
    private func summary(_ id: String, _ title: String, _ sub: String) -> some View {
        Button { withAnimation(Theme.spring) { open = open == id ? nil : id } } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.F.text(16, .bold, relativeTo: .body)).foregroundStyle(Theme.C.ink)
                    Text(sub).font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Icon(.chev, size: 18).foregroundStyle(Theme.C.ink3).rotationEffect(.degrees(open == id ? 90 : 0))
            }
            .padding(.vertical, 11)
            .overlay(alignment: .top) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(open == id ? .isSelected : [])
    }

    private func rhythmText(_ w: WatchDTO) -> String {
        guard rhythm else { return w.lastsWeeksSuggestion.map { s in "aus · Vorschlag: \(num(s)) Wochen" } ?? "aus" }
        var parts = ["hält ca. \(weeks) \(weeks == 1 ? "Woche" : "Wochen")"]
        if bought {
            parts.append("gekauft \(dayMonth(boughtDate.formatted(PantryDTO.day)))")
            if let empty = Calendar.current.date(byAdding: .day, value: weeks * 7, to: boughtDate) {
                parts.append("leer ca. \(dayMonth(empty.formatted(PantryDTO.day)))")
            }
        }
        return parts.joined(separator: " · ")
    }

    private func rhythmEditor(_ w: WatchDTO) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $rhythm.animation(Theme.spring)) { Text("Rhythmus merken").font(Theme.F.text(15, .bold, relativeTo: .body)) }
                .toggleStyle(.v8)
            if rhythm {
                HStack {
                    Text("Hält ca.").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                    Spacer()
                    Stepper8(value: $weeks, range: 1...52) { "\($0) Wo." }
                }
                Toggle(isOn: $bought.animation(Theme.spring)) { Text("Zuletzt gekauft").font(Theme.F.text(15, .bold, relativeTo: .body)) }
                    .toggleStyle(.v8)
                if bought {
                    DatePicker("am", selection: $boughtDate, in: ...Date.now, displayedComponents: .date)
                        .font(Theme.F.small).tint(Theme.C.ink)
                }
                Text("Wird automatisch gesetzt, wenn du es auf der Liste abhakst. 2 Wochen vor „leer“ melden wir Angebote, 3 Tage vorher kommt es auf die Liste.")
                    .font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 12)
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            if let w = watch {
                let patch = WatchPatch(maxPriceCents: basis.isEmpty ? cents : nil, maxBasePriceCents: basis.isEmpty ? nil : cents,
                                       baseUnit: basis.isEmpty ? "" : basis, chains: Array(chains).sorted(),
                                       lastsWeeks: rhythm && w.kind == "produkt" ? Double(weeks) : nil,
                                       lastBought: rhythm && bought ? boughtDate.formatted(PantryDTO.day) : nil)
                if await store.updateWatch(w.id, patch) {
                    await store.loadWatch()
                    dismiss()
                }
            } else {
                let body = WatchIn(kind: "zutat", label: trimmed, maxPriceCents: basis.isEmpty ? cents : nil,
                                   maxBasePriceCents: basis.isEmpty ? nil : cents, baseUnit: basis)
                if await store.addWatch(body) {
                    if !chains.isEmpty, let w = store.watches.last {
                        _ = await store.updateWatch(w.id, WatchPatch(maxPriceCents: w.maxPriceCents, maxBasePriceCents: w.maxBasePriceCents,
                                                                     baseUnit: w.baseUnit, chains: Array(chains).sorted()))
                    }
                    dismiss()
                }
            }
        }
    }
}

// MARK: S10 Suchen

/// „Produkt merken“: Suchwort beobachten oder ein Angebot dieser Woche per Herz merken.
struct WatchSearchSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = Demo.screen == "watchsearch" ? "Shampoo" : ""

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let found = q.count < 2 ? [] : Array(store.offers.filter { o in o.title.localizedCaseInsensitiveContains(q) || o.brand.localizedCaseInsensitiveContains(q) }.prefix(30))
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Produkt merken").font(Theme.F.t2)
                    Spacer()
                    CloseButton { dismiss() }
                }
                FieldBox(icon: .search) { TextField("Name oder Marke, z. B. Shampoo", text: $query).submitLabel(.search) }
                    .padding(.top, 16)
                if q.count >= 2 {
                    PrimaryButton(title: "„\(q)“ beobachten", icon: .eye) {
                        Task { if await store.addWatch(WatchIn(label: String(q.prefix(200)))) { dismiss() } }
                    }
                    .padding(.top, 14)
                    if !found.isEmpty {
                        SectionLabel("Diese Woche im Angebot", big: true).padding(.top, 22).padding(.bottom, 4)
                    }
                    ForEach(found) { o in
                        let on = store.watch(for: o) != nil
                        OfferLine(offer: o, parts: [euro(o.priceCents), Labels.chain(o.chain), o.amountText]) {
                            Button { Task { await store.toggleWatch(o) } } label: {
                                ZStack {
                                    if on { Icon8.heart.path(.stroke).fill(Theme.C.ink).frame(width: 24, height: 24) }
                                    Icon(.heart)
                                }
                                .foregroundStyle(Theme.C.ink)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle())
                            .sensoryFeedback(.impact(weight: .medium), trigger: on)
                            .accessibilityLabel(on ? "Von der Merkliste entfernen" : "Merken")
                        }
                    }
                } else {
                    Text("Tippe mindestens 2 Buchstaben – wir zeigen passende Angebote, oder du beobachtest den Begriff.")
                        .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 14)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.immediately)
        .sheet8()
    }
}

// MARK: Barcode-Scanner (VisionKit)

/// Vollbild-Kamera, dunkel; Rahmen-Ecken in Pastellblau, unten eine Glas-Pille mit Hinweis. Treffer → „Auf Merkliste?“.
struct BarcodeScanView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var camera: Bool?  // nil = wird geprüft
    @State private var ean: String? = Demo.screen == "scanner" ? Demo.eanProduct.ean : nil
    /// Coupon-Barcode (38a): Code128/EAN/QR, Treffer geht mit Typ zurück, kein Merklisten-Sheet.
    var coupon: ((String, String) -> Void)? = nil

    private enum L {
        static let frame = CGSize(width: 270, height: 170)
        static let hint: CGFloat = 120  // Glas-Pille über unten
    }

    var body: some View {
        ZStack {
            // shortcut: Kamera-Grund #1E1C19/#4A4640 fehlt in Theme – aus Tinte angenähert
            RadialGradient(colors: [Theme.C.ink2.opacity(0.55), Theme.C.ink], center: UnitPoint(x: 0.5, y: 0.46), startRadius: 0, endRadius: 420)
                .background(Theme.C.ink)
                .ignoresSafeArea()
            if !store.demo, camera == true {
                DataScanner(paused: ean != nil, symbologies: coupon == nil ? [.ean8, .ean13, .upce] : [.code128, .ean13, .ean8, .qr],
                            digitsOnly: coupon == nil) { code, symbology in
                    if let coupon {
                        coupon(code, Barcode.type(symbology))
                        dismiss()
                    } else if ean == nil {
                        ean = code
                    }
                }
                .ignoresSafeArea()
            } else if camera == false {
                VStack(spacing: 16) {
                    Text(DataScannerViewController.isSupported ? "Kamera ist nicht erlaubt." : "Dieses iPhone kann keine Barcodes scannen.")
                        .font(Theme.F.t2).foregroundStyle(Theme.C.onInk).multilineTextAlignment(.center)
                    if DataScannerViewController.isSupported {
                        PrimaryButton(title: "In iOS-Einstellungen öffnen", style: .blue) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .frame(maxWidth: 300)
                    }
                }
                .padding(Theme.pagePadding)
                .offset(y: 160)
            }
            ZStack {
                if store.demo || camera != true { BarcodeStripes().stroke(Theme.C.onInk.opacity(0.35), lineWidth: 3) }
                ScanCorners().stroke(Theme.C.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            .frame(width: L.frame.width, height: L.frame.height)
            .accessibilityHidden(true)
            VStack {
                HStack {
                    Text(coupon == nil ? "Barcode scannen" : "Coupon-Barcode scannen").font(Theme.F.t2).foregroundStyle(Theme.C.onInk)
                    Spacer()
                    Button { dismiss() } label: {
                        Icon(.x, size: 18).foregroundStyle(Theme.C.onInk)
                            .frame(width: Theme.S.close, height: Theme.S.close)
                            .overlay(Circle().strokeBorder(Theme.C.onInk.opacity(0.45), lineWidth: Theme.S.hair))
                            .frame(minWidth: 44, minHeight: 44).contentShape(Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Schließen")
                }
                Spacer()
                HStack(spacing: 10) {
                    Icon(.barcode, size: 18)
                    Text(coupon == nil ? "Strichcode in den Rahmen halten" : "Barcode oder QR-Code in den Rahmen halten").lineLimit(1)
                }
                .font(Theme.F.text(14, .semibold, relativeTo: .subheadline))
                .foregroundStyle(Theme.C.onInk)
                .padding(.horizontal, 20).frame(height: 48)
                .background(Theme.C.onInk.opacity(0.14), in: Capsule())
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.C.onInk.opacity(0.2), lineWidth: 1))
                .environment(\.colorScheme, .dark)
                .padding(.bottom, L.hint)
                .ignoresSafeArea(edges: .bottom)
            }
            .padding(.horizontal, Theme.pagePadding).padding(.top, 14)
        }
        .task {
            guard !store.demo else { return }
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined { _ = await AVCaptureDevice.requestAccess(for: .video) }
            camera = DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        }
        .sheet(item: Binding(get: { ean.map(ScannedCode.init) }, set: { c in ean = c?.id })) { code in
            ScanResultSheet(ean: code.id) { added in
                ean = nil
                if added { dismiss() }
            }
            .presentationDetents([.medium, .large])
        }
        .sensoryFeedback(.success, trigger: ean)
    }
}

private struct ScannedCode: Identifiable { var id: String }

/// Rahmen-Ecken (Mockup-Pfad auf 270 × 170).
private struct ScanCorners: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 270, sy = r.height / 170
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * sx, y: r.minY + y * sy) }
        var path = Path()
        path.move(to: p(4, 40)); path.addLine(to: p(4, 16)); path.addQuadCurve(to: p(16, 4), control: p(4, 4)); path.addLine(to: p(40, 4))
        path.move(to: p(230, 4)); path.addLine(to: p(254, 4)); path.addQuadCurve(to: p(266, 16), control: p(266, 4)); path.addLine(to: p(266, 40))
        path.move(to: p(266, 130)); path.addLine(to: p(266, 154)); path.addQuadCurve(to: p(254, 166), control: p(266, 166)); path.addLine(to: p(230, 166))
        path.move(to: p(40, 166)); path.addLine(to: p(16, 166)); path.addQuadCurve(to: p(4, 154), control: p(4, 166)); path.addLine(to: p(4, 130))
        return path
    }
}

/// Angedeuteter Strichcode im Rahmen (nur ohne Live-Kamera).
private struct BarcodeStripes: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 270, sy = r.height / 170
        var path = Path()
        for x: CGFloat in [70, 80, 86, 98, 104, 118, 124, 134, 146, 152, 164, 176, 182, 194, 200] {
            path.move(to: CGPoint(x: r.minX + x * sx, y: r.minY + 50 * sy))
            path.addLine(to: CGPoint(x: r.minX + x * sx, y: r.minY + 120 * sy))
        }
        return path
    }
}

/// „Auf Merkliste?“: Packung im Kreis, Nutri-Score als Ampel-Leiste, EAN und Datenquelle; unbekannt → Namen eintippen.
struct ScanResultSheet: View {
    @Environment(AppStore.self) private var store
    let ean: String
    let done: (Bool) -> Void
    @State private var product: EanProductDTO?
    @State private var error: String?
    @State private var name = ""
    @State private var saving = false

    var body: some View {
        let label = String((product?.found == true ? product!.name : name).trimmingCharacters(in: .whitespaces).prefix(200))
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Auf Merkliste?").font(Theme.F.t2)
                    Spacer()
                    CloseButton { done(false) }
                }
                if let p = product, p.found {
                    HStack(spacing: 18) {
                        Group {
                            if OfferArt.ill(p.name) != nil {
                                OfferArt(title: p.name, url: p.imageUrl).frame(width: 130, height: 130)
                            } else {
                                RemoteImage(url: URL(string: p.imageUrl)) { Ill("bag").frame(width: 90) }.frame(width: 76, height: 76)
                            }
                        }
                        .frame(width: 104, height: 104)
                        .background(Theme.C.sand, in: Circle())
                        .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 0) {
                            Text(p.name).font(Theme.F.t2).fixedSize(horizontal: false, vertical: true)
                            if !p.brand.isEmpty {
                                Text(p.brand).font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                            }
                            if let n = p.nutriScore { NutriStrip(score: n).padding(.top, 10) }
                        }
                    }
                    .padding(.top, 18)
                    VStack(spacing: 0) {
                        info("EAN") { Text(groupedEAN(p.ean)).font(Theme.F.num(16, relativeTo: .body)) }
                        info("Daten") { Text("Open Food Facts (ODbL)").font(Theme.F.text(14, .bold, relativeTo: .subheadline)) }
                    }
                    .padding(.top, 18)
                } else if product != nil || error != nil {
                    Text(error ?? "Unbekanntes Produkt (EAN \(ean)) – wie heißt es?").font(Theme.F.text(13, .semibold, relativeTo: .footnote))
                        .foregroundStyle(Theme.C.ink2).fixedSize(horizontal: false, vertical: true).padding(.top, 18)
                    FieldBox { TextField("Name, z. B. Repair Shampoo", text: $name) }.padding(.top, 12)
                } else {
                    HStack(spacing: 18) {
                        Skeleton8(width: 104, height: 104)
                        VStack(alignment: .leading, spacing: 8) { Skeleton8(height: 22); Skeleton8(width: 120, height: 14) }
                    }
                    .padding(.top, 18)
                    Text("Suche in Open Food Facts …").font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                        .padding(.top, 8)
                }
                PrimaryButton(title: saving ? "Merke …" : "Auf die Merkliste", icon: .heart, disabled: label.isEmpty || saving) {
                    saving = true
                    Task {
                        let p = product
                        let ok = await store.addWatch(WatchIn(label: label, brand: p?.found == true ? p!.brand : "", ean: ean,
                                                              imageUrl: p?.found == true ? p!.imageUrl : ""))
                        saving = false
                        if ok { done(true) }
                    }
                }
                .padding(.top, 16)
                OutlineButton(title: "Weiter scannen", icon: .barcode) { done(false) }.padding(.top, 10)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 40)
        }
        .sheet8()
        .task {
            do {
                product = try await store.product(ean: ean)
            } catch APIError.http(502) {
                error = "Open Food Facts ist gerade nicht erreichbar – gib einen Namen ein."
            } catch {
                self.error = "Produkt nicht gefunden (\(error.localizedDescription)) – gib einen Namen ein."
            }
        }
    }

    private func info(_ label: String, @ViewBuilder _ value: () -> some View) -> some View {
        HStack {
            Text(label).font(Theme.F.small).foregroundStyle(Theme.C.ink2).frame(maxWidth: .infinity, alignment: .leading)
            value().foregroundStyle(Theme.C.ink)
        }
        .frame(minHeight: 48)
        .overlay(alignment: .top) { Hairline() }
        .accessibilityElement(children: .combine)
    }

    /// „8076800195057“ → „8076 8001 9505 7“
    private func groupedEAN(_ e: String) -> String {
        stride(from: 0, to: e.count, by: 4).map { i in
            String(e.dropFirst(i).prefix(4))
        }.joined(separator: " ")
    }
}

/// Nutri-Score als Ampel-Leiste A–E, aktiver Buchstabe größer (`.c-nss`).
private struct NutriStrip: View {
    let score: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(["A", "B", "C", "D", "E"].enumerated()), id: \.offset) { i, l in
                let on = l == score
                Text(l)
                    .font(Theme.F.text(on ? 16 : 12, .extrabold, relativeTo: .caption))
                    .foregroundStyle(l == "C" ? Theme.C.onBright : Theme.C.onInk)
                    .frame(width: on ? 30 : 22, height: on ? 34 : 24)
                    .background(Theme.C.nutri[l] ?? Theme.C.line,
                                in: UnevenRoundedRectangle(topLeadingRadius: on ? 9 : i == 0 ? 7 : 0, bottomLeadingRadius: on ? 9 : i == 0 ? 7 : 0,
                                                           bottomTrailingRadius: on ? 9 : i == 4 ? 7 : 0, topTrailingRadius: on ? 9 : i == 4 ? 7 : 0))
                    .overlay {
                        if on { RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.C.bg, lineWidth: 2).padding(-2) }
                    }
                    .zIndex(on ? 1 : 0)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Nutri-Score \(score)")
    }
}


/// VisionKit `DataScannerViewController`: Merkliste EAN-8/EAN-13/UPC-E (nur Ziffern), Coupons zusätzlich Code128/QR.
struct DataScanner: UIViewControllerRepresentable {
    var paused: Bool
    var symbologies: [VNBarcodeSymbology] = [.ean8, .ean13, .upce]
    var digitsOnly = true
    let found: (String, VNBarcodeSymbology) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: symbologies)], qualityLevel: .balanced,
                                           recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        context.coordinator.digitsOnly = digitsOnly
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        context.coordinator.found = found
        if paused { vc.stopScanning() } else if !vc.isScanning { try? vc.startScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) { vc.stopScanning() }

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var found: (String, VNBarcodeSymbology) -> Void
        var digitsOnly = true

        init(found: @escaping (String, VNBarcodeSymbology) -> Void) { self.found = found }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let b) = item, let code = b.payloadStringValue, !code.isEmpty, !digitsOnly || code.allSatisfy(\.isNumber) {
                    found(code, b.observation.symbology)
                    return
                }
            }
        }
    }
}
