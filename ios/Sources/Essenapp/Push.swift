import SwiftUI
import UserNotifications

// Mitteilungen über Apple Push (APNs). Ohne `aps-environment`-Entitlement schlägt die Registrierung still fehl.

/// App-Delegate: Geräte-Token ans Backend, Antippen einer Mitteilung → `pendingURL` (MainView leitet weiter).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    @Published var pendingURL: URL?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        _ = StoreReminder.shared  // Region-Ereignisse (36) auch, wenn iOS die App im Hintergrund weckt
        // Wochenplan-Erinnerung (Backend-Job plan_prompt): „Plan erstellen“ öffnet den Generator, „Später“ schließt nur
        UNUserNotificationCenter.current().setNotificationCategories([UNNotificationCategory(
            identifier: "PLAN_PROMPT",
            actions: [UNNotificationAction(identifier: "PLAN_CREATE", title: "Plan erstellen", options: [.foreground]),
                      UNNotificationAction(identifier: "LATER", title: "Später", options: [])],
            intentIdentifiers: [])])
        Task {  // schon erlaubt → Token bei jedem Start auffrischen
            if await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized {
                application.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        struct Body: Encodable { var token: String; var environment: String }
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let environment = "development"  // Debug-Build → APNs-Sandbox
        #else
        let environment = "production"
        #endif
        Task { _ = try? await API().send("POST", "/me/push/device", body: Body(token: token, environment: environment)) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // auch im Vordergrund als Banner; Koch-Timer klingeln bei offenem Kochmodus in der App selbst (Ton, Haptik, Banner)
        let cookTimer = notification.request.identifier.hasPrefix("timer-") && CookTimers.cookingOpen
        completionHandler(cookTimer ? [.list] : [.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let url = (response.notification.request.content.userInfo["url"] as? String).flatMap(URL.init(string:))
            ?? (response.actionIdentifier == "PLAN_CREATE" ? URL(string: "essenapp://generator") : nil)
        completionHandler()
        guard response.actionIdentifier != "LATER", let url else { return }
        Task { @MainActor in self.pendingURL = url }
    }
}

/// = backend PushSettings. `quiet_hours` wird immer gesendet: null = Ruhezeit aus.
struct PushSettingsDTO: Codable, Equatable {
    struct Quiet: Codable, Equatable {
        var start: String  // "HH:MM"
        var end: String
    }

    var pushEnabled: Bool
    var planPromptEnabled: Bool
    var planPromptWeekday: Int  // 0 = Montag
    var planPromptTime: String
    var quietHours: Quiet?
    var lunchboxPush: String? = nil  // „Lunchbox für morgen vorbereiten“ um HH:MM (24), nil = aus

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pushEnabled, forKey: .pushEnabled)
        try c.encode(planPromptEnabled, forKey: .planPromptEnabled)
        try c.encode(planPromptWeekday, forKey: .planPromptWeekday)
        try c.encode(planPromptTime, forKey: .planPromptTime)
        try c.encode(quietHours, forKey: .quietHours)
        try c.encode(lunchboxPush, forKey: .lunchboxPush)
    }
}

extension AppStore {
    func pushSettings() async throws -> PushSettingsDTO {
        demo ? Demo.pushSettings : try await api.request("GET", "/me/push/settings")
    }

    func savePushSettings(_ s: PushSettingsDTO) async {
        guard !demo else { return }
        do { let _: PushSettingsDTO = try await api.request("PATCH", "/me/push/settings", body: s) } catch { flash("Nicht gespeichert: \(error.localizedDescription)") }
    }

    func testPush() async {
        do {
            if !demo { try await api.send("POST", "/me/push/test") }
            flash("Test-Push gesendet")
        } catch APIError.http(422) {  // kein Gerät registriert
            flash("Erst Mitteilungen erlauben")
        } catch APIError.http(502) {
            flash("Apple hat abgelehnt")
        } catch {
            flash("Push konnte nicht gesendet werden")
        }
    }
}

enum PushPermission {
    /// Systemabfrage; bei Erlaubnis beim APNs registrieren.
    @MainActor static func request() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }
}


