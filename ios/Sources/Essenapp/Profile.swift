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

/// S15 Mein Profil.
struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var p = ProfileDTO.blank
    @State private var dislikes = ""
    @State private var loaded: Bool?  // nil = lädt, false = Fehler
    @State private var saving = false

    static let emojis = ["🙂", "😎", "🤓", "🥳", "😺", "🐻", "🦊", "🐼", "🐸", "🦁", "🐯", "🐨", "👩‍🍳", "🧑‍🍳", "👨‍🍳", "💪",
                         "🌱", "🍕", "🥑", "🌶️", "🍓", "⚽️", "🎸", "🚀"]
    static let goals = Labels.goals + [("eigenes", "Eigenes", "Werte selbst festlegen")]
    static let suggestion = ["ausgewogen": (2000, 80), "proteinreich": (2200, 140), "kalorienarm": (1600, 90)]  // = Backend GOAL_DEFAULTS

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.C.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    RoundIconButton(systemName: "chevron.left", label: "Zurück") { dismiss() }
                    DisplayHeader(line1: "Mein Profil", line2: "Ziele & Essenszeiten")
                    switch loaded {
                    case nil: ForEach(0..<3, id: \.self) { _ in SkeletonCard(height: 160) }
                    case false?: ErrorState(message: store.error ?? "Profil konnte nicht geladen werden.") { Task { await load() } }
                    case true?: form
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 200)
            }
            .scrollDismissesKeyboard(.immediately)
            if loaded == true {
                Button(action: save) { Text(saving ? "Speichere …" : "Speichern") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(saving || p.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.horizontal, Theme.pagePadding).padding(.bottom, Theme.ctaAboveTabBar)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    @ViewBuilder private var form: some View {
        section("😀", "Avatar & Name") {
            HStack(spacing: 14) {
                Text(p.emoji).font(.system(size: 40)).frame(width: 72, height: 72).background(Theme.C.accentSoft, in: Circle())
                    .contentTransition(.opacity)
                TextField("Name", text: $p.name).font(.system(.title3, weight: .bold))
                    .padding(12).background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.chip))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                ForEach(Self.emojis, id: \.self) { e in
                    Button { withAnimation(Theme.spring) { p.emoji = e } } label: {
                        Text(e).font(.system(size: 24)).frame(maxWidth: .infinity, minHeight: 44)
                            .background(p.emoji == e ? Theme.C.accentSoft : .clear, in: Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Avatar \(e)")
                    .accessibilityAddTraits(p.emoji == e ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: p.emoji)
        }
        section("🎯", "Ziel") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(Self.goals, id: \.0) { g in goalCard(g) }
            }
            .sensoryFeedback(.selection, trigger: p.goal)
        }
        section("🔥", "Tagesziel") {
            HStack(spacing: 14) {
                ring(.kcal, p.kcal, "kcal", Double(p.kcal) / 5000)
                ring(.protein, p.proteinG, "g Protein", Double(p.proteinG) / 400)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Portion ×\(((Double(p.kcal) / 2000 * 4).rounded() / 4).formatted())").font(Theme.F.callout)
                        .contentTransition(.numericText())
                    Text("gemessen an 2000 kcal").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                }
            }
            slider("kcal pro Tag", "\(p.kcal) kcal", Binding(get: { Double(p.kcal) }, set: { p.kcal = Int($0) }), 1000...5000, 50, Theme.C.kcal)
            slider("Protein pro Tag", "\(p.proteinG) g", Binding(get: { Double(p.proteinG) }, set: { p.proteinG = Int($0) }), 0...400, 5, Theme.C.protein)
            if let s = Self.suggestion[p.goal], s != (p.kcal, p.proteinG) {
                Button("Vorschlag übernehmen: \(s.0) kcal · \(s.1) g") {
                    withAnimation(Theme.spring) { p.kcal = s.0; p.proteinG = s.1 }
                }
                .font(Theme.F.callout).foregroundStyle(Theme.C.accentDeep)
            }
        }
        section("🥗", "Allergien & Mag ich nicht") {
            ChipFlow(items: (Labels.allergies + p.allergies.filter { !Labels.allergies.contains($0) }).map { ($0, $0) },
                     selected: Set(p.allergies), color: Theme.C.protein) { a in
                if let i = p.allergies.firstIndex(of: a) { p.allergies.remove(at: i) } else { p.allergies.append(a) }
            }
            TextField("Mag ich nicht, z.B. Koriander, Pilze", text: $dislikes)
                .padding(12).background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.chip))
        }
        section("🍽️", "Isst mit") {
            Grid(horizontalSpacing: 4, verticalSpacing: 8) {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    ForEach(Labels.days, id: \.self) { d in Text(d).font(Theme.F.micro).foregroundStyle(Theme.C.text2) }
                }
                ForEach(Labels.mealTypes, id: \.0) { m in
                    GridRow {
                        Text(m.1).font(Theme.F.caption).gridColumnAlignment(.leading)
                        ForEach(0..<7, id: \.self) { d in
                            let on = p.eats[m.0].map { row in row.indices.contains(d) ? row[d] : true } ?? true
                            roundToggle(on ? "✓" : "", on: on, label: "\(m.1) \(Labels.days[d])") {
                                p.eats[m.0, default: Array(repeating: true, count: 7)][d].toggle()
                            }
                        }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: p.eats)
            Text("Z. B. mittags nie zu Hause – dann wird für dich nicht mitgekocht.").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
        }
        section("🥡", "Lunchbox-Tage") {
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { d in
                    let on = p.lunchboxDays.contains(d)
                    roundToggle(Labels.days[d], on: on, label: "Lunchbox \(Labels.dayNames[d])") {
                        if on { p.lunchboxDays.removeAll { $0 == d } } else { p.lunchboxDays.append(d) }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: p.lunchboxDays)
        }
    }

    private func goalCard(_ g: (String, String, String)) -> some View {
        let on = p.goal == g.0
        return Button {
            withAnimation(Theme.spring) {
                p.goal = g.0
                if let s = Self.suggestion[g.0] { p.kcal = s.0; p.proteinG = s.1 }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(["proteinreich": "💪", "kalorienarm": "🥗", "eigenes": "✏️"][g.0] ?? "⚖️").font(.system(size: 28))
                Text(g.1).font(Theme.F.callout)
                Text(g.2).font(Theme.F.micro).foregroundStyle(Theme.C.text2)
            }
            .foregroundStyle(Theme.C.text1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(on ? Theme.C.accentSoft : Theme.C.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(on ? Theme.C.accent : Theme.C.line, lineWidth: on ? 2 : 0.5))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func ring(_ n: Nutrient, _ value: Int, _ unit: String, _ fraction: Double) -> some View {
        ZStack {
            Circle().stroke(n.color.opacity(0.15), lineWidth: 8)
            Circle().trim(from: 0, to: min(fraction, 1)).stroke(n.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(value)").font(.system(.subheadline, design: .rounded, weight: .bold)).monospacedDigit().contentTransition(.numericText())
                Text(unit).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.C.text2)
            }
        }
        .frame(width: 76, height: 76)
        .animation(Theme.spring, value: fraction)
        .accessibilityElement(children: .combine)
    }

    private func slider(_ title: String, _ value: String, _ binding: Binding<Double>, _ range: ClosedRange<Double>, _ step: Double,
                        _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                Spacer()
                Text(value).font(.system(.headline, design: .rounded, weight: .bold)).monospacedDigit().contentTransition(.numericText())
            }
            Slider(value: binding, in: range, step: step).tint(color)
        }
    }

    private func roundToggle(_ text: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button { withAnimation(Theme.spring) { action() } } label: {
            Text(text).font(.system(.caption, design: .rounded, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 38)
                .foregroundStyle(on ? .white : Theme.C.text1)
                .background(on ? Theme.C.action : Theme.C.surface, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func section(_ emoji: String, _ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label { Text(title).font(Theme.F.headline) } icon: { Text(emoji) }
            content()
        }
        .padding(16)
        .card()
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
