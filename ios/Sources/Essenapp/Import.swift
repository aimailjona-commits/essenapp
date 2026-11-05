import EssenappShareUI
import SwiftUI

// Rezept-Import (5): Kopplung der Teilen-Erweiterung (S21), „Link einfügen“ (S22); Schritt-Bilder (9); Angebots-Nährwerte (2).

struct PairingCodeDTO: Decodable {
    var code: String
    var expiresAt: String  // Server-Ortszeit, ohne Zeitzone
}

struct PairedTokenDTO: Decodable, Identifiable, Hashable {
    var id: Int
    var label: String
    var createdAt: String
}

struct StepImagesDTO: Decodable {
    var stepImages: [String]
    var pending: Bool
}

struct OfferNutritionDTO: Decodable {
    var status: String  // ok | pending | none
    var food: String
    var per100g: NutritionDTO?
    var perPack: NutritionDTO?
}

/// `convertFromSnakeCase` macht aus „per_100g“ per `capitalized` „per100G“ – ohne eigene Schlüssel bliebe `per100g` immer nil
/// (iPhone: grauer Platzhalter statt Werten). Beide Schreibweisen annehmen; im Extension, damit der Memberwise-Init bleibt.
extension OfferNutritionDTO {
    private enum Keys: String, CodingKey { case status, food, perPack, per100g, per100G }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        status = try c.decode(String.self, forKey: .status)
        food = try c.decodeIfPresent(String.self, forKey: .food) ?? ""
        per100g = try c.decodeIfPresent(NutritionDTO.self, forKey: .per100G) ?? c.decodeIfPresent(NutritionDTO.self, forKey: .per100g)
        perPack = try c.decodeIfPresent(NutritionDTO.self, forKey: .perPack)
    }
}

extension AppStore {
    func pairingCode() async throws -> PairingCodeDTO {
        if demo { return PairingCodeDTO(code: "482913", expiresAt: Date.now.addingTimeInterval(9 * 60 + 12).formatted(.iso8601)) }
        return try await api.request("POST", "/me/pairing-code")
    }

    func pairedTokens() async throws -> [PairedTokenDTO] {
        demo ? Demo.pairedTokens : try await api.request("GET", "/me/tokens")
    }

    func revokeToken(_ id: Int) async -> Bool {
        do {
            if !demo { try await api.send("DELETE", "/me/tokens/\(id)") }
            flash("Kopplung widerrufen")
            return true
        } catch {
            flash("Nicht widerrufen: \(error.localizedDescription)")
            return false
        }
    }

    /// Fehlende Schritt-Bilder anfordern (startet die Erzeugung, nie doppelt); 422 = aus oder nicht eingerichtet.
    func stepImages(_ recipeId: Int) async throws -> StepImagesDTO {
        try await api.request("POST", "/recipes/\(recipeId)/step-images")
    }

    func setStepImages(_ on: Bool) async {
        do {
            if demo { household?.stepImages = on } else { try await save(HouseholdPatch(stepImages: on)) }
        } catch {
            flash("Nicht gespeichert: \(error.localizedDescription)")
        }
    }

    var stepImagesOn: Bool { household?.stepImagesAvailable == true && household?.stepImages != false }

    func offerNutrition(_ id: Int) async throws -> OfferNutritionDTO {
        if demo {
            guard id == Demo.offers[0].id else { return OfferNutritionDTO(status: "none", food: "", per100g: nil, perPack: nil) }
            return Demo.offerNutrition
        }
        return try await api.request("GET", "/offers/\(id)/nutrition")
    }

    /// Anmeldung der App für die geteilte Import-Oberfläche („Link einfügen“).
    var shareSession: ShareSession { ShareSession(server: api.baseURL, token: api.token ?? "") }
}

/// Schritt-Bild 16:10; leer = wird noch erzeugt → schimmernder Platzhalter (`.sk`).
struct StepImage: View {
    let path: String
    var dark = false  // früher Kochmodus dunkel; v8 ist überall hell

