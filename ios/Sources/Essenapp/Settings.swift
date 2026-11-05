import MapKit
import SwiftUI

// MARK: - Bausteine aus e.html (Einstellungen, Onboarding, Profil)

/// Zusatz-Icons aus e.html (`#e-…`), Strich 1.8 auf 24er-Raster wie `Icon`.
struct EIcon: View {
    enum Kind { case alert, nope, cup }

    let kind: Kind
    var size: CGFloat = 18

    var body: some View {
        path.stroke(style: StrokeStyle(lineWidth: Theme.S.iconStroke, lineCap: .round, lineJoin: .round))
            .overlay { if kind == .alert { Circle().frame(width: 1.4, height: 1.4).position(x: 12, y: 17) } }
            .frame(width: 24, height: 24)
            .scaleEffect(size / 24)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var path: Path {
        var p = Path()
        switch kind {
        case .alert:  // M12 4 21 19.5H3z M12 10v4.5
            p.move(to: CGPoint(x: 12, y: 4)); p.addLine(to: CGPoint(x: 21, y: 19.5)); p.addLine(to: CGPoint(x: 3, y: 19.5)); p.closeSubpath()
            p.move(to: CGPoint(x: 12, y: 10)); p.addLine(to: CGPoint(x: 12, y: 14.5))
        case .nope:  // Kreis r 8.5, Strich 6,6 → 18,18
            p.addEllipse(in: CGRect(x: 3.5, y: 3.5, width: 17, height: 17))
            p.move(to: CGPoint(x: 6, y: 6)); p.addLine(to: CGPoint(x: 18, y: 18))
        case .cup:  // Tasse mit Henkel und zwei Dampf-Wellen
            p.move(to: CGPoint(x: 5, y: 9)); p.addLine(to: CGPoint(x: 16, y: 9)); p.addLine(to: CGPoint(x: 16, y: 14))
            p.addArc(center: CGPoint(x: 11, y: 14), radius: 5, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: CGPoint(x: 10, y: 19))
            p.addArc(center: CGPoint(x: 10, y: 14), radius: 5, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            p.closeSubpath()
            p.move(to: CGPoint(x: 16, y: 10.5)); p.addLine(to: CGPoint(x: 17.5, y: 10.5))
            p.addArc(center: CGPoint(x: 17.5, y: 13), radius: 2.5, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: CGPoint(x: 16, y: 15.5))
            for x in [8.5, 12.0] {
                p.move(to: CGPoint(x: x, y: 3.5))
                p.addQuadCurve(to: CGPoint(x: x, y: 6.5), control: CGPoint(x: x - 1.6, y: 5))
            }
        }
        return p
    }
}

/// Linker Kreis einer Einstellungs-Zeile.
enum ELead {
    case none, icon(Icon8), extra(EIcon.Kind), emoji(String)
}

/// Einstellungs-Zeile (`.e-row`): Kreis 32 mit Icon 18, Titel 15/700 (oder Serif 18), Untertitel 12, Wert, Chevron.
struct ERow<Trail: View>: View {
    let title: String
    var sub: String?
    var value: String?
    var lead: ELead
    var tint: Color
    var serif: Bool
    var monoSub: Bool
    var chevron: Bool
    var line: Color
    var minHeight: CGFloat
    let trail: Trail

    init(_ title: String, sub: String? = nil, value: String? = nil, lead: ELead = .none, tint: Color = Theme.C.blue1,
         serif: Bool = false, monoSub: Bool = false, chevron: Bool = true, line: Color = Theme.C.line, minHeight: CGFloat = 44,
         @ViewBuilder trail: () -> Trail) {
        self.title = title; self.sub = sub; self.value = value; self.lead = lead; self.tint = tint
        self.serif = serif; self.monoSub = monoSub; self.chevron = chevron; self.line = line; self.minHeight = minHeight; self.trail = trail()
    }

    var body: some View {
        HStack(spacing: 12) {
            leadView
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(serif ? Theme.F.serif(18, relativeTo: .title3) : Theme.F.text(15, .bold, relativeTo: .subheadline))
                if let sub {
                    Text(sub).font(monoSub ? Font.system(size: 12, weight: .medium, design: .monospaced) : Theme.F.text(12, relativeTo: .caption))
                        .foregroundStyle(Theme.C.ink2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let value { Text(value).font(Theme.F.text(14, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2).lineLimit(1) }
            trail
            if chevron { Icon(.chev, size: 18).foregroundStyle(Theme.C.ink3) }
        }
        .foregroundStyle(Theme.C.ink)
        .padding(.vertical, 4)
        .frame(minHeight: minHeight)
        .overlay(alignment: .top) { Hairline(color: line) }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var leadView: some View {
        switch lead {
        case .none: EmptyView()
        case .icon(let i): Icon(i, size: 18).frame(width: 32, height: 32).background(tint, in: Circle())
        case .extra(let k): EIcon(kind: k).frame(width: 32, height: 32).background(tint, in: Circle())
        case .emoji(let e): Text(e).font(.system(size: 17)).frame(width: 32, height: 32).background(tint, in: Circle())
        }
    }
}

extension ERow where Trail == EmptyView {
    init(_ title: String, sub: String? = nil, value: String? = nil, lead: ELead = .none, tint: Color = Theme.C.blue1,
         serif: Bool = false, monoSub: Bool = false, chevron: Bool = true, line: Color = Theme.C.line, minHeight: CGFloat = 44) {
        self.init(title, sub: sub, value: value, lead: lead, tint: tint, serif: serif, monoSub: monoSub, chevron: chevron, line: line,
                  minHeight: minHeight) { EmptyView() }
    }
}

/// Schalter `.sw` (50 × 30) für Zeilen-Enden.
struct ESwitch: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Toggle(isOn: $isOn) { EmptyView() }.toggleStyle(.v8).fixedSize()  // .v8 zeigt das Label auch bei labelsHidden()
            .accessibilityLabel(label)
    }
}

/// Zurück (`#i-back` ohne Kreis), Tap-Fläche 44.
struct EBack: View {
    @Environment(\.dismiss) private var dismiss
    var size: CGFloat = Theme.S.icon
    var action: (() -> Void)?

    var body: some View {
        Button { if let action { action() } else { dismiss() } } label: {
            Icon(.back, size: size).foregroundStyle(Theme.C.ink)
                .frame(width: 44, height: 44, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Zurück")
    }
}

/// Regler (`.e-range`): Linie 2, Füllung Tinte, Knopf 28. Mit `track`/`knob`/`ring` auch der Umkreis-Regler aus S14.
struct ERange: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var track: CGFloat = 2
    var knob: CGFloat = 28
    var ring: CGFloat = 0
    var label = "Wert"
    var onEnd: () -> Void = {}

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let f = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.C.line).frame(height: track)
                Capsule().fill(Theme.C.ink).frame(width: max(track, w * f), height: track)
                Circle().fill(Theme.C.ink).frame(width: knob, height: knob)
                    .overlay(Circle().strokeBorder(Theme.C.bg, lineWidth: ring).padding(-ring))
                    .offset(x: w * f - knob / 2)
            }
            .frame(height: max(knob, 44))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { d in
                    let raw = range.lowerBound + min(max(d.location.x / max(w, 1), 0), 1) * (range.upperBound - range.lowerBound)
                    let v = (raw / step).rounded() * step
                    if v != value { value = v }
                }
                .onEnded { _ in onEnd() })
        }
        .frame(height: knob)
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(num(value))
        .accessibilityAdjustableAction { dir in
            value = dir == .increment ? min(range.upperBound, value + step) : max(range.lowerBound, value - step)
            onEnd()
        }
    }
}

