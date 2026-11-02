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
        case .pair: stage = .pair; server = "http://192.168.0.224:8000"; code = "4829"
        case .importing: stage = .importing; step = 2; link = "https://www.instagram.com/reel/C9xYz12AbCd/"
        case .result: stage = .result; recipe = Self.demoRecipe; link = "https://www.instagram.com/reel/C9xYz12AbCd/"
        case nil:
            if !link.isEmpty { start() } else if input != nil { linkError = "Im geteilten Inhalt war kein Link." }
        }
    }

    static let demoRecipe = ImportedRecipe(
        id: 102, title: "One-Pot-Pasta mit Feta", imageUrl: "",
        ingredients: [.init(name: "Spaghetti", estimated: nil), .init(name: "Kirschtomaten", estimated: nil), .init(name: "Feta", estimated: nil),
                      .init(name: "Knoblauch", estimated: true), .init(name: "Olivenöl", estimated: true), .init(name: "Basilikum", estimated: nil),
                      .init(name: "Salz", estimated: true)],
        steps: ["a", "b", "c", "d"], source: "instagram", sourceAuthor: "@koch_xy")

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

/// S20 Teilen-Erweiterung „Essenapp“ (auch „Link einfügen“ in der App, S22): Link → ggf. Kopplung → Import → Ergebnis.
public struct ShareFlowView: View {
    @State private var model: ShareModel
    private let onOpen: ((Int) -> Void)?
    private let onClose: () -> Void
    @FocusState private var codeFocus: Bool
    @State private var spin = false

