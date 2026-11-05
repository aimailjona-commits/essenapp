import SwiftUI

// Ziele pro Person (48): Profil des angemeldeten Mitglieds + Profile aller Mitglieder.

/// = backend ProfileOut / MemberProfileOut (`dislikes` fehlt bei /household/profiles).
struct ProfileDTO: Codable, Identifiable, Hashable {
    var memberId: Int
    var name: String
    var emoji: String
    var goal: String
    var kcal: Int
    var proteinG: Int
    var allergies: [String]
    var dislikes: [String]?
    var lunchboxDays: [Int]
    var eats: [String: [Bool]]  // {mahlzeit: [Mo..So]}

    var id: Int { memberId }

    /// Portion relativ zu 2000 kcal, auf 0,25 gerundet (= Backend planner.portion_factor).
    var portionFactor: Double { max(0.25, (Double(kcal) / 2000 * 4).rounded() / 4) }

    /// Isst am Tag bei mindestens einer der Mahlzeiten mit (fehlende Angabe = ja).
    func eatsOn(day: Int, mealTypes: [String]) -> Bool {
        mealTypes.contains { t in eats[t].map { d in d.indices.contains(day) ? d[day] : true } ?? true }
    }

    static let blank = ProfileDTO(memberId: 0, name: "", emoji: "🙂", goal: "ausgewogen", kcal: 2000, proteinG: 80,
                                  allergies: [], dislikes: [], lunchboxDays: [], eats: [:])
}

extension AppStore {
    func loadProfiles() async {
        guard !demo else { return }
        profile = try? await api.request("GET", "/me/profile")
        profiles = (try? await api.request("GET", "/household/profiles")) ?? profiles
    }

    func saveProfile(_ p: ProfileDTO) async throws {
        profile = demo ? p : try await api.request("PATCH", "/me/profile", body: p)
        if let me = profile, let i = profiles.firstIndex(where: { $0.memberId == me.memberId }) { profiles[i] = me }
    }
}

/// Kleiner Emoji-Avatar (Plan-Kopf, Rezept).
struct Avatar: View {
    let profile: ProfileDTO
    var size: CGFloat = 30

    var body: some View {
        Text(profile.emoji).font(.system(size: size * 0.55))
            .frame(width: size, height: size)
            .background(Theme.C.card, in: Circle())
            .overlay(Circle().strokeBorder(Theme.C.bg, lineWidth: 2))
            .accessibilityLabel(profile.name)
    }
}

