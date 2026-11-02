import SwiftUI

@main
struct EssenappApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate  // Push (APNs), liegt als EnvironmentObject bereit
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