/// Fragt einmal freundlich vor der Systemabfrage (nach dem Onboarding bzw. beim ersten Öffnen der Einstellungen).
struct PushAsk: ViewModifier {
    @Environment(AppStore.self) private var store
    var active = true
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .task(id: active) {
                guard active, !store.demo, !UserDefaults.standard.bool(forKey: "pushAsked"),
                      await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined else { return }
                UserDefaults.standard.set(true, forKey: "pushAsked")
                show = true
            }
            .sheet(isPresented: $show) { PushPermissionSheet() }
    }
}

/// Erklär-Sheets vor der iOS-Abfrage (e.html): „Nichts verpassen“ (Fernglas, drei Gründe) und – mit `emoji: "📍"` –
/// „Erinnerung im Laden“ (Einkäufer, Pin-Kreis). Eigener `text` ersetzt Satz und Gründe (z. B. Koch-Timer).
struct PushPermissionSheet: View {
    @Environment(\.dismiss) private var dismiss
    var emoji = "🔔"
    var title = "Nichts verpassen"
    var text: String?
    var allowTitle = "Mitteilungen erlauben"
    var allow: @MainActor () async -> Void = { _ = await PushPermission.request() }
    @State private var height: CGFloat = 560

    private var place: Bool { emoji == "📍" }  // Standort-Variante (StoreReminderCard)

    // Mockup-Maße (e.html Erklär-Sheets), relativ zur Sheet-Oberkante unter dem Griff
    private let titleWidth: CGFloat = 190
    private let introWidth: CGFloat = 180

    /// Höhe passt sich dem Text an (mit großer Schrift mehr) – nichts wird abgeschnitten.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if place {
                    Icon(.pin).foregroundStyle(Theme.C.onInk).frame(width: 48, height: 48).background(Theme.C.ink, in: Circle())
                        .padding(.top, 10).accessibilityHidden(true)
                }
                Text(title).font(Theme.F.t1).frame(maxWidth: titleWidth, alignment: .leading).padding(.top, place ? 14 : 20)
                if place || text != nil {
                    Text(text ?? "").font(Theme.F.text(15, relativeTo: .subheadline)).lineSpacing(5).foregroundStyle(Theme.C.ink2)
                        .padding(.top, place ? 26 : 10)
                        .frame(maxWidth: place ? .infinity : introWidth + 100, alignment: .leading)
                } else {
                    Text("Wir melden uns nur, wenn es sich lohnt.").font(Theme.F.text(15, relativeTo: .subheadline)).lineSpacing(5)
                        .foregroundStyle(Theme.C.ink2).frame(maxWidth: introWidth, alignment: .leading).padding(.top, 10)
                    VStack(spacing: 0) {
                        ERow("Sonntags: Zeit für den Wochenplan", lead: .icon(.cal), tint: Theme.C.sage, chevron: false)
                        ERow("Angebote von deiner Merkliste", lead: .icon(.tag), tint: Theme.C.rose, chevron: false)
                        ERow("Lunchbox am Vorabend", lead: .icon(.box), tint: Theme.C.sand, chevron: false)
                    }
                    .padding(.top, 34)
                }
                PrimaryButton(title: allowTitle, icon: place ? .pin : .bell) { Task { await allow(); dismiss() } }
                    .padding(.top, place ? 24 : 22)
                OutlineButton(title: "Später") { dismiss() }.padding(.top, 10)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 40)
            .background(alignment: .topTrailing) {
                Color.clear
                    .pinned(right: place ? 18 : 4, top: place ? 20 - 33 : 26 - 33) {
                        Ill(place ? "shopper" : "binoculars").frame(width: place ? 150 : 160)
                    }
                    .edgeForm(.circle, place ? Theme.C.sage : Theme.C.blue1, width: place ? 270 : 250, height: place ? 270 : 250,
                              right: place ? -90 : -70, top: place ? -40 - 33 : -30 - 33)
            }
            .onGeometryChange(for: CGFloat.self) { g in g.size.height } action: { h in height = h + 33 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .sheet8()
        .presentationDetents([.height(height)])
    }
}

