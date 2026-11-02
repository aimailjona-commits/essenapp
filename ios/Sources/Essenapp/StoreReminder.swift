import CoreLocation
import SwiftUI
import UserNotifications

// Feature 36: Standort-Erinnerung. Region-Überwachung braucht keinen `location`-Hintergrundmodus –
// iOS weckt die App beim Betreten selbst (auch nach Beenden), dafür entsteht der Manager beim Start (AppDelegate).

/// Überwacht bis zu 20 gewählte Läden (nächste zuerst, 120 m) und meldet beim Betreten lokal die offenen Artikel der Kette –
/// nur 8–21 Uhr, höchstens 1× pro Laden und Tag, nur wenn etwas offen ist.
@MainActor @Observable
final class StoreReminder: NSObject, CLLocationManagerDelegate {
    static let shared = StoreReminder()
    static let radius: CLLocationDistance = 120
    static let maxRegions = 20  // iOS-Grenze pro App (A5)

    var enabled = Demo.screen != nil || UserDefaults.standard.bool(forKey: "storeReminder") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "storeReminder")
            sync()
        }
    }
    private(set) var status = CLAuthorizationStatus.notDetermined
    private(set) var watched = 0  // gerade überwachte Läden
    @ObservationIgnored private var stores: [StoreDTO]?  // nil bis der Haushalt geladen ist – bis dahin Regionen nicht anfassen
    @ObservationIgnored private var home: CLLocationCoordinate2D?
    @ObservationIgnored private let manager = CLLocationManager()

    private override init() {
        super.init()
        if Demo.screen != nil {
            status = .authorizedAlways
            watched = Demo.household.stores.count
            return
        }
        manager.delegate = self
        status = manager.authorizationStatus
    }

    /// Läden und Wohnort aus dem Haushalt (nach jedem Laden/Speichern).
    func update(_ household: HouseholdDTO?) {
        guard let household else { return }
        stores = household.stores
        home = household.lat.flatMap { lat in household.lng.map { lng in CLLocationCoordinate2D(latitude: lat, longitude: lng) } }
        sync()
    }

    /// Erlaubnis „Immer“ anfragen (nach dem Erklär-Sheet). Schon abgelehnt → iOS fragt nicht mehr, die Karte zeigt den Weg.
    func requestAlways() {
        manager.requestAlwaysAuthorization()
    }

    private func sync() {
        guard Demo.screen == nil, let stores else { return }
        let picked = enabled && CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self)
            ? Self.pick(stores, near: manager.location?.coordinate ?? home) : []
        let ids = Set(picked.map(Self.id))
        watched = ids.count
        guard ids != Set(manager.monitoredRegions.map(\.identifier)) else { return }
        for r in manager.monitoredRegions { manager.stopMonitoring(for: r) }
        for s in picked {
            guard let lat = s.lat, let lng = s.lng else { continue }
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lng), radius: Self.radius, identifier: Self.id(s))
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
    }

    // MARK: Regeln (reine Funktionen)

    /// Gewählte Läden mit Koordinaten, nächste zuerst, höchstens 20. Ohne Standort: Reihenfolge der Auswahl.
    // shortcut: sortiert beim Laden/Speichern, nicht unterwegs – reicht, solange ein Haushalt ≤ 20 Läden mit Standort hat
    static func pick(_ stores: [StoreDTO], near: CLLocationCoordinate2D?) -> [StoreDTO] {
        let located = stores.filter { s in s.enabled && s.lat != nil && s.lng != nil }
        guard let near else { return Array(located.prefix(maxRegions)) }
        let here = CLLocation(latitude: near.latitude, longitude: near.longitude)
        func distance(_ s: StoreDTO) -> CLLocationDistance { here.distance(from: CLLocation(latitude: s.lat ?? 0, longitude: s.lng ?? 0)) }
        return Array(located.sorted { a, b in distance(a) < distance(b) }.prefix(maxRegions))
    }

    /// Kennung der Region: Kette vorn, damit das Betreten ohne geladene Läden auskommt.
    static func id(_ s: StoreDTO) -> String {
        "\(s.chain)|\(s.osmId ?? s.storeRef)|\(s.lat ?? 0),\(s.lng ?? 0)"
    }

    /// Nur 8–21 Uhr.
    static func allowed(hour: Int) -> Bool { (8..<21).contains(hour) }

    static func message(chain: String, open: Int) -> String {
        "🛒 Du bist bei \(Labels.chain(chain)): \(open == 1 ? "1 Sache" : "\(open) Sachen") auf der Liste"
    }

    #if DEBUG
    static func selfTest() {
        let far = StoreDTO(chain: "lidl", osmId: "a", lat: 51.0, lng: 7.0)
        let near = StoreDTO(chain: "rewe", osmId: "b", lat: 50.9376, lng: 6.9604)
        let off = StoreDTO(chain: "dm", enabled: false, osmId: "c", lat: 50.9375, lng: 6.9603)
        let noPos = StoreDTO(chain: "aldi_sued")
        assert(pick([far, near, off, noPos], near: CLLocationCoordinate2D(latitude: 50.9375, longitude: 6.9603)).map(\.chain) == ["rewe", "lidl"])
        assert(pick(Array(repeating: near, count: 25), near: nil).count == 20)
        assert(id(near).hasPrefix("rewe|b|"))
        assert(allowed(hour: 8) && allowed(hour: 20) && !allowed(hour: 21) && !allowed(hour: 7))
        assert(message(chain: "rewe", open: 4) == "🛒 Du bist bei Rewe: 4 Sachen auf der Liste")
        assert(message(chain: "lidl", open: 1) == "🛒 Du bist bei Lidl: 1 Sache auf der Liste")
    }
    #endif

    // MARK: Betreten

    private func entered(_ id: String) async {
        let chain = String(id.prefix { c in c != "|" })
        let now = Date.now
        let day = now.formatted(.iso8601.year().month().day())
        var last = UserDefaults.standard.dictionary(forKey: "storeReminderLast") as? [String: String] ?? [:]
        guard enabled, Self.allowed(hour: Calendar.current.component(.hour, from: now)), last[id] != day else { return }
        let background = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)  // im Hintergrund geweckt: Zeit für die Abfrage
        defer { UIApplication.shared.endBackgroundTask(background) }
        let open = await Self.openItems(chain)
        guard open > 0 else { return }
        last[id] = day
        UserDefaults.standard.set(last, forKey: "storeReminderLast")
        let content = UNMutableNotificationContent()
        content.body = Self.message(chain: chain, open: open)
        content.sound = .default
        content.userInfo = ["url": "essenapp://list/\(chain)"]  // → Laden-Liste
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "store-\(id)", content: content, trigger: nil))
    }

    /// Offene Artikel dieser Kette auf der Haushaltsliste (Server, ohne Netz der zuletzt geladene Stand).
    private static func openItems(_ chain: String) async -> Int {
        let api = API()
        guard let lists: [ListSummaryDTO] = try? await api.request("GET", "/lists"),
              let id = lists.first(where: { l in l.kind == "household" })?.id,
              let list: ListDTO = try? await api.request("GET", "/lists/\(id)") else { return 0 }
        return list.items.filter { i in !i.checked && i.chain == chain }.count
    }

    // MARK: CLLocationManagerDelegate (Aufrufe kommen auf dem Main-Thread, der den Manager erzeugt hat)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.status = s
            self.sync()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let id = region.identifier
        Task { @MainActor in await self.entered(id) }
    }
}

