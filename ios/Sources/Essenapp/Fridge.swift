import PhotosUI
import SwiftUI

// Kühlschrank-Foto (69): Kamera-Sheet S23 → Prüf-Bildschirm S24 → „Was koche ich jetzt?“ S25.

/// = backend ScanItem (noch nicht gespeichert); `checked` nur lokal (Prüf-Bildschirm).
struct ScanItemDTO: Decodable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var amount: Double?
    var unit: String  // "" | g | ml | stk
    var location: String  // kuehlschrank | vorrat | gefrierfach
    var category: String
    var confidence: String  // hoch | mittel | niedrig
    var bestBefore: String?  // YYYY-MM-DD
    var checked = true

    enum CodingKeys: String, CodingKey { case name, amount, unit, location, category, confidence, bestBefore }
}

struct ScanOutDTO: Decodable {
    var items: [ScanItemDTO]
    var costCents: Double
}

/// = backend CookIdeaOut.
struct CookIdeaDTO: Decodable, Hashable, Identifiable {
    struct Missing: Decodable, Hashable {
        var name: String
        var amount: Double
        var unit: String
    }
    var recipe: RecipeDTO
    var missing: [Missing]
    var id: Int { recipe.id }
}

enum ScanLabels {
    static let modes = [("kuehlschrank", "Kühlschrank"), ("vorrat", "Vorrat"), ("gefrierfach", "Gefrierfach")]
    static let modeEmoji = ["kuehlschrank": "🧊", "vorrat": "🥫", "gefrierfach": "❄️"]
    static let units = [("g", "g"), ("ml", "ml"), ("stk", "Stück"), ("", "ohne")]
    static func confidence(_ c: String) -> (String, Color) {
        switch c {
        case "hoch": ("sicher", Theme.C.success)
        case "mittel": ("ziemlich sicher", Theme.C.text2)
        default: ("unsicher", Theme.C.warning)
        }
    }
}

extension AppStore {
    /// Fotos → erkannte Lebensmittel (speichert nichts). Unsichere sind vorab abgewählt.
    func scanPantry(_ photos: [Data], mode: String, progress: @escaping @Sendable (Double) -> Void) async throws -> [ScanItemDTO] {
        if demo { progress(1); return Demo.scanItems }
        let out: ScanOutDTO = try await api.upload("/pantry/scan", files: photos, fields: ["mode": mode], progress: progress)
        return out.items.map { item in
            var i = item
            i.checked = item.confidence != "niedrig"
            return i
        }
    }

    /// „In den Vorrat übernehmen“: alle auf einmal (gleiche Zutat+Einheit addiert das Backend).
    func addPantryBulk(_ items: [PantryIn]) async throws {
        if demo {
            for (i, n) in items.enumerated() {
                pantry.insert(PantryDTO(id: -(pantry.count + i + 1), name: n.name, ingredientKey: n.name.lowercased(), amount: n.amount,
                                        unit: n.unit, bestBefore: n.bestBefore, isBasic: false, source: "scan", updatedAt: ""), at: 0)
            }
            return
        }
        let _: [PantryDTO] = try await api.request("POST", "/pantry/bulk", body: items)
        try? await loadPantry()
    }

    /// „Was koche ich jetzt?“: bis zu 3 Gerichte aus dem Vorrat (KI, legt Rezepte an).
    func cookNow() async throws -> [CookIdeaDTO] {
        demo ? Demo.cookIdeas : try await api.request("POST", "/pantry/cook-now", timeout: 120)
    }
}

/// Upload-Fortschritt (wird aus dem URLSession-Delegate gemeldet).
@MainActor @Observable
final class ScanProgress {
    var sent = 0.0
}

/// Kühlschrank-Foto als Sheet: Fotos (S23) → Upload → Prüfen (S24) → Kochideen (S25).
struct FridgeScanSheet: View {
    enum Stage { case photos, upload, review, cook }
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var stage: Stage
    @State private var mode = "kuehlschrank"
    @State private var photos: [UIImage]
    @State private var camera = false
    @State private var picks: [PhotosPickerItem] = []
    @State private var upload = ScanProgress()
    @State private var recognizing = 0  // Schritt der Erkennung (Animation)
    @State private var items: [ScanItemDTO]
    @State private var error: String?
    @State private var flying = false
    @State private var saving = false