/// S13 › Mitteilungen: Hauptschalter mit Test-Push, Arten und Ruhezeit als Schalter-Zeilen, Erinnerung im Laden.
struct NotificationsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = UNAuthorizationStatus.notDetermined
    @State private var settings: PushSettingsDTO?
    @State private var error: String?
    @State private var testing = false

    // Mockup-Maße (e.html S13 › Mitteilungen)
    private let blob = (right: CGFloat(-110), top: CGFloat(-110), size: CGFloat(290))
    private let ill = (right: CGFloat(6), top: CGFloat(56), width: CGFloat(124))
    private let indent: CGFloat = 44

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EBack()
                Text("Mitteilungen").font(Theme.F.t1).padding(.top, 10)
                permission.padding(.top, 28)
                if let s = Binding($settings) {
                    kinds(s)
                    StoreReminderCard()
                } else if let error {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(error).font(Theme.F.text(13, relativeTo: .footnote)).foregroundStyle(Theme.C.deal)
                        OutlineButton(title: "Erneut versuchen") { Task { await load() } }
                    }
                    .padding(.top, 28)
                } else {
                    VStack(spacing: 10) { ForEach(0..<4, id: \.self) { _ in Skeleton8(height: 44) } }.padding(.top, 28)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .background(alignment: .topTrailing) {
            Color.clear
                .pinned(right: ill.right, top: ill.top) { Ill("binoculars").frame(width: ill.width) }
                .edgeForm(.circle, Theme.C.blue1, width: blob.size, height: blob.size, right: blob.right, top: blob.top)
                .ignoresSafeArea()
        }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
        .task { await load() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await loadStatus() } } }  // zurück aus den iOS-Einstellungen
        .onChange(of: settings) { old, new in
            if old != nil, let new { Task { await store.savePushSettings(new) } }  // sofort speichern (S13)
        }
        .animation(Theme.spring, value: settings)
    }

    /// Hauptschalter (Push an/aus beim Server) und je nach iOS-Erlaubnis: erlauben, iOS-Einstellungen oder Test-Push.
    @ViewBuilder private var permission: some View {
        ERow("Mitteilungen", sub: status == .authorized ? "In iOS erlaubt" : status == .denied ? "In iOS ausgeschaltet" : "Noch nicht erlaubt",
             lead: .icon(.bell), tint: Theme.C.blue1, chevron: false) {
            if settings != nil {
                ESwitch(isOn: Binding(get: { settings?.pushEnabled ?? false }, set: { settings?.pushEnabled = $0 }), label: "Mitteilungen")
            }
        }
        switch status {
        case .denied:
            OutlineButton(title: "In iOS-Einstellungen öffnen") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            }
            .padding(.top, 6)
        case .notDetermined:
            PrimaryButton(title: "Mitteilungen erlauben", icon: .bell) { Task { _ = await PushPermission.request(); await loadStatus() } }
                .padding(.top, 6)
        default:
            Button {
                testing = true
                Task { await store.testPush(); testing = false }
            } label: {
                Text(testing ? "Sende …" : "Test-Push senden").font(Theme.F.button2).foregroundStyle(Theme.C.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .overlay(Capsule().strokeBorder(Theme.C.ink, lineWidth: Theme.S.hair))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .disabled(testing)
            .padding(.top, 6)
        }
    }

    @ViewBuilder private func kinds(_ s: Binding<PushSettingsDTO>) -> some View {
        SectionLabel("Worüber").padding(.top, 28).padding(.bottom, 4)
        ERow("Wochenplan-Erinnerung", sub: "\(Labels.dayNames[s.wrappedValue.planPromptWeekday]) · \(s.wrappedValue.planPromptTime)",
             lead: .icon(.cal), tint: Theme.C.sage, chevron: false) {
            ESwitch(isOn: s.planPromptEnabled, label: "Wochenplan-Erinnerung")
        }
        if s.wrappedValue.planPromptEnabled {
            detail("Wochentag") {
                Picker("Wochentag", selection: s.planPromptWeekday) {
                    ForEach(0..<7, id: \.self) { d in Text(Labels.dayNames[d]).tag(d) }
                }
                .pickerStyle(.menu)
            }
            detail("Uhrzeit") { timePicker("Uhrzeit Wochenplan", s.planPromptTime) }
        }
        ERow("Lunchbox-Erinnerung", sub: s.wrappedValue.lunchboxPush.map { "am Vorabend · \($0)" } ?? "am Vorabend deiner Lunchbox-Tage",
             lead: .icon(.box), tint: Theme.C.blue1, chevron: false) {
            ESwitch(isOn: Binding(get: { s.wrappedValue.lunchboxPush != nil }, set: { on in s.wrappedValue.lunchboxPush = on ? "20:00" : nil }),
                    label: "Lunchbox-Erinnerung")
        }
        if s.wrappedValue.lunchboxPush != nil {
            detail("Uhrzeit") {
                timePicker("Uhrzeit Lunchbox", Binding(get: { s.wrappedValue.lunchboxPush ?? "20:00" }, set: { v in s.wrappedValue.lunchboxPush = v }))
            }
        }
        ERow("Ruhezeit", sub: s.wrappedValue.quietHours.map { "\($0.start) – \($0.end)" } ?? "keine Mitteilungen in der Nacht",
             lead: .icon(.clock), tint: Theme.C.rose, chevron: false) {
            ESwitch(isOn: Binding(get: { s.wrappedValue.quietHours != nil }, set: { on in
                s.wrappedValue.quietHours = on ? PushSettingsDTO.Quiet(start: "22:00", end: "07:00") : nil
            }), label: "Ruhezeit")
        }
        if s.wrappedValue.quietHours != nil {
            detail("Von") {
                timePicker("Ruhezeit von", Binding(get: { s.wrappedValue.quietHours?.start ?? "22:00" }, set: { v in s.wrappedValue.quietHours?.start = v }))
            }
            detail("Bis") {
                timePicker("Ruhezeit bis", Binding(get: { s.wrappedValue.quietHours?.end ?? "07:00" }, set: { v in s.wrappedValue.quietHours?.end = v }))
            }
        }
    }

    /// Unterzeile einer Schalter-Zeile (eingerückt wie der Erklärtext im Mockup).
    private func detail(_ title: String, @ViewBuilder _ control: () -> some View) -> some View {
        HStack {
            Text(title).font(Theme.F.text(13, .bold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
            Spacer()
            control()
        }
        .tint(Theme.C.ink)
        .frame(minHeight: 44)
        .padding(.leading, indent)
    }

    private func timePicker(_ label: String, _ text: Binding<String>) -> some View {
        DatePicker(label, selection: time(text), displayedComponents: .hourAndMinute).labelsHidden()
    }

    /// "HH:MM" ↔ Date für den DatePicker.
    private func time(_ text: Binding<String>) -> Binding<Date> {
        Binding(get: {
            let hm = text.wrappedValue.split(separator: ":").compactMap { Int($0) }
            return Calendar.current.date(bySettingHour: hm.first ?? 18, minute: hm.count > 1 ? hm[1] : 0, second: 0, of: .now) ?? .now
        }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            text.wrappedValue = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        })
    }

    private func loadStatus() async {
        status = store.demo ? .authorized : await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func load() async {
        await loadStatus()
        do {
            settings = try await store.pushSettings()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