// MARK: - S14 Läden & Umkreis

/// Läden im Umkreis auf der Karte wählen (Einstellungen › Ort & Läden, Angebote).
struct StoreMapView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var radius = 5.0
    @State private var nearby: [NearbyStore] = []
    @State private var selected: Set<String> = []
    @State private var loading = false
    @State private var error: String?
    @State private var camera: MapCameraPosition = .automatic
    @State private var saving = false

    // Mockup-Maße (c.html S14)
    private let mapTop: CGFloat = 78  // 130 − 52
    private let mapHeight: CGFloat = 240
    private let pinSize: CGFloat = 28

    private var center: CLLocationCoordinate2D? {
        guard let h = store.household, let lat = h.lat, let lng = h.lng else {
            guard let first = nearby.first else { return nil }  // Fallback: nächster Laden
            return CLLocationCoordinate2D(latitude: first.lat, longitude: first.lng)
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    EBack(size: 26)
                    Text("Läden & Umkreis").font(Theme.F.t2)
                }
                .padding(.leading, -10)
                Text("\(store.household?.plz ?? "") · \(selected.count) von \(nearby.count) Läden")
                    .font(Theme.F.text(13, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                    .padding(.leading, 38).padding(.top, 2)
                map.padding(.horizontal, -Theme.pagePadding).padding(.top, mapTop - 70)
                StatNumber(label: "Umkreis", value: "\(Int(radius)) km", size: 48).padding(.top, 14)
                HStack(spacing: 12) {
                    Text("1 km")
                    ERange(value: $radius, range: 1...30, track: Theme.S.bar, knob: 26, ring: 4, label: "Umkreis in Kilometern") {
                        Task { await load() }
                    }
                    Text("30 km")
                }
                .font(Theme.F.text(12, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                .padding(.top, 12)
                list.padding(.top, 12)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .ctaBar(bottom: 34) {
            PrimaryButton(title: saving ? "Speichere …" : selected.isEmpty ? "Mindestens einen Laden wählen" : "\(selected.count) Läden übernehmen",
                          disabled: selected.isEmpty || saving, action: save)
        }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
        .task {
            radius = Double(store.household?.radiusKm ?? 5)
            selected = Set(store.household?.stores.compactMap(\.osmId) ?? [])
            await load()
        }
    }

    /// Karte mit weichem Rand, Umkreis als blauer Kreis, Läden als Kreise mit Kürzel (gewählt Tinte, sonst `card`).
    private var map: some View {
        Map(position: $camera) {
            if let center {
                MapCircle(center: center, radius: radius * 1000)
                    .foregroundStyle(Theme.C.blue.opacity(0.3))
                    .stroke(Theme.C.blue3, lineWidth: Theme.S.hair)
                Annotation("Du", coordinate: center) {
                    Circle().fill(Theme.C.blue3).frame(width: 12, height: 12).overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                }
            }
            ForEach(nearby) { s in
                Annotation(s.name, coordinate: CLLocationCoordinate2D(latitude: s.lat, longitude: s.lng)) {
                    let on = selected.contains(s.id)
                    Button { toggle(s) } label: {
                        Text(short(s.chain))
                            .font(Theme.F.text(11, .extrabold, relativeTo: .caption2))
                            .foregroundStyle(on ? Theme.C.onInk : Theme.C.ink2)
                            .frame(width: pinSize, height: pinSize)
                            .background(on ? Theme.C.ink : Theme.C.card, in: Circle())
                            .overlay { if !on { Circle().strokeBorder(Theme.C.ink3, lineWidth: Theme.S.hair) } }
                            .frame(minWidth: 44, minHeight: 44)
                            .animation(Theme.spring, value: on)
                    }
                    .accessibilityLabel("\(s.name), \(on ? "gewählt" : "nicht gewählt")")
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .frame(height: mapHeight)
        .mask(RadialGradient(stops: [.init(color: .black, location: 0.35), .init(color: .clear, location: 0.98)],
                             center: .center, startRadius: 0, endRadius: 200))
        .onChange(of: radius) { focus() }
        .onChange(of: nearby) { focus() }
    }

    @ViewBuilder private var list: some View {
        if loading {
            VStack(spacing: 10) { ForEach(0..<4, id: \.self) { _ in Skeleton8(height: 44) } }
        } else if let error {
            VStack(alignment: .leading, spacing: 12) {
                Text(error).font(Theme.F.text(13, relativeTo: .footnote)).foregroundStyle(Theme.C.deal)
                OutlineButton(title: "Erneut versuchen") { Task { await load() } }
            }
        } else if nearby.isEmpty {
            Text("Keine Läden gefunden – vergrößere den Umkreis.").font(Theme.F.small).foregroundStyle(Theme.C.ink2).padding(.top, 8)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(selected.count == nearby.count ? "Keine" : "Alle") {
                        withAnimation(Theme.spring) { selected = selected.count == nearby.count ? [] : Set(nearby.map(\.id)) }
                    }
                    .font(Theme.F.text(13, .extrabold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink)
                    .frame(minHeight: 44)
                }
                ForEach(nearby) { s in storeRow(s) }
            }
        }
    }

    /// Zeile `.c-r2`: Name 16, Adresse · Entfernung 12, rechts der Haken.
    private func storeRow(_ s: NearbyStore) -> some View {
        let on = selected.contains(s.id)
        return Button { toggle(s) } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Labels.chains.contains { $0.key == s.chain } ? Labels.chain(s.chain) : s.name)
                        .font(Theme.F.text(16, .bold, relativeTo: .body)).lineLimit(1)
                    Text([s.address, "\(num(s.distanceKm, 1...1)) km"].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(Theme.F.text(12, relativeTo: .caption)).foregroundStyle(Theme.C.ink2).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                CheckCircle(on: on)
            }
            .foregroundStyle(Theme.C.ink)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .overlay(alignment: .top) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
    }

    private func short(_ chain: String) -> String {
        let name = Labels.chain(chain)
        return name.count <= 2 ? name : String(name.prefix(1)).uppercased()
    }

    private func toggle(_ s: NearbyStore) {
        withAnimation(Theme.spring) { if selected.remove(s.id) == nil { selected.insert(s.id) } }
    }

    private func focus() {
        guard let center else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            camera = .region(MKCoordinateRegion(center: center, latitudinalMeters: radius * 2600, longitudinalMeters: radius * 2600))
        }
    }

    private func load() async {
        if store.demo { nearby = Demo.nearby; selected = Set(Demo.nearby.prefix(4).map(\.id)); focus(); return }
        loading = nearby.isEmpty
        defer { loading = false }
        do {
            nearby = try await store.nearbyStores(radiusKm: Int(radius))
            error = nil
            focus()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            let stores = nearby.filter { selected.contains($0.id) }.map {
                StoreDTO(chain: $0.chain, storeName: $0.name, osmId: $0.osmId, lat: $0.lat, lng: $0.lng, address: $0.address)
            }
            do {
                try await store.save(HouseholdPatch(radiusKm: Int(radius), stores: stores))
                store.flash("\(stores.count) Läden gespeichert")
                Task { await store.refreshOffers() }
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - S13 Einstellungen

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"
    static let appearances = [("system", "System"), ("light", "Hell"), ("dark", "Dunkel")]
    static let storage = [("klein", "Klein (3 Packungen)"), ("mittel", "Mittel (6)"), ("gross", "Groß (12)")]
    @State private var confirmReset = false
    @State private var members: [MemberDTO] = []
    @State private var invite: URL?
    @State private var push: PushSettingsDTO?
    @State private var scrolled = false
    @State private var reminder = StoreReminder.shared

    // Mockup-Maße (e.html S13 oben), Inhalt ab Safe Area (Mockup-y − 52), x ab Seitenrand 24
    private let blob = (left: CGFloat(-104), top: CGFloat(-132), size: CGFloat(290))
    private let avatar = (x: CGFloat(20), y: CGFloat(46), size: CGFloat(88))
    private let nameX: CGFloat = 188
    private let nameY: CGFloat = 64
    private let rowsY: CGFloat = 160

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let h = store.household {
                    top(h)
                    planning(h)
                } else {
                    topRows
                }
                family
                devices
                app
                Button("Abmelden & neu einrichten", role: .destructive) { confirmReset = true }
                    .font(Theme.F.text(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.C.deal)
                    .frame(maxWidth: .infinity, minHeight: 44).padding(.top, 28)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 40)
            .edgeForm(.circle, Theme.C.blue, width: blob.size, height: blob.size, left: blob.left, top: blob.top)
        }
        .coordinateSpace(name: "settings")
        .overlay(alignment: .top) { if scrolled { stickyBar } }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
        .modifier(PushAsk())  // bestehende Installationen: einmal beim ersten Öffnen der Einstellungen
        // 19.3: neu einrichten legt einen neuen Haushalt an – Plan, Liste und Rezepte bleiben beim alten
        .confirmationDialog("Wirklich neu einrichten?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Abmelden & neu einrichten", role: .destructive) {
                store.api.token = nil; store.onboarded = false; store.plan = nil; store.household = nil
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Dein Wochenplan, die Einkaufsliste und deine Rezepte sind danach auf diesem iPhone weg. Präferenzen änderst du ohne Neueinrichtung oben unter „Präferenzen“ – der Plan bleibt dabei.")
        }
        .task {
            members = store.demo ? [] : await store.members()
            invite = await store.inviteURL()
            push = try? await store.pushSettings()
        }
    }

    /// Kopf: Zurück, Avatar groß im blauen Kreis, Name und Haushalt.
    private var header: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 4) {
                EBack()
                Text("Einstellungen").font(Theme.F.text(16, .bold))
            }
            .padding(.top, -10)
            Text(store.profile?.emoji ?? "🧑‍🍳").font(.system(size: avatar.size)).accessibilityHidden(true)
                .offset(x: avatar.x, y: avatar.y)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.profile?.name ?? store.household?.name ?? "Zuhause").font(Theme.F.t1).lineLimit(1).minimumScaleFactor(0.6)
                Text(householdLine).font(Theme.F.text(13, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
            }
            .offset(x: nameX, y: nameY)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, nameX)
        }
        .frame(height: rowsY, alignment: .topLeading)
        .onGeometryChange(for: Bool.self) { g in g.frame(in: .named("settings")).minY < -rowsY + 40 } action: { s in
            withAnimation(.easeOut(duration: 0.2)) { scrolled = s }
        }
    }

    private var householdLine: String {
        let others = members.filter { m in m.id != store.profile?.memberId }.map(\.name)
        let persons = store.household?.persons ?? 2
        return "Haushalt \(store.household?.name ?? "Zuhause")\n\(others.isEmpty ? "" : "mit \(others.joined(separator: ", ")) · ")\(persons) \(persons == 1 ? "Person" : "Personen")"
    }

    /// Beim Scrollen: Zurück + „Einstellungen“ in t2 oben fest (S13 Mitte/unten).
    private var stickyBar: some View {
        HStack(spacing: 4) {
            EBack()
            Text("Einstellungen").font(Theme.F.t2)
            Spacer()
        }
        .padding(.horizontal, Theme.pagePadding - 0).padding(.top, 4).padding(.bottom, 6)
        .background(Theme.C.bg.ignoresSafeArea(edges: .top))
        .transition(.opacity)
    }

    private func label(_ text: String) -> some View {
        SectionLabel(text).padding(.top, 28).padding(.bottom, 4)
    }

    @ViewBuilder private var topRows: some View {
        NavigationLink { ProfileView() } label: {
            ERow("Mein Profil", value: store.profile.map { p in ProfileView.goals.first { g in g.0 == p.goal }?.1 ?? p.goal },
                 lead: .emoji(store.profile?.emoji ?? "🧑‍🍳"), tint: Theme.C.rose)
        }
        .buttonStyle(.plain)
        NavigationLink { AchievementsView() } label: {  // Profil › Erfolge (54)
            ERow("Erfolge", value: "Sparen & Gesundheit", lead: .icon(.trophy), tint: Theme.C.sand)
        }
        .buttonStyle(.plain)
        if let p = store.pro, p.paywall {  // 19.8: Pro-Stand und Paywall (ohne PAYWALL am Server ausgeblendet)
            Button { store.api.paywall = "" } label: {
                ERow(p.pro ? "Pro ist aktiv" : "Pro holen",
                     sub: p.pro ? "für alle im Haushalt · kündbar in den iOS-Einstellungen" : "\(p.price) · \(p.freePlansLeft) Gratis-Plan diese Woche übrig",
                     lead: .icon(.sparkle), tint: Theme.C.blue1)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private func top(_ h: HouseholdDTO) -> some View {
        topRows
        label("Haushalt")
        link(.persons) { ERow("Personen", value: "\(h.persons)", lead: .icon(.users), tint: Theme.C.blue1) }
        link(.diet) { ERow("Ernährung", value: Labels.diets.first { $0.0 == h.diet }?.1 ?? h.diet, lead: .icon(.leaf), tint: Theme.C.sage) }
        link(.diet) {
            ERow("Allergien & Abneigungen", sub: summary([h.allergies.joined(separator: ", "), h.excludedIngredients.joined(separator: ", ")], empty: "keine"),
                 lead: .extra(.alert), tint: Theme.C.rose)
        }
        label("Einkaufen")
        NavigationLink { StoreMapView() } label: {
            ERow("Ort & Läden", sub: "\(h.plz) · \(summary([h.stores.filter(\.enabled).map { s in Labels.chain(s.chain) }.uniqued().joined(separator: ", ")], empty: "keine Läden"))",
                 lead: .icon(.pin), tint: Theme.C.blue1)
        }
        .buttonStyle(.plain)
        link(.budget) {
            ERow("Budget", sub: "Lebensmittel \(euro(h.budgetFoodWeekCents))" + (h.budgetDrugstoreCents.map { " · Drogerie \(euro($0))" } ?? ""),
                 lead: .icon(.tag), tint: Theme.C.rose)
        }
        NavigationLink { SpendingView() } label: {  // Monats-Dashboard (34)
            ERow("Ausgaben", value: "Monats-Dashboard", lead: .icon(.chart), tint: Theme.C.sand)
        }
        .buttonStyle(.plain)
        Menu {  // Vorratsplatz für Vorratskauf-Tipps (31)
            Picker("Vorratsplatz", selection: Binding(get: { h.storageSpace ?? "mittel" }, set: { v in
                if store.demo { store.household?.storageSpace = v } else { Task {
                    do { try await store.save(HouseholdPatch(storageSpace: v)) } catch { store.flash("Nicht gespeichert: \(error.localizedDescription)") }
                } }
            })) {
                ForEach(Self.storage, id: \.0) { key, label in Text(label).tag(key) }
            }
        } label: {
            ERow("Vorratsplatz", sub: "begrenzt Vorratskauf-Tipps", value: Self.storage.first { $0.0 == (h.storageSpace ?? "mittel") }?.1,
                 lead: .icon(.box), tint: Theme.C.blue1)
        }
        .sensoryFeedback(.selection, trigger: h.storageSpace)
    }

    @ViewBuilder private func planning(_ h: HouseholdDTO) -> some View {
        label("Planung")
        link(.meals) {
            ERow("Mahlzeiten & Tage", sub: "\(h.mealTypes.map(Labels.meal).joined(separator: ", ")) · \(days(h.planDays))",
                 lead: .icon(.fork), tint: Theme.C.blue1)
        }
        link(.cuisines) {
            ERow("Küchen", value: h.cuisines.isEmpty ? "alle" : h.cuisines.count == 1 ? h.cuisines[0] : "\(h.cuisines[0]) +\(h.cuisines.count - 1)",
                 lead: .icon(.book), tint: Theme.C.rose)
        }
        link(.goal) {
            ERow("Ziel & Kochzeit", sub: "\(ProfileView.goals.first { $0.0 == h.nutritionGoal }?.1 ?? h.nutritionGoal) · max. \(h.maxCookMinutes) min",
                 lead: .icon(.chart), tint: Theme.C.sand)
        }
        label("Präferenzen")
        NavigationLink { VarietyView() } label: {
            let v = h.variety ?? VarietyDTO()
            ERow("Abwechslung", sub: "max. \(v.maxPasta)× Pasta · \(v.veggieDays) Veggie-Tage", lead: .icon(.refresh), tint: Theme.C.sage)
        }
        .buttonStyle(.plain)
        NavigationLink { WeeklyBasicsView() } label: {
            ERow("Frühstück & Snacks", sub: "jede Woche auf die Liste", lead: .extra(.cup), tint: Theme.C.sand, line: Theme.C.ink)
        }
        .buttonStyle(.plain)
        label("Mitteilungen")
        NavigationLink { NotificationsView() } label: {
            ERow("Mitteilungen", sub: pushLine, lead: .icon(.bell), tint: Theme.C.blue1)
        }
        .buttonStyle(.plain)
        NavigationLink { NotificationsView() } label: {
            ERow("Erinnerung im Laden",
                 sub: reminder.enabled ? "an · \(reminder.watched) \(reminder.watched == 1 ? "Laden" : "Läden") überwacht" : "aus",
                 lead: .icon(.pin), tint: Theme.C.sage)
        }
        .buttonStyle(.plain)
    }

    private var pushLine: String {
        guard let p = push else { return "Erinnerung, Ruhezeit" }
        let kinds = [p.planPromptEnabled, p.lunchboxPush != nil].filter { $0 }.count
        return ([p.pushEnabled ? "an" : "aus", "\(kinds) \(kinds == 1 ? "Art" : "Arten")"] + (p.quietHours.map { ["Ruhe ab \($0.start)"] } ?? []))
            .joined(separator: " · ")
    }

    /// Familie: Mitglieder in einer Zeile (Entfernen im Kontextmenü), Einladungslink teilen.
    @ViewBuilder private var family: some View {
        label("Familie")
        if !members.isEmpty {
            HStack(spacing: 12) {
                HStack(spacing: -8) {
                    ForEach(Array(members.prefix(4).enumerated()), id: \.element.id) { i, m in
                        Text(store.profiles.first { $0.memberId == m.id }?.emoji ?? String(m.name.prefix(1)))
                            .font(.system(size: 17)).frame(width: 32, height: 32)
                            .background([Theme.C.blue, Theme.C.rose, Theme.C.sage, Theme.C.sand][i % 4], in: Circle())
                            .overlay { if i > 0 { Circle().strokeBorder(Theme.C.bg, lineWidth: 2).padding(-2) } }
                    }
                }
                Text(members.map(\.name).joined(separator: ", ")).font(Theme.F.text(15, .bold, relativeTo: .subheadline))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(members.count) \(members.count == 1 ? "Mitglied" : "Mitglieder")").font(Theme.F.text(14, relativeTo: .subheadline))
                    .foregroundStyle(Theme.C.ink2)
            }
            .padding(.vertical, 4).frame(minHeight: 44)
            .overlay(alignment: .top) { Hairline() }
            .contentShape(Rectangle())
            .contextMenu {
                ForEach(members.filter { $0.role != "owner" }) { m in
                    Button("\(m.name) entfernen", systemImage: "person.badge.minus", role: .destructive) {
                        Task { await store.removeMember(m); members = await store.members() }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Gedrückt halten zum Entfernen")
        }
        if let invite {
            ShareLink(item: invite, subject: Text("Kochpilot"), message: Text("Komm in unseren Haushalt – Wochenplan & Einkaufsliste gemeinsam:")) {
                ERow("Einladungslink teilen", sub: "öffnet die Web-Version · 7 Tage gültig", lead: .icon(.share), tint: Theme.C.blue1)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var devices: some View {
        label("Rezepte & Geräte")
        NavigationLink { InstagramShareView() } label: {
            ERow("Teilen aus Instagram", lead: .icon(.link), tint: Theme.C.rose)
        }
        .buttonStyle(.plain)
        if store.household?.stepImagesAvailable == true {
            ERow("Schritt-Bilder erzeugen", sub: "ca. 2 Cent/Rezept", lead: .icon(.photo), tint: Theme.C.sand, chevron: false) {
                ESwitch(isOn: Binding(get: { store.stepImagesOn }, set: { on in Task { await store.setStepImages(on) } }), label: "Schritt-Bilder erzeugen")
            }
        }
        NavigationLink { InstagramShareView(widget: true) } label: {
            ERow("Widget einrichten", lead: .icon(.widget), tint: Theme.C.blue1)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var app: some View {
        label("App")
        Menu {
            Picker("Erscheinungsbild", selection: $appearance) {
                ForEach(Self.appearances, id: \.0) { key, label in Text(label).tag(key) }
            }
        } label: {
            ERow("Erscheinungsbild", value: Self.appearances.first { $0.0 == appearance }?.1, lead: .icon(.eye), tint: Theme.C.sage)
        }
        .sensoryFeedback(.selection, trigger: appearance)
        NavigationLink { ServerView() } label: {
            ERow("Server & Version", sub: "\(URL(string: store.api.baseURL)?.host() ?? store.api.baseURL) · \(Self.version)",
                 lead: .icon(.gear), tint: Theme.C.sand, monoSub: true)
        }
        .buttonStyle(.plain)
        if let left = Self.reinstallDays {
            ERow(left <= 2 ? "Neu installieren fällig" : "Neu installieren", lead: .icon(.refresh), tint: Theme.C.warn, chevron: false) {
                SoftPill(text: left <= 0 ? "heute" : left == 1 ? "in 1 Tag" : "in \(left) Tagen", tint: Theme.C.warn)
            }
        } else {
            ERow("Neu installieren", sub: "alle 7 Tage (kostenlose Apple-ID)", lead: .icon(.refresh), tint: Theme.C.warn, chevron: false)
        }
    }

    private func link(_ focus: PrefsSection, @ViewBuilder row: () -> some View) -> some View {
        NavigationLink { PreferencesView(focus: focus) } label: { row() }.buttonStyle(.plain)
    }

    private func summary(_ parts: [String], empty: String) -> String {
        let p = parts.filter { !$0.isEmpty }
        return p.isEmpty ? empty : p.joined(separator: " · ")
    }

    private func days(_ d: [Int]) -> String {
        let s = d.sorted()
        if s.count > 2, s == Array(s[0]...s[s.count - 1]) { return "\(Labels.days[s[0]])–\(Labels.days[s[s.count - 1]])" }
        return s.map { Labels.days[$0] }.joined(separator: ", ")
    }

    static var version: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "–") (\(i?["CFBundleVersion"] as? String ?? "–"))"
    }

    /// Tage bis das Profil der kostenlosen Apple-ID abläuft (ExpirationDate aus embedded.mobileprovision).
    static let reinstallDays: Int? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let raw = try? Data(contentsOf: url), let text = String(data: raw, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"), let end = text.range(of: "</plist>"),
              let xml = String(text[start.lowerBound..<end.upperBound]).data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any],
              let expiry = plist["ExpirationDate"] as? Date else { return nil }
        return Int(ceil(expiry.timeIntervalSinceNow / 86_400))
    }()
}

/// Einstellungen › Server & Version: Server-Adresse ändern (ohne Mockup: Zeilen-Stil wie S13).
private struct ServerView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var api = store.api
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EBack()
                Text("Server & Version").font(Theme.F.t1).padding(.top, 10)
                SectionLabel("Server-Adresse").padding(.top, 28).padding(.bottom, 8)
                FieldBox(icon: .gear) {
                    TextField("http://…", text: $api.baseURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                }
                ERow("Version", value: SettingsView.version, chevron: false).padding(.top, 28)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 4)
        }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
    }
}
