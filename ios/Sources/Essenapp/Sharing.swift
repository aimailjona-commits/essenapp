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
    var packAmount: Double? = nil  // Packungsgröße (19.5), Einheit = unit
    var packs: Int? = nil  // zu kaufende Packungen (Backend rechnet)

    /// „1 × 1,1 kg · 900 g gebraucht“; ohne Packung nur die Menge.
    var amountText: String {
        guard let amount else { return "" }
        guard let packs, let packAmount else { return packSize(amount, unit) }
        return "\(packs) × \(packSize(packAmount, unit)) · \(packSize(amount, unit)) gebraucht"
    }
}

/// 1100 g → „1,1 kg“, 2 stk → „2 Stück“, el → „EL“.
func packSize(_ v: Double, _ unit: String) -> String {
    if v >= 1000, unit == "g" || unit == "ml" { return "\(num(v / 1000, 0...2)) \(unit == "g" ? "kg" : "l")" }
    return "\(num(v, 0...2)) \(Labels.unit(unit))"
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

/// Familie: Mitglieder und Einladungslink (Einstellungen S13 „Haushalt“, e.html `.e-row`).
struct FamilySection: View {
    @Environment(AppStore.self) private var store
    @State private var members: [MemberDTO] = []
    @State private var invite: URL?

    private static let tints = [Theme.C.blue, Theme.C.rose, Theme.C.sage, Theme.C.sand]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Haushalt").padding(.top, 28).padding(.bottom, 4)
            HStack(spacing: 12) {
                HStack(spacing: -8) {
                    ForEach(Array(members.prefix(4).enumerated()), id: \.offset) { i, m in
                        Text(String(m.name.prefix(1)).uppercased()).font(Theme.F.serif(15, relativeTo: .body))
                            .frame(width: 32, height: 32).background(Self.tints[i % Self.tints.count], in: Circle())
                            .overlay(Circle().stroke(Theme.C.bg, lineWidth: 2))
                    }
                }
                Text(members.map(\.name).joined(separator: ", ")).font(Theme.F.text(15, .bold)).lineLimit(1)
                Spacer()
                Text(members.count == 1 ? "1 Mitglied" : "\(members.count) Mitglieder").font(Theme.F.text(14, .semibold)).foregroundStyle(Theme.C.ink2)
            }
            .padding(.vertical, 4).frame(minHeight: 42)
            .overlay(alignment: .top) { Hairline() }
            .contextMenu {
                ForEach(members.filter { $0.role != "owner" }) { m in
                    Button("\(m.name) entfernen", systemImage: "person.badge.minus", role: .destructive) {
                        Task { await store.removeMember(m); members = await store.members() }
                    }
                }
            }
            if let invite {
                ShareLink(item: invite, subject: Text("Essenapp"),
                          message: Text("Komm in unseren Haushalt – Wochenplan & Einkaufsliste gemeinsam:")) {
                    HStack(spacing: 12) {
                        Icon(.share, size: 18).frame(width: 32, height: 32).background(Theme.C.blue1, in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Einladungslink teilen").font(Theme.F.text(15, .bold))
                            Text("öffnet die Web-Version, 7 Tage gültig – keine App nötig")
                                .font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                        }
                        Spacer()
                        Icon(.chev, size: 18).foregroundStyle(Theme.C.ink3)
                    }
                    .padding(.vertical, 4).frame(minHeight: 44)
                    .overlay(alignment: .top) { Hairline() }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .foregroundStyle(Theme.C.ink)
        .task {
            members = await store.members()
            invite = await store.inviteURL()
        }
    }
}

/// Einmalige Liste (z. B. „Grillparty“) mit Gast-Link. Ohne eigenes Mockup – aufgebaut wie die Laden-Liste S5b.
struct OneOffListView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let summary: ListSummaryDTO
    @State private var list: ListDTO?
    @State private var newItem = ""
    @State private var voiceOpen = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button { dismiss() } label: {
                    HStack(spacing: 2) {
                        Icon(.back)
                        Text("Einkauf").font(Theme.F.small).foregroundStyle(Theme.C.ink)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .padding(.leading, -6)
                Text("\(list?.items.filter { !$0.checked }.count ?? summary.openCount) offen").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                    .padding(.top, 12)
                Text(summary.name).font(Theme.F.t1)
                if let s = summary.shareUrl, let url = URL(string: s) {
                    ShareLink(item: url, message: Text("Unsere Liste „\(summary.name)“ – einfach öffnen und mit abhaken:")) {
                        HStack(spacing: 8) {
                            Icon(.share, size: 16)
                            Text("Liste teilen")
                        }
                        .font(Theme.F.text(14, .extrabold)).foregroundStyle(Theme.C.ink)
                        .padding(.horizontal, 16).frame(height: 40)
                        .overlay(Capsule().strokeBorder(Theme.C.ink, lineWidth: Theme.S.hair))
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.top, 20)
                }
                VStack(spacing: 0) {
                    AddItemField(text: $newItem, add: add) { withAnimation(Theme.spring) { voiceOpen = true } }
                    ForEach(list?.items ?? []) { item in
                        Button { toggle(item) } label: { ItemRow(item: item, offer: nil) }.buttonStyle(PressableStyle())
                    }
                }
                .padding(.top, 28)
            }
            .foregroundStyle(Theme.C.ink)
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 120)
        }
        .backdrop8 {
            Color.clear
                .pinned(left: 240, top: 44) { Ill("shopper").frame(width: 144) }
                .edgeForm(.leaf(110), Theme.C.blue, width: 166, height: 270, right: 0, top: 0)
        }
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

/// Zeile einer Liste (S5b `.irow`): Haken, Name, darunter Menge · Vorratskauf · wer; rechts genau ein Zusatz.
struct ItemRow: View {
    let item: ListItemDTO
    let offer: OfferDTO?

    var body: some View {
        HStack(spacing: 14) {
            CheckCircle(on: item.checked)
            VStack(alignment: .leading, spacing: 1) {
                Text(offer?.title ?? item.name).font(Theme.F.text(16, .bold)).strikethrough(item.checked)
                    .foregroundStyle(item.checked ? Theme.C.ink3 : Theme.C.ink)
                    .multilineTextAlignment(.leading)
                let who = item.checked && !item.checkedBy.isEmpty ? "✓ \(item.checkedBy)" : (item.source == "manual" && !item.addedBy.isEmpty ? "von \(item.addedBy)" : "")
                let sub = [item.checked ? "" : item.amountText, item.source == "stockup" ? "Vorratskauf" : "", who].filter { !$0.isEmpty }  // 31
                if !sub.isEmpty {
                    Text(sub.joined(separator: " · ")).font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                }
            }
            Spacer(minLength: 8)
            if !item.checked { extra }
        }
        .frame(minHeight: Theme.S.row)
        .overlay(alignment: .top) { Hairline() }
        .contentShape(Rectangle())
    }

    /// Nur ein Zusatz: Coupon (38c/59, antippen = Kasse) › „bald leer“ (58) › Rabatt › Preis.
    @ViewBuilder private var extra: some View {
        if let c = item.coupon {
            CouponTag(coupon: c)
        } else if item.source == "rhythm" {
            SoftPill(text: "bald leer")
        } else if let o = offer, let regular = o.regularPriceCents, regular > o.priceCents {
            DealPill(text: "−\(Int((Double(regular - o.priceCents) / Double(regular) * 100).rounded())) %")
        } else if let price = offer?.priceCents {
            Text(euro(price)).font(Theme.F.text(15, .extrabold)).monospacedDigit()
        }
    }
}
