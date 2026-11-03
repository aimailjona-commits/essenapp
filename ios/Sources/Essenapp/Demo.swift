import Foundation
import UIKit

/// Demo-Modus für Screenshots im Simulator (CI): App starten mit `-demoScreen <name>`.
/// Namen: onboarding, start, quick, generator, generating, offers, offer, plan, recipe, shopping, list, pantry, settings, profile,
/// notifications, stores, empty, cooking (Kochmodus Schritt 2 mit Timer), sharecard (Bildkarte),
/// recipes (Meine Rezepte), myrecipe (eigenes Rezept mit Bewertungen + Blüte), recipeform (Rezept-Formular, Seite Zutaten),
/// imported (Instagram-Import mit Original-Reel, geschätzten Mengen, Schritt-Bildern), instagram (Teilen aus Instagram, S21),
/// sharepair / shareimport / shareresult (Teilen-Erweiterung S20), importlink (Link einfügen S22),
/// fridgecam / fridgereview / cooknow (Kühlschrank-Foto S23–S25), offline (Einkauf mit Offline-Banner, 66),
/// voiceadd (Einkauf mit Sprach-Eingabe, 45), storeask (Benachrichtigungen mit Erklär-Sheet Standort-Erinnerung, 36),
/// substitute (Ersatz finden, 7), nomood („Keine Lust“, 16), guests (Gäste-Sheet über dem Wochenplan, 15),
/// leftovers (Reste in den Vorrat, 19), basics (Frühstück & Snacks, 23), variety (Präferenzen › Abwechslung, 12),
/// Phase 12: watch (Merkliste S10), scanner (Barcode-Scan + „Auf Merkliste?“), nextweek (Angebote nächste Woche),
/// offerstock (Angebotsdetail mit Vorratstipp + Bio/Nutri), savings (Start: Budget-Rest, nächste Woche günstiger, Vorrat),
/// budgetover (Start: über Budget), singlestore (Plan-Generator: nächste Woche + nur ein Laden).
/// Erscheinungsbild (68): zusätzlich `-demoAppearance dark|light` (überschreibt die Einstellung).
enum Demo {
    static let screen: String? = arg("-demoScreen")
    static let appearance: String? = arg("-demoAppearance")

