import SwiftUI

/// Demo-Zustände für die CI-Screenshots (die App rendert die Erweiterung als Vorschau, S20).
public enum ShareDemo: Sendable {
    case link, pair, importing, result
}

private let days = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
private let meals = ["fruehstueck": "Frühstück", "mittag": "Mittag", "abend": "Abend", "dessert": "Dessert"]

@MainActor @Observable
final class ShareModel {
    enum Stage: Equatable { case link, pair, importing, result, plan, noRecipe, failed(String) }

    var stage: Stage = .link
    var link: String
    var text: String
    var server: String
    var code = ""
    var pairError: String?
    var linkError: String?
    var busy = false
    var step = 0
    var recipe: ImportedRecipe?
    var existed = false
    var entries: [SharePlan.Entry]?
    var planError: String?
    var planned: String?
    var session: ShareSession?
    let persist: Bool
    let demo: Bool

    init(input: ShareInput?, session: ShareSession?, persist: Bool, demo: ShareDemo?) {
        link = input?.url ?? ""
        text = input?.text ?? ""
        self.session = session
        server = session?.server.isEmpty == false ? session!.server : "http://"
        self.persist = persist
        self.demo = demo != nil
        switch demo {
        case .link: stage = .link
        case .pair: stage = .pair; server = "http://192.168.0.224:8000"; code = "482913"; busy = true  // S20: wartet auf Kopplung
        case .importing: stage = .importing; step = 1; link = "https://www.instagram.com/reel/C9xYz12AbCd/"
        case .result: stage = .result; recipe = Self.demoRecipe; link = "https://www.instagram.com/reel/C9xYz12AbCd/"
        case nil:
            if !link.isEmpty { start() } else if input != nil { linkError = "Im geteilten Inhalt war kein Link." }
        }
    }

    static let demoRecipe = ImportedRecipe(
        id: 102, title: "Bunte Linsen-Bowl", imageUrl: "",
        ingredients: [.init(name: "Linsen", estimated: nil), .init(name: "Süßkartoffel", estimated: nil), .init(name: "Feta", estimated: nil),
                      .init(name: "Spinat", estimated: nil), .init(name: "Kräuter", estimated: true), .init(name: "Öl", estimated: true),
                      .init(name: "Salz", estimated: true), .init(name: "Zitrone", estimated: nil)],
        steps: ["a", "b", "c", "d", "e"], source: "instagram", sourceAuthor: "@gruenegabel")

    var hasToken: Bool { !(session?.token ?? "").isEmpty }
    var validLink: Bool { URL(string: link).map { u in (u.scheme == "http" || u.scheme == "https") && u.host() != nil } ?? false }

    /// Ohne Kopplung erst den Code, sonst direkt importieren.
    func start() {
        guard validLink else { linkError = "Das ist kein gültiger Link."; stage = .link; return }
        linkError = nil
        if hasToken { Task { await runImport() } } else { withAnimation(ST.spring) { stage = .pair } }
    }