    /// `persist`: Kopplung im Schlüsselbund der Erweiterung speichern. `onOpen` (nur App): „Rezept ansehen“.
    public init(input: ShareInput?, session: ShareSession?, persist: Bool = false, demo: ShareDemo? = nil,
                onOpen: ((Int) -> Void)? = nil, onClose: @escaping () -> Void) {
        _model = State(initialValue: ShareModel(input: input, session: session, persist: persist, demo: demo))
        self.onOpen = onOpen
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("🍲").font(.system(size: 18)).frame(width: 34, height: 34).background(ST.accentSoft, in: Circle())
                Text("Essenapp").font(ST.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(ST.text1)
                        .frame(width: 44, height: 44).background(ST.card, in: Circle())
                        .overlay(Circle().strokeBorder(ST.line, lineWidth: 0.5))
                }
                .accessibilityLabel("Schließen")
            }
            .padding(.horizontal, ST.page).padding(.top, 16).padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { content }
                    .padding(.horizontal, ST.page).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            buttons
                .padding(.horizontal, ST.page).padding(.top, 8).padding(.bottom, 16)
        }
        .background(ST.bg.ignoresSafeArea())
        .foregroundStyle(ST.text1)
        .tint(ST.accentDeep)
        .environment(\.locale, Locale(identifier: "de_DE"))
        .onAppear {
            #if DEBUG
            ShareInput.selfTest()
            #endif
        }
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
            message("🤷", "Kein Rezept gefunden",
                    "In der Beschreibung steht kein Rezept – manche Reels zeigen es nur im Video. Probier einen anderen Beitrag oder eine Rezept-Webseite.")
        case .failed(let text): message("📡", "Das hat nicht geklappt", text)
        }
    }

    private var linkPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rezept aus Link").font(ST.title)
            Text("Instagram-Reel, -Beitrag oder Rezept-Webseite – wir machen daraus ein Rezept in „Meine Rezepte“.")
                .font(ST.caption).foregroundStyle(ST.text2)
            HStack(spacing: 8) {
                TextField("https://www.instagram.com/reel/…", text: $model.link)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(.horizontal, 16).frame(minHeight: 50)
                    .background(ST.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(ST.line, lineWidth: 0.5))
                PasteButton(payloadType: String.self) { strings in
                    let found = ShareInput.parse(url: nil, text: strings.joined(separator: " "))
                    Task { @MainActor in model.link = found.url.isEmpty ? strings.first ?? "" : found.url }
                }
                .labelStyle(.iconOnly).buttonBorderShape(.capsule).tint(ST.pasteTint)
            }
            if let e = model.linkError { Text(e).font(ST.caption).foregroundStyle(ST.danger) }
        }
    }

    private var pairPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mit Essenapp koppeln").font(ST.title)
            Text("Einmalig: Öffne in der App Einstellungen › Teilen aus Instagram, tippe „Code erzeugen“ und gib hier Server-Adresse und Code ein.")
                .font(ST.caption).foregroundStyle(ST.text2)
            VStack(alignment: .leading, spacing: 6) {
                Text("SERVER-ADRESSE").font(ST.micro).foregroundStyle(ST.text2)
                TextField("http://192.168.0.10:8000", text: $model.server)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 16).frame(minHeight: 50)
                    .background(ST.card, in: RoundedRectangle(cornerRadius: ST.tile, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("KOPPLUNGSCODE").font(ST.micro).foregroundStyle(ST.text2)
                ZStack {
                    TextField("", text: $model.code)
                        .keyboardType(.numberPad).textContentType(.oneTimeCode)
                        .focused($codeFocus)
                        .foregroundStyle(.clear).tint(.clear)
                        .accessibilityLabel("Kopplungscode, 6 Ziffern")
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { i in codeBox(i) }
                    }
                    .allowsHitTesting(false)
                }
                .frame(height: 64)
                .contentShape(Rectangle())
                .onTapGesture { codeFocus = true }
                .onChange(of: model.code) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(6))
                    if digits != new { model.code = digits }
                    if digits.count == 6 { Task { await model.pair() } }
                }
            }
            if let e = model.pairError {
                Label(e, systemImage: "exclamationmark.circle.fill").font(ST.caption).foregroundStyle(ST.danger)
                    .transition(.opacity)
            }
        }
        .onAppear { if !model.demo { codeFocus = true } }
    }

    private func codeBox(_ i: Int) -> some View {
        let chars = Array(model.code)
        let active = codeFocus && i == min(chars.count, 5)
        return Text(i < chars.count ? String(chars[i]) : "")
            .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(ST.card, in: RoundedRectangle(cornerRadius: ST.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ST.tile, style: .continuous)
                .strokeBorder(active ? ST.accent : (model.pairError != nil ? ST.danger.opacity(0.5) : ST.line), lineWidth: active ? 2 : 1))
            .animation(ST.spring, value: active)
    }

    private var importingPage: some View {
        let steps = ["Link öffnen", "Rezept wird gelesen …", "Zutaten & Mengen ordnen", "Foto speichern"]
        return VStack(spacing: 18) {
            Text("🍲").font(.system(size: 60))
                .frame(width: 130, height: 130)
                .background(Circle().fill(ST.card).shadow(color: .black.opacity(0.08), radius: 12, y: 6))
                .rotationEffect(.degrees(spin ? 360 : 0))
                .onAppear { withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { spin = true } }
                .padding(.top, 12)
            Text("Rezept wird gelesen …").font(ST.title)
            Text(URL(string: model.link)?.host() ?? model.link).font(ST.caption).foregroundStyle(ST.text2).lineLimit(1)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(i < model.step ? ST.accent : ST.surface)
                            if i < model.step {
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                    .transition(.scale.combined(with: .opacity))
                            } else if i == model.step {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .frame(width: 28, height: 28)
                        Text(s).font(ST.callout).foregroundStyle(i <= model.step ? ST.text1 : ST.text3)
                        Spacer()
                    }
                    .sensoryFeedback(.success, trigger: i < model.step)
                }
            }
            .padding(18).stCard()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var resultPage: some View {
        if let r = model.recipe {
            let estimated = r.ingredients.filter { i in i.estimated == true }.map(\.name)
            VStack(spacing: 14) {
                AsyncImage(url: ShareAPI.media(r.imageUrl, model.session?.server ?? "")) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { Text("🍝").font(.system(size: 64)) }
                }
                .frame(width: 150, height: 150)
                .background(ST.card)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.12), radius: 12, y: 8)
                Text(r.title).font(ST.title).multilineTextAlignment(.center)
                if !r.sourceAuthor.isEmpty {
                    Text("\(r.source == "instagram" ? "Instagram" : "Web") · \(r.sourceAuthor)").font(ST.caption).foregroundStyle(ST.text2)
                }
                HStack(spacing: 8) {
                    chip("\(r.ingredients.count) Zutaten", "list.bullet")
                    chip("\(r.steps.count) Schritte", "text.alignleft")
                }
                Label(model.existed ? "War schon in Meine Rezepte" : "In Meine Rezepte gespeichert", systemImage: "checkmark.circle.fill")
                    .font(ST.callout).foregroundStyle(ST.success)
                    .padding(.horizontal, 14).frame(minHeight: 36).background(ST.successSoft, in: Capsule())
                if let planned = model.planned {
                    Label("Eingeplant: \(planned)", systemImage: "calendar.badge.checkmark")
                        .font(ST.callout).foregroundStyle(ST.accentDeep)
                        .padding(.horizontal, 14).frame(minHeight: 36).background(ST.accentSoft, in: Capsule())
                }
                if !estimated.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(estimated.count == 1 ? "1 Menge geschätzt" : "\(estimated.count) Mengen geschätzt", systemImage: "exclamationmark.triangle.fill")
                            .font(ST.callout).foregroundStyle(ST.text1)
                        Text("\(estimated.joined(separator: ", ")) – im Original stand keine Menge. Bitte beim Kochen prüfen.")
                            .font(ST.caption).foregroundStyle(ST.text2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(ST.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: ST.tile, style: .continuous))
                }
                if onOpen == nil {
                    Text("Du findest es in Essenapp › Rezepte › Meine Rezepte (Filter „Importiert“).")
                        .font(ST.caption).foregroundStyle(ST.text2).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder private var planPage: some View {
        Text("Diese Woche einplanen").font(ST.title)
        Text("„\(model.recipe?.title ?? "")“ ersetzt das Gericht im gewählten Slot.").font(ST.caption).foregroundStyle(ST.text2)
        if let e = model.planError {
            Label(e, systemImage: "exclamationmark.circle.fill").font(ST.caption).foregroundStyle(ST.danger)
        }
        if let entries = model.entries {
            if entries.isEmpty {
                message("📅", "Noch kein Wochenplan", "Erstelle zuerst in der App einen Plan – dann kannst du Rezepte einsetzen.")
            }
            ForEach(entries) { e in
                Button { Task { await model.replace(e) } } label: {
                    HStack(spacing: 12) {
                        AsyncImage(url: ShareAPI.media(e.recipe.imageUrl, model.session?.server ?? "")) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() } else { ST.surface }
                        }
                        .frame(width: 44, height: 44).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(days[e.day]) · \(meals[e.mealType] ?? e.mealType)").font(ST.callout)
                            Text(e.recipe.title).font(ST.caption).foregroundStyle(ST.text2).lineLimit(1)
                        }
                        Spacer()
                        if e.locked { Image(systemName: "lock.fill").foregroundStyle(ST.text3).accessibilityLabel("fixiert") }
                        Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(ST.accentDeep).accessibilityHidden(true)
                    }
                    .padding(12).frame(minHeight: 44)
                    .stCard(radius: ST.tile)
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
            }
        } else if model.planError == nil {
            ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: ST.tile).fill(ST.surface).frame(height: 68) }
        }
    }

    private func message(_ emoji: String, _ title: String, _ text: String) -> some View {
        VStack(spacing: 12) {
            Text(emoji).font(.system(size: 52)).frame(width: 104, height: 104).background(ST.accentSoft, in: Circle())
            Text(title).font(ST.headline)
            Text(text).font(ST.caption).foregroundStyle(ST.text2).multilineTextAlignment(.center)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    private func chip(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol).font(ST.callout)
            .padding(.horizontal, 14).frame(minHeight: 36).background(ST.card, in: Capsule())
            .overlay(Capsule().strokeBorder(ST.line, lineWidth: 0.5))
    }

    // MARK: Knöpfe unten

    @ViewBuilder private var buttons: some View {
        switch model.stage {
        case .link:
            Button("Importieren") { model.start() }
                .buttonStyle(STPrimary()).disabled(!model.validLink).opacity(model.validLink ? 1 : 0.5)
        case .pair:
            Button { Task { await model.pair() } } label: {
                if model.busy { ProgressView().tint(ST.onAction) } else { Text("Koppeln") }
            }
            .buttonStyle(STPrimary())
            .disabled(model.code.count < 6 || model.busy).opacity(model.code.count < 6 ? 0.5 : 1)
        case .importing:
            Button("Abbrechen", action: onClose).buttonStyle(STSecondary())
        case .result:
            VStack(spacing: 10) {
                if let onOpen, let id = model.recipe?.id {
                    Button("Rezept ansehen") { onOpen(id) }.buttonStyle(STPrimary())
                } else {
                    if model.planned == nil {
                        Button { Task { await model.loadPlan() } } label: { Label("Diese Woche einplanen", systemImage: "calendar.badge.plus") }
                            .buttonStyle(STSecondary())
                    }
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
