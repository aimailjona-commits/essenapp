import EssenappShareUI
import SwiftUI

/// „Alles“ (v9 f.html 2A): Fläche aus dem „+“ der Tab-Leiste. Suche, die fünf Kern-Dinge mit Zeichnung, alle Funktionen als
/// Pillen; darunter „Noch nicht ausprobiert“ (2B). Liegt unter der Tab-Leiste, damit das „+“ als × sichtbar bleibt.
struct AllSheet: View {
    /// Ziele außerhalb der Fläche (MainView schließt sie dabei).
    enum Go { case close, tab(AppTab), recipes, planWeek, generator, scan, barcode, review, recipe(Int) }

    struct Feature: Identifiable {
        let id: String
        let title: String
        let icon: Icon8
        var new = false
        var pitch: (ill: String, text: String)?  // Karte in „Noch nicht ausprobiert“
    }

    struct Thing {
        let title: String
        let sub: String
        let ill: String
        let tint: Color
        let items: [Feature]
    }

    static let things: [Thing] = [
        Thing(title: "Gericht", sub: "kochen, sammeln, teilen", ill: "pot", tint: Theme.C.blue1, items: [
            Feature(id: "cook", title: "Kochmodus", icon: .play),
            Feature(id: "recipes", title: "Meine Rezepte", icon: .book),
            Feature(id: "newRecipe", title: "Rezept anlegen", icon: .edit),
            Feature(id: "import", title: "Aus Instagram", icon: .link, new: true,
                    pitch: ("cookbook", "Link aus Instagram oder einer Webseite einfügen – das Rezept landet bei dir.")),
            Feature(id: "fridge", title: "Kühlschrank-Foto", icon: .cam,  // shortcut: Kamera statt eigenem Kühlschrank-Symbol, bis make_icons.py es erzeugt
                    pitch: ("fridge", "Foto machen – wir füllen den Vorrat und schlagen 3 Gerichte vor.")),
        ]),
        Thing(title: "Woche", sub: "planen & anpassen", ill: "table", tint: Theme.C.sage, items: [
            Feature(id: "swipe", title: "Swipe-Planen", icon: .heart,
                    pitch: ("table", "Gerichte wischen wie Karten – deine Woche plant sich fast von allein.")),
            Feature(id: "generator", title: "Überrasch mich", icon: .dice),
            Feature(id: "nomood", title: "Keine Lust?", icon: .clock, pitch: ("lying", "Schnelle Gerichte in 15 Minuten, ganz ohne Einkauf.")),
            Feature(id: "guests", title: "Gäste", icon: .users),
            Feature(id: "rests", title: "Reste", icon: .refresh),
            Feature(id: "variety", title: "Abwechslung", icon: .leaf),
            Feature(id: "basics", title: "Frühstück & Snacks", icon: .sparkle),
        ]),
        Thing(title: "Angebote", sub: "finden, merken, sparen", ill: "tomato", tint: Theme.C.rose, items: [
            Feature(id: "forYou", title: "Für dich", icon: .tag),
            Feature(id: "watchlist", title: "Merkliste", icon: .heart),
            Feature(id: "alarm", title: "Preisalarm", icon: .bell,
                    pitch: ("binoculars", "Sag uns deinen Wunschpreis – wir melden uns, sobald es so weit ist.")),
            Feature(id: "barcode", title: "Barcode", icon: .barcode),
            Feature(id: "nextweek", title: "Nächste Woche", icon: .eye),
            Feature(id: "stores", title: "Läden & Umkreis", icon: .pin),
        ]),
        Thing(title: "Einkauf", sub: "Liste, Vorrat, Coupons", ill: "bag", tint: Theme.C.sand, items: [
            Feature(id: "list", title: "Einkaufsliste", icon: .bag),
            Feature(id: "voice", title: "Per Sprache", icon: .mic),
            Feature(id: "pantry", title: "Vorrat", icon: .box),
            Feature(id: "coupons", title: "Coupons & Bonus", icon: .gift,
                    pitch: ("shopper", "Coupons und Bonuskarten an einem Ort – an der Kasse einfach vorzeigen.")),
            Feature(id: "reminder", title: "Erinnerung im Laden", icon: .pin),
            Feature(id: "spending", title: "Ausgaben", icon: .chart),
        ]),
        Thing(title: "Ich & Familie", sub: "Ziele, Erfolge, Geräte", ill: "shopper", tint: Theme.C.blue, items: [
            Feature(id: "family", title: "Familie einladen", icon: .users),
            Feature(id: "goal", title: "Mein Ziel", icon: .sparkle),
            Feature(id: "achievements", title: "Erfolge", icon: .trophy),
            Feature(id: "review", title: "Wochenrückblick", icon: .book),
            Feature(id: "widget", title: "Widget", icon: .widget, pitch: ("pot", "Das Gericht von heute direkt auf dem Home-Bildschirm.")),
            Feature(id: "settings", title: "Einstellungen", icon: .gear),
        ]),
    ]