/// Einstellungen › Benachrichtigungen: „Erinnern, wenn ich in einem Laden bin“ (36). Einschalten ohne „Immer“ → Erklär-Sheet.
struct StoreReminderCard: View {
    @Environment(\.openURL) private var openURL
    @State private var reminder = StoreReminder.shared
    @State private var ask = Demo.screen == "storeask"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Erinnern, wenn ich in einem Laden bin", isOn: Binding(get: { reminder.enabled }, set: { on in
                if on && reminder.status != .authorizedAlways { ask = true } else { reminder.enabled = on }
            }))
            .font(.system(.body, weight: .semibold))
            Text("Bis zu 20 deiner Läden (nächste zuerst), 8–21 Uhr, höchstens einmal pro Laden und Tag – nur wenn dort etwas auf der Liste steht.")
                .font(Theme.F.micro).foregroundStyle(Theme.C.text2)
            if reminder.enabled {
                if reminder.status != .authorizedAlways {
                    Text(reminder.status == .authorizedWhenInUse ? "Standort steht auf „Beim Verwenden“ – für Erinnerungen „Immer“ wählen."
                                                                  : "Standort ist in iOS nicht erlaubt.")
                        .font(Theme.F.caption).foregroundStyle(Theme.C.danger)
                    Button("In iOS-Einstellungen öffnen") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                        .buttonStyle(SecondaryButtonStyle())
                } else if reminder.watched == 0 {
                    Text("Noch kein Laden mit Standort – wähle deine Läden auf der Karte (Einstellungen › Läden & Filialen).")
                        .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                } else {
                    Label("\(reminder.watched) \(reminder.watched == 1 ? "Laden" : "Läden") überwacht", systemImage: "location.fill")
                        .font(Theme.F.caption).foregroundStyle(Theme.C.success)
                }
            }
        }
        .tint(Theme.C.accent)
        .padding(16).card()
        .animation(Theme.spring, value: reminder.enabled)
        .sheet(isPresented: $ask) {
            PushPermissionSheet(emoji: "📍", title: "Erinnerung im Laden",
                                text: "Bist du bei einem deiner Läden, sagen wir dir, was dort auf der Liste steht. Dafür braucht die App den Standort „Immer“ – er bleibt auf deinem iPhone.",
                                allowTitle: "Standort erlauben") {
                if reminder.status == .denied || reminder.status == .restricted {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } else {
                    reminder.requestAlways()
                }
                if await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined {
                    _ = await PushPermission.request()
                }
                reminder.enabled = true
            }
            .presentationDetents([.medium]).presentationCornerRadius(Theme.R.sheet)
        }
    }
}
