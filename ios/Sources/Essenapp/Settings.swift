import MapKit
import SwiftUI

/// Läden im Umkreis auf der Karte wählen (Onboarding Schritt 2 und Einstellungen).
struct StoreMapView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var onDone: (() -> Void)?
    @State private var radius = 5.0
    @State private var nearby: [NearbyStore] = []
    @State private var selected: Set<String> = []
    @State private var loading = false
    @State private var error: String?
    @State private var camera: MapCameraPosition = .automatic
    @State private var saving = false

    private var center: CLLocationCoordinate2D? {
        guard let h = store.household, let lat = h.lat, let lng = h.lng else {
            guard let first = nearby.first else { return nil }  // Fallback: nächster Laden
            return CLLocationCoordinate2D(latitude: first.lat, longitude: first.lng)
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.C.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if onDone == nil { RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() } }
                    DisplayHeader(line1: "Deine Läden", line2: "im Umkreis")
                    map
                    radiusControl
                    if loading {
                        ForEach(0..<4, id: \.self) { _ in SkeletonCard(height: 64) }
                    } else if let error {
                        ErrorState(message: error) { Task { await load() } }
                    } else if nearby.isEmpty {
                        EmptyState(emoji: "🗺️", title: "Keine Läden gefunden", text: "Vergrößere den Umkreis.")
                    } else {
                        HStack {
                            Text("\(nearby.count) Läden gefunden").font(Theme.F.headline)
                            Spacer()
                            Button(selected.count == nearby.count ? "Keine" : "Alle") {
                                withAnimation(Theme.spring) { selected = selected.count == nearby.count ? [] : Set(nearby.map(\.id)) }
                            }
                            .font(Theme.F.callout)
                        }
                        ForEach(Array(nearby.enumerated()), id: \.element.id) { i, s in
                            storeRow(s).appear(delay: Double(i) * 0.03)
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 200)
            }
            Button(action: save) {
                Text(saving ? "Speichere …" : selected.isEmpty ? "Mindestens einen Laden wählen" : "\(selected.count) Läden übernehmen")
                    .contentTransition(.numericText())
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selected.isEmpty || saving)
            .opacity(selected.isEmpty ? 0.5 : 1)
            .padding(.horizontal, Theme.pagePadding).padding(.bottom, onDone == nil ? Theme.ctaAboveTabBar : 12)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            radius = Double(store.household?.radiusKm ?? 5)
            selected = Set(store.household?.stores.compactMap(\.osmId) ?? [])
            await load()
        }
    }

    private var map: some View {
        Map(position: $camera) {
            if let center {
                MapCircle(center: center, radius: radius * 1000)
                    .foregroundStyle(Theme.C.accent.opacity(0.08))
                    .stroke(Theme.C.accent, lineWidth: 2)
                Annotation("Du", coordinate: center) {
                    Circle().fill(Theme.C.action).frame(width: 14, height: 14).overlay(Circle().strokeBorder(.white, lineWidth: 3))
                }
            }
            ForEach(nearby) { s in
                Annotation(s.name, coordinate: CLLocationCoordinate2D(latitude: s.lat, longitude: s.lng)) {
                    let on = selected.contains(s.id)
                    Button { toggle(s) } label: {
                        Text(String(Labels.chain(s.chain).prefix(1)))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(on ? .white : Theme.storeColor(s.chain))
                            .frame(width: 30, height: 30)
                            .background(on ? Theme.storeColor(s.chain) : .white, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.storeColor(s.chain), lineWidth: 2))
                            .scaleEffect(on ? 1.15 : 1)
                            .animation(Theme.spring, value: on)
                    }
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: Theme.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.R.card, style: .continuous).strokeBorder(Theme.C.line, lineWidth: 0.5))
        .onChange(of: radius) { focus() }
        .onChange(of: nearby) { focus() }
    }

    private var radiusControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Umkreis").font(Theme.F.callout)
                Spacer()
                Text("\(Int(radius)) km").font(.system(.headline, design: .rounded, weight: .bold)).contentTransition(.numericText())
            }
            Slider(value: $radius, in: 1...30, step: 1) { editing in
                if !editing { Task { await load() } }
            }
            .tint(Theme.C.accent)
        }
        .padding(16).card()
    }

    private func storeRow(_ s: NearbyStore) -> some View {
        let on = selected.contains(s.id)
        return Button { toggle(s) } label: {
            HStack(spacing: 12) {
                Text(String(Labels.chain(s.chain).prefix(1)))
                    .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Theme.storeColor(s.chain), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(.system(.body, weight: .semibold)).lineLimit(1)
                    Text(s.address.isEmpty ? Labels.chain(s.chain) : s.address).font(Theme.F.micro).foregroundStyle(Theme.C.text2).lineLimit(1)
                }
                Spacer()
                Text(String(format: "%.1f km", s.distanceKm)).font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22)).foregroundStyle(on ? Theme.C.accent : Theme.C.text3)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(12)
            .card(radius: Theme.R.tile)
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.selection, trigger: on)
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
                if let onDone { onDone() } else { dismiss() }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// S13 Einstellungen.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var api = store.api
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                VStack(spacing: 8) {
                    Text("👩‍🍳").font(.system(size: 44)).frame(width: 84, height: 84).background(Theme.C.accentSoft, in: Circle())
                    Text(store.household?.name ?? "Zuhause").font(Theme.F.title)
                    Text("\(store.household?.persons ?? 2) Personen · PLZ \(store.household?.plz ?? "")").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                }
                .frame(maxWidth: .infinity).padding(.bottom, 6)

                if let h = store.household {
                    group("EINKAUFEN") {
                        NavigationLink { StoreMapView() } label: {
                            row("mappin.and.ellipse", Theme.C.accent, "Läden & Umkreis",
                                "\(h.stores.filter(\.enabled).count) Läden · \(h.radiusKm ?? 5) km")
                        }
                        NavigationLink { PreferencesView() } label: {
                            row("eurosign.circle.fill", Theme.C.warning, "Budget", "\(euro(h.budgetFoodWeekCents)) / Woche")
                        }
                    }
                    group("PRÄFERENZEN") {
                        NavigationLink { PreferencesView() } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                row("fork.knife", Theme.C.kcal, "Mahlzeiten & Küche",
                                    "\(h.mealTypes.map(Labels.meal).joined(separator: ", ")) · \(h.cuisines.isEmpty ? "gemischt" : h.cuisines.joined(separator: ", "))")
                                row("leaf.fill", Theme.C.carbs, "Ernährung", ([h.diet.capitalized] + h.allergies).joined(separator: " · "))
                                row("target", Theme.C.protein, "Ziel", "\(h.nutritionGoal.capitalized) · max. \(h.maxCookMinutes) min")
                                Text("Ändern ›").font(Theme.F.callout).foregroundStyle(Theme.C.accentDeep)
                            }
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                group("APP") {
                    HStack(spacing: 12) {
                        icon("server.rack", Theme.C.text2)
                        TextField("http://…", text: $api.baseURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    .padding(.vertical, 4)
                    row("clock.arrow.circlepath", Theme.C.danger, "Neu installieren", "alle 7 Tage (kostenlose Apple-ID)")
                }
                Button("Abmelden & neu einrichten", role: .destructive) {
                    api.token = nil; store.onboarded = false; store.plan = nil; store.household = nil
                }
                .frame(maxWidth: .infinity).padding(.top, 8)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
        }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.F.micro).foregroundStyle(Theme.C.text2).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 10) { content() }.padding(14).card()
        }
        .appear()
    }

    private func icon(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
            .frame(width: 34, height: 34).background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ symbol: String, _ color: Color, _ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            icon(symbol, color)
            Text(title).font(.system(.body, weight: .semibold)).foregroundStyle(Theme.C.text1)
            Spacer()
            Text(value).font(Theme.F.caption).foregroundStyle(Theme.C.text2).lineLimit(1)
        }
    }
}
