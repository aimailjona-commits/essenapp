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
                                        unit: n.unit, bestBefore: n.bestBefore, isBasic: false, source: n.source, updatedAt: "",
                                        location: n.location), at: 0)
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

enum ScanLabels {
    static let modes = [("kuehlschrank", "Kühlschrank"), ("vorrat", "Vorrat"), ("gefrierfach", "Gefrierfach")]
    static let units = [("g", "g"), ("ml", "ml"), ("stk", "Stück"), ("", "ohne")]

    static func mode(_ key: String) -> String { modes.first { m in m.0 == key }?.1 ?? key }

    /// „6 Stück · Kühlschrank · bis 8.11.“ (anderes Jahr: „bis 3/27“).
    static func sub(_ i: ScanItemDTO) -> String {
        let unit = units.first { u in u.0 == i.unit && !u.0.isEmpty }?.1
        let amount = i.amount.map { a in num(a, 0...2) + (unit.map { u in " \(u)" } ?? "") }
        let date = i.bestBefore.flatMap { s in try? Date(s, strategy: PantryDTO.day) }.map { d in
            let c = Calendar.current.dateComponents([.day, .month, .year], from: d)
            return Calendar.current.isDate(d, equalTo: .now, toGranularity: .year)
                ? "bis \(c.day ?? 0).\(c.month ?? 0)."
                : "bis \(c.month ?? 0)/\(String(format: "%02d", (c.year ?? 0) % 100))"
        }
        return [amount, mode(i.location), date].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Sicherheit rechts in der Zeile (`.soft ok` / Umriss / `.soft warn`).
private struct ConfidenceTag: View {
    let confidence: String

    var body: some View {
        switch confidence {
        case "hoch": SoftPill(text: "sicher", tint: Theme.C.sage)
        case "mittel": SoftTag(text: "ziemlich", tint: nil, color: Theme.C.ink2)
        default: SoftPill(text: "unsicher", tint: Theme.C.warn)
        }
    }
}

/// Eckrahmen des Suchers (`.d-cn`): vier Ecken, 30 lang, Radius 14.
private struct ViewfinderCorners: Shape {
    var length: CGFloat = 30
    var radius: CGFloat = 14

    func path(in r: CGRect) -> Path {
        var p = Path()
        for (corner, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1.0, 1.0), (CGPoint(x: r.maxX, y: r.minY), -1.0, 1.0),
                                 (CGPoint(x: r.minX, y: r.maxY), 1.0, -1.0), (CGPoint(x: r.maxX, y: r.maxY), -1.0, -1.0)] {
            p.move(to: CGPoint(x: corner.x, y: corner.y + dy * length))
            p.addArc(tangent1End: corner, tangent2End: CGPoint(x: corner.x + dx * length, y: corner.y), radius: radius)
            p.addLine(to: CGPoint(x: corner.x + dx * length, y: corner.y))
        }
        return p
    }
}

/// Kühlschrank-Foto als Sheet: Intro → Sucher (S23) → Upload → Prüfen (S24) → Kochideen (S25).
struct FridgeScanSheet: View {
    enum Stage { case intro, photos, upload, review, cook }
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage: Stage
    @State private var mode = "kuehlschrank"
    @State private var photos: [UIImage]
    @State private var camera = false
    @State private var picks: [PhotosPickerItem] = []
    @State private var upload = ScanProgress()
    @State private var recognizing = 0  // Schritt der Erkennung
    @State private var items: [ScanItemDTO]
    @State private var error: String?
    @State private var flying = false
    @State private var saving = false
    @State private var flash = false
    @State private var shown = Int.max  // a2-fridge: so viele Zeilen sind schon eingeblendet
    @State private var editing: Int?

