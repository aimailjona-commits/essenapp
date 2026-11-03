import ActivityKit
import EssenappShareUI
import Foundation

/// Live-Aktivität beim Einkaufen (37): Start in der Laden-Liste, folgt der Haushaltsliste (Abhaken in App, Live-Aktivität
/// oder bei den anderen), endet bei „alles abgehakt“ oder nach 2 h. Nur lokal (kein Push-Token, kostenlose Apple-ID).
@MainActor
enum LiveShop {
    static let maxDuration: TimeInterval = 2 * 3600

    static var available: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    static func running(_ chain: String) -> Bool { Activity<ShopAttributes>.activities.contains { a in a.attributes.chain == chain } }

    /// Stand eines Ladens: erledigt/gesamt (ohne „Nächste Woche“) und die nächsten 3 offenen Artikel wie in S5b sortiert.
    static func state(_ list: ListDTO?, chain: String) -> ShopAttributes.ContentState? {
        guard let list else { return nil }
        let items = list.items.filter { i in i.chain == chain && i.nextWeek != true }
        let open = items.filter { i in !i.checked }.sorted { a, b in a.name < b.name }
        return .init(done: items.count - open.count, total: items.count, next: open.prefix(3).map { i in
            .init(id: i.id, name: i.name, amount: i.amount.map { a in "\(num(a, 0...2)) \(Labels.unit(i.unit))" } ?? "")
        })
    }

    static func start(chain: String, list: ListDTO?) throws {
        guard let state = state(list, chain: chain), state.done < state.total else { return }
        end()  // ein Einkauf zur Zeit
        let name = chain.isEmpty ? "Überall" : Labels.chain(chain)
        let attributes = ShopAttributes(chain: chain, name: name, short: String(name.prefix(1)), tint: Theme.storeHex(chain), started: .now)
        _ = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: .now + maxDuration))
        Task {  // läuft nur, solange die App lebt; sonst beendet `sync` beim nächsten Laden der Liste
            try? await Task.sleep(for: .seconds(maxDuration))
            sync(nil)
        }
    }

    /// Aktualisiert laufende Aktivitäten; beendet sie nach 2 h oder wenn alles abgehakt ist.
    /// `Activity` ist nicht Sendable → Stände hier ausrechnen, die Aktivitäten nur im losgelösten Task anfassen.
    static func sync(_ list: ListDTO?) {
        let chains = Set(Activity<ShopAttributes>.activities.map { a in a.attributes.chain })
        guard !chains.isEmpty else { return }
        let states = Dictionary(uniqueKeysWithValues: chains.map { c in (c, state(list, chain: c)) })
        let limit = maxDuration
        Task.detached {
            for activity in Activity<ShopAttributes>.activities {
                let stale = activity.attributes.started + limit
                let new = states[activity.attributes.chain] ?? nil
                if Date.now >= stale {
                    await activity.end(nil, dismissalPolicy: .immediate)
                } else if let new, new.total > 0, new.done == new.total {
                    await activity.end(.init(state: new, staleDate: nil), dismissalPolicy: .default)
                } else if let new, new != activity.content.state {
                    await activity.update(.init(state: new, staleDate: stale))
                }
            }
        }
    }

    /// Nur die jetzt laufenden – eine gleich danach gestartete bleibt.
    static func end() {
        let ids = Set(Activity<ShopAttributes>.activities.map(\.id))
        Task.detached {
            for activity in Activity<ShopAttributes>.activities where ids.contains(activity.id) { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    static func selfTest() {
        let list = ListDTO(id: 1, name: "", kind: "household", shareUrl: nil, items: [
            Demo.item(1, "Milch", 1, "l", "rewe", nil), Demo.item(2, "Brot", nil, "", "rewe", nil, checked: true),
            Demo.item(3, "Feta", 200, "g", "lidl", nil), Demo.item(4, "Butter", 1, "stk", "rewe", nil, next: true),
        ])
        let s = state(list, chain: "rewe")
        assert(s?.done == 1 && s?.total == 2 && s?.next.map(\.name) == ["Milch"] && s?.next.first?.amount == "1 l", "Live-Aktivität: Stand je Laden")
    }
}
