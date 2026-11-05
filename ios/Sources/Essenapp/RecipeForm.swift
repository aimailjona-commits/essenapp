import SwiftUI
import PhotosUI

/// Eingaben des Rezept-Formulars (S17); `body` = backend RecipeIn.
struct RecipeDraft {
    struct Line: Identifiable {
        let id = UUID()
        var name = ""
        var amount: Double?
        var unit = "g"
    }

    struct Step: Identifiable {
        let id = UUID()
        var text = ""
    }

    struct Body: Encodable {
        struct Ingredient: Encodable {
            var name: String
            var amount: Double
            var unit: String
        }
        var title: String
        var servings: Int
        var prepMinutes: Int
        var cuisine: String
        var mealType: String
        var ingredients: [Ingredient]
        var steps: [String]
        var tags: [String]
        var image: String?  // Base64-JPEG; fehlt = Foto bleibt
    }

    var title = ""
    var servings = 2
    var prepMinutes = 30
    var cuisine = ""
    var mealType = "abend"
    var lines = [Line()]
    var steps = [Step()]
    var tags: [String] = []

    init(_ r: RecipeDTO? = nil) {
        guard let r else { return }
        title = r.title
        servings = r.servings
        prepMinutes = r.prepMinutes
        cuisine = r.cuisine
        mealType = r.mealType
        lines = r.ingredients.map { i in
            Line(name: i.name, amount: i.amount, unit: Labels.units.contains { u in u.0 == i.unit } ? i.unit : "g")
        }
        if lines.isEmpty { lines = [Line()] }
        steps = r.steps.map { s in Step(text: s) }
        if steps.isEmpty { steps = [Step()] }
        tags = r.tags
    }

    var validBasics: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }
    var validLines: Bool { lines.contains { l in !l.name.trimmingCharacters(in: .whitespaces).isEmpty } }

    func body(image: String?) -> Body {
        let trim = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        return Body(title: trim(title), servings: servings, prepMinutes: prepMinutes, cuisine: cuisine, mealType: mealType,
                    ingredients: lines.filter { l in !trim(l.name).isEmpty }
                        .map { l in Body.Ingredient(name: trim(l.name), amount: l.amount ?? 0, unit: l.unit) },
                    steps: steps.map { s in trim(s.text) }.filter { t in !t.isEmpty }, tags: tags, image: image)
    }
}

