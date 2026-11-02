import SwiftUI

// Teilen (E40): gemeinsame Haushaltsliste im Backend, einmalige Listen mit Gast-Link, Einladungen.

struct ListItemDTO: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var amount: Double?
    var unit: String
    var chain: String
    var offerId: Int?
    var checked: Bool
    var addedBy: String
    var checkedBy: String
    var source: String
}

struct ListDTO: Codable {
    var id: Int
    var name: String
    var kind: String
    var shareUrl: String?
    var items: [ListItemDTO]
}

struct ListSummaryDTO: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var kind: String
    var shareUrl: String?
    var openCount: Int
    var totalCount: Int
}

struct MemberDTO: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var role: String
}

struct URLDTO: Codable { var url: String }

extension AppStore {
    func loadLists() async {
        guard !demo else { return }
        do {
            lists = try await api.request("GET", "/lists")
            if let id = lists.first(where: { $0.kind == "household" })?.id {
                householdList = try await api.request("GET", "/lists/\(id)")
                if householdList?.items.isEmpty == true, plan != nil {  // ältere Pläne einmalig übernehmen
                    householdList = try await api.request("POST", "/lists/household/sync-plan")
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func list(_ id: Int) async throws -> ListDTO { try await api.request("GET", "/lists/\(id)") }

    func addItem(name: String, chain: String = "", offerId: Int? = nil, to listID: Int) async {
        struct Body: Encodable { var name: String; var chain: String; var offerId: Int? }
        guard !demo else { return }
        let _: ListItemDTO? = try? await api.request("POST", "/lists/\(listID)/items", body: Body(name: name, chain: chain, offerId: offerId))
        await loadLists()
    }

    /// Abhaken: sofort lokal, dann Server (gemeinsam mit allen Mitgliedern).
    func toggle(_ item: ListItemDTO) async {
        if let i = householdList?.items.firstIndex(where: { $0.id == item.id }) { householdList?.items[i].checked.toggle() }
        guard !demo, item.id > 0 else { return }
        struct Body: Encodable { var checked: Bool }
        let _: ListItemDTO? = try? await api.request("PATCH", "/items/\(item.id)", body: Body(checked: !item.checked))
    }

    func deleteItem(_ item: ListItemDTO) async {
        householdList?.items.removeAll { $0.id == item.id }
        guard !demo, item.id > 0 else { return }
        struct Empty: Decodable {}
        _ = try? await api.request("DELETE", "/items/\(item.id)") as Empty?
    }

    func createList(_ name: String) async {
        struct Body: Encodable { var name: String }
        guard !demo else { return }
        let _: ListSummaryDTO? = try? await api.request("POST", "/lists", body: Body(name: name))
        await loadLists()
    }

    func deleteList(_ id: Int) async {
        lists.removeAll { $0.id == id }
        guard !demo else { return }
        struct Empty: Decodable {}
        _ = try? await api.request("DELETE", "/lists/\(id)") as Empty?
    }

    func inviteURL() async -> URL? {
        if demo { return URL(string: "http://192.168.0.224:8000/join/demo1234") }
        let r: URLDTO? = try? await api.request("POST", "/household/invites")
        return r.flatMap { URL(string: $0.url) }
    }

    func members() async -> [MemberDTO] {
        if demo { return [MemberDTO(id: 1, name: "Jona", role: "owner"), MemberDTO(id: 2, name: "Malina", role: "member")] }
        return (try? await api.request("GET", "/household/members")) ?? []
    }

    func removeMember(_ m: MemberDTO) async {
        struct Empty: Decodable {}
        _ = try? await api.request("DELETE", "/household/members/\(m.id)") as Empty?
    }
}

/// Familie: Mitglieder und Einladungslink (Einstellungen).
struct FamilySection: View {
    @Environment(AppStore.self) private var store
    @State private var members: [MemberDTO] = []
    @State private var invite: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HAUSHALT TEILEN").font(Theme.F.micro).foregroundStyle(Theme.C.text2).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(members) { m in
                    HStack(spacing: 12) {
                        Text(String(m.name.prefix(1)).uppercased()).font(.system(.subheadline, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 34, height: 34).background(Theme.storeColor(Labels.chains[m.id % Labels.chains.count].key), in: Circle())
                        Text(m.name).font(.system(.body, weight: .semibold))
                        Spacer()
                        Text(m.role == "owner" ? "Besitzer" : "Mitglied").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                    }
                    .contextMenu {
                        if m.role != "owner" {
                            Button("Entfernen", systemImage: "person.badge.minus", role: .destructive) {
                                Task { await store.removeMember(m); members = await store.members() }
                            }
                        }
                    }
                }
                if let invite {
                    ShareLink(item: invite, subject: Text("Essenapp"),
                              message: Text("Komm in unseren Haushalt – Wochenplan & Einkaufsliste gemeinsam:")) {
                        Label("Person einladen", systemImage: "person.badge.plus").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Text("Der Link öffnet die Web-Version (7 Tage gültig). Andere brauchen keine App.")
                        .font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                }
            }
            .padding(14).card()
        }
        .task {
            members = await store.members()
            invite = await store.inviteURL()
        }
    }
}

/// Einmalige Liste (z.B. „Grillparty“) mit Gast-Link.
struct OneOffListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let summary: ListSummaryDTO
    @State private var list: ListDTO?
    @State private var newItem = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                    Spacer()
                    if let s = summary.shareUrl, let url = URL(string: s) {
                        ShareLink(item: url, message: Text("Unsere Liste „\(summary.name)“ – einfach öffnen und mit abhaken:")) {
                            Label("Teilen", systemImage: "square.and.arrow.up").font(Theme.F.callout)
                                .padding(.horizontal, 14).frame(height: 40).background(Theme.C.card, in: Capsule())
                        }
                    }
                }
                DisplayHeader(line1: summary.name, line2: "\(list?.items.filter { !$0.checked }.count ?? summary.openCount) offen")
                HStack(spacing: 10) {
                    TextField("Artikel hinzufügen …", text: $newItem).onSubmit(add)
                        .padding(.horizontal, 16).frame(height: 46).background(Theme.C.card, in: Capsule())
                    RoundIconButton(systemName: "plus", dark: true, label: "Hinzufügen", action: add)
                }
                ForEach(list?.items ?? []) { item in
                    Button { toggle(item) } label: { ItemRow(item: item, offer: nil) }.buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
        }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            while !Task.isCancelled {  // gemeinsames Einkaufen: alle 10 s aktualisieren
                list = try? await store.list(summary.id)
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func add() {
        let name = newItem.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        newItem = ""
        Task { await store.addItem(name: name, to: summary.id); list = try? await store.list(summary.id) }
    }

    private func toggle(_ item: ListItemDTO) {
        if let i = list?.items.firstIndex(where: { $0.id == item.id }) { list?.items[i].checked.toggle() }
        Task {
            struct Body: Encodable { var checked: Bool }
            let _: ListItemDTO? = try? await store.api.request("PATCH", "/items/\(item.id)", body: Body(checked: !item.checked))
        }
    }
}

/// Zeile einer Liste: Haken, Emoji, Name, Menge, wer hat's hinzugefügt/abgehakt, Preis.
struct ItemRow: View {
    let item: ListItemDTO
    let offer: OfferDTO?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24))
                .foregroundStyle(item.checked ? Theme.C.success : Theme.C.text3)
                .contentTransition(.symbolEffect(.replace))
            Text(offer.map { Theme.hue(category: $0.category).emoji } ?? (item.source == "plan" ? "🥄" : "📝")).font(.system(size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text(offer?.title ?? item.name).font(.system(.body, weight: .semibold)).strikethrough(item.checked)
                    .foregroundStyle(item.checked ? Theme.C.text3 : Theme.C.text1)
                let who = item.checked && !item.checkedBy.isEmpty ? "✓ \(item.checkedBy)" : (item.source == "manual" && !item.addedBy.isEmpty ? "von \(item.addedBy)" : "")
                let amount = item.amount.map { "\($0.formatted()) \(item.unit == "stk" ? "Stück" : item.unit)" } ?? ""
                if !(amount + who).isEmpty {
                    Text([amount, who].filter { !$0.isEmpty }.joined(separator: " · ")).font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                }
            }
            Spacer()
            if let price = offer?.priceCents {
                Text(euro(price)).font(.system(.subheadline, weight: .bold)).monospacedDigit()
                    .foregroundStyle(item.checked ? Theme.C.text3 : Theme.C.text1)
            }
        }
        .padding(14)
        .background(item.checked ? Color.clear : Theme.C.card, in: RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
    }
}