    init(stage: Stage = .photos) {
        _stage = State(initialValue: stage)
        _photos = State(initialValue: stage == .photos && Demo.screen != nil ? Demo.fridgePhotos : [])
        _items = State(initialValue: stage == .review ? Demo.scanItems : [])
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .photos: photosPage
                case .upload: uploadPage
                case .review: reviewPage
                case .cook: CookNowView { dismiss() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.C.bg)
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { image in
                camera = false
                if let image { withAnimation(Theme.spring) { photos.append(image) } }
            }
            .ignoresSafeArea()
        }
        .onChange(of: picks) { _, new in
            guard !new.isEmpty else { return }
            Task {
                for item in new {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data), photos.count < 5 {
                        withAnimation(Theme.spring) { photos.append(image) }
                    }
                }
                picks = []
            }
        }
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.F.title)
                Text(subtitle).font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            }
            Spacer()
            RoundIconButton(systemName: "xmark", label: "Schließen") { dismiss() }
        }
        .padding(.horizontal, Theme.pagePadding).padding(.top, 20)
    }

    // MARK: S23 Kamera-Sheet

    private var photosPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PillSegment(options: ScanLabels.modes, selection: $mode)
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.R.card, style: .continuous).fill(Theme.C.surface)
                    if let last = photos.last {
                        Color.clear.overlay { Image(uiImage: last).resizable().scaledToFill() }
                            .clipShape(RoundedRectangle(cornerRadius: Theme.R.card, style: .continuous))
                            .transition(.opacity)
                    } else {
                        VStack(spacing: 8) {
                            Text(ScanLabels.modeEmoji[mode] ?? "📸").font(.system(size: 56))
                            Text("Fotografiere jedes Fach einzeln – bis zu 5 Fotos.")
                                .font(Theme.F.caption).foregroundStyle(Theme.C.text2).multilineTextAlignment(.center)
                        }
                        .padding(24)
                    }
                    CornerFrame().stroke(Theme.C.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round)).padding(18)
                }
                .frame(height: 340)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(photos.isEmpty ? "Noch kein Foto" : "Letztes Foto")

                HStack(spacing: 10) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { i, image in
                        Color.clear.overlay { Image(uiImage: image).resizable().scaledToFill() }
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button { _ = withAnimation(Theme.spring) { photos.remove(at: i) } } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 20)).symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Theme.C.action)
                                        .frame(width: 44, height: 44)
                                }
                                .offset(x: 16, y: -16)
                                .accessibilityLabel("Foto \(i + 1) löschen")
                            }
                            .transition(.scale.combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                    Text("\(photos.count) / 5").font(Theme.F.micro).foregroundStyle(Theme.C.text2).monospacedDigit()
                        .contentTransition(.numericText())
                }
                .frame(minHeight: 56)

                HStack(spacing: 14) {
                    PhotosPicker(selection: $picks, maxSelectionCount: max(5 - photos.count, 1), matching: .images) {
                        Label("Aus Fotos", systemImage: "photo.on.rectangle").font(Theme.F.callout)
                            .padding(.horizontal, 16).frame(minHeight: 48)
                            .background(Theme.C.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: 0.5))
                    }
                    .disabled(photos.count >= 5)
                    Spacer()
                    Button {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true } else { store.flash("Keine Kamera – wähle Fotos aus") }
                    } label: {
                        Circle().fill(Theme.C.action).frame(width: 76, height: 76)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 4).padding(5))
                            .overlay(Image(systemName: "camera.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white))
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(photos.count >= 5).opacity(photos.count >= 5 ? 0.4 : 1)
                    .accessibilityLabel("Foto aufnehmen")
                    .sensoryFeedback(.impact(weight: .medium), trigger: photos.count)
                    Spacer()
                    Color.clear.frame(width: 100, height: 1)
                }
            }
            .padding(.horizontal, Theme.pagePadding).padding(.vertical, 12)
        }
        .safeAreaInset(edge: .top) { header("Kühlschrank scannen", "Fotos → Vorrat & Kochideen") }
        .ctaBar(bottom: 12) {
            Button(action: send) { Text(photos.isEmpty ? "Fertig" : "Fertig · \(photos.count) \(photos.count == 1 ? "Foto" : "Fotos")") }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(photos.isEmpty).opacity(photos.isEmpty ? 0.5 : 1)
        }
    }

    // MARK: Upload & Erkennung

    private var uploadPage: some View {
        let steps = ["Fotos hochladen", "Lebensmittel erkennen", "Mengen & Haltbarkeit schätzen"]
        let done = upload.sent < 1 ? 0 : 1 + recognizing
        return VStack(spacing: 20) {
            header(error == nil ? "Wird erkannt …" : "Kühlschrank scannen", ScanLabels.modes.first { m in m.0 == mode }?.1 ?? "")
            if let error {
                ErrorState(message: error) { send() }
                Button("Andere Fotos") { withAnimation(Theme.spring) { stage = .photos; self.error = nil } }
                    .buttonStyle(SecondaryButtonStyle()).padding(.horizontal, Theme.pagePadding)
            } else {
                ZStack {
                    GoalRing(fraction: upload.sent, color: Theme.C.accent, lineWidth: 10)
                    Text(upload.sent < 1 ? "\(Int(upload.sent * 100)) %" : (ScanLabels.modeEmoji[mode] ?? "📸"))
                        .font(.system(.title, design: .rounded, weight: .bold)).monospacedDigit().contentTransition(.numericText())
                }
                .frame(width: 150, height: 150)
                .padding(.top, 24)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(i < done ? Theme.C.accent : Theme.C.surface)
                                if i < done { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
                                else if i == done { ProgressView().controlSize(.small) }
                            }
                            .frame(width: 28, height: 28)
                            Text(s).font(Theme.F.callout).foregroundStyle(i <= done ? Theme.C.text1 : Theme.C.text3)
                            Spacer()
                        }
                    }
                }
                .padding(18).card()
                .padding(.horizontal, Theme.pagePadding)
                .animation(Theme.spring, value: done)
            }
        }
    }

    private func send() {
        let datas = photos.compactMap { p in p.jpeg(maxBytes: 4_000_000, maxSide: 1024) }  // Backend: ≤ 5 MB je Foto
        guard !datas.isEmpty else { return }
        error = nil
        upload.sent = 0
        recognizing = 0
        withAnimation(Theme.spring) { stage = .upload }
        let box = upload
        Task {
            let ticker = Task {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(3))
                    if box.sent >= 1 { withAnimation(Theme.spring) { recognizing = min(recognizing + 1, 1) } }
                }
            }
            defer { ticker.cancel() }
            do {
                let found = try await store.scanPantry(datas, mode: mode) { p in Task { @MainActor in box.sent = p } }
                box.sent = 1
                items = found
                withAnimation(Theme.spring) { stage = .review }
            } catch APIError.http(422) {
                error = "Die Fotos konnten nicht gelesen werden (nur JPEG bis 5 MB)."
            } catch APIError.http(502) {
                error = "Die Erkennung ist gerade nicht erreichbar. Bitte gleich noch einmal."
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: S24 Prüf-Bildschirm

    private var reviewPage: some View {
        let chosen = items.filter { i in i.checked && !i.name.trimmingCharacters(in: .whitespaces).isEmpty }
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if items.isEmpty {
                    EmptyState(emoji: "🔍", title: "Nichts erkannt", text: "Versuch es mit helleren Fotos, je Fach eines.",
                               buttonTitle: "Neue Fotos") { withAnimation(Theme.spring) { photos = []; stage = .photos } }
                }
                ForEach(items.indices, id: \.self) { i in
                    let rank = chosen.firstIndex { c in c.id == items[i].id } ?? 0
                    ScanReviewRow(item: $items[i])
                        .offset(x: flying && items[i].checked ? 140 : 0, y: flying && items[i].checked ? -520 : 0)
                        .scaleEffect(flying && items[i].checked ? 0.15 : 1, anchor: .topTrailing)
                        .opacity(flying && items[i].checked ? 0 : 1)
                        .animation(.easeIn(duration: 0.45).delay(Double(rank) * 0.05), value: flying)
                        .appear(delay: Double(i) * 0.03)
                }
                Button {
                    withAnimation(Theme.spring) {
                        items.append(ScanItemDTO(name: "", amount: nil, unit: "", location: mode, category: "sonstiges", confidence: "hoch",
                                                 bestBefore: nil))
                    }
                } label: {
                    Label("Fehlt etwas?", systemImage: "plus").font(Theme.F.callout).frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.C.surface, in: RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, Theme.pagePadding).padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .top) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(items.count) erkannt").font(Theme.F.title)
                    Text("Unsichere sind abgewählt – prüfen, Mengen anpassen.").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                }
                Spacer()
                // Ziel der Animation: die Karten fliegen in diese Vorrats-Pille
                Label("Vorrat \(flying ? store.pantry.count : chosen.count)", systemImage: "basket.fill")
                    .font(Theme.F.callout).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Theme.C.action, in: Capsule())
                    .symbolEffect(.bounce, value: flying)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, Theme.pagePadding).padding(.top, 20).padding(.bottom, 8)
            .background(Theme.C.bg)
        }
        .ctaBar(bottom: 12) {
            Button(action: commit) {
                Text(saving ? "Übernehme …" : chosen.isEmpty ? "Nichts ausgewählt" : "\(chosen.count) in den Vorrat übernehmen")
                    .contentTransition(.numericText())
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(chosen.isEmpty || saving).opacity(chosen.isEmpty ? 0.5 : 1)
            .sensoryFeedback(.success, trigger: flying)
        }
    }

    private func commit() {
        let chosen = items.filter { i in i.checked && !i.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let body = chosen.map { i in
            PantryIn(name: String(i.name.trimmingCharacters(in: .whitespaces).prefix(100)), amount: i.amount.map { a in min(max(a, 0), 100_000) },
                     unit: i.unit, bestBefore: i.bestBefore, isBasic: false, source: "scan")
        }
        saving = true
        Task {
            defer { saving = false }
            do {
                try await store.addPantryBulk(body)
                flying = true
                try? await Task.sleep(for: .seconds(0.6 + Double(chosen.count) * 0.05))
                store.flash(chosen.count == 1 ? "1 Sache im Vorrat" : "\(chosen.count) Sachen im Vorrat")
                withAnimation(Theme.spring) { stage = .cook }
            } catch {
                store.flash("Nicht übernommen: \(error.localizedDescription)")
            }
        }
    }
}