/// S17 Rezept-Formular (b.html): Sheet in vier Schritten (Rezept · Zutaten · Zubereitung · Tags), anlegen oder bearbeiten.
/// Seite 3 und 4 haben kein Mockup – gebaut aus den v8-Bausteinen.
struct RecipeFormSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let editing: RecipeDTO?
    @State private var page: Int
    @State private var d: RecipeDraft
    @State private var photo: UIImage?
    @State private var jpeg: Data?
    @State private var pick: PhotosPickerItem?
    @State private var camera = false
    @State private var saving = false
    @State private var newTag = ""
    @FocusState private var focus: UUID?  // aktive Zutat → Vorschläge darunter

    // Mockup-Maße (b.html S17): Kreis im Sheet (left −110, top 150 ab Sheet-Oberkante; Griff-Bereich 33 abgezogen)
    private static let blob = (x: -110.0, y: 117.0, size: 300.0)
    private static let plate: CGFloat = 130

    init(editing: RecipeDTO? = nil, page: Int = 0) {
        self.editing = editing
        _page = State(initialValue: page)
        _d = State(initialValue: RecipeDraft(editing))
    }

    private static let pages = ["Das Rezept", "Zutaten", "Zubereitung", "Tags"]
    private var last: Int { Self.pages.count - 1 }
    private var canContinue: Bool { page == 0 ? d.validBasics : page == 1 ? d.validLines : true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(editing == nil ? "Neues Rezept" : "Rezept bearbeiten").font(Theme.F.t2).foregroundStyle(Theme.C.ink)
                Spacer()
                CloseButton { dismiss() }
            }
            StepBars(count: Self.pages.count, current: page).padding(.top, 14)
            Text("Schritt \(page + 1) von \(Self.pages.count) · \(Self.pages[page])")
                .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2).padding(.top, 8)
            Group {
                switch page {
                case 0: basicsPage
                case 1: ingredientsPage
                case 2: stepsPage
                default: tagsPage
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            .id(page)
            buttons
        }
        .padding(.horizontal, Theme.pagePadding)
        .pinned(left: Self.blob.x, top: Self.blob.y) {
            Circle().fill(Theme.C.blue1).frame(width: Self.blob.size, height: Self.blob.size)
                .opacity(page == 0 ? 1 : 0).accessibilityHidden(true)  // Kreis nur auf Seite 1 (Mockup)
        }
        .tint(Theme.C.blue3)  // Schreibmarke `.b-caret`
        .sheet8()
        .sensoryFeedback(.selection, trigger: page)
        .onChange(of: pick) { load(pick) }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { image in
                camera = false
                if let image { setPhoto(image) }
            }
            .ignoresSafeArea()
        }
        .interactiveDismissDisabled(saving)
        .onAppear {
            #if DEBUG
            UIImage.selfTest()
            #endif
        }
    }

    /// Unten fest: Seite 1 nur „Weiter“, danach „Zurück“ (1) und „Weiter“ (1,4).
    private var buttons: some View {
        GeometryReader { g in
            HStack(spacing: 10) {
                if page > 0 {
                    OutlineButton(title: "Zurück") { withAnimation(Theme.spring) { page -= 1 } }
                        .frame(width: (g.size.width - 10) / 2.4)
                }
                PrimaryButton(title: page < last ? "Weiter" : saving ? "Speichere …" : "Speichern", disabled: !canContinue || saving) {
                    if page < last { withAnimation(Theme.spring) { page += 1 } } else { save() }
                }
            }
        }
        .frame(height: Theme.S.button)
        .padding(.top, 12)
    }

    // MARK: Seiten

    private var basicsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 26) {
                    Group {
                        if let photo {
                            Image(uiImage: photo).resizable().scaledToFill().plate(Self.plate).frame(width: Self.plate, height: Self.plate)
                        } else {
                            PlatePhoto(url: mediaURL(editing?.imageUrl ?? ""), size: Self.plate)
                        }
                    }
                    .accessibilityLabel(photo == nil ? "Rezeptfoto" : "Gewähltes Foto")
                    VStack(spacing: 10) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { camera = true } label: { OutlineLabel(title: "Kamera", icon: .cam) }.buttonStyle(PressableStyle())
                        }
                        PhotosPicker(selection: $pick, matching: .images) { OutlineLabel(title: "Fotos", icon: .photo) }.buttonStyle(PressableStyle())
                    }
                }
                .padding(.leading, Theme.S.plateRing)
                FieldBox {
                    TextField("", text: $d.title, prompt: Text("z. B. Omas Linsensuppe").foregroundStyle(Theme.C.ink2))
                        .accessibilityLabel("Titel")
                }
                .padding(.top, 30)
                row("Portionen") { Stepper8(value: $d.servings, range: 1...20) }.padding(.top, 12)
                row("Zeit") {
                    Stepper8(value: Binding(get: { d.prepMinutes / 5 }, set: { v in d.prepMinutes = v * 5 }), range: 1...120) { v in "\(v * 5) min" }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Labels.mealTypes, id: \.0) { key, title in
                            Chip8(title: title, on: d.mealType == key) { withAnimation(Theme.spring) { d.mealType = key } }
                        }
                    }
                    .padding(.trailing, Theme.pagePadding)
                }
                .padding(.trailing, -Theme.pagePadding)
                .padding(.top, 26)  // 30 − Tapfläche
                Menu {
                    Button("Keine Angabe") { d.cuisine = "" }
                    ForEach(Labels.cuisines, id: \.self) { c in Button(c) { d.cuisine = c } }
                } label: {
                    HStack(spacing: 8) {
                        (Text("Küche").font(Theme.F.text(16, .extrabold))
                            + Text(" · optional").font(Theme.F.text(16, .semibold)).foregroundColor(Theme.C.ink3))
                            .foregroundStyle(Theme.C.ink)
                        Spacer()
                        Text(d.cuisine.isEmpty ? "–" : d.cuisine).font(Theme.F.text(16, .semibold)).foregroundStyle(Theme.C.ink2)
                        Icon(.chev, size: 20).foregroundStyle(Theme.C.ink2)
                    }
                    .frame(minHeight: Theme.S.row)
                    .overlay(alignment: .top) { Hairline() }
                    .overlay(alignment: .bottom) { Hairline() }
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Küche, optional: \(d.cuisine.isEmpty ? "keine" : d.cuisine)")
                .padding(.top, 10)
            }
            .padding(.top, 28)
            .padding(.bottom, 12)
            .padding(.horizontal, Theme.pagePadding)  // Rand innen, sonst schneidet die ScrollView Tellerrand und -schatten ab
        }
        .padding(.horizontal, -Theme.pagePadding)
        .scrollDismissesKeyboard(.immediately)
    }

    private var ingredientsPage: some View {
        List {
            ForEach($d.lines) { $line in
                let active = focus == line.id
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 14) {
                        TextField("", text: $line.name, prompt: Text("Zutat").foregroundStyle(Theme.C.ink3))
                            .font(Theme.F.serif(18, relativeTo: .title3)).foregroundStyle(Theme.C.ink)
                            .focused($focus, equals: line.id)
                        amountPill($line)
                    }
                    .frame(minHeight: Theme.S.row)
                    .overlay(alignment: .top) { Hairline(color: active ? Theme.C.ink : Theme.C.line) }
                    if active { suggestions(line.name) { name in $line.wrappedValue.name = name } }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Entfernen", role: .destructive) { remove(line.id) }.disabled(d.lines.count == 1)
                }
                .accessibilityAction(named: "Zutat entfernen") { if d.lines.count > 1 { remove(line.id) } }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            Button(action: addLine) {
                HStack(spacing: 14) {
                    Icon(.plus)
                    Text("Zutat hinzufügen").font(Theme.F.text(16, .extrabold)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(Theme.C.ink2)
                .frame(minHeight: Theme.S.row)
                .overlay(alignment: .top) { Hairline() }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 28)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .padding(.top, 28)
    }

    /// Menge als Pille (`.b-amt`): Zahl tippen, Einheit im Menü.
    private func amountPill(_ line: Binding<RecipeDraft.Line>) -> some View {
        HStack(spacing: 4) {
            TextField("", value: line.amount, format: .number.locale(.de), prompt: Text("Menge").foregroundStyle(Theme.C.ink3))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .fixedSize()
                .accessibilityLabel("Menge")
            Menu {
                ForEach(Labels.units, id: \.0) { u in Button(u.1) { line.wrappedValue.unit = u.0 } }
            } label: {
                HStack(spacing: 4) {
                    Text(Labels.unit(line.wrappedValue.unit))
                    Icon(.chev, size: 14).rotationEffect(.degrees(90))
                }
                .foregroundStyle(line.wrappedValue.amount == nil ? Theme.C.ink3 : Theme.C.ink)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Einheit: \(Labels.unit(line.wrappedValue.unit))")
        }
        .font(Theme.F.text(15, .extrabold))
        .foregroundStyle(Theme.C.ink)
        .padding(.horizontal, 12)
        .frame(minWidth: 104, minHeight: 36, maxHeight: 36)
        .background(Theme.C.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair))
    }

    private var stepsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Zum Sortieren am Griff ziehen, zum Löschen nach links wischen.")
                .font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
            List {
                ForEach($d.steps) { $step in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        let n = (d.steps.firstIndex(where: { s in s.id == step.id }) ?? 0) + 1
                        Text(n < 10 ? "0\(n)" : "\(n)").font(Theme.F.num(22)).tracking(Theme.F.numTracking(22)).foregroundStyle(Theme.C.ink2)
                            .frame(width: 34, alignment: .leading)
                        TextField("", text: $step.text, prompt: Text("Schritt beschreiben …").foregroundStyle(Theme.C.ink3), axis: .vertical)
                            .font(Theme.F.text(15, .semibold)).lineLimit(1...6)
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { Hairline() }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onMove { d.steps.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { d.steps.remove(atOffsets: $0) }
                Button { withAnimation(Theme.spring) { d.steps.append(RecipeDraft.Step()) } } label: {
                    HStack(spacing: 14) {
                        Icon(.plus)
                        Text("Schritt hinzufügen").font(Theme.F.text(16, .extrabold)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .foregroundStyle(Theme.C.ink2)
                    .frame(minHeight: Theme.S.row)
                    .overlay(alignment: .top) { Hairline() }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .environment(\.editMode, .constant(.active))
            .padding(.top, 12)
        }
        .padding(.top, 28)
    }

    private var tagsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Tags helfen beim Suchen, z. B. „schnell“ oder „Meal Prep“.")
                    .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                HStack(spacing: 10) {
                    FieldBox {
                        TextField("", text: $newTag, prompt: Text("Tag hinzufügen").foregroundStyle(Theme.C.ink2))
                            .submitLabel(.done).onSubmit(addTag)
                    }
                    RoundIcon(icon: .plus, filled: true, label: "Tag hinzufügen", action: addTag)
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, 14)
                if !d.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(d.tags, id: \.self) { t in
                                Chip8(title: t, on: true, icon: .x) { withAnimation(Theme.spring) { d.tags.removeAll { x in x == t } } }
                                    .accessibilityLabel("Tag \(t) entfernen")
                            }
                        }
                        .padding(.trailing, Theme.pagePadding)
                    }
                    .padding(.trailing, -Theme.pagePadding)
                    .padding(.top, 10)
                }
                let count = d.lines.filter { l in !l.name.trimmingCharacters(in: .whitespaces).isEmpty }.count
                HStack(spacing: 14) {
                    CheckCircle(on: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(d.title).font(Theme.F.rowName).foregroundStyle(Theme.C.ink).lineLimit(2)
                        Text("\(count) Zutaten · \(d.steps.filter { s in !s.text.isEmpty }.count) Schritte")
                            .font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Theme.S.row)
                .overlay(alignment: .top) { Hairline() }
                .overlay(alignment: .bottom) { Hairline() }
                .padding(.top, 28)
            }
            .padding(.top, 28)
        }
    }

    // MARK: Bausteine

    /// `.irow` mit Titel (800) links und Bedienelement rechts.
    private func row(_ title: String, @ViewBuilder _ trail: () -> some View) -> some View {
        HStack {
            Text(title).font(Theme.F.text(16, .extrabold)).foregroundStyle(Theme.C.ink)
            Spacer()
            trail()
        }
        .frame(minHeight: Theme.S.row)
        .overlay(alignment: .top) { Hairline() }
    }

    /// Vorschläge aus bekannten Zutaten (Plan, Vorrat) unter der aktiven Zeile; der erste hervorgehoben.
    @ViewBuilder private func suggestions(_ text: String, pick: @escaping (String) -> Void) -> some View {
        let t = text.trimmingCharacters(in: .whitespaces)
        let hits = t.isEmpty ? [] : Array(store.knownIngredients
            .filter { k in k.localizedCaseInsensitiveContains(t) && k.caseInsensitiveCompare(t) != .orderedSame }.prefix(6))
        if !hits.isEmpty {
            Text("Aus Plan und Vorrat").font(Theme.F.text(12, .semibold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2).padding(.top, 2)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(hits.enumerated()), id: \.offset) { i, k in
                        Button { pick(k) } label: {
                            Text(k).font(Theme.F.chip).foregroundStyle(i == 0 ? Theme.C.ink : Theme.C.ink2)
                                .padding(.horizontal, 15).frame(height: Theme.S.chip)
                                .background(i == 0 ? Theme.C.blue1 : .clear, in: Capsule())
                                .overlay { if i > 0 { Capsule().strokeBorder(Theme.C.line, lineWidth: Theme.S.hair) } }
                                .frame(minHeight: 44)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func addLine() {
        let line = RecipeDraft.Line()
        withAnimation(Theme.spring) { d.lines.append(line) }
        focus = line.id
    }

    private func remove(_ id: UUID) {
        withAnimation(Theme.spring) { d.lines.removeAll { l in l.id == id } }
    }

    private func addTag() {
        let t = String(newTag.trimmingCharacters(in: .whitespaces).prefix(50))
        guard !t.isEmpty, !d.tags.contains(t), d.tags.count < 20 else { return }
        withAnimation(Theme.spring) { d.tags.append(t) }
        newTag = ""
    }

    private func load(_ item: PhotosPickerItem?) {
        Task {
            guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
            setPhoto(image)
        }
    }

    private func setPhoto(_ image: UIImage) {
        guard let data = image.jpeg() else { store.flash("Foto ist zu groß"); return }
        withAnimation(Theme.spring) { photo = UIImage(data: data); jpeg = data }
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do {
                try await store.saveRecipe(id: editing?.id, d.body(image: jpeg?.base64EncodedString()))
                store.flash(editing == nil ? "Rezept gespeichert" : "Änderungen gespeichert")
                dismiss()
            } catch {
                store.flash("Nicht gespeichert: \(error.localizedDescription)")
            }
        }
    }
}

/// `.btn2`-Look als Label (für Button und PhotosPicker).
private struct OutlineLabel: View {
    let title: String
    let icon: Icon8

    var body: some View {
        HStack(spacing: 8) {
            Icon(icon, size: 20)
            Text(title)
        }
        .font(Theme.F.button2)
        .foregroundStyle(Theme.C.ink)
        .frame(maxWidth: .infinity, minHeight: Theme.S.button2)
        .overlay(Capsule().strokeBorder(Theme.C.ink, lineWidth: Theme.S.hair))
        .contentShape(Capsule())
    }
}

/// Kamera (UIImagePickerController) für das Rezeptfoto.
struct CameraPicker: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    @MainActor final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void

        init(done: @escaping (UIImage?) -> Void) { self.done = done }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}

extension UIImage {
    /// JPEG für den Upload (Backend: max. 2 MB): längste Seite ≤ `maxSide` px, dann Qualität und Größe senken, bis es passt.
    func jpeg(maxBytes: Int = 2_000_000, maxSide: CGFloat = 1600) -> Data? {
        var side = maxSide
        while side >= 400 {
            let k = min(1, side / max(size.width, size.height, 1))
            let target = CGSize(width: (size.width * k).rounded(), height: (size.height * k).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let scaled = UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
            for q in [0.8, 0.6, 0.4] {
                if let data = scaled.jpegData(compressionQuality: q), data.count <= maxBytes { return data }
            }
            side *= 0.7
        }
        return nil
    }

    static func selfTest() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1  // sonst 3× Pixel (Bildschirm-Skalierung)
        let big = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000), format: format).image { c in
            UIColor.orange.setFill()
            c.fill(CGRect(x: 0, y: 0, width: 3000, height: 1000))
        }
        let data = big.jpeg()
        let out = data.flatMap(UIImage.init(data:))
        assert(data.map { d in d.count <= 2_000_000 } == true, "Foto größer als 2 MB")
        assert(out.map { o in max(o.size.width, o.size.height) <= 1600 } == true, "Foto nicht verkleinert")
    }
}
