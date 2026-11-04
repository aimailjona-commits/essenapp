import StoreKit
import SwiftUI

/// Pro-Stand des Haushalts (GET /pro, 19.8).
struct ProDTO: Codable {
    var paywall: Bool
    var pro: Bool
    var until: String?
    var trialUntil: String?
    var adCredits: Int
    var freePlansLeft: Int
    var price: String
    var features: [String: String]
}

/// Abo über StoreKit 2; geprüft wird auf dem Server (App Store Server API), freigeschaltet der ganze Haushalt (R11).
enum ProStore {
    static let productID = "de.jsenf.essenapp.pro.monthly"

    /// Gekaufte oder verlängerte Transaktion beim Server eintragen und abschließen.
    @MainActor static func register(_ result: VerificationResult<StoreKit.Transaction>, store: AppStore) async -> Bool {
        guard case .verified(let t) = result, t.productID == productID else { return false }
        struct Body: Encodable { var originalTransactionId: String }
        do {
            store.pro = try await store.api.request("POST", "/pro/apple", body: Body(originalTransactionId: String(t.originalID)))
            await t.finish()
            return true
        } catch {
            store.flash("Abo nicht bestätigt: \(error.localizedDescription)")
            return false
        }
    }

    /// Läuft die ganze App-Zeit: Verlängerungen und Käufe von anderen Geräten derselben Apple-ID.
    @MainActor static func listen(store: AppStore) async {
        for await update in StoreKit.Transaction.updates { _ = await register(update, store: store) }
    }
}

extension AppStore {
    func loadPro() async {
        guard !demo else { return }
        pro = try? await api.request("GET", "/pro", cache: false)
    }
}

/// Paywall (19.8): immer schließbar, Preis groß, Kündigen-Hinweis; erscheint bei einer 402-Antwort des Servers.
struct PaywallSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let reason: String
    @State private var product: Product?
    @State private var busy = false

    private var features: [String] {
        let all = store.pro?.features ?? [:]
        return ["plan", "reroll_direction", "scan", "import", "step_images", "no_mood", "substitutes", "price_alert"].compactMap { all[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Spacer()
                RoundIconButton(systemName: "xmark", label: "Schließen") { dismiss() }
            }
            DisplayHeader(line1: "Kochpilot", line2: "Pro")
            if !reason.isEmpty {
                Text(reason.replacingOccurrences(of: "Pro: ", with: "") + " gehört zu Pro.")
                    .font(Theme.F.callout).foregroundStyle(Theme.C.text1)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(features, id: \.self) { f in
                    Label(f, systemImage: "checkmark.circle.fill").font(Theme.F.caption).foregroundStyle(Theme.C.text1)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).card()
            VStack(alignment: .leading, spacing: 4) {
                Text(product.map { "\($0.displayPrice) im Monat" } ?? store.pro?.price ?? "3 € im Monat")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                if let offer = product?.subscription?.introductoryOffer, offer.paymentMode == .freeTrial {
                    Text("\(offer.period.value) \(unit(offer.period.unit)) gratis testen, danach \(product?.displayPrice ?? "") im Monat. Wir erinnern dich 2 Tage vor Ende.")
                        .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                }
                Text("Gilt für alle im Haushalt. Jederzeit in den iOS-Einstellungen kündbar.")
                    .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            }
            Spacer()
            Button(action: buy) {
                HStack {
                    if busy { ProgressView().tint(Theme.C.onAction) }
                    Text(busy ? "Einen Moment …" : "Pro holen")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(product == nil || busy)
            Button("Käufe wiederherstellen", action: restore)
                .font(Theme.F.caption).frame(maxWidth: .infinity, minHeight: 44)
                .disabled(busy)
        }
        .padding(.horizontal, Theme.pagePadding).padding(.vertical, 16)
        .background(Theme.C.bg.ignoresSafeArea())
        .task {
            product = try? await Product.products(for: [ProStore.productID]).first
            await store.loadPro()
        }
    }

    private func unit(_ u: Product.SubscriptionPeriod.Unit) -> String {
        switch u {
        case .day: "Tage"
        case .week: "Wochen"
        case .month: "Monate"
        default: "Jahre"
        }
    }

    private func buy() {
        guard let product else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                if case .success(let result) = try await product.purchase(), await ProStore.register(result, store: store) {
                    store.flash("Pro ist aktiv – für den ganzen Haushalt")
                    dismiss()
                }
            } catch {
                store.flash("Kauf nicht möglich: \(error.localizedDescription)")
            }
        }
    }

    private func restore() {
        busy = true
        Task {
            defer { busy = false }
            try? await StoreKit.AppStore.sync()
            for await result in StoreKit.Transaction.currentEntitlements where await ProStore.register(result, store: store) {
                store.flash("Pro wiederhergestellt")
                dismiss()
                return
            }
            store.flash("Kein Abo gefunden")
        }
    }
}
