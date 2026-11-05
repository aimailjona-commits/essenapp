import EssenappShareUI
import SwiftUI

@main
struct EssenappApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate  // Push (APNs), liegt als EnvironmentObject bereit

    init() {
        Theme.registerFonts()
        ShareArt.potLoader = { AnyView(PotLoader()) }  // v8-Zeichnungen für EssenappShareUI (in der App)
        CheckItemIntent.handler = { id in await AppStore.shared.checkFromActivity(id) }  // Knopf in der Live-Aktivität (37)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
