import SwiftUI
import UserNotifications

// Mitteilungen über Apple Push (APNs). Ohne `aps-environment`-Entitlement schlägt die Registrierung still fehl.

/// App-Delegate: Geräte-Token ans Backend, Antippen einer Mitteilung → `pendingURL` (MainView leitet weiter).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    @Published var pendingURL: URL?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
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
        Task { _ = try? await API().send("POST", "/me/push/device", body: Body(token: token, environment: "development")) }
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
        completionHandler()
        guard let url else { return }
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

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pushEnabled, forKey: .pushEnabled)
        try c.encode(planPromptEnabled, forKey: .planPromptEnabled)
        try c.encode(planPromptWeekday, forKey: .planPromptWeekday)
        try c.encode(planPromptTime, forKey: .planPromptTime)
        try c.encode(quietHours, forKey: .quietHours)
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
            .sheet(isPresented: $show) { PushPermissionSheet().presentationDetents([.medium]).presentationCornerRadius(Theme.R.sheet) }
    }
}

/// Erklär-Sheet vor der iOS-Abfrage.
struct PushPermissionSheet: View {
    @Environment(\.dismiss) private var dismiss
    var text = "Wir erinnern dich ans Planen der Woche und melden, wenn deine Lieblingsprodukte im Angebot sind. Ruhezeiten stellst du selbst ein."

    var body: some View {
        VStack(spacing: 14) {
            EmptyState(emoji: "🔔", title: "Nichts verpassen", text: text)
            Button("Mitteilungen erlauben") { Task { _ = await PushPermission.request(); dismiss() } }
                .buttonStyle(PrimaryButtonStyle())
            Button("Später") { dismiss() }.buttonStyle(SecondaryButtonStyle())
        }
        .padding(Theme.pagePadding)
        .presentationBackground(Theme.C.bg)
    }
}

/// Einstellungen › Benachrichtigungen.
struct NotificationsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = UNAuthorizationStatus.notDetermined
    @State private var settings: PushSettingsDTO?
    @State private var error: String?
    @State private var testing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                DisplayHeader(line1: "Benachrichtigungen", line2: "Erinnerungen & Angebote")
                permissionCard
                if let s = Binding($settings) {
                    settingsCard(s)
                } else if let error {
                    ErrorState(message: error) { Task { await load() } }
                } else {
                    SkeletonCard(height: 220)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
        }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await loadStatus() } } }  // zurück aus den iOS-Einstellungen
        .onChange(of: settings) { old, new in
            if old != nil, let new { Task { await store.savePushSettings(new) } }  // sofort speichern (S13)
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: status == .authorized ? "bell.badge.fill" : "bell.slash.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(status == .authorized ? Theme.C.success : Theme.C.text2)
                    .frame(width: 34, height: 34)
                    .background((status == .authorized ? Theme.C.success : Theme.C.text2).opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mitteilungen").font(.system(.body, weight: .semibold))
                    Text(status == .authorized ? "an" : status == .denied ? "in iOS ausgeschaltet" : "noch nicht erlaubt")
                        .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                }
                Spacer()
            }
            switch status {
            case .denied:
                Button("In iOS-Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
                .buttonStyle(SecondaryButtonStyle())
            case .notDetermined:
                Button("Mitteilungen erlauben") { Task { _ = await PushPermission.request(); await loadStatus() } }
                    .buttonStyle(PrimaryButtonStyle())
            default:
                Button {
                    testing = true
                    Task { await store.testPush(); testing = false }
                } label: { Label(testing ? "Sende …" : "Test-Push senden", systemImage: "paperplane.fill") }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(testing)
            }
        }
        .padding(14).card()
    }

    private func settingsCard(_ s: Binding<PushSettingsDTO>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Push-Mitteilungen", isOn: s.pushEnabled).font(.system(.body, weight: .semibold))
            Divider()
            Toggle("Erinnerung: Wochenplan erstellen", isOn: s.planPromptEnabled)
            if s.wrappedValue.planPromptEnabled {
                Picker("Wochentag", selection: s.planPromptWeekday) {
                    ForEach(0..<7, id: \.self) { d in Text(Labels.dayNames[d]).tag(d) }
                }
                DatePicker("Uhrzeit", selection: time(s.planPromptTime), displayedComponents: .hourAndMinute)
            }
            Divider()
            Toggle("Ruhezeit", isOn: Binding(get: { s.wrappedValue.quietHours != nil }, set: { on in
                s.wrappedValue.quietHours = on ? PushSettingsDTO.Quiet(start: "22:00", end: "07:00") : nil
            }))
            if s.wrappedValue.quietHours != nil {
                DatePicker("Von", selection: time(Binding(get: { s.wrappedValue.quietHours?.start ?? "22:00" },
                                                          set: { v in s.wrappedValue.quietHours?.start = v })), displayedComponents: .hourAndMinute)
                DatePicker("Bis", selection: time(Binding(get: { s.wrappedValue.quietHours?.end ?? "07:00" },
                                                          set: { v in s.wrappedValue.quietHours?.end = v })), displayedComponents: .hourAndMinute)
                Text("In der Ruhezeit kommen keine Mitteilungen.").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
            }
        }
        .tint(Theme.C.accent)
        .padding(16).card()
        .animation(Theme.spring, value: s.wrappedValue)
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
