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
    @State private var loaded = false
    @State private var error: String?
    @State private var editing: WatchDTO?
    @State private var searching = false
    @State private var newAlarm = false

    var body: some View {
        let cheap = store.watches.filter { w in w.kind == "produkt" && !w.hits.isEmpty }
        let watched = store.watches.filter { w in w.kind == "produkt" && w.hits.isEmpty }
        let alarms = store.watches.filter { w in w.kind == "zutat" }
        VStack(alignment: .leading, spacing: 14) {
            if store.watches.isEmpty {
                if !loaded && !store.demo {
                    ForEach(0..<3, id: \.self) { _ in SkeletonCard(height: 72) }
                } else if let error {
                    ErrorState(message: error) { Task { await load() } }
                } else {
                    EmptyState(emoji: "🤍", title: "Noch nichts gemerkt",
                               text: "Merk dir Lieblingsprodukte – wir sagen Bescheid, wenn sie im Angebot sind.")
                }
            }
            if !cheap.isEmpty {
                header("🔥", "Diese Woche günstig")
                ForEach(Array(cheap.enumerated()), id: \.element.id) { i, w in hitRow(w).appear(delay: Double(i) * 0.04) }
            }
            if !watched.isEmpty {
                header("👀", "Beobachtet")
                ForEach(Array(watched.enumerated()), id: \.element.id) { i, w in watchRow(w).appear(delay: Double(i) * 0.04) }
            }
            HStack {
                header("🔔", "Preisalarme")
                Spacer()
                Button { newAlarm = true } label: { Label("Zutat", systemImage: "plus").font(Theme.F.callout).frame(minHeight: 44) }
                    .accessibilityLabel("Preisalarm für eine Zutat anlegen")
            }
            if alarms.isEmpty {
                Text("Z. B. „Butter unter 1,49 €“ oder „Hähnchenbrust unter 7 €/kg“ – auch per langem Druck auf eine Rezept-Zutat.")
                    .font(Theme.F.caption).foregroundStyle(Theme.C.text2).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(alarms.enumerated()), id: \.element.id) { i, w in alarmRow(w).appear(delay: Double(i) * 0.04) }
            HStack(spacing: 10) {
                Button { searching = true } label: { Label("Suchen", systemImage: "magnifyingglass") }
                    .buttonStyle(SecondaryButtonStyle())
                Button { store.barcode = true } label: { Label("Barcode scannen", systemImage: "barcode.viewfinder") }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.top, 6)
        }
        .animation(Theme.spring, value: store.watches)
        .task { await load() }
        .sheet(item: $editing) { w in WatchSheet(watch: w).presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
        .sheet(isPresented: $newAlarm) { WatchSheet(ingredient: "").presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
        .sheet(isPresented: $searching) { WatchSearchSheet().presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet) }
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

    private func header(_ emoji: String, _ title: String) -> some View {
        Label { Text(title).font(Theme.F.headline) } icon: { Text(emoji) }.padding(.top, 4)
    }

    private func thumb(_ w: WatchDTO, _ url: String) -> some View {
        let hue = Theme.hue(category: w.category)
        return RemoteImage(url: URL(string: url)) { Text(w.kind == "zutat" ? "🔔" : hue.emoji).font(.system(size: 24)) }
            .padding(6).frame(width: 52, height: 52).background(hue.tint, in: RoundedRectangle(cornerRadius: 14))
    }

    /// „Diese Woche günstig“: bester Preis + Laden, Rabatt, → Angebot.
    private func hitRow(_ w: WatchDTO) -> some View {
        let o = w.hits[0]
        return NavigationLink { OfferDetailView(offer: o) } label: {
            HStack(spacing: 12) {
                thumb(w, o.imageUrl.isEmpty ? w.imageUrl : o.imageUrl)
                VStack(alignment: .leading, spacing: 3) {
                    Text(w.label).font(.system(.subheadline, weight: .semibold)).foregroundStyle(Theme.C.text1).lineLimit(1)
                    HStack(spacing: 6) {
                        Text("\(euro(o.priceCents)) bei \(Labels.chain(o.chain))").font(Theme.F.micro).monospacedDigit()
                            .foregroundStyle(Theme.C.text2)
                        DealBadge(text: o.discount.map { d in "−\(d) %" } ?? "Angebot")
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.C.text3)
            }
            .padding(10)
            .card(radius: Theme.R.tile)
        }
        .buttonStyle(PressableStyle())
        .contextMenu { menu(w) }
    }

    /// „Beobachtet“: Wunschpreis, Verbrauchsrhythmus.
    private func watchRow(_ w: WatchDTO) -> some View {
        let parts = [w.alarmText.map { a in "Alarm \(a)" }, w.lastsWeeks.map { n in "hält ca. \(num(n)) Wochen" },
                     w.emptyOn.map { d in "leer ca. \(shortDate(d))" }].compactMap { s in s }
        return Button { editing = w } label: {
            HStack(spacing: 12) {
                thumb(w, w.imageUrl)
                VStack(alignment: .leading, spacing: 3) {
                    Text(w.brand.isEmpty ? w.label : "\(w.label) · \(w.brand)").font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.C.text1).lineLimit(1)
                    Text(parts.isEmpty ? "gerade nicht im Angebot" : parts.joined(separator: " · "))
                        .font(Theme.F.micro).foregroundStyle(Theme.C.text2).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.C.text3)
            }
            .padding(10)
            .card(radius: Theme.R.tile)
        }
        .buttonStyle(PressableStyle())
        .contextMenu { menu(w) }
    }

    /// „Preisalarme“ (Zutat): „Butter unter 1,49 €“, greift → Angebot.
    private func alarmRow(_ w: WatchDTO) -> some View {
        Button { editing = w } label: {
            HStack(spacing: 12) {
                thumb(w, "")
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(w.label) \(w.alarmText ?? "")").font(.system(.subheadline, weight: .semibold))
                        .foregroundStyle(Theme.C.text1).lineLimit(1)
                    if let o = w.hits.first {
                        Text("greift: \(euro(o.priceCents)) bei \(Labels.chain(o.chain)) – \(o.title)").font(Theme.F.micro)
                            .foregroundStyle(Theme.C.success).lineLimit(1)
                    } else {
                        Text("wartet auf ein passendes Angebot").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.C.text3)
            }
            .padding(10)
            .card(radius: Theme.R.tile)
        }
        .buttonStyle(PressableStyle())
        .contextMenu { menu(w) }
    }

    @ViewBuilder private func menu(_ w: WatchDTO) -> some View {
        Button("Bearbeiten", systemImage: "slider.horizontal.3") { editing = w }
        Button("Entfernen", systemImage: "trash", role: .destructive) { Task { await store.deleteWatch(w) } }
    }
}

// MARK: Eintrag bearbeiten / Preisalarm anlegen

/// Wunschpreis (Packung oder Grundpreis), Läden, „Hält ca. X Wochen“ + „zuletzt gekauft“ (58). Ohne `watch`: neuer
/// Preisalarm für eine Zutat (40), Name aus `ingredient`.
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
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(watch == nil ? "Preisalarm" : watch!.label).font(Theme.F.title).lineLimit(2)
                        Text(isProduct ? (watch!.brand.isEmpty ? "Merkliste" : watch!.brand) : "Für eine Zutat – jede passende Marke und Packung")
                            .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                    }
                    Spacer()
                    RoundIconButton(systemName: "xmark", label: "Schließen") { dismiss() }
                }
                if watch == nil {
                    TextField("Zutat, z. B. Butter", text: $name)
                        .padding(12).background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.chip))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label { Text("Wunschpreis").font(Theme.F.headline) } icon: { Text("🔔") }
                    HStack(spacing: 10) {
                        Text("unter").font(Theme.F.callout).foregroundStyle(Theme.C.text2)
                        TextField(isProduct ? "optional, z. B. 2,00" : "z. B. 1,49", text: $price).keyboardType(.decimalPad)
                            .font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                            .padding(.horizontal, 12).frame(height: 44).background(Theme.C.surface, in: Capsule())
                        Text("€").font(Theme.F.callout)
                    }
                    Picker("Bezug", selection: $basis) {
                        Text("Packung").tag(""); Text("pro kg").tag("kg"); Text("pro l").tag("l"); Text("pro Stück").tag("stk")
                    }
                    .pickerStyle(.segmented)
                    Text(basis.isEmpty ? "Alarm, wenn eine Packung darunter im Angebot ist."
                                       : "Grundpreis-Alarm: gilt für jede Packungsgröße (g → kg, ml → l).")
                        .font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                }
                .padding(16).card()
                VStack(alignment: .leading, spacing: 10) {
                    Label { Text("Läden").font(Theme.F.headline) } icon: { Text("🏪") }
                    ChipFlow(items: [("", "Alle")] + household.map { c in (c, Labels.chain(c)) },
                             selected: chains.isEmpty ? [""] : chains, color: Theme.C.accent) { c in
                        if c.isEmpty { chains = [] } else { chains.formSymmetricDifference([c]) }
                    }
                }
                .padding(16).card()
                if isProduct, let w = watch {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $rhythm.animation(Theme.spring)) {
                            Label { Text("Verbrauchsrhythmus").font(Theme.F.headline) } icon: { Text("🔁") }
                        }
                        if rhythm {
                            HStack {
                                Text("Hält ca. \(weeks) \(weeks == 1 ? "Woche" : "Wochen")").font(Theme.F.callout)
                                    .contentTransition(.numericText())
                                Spacer()
                                Stepper("Wochen", value: $weeks, in: 1...52).labelsHidden()
                            }
                            .sensoryFeedback(.selection, trigger: weeks)
                            if let s = w.lastsWeeksSuggestion {
                                Text("Vorschlag: \(num(s)) Wochen").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                            }
                            Toggle("Zuletzt gekauft", isOn: $bought.animation(Theme.spring)).font(Theme.F.callout)
                            if bought { DatePicker("am", selection: $boughtDate, in: ...Date.now, displayedComponents: .date) }
                            Text("Wird automatisch gesetzt, wenn du es auf der Liste abhakst. 2 Wochen vor „leer“ melden wir Angebote, 3 Tage vorher kommt es auf die Liste.")
                                .font(Theme.F.micro).foregroundStyle(Theme.C.text2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Theme.C.accent)
                    .padding(16).card()
                }
                Button(action: save) { Text(saving ? "Speichere …" : watch == nil ? "Preisalarm anlegen" : "Speichern") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!valid || saving).opacity(valid ? 1 : 0.5)
                if let w = watch {
                    Button("Entfernen", role: .destructive) {
                        Task { await store.deleteWatch(w); dismiss() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(Theme.pagePadding)
        }
        .scrollDismissesKeyboard(.immediately)
        .presentationBackground(Theme.C.bg)
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

/// „Suchen“: Angebote der Woche merken oder ein Produkt per Freitext beobachten.
struct WatchSearchSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let found = q.count < 2 ? [] : Array(store.offers.filter { o in o.title.localizedCaseInsensitiveContains(q) || o.brand.localizedCaseInsensitiveContains(q) }.prefix(30))
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Produkt merken").font(Theme.F.title)
                    Spacer()
                    RoundIconButton(systemName: "xmark", label: "Schließen") { dismiss() }
                }
                SearchField(text: $query, placeholder: "Name oder Marke, z. B. Shampoo")
                if q.count >= 2 {
                    Button {
                        Task { if await store.addWatch(WatchIn(label: String(q.prefix(200)))) { dismiss() } }
                    } label: { Label("„\(q)“ beobachten", systemImage: "eye") }
                    .buttonStyle(PrimaryButtonStyle())
                    if !found.isEmpty { Text("Diese Woche im Angebot").font(Theme.F.headline).padding(.top, 4) }
                    ForEach(found) { o in
                        let on = store.watch(for: o) != nil
                        HStack(spacing: 8) {
                            OfferRow(offer: o)
                            Button { Task { await store.toggleWatch(o) } } label: {
                                Image(systemName: on ? "heart.fill" : "heart").font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(on ? Theme.C.accent : Theme.C.text1).frame(width: 44, height: 44)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .buttonStyle(PressableStyle())
                            .sensoryFeedback(.impact(weight: .medium), trigger: on)
                            .accessibilityLabel(on ? "Von der Merkliste entfernen" : "Merken")
                        }
                    }
                } else {
                    Text("Tippe mindestens 2 Buchstaben – wir zeigen passende Angebote, oder du beobachtest den Begriff.")
                        .font(Theme.F.caption).foregroundStyle(Theme.C.text2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.pagePadding)
        }
        .scrollDismissesKeyboard(.immediately)
        .presentationBackground(Theme.C.bg)
    }
}

