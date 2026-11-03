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
    var source: String  // plan | manual | basics | stockup („Vorratskauf“, 31) | rhythm („bald leer“, 58)
    var deferWeek: String? = nil  // ISO-Woche der Gruppe „Nächste Woche“ (30)
    var nextWeek: Bool? = nil  // in der Gruppe „Nächste Woche“ (Backend rechnet)
    var coupon: CouponBadgeDTO? = nil  // passender aktiver Coupon (38c/59): „🎟 10fach“
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
        await syncPending()  // erst Offline-Änderungen senden, sonst überschreibt der Server-Stand sie
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

    /// `source`: manual | stockup („n× auf die Liste“, 31); `nextWeek`: gleich in die Gruppe „Nächste Woche“ (30).
    func addItem(name: String, amount: Double? = nil, unit: String = "", chain: String = "", offerId: Int? = nil,
                 source: String = "manual", nextWeek: Bool = false, to listID: Int) async {
        struct Body: Encodable {
            var name: String; var amount: Double?; var unit: String; var chain: String; var offerId: Int?; var source: String; var nextWeek: Bool
        }
        guard !demo else { return }
        let temp = api.newTempId()
        do {
            let _: ListItemDTO = try await api.request("POST", "/lists/\(listID)/items", body: Body(
                name: name, amount: amount, unit: unit, chain: chain, offerId: offerId, source: source, nextWeek: nextWeek), tempId: temp)
        } catch APIError.queued {
            // offline: sofort in Liste und Cache, der Server bekommt es beim nächsten Netz (66)
            let item = ListItemDTO(id: temp, name: name, amount: amount, unit: unit, chain: chain, offerId: offerId, checked: false,
                                   addedBy: profile?.name ?? "", checkedBy: "", source: source, nextWeek: nextWeek)
            editList(listID) { l in
                l.items.removeAll { i in i.id < 0 && !API.isTemp(i.id) && i.name == name }  // optimistischer Platzhalter
                l.items.append(item)
            }
            return
        } catch {}
        await loadLists()
    }

    /// Abhaken: sofort lokal, dann Server (gemeinsam mit allen Mitgliedern). Haltbares → Toast „In den Vorrat“ (60).
    func toggle(_ item: ListItemDTO) async {
        if let i = householdList?.items.firstIndex(where: { $0.id == item.id }) { householdList?.items[i].checked.toggle() }
        var suggest = demo && !item.checked  // Demo: immer anbieten
        if !demo, item.id > 0 || API.isTemp(item.id) {  // offline angelegte Artikel: Haken wartet mit in der Warteschlange
            struct Body: Encodable { var checked: Bool }
            struct Out: Decodable { var pantrySuggest: Bool }
            let out: Out? = try? await api.request("PATCH", "/items/\(item.id)", body: Body(checked: !item.checked))
            suggest = out?.pantrySuggest == true
        }
        if suggest {
            flash("„\(item.name)“ abgehakt", action: ("In den Vorrat", { Task { await self.toPantry(item) } }))
        }
    }

    func deleteItem(_ item: ListItemDTO) async {
        householdList?.items.removeAll { $0.id == item.id }
        guard !demo, item.id > 0 || API.isTemp(item.id) else { return }
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
    @State private var voiceOpen = false

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
                AddItemField(text: $newItem, add: add) { withAnimation(Theme.spring) { voiceOpen = true } }
                ForEach(list?.items ?? []) { item in
                    Button { toggle(item) } label: { ItemRow(item: item, offer: nil) }.buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
        }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .overlay {
            if voiceOpen {
                VoiceAddOverlay { items in
                    withAnimation(Theme.spring) { voiceOpen = false }
                    Task { await store.addSpoken(items, to: summary.id); list = try? await store.list(summary.id) }
                } close: { withAnimation(Theme.spring) { voiceOpen = false } }
            }
        }
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
            do {
                let _: ListItemDTO = try await store.api.request("PATCH", "/items/\(item.id)", body: Body(checked: !item.checked))
            } catch APIError.queued {  // offline: Haken auch im Cache, damit das Neuladen ihn nicht zurücksetzt (66)
                store.editList(summary.id) { l in
                    if let i = l.items.firstIndex(where: { x in x.id == item.id }) { l.items[i].checked = !item.checked }
                }
            } catch {}
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
                let amount = item.amount.map { "\(num($0, 0...2)) \(item.unit == "stk" ? "Stück" : item.unit)" } ?? ""
                if !(amount + who).isEmpty {
                    Text([amount, who].filter { !$0.isEmpty }.joined(separator: " · ")).font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                }
                if item.source == "stockup" { DealBadge(text: "Vorratskauf", style: .ok) }  // 31
                if item.source == "rhythm" { DealBadge(text: "bald leer", style: .soft) }  // 58
                if let c = item.coupon, !item.checked { CouponTag(coupon: c) }  // 38c/59: antippen = Kasse
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
