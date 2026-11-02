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

/// S17 Rezept-Formular: Schritt-für-Schritt-Sheet (Rezept · Zutaten · Zubereitung · Tags), anlegen oder bearbeiten.
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

    init(editing: RecipeDTO? = nil, page: Int = 0) {
        self.editing = editing
        _page = State(initialValue: page)
        _d = State(initialValue: RecipeDraft(editing))
    }

    private static let pages = ["Das Rezept", "Zutaten", "Zubereitung", "Tags"]
    private var last: Int { Self.pages.count - 1 }
    private var canContinue: Bool { page == 0 ? d.validBasics : page == 1 ? d.validLines : true }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(editing == nil ? "Neues Rezept" : "Rezept bearbeiten").font(Theme.F.title)
                Spacer()
                RoundIconButton(systemName: "xmark", label: "Schließen") { dismiss() }
            }
            HStack(spacing: 6) {
                ForEach(0..<Self.pages.count, id: \.self) { i in
                    Capsule().fill(i <= page ? Theme.C.action : Theme.C.surface).frame(height: 4)
                }
            }
            Text("Schritt \(page + 1) von \(Self.pages.count) · \(Self.pages[page])").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
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
            HStack(spacing: 10) {
                if page > 0 {
                    Button("Zurück") { withAnimation(Theme.spring) { page -= 1 } }
                        .buttonStyle(SecondaryButtonStyle()).frame(maxWidth: 140)
                }
                Button(page < last ? "Weiter" : saving ? "Speichere …" : "Speichern") {
                    if page < last { withAnimation(Theme.spring) { page += 1 } } else { save() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canContinue || saving)
                .opacity(canContinue ? 1 : 0.5)
            }
        }
        .padding(Theme.pagePadding)
        .background(Theme.C.bg)
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

    // MARK: Seiten

    private var basicsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 12) {
                    Group {
                        if let photo {
                            Image(uiImage: photo).resizable().scaledToFill().frame(width: 150, height: 150).clipShape(Circle()).floatShadow()
                        } else {
                            Plate(url: mediaURL(editing?.imageUrl ?? ""), size: 150, seed: d.title)
                        }
                    }
                    .accessibilityLabel(photo == nil ? "Rezeptfoto" : "Gewähltes Foto")
                    HStack(spacing: 10) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { camera = true } label: { Label("Kamera", systemImage: "camera.fill") }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        PhotosPicker(selection: $pick, matching: .images) { Label("Fotos", systemImage: "photo.on.rectangle") }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity)
                field("Titel") {
                    TextField("z. B. Omas Linsensuppe", text: $d.title).font(.system(.title3, weight: .bold))
                        .padding(12).background(Theme.C.card, in: RoundedRectangle(cornerRadius: Theme.R.chip))
                }
                stepper("Portionen", "\(d.servings)", $d.servings, 1...20, 1)
                stepper("Zeit", "\(d.prepMinutes) min", $d.prepMinutes, 5...600, 5)
                field("Mahlzeit") {
                    ChipFlow(items: Labels.mealTypes, selected: [d.mealType]) { m in d.mealType = m }
                }
                field("Küche") {
                    ChipFlow(items: Labels.cuisines.map { ($0, $0) }, selected: [d.cuisine]) { c in d.cuisine = d.cuisine == c ? "" : c }
                }
            }
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var ingredientsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach($d.lines) { $line in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            TextField("Zutat", text: $line.name)
                                .focused($focus, equals: line.id)
                                .padding(12).background(Theme.C.card, in: RoundedRectangle(cornerRadius: Theme.R.chip))
                            TextField("Menge", value: $line.amount, format: .number.locale(.de))
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                .frame(width: 60)
                                .padding(12).background(Theme.C.card, in: RoundedRectangle(cornerRadius: Theme.R.chip))
                            Menu {
                                ForEach(Labels.units, id: \.0) { u in Button(u.1) { $line.wrappedValue.unit = u.0 } }
                            } label: {
                                Text(Labels.unit(line.unit)).font(Theme.F.callout).foregroundStyle(Theme.C.text1)
                                    .frame(minWidth: 54, minHeight: 44).background(Theme.C.surface, in: Capsule())
                            }
                            .accessibilityLabel("Einheit: \(Labels.unit(line.unit))")
                            Button { remove(line.id) } label: {
                                Image(systemName: "minus.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.C.text3)
                                    .frame(width: 30, height: 44)
                            }
                            .accessibilityLabel("Zutat entfernen")
                            .disabled(d.lines.count == 1)
                        }
                        if focus == line.id { suggestions(line.name) { name in $line.wrappedValue.name = name } }
                    }
                }
                Button(action: addLine) { Label("Zutat hinzufügen", systemImage: "plus") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.vertical, 8)
        }
    }

    private var stepsPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zum Sortieren am Griff ziehen.").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
            List {
                ForEach($d.steps) { $step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\((d.steps.firstIndex(where: { s in s.id == step.id }) ?? 0) + 1)")
                            .font(.system(.footnote, design: .rounded, weight: .bold)).foregroundStyle(Theme.C.onAction)
                            .frame(width: 26, height: 26).background(Theme.C.action, in: Circle())
                        TextField("Schritt beschreiben …", text: $step.text, axis: .vertical).lineLimit(1...6)
                    }
                    .listRowBackground(Theme.C.card)
                }
                .onMove { d.steps.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { d.steps.remove(atOffsets: $0) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .clipShape(RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
            .environment(\.editMode, .constant(.active))
            Button { withAnimation(Theme.spring) { d.steps.append(RecipeDraft.Step()) } } label: {
                Label("Schritt hinzufügen", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var tagsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tags helfen beim Suchen, z. B. „schnell“ oder „Meal Prep“.").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
                HStack(spacing: 8) {
                    TextField("Tag hinzufügen", text: $newTag).submitLabel(.done).onSubmit(addTag)
                        .padding(12).background(Theme.C.card, in: RoundedRectangle(cornerRadius: Theme.R.chip))
                    RoundIconButton(systemName: "plus", dark: true, label: "Tag hinzufügen", action: addTag)
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if !d.tags.isEmpty {
                    ChipFlow(items: d.tags.map { ($0, "\($0)  ✕") }, selected: []) { t in d.tags.removeAll { x in x == t } }
                }
                let count = d.lines.filter { l in !l.name.trimmingCharacters(in: .whitespaces).isEmpty }.count
                Label("\(d.title) · \(count) Zutaten · \(d.steps.filter { s in !s.text.isEmpty }.count) Schritte", systemImage: "checkmark.circle.fill")
                    .font(Theme.F.callout).foregroundStyle(Theme.C.text1)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).card(radius: Theme.R.tile)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: Bausteine

    private func field(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            content()
        }
    }

    private func stepper(_ title: String, _ value: String, _ binding: Binding<Int>, _ range: ClosedRange<Int>, _ step: Int) -> some View {
        Stepper(value: binding, in: range, step: step) {
            HStack {
                Text(title).font(Theme.F.callout).foregroundStyle(Theme.C.text2)
                Spacer()
                Text(value).font(.system(.headline, design: .rounded, weight: .bold)).monospacedDigit().contentTransition(.numericText())
            }
        }
        .padding(12)
        .card(radius: Theme.R.tile)
    }

    /// Vorschläge aus bekannten Zutaten (Plan, Vorrat).
    private func suggestions(_ text: String, pick: @escaping (String) -> Void) -> some View {
        let t = text.trimmingCharacters(in: .whitespaces)
        let hits = t.isEmpty ? [] : Array(store.knownIngredients
            .filter { k in k.localizedCaseInsensitiveContains(t) && k.caseInsensitiveCompare(t) != .orderedSame }.prefix(6))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(hits, id: \.self) { k in
                    Button(k) { pick(k) }
                        .font(Theme.F.caption).foregroundStyle(Theme.C.text1)
                        .padding(.horizontal, 12).frame(minHeight: 34)
                        .background(Theme.C.accentSoft, in: Capsule())
                }
            }
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
