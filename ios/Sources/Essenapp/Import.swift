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

/// Schritt-Bild 16:10; leer = wird noch erzeugt → Schimmer.
struct StepImage: View {
    let path: String
    var dark = false

    var body: some View {
        let base = dark ? Theme.C.cookSurface : Theme.C.surface
        Color.clear
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay {
                if path.isEmpty {
                    base.modifier(Shimmer(active: true))
                } else {
                    RemoteImage(url: mediaURL(path), contentMode: .fill) { base }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
            .accessibilityLabel(path.isEmpty ? "Schritt-Bild wird erzeugt" : "Schritt-Bild")
    }
}

// MARK: S21 Teilen aus Instagram (Einstellungen)

struct InstagramShareView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var code: PairingCodeDTO?
    @State private var creating = false
    @State private var tokens: [PairedTokenDTO]?
    @State private var error: String?
    @State private var revoke: PairedTokenDTO?

    private static let steps = [
        "Unten „Code erzeugen“ tippen.",
        "In Instagram beim Reel oder Beitrag auf Teilen (Papierflieger) › „Teilen über …“ › „Essenapp“. Fehlt Essenapp, unter „Mehr“ einschalten.",
        "Beim ersten Mal Server-Adresse und Code eingeben – danach geht es mit einem Tipp.",
        "Das Rezept landet in Meine Rezepte (Filter „Importiert“).",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                DisplayHeader(line1: "Teilen aus", line2: "Instagram")
                Text("Reels und Rezept-Webseiten direkt aus dem Teilen-Menü in Meine Rezepte holen.")
                    .font(Theme.F.caption).foregroundStyle(Theme.C.text2)

                section("So geht's") {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)").font(.system(.footnote, design: .rounded, weight: .bold)).foregroundStyle(Theme.C.onAction)
                                .frame(width: 26, height: 26).background(Theme.C.action, in: Circle())
                            Text(s).font(Theme.F.body).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                section("Kopplungscode") { codeCard }
                section("Gekoppelte Geräte") { devices }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
        }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await loadTokens() }
        .task {
            if Demo.screen == "instagram" { code = try? await store.pairingCode() }
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
            Text("Die Teilen-Erweiterung muss sich danach mit einem neuen Code koppeln.")
        }
    }

    @ViewBuilder private var codeCard: some View {
        if let code {
            let expires = Self.date(code.expiresAt)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = Int(expires.timeIntervalSince(context.date))
                VStack(alignment: .leading, spacing: 10) {
                    Text(left > 0 ? "\(code.code.prefix(3)) \(code.code.suffix(3))" : "– – –  – – –")
                        .font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit().tracking(4)
                        .foregroundStyle(left > 0 ? Theme.C.text1 : Theme.C.text3)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(left > 0 ? "Code \(code.code.map(String.init).joined(separator: " "))" : "Code abgelaufen")
                    Text(left > 0 ? "gültig noch \(left / 60):\(String(format: "%02d", left % 60)) · nur einmal benutzbar" : "Code abgelaufen")
                        .font(Theme.F.caption).foregroundStyle(left > 0 ? Theme.C.text2 : Theme.C.danger).monospacedDigit()
                        .frame(maxWidth: .infinity)
                }
            }
            serverRow
            Button { Task { await create() } } label: { Text(creating ? "Erzeuge …" : "Neuen Code erzeugen") }
                .buttonStyle(SecondaryButtonStyle()).disabled(creating)
        } else {
            Text("Der Code ist 10 Minuten gültig und koppelt ein Gerät mit deinem Konto.").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            serverRow
            Button { Task { await create() } } label: { Label(creating ? "Erzeuge …" : "Code erzeugen", systemImage: "key.fill") }
                .buttonStyle(PrimaryButtonStyle()).disabled(creating)
        }
    }

    /// Die Erweiterung kennt die Server-Adresse der App nicht (kein geteilter Speicher, E48) → hier zum Abtippen/Kopieren.
    private var serverRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Server-Adresse").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                Text(store.api.baseURL.isEmpty ? "nicht eingestellt" : store.api.baseURL)
                    .font(.system(.callout, design: .monospaced, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            Button {
                UIPasteboard.general.string = store.api.baseURL
                store.flash("Adresse kopiert")
            } label: {
                Label("Kopieren", systemImage: "doc.on.doc").font(Theme.F.callout)
                    .padding(.horizontal, 12).frame(minHeight: 44).background(Theme.C.surface, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .disabled(store.api.baseURL.isEmpty)
        }
        .padding(12)
        .background(Theme.C.bg, in: RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
    }

    @ViewBuilder private var devices: some View {
        if let tokens {
            if tokens.isEmpty {
                Text("Noch kein Gerät gekoppelt.").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            }
            ForEach(tokens) { t in
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.C.accent)
                        .frame(width: 34, height: 34).background(Theme.C.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.label).font(.system(.body, weight: .semibold))
                        Text("gekoppelt am \(shortDate(t.createdAt))").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                    }
                    Spacer()
                    Button("Widerrufen", role: .destructive) { revoke = t }
                        .font(Theme.F.callout).frame(minHeight: 44)
                }
            }
        } else if let error {
            ErrorState(message: error) { Task { await loadTokens() } }
        } else {
            SkeletonCard(height: 52)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Theme.F.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .appear()
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

// MARK: Nährwerte im Angebotsdetail (2)

/// Pro 100 g / pro Packung, nur bei sicherer Zuordnung; „pending“ → Schimmer und später neu laden; „none“ → nichts.
struct OfferNutritionCard: View {
    @Environment(AppStore.self) private var store
    let offer: OfferDTO
    @State private var data: OfferNutritionDTO?
    @State private var perPack = false

    var body: some View {
        VStack(spacing: 0) {
            if let d = data, d.status != "none" {
                let values = perPack ? d.perPack : d.per100g
                VStack(alignment: .leading, spacing: 12) {
                    Text("Nährwerte").font(Theme.F.headline)
                    if d.perPack != nil {
                        PillSegment(options: [(false, "pro 100 g"), (true, "pro Packung\(offer.amountText.map { a in " (\(a))" } ?? "")")],
                                    selection: $perPack)
                    }
                    HStack(spacing: 8) {
                        if let n = values {
                            NutrientTile(nutrient: .kcal, value: "\(Int(n.kcal.rounded()))")
                            NutrientTile(nutrient: .protein, value: "\(num(n.protein)) g")
                            NutrientTile(nutrient: .carbs, value: "\(num(n.carbs)) g")
                            NutrientTile(nutrient: .fat, value: "\(num(n.fat)) g")
                        } else {
                            ForEach(0..<4, id: \.self) { _ in SkeletonCard(height: 92) }
                        }
                    }
                    .animation(Theme.spring, value: perPack)
                    Text(d.status == "pending" ? "Nährwerte werden zugeordnet …" : "Quelle: USDA FoodData Central · „\(d.food)“")
                        .font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                }
                .padding(16)
                .card()
                .transition(.opacity)
            }
        }
        .task(id: offer.id) { await load() }
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
