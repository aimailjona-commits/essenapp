import Foundation

/// Demo-Modus für Screenshots im Simulator (CI): App starten mit `-demoScreen <name>`.
/// Namen: onboarding, start, quick, generator, generating, offers, offer, plan, recipe, shopping, list, pantry, settings, profile,
/// notifications, stores, empty, cooking (Kochmodus Schritt 2 mit Timer), sharecard (Bildkarte),
/// recipes (Meine Rezepte), myrecipe (eigenes Rezept mit Bewertungen + Blüte), recipeform (Rezept-Formular, Seite Zutaten)
enum Demo {
    static let screen: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    static let household = HouseholdDTO(
        id: 1, name: "Zuhause", plz: "50667", persons: 2, diet: "alles", allergies: ["Laktose"], excludedIngredients: [],
        cuisines: [], mealTypes: ["mittag", "abend"], planDays: [0, 1, 2, 3, 4], budgetFoodWeekCents: 6000,
        budgetDrugstoreCents: nil, nutritionGoal: "ausgewogen", maxCookMinutes: 45, radiusKm: 3, lat: 50.9375, lng: 6.9603,
        stores: nearby.prefix(4).map { StoreDTO(chain: $0.chain, storeName: $0.name, osmId: $0.osmId, lat: $0.lat, lng: $0.lng, address: $0.address) })

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
        offer(1, "rewe", "Hähnchenbrustfilet", "fleisch_fisch", 399, 599, 400, "g", 998),
        offer(2, "aldi_sued", "Avocado, essreif", "obst_gemuese", 79, 119, 1, "stk", 79),
        offer(3, "lidl", "Rispentomaten", "obst_gemuese", 199, nil, 500, "g", 398),
        offer(4, "lidl", "Lachsfilet", "fleisch_fisch", 349, 499, 250, "g", 1396),
        offer(5, "aldi_sued", "Skyr Natur", "kuehlung", 129, 159, 450, "g", 287),
        offer(6, "dm", "Shampoo Repair", "drogerie", 179, 239, 300, "ml", 597),
        offer(7, "rewe", "Basmatireis", "vorrat", 149, 199, 500, "g", 298),
        offer(8, "lidl", "Feta", "kuehlung", 99, 139, 200, "g", 495),
    ]

    static func offer(_ id: Int, _ chain: String, _ title: String, _ category: String, _ price: Int, _ regular: Int?,
                      _ amount: Double, _ unit: String, _ base: Int) -> OfferDTO {
        OfferDTO(id: id, chain: chain, title: title, brand: "", category: category, priceCents: price, regularPriceCents: regular,
                 amount: amount, unit: unit, basePriceCents: base, validFrom: "2026-11-02", validTo: "2026-11-07", imageUrl: "")
    }

    static func meal(_ day: Int, _ type: String, _ title: String, _ cost: Int, _ minutes: Int, _ ings: [IngredientDTO]) -> MealDTO {
        // Jona (Faktor 1,25) ist mittwochs mittags nicht zu Hause, Malina (1,0) isst immer mit
        let portions = [PortionDTO(memberId: 1, factor: 1.25), PortionDTO(memberId: 2, factor: 1)].filter { $0.memberId == 2 || !(day == 2 && type == "mittag") }
        return MealDTO(id: day * 10 + (type == "mittag" ? 1 : 2), day: day, mealType: type, costCents: cost, locked: day == 1 && type == "mittag", recipe: RecipeDTO(
            id: day * 10 + (type == "mittag" ? 1 : 2), title: title, description: "Schnell, würzig und mit Angeboten der Woche.",
            cuisine: "Indisch", mealType: type, servings: 2, prepMinutes: minutes, ingredients: ings,
            steps: ["Zwiebel würfeln und 5 Minuten glasig anbraten.", "Hähnchen dazugeben und 8–10 Min. rundum anbraten.",
                    "Tomaten und Gewürze zugeben, 15 Minuten köcheln.", "Mit Reis servieren."],
            imageUrl: "", favorite: day == 1 && type == "mittag",
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
        stock(1, "Feta", 200, "g", days: 2),
        stock(2, "Eier", 6, "stk", days: 12),
        stock(3, "Basmatireis", 500, "g"),
        stock(4, "Passierte Tomaten", 500, "g"),
        stock(5, "Spaghetti", 500, "g"),
        stock(6, "Öl", nil, "", basic: true),
        stock(7, "Pfeffer", 0, "", basic: true),
        stock(8, "Salz", nil, "", basic: true),
    ]

    static func stock(_ id: Int, _ name: String, _ amount: Double?, _ unit: String, days: Double? = nil, basic: Bool = false) -> PantryDTO {
        PantryDTO(id: id, name: name, ingredientKey: name.lowercased(), amount: amount, unit: unit,
                  bestBefore: days.map { Date.now.addingTimeInterval($0 * 86400).formatted(PantryDTO.day) }, isBasic: basic,
                  source: "manual", updatedAt: "")
    }

    static let pushSettings = PushSettingsDTO(pushEnabled: true, planPromptEnabled: true, planPromptWeekday: 6, planPromptTime: "18:00",
                                              quietHours: .init(start: "22:00", end: "07:00"))

    static func ing(_ name: String, _ amount: Double, _ unit: String = "g", offer: Int? = nil, pantry: Bool = false) -> IngredientDTO {
        IngredientDTO(name: name, amount: amount, unit: unit, offerId: offer, inPantry: pantry)
    }

    static let plan = PlanDTO(id: 1, week: "2026-W45", totalCents: 3820, savedCents: 1240, entries: [
        meal(0, "mittag", "Shakshuka mit Feta", 320, 25, [ing("Eier", 4, "stk"), ing("Rispentomaten", 400, offer: 3), ing("Feta", 100, offer: 8)]),
        meal(0, "abend", "Linsen-Dal mit Reis", 240, 30, [ing("Rote Linsen", 250), ing("Basmatireis", 160, offer: 7), ing("Currypulver", 2, "g", pantry: true)]),
        meal(1, "mittag", "Chicken Tikka Masala", 490, 35, [ing("Hähnchenbrustfilet", 400, offer: 1), ing("Basmatireis", 160, offer: 7),
                                                           ing("Passierte Tomaten", 500), ing("Joghurt", 150), ing("Zwiebel", 1, "stk"),
                                                           ing("Garam Masala", 2, "g", pantry: true)]),
        meal(1, "abend", "Lachs-Bowl mit Avocado", 620, 20, [ing("Lachsfilet", 250, offer: 4), ing("Avocado", 1, "stk", offer: 2), ing("Basmatireis", 160, offer: 7)]),
        meal(2, "mittag", "Pasta al Pomodoro", 210, 15, [ing("Spaghetti", 250), ing("Rispentomaten", 300, offer: 3)]),
        meal(3, "mittag", "Ofengemüse mit Feta", 380, 30, [ing("Paprika", 2, "stk"), ing("Feta", 100, offer: 8)]),
    ])

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
    ])

    static let lists = [
        ListSummaryDTO(id: 1, name: "Haushalt", kind: "household", shareUrl: nil, openCount: 6, totalCount: 7),
        ListSummaryDTO(id: 2, name: "Grillparty", kind: "oneoff", shareUrl: "http://192.168.0.224:8000/l/abc", openCount: 5, totalCount: 8),
    ]

    static func item(_ id: Int, _ name: String, _ amount: Double?, _ unit: String, _ chain: String, _ offer: Int?,
                     checked: Bool = false, by: String = "", source: String = "plan", added: String = "") -> ListItemDTO {
        ListItemDTO(id: id, name: name, amount: amount, unit: unit, chain: chain, offerId: offer, checked: checked,
                    addedBy: added, checkedBy: by, source: source)
    }
}