    // Mockup-Lage (d.html S23/S24)
    private enum M {
        static let introBlob: CGFloat = 460, introBlobLeft: CGFloat = 60, introBlobTop: CGFloat = 100
        static let introFridge: CGFloat = 310, introFridgeLeft: CGFloat = 40, introFridgeTop: CGFloat = 130
        static let introText: CGFloat = 494  // t1 bei y 560 im Mockup (− 52 Statusleiste − 14 Kopfabstand)
        static let finder: CGFloat = 334, finderCircle: CGFloat = 300, finderFridge: CGFloat = 220, finderTop: CGFloat = 8
        static let thumb: CGFloat = 56, thumbX: CGFloat = 22, shutter: CGFloat = 76
        static let reviewBlob: CGFloat = 250, reviewBlobLeft: CGFloat = 250, reviewBlobTop: CGFloat = -70
        static let potTop: CGFloat = 76
    }

    private static let thumbTints = [Theme.C.blue1, Theme.C.sand, Theme.C.sage, Theme.C.rose, Theme.C.blue1]
    private static let steps = ["Fotos hochladen", "Lebensmittel erkennen", "Mengen & Haltbarkeit schätzen"]

    init(stage: Stage = .photos) {
        _stage = State(initialValue: stage == .photos && Demo.screen == nil ? .intro : stage)
        _photos = State(initialValue: stage == .photos && Demo.screen != nil ? Demo.fridgePhotos : [])
        _items = State(initialValue: stage == .review ? Demo.scanItems : [])
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .intro: introPage
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
                if let image { took(image) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: picks) { _, new in
            guard !new.isEmpty else { return }
            Task {
                for item in new {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data), photos.count < 5 { took(image) }
                }
                picks = []
            }
        }
    }

    private func took(_ image: UIImage) {
        withAnimation(Theme.spring) {
            photos.append(image)
            stage = .photos
        }
        guard !reduceMotion else { return }  // a2-fridge: kurzer weißer Blitz
        flash = true
        withAnimation(.easeOut(duration: 0.4)) { flash = false }
    }