    func pair() async {
        guard !demo, code.count == 6, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let body = ShareAPI.json(["code": code, "label": "Teilen-Erweiterung"])
            let (out, _): (PairResult, Int) = try await ShareAPI.call("POST", server, "/pair", token: nil, body: body)
            let s = ShareSession(server: server, token: out.token)
            session = s
            if persist { ShareKeychain.save(s) }
            pairError = nil
            start()
        } catch let e as ShareError {
            code = ""
            pairError = switch e.status {
            case 404: "Code ungültig – bitte in der App einen neuen Code erzeugen."
            case 410: "\(e.detail) – bitte in der App einen neuen Code erzeugen."
            case 429: "Zu viele Fehlversuche – bitte in 10 Minuten erneut versuchen."
            default: e.detail
            }
        } catch {
            pairError = error.localizedDescription
        }
    }

    func runImport() async {
        guard let session else { return }
        withAnimation(ST.spring) { stage = .importing; step = 0 }
        let ticker = Task {  // Schritte wandern weiter, solange das Backend liest (ein Aufruf, < 15 s)
            for next in 1...3 {
                try await Task.sleep(for: .seconds(2.5))
                withAnimation(ST.spring) { step = next }
            }
        }
        defer { ticker.cancel() }
        do {
            let body = ShareAPI.json(["url": link, "text": text])
            let (r, status): (ImportedRecipe, Int) = try await ShareAPI.call("POST", session.server, "/import", token: session.token,
                                                                              body: body, timeout: 60)
            withAnimation(ST.spring) { step = 4 }
            try? await Task.sleep(for: .milliseconds(400))
            recipe = r
            existed = status == 200
            withAnimation(ST.spring) { stage = .result }
        } catch let e as ShareError where e.status == 401 {
            var s = session
            s.token = ""
            self.session = s
            if persist { ShareKeychain.save(s) }
            pairError = "Die Kopplung wurde widerrufen – bitte neu koppeln."
            withAnimation(ST.spring) { stage = .pair }
        } catch let e as ShareError where e.status == 422 {
            withAnimation(ST.spring) { stage = .noRecipe }
        } catch {
            withAnimation(ST.spring) { stage = .failed(error.localizedDescription) }
        }
    }

    func loadPlan() async {
        withAnimation(ST.spring) { stage = .plan }
        guard let session, !demo else { return }
        entries = nil
        planError = nil
        do {
            let (plan, _): (SharePlan, Int) = try await ShareAPI.call("GET", session.server, "/plans/current", token: session.token)
            entries = plan.entries.sorted { a, b in (a.day, order(a.mealType)) < (b.day, order(b.mealType)) }
        } catch let e as ShareError where e.status == 404 {
            entries = []
        } catch {
            planError = error.localizedDescription
        }
    }

    func replace(_ entry: SharePlan.Entry) async {
        guard let session, let id = entry.id, let recipe, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let body = ShareAPI.json(["recipe_id": recipe.id])
            let _: (SharePlan, Int) = try await ShareAPI.call("POST", session.server, "/plans/current/entries/\(id)/replace",
                                                              token: session.token, body: body, timeout: 60)
            planned = "\(days[entry.day]) · \(meals[entry.mealType] ?? entry.mealType)"
            withAnimation(ST.spring) { stage = .result }
        } catch {
            planError = error.localizedDescription
        }
    }

    private func order(_ type: String) -> Int { ["fruehstueck", "mittag", "abend", "dessert"].firstIndex(of: type) ?? 9 }
}


/// S20 Teilen-Erweiterung (Koppeln) und S22 „Link einfügen“ in der App: Link → ggf. Kopplung → Import → Ergebnis.
public struct ShareFlowView: View {
    @State private var model: ShareModel
    private let onOpen: ((Int) -> Void)?
    private let onClose: () -> Void
    @FocusState private var codeFocus: Bool

    // Mockup-Maße (b.html S20/S22)
    private let resultBlob = (x: CGFloat(190), y: CGFloat(-30), size: CGFloat(300))
    private let plateSize: CGFloat = 150
    private let digitWidth: CGFloat = 46
    private let digitHeight: CGFloat = 62
    private let stepRow: CGFloat = 52

    /// `persist`: Kopplung im Schlüsselbund der Erweiterung speichern. `onOpen` (nur App): „Rezept ansehen“.
    public init(input: ShareInput?, session: ShareSession?, persist: Bool = false, demo: ShareDemo? = nil,
                onOpen: ((Int) -> Void)? = nil, onClose: @escaping () -> Void) {
        _model = State(initialValue: ShareModel(input: input, session: session, persist: persist, demo: demo))
        self.onOpen = onOpen
        self.onClose = onClose
    }

