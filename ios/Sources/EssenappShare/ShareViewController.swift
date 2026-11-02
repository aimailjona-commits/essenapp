import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Spike (Phase 9, A1): Teilen-Erweiterung „Essenapp“ – zeigt den geteilten Link und prüft die App Group.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let group = UserDefaults(suiteName: "group.de.jsenf.essenapp")
        let groupOK = group?.string(forKey: "probe") ?? "keine App Group"
        Task { @MainActor in
            let url = await sharedURL()
            let host = UIHostingController(rootView: SpikeView(url: url, group: groupOK) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            })
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }
    }

    private func sharedURL() async -> String {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?.flatMap { $0.attachments ?? [] } ?? []
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL { return url.absoluteString }
        }
        for p in providers where p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String { return text }
        }
        return "(nichts erkannt)"
    }
}

struct SpikeView: View {
    let url: String
    let group: String
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Essenapp").font(.title.bold())
            Text("Geteilt:").font(.footnote).foregroundStyle(.secondary)
            Text(url).font(.callout).lineLimit(4)
            Text("App Group: \(group)").font(.footnote).foregroundStyle(.secondary)
            Button("Fertig", action: done).buttonStyle(.borderedProminent).tint(.orange)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.96))
    }
}