// MARK: Barcode-Scanner (VisionKit)

/// Vollbild-Kamera mit Orange-Eckrahmen; Treffer → Open Food Facts → Sheet „Auf Merkliste?“.
struct BarcodeScanView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var camera: Bool?  // nil = wird geprüft
    @State private var ean: String? = Demo.screen == "scanner" ? Demo.eanProduct.ean : nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if store.demo {
                HeroImage(name: "table").ignoresSafeArea().overlay(Color.black.opacity(0.35).ignoresSafeArea())
            } else if camera == true {
                DataScanner(paused: ean != nil) { code in if ean == nil { ean = code } }.ignoresSafeArea()
            } else if camera == false {
                VStack(spacing: 12) {
                    Text("📷").font(.system(size: 44))
                    Text(DataScannerViewController.isSupported ? "Kamera ist nicht erlaubt." : "Dieses iPhone kann keine Barcodes scannen.")
                        .font(Theme.F.headline).foregroundStyle(.white)
                    if DataScannerViewController.isSupported {
                        Button("In iOS-Einstellungen öffnen") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                            .buttonStyle(SecondaryButtonStyle()).frame(maxWidth: 280)
                    }
                }
                .padding(Theme.pagePadding)
            }
            CornerFrame().stroke(Theme.C.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 270, height: 170)
                .accessibilityHidden(true)
            VStack {
                HStack {
                    Text("Barcode scannen").font(Theme.F.headline).foregroundStyle(.white)
                    Spacer()
                    RoundIconButton(systemName: "xmark", label: "Schließen") { dismiss() }
                }
                Spacer()
                Text("Strichcode in den Rahmen halten").font(Theme.F.callout).foregroundStyle(Theme.C.text1)
                    .padding(.horizontal, 16).frame(minHeight: 40).glass(Capsule())
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, Theme.pagePadding).padding(.top, 8)
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
            .presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet)
        }
        .sensoryFeedback(.success, trigger: ean)
    }
}