    private var floatingClose: Bool {
        switch model.stage {
        case .link, .pair: false
        default: true
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.horizontal, ST.page).padding(.top, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            buttons.padding(.horizontal, ST.page).padding(.top, 8).padding(.bottom, 34)
        }
        .background(alignment: .topLeading) {
            if model.stage == .result {
                Circle().fill(ST.blue1).frame(width: resultBlob.size, height: resultBlob.size)
                    .offset(x: resultBlob.x, y: resultBlob.y).accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) {
            if floatingClose { closeButton.padding(.trailing, ST.page - 2).padding(.top, 12) }
        }
        .background(ST.bg.ignoresSafeArea())
        .foregroundStyle(ST.ink)
        .tint(ST.ink)
        .environment(\.locale, Locale(identifier: "de_DE"))
        .environment(\.colorScheme, .light)  // v8 ist vorerst fest hell
        .onAppear {
            #if DEBUG
            ShareInput.selfTest()
            #endif
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(ST.ink)
                .frame(width: ST.close, height: ST.close)
                .overlay(Circle().strokeBorder(ST.line, lineWidth: ST.hair))
                .frame(minWidth: 44, minHeight: 44).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Schließen")
    }

    // MARK: Inhalt je Schritt

    @ViewBuilder private var content: some View {
        switch model.stage {
        case .link: linkPage
        case .pair: pairPage
        case .importing: importingPage
        case .result: resultPage
        case .plan: planPage
        case .noRecipe:
            message("questionmark", "Kein Rezept gefunden",
                    "In der Beschreibung steht kein Rezept – manche Reels zeigen es nur im Video. Probier einen anderen Beitrag oder eine Rezept-Webseite.")
        case .failed(let text): message("wifi.slash", "Das hat nicht geklappt", text)
        }
    }

    /// S22 Link einfügen.
    private var linkPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Rezept aus Link").font(ST.t2)
                Spacer()
                closeButton
            }
            Text("Link aus Instagram oder einer Rezeptseite einfügen – wir lesen Zutaten und Schritte aus.")
                .font(ST.text(15)).lineSpacing(4).foregroundStyle(ST.ink2).padding(.top, 8)
            HStack(spacing: 10) {
                Image(systemName: "link").font(.system(size: 17, weight: .medium)).foregroundStyle(ST.ink2)
                TextField("instagram.com/reel/…", text: $model.link)
                    .font(ST.text(15)).foregroundStyle(ST.ink)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                PasteButton(payloadType: String.self) { strings in
                    let found = ShareInput.parse(url: nil, text: strings.joined(separator: " "))
                    Task { @MainActor in model.link = found.url.isEmpty ? strings.first ?? "" : found.url }
                }
                .labelStyle(.titleAndIcon).buttonBorderShape(.capsule).tint(ST.ink)
            }
            .padding(.leading, 18).padding(.trailing, 8)
            .frame(minHeight: ST.field)
            .background(ST.card, in: Capsule())
            .overlay(Capsule().strokeBorder(ST.line, lineWidth: ST.hair))
            .padding(.top, 20)
            if let e = model.linkError { errorLine(e).padding(.top, 10) }
            Button("Importieren") { model.start() }
                .buttonStyle(STPrimary()).disabled(!model.validLink).opacity(model.validLink ? 1 : 0.35)
                .padding(.top, 22)
        }
    }

    /// S20 Koppeln.
    private var pairPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Group {
                    if let ill = ShareArt.ill { ill("pot").frame(width: 70, height: 70) } else {
                        Image(systemName: "fork.knife").font(.system(size: 18, weight: .medium))
                    }
                }
                .frame(width: 44, height: 44).background(ST.blue1).clipShape(Circle())
                Text("Kochpilot").font(ST.text(17, .extrabold))
                Spacer()
                closeButton
            }
            Text("Mit Kochpilot koppeln").font(ST.serif(28)).padding(.top, 26)
            Text("Einmalig: In der App Einstellungen › Teilen aus Instagram einen Code erzeugen und hier eingeben.")
                .font(ST.text(15)).lineSpacing(4).foregroundStyle(ST.ink2).padding(.top, 8)
            Text("SERVER-ADRESSE").stLabel().padding(.top, 24)
            TextField("http://192.168.0.10:8000", text: $model.server)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(.system(size: 15, weight: .medium, design: .monospaced)).foregroundStyle(ST.ink)
                .padding(.horizontal, 18).frame(minHeight: ST.field)
                .background(ST.card, in: Capsule())
                .overlay(Capsule().strokeBorder(ST.line, lineWidth: ST.hair))
                .padding(.top, 8)
            Text("CODE").stLabel().padding(.top, 26)
            ZStack {
                TextField("", text: $model.code)
                    .keyboardType(.numberPad).textContentType(.oneTimeCode)
                    .focused($codeFocus)
                    .foregroundStyle(.clear).tint(.clear)
                    .accessibilityLabel("Kopplungscode, 6 Ziffern")
                HStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { i in
                        codeDigit(i)
                        if i < 5 { Spacer(minLength: 4) }
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(height: digitHeight)
            .contentShape(Rectangle())
            .onTapGesture { codeFocus = true }
            .onChange(of: model.code) { _, new in
                let digits = String(new.filter(\.isNumber).prefix(6))
                if digits != new { model.code = digits }
                if digits.count == 6 { Task { await model.pair() } }
            }
            .padding(.top, 10)
            Text("Bei 6 Ziffern koppeln wir automatisch.").font(ST.text(13)).foregroundStyle(ST.ink2).padding(.top, 14)
            if let e = model.pairError { errorLine(e).padding(.top, 10).transition(.opacity) }
        }
        .onAppear { if !model.demo { codeFocus = true } }
    }

    private func codeDigit(_ i: Int) -> some View {
        let chars = Array(model.code)
        let active = codeFocus && i == min(chars.count, 5)
        let filled = i < chars.count
        let rule = active ? ST.blue3 : filled ? ST.ink : model.pairError != nil ? ST.deal : ST.ink3
        return Text(filled ? String(chars[i]) : "")
            .font(ST.num(52)).tracking(ST.numTracking(52))
            .frame(width: digitWidth, height: digitHeight - 8)
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(rule).frame(height: 2) }
            .animation(ST.spring, value: active)
    }

    /// S22 Import läuft: Topf-Lader, vier Schritte, alle 2,5 s ein Haken.
    private var importingPage: some View {
        let steps = ["Link öffnen", "Rezept wird gelesen …", "Zutaten & Mengen ordnen", "Foto speichern"]
        return VStack(spacing: 0) {
            Group {
                if let pot = ShareArt.potLoader { pot() } else {
                    Circle().fill(ST.blue1).frame(width: 240, height: 240)
                        .overlay(Image(systemName: "fork.knife").font(.system(size: 64, weight: .light)))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            Text("Rezept wird gelesen …").font(ST.t2).multilineTextAlignment(.center).padding(.top, 28)
            Text(URL(string: model.link)?.host() ?? model.link).font(ST.text(13)).foregroundStyle(ST.ink2).lineLimit(1).padding(.top, 4)
            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(spacing: 14) {
                        if i == model.step {
                            Circle().strokeBorder(ST.line, lineWidth: 2)
                                .overlay(Circle().trim(from: 0, to: 0.75).stroke(ST.ink, lineWidth: 2).rotationEffect(.degrees(-45)).padding(1))
                                .frame(width: ST.check, height: ST.check)
                        } else {
                            STCheck(on: i < model.step)
                        }
                        Text(s).font(ST.text(16, i == model.step ? .extrabold : .bold))
                            .foregroundStyle(i <= model.step ? ST.ink : ST.ink3)
                        Spacer()
                    }
                    .frame(height: stepRow)
                    .overlay(alignment: .top) { Rectangle().fill(ST.line).frame(height: ST.hair) }
                    .sensoryFeedback(.success, trigger: i < model.step)
                }
            }
            .padding(.top, 28)
        }
        .frame(maxWidth: .infinity)
    }

    /// S22 Ergebnis.
    @ViewBuilder private var resultPage: some View {
        if let r = model.recipe {
            let estimated = r.ingredients.filter { i in i.estimated == true }.map(\.name)
            let source: String? = r.sourceAuthor.isEmpty ? nil : "\(r.source == "instagram" ? "Instagram" : "Web") · \(r.sourceAuthor)"
            VStack(spacing: 0) {
                AsyncImage(url: ShareAPI.media(r.imageUrl, model.session?.server ?? "")) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else {
                        ST.plate.overlay(Image(systemName: "fork.knife").font(.system(size: 44, weight: .light)).foregroundStyle(ST.ink3))
                    }
                }
                .frame(width: plateSize, height: plateSize)
                .clipShape(Circle())
                .padding(ST.plateRing)
                .background(ST.card, in: Circle())
                .shadow(color: ST.shadow.opacity(0.16), radius: 15, y: 14)
                .padding(.top, 20)
                Text(r.title).font(ST.t2).multilineTextAlignment(.center).padding(.top, 22)
                Text(([source, "\(r.ingredients.count) Zutaten", "\(r.steps.count) Schritte"]).compactMap { $0 }.joined(separator: " · "))
                    .font(ST.text(13)).foregroundStyle(ST.ink2).multilineTextAlignment(.center).padding(.top, 4)
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                    Text(model.existed ? "War schon in Meine Rezepte" : "In Meine Rezepte gespeichert")
                }
                .font(ST.text(13, .extrabold)).padding(.horizontal, 14).frame(height: 30).background(ST.sage, in: Capsule())
                .padding(.top, 16)
                if let planned = model.planned {
                    STSoft(text: "Eingeplant: \(planned)", symbol: "calendar").padding(.top, 8)
                }
                if !estimated.isEmpty {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mengen geschätzt").font(ST.text(16, .extrabold))
                            Text("\(estimated.joined(separator: ", ")) – bitte beim Kochen prüfen").font(ST.text(13)).foregroundStyle(ST.ink2)
                        }
                        Spacer()
                        STSoft(text: "\(estimated.count)", tint: ST.warn)
                    }
                    .frame(minHeight: ST.row)
                    .overlay(alignment: .top) { Rectangle().fill(ST.line).frame(height: ST.hair) }
                    .overlay(alignment: .bottom) { Rectangle().fill(ST.line).frame(height: ST.hair) }
                    .padding(.top, 28)
                }
                if onOpen == nil {
                    Text("Du findest es in Kochpilot › Rezepte › Meine Rezepte (Filter „Importiert“).")
                        .font(ST.text(13)).foregroundStyle(ST.ink2).multilineTextAlignment(.center).padding(.top, 16)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Diese Woche einplanen (ohne Mockup: Zeilen mit Teller-Kreis wie `.irow`).
    @ViewBuilder private var planPage: some View {
        Text("Diese Woche einplanen").font(ST.t2).padding(.trailing, 52)
        Text("„\(model.recipe?.title ?? "")“ ersetzt das Gericht im gewählten Slot.").font(ST.text(15)).foregroundStyle(ST.ink2).padding(.top, 8)
        if let e = model.planError { errorLine(e).padding(.top, 10) }
        VStack(spacing: 0) {
            if let entries = model.entries {
                if entries.isEmpty {
                    message("calendar", "Noch kein Wochenplan", "Erstelle zuerst in der App einen Plan – dann kannst du Rezepte einsetzen.")
                }
                ForEach(entries) { e in
                    Button { Task { await model.replace(e) } } label: {
                        HStack(spacing: 14) {
                            AsyncImage(url: ShareAPI.media(e.recipe.imageUrl, model.session?.server ?? "")) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() } else { ST.blue1 }
                            }
                            .frame(width: ST.rowCircle, height: ST.rowCircle).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(days[e.day]) · \(meals[e.mealType] ?? e.mealType)").font(ST.rowName)
                                Text(e.recipe.title).font(ST.text(13)).foregroundStyle(ST.ink2).lineLimit(1)
                            }
                            Spacer()
                            if e.locked { Image(systemName: "lock").foregroundStyle(ST.ink3).accessibilityLabel("fixiert") }
                            Image(systemName: "arrow.left.arrow.right").foregroundStyle(ST.ink).accessibilityHidden(true)
                        }
                        .frame(minHeight: ST.row)
                        .overlay(alignment: .top) { Rectangle().fill(ST.line).frame(height: ST.hair) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy)
                }
            } else if model.planError == nil {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12).fill(ST.line).frame(height: 48).padding(.vertical, 6)
                }
            }
        }
        .padding(.top, 20)
    }

    private func message(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(spacing: 0) {
            Image(systemName: symbol).font(.system(size: 40, weight: .light))
                .frame(width: 104, height: 104).background(ST.blue1, in: Circle())
            Text(title).font(ST.t2).multilineTextAlignment(.center).padding(.top, 20)
            Text(text).font(ST.text(15)).foregroundStyle(ST.ink2).multilineTextAlignment(.center).padding(.top, 8)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    private func errorLine(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle").font(ST.text(13)).foregroundStyle(ST.deal)
    }

    // MARK: Knöpfe unten

    @ViewBuilder private var buttons: some View {
        switch model.stage {
        case .link:
            EmptyView()  // „Importieren“ steht im Mockup direkt unter dem Feld
        case .pair:
            Button { Task { await model.pair() } } label: {
                if model.busy {
                    if let hop = ShareArt.hop { hop() } else { Text("Koppelt …") }
                } else {
                    Text("Koppeln")
                }
            }
            .buttonStyle(STPrimary(color: ST.blue))
            .disabled(model.code.count < 6 || model.busy)
            .opacity(model.code.count < 6 ? 0.35 : 1)
            .accessibilityLabel(model.busy ? "Koppelt" : "Koppeln")
        case .importing:
            Button("Abbrechen", action: onClose).buttonStyle(STSecondary())
        case .result:
            VStack(spacing: 10) {
                if model.planned == nil {
                    Button("Diese Woche einplanen") { Task { await model.loadPlan() } }.buttonStyle(STSecondary())
                }
                if let onOpen, let id = model.recipe?.id {
                    Button("Rezept ansehen") { onOpen(id) }.buttonStyle(STPrimary())
                } else {
                    Button("Fertig", action: onClose).buttonStyle(STPrimary())
                }
            }
        case .plan:
            Button("Zurück") { withAnimation(ST.spring) { model.stage = .result } }.buttonStyle(STSecondary())
        case .noRecipe:
            VStack(spacing: 10) {
                if onOpen != nil {
                    Button("Anderen Link") { withAnimation(ST.spring) { model.link = ""; model.stage = .link } }.buttonStyle(STSecondary())
                }
                Button("Schließen", action: onClose).buttonStyle(STPrimary())
            }
        case .failed:
            VStack(spacing: 10) {
                Button("Erneut versuchen") { model.start() }.buttonStyle(STPrimary())
                Button("Schließen", action: onClose).buttonStyle(STSecondary())
            }
        }
    }
}
