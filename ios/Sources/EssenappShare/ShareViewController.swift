import EssenappShareUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Teilen-Erweiterung „Essenapp“ (Feature 5): nimmt Link/Text aus Instagram & Co. und importiert das Rezept (S20).
/// Anmeldung über Kopplungscode, Token im eigenen Schlüsselbund (keine App Group, E48).
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = shareBackground  // hell/dunkel wie ST.bg (68)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let (url, text) = await sharedContent()
            let root = ShareFlowView(input: ShareInput.parse(url: url, text: text), session: ShareKeychain.load(), persist: true) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
            let host = UIHostingController(rootView: root)
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }
    }

    /// Erster Link und Text aus den Anhängen (Instagram schickt den Link mal als URL, mal als Text).
    private func sharedContent() async -> (String?, String?) {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?.flatMap { item in item.attachments ?? [] } ?? []
        var url: String?, text: String?
        for p in providers where url == nil && p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            url = (try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL)?.absoluteString
        }
        for p in providers where text == nil && p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            text = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String
        }
        return (url, text)
    }
}