    static var features: [Feature] { things.flatMap(\.items) }

    /// Schon einmal geöffnete Funktionen (lokal, für „Noch nicht ausprobiert“).
    static let triedKey = "triedFeatures"
    static func markTried(_ id: String) {
        let d = UserDefaults.standard
        var set = Set((d.string(forKey: triedKey) ?? "").split(separator: ",").map(String.init))
        guard set.insert(id).inserted else { return }
        d.set(set.sorted().joined(separator: ","), forKey: triedKey)
    }

    private enum Sheet: String, Identifiable {
        case newRecipe, importing, nomood, guests, alarm, nextweek
        var id: String { rawValue }
    }

    // Mockup-Maße (f.html .f9-sheet, .f9-oh, .f9-fn)
    private enum K {
        static let thingCircle: CGFloat = 52, thingIll: CGFloat = 60
        static let pill: CGFloat = 38, pillIcon: CGFloat = 17
        static let newBadge: CGFloat = 18
        static let tryIll: CGFloat = 130
        static let tryButton: CGFloat = 36
        static let bottom: CGFloat = 140  // Ende über der Tab-Leiste
    }

    @Environment(AppStore.self) private var store
    @AppStorage("triedFeatures") private var tried = ""  // = triedKey
    @State private var query = ""
    @State private var path: [String] = []
    @State private var sheet: Sheet?
    let go: (Go) -> Void

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Alles").font(Theme.F.t2).accessibilityAddTraits(.isHeader)
                        Spacer()
                        Text("\(Self.features.count) Funktionen").font(Theme.F.text(13, .semibold, relativeTo: .footnote))
                            .foregroundStyle(Theme.C.ink2)
                    }
                    FieldBox(icon: .search) {
                        TextField("", text: $query, prompt: Text("Funktion, Rezept oder Angebot").foregroundStyle(Theme.C.ink2))
                            .submitLabel(.search)
                        if !query.isEmpty {
                            Button { query = "" } label: { Icon(.x, size: 18).frame(width: 44, height: 44) }
                                .buttonStyle(.plain).accessibilityLabel("Suche leeren")
                        }
                    }
                    .padding(.top, 14)
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        ForEach(Self.things, id: \.title) { thing in thingBlock(thing).padding(.top, 22) }
                        untried
                    } else {
                        results.padding(.top, 18)
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 30)
                .padding(.bottom, K.bottom)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Theme.C.bg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { id in page(id) }
        }
        .background(Theme.C.bg)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: Theme.R.sheet, topTrailingRadius: Theme.R.sheet, style: .continuous))
        .overlay(alignment: .top) {
            // Griff: antippen oder nach unten ziehen schließt
            Capsule().fill(Theme.C.ink3).frame(width: Theme.S.grip.width, height: Theme.S.grip.height)
                .frame(width: 120, height: 30)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 10).onEnded { v in if v.translation.height > 60 { go(.close) } })
                .onTapGesture { go(.close) }
                .accessibilityLabel("Alles schließen")
                .accessibilityAddTraits(.isButton)
        }
        .sheet(item: $sheet) { s in sheetView(s) }
    }

    // MARK: Kern-Dinge

    private func thingBlock(_ thing: Thing) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle().fill(thing.tint).frame(width: K.thingCircle, height: K.thingCircle)
                    .overlay(alignment: .topLeading) { Ill(thing.ill).frame(width: K.thingIll).offset(x: -4, y: -2) }
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(thing.title).font(Theme.F.serif(22, relativeTo: .title2))
                    Text(thing.sub).font(Theme.F.text(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.C.ink2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            pills(thing.items)
        }
    }

    private func pills(_ items: [Feature]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(items) { f in
                Button { open(f) } label: {
                    HStack(spacing: 7) {
                        Icon(f.icon, size: K.pillIcon)
                        Text(f.title).lineLimit(1)
                        if f.new {
                            Text("neu").font(Theme.F.text(10, .extrabold, relativeTo: .caption2))
                                .padding(.horizontal, 6).frame(height: K.newBadge)
                                .background(Theme.C.blue, in: Capsule())
                                .padding(.leading, 2)
                        }
                    }
                    .font(Theme.F.text(13, .extrabold, relativeTo: .footnote))
                    .foregroundStyle(Theme.C.ink)
                    .padding(.leading, 10).padding(.trailing, 14)
                    .frame(minHeight: K.pill)
                    .background(Theme.C.card, in: Capsule())
                    .padding(3).contentShape(Rectangle()).padding(-3)  // Tap-Fläche 44 ohne Einfluss aufs Layout
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(f.new ? "\(f.title), neu" : f.title)
            }
        }
    }

    // MARK: Noch nicht ausprobiert (2B)

    @ViewBuilder private var untried: some View {
        let done = Set(tried.split(separator: ",").map(String.init))
        let open = Self.features.filter { f in f.pitch != nil && !done.contains(f.id) }.prefix(2)
        if !open.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                SectionLabel("Wusstest du?")
                Text("Noch nicht ausprobiert").font(Theme.F.serif(27, relativeTo: .title)).accessibilityAddTraits(.isHeader)
            }
            .padding(.top, 30).padding(.bottom, 10)
            VStack(spacing: 10) {
                ForEach(Array(open)) { f in tryCard(f) }
            }
        }
    }

    private func tryCard(_ f: Feature) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(f.title).font(Theme.F.text(17, .extrabold, relativeTo: .headline))
            Text(f.pitch?.text ?? "").font(Theme.F.text(13, .semibold, relativeTo: .footnote)).foregroundStyle(Theme.C.ink2)
                .padding(.top, 4)
            Button { open(f) } label: {
                Text("Ausprobieren").font(Theme.F.pill).foregroundStyle(Theme.C.onInk)
                    .padding(.horizontal, 14).frame(height: K.tryButton)
                    .background(Theme.C.ink, in: Capsule())
                    .padding(4).contentShape(Rectangle()).padding(-4)
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("\(f.title) ausprobieren")
            .padding(.top, 14)
        }
        .frame(maxWidth: 200, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(alignment: .topTrailing) { Ill(f.pitch?.ill ?? "pot").frame(width: K.tryIll).offset(x: 24, y: -10) }
        .background(Theme.C.card)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: Suche: Funktionen, Gerichte, Angebote

    private var results: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let features = Self.features.filter { $0.title.localizedCaseInsensitiveContains(q) }
        let meals = store.plan?.entries.filter { $0.recipe.title.localizedCaseInsensitiveContains(q) } ?? []
        let offers = store.offers.filter { $0.title.localizedCaseInsensitiveContains(q) }.prefix(20)
        return VStack(alignment: .leading, spacing: 0) {
            if !features.isEmpty {
                SectionLabel("Funktionen").padding(.bottom, 10)
                pills(features).padding(.bottom, 18)
            }
            if !meals.isEmpty { SectionLabel("Gerichte").padding(.bottom, 6) }
            ForEach(meals, id: \.self) { meal in
                NavigationLink { RecipeDetailView(meal: meal) } label: {
                    IRow(name: meal.recipe.title, sub: "\(Labels.days[meal.day]) · \(Labels.meal(meal.mealType))") {
                        PlanPlate(url: mediaURL(meal.recipe.imageUrl), size: Theme.S.rowCircle, mini: true)
                    }
                    .foregroundStyle(Theme.C.ink)
                }
                .buttonStyle(PressableStyle())
            }
            if !offers.isEmpty { SectionLabel("Angebote").padding(.top, 18).padding(.bottom, 6) }
            ForEach(Array(offers)) { offer in
                NavigationLink { OfferDetailView(offer: offer) } label: {
                    IRow(name: offer.title, sub: "\(Labels.chain(offer.chain)) · \(euro(offer.priceCents))",
                         tint: Theme.hue(category: offer.category).tint) {
                        RemoteImage(url: URL(string: offer.imageUrl)) { Icon(.tag, size: 22) }.padding(6).clipShape(Circle())
                    } trail: {
                        if let d = offer.discount { DealPill(text: "−\(d) %") }
                    }
                    .foregroundStyle(Theme.C.ink)
                }
                .buttonStyle(PressableStyle())
            }
            if features.isEmpty && meals.isEmpty && offers.isEmpty {
                VStack(spacing: 8) {
                    Ill("binoculars").frame(width: 120)
                    Text("Nichts gefunden").font(Theme.F.t2)
                    Text("Versuch einen anderen Begriff.").font(Theme.F.small).foregroundStyle(Theme.C.ink2)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Öffnen

    private var someMeal: MealDTO? { store.todayMeal ?? store.plan?.entries.first }

    private func open(_ f: Feature) {
        Self.markTried(f.id)
        switch f.id {
        case "cook":
            if let m = someMeal { go(.recipe(m.recipe.id)) } else { store.flash("Noch kein Gericht geplant") }
        case "recipes": go(.recipes)
        case "swipe": go(.planWeek)
        case "generator": go(.generator)
        case "fridge": go(.scan)
        case "barcode": go(.barcode)
        case "review": go(.review)
        case "forYou": go(.tab(.angebote))
        case "list", "voice": go(.tab(.einkauf))  // Sprach-Eingabe sitzt im Feld der Einkaufsliste
        case "rests": go(.tab(.woche))  // Reste-Karte steht im Wochenplan
        case "newRecipe": sheet = .newRecipe
        case "import": sheet = .importing
        case "nomood": sheet = .nomood
        case "guests":
            if someMeal != nil { sheet = .guests } else { store.flash("Noch kein Gericht geplant") }
        case "alarm": sheet = .alarm
        case "nextweek": sheet = .nextweek
        default: path.append(f.id)
        }
    }

    @ViewBuilder private func page(_ id: String) -> some View {
        switch id {
        case "variety": VarietyView()
        case "basics": WeeklyBasicsView()
        case "watchlist": WatchListView { go(.tab(.angebote)) }.backBar()
        case "stores": StoreMapView()
        case "pantry": PantryView(page: .constant(1)).backBar()
        case "coupons": CouponWalletView(page: .constant(2)).backBar()
        case "reminder": NotificationsView()
        case "spending": SpendingView()
        case "goal": ProfileView()
        case "achievements": AchievementsView()
        case "widget": InstagramShareView(widget: true)
        default: SettingsView()  // family, settings
        }
    }

    @ViewBuilder private func sheetView(_ s: Sheet) -> some View {
        switch s {
        case .newRecipe: RecipeFormSheet().presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet)
        case .importing:
            ShareFlowView(input: nil, session: store.shareSession, onOpen: { id in
                sheet = nil
                store.recipesVersion += 1
                Task { try? await Task.sleep(for: .milliseconds(450)); go(.recipe(id)) }  // erst nach dem Schließen des Sheets
            }) { sheet = nil }
            .presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet)
        case .nomood: NoMoodSheet().presentationDetents([.large])
        case .guests:
            if let m = someMeal { GuestsSheet(meal: m).presentationDetents([.height(466), .large]) }
        case .alarm: WatchSearchSheet().presentationDetents([.large]).presentationCornerRadius(Theme.R.sheet)
        case .nextweek: TipsSheet().presentationDetents([.large])
        }
    }
}

extension View {
    /// Zurück-Pfeil über Seiten, die sonst nur als Tab-Inhalt erscheinen (Vorrat, Coupons, Merkliste, Rezepte).
    func backBar() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            HStack { BackButton8(); Spacer() }
                .padding(.horizontal, Theme.pagePadding).padding(.vertical, 9)
                .background(Theme.C.bg)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