/// Zeile im Prüf-Bildschirm: Häkchen, Name, Sicherheit, Menge/Einheit, Ort, Haltbarkeit – alles änderbar.
struct ScanReviewRow: View {
    @Binding var item: ScanItemDTO
    @State private var amountText: String

    init(item: Binding<ScanItemDTO>) {
        _item = item
        // ohne Tausenderpunkt, sonst liest „1.000“ als 1
        _amountText = State(initialValue: item.wrappedValue.amount.map { a in num(a, 0...2).replacingOccurrences(of: ".", with: "") } ?? "")
    }

    var body: some View {
        let conf = ScanLabels.confidence(item.confidence)
        HStack(alignment: .top, spacing: 12) {
            Button { withAnimation(Theme.spring) { item.checked.toggle() } } label: {
                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26)).foregroundStyle(item.checked ? Theme.C.accent : Theme.C.text3)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(PressableStyle())
            .sensoryFeedback(.selection, trigger: item.checked)
            .accessibilityLabel(item.checked ? "\(item.name) übernehmen" : "\(item.name) nicht übernehmen")
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(Theme.hue(category: item.category).emoji).font(.system(size: 20))
                    TextField("Name", text: $item.name).font(.system(.body, weight: .semibold))
                    Text(conf.0).font(Theme.F.micro).foregroundStyle(conf.1)
                        .padding(.horizontal, 8).frame(height: 22).background(conf.1.opacity(0.14), in: Capsule())
                        .accessibilityLabel("Erkennung \(conf.0)")
                }
                FlowLayout(spacing: 6) {
                    TextField("Menge", text: $amountText).keyboardType(.decimalPad)
                        .font(Theme.F.callout).monospacedDigit().multilineTextAlignment(.center)
                        .frame(width: 64, height: 36).background(Theme.C.surface, in: Capsule())
                        .onChange(of: amountText) { _, t in item.amount = Double(t.replacingOccurrences(of: ",", with: ".")) }
                    Menu {
                        ForEach(ScanLabels.units, id: \.0) { u in Button(u.1) { item.unit = u.0 } }
                    } label: { chip(ScanLabels.units.first { u in u.0 == item.unit }?.1 ?? item.unit, "chevron.down") }
                    Menu {
                        ForEach(ScanLabels.modes, id: \.0) { m in Button("\(ScanLabels.modeEmoji[m.0] ?? "") \(m.1)") { item.location = m.0 } }
                    } label: {
                        chip("\(ScanLabels.modeEmoji[item.location] ?? "") \(ScanLabels.modes.first { m in m.0 == item.location }?.1 ?? item.location)",
                             "chevron.down")
                    }
                    if let bb = item.bestBefore {
                        HStack(spacing: 2) {
                            DatePicker("Haltbar bis", selection: Binding(get: { (try? Date(bb, strategy: PantryDTO.day)) ?? .now },
                                                                       set: { d in item.bestBefore = d.formatted(PantryDTO.day) }),
                                       displayedComponents: .date)
                                .labelsHidden().datePickerStyle(.compact)
                            Button { item.bestBefore = nil } label: {
                                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.C.text2)
                                    .frame(width: 30, height: 36)
                            }
                            .accessibilityLabel("Haltbarkeit entfernen")
                        }
                    } else {
                        Button { item.bestBefore = Date.now.addingTimeInterval(7 * 86400).formatted(PantryDTO.day) } label: {
                            chip("MHD", "plus")
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(item.confidence == "niedrig" ? Theme.C.warning.opacity(0.14) : Theme.C.card,
                    in: RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
        .opacity(item.checked ? 1 : 0.65)
    }

    private func chip(_ text: String, _ symbol: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
        }
        .font(Theme.F.callout).foregroundStyle(Theme.C.text1)
        .padding(.horizontal, 12).frame(height: 36)
        .background(Theme.C.surface, in: Capsule())
    }
}

// MARK: S25 „Was koche ich jetzt?“

struct CookNowView: View {
    @Environment(AppStore.self) private var store
    let close: () -> Void
    @State private var ideas: [CookIdeaDTO]?
    @State private var error: String?
    @State private var empty = false
    @State private var step = 0
    @State private var spin = false
    @State private var busy: Int?
    @State private var planFor: RecipeDTO?
    @State private var onList: Set<Int> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Was koche ich jetzt?").font(Theme.F.title)
                        Text("Aus deinem Vorrat · höchstens 30 min").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                    }
                    Spacer()
                    RoundIconButton(systemName: "xmark", label: "Schließen", action: close)
                }
                if let ideas {
                    if ideas.isEmpty {
                        EmptyState(emoji: "🤔", title: "Keine passende Idee", text: "Mit dem Vorrat geht gerade nichts ohne Einkauf.")
                    }
                    ForEach(Array(ideas.enumerated()), id: \.element.id) { i, idea in card(idea).appear(delay: Double(i) * 0.08) }
                } else if empty {
                    EmptyState(emoji: "🧺", title: "Vorrat ist leer", text: "Fotografiere zuerst Kühlschrank oder Vorrat.")
                } else if let error {
                    ErrorState(message: error) { Task { await load() } }
                } else {
                    loading
                }
            }
            .padding(.horizontal, Theme.pagePadding).padding(.top, 20).padding(.bottom, 40)
        }
        .task { if ideas == nil { await load() } }
        .sheet(item: $planFor) { r in
            PlanSlotSheet(recipeId: r.id, title: r.title).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet)
        }
    }

    private var loading: some View {
        let steps = ["Vorrat ansehen", "Ideen sammeln", "Fehlende Zutaten prüfen"]
        return VStack(spacing: 18) {
            Plate(url: nil, size: 140, seed: "vorrat")
                .rotationEffect(.degrees(spin ? 360 : 0))
                .onAppear { withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { spin = true } }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    Label(s, systemImage: i < step ? "checkmark.circle.fill" : "circle.dotted")
                        .font(Theme.F.callout).foregroundStyle(i <= step ? Theme.C.text1 : Theme.C.text3)
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
        }
        .padding(.top, 12)
        .task {
            while !Task.isCancelled && step < 2 {
                try? await Task.sleep(for: .seconds(3))
                withAnimation(Theme.spring) { step += 1 }
            }
        }
    }

    private func card(_ idea: CookIdeaDTO) -> some View {
        let r = idea.recipe
        return VStack(alignment: .leading, spacing: 12) {
            NavigationLink { SavedRecipeView(recipeId: r.id) } label: {
                HStack(spacing: 14) {
                    Plate(url: mediaURL(r.imageUrl), size: 76, seed: r.title)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.title).font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(Theme.C.text1)
                            .multilineTextAlignment(.leading)
                        Text("\(r.prepMinutes) min · \(r.servings) Portionen").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
                        if idea.missing.isEmpty {
                            DealBadge(text: "Alles da ✓", style: .ok)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.C.text3)
                }
            }
            .buttonStyle(PressableStyle())
            if !idea.missing.isEmpty {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fehlt").font(Theme.F.micro).foregroundStyle(Theme.C.deal)
                        Text(idea.missing.map { m in m.amount > 0 ? "\(m.name) (\(qty(m.amount, m.unit)))" : m.name }.joined(separator: ", "))
                            .font(Theme.F.caption)
                    }
                    Spacer()
                    let added = onList.contains(r.id)
                    Button { addMissing(idea) } label: {
                        Label(added ? "Auf der Liste" : "Zur Liste", systemImage: added ? "checkmark" : "cart.badge.plus")
                            .font(Theme.F.callout).padding(.horizontal, 12).frame(minHeight: 40)
                            .background(Theme.C.surface, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(added)
                }
                .padding(10)
                .background(Theme.C.deal.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.R.chip, style: .continuous))
            }
            Button { Task { await cookToday(r) } } label: {
                if busy == r.id { ProgressView().tint(.white) } else { Label("Heute kochen", systemImage: "flame.fill") }
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.C.accent))
            .disabled(busy != nil)
        }
        .padding(14)
        .card()
    }

    private func load() async {
        error = nil
        do {
            let found = try await store.cookNow()
            withAnimation(Theme.spring) { ideas = found }
        } catch APIError.http(422) {
            empty = true
        } catch APIError.http(502) {
            error = "Die Ideen-Suche ist gerade nicht erreichbar."
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func addMissing(_ idea: CookIdeaDTO) {
        guard let list = store.householdList else { store.flash("Keine Einkaufsliste gefunden"); return }
        onList.insert(idea.recipe.id)
        Task {
            for m in idea.missing { await store.addItem(name: m.name, to: list.id) }
            store.flash(idea.missing.count == 1 ? "1 Zutat auf der Liste" : "\(idea.missing.count) Zutaten auf der Liste")
        }
    }

    /// Setzt das Gericht in den heutigen Slot (gleiche Mahlzeit bevorzugt); ohne Slot heute → Slot wählen (S19).
    private func cookToday(_ r: RecipeDTO) async {
        let today = store.plan?.entries.filter { e in e.day == store.todayMeal?.day } ?? []
        guard let slot = today.first(where: { e in e.mealType == r.mealType && !e.locked }) ?? today.first(where: { e in !e.locked }) ?? today.first
        else { planFor = r; return }
        busy = r.id
        defer { busy = nil }
        if await store.replace(slot, with: r.id) {
            store.flash("Heute: \(r.title)")
            close()
        }
    }
}
