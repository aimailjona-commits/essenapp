import Foundation

/// Demo-Modus für Screenshots im Simulator (CI): App starten mit `-demoScreen <name>`.
/// Namen: onboarding, start, quick, generator, offers, plan, recipe, shopping, list, settings, empty
enum Demo {
    static let screen: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-demoScreen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    static let household = HouseholdDTO(
        id: 1, name: "Zuhause", plz: "50667", persons: 2, diet: "alles", allergies: ["Laktose"], excludedIngredients: [],
        cuisines: [], mealTypes: ["mittag", "abend"], planDays: [0, 1, 2, 3, 4], budgetFoodWeekCents: 6000,
        budgetDrugstoreCents: nil, nutritionGoal: "ausgewogen", maxCookMinutes: 45,
        stores: [StoreDTO(chain: "rewe", storeRef: "1763159"), StoreDTO(chain: "lidl"), StoreDTO(chain: "aldi_sued"), StoreDTO(chain: "dm")])

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
        MealDTO(day: day, mealType: type, costCents: cost, locked: false, recipe: RecipeDTO(
            id: day * 10 + (type == "mittag" ? 1 : 2), title: title, description: "Schnell, würzig und mit Angeboten der Woche.",
            cuisine: "Indisch", mealType: type, servings: 2, prepMinutes: minutes, ingredients: ings,
            steps: ["Zwiebel würfeln und anbraten.", "Hähnchen dazugeben und rundum anbraten.",
                    "Tomaten und Gewürze zugeben, 15 Minuten köcheln.", "Mit Reis servieren."],
            imageUrl: ""))
    }

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
}