    private func openCamera() {
        if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true } else {
            store.flash("Keine Kamera – wähle Fotos aus")
            withAnimation(Theme.spring) { stage = .photos }
        }
    }

    /// Kopf (`.small` + `.t2` + ✕).
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Fotos → Vorrat & Kochideen").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                Text("Kühlschrank scannen").font(Theme.F.t2).accessibilityAddTraits(.isHeader)
            }
            Spacer()
            CloseButton { dismiss() }
        }
    }

    // MARK: S23 Intro

    private var introPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                CloseButton { dismiss() }
                Spacer()
                (Text("1") + Text("/3").foregroundStyle(Theme.C.ink3)).font(Theme.F.num(30))
                    .accessibilityLabel("Schritt 1 von 3")
            }
            Spacer(minLength: 0)
            Button(action: openCamera) {
                HStack {
                    Text("Foto machen").font(Theme.F.text(17, .extrabold))
                    Spacer()
                    Icon(.cam, size: 28).foregroundStyle(Theme.C.onInk)
                        .frame(width: 72, height: 72).background(Theme.C.ink, in: Circle())
                }
                .foregroundStyle(Theme.C.ink)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .padding(.bottom, 6)
        }
        .overlay(alignment: .topLeading) {
            // Titel fest auf Mockup-Höhe (y 560), unter der Zeichnung
            VStack(alignment: .leading, spacing: 8) {
                Text("Was ist im Kühlschrank?").font(Theme.F.t1).accessibilityAddTraits(.isHeader)
                Text("Mach 1–5 Fotos. Wir füllen den Vorrat und schlagen Gerichte vor.")
                    .font(Theme.F.text(16)).foregroundStyle(Theme.C.ink2).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, M.introText)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 14)
        .backdrop8 {
            Color.clear
                .pinned(left: M.introFridgeLeft, top: M.introFridgeTop) { Ill("fridge").frame(width: M.introFridge) }
                .edgeForm(.circle, Theme.C.sage, width: M.introBlob, height: M.introBlob, left: M.introBlobLeft, top: M.introBlobTop)
        }
    }

    // MARK: S23 Sucher

    private var photosPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                Segmented8(options: ScanLabels.modes, selection: $mode).padding(.top, 16)
                ZStack {
                    Circle().fill(Theme.C.sage).frame(width: M.finderCircle, height: M.finderCircle)
                    if let last = photos.last {
                        Color.clear.overlay { Image(uiImage: last).resizable().scaledToFill() }
                            .frame(width: M.finderCircle, height: M.finderCircle)
                            .clipShape(Circle())
                            .transition(.opacity)
                    } else {
                        Ill("fridge").frame(width: M.finderFridge)
                    }
                    ViewfinderCorners().stroke(Theme.C.blue3, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: M.finder - 3, height: M.finder - 3)
                }
                .frame(width: M.finder, height: M.finder)
                .padding(.top, M.finderTop)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(photos.isEmpty ? "Sucher, noch kein Foto" : "Letztes Foto")
                Text("Fotografiere jedes Fach einzeln – bis zu 5 Fotos.")
                    .font(Theme.F.text(14)).foregroundStyle(Theme.C.ink2).multilineTextAlignment(.center)
                    .padding(.top, 13)
                HStack(spacing: 12) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { i, image in thumb(i, image) }
                    Spacer(minLength: 0)
                    (Text("\(photos.count)") + Text(" / 5").foregroundStyle(Theme.C.ink3)).font(Theme.F.num(30))
                        .contentTransition(.numericText())
                        .accessibilityLabel("\(photos.count) von 5 Fotos")
                }
                .frame(minHeight: M.thumb)
                .padding(.top, 14)
                ZStack {
                    HStack {
                        PhotosPicker(selection: $picks, maxSelectionCount: max(5 - photos.count, 1), matching: .images) {
                            HStack(spacing: 6) {
                                Icon(.photo, size: 18)
                                Text("Aus Fotos")
                            }
                            .font(Theme.F.chip)
                            .foregroundStyle(Theme.C.ink)
                            .padding(.horizontal, 14)
                            .frame(height: Theme.S.chip)
                            .background(Theme.C.plate, in: Capsule())
                        }
                        .disabled(photos.count >= 5)
                        Spacer()
                    }
                    Button(action: openCamera) {
                        Circle().fill(Theme.C.ink)
                            .overlay(Circle().strokeBorder(Theme.C.plate, lineWidth: 3).padding(4))
                            .frame(width: M.shutter, height: M.shutter)
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(photos.count >= 5).opacity(photos.count >= 5 ? 0.4 : 1)
                    .accessibilityLabel("Foto aufnehmen")
                    .sensoryFeedback(.impact(weight: .medium), trigger: photos.count)
                }
                .padding(.top, 26)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 100)
        }
        .scrollBounceBehavior(.basedOnSize)
        .overlay { Theme.C.plate.opacity(flash ? 0.9 : 0).ignoresSafeArea().allowsHitTesting(false) }
        .ctaBar(bottom: 12) {
            PrimaryButton(title: photos.isEmpty ? "Fertig" : "Fertig · \(photos.count) \(photos.count == 1 ? "Foto" : "Fotos")",
                          disabled: photos.isEmpty, action: send)
        }
    }

    /// Vorschau-Kreis 56 mit ✕ (22) oben rechts.
    private func thumb(_ i: Int, _ image: UIImage) -> some View {
        Color.clear.overlay { Image(uiImage: image).resizable().scaledToFill() }
            .frame(width: M.thumb, height: M.thumb)
            .background(Self.thumbTints[i % Self.thumbTints.count])
            .clipShape(Circle())
            .overlay(alignment: .topTrailing) {
                Button { _ = withAnimation(Theme.spring) { photos.remove(at: i) } } label: {
                    Icon(.x, size: 12).foregroundStyle(Theme.C.onInk)
                        .frame(width: M.thumbX, height: M.thumbX).background(Theme.C.ink, in: Circle())
                        .tapArea(11)
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .accessibilityLabel("Foto \(i + 1) löschen")
            }
            .transition(.scale.combined(with: .opacity))
    }

    // MARK: S23 Hochladen

    private var uploadPage: some View {
        let current = upload.sent < 1 ? 0 : 1 + recognizing
        let next = Array(Self.steps.dropFirst(current + 1))
        return VStack(spacing: 0) {
            header
            if let error {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Das hat nicht geklappt").font(Theme.F.t2)
                    Text(error).font(Theme.F.small).foregroundStyle(Theme.C.ink2).fixedSize(horizontal: false, vertical: true)
                    PrimaryButton(title: "Erneut versuchen", icon: .refresh, action: send).padding(.top, 12)
                    OutlineButton(title: "Andere Fotos") { withAnimation(Theme.spring) { stage = .photos; self.error = nil } }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 40)
            } else {
                PotLoader(ingredients: ["tomato", "garlic", "basil", "bag"]).padding(.top, M.potTop)
                Text(upload.sent < 1 ? "\(Int(upload.sent * 100)) %" : "100 %")
                    .font(Theme.F.num(64)).contentTransition(.numericText())
                    .padding(.top, 30)
                Text("\(Self.steps[min(current, 2)]) …").font(Theme.F.t2).multilineTextAlignment(.center).padding(.top, 28)
                Text(next.isEmpty ? "Danach: Vorrat prüfen" : "Danach: \(next.joined(separator: ", "))")
                    .font(Theme.F.text(14)).foregroundStyle(Theme.C.ink2).multilineTextAlignment(.center)
                    .padding(.top, 4)
                StepBars(count: 3, current: min(current, 2)).frame(width: 120).padding(.top, 22)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 14)
        .animation(Theme.spring, value: current)
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
                shown = reduceMotion ? found.count : 0
                withAnimation(Theme.spring) { stage = .review }
                await reveal()
            } catch APIError.http(422) {
                error = "Die Fotos konnten nicht gelesen werden (nur JPEG bis 5 MB)."
            } catch APIError.http(502) {
                error = "Die Erkennung ist gerade nicht erreichbar. Bitte gleich noch einmal."
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    /// a2-fridge: Zeilen nacheinander, Zähler zählt mit, danach gleitet der Knopf herein.
    private func reveal() async {
        guard !reduceMotion else { return }
        for i in items.indices {
            try? await Task.sleep(for: .seconds(0.25))
            withAnimation(Theme.spring) { shown = i + 1 }
        }
    }

    // MARK: S24 Prüfen

    private var reviewPage: some View {
        let chosen = items.filter { i in i.checked && !i.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let revealed = shown >= items.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Kühlschrank scannen").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                    Spacer()
                    CloseButton { dismiss() }
                }
                HStack(alignment: .bottom) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        BigNumber("\(min(shown, items.count))", size: 72).contentTransition(.numericText())
                        Text("erkannt").font(Theme.F.t2)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer()
                    // Ziel der Flug-Animation: die Zeilen fliegen in diese Vorrats-Pille
                    HStack(spacing: 6) {
                        Icon(.box, size: 16)
                        Text("Vorrat \(flying ? store.pantry.count : chosen.count)").contentTransition(.numericText())
                    }
                    .font(Theme.F.pill)
                    .foregroundStyle(Theme.C.onInk)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Theme.C.ink, in: Capsule())
                    .scaleEffect(flying ? 1.12 : 1)
                    .padding(.bottom, 6)
                }
                .padding(.top, 8)
                Text("Unsichere sind abgewählt – prüfen, Mengen anpassen.").font(Theme.F.text(13)).foregroundStyle(Theme.C.ink2)
                    .padding(.top, 8)
                if items.isEmpty {
                    VStack(spacing: 8) {
                        Ill("fridge").frame(width: 140, height: 140)
                        Text("Nichts erkannt").font(Theme.F.t2)
                        Text("Versuch es mit helleren Fotos, je Fach eines.").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                        PrimaryButton(title: "Neue Fotos", icon: .cam) { withAnimation(Theme.spring) { photos = []; stage = .photos } }
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 28)
                }
                VStack(spacing: 0) {
                    ForEach(items.indices, id: \.self) { i in
                        let rank = chosen.firstIndex { c in c.id == items[i].id } ?? 0
                        let fly = flying && items[i].checked
                        reviewRow(i)
                            .opacity(i < shown ? 1 : 0)
                            .offset(y: i < shown ? 0 : 14)
                            .offset(x: fly ? 140 : 0, y: fly ? -420 : 0)
                            .scaleEffect(fly ? 0.15 : 1, anchor: .topTrailing)
                            .opacity(fly ? 0 : 1)
                            .animation(.easeIn(duration: 0.45).delay(Double(rank) * 0.05), value: flying)
                    }
                    if revealed {
                        Button {
                            withAnimation(Theme.spring) {
                                items.append(ScanItemDTO(name: "", amount: nil, unit: "", location: mode, category: "sonstiges", confidence: "hoch",
                                                         bestBefore: nil))
                            }
                            editing = items.count - 1
                        } label: {
                            HStack(spacing: 14) {
                                Icon(.plus)
                                Text("Fehlt etwas?").font(Theme.F.text(16, .bold))
                                Spacer()
                            }
                            .foregroundStyle(Theme.C.ink2)
                            .frame(minHeight: Theme.S.row)
                            .overlay(alignment: .top) { Hairline() }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 110)
        }
        .backdrop8 {
            Color.clear.edgeForm(.circle, Theme.C.blue1, width: M.reviewBlob, height: M.reviewBlob, left: M.reviewBlobLeft, top: M.reviewBlobTop)
        }
        .ctaBar(bottom: 12) {
            PrimaryButton(title: saving ? "Übernehme …" : chosen.isEmpty ? "Nichts ausgewählt" : "\(chosen.count) in den Vorrat übernehmen",
                          disabled: chosen.isEmpty || saving, action: commit)
                .offset(y: revealed ? 0 : 120)
                .opacity(revealed ? 1 : 0)
                .sensoryFeedback(.success, trigger: flying)
        }
        .sheet(isPresented: Binding(get: { editing != nil }, set: { open in if !open { editing = nil } }), onDismiss: {
            withAnimation(Theme.spring) { items.removeAll { i in i.name.trimmingCharacters(in: .whitespaces).isEmpty } }
        }) {
            if let i = editing, items.indices.contains(i) { ScanEditSheet(item: $items[i]) }
        }
    }

    /// Zeile (`.d-row`): Haken, Kreis, Name (Serif 18), „Menge · Ort · MHD“, Sicherheit. Antippen = bearbeiten.
    private func reviewRow(_ i: Int) -> some View {
        let item = items[i]
        let art = PantryArt.of(name: item.name, category: item.category)
        return HStack(spacing: 12) {
            Button { withAnimation(Theme.spring) { items[i].checked.toggle() } } label: { CheckCircle(on: item.checked).tapArea(9) }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: item.checked)
                .accessibilityLabel(item.name)
                .accessibilityValue(item.checked ? "wird übernommen" : "wird nicht übernommen")
            Button { editing = i } label: {
                HStack(spacing: 12) {
                    art.circle(40, image: 34)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(item.name.isEmpty ? "Neuer Eintrag" : item.name).font(Theme.F.serif(18)).lineLimit(1)
                        Text(ScanLabels.sub(item)).font(Theme.F.text(12)).foregroundStyle(Theme.C.ink2).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 8)
                    ConfidenceTag(confidence: item.confidence)
                }
                .foregroundStyle(Theme.C.ink)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Bearbeiten")
        }
        .frame(minHeight: Theme.S.row)
        .overlay(alignment: .top) { Hairline() }
        .opacity(item.checked ? 1 : 0.55)
    }

    private func commit() {
        let chosen = items.filter { i in i.checked && !i.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let body = chosen.map { i in
            PantryIn(name: String(i.name.trimmingCharacters(in: .whitespaces).prefix(100)), amount: i.amount.map { a in min(max(a, 0), 100_000) },
                     unit: i.unit, bestBefore: i.bestBefore, isBasic: false, source: "scan", location: i.location)
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

/// Erkannte Sache bearbeiten (Sheet): Name, Menge + Einheit, Ort, Haltbarkeit.
private struct ScanEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var item: ScanItemDTO
    @State private var amountText: String
    @State private var height: CGFloat = 420

    init(item: Binding<ScanItemDTO>) {
        _item = item
        // ohne Tausenderpunkt, sonst liest „1.000“ als 1
        _amountText = State(initialValue: item.wrappedValue.amount.map { a in num(a, 0...2).replacingOccurrences(of: ".", with: "") } ?? "")
    }

    var body: some View {
        let date = Binding(get: { item.bestBefore.flatMap { s in try? Date(s, strategy: PantryDTO.day) } ?? .now.addingTimeInterval(7 * 86400) },
                           set: { d in item.bestBefore = d.formatted(PantryDTO.day) })
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(item.name.isEmpty ? "Was fehlt?" : "Bearbeiten").font(Theme.F.t2)
                    Spacer()
                    CloseButton { dismiss() }
                }
                FieldBox { TextField("Name, z. B. Joghurt", text: $item.name) }.padding(.top, 18)
                HStack(spacing: 8) {
                    FieldBox {
                        TextField("Menge", text: $amountText).keyboardType(.decimalPad)
                            .onChange(of: amountText) { _, t in item.amount = Double(t.replacingOccurrences(of: ",", with: ".")) }
                    }
                    .frame(width: 100)
                    Segmented8(options: ScanLabels.units, selection: $item.unit)
                }
                .padding(.top, 10)
                Segmented8(options: ScanLabels.modes, selection: $item.location).padding(.top, 10)
                HStack {
                    Text(item.bestBefore == nil ? "Ohne Haltbarkeit" : "Haltbar bis \(PantryDTO.dayText(date.wrappedValue))")
                        .font(Theme.F.text(16, .bold))
                    Spacer()
                    Toggle(isOn: Binding(get: { item.bestBefore != nil },
                                         set: { on in item.bestBefore = on ? date.wrappedValue.formatted(PantryDTO.day) : nil }).animation(Theme.spring)) {
                        EmptyView()
                    }
                    .toggleStyle(.v8).fixedSize()
                    .accessibilityLabel("Haltbarkeit")
                }
                .frame(minHeight: Theme.S.row)
                .overlay(alignment: .top) { Hairline() }
                .padding(.top, 18)
                if item.bestBefore != nil {
                    DatePicker("Haltbar bis", selection: date, displayedComponents: .date).datePickerStyle(.graphical).tint(Theme.C.ink)
                }
                PrimaryButton(title: "Fertig", disabled: item.name.trimmingCharacters(in: .whitespaces).isEmpty) { dismiss() }.padding(.top, 18)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 40)
            .onGeometryChange(for: CGFloat.self) { g in g.size.height } action: { h in height = h }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.immediately)
        .presentationDetents([.height(height + 33), .large])
        .sheet8()
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
    @State private var busy: Int?
    @State private var planFor: RecipeDTO?
    @State private var onList: Set<Int> = []

    // Mockup-Lage (S25): Kreis links
    private enum M { static let blob: CGFloat = 300, blobLeft: CGFloat = -130, blobTop: CGFloat = 170, plate: CGFloat = 112 }
    private static let steps = ["Vorrat ansehen", "Ideen sammeln", "Fehlende Zutaten prüfen"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aus deinem Vorrat · für \(store.household?.persons ?? 2) · bis 30 min").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                        Text("Was koche\nich jetzt?").font(Theme.F.t1).accessibilityAddTraits(.isHeader)
                    }
                    Spacer()
                    CloseButton(action: close)
                }
                Group {
                    if let ideas {
                        if ideas.isEmpty {
                            note("Keine passende Idee", "Mit dem Vorrat geht gerade nichts ohne Einkauf.")
                        }
                        ForEach(Array(ideas.enumerated()), id: \.element.id) { i, idea in row(idea, first: i == 0).appear(delay: Double(i) * 0.08) }
                    } else if empty {
                        note("Vorrat ist leer", "Fotografiere zuerst Kühlschrank oder Vorrat.")
                    } else if let error {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ideen nicht geladen").font(Theme.F.t2)
                            Text(error).font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                            OutlineButton(title: "Erneut versuchen", icon: .refresh) { Task { await load() } }.padding(.top, 8)
                        }
                    } else {
                        loading
                    }
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, Theme.pagePadding).padding(.top, 14).padding(.bottom, 40)
        }
        .backdrop8 { Color.clear.edgeForm(.circle, Theme.C.blue1, width: M.blob, height: M.blob, left: M.blobLeft, top: M.blobTop) }
        .task { if ideas == nil { await load() } }
        .sheet(item: $planFor) { r in
            PlanSlotSheet(recipeId: r.id, title: r.title).presentationDetents([.medium, .large]).presentationCornerRadius(Theme.R.sheet)
        }
    }

    private func note(_ title: String, _ text: String) -> some View {
        VStack(spacing: 8) {
            Ill("fridge").frame(width: 140, height: 140)
            Text(title).font(Theme.F.t2)
            Text(text).font(Theme.F.small).foregroundStyle(Theme.C.ink2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var loading: some View {
        VStack(spacing: 0) {
            PotLoader()
            Text("\(Self.steps[step]) …").font(Theme.F.t2).padding(.top, 28)
            StepBars(count: 3, current: step).frame(width: 120).padding(.top, 22)
        }
        .frame(maxWidth: .infinity)
        .task {
            while !Task.isCancelled && step < 2 {
                try? await Task.sleep(for: .seconds(3))
                withAnimation(Theme.spring) { step += 1 }
            }
        }
    }

    /// Idee (`.d-row`): Teller 112, Titel Serif 21, „25 min · Alles da“ bzw. „Fehlt: …“, Pillen.
    private func row(_ idea: CookIdeaDTO, first: Bool) -> some View {
        let r = idea.recipe
        let added = onList.contains(r.id)
        return HStack(alignment: .top, spacing: 22) {
            NavigationLink { SavedRecipeView(recipeId: r.id) } label: {
                RemoteImage(url: mediaURL(r.imageUrl), contentMode: .fill) { Theme.C.blue1.overlay { Ill("pasta").frame(width: M.plate * 0.7) } }
                    .plate(M.plate)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("\(r.title) ansehen")
            VStack(alignment: .leading, spacing: 0) {
                NavigationLink { SavedRecipeView(recipeId: r.id) } label: {
                    Text(r.title).font(Theme.F.serif(21)).foregroundStyle(Theme.C.ink).multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                (Text("\(r.prepMinutes) min · ")
                    + (idea.missing.isEmpty
                        ? Text("Alles da").foregroundStyle(Theme.C.success)
                        : Text("Fehlt: \(idea.missing.map { m in m.amount > 0 ? "\(m.name) (\(qty(m.amount, m.unit)))" : m.name }.joined(separator: ", "))")
                            .foregroundStyle(Theme.C.deal)))
                    .font(Theme.F.text(13)).foregroundStyle(Theme.C.ink2)
                    .padding(.top, 2)
                HStack(spacing: 6) {
                    if !idea.missing.isEmpty {
                        Button { addMissing(idea) } label: {
                            HStack(spacing: 5) {
                                if added { Icon(.check, size: 14) }
                                Text(added ? "Auf der Liste" : "Zur Liste").fixedSize()
                            }
                            .font(Theme.F.pill).foregroundStyle(Theme.C.ink)
                            .padding(.horizontal, 12).frame(height: Theme.S.pill)
                            .overlay(Capsule().strokeBorder(Theme.C.ink, lineWidth: 1.5))
                            .tapArea(7)
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(added)
                    }
                    Button { Task { await cookToday(r) } } label: {
                        Group {
                            if busy == r.id {
                                Hop3().scaleEffect(0.5).frame(width: 64, height: 30).padding(.top, 8).padding(.horizontal, 12)
                            } else {
                                Text("Heute kochen").fixedSize().padding(.horizontal, 12)
                            }
                        }
                        .font(Theme.F.pill).foregroundStyle(Theme.C.ink)
                        .frame(height: busy == r.id ? 40 : Theme.S.pill)
                        .background(Theme.C.blue, in: Capsule())
                        .tapArea(7)
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(busy != nil)
                    .accessibilityLabel(busy == r.id ? "Wird eingeplant" : "Heute kochen")
                }
                .padding(.top, 12)
                .animation(Theme.spring, value: busy)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 20)
        .overlay(alignment: .top) { if !first { Hairline() } }
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