/// S15 Mein Profil (e.html): Avatar im Kreis, Ziel als Umschalter, kcal groß mit Regler, „Isst mit“ als Matrix.
/// Avatar & Name, Protein & Allergien sowie Lunchbox-Tage öffnen je ein Sheet.
struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var p = ProfileDTO.blank
    @State private var dislikes = ""
    @State private var loaded: Bool?  // nil = lädt, false = Fehler
    @State private var saving = false
    @State private var sheet: Sheet?

    private enum Sheet: String, Identifiable { case avatar, protein, lunchbox; var id: String { rawValue } }

    static let emojis = ["🙂", "😎", "🤓", "🥳", "😺", "🐻", "🦊", "🐼", "🐸", "🦁", "🐯", "🐨", "👩‍🍳", "🧑‍🍳", "👨‍🍳", "💪",
                         "🌱", "🍕", "🥑", "🌶️", "🍓", "⚽️", "🎸", "🚀"]
    static let goals = Labels.goals + [("eigenes", "Eigenes", "Werte selbst festlegen")]
    static let suggestion = ["ausgewogen": (2000, 80), "proteinreich": (2200, 140), "kalorienarm": (1600, 90)]  // = Backend GOAL_DEFAULTS

    // Mockup-Maße (e.html S15); top relativ zum Inhalt (Mockup zählt ab Bildschirmrand inkl. Statusleiste)
    private let blob = (right: CGFloat(-120), top: CGFloat(-150), size: CGFloat(300))
    private let avatar = (right: CGFloat(28), top: CGFloat(4), size: CGFloat(72))
    private let firstColumn: CGFloat = 78
    private let toggleSize: CGFloat = 28

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EBack()
                Text("Mein Profil").font(Theme.F.t1).padding(.top, 10)
                Text("Ziele & Essenszeiten").font(Theme.F.text(14, relativeTo: .subheadline)).foregroundStyle(Theme.C.ink2)
                switch loaded {
                case nil: VStack(spacing: 12) { ForEach(0..<4, id: \.self) { _ in Skeleton8(height: 56) } }.padding(.top, 28)
                case false?:
                    VStack(alignment: .leading, spacing: 12) {
                        Text(store.error ?? "Profil konnte nicht geladen werden.").font(Theme.F.small).foregroundStyle(Theme.C.deal)
                        OutlineButton(title: "Erneut versuchen") { Task { await load() } }
                    }
                    .padding(.top, 28)
                case true?: form
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 4)
            .padding(.bottom, 16)
            // Deko scrollt mit dem Inhalt: Kreis und Avatar bleiben beim Kopf und liegen nie über der kcal-Zahl.
            .background(alignment: .topTrailing) {
                Color.clear
                    .pinned(right: avatar.right, top: avatar.top) {
                        Text(p.emoji).font(.system(size: avatar.size)).contentTransition(.opacity).accessibilityHidden(true)
                    }
                    .edgeForm(.circle, Theme.C.rose, width: blob.size, height: blob.size, right: blob.right, top: blob.top)
            }
            .overlay(alignment: .topTrailing) {  // Avatar antippen → Avatar & Name
                Button { sheet = .avatar } label: { Color.clear.frame(width: 96, height: 96).contentShape(Rectangle()) }
                    .padding(.trailing, avatar.right - 12).padding(.top, max(avatar.top - 8, 0))
                    .accessibilityLabel("Avatar und Name ändern")
                    .disabled(loaded != true)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .ctaBar(bottom: 34) {
            if loaded == true {
                PrimaryButton(title: saving ? "Speichere …" : "Speichern",
                              disabled: saving || p.name.trimmingCharacters(in: .whitespaces).isEmpty, action: save)
            }
        }
        .background(Theme.C.bg)
        .toolbar(.hidden, for: .navigationBar)
        .hidesTabBar()
        .sheet(item: $sheet) { s in sheetContent(s).sheet8().presentationDetents([.medium, .large]) }
        .task { await load() }
    }

    @ViewBuilder private var form: some View {
        // Chips statt Segment: vier Ziele passen nicht ungekürzt in eine Zeile (iPhone-Fehler 57).
        ChipFlow(items: Self.goals.map { ($0.0, $0.1) }, selected: [p.goal]) { g in
            p.goal = g
            if let s = Self.suggestion[g] { p.kcal = s.0; p.proteinG = s.1 }
        }
        .padding(.top, 28)
        .sensoryFeedback(.selection, trigger: p.goal)
        VStack(spacing: 6) {
            Hairline(color: Theme.C.ink)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("kcal pro Tag").font(Theme.F.text(12, .bold, relativeTo: .caption))
                    Text("Portion ×\(num(p.portionFactor, 0...2))").font(Theme.F.text(12, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                        .contentTransition(.numericText())
                }
                Spacer()
                BigNumber(p.kcal.formatted(.number.locale(.de)), size: 52)
            }
        }
        .padding(.top, 28)
        ERange(value: Binding(get: { Double(p.kcal) }, set: { p.kcal = Int($0) }), range: 1000...5000, step: 50, label: "kcal pro Tag")
            .padding(.top, 8)
        Button { sheet = .protein } label: {
            ERow("Protein & Allergien", sub: "\(p.proteinG) g pro Tag" + (p.allergies.isEmpty ? "" : " · \(p.allergies.joined(separator: ", "))"))
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
        SectionLabel("Isst mit").padding(.top, 28).padding(.bottom, 4)
        Grid(horizontalSpacing: 0, verticalSpacing: 8) {
            GridRow {
                Color.clear.frame(width: firstColumn, height: 1)
                ForEach(Labels.days, id: \.self) { d in
                    Text(d).font(Theme.F.text(11, .extrabold, relativeTo: .caption2)).foregroundStyle(Theme.C.ink2).frame(maxWidth: .infinity)
                }
            }
            ForEach(Labels.mealTypes, id: \.0) { m in
                GridRow {
                    Text(m.1).font(Theme.F.text(13, .bold, relativeTo: .footnote)).frame(width: firstColumn, alignment: .leading)
                    ForEach(0..<7, id: \.self) { d in
                        let on = p.eats[m.0].map { row in row.indices.contains(d) ? row[d] : true } ?? true
                        Button {
                            withAnimation(Theme.spring) { p.eats[m.0, default: Array(repeating: true, count: 7)][d].toggle() }
                        } label: {
                            Circle().fill(on ? Theme.C.ink : .clear)
                                .overlay { if !on { Circle().strokeBorder(Theme.C.ink3, lineWidth: Theme.S.hair) } }
                                .frame(width: toggleSize, height: toggleSize)
                                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .accessibilityLabel("\(m.1) \(Labels.dayNames[d])")
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: p.eats)
        Button { sheet = .lunchbox } label: {
            ERow("Lunchbox-Tage", value: p.lunchboxDays.isEmpty ? "keine" : p.lunchboxDays.sorted().map { Labels.days[$0] }.joined(separator: ", "))
        }
        .buttonStyle(.plain)
        .padding(.top, 14)
    }

    @ViewBuilder private func sheetContent(_ s: Sheet) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(s == .avatar ? "Avatar & Name" : s == .protein ? "Protein & Allergien" : "Lunchbox-Tage").font(Theme.F.t2)
                    Spacer()
                    CloseButton { sheet = nil }
                }
                switch s {
                case .avatar:
                    FieldBox { TextField("Name", text: $p.name) }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                        ForEach(Self.emojis, id: \.self) { e in
                            Button { withAnimation(Theme.spring) { p.emoji = e } } label: {
                                Text(e).font(.system(size: 24)).frame(maxWidth: .infinity, minHeight: 44)
                                    .background(p.emoji == e ? Theme.C.blue1 : .clear, in: Circle())
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("Avatar \(e)")
                            .accessibilityAddTraits(p.emoji == e ? .isSelected : [])
                        }
                    }
                    .sensoryFeedback(.selection, trigger: p.emoji)
                case .protein:
                    StatNumber(label: "Protein pro Tag", value: "\(p.proteinG) g", size: 44)
                    ERange(value: Binding(get: { Double(p.proteinG) }, set: { p.proteinG = Int($0) }), range: 0...400, step: 5, label: "Protein pro Tag")
                    if let sug = Self.suggestion[p.goal], sug != (p.kcal, p.proteinG) {
                        OutlineButton(title: "Vorschlag: \(sug.0.formatted(.number.locale(.de))) kcal · \(sug.1) g") {
                            withAnimation(Theme.spring) { p.kcal = sug.0; p.proteinG = sug.1 }
                        }
                    }
                    SectionLabel("Allergien").padding(.top, 12)
                    ChipFlow(items: (Labels.allergies + p.allergies.filter { !Labels.allergies.contains($0) }).map { ($0, $0) },
                             selected: Set(p.allergies)) { a in
                        if let i = p.allergies.firstIndex(of: a) { p.allergies.remove(at: i) } else { p.allergies.append(a) }
                    }
                    SectionLabel("Mag ich nicht").padding(.top, 12)
                    FieldBox { TextField("z. B. Koriander, Pilze", text: $dislikes) }
                case .lunchbox:
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { d in
                            let on = p.lunchboxDays.contains(d)
                            Button {
                                withAnimation(Theme.spring) { if on { p.lunchboxDays.removeAll { $0 == d } } else { p.lunchboxDays.append(d) } }
                            } label: {
                                Text(Labels.days[d]).font(Theme.F.text(13, .extrabold, relativeTo: .footnote))
                                    .foregroundStyle(on ? Theme.C.onInk : Theme.C.ink3)
                                    .frame(maxWidth: .infinity).frame(height: 38)
                                    .background(on ? Theme.C.ink : .clear, in: Circle())
                                    .overlay { if !on { Circle().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
                                    .frame(minHeight: 44).contentShape(Circle())
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("Lunchbox \(Labels.dayNames[d])")
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .sensoryFeedback(.selection, trigger: p.lunchboxDays)
                    Text("Z. B. mittags nie zu Hause – dann wird für dich nicht mitgekocht, sondern eine Lunchbox geplant.")
                        .font(Theme.F.text(13, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 24)
        }
    }

    private func load() async {
        loaded = nil
        if store.profile == nil { await store.loadProfiles() }
        guard let profile = store.profile else { loaded = false; return }
        p = profile
        dislikes = (profile.dislikes ?? []).joined(separator: ", ")
        loaded = true
    }

    private func save() {
        var out = p
        out.name = String(p.name.trimmingCharacters(in: .whitespaces).prefix(50))
        out.dislikes = dislikes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        out.lunchboxDays.sort()
        saving = true
        Task {
            defer { saving = false }
            do {
                try await store.saveProfile(out)
                store.flash("Profil gespeichert")
                dismiss()
            } catch {
                store.flash(error.localizedDescription)
            }
        }
    }
}