    var body: some View {
        Color.clear
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay {
                if path.isEmpty {
                    Skeleton8(height: 400)
                } else {
                    RemoteImage(url: mediaURL(path), contentMode: .fill) { Theme.C.card }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
            .accessibilityLabel(path.isEmpty ? "Schritt-Bild wird erzeugt" : "Schritt-Bild")
    }
}

// MARK: S21 Teilen aus Instagram / S38 Widget einrichten (e.html) – gleiche Kopplung (E53/E83)

struct InstagramShareView: View {
    var widget = false
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var code: PairingCodeDTO?
    @State private var creating = false
    @State private var tokens: [PairedTokenDTO]?
    @State private var error: String?
    @State private var revoke: PairedTokenDTO?
    @State private var showDevices = false

    private static let steps = [
        "Unten „Neuen Code erzeugen“ tippen.",
        "In Instagram Teilen › „Teilen über …“ › Essenapp – ggf. unter „Mehr“ einschalten.",
        "Beim ersten Mal Server-Adresse und Code eintragen.",
        "Das Rezept landet in Meine Rezepte.",
    ]
    private static let widgetSteps = [
        "„Code erzeugen“ tippen.",
        "Home-Bildschirm lange drücken › Bearbeiten › Widget hinzufügen › Essenapp.",
        "Widget lange drücken › Widget bearbeiten › Server-Adresse und Code eintragen.",
        "Lädt selbst etwa alle 30 Minuten; weitere Widgets brauchen nur die Adresse.",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button { dismiss() } label: { Icon(.back).frame(width: 44, height: 44, alignment: .leading) }
                    .buttonStyle(PressableStyle()).accessibilityLabel("Zurück")
                Text(widget ? "Widget\neinrichten" : "Teilen aus\nInstagram").font(Theme.F.t1).padding(.top, 0)
                Text(widget ? "Gericht und offene Artikel – klein, mittel oder auf dem Sperrbildschirm."
                            : "Rezepte aus Reels landen direkt in Meine Rezepte.")
                    .font(Theme.F.text(14, .semibold, relativeTo: .subheadline)).lineSpacing(4).foregroundStyle(Theme.C.ink2)
                    .frame(width: widget ? 190 : 200, alignment: .leading).padding(.top, 6)
                SectionLabel("So geht's").padding(.top, 28).padding(.bottom, 4)
                ForEach(Array((widget ? Self.widgetSteps : Self.steps).enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("\(i + 1)").font(Theme.F.num(24)).tracking(Theme.F.numTracking(24)).frame(width: 20, alignment: .leading)
                        Text(s).font(Theme.F.text(13, .semibold, relativeTo: .footnote)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7)
                    .overlay(alignment: .top) { Hairline() }
                }
                codeBlock
                serverRow
                devices.padding(.top, 28)
            }
            .foregroundStyle(Theme.C.ink)
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 4)
            .padding(.bottom, 120)
        }
        .backdrop8 {
            if widget {
                Color.clear
                    .pinned(right: 6, top: 84) { Ill("table").frame(width: 150) }
                    .edgeForm(.leaf(120), Theme.C.sage, width: 170, height: 250, right: 0, top: 0)
            } else {
                Color.clear
                    .pinned(right: 20, top: 62) { Ill("cookbook").frame(width: 116) }
                    .edgeForm(.circle, Theme.C.blue1, width: 320, height: 320, right: -110, top: -110)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await loadTokens() }
        .task {
            if ["instagram", "widgetsetup"].contains(Demo.screen ?? "") && !widget { code = try? await store.pairingCode() }
            await loadTokens()
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await loadTokens() } } }  // zurück aus Instagram
        .confirmationDialog("Kopplung widerrufen?", isPresented: Binding(get: { revoke != nil }, set: { on in if !on { revoke = nil } }),
                            titleVisibility: .visible, presenting: revoke) { t in
            Button("Widerrufen", role: .destructive) {
                Task {
                    if await store.revokeToken(t.id) { withAnimation(Theme.spring) { tokens?.removeAll { x in x.id == t.id } } }
                }
            }
        } message: { _ in
            Text("Das Gerät muss sich danach mit einem neuen Code koppeln.")
        }
    }

    /// Mit Code: riesige Zahl mit Restzeit und „neu“ (S21); ohne: „Code erzeugen“ (S38).
    @ViewBuilder private var codeBlock: some View {
        if let code {
            let expires = Self.date(code.expiresAt)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = Int(expires.timeIntervalSince(context.date))
                VStack(spacing: 8) {
                    StatNumber(label: "Kopplungs-\ncode", value: left > 0 ? "\(code.code.prefix(3)) \(code.code.suffix(3))" : "––– –––",
                               size: 60, mute: left <= 0)
                        .accessibilityLabel(left > 0 ? "Kopplungscode \(code.code.map(String.init).joined(separator: " "))" : "Code abgelaufen")
                    HStack {
                        Text(left > 0 ? "gültig noch \(left / 60):\(String(format: "%02d", left % 60)) · nur einmal benutzbar" : "Code abgelaufen")
                            .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(left > 0 ? Theme.C.ink2 : Theme.C.deal)
                            .monospacedDigit()
                        Spacer()
                        if creating {
                            Hop3().frame(width: 60)
                        } else {
                            CircleButton(icon: .refresh, label: "Neuen Code erzeugen") { Task { await create() } }
                        }
                    }
                }
            }
            .padding(.top, 28)
        } else {
            PrimaryButton(title: creating ? "Erzeuge …" : "Code erzeugen", icon: .link, disabled: creating) { Task { await create() } }
                .padding(.top, 28)
        }
    }

    /// Die Erweiterung kennt die Server-Adresse der App nicht (kein geteilter Speicher, E48) → hier zum Abtippen/Kopieren.
    private var serverRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Server-Adresse").font(Theme.F.text(15, .bold))
                Text(store.api.baseURL.isEmpty ? "nicht eingestellt" : store.api.baseURL)
                    .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            Button {
                UIPasteboard.general.string = store.api.baseURL
                store.flash("Adresse kopiert")
            } label: {
                Pill8(text: "Kopieren", icon: .copy).frame(minHeight: 44).contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .disabled(store.api.baseURL.isEmpty)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 42)
        .overlay(alignment: .top) { Hairline() }
        .padding(.top, 8)
    }

    /// „Gekoppelte Geräte“ als eine Zeile; aufgeklappt die Liste mit Widerrufen.
    @ViewBuilder private var devices: some View {
        if let tokens {
            VStack(spacing: 0) {
                Button { withAnimation(Theme.spring) { showDevices.toggle() } } label: {
                    HStack(spacing: 12) {
                        Icon(widget ? .widget : .share, size: 18)
                            .frame(width: 32, height: 32).background(widget ? Theme.C.blue1 : Theme.C.rose, in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Gekoppelte Geräte").font(Theme.F.text(15, .bold))
                            Text(tokens.isEmpty ? "Noch kein Gerät gekoppelt" : tokens.map(\.label).joined(separator: ", "))
                                .font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2).lineLimit(1)
                        }
                        Spacer()
                        Text("\(tokens.count)").font(Theme.F.text(14, .semibold)).foregroundStyle(Theme.C.ink2)
                        Icon(.chev, size: 18).foregroundStyle(Theme.C.ink3).rotationEffect(.degrees(showDevices ? 90 : 0))
                    }
                    .padding(.vertical, 4)
                    .frame(minHeight: 44)
                    .overlay(alignment: .top) { Hairline() }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .disabled(tokens.isEmpty)
                if showDevices {
                    ForEach(tokens) { t in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.label).font(Theme.F.text(15, .bold))
                                Text("gekoppelt am \(shortDate(t.createdAt))").font(Theme.F.text(12, .semibold, relativeTo: .caption))
                                    .foregroundStyle(Theme.C.ink2)
                            }
                            Spacer()
                            Button("Widerrufen") { revoke = t }
                                .font(Theme.F.text(14, .extrabold)).foregroundStyle(Theme.C.deal).frame(minHeight: 44)
                        }
                        .padding(.leading, 44)
                        .overlay(alignment: .top) { Hairline() }
                        .transition(.opacity)
                    }
                }
            }
        } else if let error {
            StateNote8.error(error) { Task { await loadTokens() } }
        } else {
            Skeleton8(height: 42)
        }
    }

    private func create() async {
        creating = true
        defer { creating = false }
        do {
            let new = try await store.pairingCode()
            withAnimation(Theme.spring) { code = new }
        } catch {
            store.flash("Kein Code: \(error.localizedDescription)")
        }
    }

    private func loadTokens() async {
        do {
            let found = try await store.pairedTokens()
            withAnimation(Theme.spring) { tokens = found }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// „2026-11-02T18:30:00.123456“ (Server-Ortszeit) → Date; Fallback: 10 min ab jetzt.
    static func date(_ iso: String) -> Date {
        if let d = try? Date(iso, strategy: .iso8601) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.date(from: String(iso.prefix(19))) ?? .now.addingTimeInterval(600)
    }
}

// MARK: Nährwerte im Angebotsdetail (2) – S9 (c.html)

/// Pro 100 g / pro Packung, nur bei sicherer Zuordnung; „pending“ → Platzhalter und später neu laden; „none“ → nichts.
struct OfferNutritionCard: View {
    @Environment(AppStore.self) private var store
    let offer: OfferDTO
    @State private var data: OfferNutritionDTO?
    @State private var perPack = false

    var body: some View {
        VStack(spacing: 0) {
            if let d = data, d.status != "none" {
                let values = perPack ? d.perPack : d.per100g
                VStack(alignment: .leading, spacing: 0) {
                    Text("Nährwerte").font(Theme.F.t2)
                    if d.perPack != nil {
                        Segmented8(options: [(false, "pro 100 g"), (true, "pro Packung\(offer.amountText.map { a in " (\(a))" } ?? "")")],
                                   selection: $perPack)
                            .padding(.top, 12)
                    }
                    HStack(alignment: .bottom, spacing: 14) {
                        if let n = values {
                            StatNumber(label: "kcal", value: "\(Int(n.kcal.rounded()))", size: 44).frame(width: 120)
                            small("Protein", "\(num(n.protein)) g")
                            small("KH", "\(num(n.carbs)) g")
                            small("Fett", "\(num(n.fat)) g")
                        } else if d.status == "pending" {
                            Skeleton8(height: 56)
                        }
                    }
                    .padding(.top, 18)
                    .animation(Theme.spring, value: perPack)
                    Text(d.status == "pending" ? "Nährwerte werden zugeordnet …" : "Quelle: USDA FoodData Central · „\(d.food)“")
                        .font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2).padding(.top, 8)
                }
                .foregroundStyle(Theme.C.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
        }
        .task(id: offer.id) { await load() }
    }

    private func small(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
            Text(value).font(Theme.F.text(17, .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        var wait = 3.0
        for _ in 0..<4 {  // pending: Zuordnung läuft im Hintergrund → mit wachsendem Abstand nachfragen
            guard let d = try? await store.offerNutrition(offer.id) else { return }
            withAnimation(Theme.spring) { data = d }
            guard d.status == "pending" else { return }
            try? await Task.sleep(for: .seconds(wait))
            wait *= 2
        }
    }
}