private struct ScannedCode: Identifiable { var id: String }

/// „Auf Merkliste?“: Produkt aus Open Food Facts (Name, Marke, Bild, Nutri-Score); unbekannt → Namen eintippen.
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Auf Merkliste?").font(Theme.F.title)
            if let p = product, p.found {
                HStack(spacing: 14) {
                    RemoteImage(url: URL(string: p.imageUrl)) { Text("🛒").font(.system(size: 30)) }
                        .padding(6).frame(width: 72, height: 72).background(Theme.C.imageBg, in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.name).font(Theme.F.headline).fixedSize(horizontal: false, vertical: true)
                        if !p.brand.isEmpty { Text(p.brand).font(Theme.F.caption).foregroundStyle(Theme.C.text2) }
                        HStack(spacing: 6) {
                            if let n = p.nutriScore { NutriBadge(score: n) }
                            Text("EAN \(p.ean)").font(Theme.F.micro).foregroundStyle(Theme.C.text3)
                        }
                    }
                }
                Text("Daten: Open Food Facts (ODbL)").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
            } else if product != nil || error != nil {
                Text(error ?? "Unbekanntes Produkt (EAN \(ean)) – wie heißt es?").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Name, z. B. Repair Shampoo", text: $name)
                    .padding(12).background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.chip))
            } else {
                SkeletonCard(height: 84)
                Text("Suche in Open Food Facts …").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
            }
            Button {
                saving = true
                Task {
                    let p = product
                    let ok = await store.addWatch(WatchIn(label: label, brand: p?.found == true ? p!.brand : "", ean: ean,
                                                          imageUrl: p?.found == true ? p!.imageUrl : ""))
                    saving = false
                    if ok { done(true) }
                }
            } label: { Text(saving ? "Merke …" : "Auf die Merkliste") }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(label.isEmpty || saving).opacity(label.isEmpty ? 0.5 : 1)
            Button("Weiter scannen") { done(false) }.buttonStyle(SecondaryButtonStyle())
        }
        .padding(Theme.pagePadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationBackground(Theme.C.bg)
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
}

/// VisionKit `DataScannerViewController` für EAN-8/EAN-13/UPC-E.
struct DataScanner: UIViewControllerRepresentable {
    var paused: Bool
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean8, .ean13, .upce])], qualityLevel: .balanced,
                                           recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        context.coordinator.found = found
        if paused { vc.stopScanning() } else if !vc.isScanning { try? vc.startScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) { vc.stopScanning() }

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var found: (String) -> Void

        init(found: @escaping (String) -> Void) { self.found = found }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let b) = item, let code = b.payloadStringValue, code.allSatisfy(\.isNumber) {
                    found(code)
                    return
                }
            }
        }
    }
}