    private static func arg(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Preisverlauf (28): Hähnchenbrust bei Rewe (jetzt 3,99 €) und Lidl, 12 Wochen bis heute → „Gutes Angebot“.
    static func history(for id: Int) -> OfferHistoryDTO {
        guard id == offers[0].id else {
            return OfferHistoryDTO(points: [], medianCents: nil, minCents: nil, verdict: "zu_wenig_daten", lastLow: nil, avgIntervalWeeks: nil)
        }
        let cal = Calendar(identifier: .iso8601)
        func week(_ back: Int) -> String {
            let d = cal.date(byAdding: .weekOfYear, value: -back, to: .now) ?? .now
            let w = cal.component(.weekOfYear, from: d)
            return "\(cal.component(.yearForWeekOfYear, from: d))-W\(w < 10 ? "0" : "")\(w)"
        }
        let rewe = [599, 599, 449, 599, 599, 599, 499, 599, 599, 599, 599, 399]
        let lidl = [549, 549, 549, 379, 549, 549, 549, 549, 429, 549, 549, 549]
        let points = (0..<12).flatMap { i in [
            OfferHistoryDTO.Point(week: week(11 - i), chain: "rewe", priceCents: rewe[i], regularPriceCents: 599, isOffer: rewe[i] < 599),
            OfferHistoryDTO.Point(week: week(11 - i), chain: "lidl", priceCents: lidl[i], regularPriceCents: nil, isOffer: lidl[i] < 549),
        ] }
        return OfferHistoryDTO(points: points, medianCents: 549, minCents: 379, verdict: "gut",
                               lastLow: .init(week: week(8), chain: "lidl", priceCents: 379), avgIntervalWeeks: 3.7)
    }

    static let household = HouseholdDTO(
        id: 1, name: "Zuhause", plz: "50667", persons: 2, diet: "alles", allergies: ["Laktose"], excludedIngredients: [],
        cuisines: [], mealTypes: ["mittag", "abend"], planDays: [0, 1, 2, 3, 4], budgetFoodWeekCents: 6000,
        budgetDrugstoreCents: nil, nutritionGoal: "ausgewogen", maxCookMinutes: 45, radiusKm: 3, lat: 50.9375, lng: 6.9603,
        stores: nearby.prefix(4).map { StoreDTO(chain: $0.chain, storeName: $0.name, osmId: $0.osmId, lat: $0.lat, lng: $0.lng, address: $0.address) },
        stepImages: true, stepImagesAvailable: true)

    static let nearby: [NearbyStore] = [
        NearbyStore(osmId: "n1", chain: "rewe", name: "REWE Hohe Straße", address: "Hohe Str. 30, 50667 Köln", lat: 50.9378, lng: 6.9568, distanceKm: 0.3),
        NearbyStore(osmId: "n2", chain: "lidl", name: "Lidl", address: "Gereonstr. 1, 50670 Köln", lat: 50.9431, lng: 6.9497, distanceKm: 0.9),
        NearbyStore(osmId: "n3", chain: "aldi_sued", name: "ALDI SÜD", address: "Breite Str. 80, 50667 Köln", lat: 50.9381, lng: 6.9480, distanceKm: 0.9),
        NearbyStore(osmId: "n4", chain: "dm", name: "dm-drogerie markt", address: "Schildergasse 65, 50667 Köln", lat: 50.9359, lng: 6.9530, distanceKm: 0.6),
        NearbyStore(osmId: "n5", chain: "rossmann", name: "Rossmann", address: "Schildergasse 24, 50667 Köln", lat: 50.9364, lng: 6.9555, distanceKm: 0.4),
        NearbyStore(osmId: "n6", chain: "edeka", name: "EDEKA Neumarkt", address: "Neumarkt 18, 50667 Köln", lat: 50.9356, lng: 6.9467, distanceKm: 1.0),
        NearbyStore(osmId: "n7", chain: "penny", name: "PENNY", address: "Severinstr. 120, 50678 Köln", lat: 50.9262, lng: 6.9585, distanceKm: 1.3),
    ]

    static let offers: [OfferDTO] = [
        offer(1, "rewe", "Hähnchenbrustfilet", "fleisch_fisch", 399, 599, 400, "g", 998, verdict: "gut"),
        offer(2, "aldi_sued", "Avocado, essreif", "obst_gemuese", 79, 119, 1, "stk", 79, verdict: "bestpreis", vegan: true),
        offer(3, "lidl", "Rispentomaten", "obst_gemuese", 199, nil, 500, "g", 398),
        offer(4, "lidl", "Lachsfilet", "fleisch_fisch", 349, 499, 250, "g", 1396, verdict: "kein_echtes"),
        offer(5, "aldi_sued", "Skyr Natur", "kuehlung", 129, 159, 450, "g", 287, verdict: "normal", nutri: "A"),
        offer(6, "dm", "Shampoo Repair", "drogerie", 179, 239, 300, "ml", 597, monthly: true),
        offer(7, "rewe", "Basmatireis", "vorrat", 149, 199, 500, "g", 298, verdict: "bestpreis", nutri: "A", bio: true, vegan: true),
        offer(8, "lidl", "Feta", "kuehlung", 99, 139, 200, "g", 495, verdict: "gut", nutri: "D"),
    ]

    static func offer(_ id: Int, _ chain: String, _ title: String, _ category: String, _ price: Int, _ regular: Int?,
                      _ amount: Double, _ unit: String, _ base: Int, verdict: String = "zu_wenig_daten", nutri: String? = nil,
                      bio: Bool = false, vegan: Bool = false, monthly: Bool = false, from: String = "2026-11-02",
                      to: String = "2026-11-07") -> OfferDTO {
        OfferDTO(id: id, chain: chain, title: title, brand: "", category: category, priceCents: price, regularPriceCents: regular,
                 amount: amount, unit: unit, basePriceCents: base, validFrom: from, validTo: to, imageUrl: "", verdict: verdict,
                 bio: bio, vegan: vegan, vegetarian: vegan, nutriScore: nutri,
                 labelSources: nutri == nil ? ["Prospekttext"] : ["Prospekttext", "Open Food Facts (ODbL)"],
                 offCode: nutri == nil ? "" : "4311501000000", monthly: monthly)
    }

    // MARK: Sparen (Phase 12)

    static let nextOffers: [OfferDTO] = [
        offer(21, "lidl", "Hähnchenbrustfilet", "fleisch_fisch", 349, 499, 400, "g", 873, from: "2099-11-09", to: "2099-11-14"),
        offer(22, "aldi_sued", "Butter", "kuehlung", 139, 199, 250, "g", 556, from: "2099-11-09", to: "2099-11-14"),
        offer(23, "dm", "Shampoo Repair", "drogerie", 149, 239, 300, "ml", 497, from: "2099-11-09", to: "2099-11-14"),
        offer(24, "rewe", "Spaghetti", "vorrat", 79, 129, 500, "g", 158, from: "2099-11-09", to: "2099-11-14"),
    ]

    static let nextWeekDeals = [
        NextWeekDealDTO(name: "Hähnchenbrustfilet", itemId: 1, watchId: nil, offer: nextOffers[0], nowPriceCents: 499, nowChain: "rewe",
                        savingPct: 30),
        NextWeekDealDTO(name: "Shampoo Repair", itemId: nil, watchId: 1, offer: nextOffers[2], nowPriceCents: 179, nowChain: "dm",
                        savingPct: 17),
    ]

    static let stockups = [
        StockupDTO(offer: offers[6], packs: 6, weeks: 6, weeklyUse: 1, savingCents: 300, normalPriceCents: 199),
        StockupDTO(offer: offers[5], packs: 3, weeks: nil, weeklyUse: nil, savingCents: 180, normalPriceCents: 239),
    ]

    static func watch(_ id: Int, _ kind: String, _ label: String, brand: String = "", category: String = "", max: Int? = nil,
                      maxBase: Int? = nil, unit: String = "", lasts: Double? = nil, bought: String? = nil, empty: String? = nil,
                      hits: [OfferDTO] = []) -> WatchDTO {
        WatchDTO(id: id, kind: kind, label: label, brand: brand, ean: "", imageUrl: "", category: category, maxPriceCents: max,
                 maxBasePriceCents: maxBase, baseUnit: unit, chains: [], lastsWeeks: lasts, lastsWeeksSuggestion: lasts,
                 lastBought: bought, emptyOn: empty, hits: hits)
    }

    static let watches = [
        watch(1, "produkt", "Shampoo Repair", brand: "Balea", category: "drogerie", max: 199, lasts: 6, bought: "2026-10-20",
              empty: "2026-12-01", hits: [offers[5]]),
        watch(2, "produkt", "Skyr Natur", category: "kuehlung", hits: [offers[4]]),
        watch(3, "produkt", "Haferdrink Barista", brand: "Oatly", category: "kuehlung", max: 149),
        watch(4, "produkt", "Toilettenpapier 4-lagig", category: "haushalt", lasts: 3, bought: "2026-10-27", empty: "2026-11-17"),
        watch(5, "zutat", "Butter", max: 149),
        watch(6, "zutat", "Lachsfilet", maxBase: 1500, unit: "kg", hits: [offers[3]]),
    ]

    static let storeCombos = [
        StoreComboDTO(chains: ["rewe", "lidl"], totalCents: 3890, perStore: ["rewe": 1620, "lidl": 2270], savedCents: 230, unpriced: 1,
                      distanceKm: 2.4, extraKm: 1.2),
        StoreComboDTO(chains: ["lidl"], totalCents: 4120, perStore: ["lidl": 4120], savedCents: 0, unpriced: 1, distanceKm: 1.2, extraKm: 0),
        StoreComboDTO(chains: ["rewe"], totalCents: 4380, perStore: ["rewe": 4380], savedCents: 0, unpriced: 1, distanceKm: 0.6, extraKm: 0),
    ]

    static let budget = BudgetDTO(budgetCents: 6000, totalCents: 3820, restCents: 2180, state: "rest", over: nil)
    static let budgetOver = BudgetDTO(budgetCents: 3500, totalCents: 3820, restCents: -320, state: "over",
                                      over: .init(entryId: 12, day: 1, title: "Lachs-Bowl mit Avocado", costCents: 620, maxCostCents: 300))

    static let budgetIdeas = [
        BudgetIdeaDTO(kind: "dessert", title: "Skyr-Creme mit Beeren", costCents: 240, recipe: idea(401, "Skyr-Creme mit Beeren", 10, []).recipe),
        BudgetIdeaDTO(kind: "snack", title: "Ofen-Kichererbsen", costCents: 180, recipe: idea(402, "Ofen-Kichererbsen", 25, []).recipe),
        BudgetIdeaDTO(kind: "vorrat", title: "Basmatireis", costCents: 894, stockup: stockups[0]),
    ]

    static let eanProduct = EanProductDTO(ean: "4066447240962", found: true, name: "Repair Shampoo", brand: "Balea", imageUrl: "",
                                          nutriScore: nil)

    static func meal(_ day: Int, _ type: String, _ title: String, _ cost: Int, _ minutes: Int, _ ings: [IngredientDTO]) -> MealDTO {
        // Jona (Faktor 1,25) ist mittwochs mittags nicht zu Hause, Malina (1,0) isst immer mit
        let portions = [PortionDTO(memberId: 1, factor: 1.25), PortionDTO(memberId: 2, factor: 1)].filter { $0.memberId == 2 || !(day == 2 && type == "mittag") }
        return MealDTO(id: day * 10 + (type == "mittag" ? 1 : 2), day: day, mealType: type, costCents: cost, locked: day == 1 && type == "mittag", recipe: RecipeDTO(
            id: day * 10 + (type == "mittag" ? 1 : 2), title: title, description: "Schnell, würzig und mit Angeboten der Woche.",
            cuisine: "Indisch", mealType: type, servings: 2, prepMinutes: minutes, ingredients: ings,
            steps: ["Zwiebel würfeln und 5 Minuten glasig anbraten.", "Hähnchen dazugeben und 8–10 Min. rundum anbraten.",
                    "Tomaten und Gewürze zugeben, 15 Minuten köcheln.", "Mit Reis servieren."],
            imageUrl: "", stepImages: [photo("chef"), photo("pasta"), photo("bowl"), photo("table")], favorite: day == 1 && type == "mittag",
            nutrition: NutritionDTO(kcal: Double(380 + cost / 2), protein: Double(14 + minutes), carbs: 62, fat: 19, fiber: 7),
            composition: composition(ings.map { i in (i.name, i.unit == "stk" ? i.amount * 120 : i.amount) })),
            portions: portions, portionsTotal: portions.map(\.factor).reduce(0, +))
    }

    // MARK: Profile (48), Vorrat (60), Mitteilungen

    static let profiles = [
        ProfileDTO(memberId: 1, name: "Jona", emoji: "🧑‍🍳", goal: "proteinreich", kcal: 2500, proteinG: 140, allergies: [],
                   dislikes: ["Koriander"], lunchboxDays: [0, 2],
                   eats: ["fruehstueck": week, "mittag": [true, true, false, true, true, true, true], "abend": week, "dessert": week]),
        ProfileDTO(memberId: 2, name: "Malina", emoji: "🦊", goal: "ausgewogen", kcal: 1900, proteinG: 80, allergies: ["Laktose"],
                   dislikes: nil, lunchboxDays: [], eats: ["fruehstueck": week, "mittag": week, "abend": week, "dessert": week]),
    ]
    static let week = [Bool](repeating: true, count: 7)

    static let pantry: [PantryDTO] = [
        stock(1, "Feta", 200, "g", days: 2, location: "kuehlschrank"),
        stock(2, "Eier", 6, "stk", days: 12, location: "kuehlschrank"),
        stock(3, "Basmatireis", 500, "g", location: "vorrat"),
        stock(4, "Passierte Tomaten", 500, "g"),
        stock(5, "Spaghetti", 500, "g"),
        stock(6, "Öl", nil, "", basic: true),
        stock(7, "Pfeffer", 0, "", basic: true),
        stock(8, "Salz", nil, "", basic: true),
    ]

    static func stock(_ id: Int, _ name: String, _ amount: Double?, _ unit: String, days: Double? = nil, basic: Bool = false,
                      location: String? = nil) -> PantryDTO {
        PantryDTO(id: id, name: name, ingredientKey: name.lowercased(), amount: amount, unit: unit,
                  bestBefore: days.map { Date.now.addingTimeInterval($0 * 86400).formatted(PantryDTO.day) }, isBasic: basic,
                  source: "manual", updatedAt: "", location: location)
    }

    static let pushSettings = PushSettingsDTO(pushEnabled: true, planPromptEnabled: true, planPromptWeekday: 6, planPromptTime: "18:00",
                                              quietHours: .init(start: "22:00", end: "07:00"), lunchboxPush: "20:00")

    static func ing(_ name: String, _ amount: Double, _ unit: String = "g", offer: Int? = nil, pantry: Bool = false,
                    estimated: Bool? = nil) -> IngredientDTO {
        IngredientDTO(name: name, amount: amount, unit: unit, offerId: offer, inPantry: pantry, estimated: estimated)
    }

    /// Foto aus den App-Ressourcen als Datei-URL (Schritt-Bilder, Kamera-Vorschau im Demo).
    static func photo(_ name: String) -> String { Bundle.module.url(forResource: name, withExtension: "jpg")?.absoluteString ?? "" }

    // MARK: Import (5), Schritt-Bilder (9), Kühlschrank-Foto (69), Angebots-Nährwerte (2)

    static let importedRecipe = RecipeDTO(
        id: 102, title: "One-Pot-Pasta mit Feta", description: "Alles in einem Topf – fertig in 20 Minuten.", cuisine: "Italienisch",
        mealType: "abend", servings: 2, prepMinutes: 20,
        ingredients: [ing("Spaghetti", 250), ing("Kirschtomaten", 300, offer: 3), ing("Feta", 200, offer: 8),
                      ing("Knoblauch", 2, "stk", estimated: true), ing("Olivenöl", 2, "el", estimated: true), ing("Salz", 1, "prise", estimated: true)],
        steps: ["Spaghetti, Tomaten, Knoblauch und 500 ml Wasser in einen Topf geben.", "Aufkochen und 10 Minuten köcheln, dabei umrühren.",
                "Feta zerbröseln und unterheben.", "Mit Olivenöl, Salz und Basilikum servieren."],
        imageUrl: photo("pasta"), stepImages: [photo("pasta"), photo("bowl"), "", ""], source: "instagram",
        sourceUrl: "https://www.instagram.com/reel/C9xYz12AbCd/", sourceAuthor: "@koch_xy", tags: ["Pasta", "One-Pot"],
        nutrition: NutritionDTO(kcal: 640, protein: 24, carbs: 82, fat: 22, fiber: 6),
        composition: composition([("Spaghetti", 250), ("Kirschtomaten", 300), ("Feta", 200), ("Olivenöl", 20), ("Knoblauch", 10)]),
        avgStars: nil, lastCooked: nil, costPerServingCents: 180, offerShare: 0.2, ratings: [])

    static let pairedTokens = [PairedTokenDTO(id: 1, label: "Teilen-Erweiterung", createdAt: "2026-11-02T10:12:00")]

    static let offerNutrition = OfferNutritionDTO(
        status: "ok", food: "Chicken, broiler or fryers, breast, skinless, boneless, meat only, raw",
        per100g: NutritionDTO(kcal: 120, protein: 22.5, carbs: 0, fat: 2.6, fiber: 0),
        perPack: NutritionDTO(kcal: 480, protein: 90, carbs: 0, fat: 10.4, fiber: 0))

    static var fridgePhotos: [UIImage] {
        ["chef", "bowl"].compactMap { name in Bundle.module.url(forResource: name, withExtension: "jpg").flatMap { u in UIImage(contentsOfFile: u.path) } }
    }

    static func scan(_ name: String, _ amount: Double?, _ unit: String, _ category: String, _ confidence: String, days: Double?,
                     location: String = "kuehlschrank") -> ScanItemDTO {
        ScanItemDTO(name: name, amount: amount, unit: unit, location: location, category: category, confidence: confidence,
                    bestBefore: days.map { d in Date.now.addingTimeInterval(d * 86400).formatted(PantryDTO.day) }, checked: confidence != "niedrig")
    }

    static let scanItems = [
        scan("Milch", 1000, "ml", "kuehlung", "hoch", days: 5),
        scan("Eier", 6, "stk", "kuehlung", "hoch", days: 14),
        scan("Paprika rot", 2, "stk", "obst_gemuese", "hoch", days: 6),
        scan("Gouda", 250, "g", "kuehlung", "mittel", days: 12),
        scan("Joghurt", 500, "g", "kuehlung", "hoch", days: 4),
        scan("Frühlingszwiebeln", 1, "stk", "obst_gemuese", "mittel", days: 3),
        scan("Pesto", nil, "", "vorrat", "niedrig", days: nil),
    ]

    static func idea(_ id: Int, _ title: String, _ minutes: Int, _ missing: [CookIdeaDTO.Missing]) -> CookIdeaDTO {
        CookIdeaDTO(recipe: RecipeDTO(id: id, title: title, description: "", cuisine: "Deutsch", mealType: "abend", servings: 2,
                                      prepMinutes: minutes, ingredients: [ing("Eier", 4, "stk")], steps: ["Alles anbraten."], imageUrl: ""),
                    missing: missing)
    }

    static let cookIdeas = [
        idea(201, "Rührei mit Paprika & Gouda", 15, []),
        idea(202, "Frittata mit Frühlingszwiebeln", 25, [.init(name: "Sahne", amount: 100, unit: "ml")]),
        idea(203, "Joghurt-Pfannkuchen", 20, [.init(name: "Mehl", amount: 200, unit: "g"), .init(name: "Zitrone", amount: 1, unit: "stk")]),
    ]

    static let plan: PlanDTO = {
        var p = basePlan
        p.entries[2].rests = [RestBadgeDTO(name: "Basmatireis", fromDay: 0)]  // Tikka nutzt den Reis-Rest vom Montag (19)
        p.entries[3].guests = 2  // Lachs-Bowl für 2 Gäste (15)
        p.entries[3].portionsTotal += 2
        var lunch = meal(1, "lunchbox", "Couscous-Salat to go", 180, 15, [ing("Couscous", 120), ing("Rispentomaten", 150, offer: 3),
                                                                           ing("Feta", 50, offer: 8)])
        lunch.id = 13
        lunch.recipe.id = 13
        lunch.portions = [PortionDTO(memberId: 1, factor: 1.25)]  // nur Jona hat dienstags Lunchbox (24)
        lunch.portionsTotal = 1.25
        p.entries.append(lunch)
        p.variety = VarietyCheckDTO(ok: false, issues: ["2× Pasta", "nur 1 vegetarischer Tag"])
        p.leftovers = LeftoversDTO(planned: 3, left: [LeftoverDTO(name: "Sahne", amount: 100, unit: "ml", untilDay: 3,
                                                                  suggestion: "Bis Do verbrauchen, z.B. im Frühstück, als Snack oder in einer Soße")])
        return p
    }()

    private static let basePlan = PlanDTO(id: 1, week: "2026-W45", totalCents: 3820, savedCents: 1240, entries: [
        meal(0, "mittag", "Shakshuka mit Feta", 320, 25, [ing("Eier", 4, "stk"), ing("Rispentomaten", 400, offer: 3), ing("Feta", 100, offer: 8)]),
        meal(0, "abend", "Linsen-Dal mit Reis", 240, 30, [ing("Rote Linsen", 250), ing("Basmatireis", 160, offer: 7), ing("Currypulver", 2, "g", pantry: true)]),
        meal(1, "mittag", "Chicken Tikka Masala", 490, 35, [ing("Hähnchenbrustfilet", 400, offer: 1), ing("Basmatireis", 160, offer: 7),
                                                           ing("Passierte Tomaten", 500), ing("Joghurt", 150), ing("Zwiebel", 1, "stk"),
                                                           ing("Garam Masala", 2, "g", pantry: true)]),
        meal(1, "abend", "Lachs-Bowl mit Avocado", 620, 20, [ing("Lachsfilet", 250, offer: 4), ing("Avocado", 1, "stk", offer: 2), ing("Basmatireis", 160, offer: 7)]),
        meal(2, "mittag", "Pasta al Pomodoro", 210, 15, [ing("Spaghetti", 250), ing("Rispentomaten", 300, offer: 3)]),
        meal(3, "mittag", "Ofengemüse mit Feta", 380, 30, [ing("Paprika", 2, "stk"), ing("Feta", 100, offer: 8)]),
    ])

    // MARK: Clever planen (Phase 11), Ersatz (7)

    static func noMood(page: Int) -> [CookIdeaDTO] {
        let all = [idea(301, "Rührei-Wrap mit Feta", 10, []), idea(302, "Tomaten-Reis-Pfanne", 15, []), idea(303, "Pasta aglio e olio", 12, []),
                   idea(304, "Shakshuka light", 15, []), idea(305, "Feta-Omelett", 8, []), idea(306, "Joghurt-Bowl mit Ei", 5, [])]
        return Array(all.dropFirst(page * 3).prefix(3))
    }

    static let entryLeftovers = [
        EntryLeftoverDTO(name: "Joghurt", amount: 350, unit: "g", bestBefore: Date.now.addingTimeInterval(3 * 86400).formatted(PantryDTO.day)),
        EntryLeftoverDTO(name: "Hähnchenbrustfilet", amount: 150, unit: "g", bestBefore: Date.now.addingTimeInterval(1 * 86400).formatted(PantryDTO.day)),
        EntryLeftoverDTO(name: "Basmatireis", amount: 180, unit: "g", bestBefore: nil),
    ]

    static let christmas = SpecialDTO(key: "weihnachten", name: "Weihnachten", emoji: "🎄", date: "2026-12-24", daysUntil: 12,
                                      template: "festtagsmenue", templateName: "Festtagsmenü", running: false,
                                      text: "🎄 Weihnachten in 12 Tagen – Menü planen?")
    static let specials = SpecialsDTO(banner: christmas, specials: [
        christmas,
        SpecialDTO(key: "plaetzchen", name: "Plätzchenzeit", emoji: "🍪", date: "2026-12-01", daysUntil: 0, template: "plaetzchen",
                   templateName: "Plätzchen-Back-Plan", running: true),
    ])
    static let generator = GeneratorDTO(week: 46, topOffers: [offers[0], offers[3], offers[7]], banner: christmas)

    static let weeklyBasics = [
        WeeklyBasicDTO(id: 1, name: "Haferflocken", amount: 1000, unit: "g"),
        WeeklyBasicDTO(id: 2, name: "Joghurt", amount: 1000, unit: "g"),
        WeeklyBasicDTO(id: 3, name: "Bananen", amount: 6, unit: "stk"),
        WeeklyBasicDTO(id: 4, name: "Brot", amount: nil, unit: ""),
        WeeklyBasicDTO(id: 5, name: "Milch", amount: 2000, unit: "ml"),
    ]

    static let substitutes: SubstitutesDTO = {
        func sub(_ name: String, _ amount: Double, _ unit: String, pantry: Bool = false, offer: Int? = nil) -> SubstitutesDTO.Ingredient {
            let o = offer.flatMap { id in offers.first { x in x.id == id } }
            return .init(name: name, amount: amount, unit: unit, inPantry: pantry,
                         offer: o.map { x in .init(id: x.id, chain: x.chain, priceCents: x.priceCents) })
        }
        return SubstitutesDTO(ingredient: .init(name: "Joghurt", amount: 150, unit: "g"), source: "tabelle", options: [
            .init(note: "etwas dicker und eiweißreicher – mit 2 EL Wasser glatt rühren", ingredients: [sub("Skyr", 130, "g", offer: 5), sub("Wasser", 20, "ml", pantry: true)]),
            .init(note: "milder und cremiger, ähnliche Säure", ingredients: [sub("Saure Sahne", 150, "g")]),
            .init(note: "laktosefrei, leicht süßlich – passt gut zu Curry", ingredients: [sub("Kokosmilch", 120, "ml", pantry: true)]),
        ])
    }()

    // MARK: Meine Rezepte (3), Nährwerte (2)

    static func composition(_ parts: [(String, Double)]) -> [CompositionItem] {
        let total = max(parts.map(\.1).reduce(0, +), 1)
        return parts.map { p in CompositionItem(name: p.0, grams: p.1 / 2, share: p.1 / total) }
    }

    static func card(_ id: Int, _ title: String, _ source: String, fav: Bool, stars: Double?, cooked: String?, cost: Int,
                     share: Double) -> RecipeCard {
        RecipeCard(id: id, title: title, imageUrl: "", cuisine: "", mealType: "abend", prepMinutes: 30, servings: 2, source: source,
                   sourceAuthor: source == "instagram" ? "koch_xy" : "", favorite: fav, avgStars: stars, lastCooked: cooked,
                   costPerServingCents: cost, offerShare: share)
    }

    static let cards = [
        card(100, "Ofen-Lachs mit Kartoffeln", "user", fav: true, stars: 4.5, cooked: "2026-10-29T19:10:00", cost: 310, share: 0.55),
        card(12, "Chicken Tikka Masala", "ai", fav: true, stars: 5, cooked: "2026-10-27T18:40:00", cost: 245, share: 0.62),
        card(102, "One-Pot-Pasta mit Feta", "instagram", fav: false, stars: nil, cooked: nil, cost: 180, share: 0.2),
        card(103, "Omas Linsensuppe", "user", fav: false, stars: 4, cooked: "2026-10-20T12:30:00", cost: 120, share: 0.1),
        card(1, "Shakshuka mit Feta", "ai", fav: true, stars: 3.5, cooked: nil, cost: 160, share: 0.45),
        card(105, "Gnocchi-Pfanne", "web", fav: false, stars: nil, cooked: nil, cost: 210, share: 0),
    ]

    static let savedRecipe = RecipeDTO(
        id: 100, title: "Ofen-Lachs mit Kartoffeln", description: "Unser Sonntagsessen – alles auf einem Blech.", cuisine: "Deutsch",
        mealType: "abend", servings: 2, prepMinutes: 40,
        ingredients: [ing("Lachsfilet", 250, offer: 4), ing("Kartoffeln", 600), ing("Brokkoli", 300), ing("Zitrone", 1, "stk"),
                      ing("Olivenöl", 2, "el"), ing("Salz", 1, "prise")],
        steps: ["Ofen auf 200 °C vorheizen.", "Kartoffeln vierteln, mit Öl mischen und 20 Minuten backen.",
                "Lachs und Brokkoli dazulegen, 15 Minuten weiterbacken.", "Mit Zitrone servieren."],
        imageUrl: "", source: "user", tags: ["Ofen", "Sonntag"], favorite: true,
        nutrition: NutritionDTO(kcal: 610, protein: 38, carbs: 52, fat: 26, fiber: 8),
        composition: composition([("Kartoffeln", 600), ("Brokkoli", 300), ("Lachsfilet", 250), ("Zitrone", 60), ("Olivenöl", 20), ("Salz", 1)]),
        avgStars: 4.5, lastCooked: "2026-10-29T19:10:00", costPerServingCents: 310, offerShare: 0.55,
        ratings: [RatingDTO(id: 1, memberId: 1, memberName: "Jona", stars: 5, again: "bald", note: "Mit mehr Zitrone noch besser.",
                            cookedAt: "2026-10-29T19:10:00"),
                  RatingDTO(id: 2, memberId: 2, memberName: "Malina", stars: 4, again: "irgendwann", note: "", cookedAt: "2026-10-12T18:45:00")])

    static func dayValues(_ d: Int, _ jona: [Double], _ malina: [Double], complete: Bool = true) -> PlanNutritionDTO.Day {
        PlanNutritionDTO.Day(day: d, members: [
            PlanNutritionDTO.MemberDay(memberId: 1, kcal: jona[0], protein: jona[1], carbs: jona[2], fat: jona[3], fiber: jona[4], complete: true),
            PlanNutritionDTO.MemberDay(memberId: 2, kcal: malina[0], protein: malina[1], carbs: malina[2], fat: malina[3], fiber: malina[4],
                                       complete: complete)])
    }

    static let nutrition = PlanNutritionDTO(
        members: [PlanNutritionDTO.Member(memberId: 1, name: "Jona", emoji: "🧑‍🍳", kcalGoal: 2500, proteinGoal: 140, avgKcal: 1980, avgProtein: 104),
                  PlanNutritionDTO.Member(memberId: 2, name: "Malina", emoji: "🦊", kcalGoal: 1900, proteinGoal: 80, avgKcal: 1520, avgProtein: 71)],
        days: [dayValues(0, [1650, 92, 180, 60, 22], [1320, 70, 150, 48, 18]),
               dayValues(1, [2180, 128, 230, 78, 28], [1740, 98, 190, 62, 22]),
               dayValues(2, [900, 40, 110, 30, 12], [1010, 44, 120, 33, 12]),
               dayValues(3, [1100, 64, 120, 41, 15], [880, 51, 95, 30, 11], complete: false)])

    static let householdList = ListDTO(id: 1, name: "Haushalt", kind: "household", shareUrl: nil, items: [
        item(1, "Hähnchenbrustfilet", 400, "g", "rewe", 1),
        item(2, "Basmatireis", 480, "g", "rewe", 7, checked: true, by: "Malina"),
        item(3, "Rispentomaten", 700, "g", "lidl", 3),
        item(4, "Feta", 200, "g", "lidl", 8),
        item(5, "Lachsfilet", 250, "g", "lidl", 4),
        item(6, "Avocado", 1, "stk", "aldi_sued", 2),
        item(7, "Spülmittel", nil, "", "", nil, source: "manual", added: "Malina"),
        item(8, "Basmatireis", 6, "stk", "rewe", 7, source: "stockup", added: "Jona"),  // Vorratskauf (31)
        item(9, "Toilettenpapier", nil, "", "dm", nil, source: "rhythm"),  // bald leer (58)
        item(10, "Butter", 1, "stk", "aldi_sued", 22, source: "manual", added: "Jona", next: true),  // Nächste Woche (30)
    ])

    static let lists = [
        ListSummaryDTO(id: 1, name: "Haushalt", kind: "household", shareUrl: nil, openCount: 6, totalCount: 7),
        ListSummaryDTO(id: 2, name: "Grillparty", kind: "oneoff", shareUrl: "http://192.168.0.224:8000/l/abc", openCount: 5, totalCount: 8),
    ]

    static func item(_ id: Int, _ name: String, _ amount: Double?, _ unit: String, _ chain: String, _ offer: Int?,
                     checked: Bool = false, by: String = "", source: String = "plan", added: String = "",
                     next: Bool = false) -> ListItemDTO {
        ListItemDTO(id: id, name: name, amount: amount, unit: unit, chain: chain, offerId: offer, checked: checked,
                    addedBy: added, checkedBy: by, source: source, deferWeek: next ? "2026-W46" : nil, nextWeek: next)
    }
}
