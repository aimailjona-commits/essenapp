import Foundation

// Demo-Daten Phase 13 (Bonus & Laden) und Phase 14 (Motivation & Teilen); Screens siehe Demo.swift.

extension Demo {
    static func day(_ offset: Int) -> String { Date.now.addingTimeInterval(Double(offset) * 86400).formatted(PantryDTO.day) }

    static func coupon(_ id: Int, _ program: String, _ partner: String, _ chain: String, _ product: String, _ benefit: String,
                       multiplier: Int? = nil, bonus: Int? = nil, percent: Int? = nil, minSpend: Int? = nil, days: Int?,
                       code: String = "", type: String = "", category: String = "") -> CouponDTO {
        CouponDTO(id: id, partner: partner, program: program, chain: chain, product: product, category: category, benefit: benefit,
                  multiplier: multiplier, bonusCents: bonus, percent: percent, minSpendCents: minSpend, validUntil: days.map(day),
                  code: code, codeType: type, source: code.isEmpty ? "foto" : "barcode",
                  badge: multiplier.map { m in "🎟 \(m)fach" } ?? bonus.map { b in "🎟 \(euro(b))" } ?? percent.map { p in "🎟 −\(p) %" } ?? "🎟 Coupon",
                  expired: (days ?? 0) < 0, daysLeft: days)
    }

    static let coupons = [
        coupon(1, "payback", "REWE", "rewe", "Kaffee", "10fach Punkte", multiplier: 10, days: 4, code: "PB2611KAFFEE10", type: "code128"),
        coupon(2, "rewe_bonus", "REWE", "rewe", "Basmatireis", "0,50 € Bonus", bonus: 50, days: 1, code: "4006381333931", type: "ean13"),
        coupon(3, "dm", "dm", "dm", "Balea Shampoo", "20 % Rabatt", percent: 20, days: 12, code: "https://dm.de/c/8F3K2", type: "qr",
               category: "drogerie"),
        coupon(4, "payback", "Aral", "", "", "5fach Punkte", multiplier: 5, minSpend: 2000, days: nil),
        coupon(5, "rossmann", "Rossmann", "rossmann", "", "10 % auf alles", percent: 10, minSpend: 1000, days: -3, code: "96385074",
               type: "ean8"),
    ]

    static let couponScan = CouponIn(partner: "REWE", program: "payback", chain: "rewe", product: "Kaffee", category: "vorrat",
                                     benefit: "10fach Punkte auf Kaffee", multiplier: 10, minSpendCents: 200, validUntil: day(6), source: "foto")

    static let bonus = [
        BonusAccountDTO(program: "payback", name: "Payback", unit: "punkte", balance: 1240, valueCents: 1240, earnedMonthCents: 180),
        BonusAccountDTO(program: "rewe_bonus", name: "Rewe Bonus", unit: "cent", balance: 850, valueCents: 850, earnedMonthCents: 230),
    ]

    static func purchase(_ id: Int, _ name: String, _ chain: String, _ category: String, _ price: Int, _ saved: Int, _ date: String,
                         estimated: Bool = false) -> SpendingDTO.Purchase {
        SpendingDTO.Purchase(id: id, name: name, amount: nil, unit: "", chain: chain, category: category, priceCents: price,
                             savedCents: saved, estimated: estimated, boughtAt: date + "T18:20:00", boughtBy: "Jona")
    }

    static func spending(_ month: String) -> SpendingDTO {
        let top = [purchase(1, "Lachsfilet", "lidl", "fleisch_fisch", 1396, 400, "\(month)-03"),
                   purchase(2, "Hähnchenbrustfilet", "rewe", "fleisch_fisch", 998, 400, "\(month)-04"),
                   purchase(3, "Basmatireis", "rewe", "vorrat", 894, 300, "\(month)-04"),
                   purchase(4, "Waschmittel", "dm", "haushalt", 795, 0, "\(month)-02", estimated: true),
                   purchase(5, "Feta", "lidl", "kuehlung", 495, 160, "\(month)-03")]
        // weitere Einkäufe über den Monat verteilt (Ersparnis S11: Wochenbalken, Verlauf)
        let more = [("09", "rewe", 380), ("11", "lidl", 510), ("16", "rewe", 290), ("19", "lidl", 640), ("23", "rewe", 470),
                    ("26", "lidl", 820), ("30", "rewe", 560)].enumerated().map { i, x in
            purchase(10 + i, "Einkauf", x.1, "vorrat", 1490, x.2, "\(month)-\(x.0)")
        }
        return SpendingDTO(
            month: month, totalCents: 18240, estimatedCents: 1260, budgetCents: 25714, savedCents: 2340, bonusCents: 410,
            weeks: [.init(week: "2026-W44", totalCents: 2140), .init(week: "2026-W45", totalCents: 6890), .init(week: "2026-W46", totalCents: 5120),
                    .init(week: "2026-W47", totalCents: 4090), .init(week: "2026-W48", totalCents: 0), .init(week: "2026-W49", totalCents: 0)],
            stores: [.init(chain: "rewe", totalCents: 7820), .init(chain: "lidl", totalCents: 5210), .init(chain: "aldi_sued", totalCents: 2990),
                     .init(chain: "dm", totalCents: 1620), .init(chain: "", totalCents: 600)],
            categories: [.init(category: "fleisch_fisch", totalCents: 5400), .init(category: "obst_gemuese", totalCents: 3900),
                         .init(category: "kuehlung", totalCents: 3600), .init(category: "vorrat", totalCents: 2800),
                         .init(category: "drogerie", totalCents: 1620), .init(category: "haushalt", totalCents: 920)],
            top: top, prevTotalCents: 16800, changePct: 8.6, items: top + more)
    }

    static func ach(_ key: String, _ group: String, _ emoji: String, _ title: String, _ target: Int, _ progress: Double, _ unit: String,
                    _ unlocked: String? = nil) -> AchievementDTO {
        AchievementDTO(key: key, group: group, emoji: emoji, title: title, target: target, progress: min(progress, Double(target)), unit: unit,
                       unlockedAt: unlocked.map { u in u + "T03:00:00" }, new: false)
    }

    static let achievements: [AchievementDTO] = [
        ach("gespart_10", "sparen", "💰", "10 € gespart", 1000, 3410, "cent", "2026-10-12"),
        ach("gespart_50", "sparen", "💰", "50 € gespart", 5000, 3410, "cent"),
        ach("gespart_100", "sparen", "💰", "100 € gespart", 10000, 3410, "cent"),
        ach("gespart_250", "sparen", "💰", "250 € gespart", 25000, 3410, "cent"),
        ach("gespart_500", "sparen", "💰", "500 € gespart", 50000, 3410, "cent"),
        ach("gespart_1000", "sparen", "💰", "1.000 € gespart", 100000, 3410, "cent"),
        ach("budget_1", "sparen", "🎯", "Budget-Wächter: 1 Woche in Folge im Budget", 1, 2, "wochen", "2026-10-26"),
        ach("budget_4", "sparen", "🎯", "Budget-Wächter: 4 Wochen in Folge im Budget", 4, 2, "wochen"),
        ach("budget_12", "sparen", "🎯", "Budget-Wächter: 12 Wochen in Folge im Budget", 12, 2, "wochen"),
        ach("bestpreis_10", "sparen", "🔥", "Bestpreis-Jäger: 10 Bestpreis-Angebote gekauft", 10, 10, "angebote", "2026-11-02"),
        ach("bestpreis_50", "sparen", "🔥", "Bestpreis-Jäger: 50 Bestpreis-Angebote gekauft", 50, 10, "angebote"),
        ach("vorrat_5", "sparen", "🏦", "Vorratsprofi: 5 Vorratskauf-Tipps genutzt", 5, 3, "tipps"),
        ach("protein_3", "gesundheit", "💪", "Proteinziel an 3 Tagen erreicht", 3, 5, "tage", "2026-10-29"),
        ach("protein_7", "gesundheit", "💪", "Proteinziel an 7 Tagen erreicht", 7, 5, "tage"),
        ach("protein_30", "gesundheit", "💪", "Proteinziel an 30 Tagen erreicht", 30, 5, "tage"),
        ach("pflanzen_15", "gesundheit", "🥦", "Pflanzenvielfalt: 15 verschiedene Pflanzen in einer Woche", 15, 18, "pflanzen", "2026-11-01"),
        ach("pflanzen_30", "gesundheit", "🥦", "Pflanzenvielfalt: 30 verschiedene Pflanzen in einer Woche", 30, 18, "pflanzen"),
        ach("ausgewogen_7", "gesundheit", "⚖️", "Ausgewogen: 7 Tage kcal-Ziel ±10 %", 7, 4, "tage"),
    ]

    /// Vollbild-Moment (Demo `unlock`): zwei frisch freigeschaltete.
    static let unlocked: [AchievementDTO] = [achievements[9], achievements[15]].map { a in
        var x = a
        x.new = true
        return x
    }

    static let review = WeekReviewDTO(
        week: "2026-W45", kw: 45, start: "2026-11-02", end: "2026-11-08",
        cooking: .init(cooked: 5, planned: 9, favorite: .init(recipeId: 12, title: "Chicken Tikka Masala", imageUrl: photo("bowl"), stars: 5)),
        money: .init(spentCents: 6890, estimatedCents: 420, savedCents: 1240, bonusCents: 210, budgetCents: 6000, budgetOk: false),
        health: [.init(memberId: 1, name: "Jona", emoji: "🧑‍🍳", avgKcal: 2310, kcalGoal: 2500, avgProtein: 128, proteinGoal: 140, plants: 18),
                 .init(memberId: 2, name: "Malina", emoji: "🦊", avgKcal: 1720, kcalGoal: 1900, avgProtein: 74, proteinGoal: 80, plants: 16)],
        pantry: .init(restsUsed: 3, restsLeft: 1, thrownAway: nil),
        achievements: unlocked.map { a in
            var x = a
            x.new = false
            x.memberId = a.group == "sparen" ? 0 : 1
            return x
        },
        nextWeek: [.init(offerId: 21, title: "Hähnchenbrustfilet", chain: "lidl", imageUrl: "", priceCents: 349, regularPriceCents: 499, savingPct: 30),
                   .init(offerId: 22, title: "Butter", chain: "aldi_sued", imageUrl: "", priceCents: 139, regularPriceCents: 199, savingPct: 30),
                   .init(offerId: 24, title: "Spaghetti", chain: "rewe", imageUrl: "", priceCents: 79, regularPriceCents: 129, savingPct: 39)])

    static let reviews = [
        ReviewSummaryDTO(week: "2026-W45", kw: 45, createdAt: "2026-11-08T19:00:00", spentCents: 6890, cooked: 5),
        ReviewSummaryDTO(week: "2026-W44", kw: 44, createdAt: "2026-11-01T19:00:00", spentCents: 5420, cooked: 6),
        ReviewSummaryDTO(week: "2026-W43", kw: 43, createdAt: "2026-10-25T19:00:00", spentCents: 6130, cooked: 4),
    ]

    static let recipeShare = RecipeShareDTO(code: "k3m9x2qa", url: "http://192.168.0.224:8000/r/k3m9x2qa",
                                            appUrl: "essenapp://import-recipe/k3m9x2qa")

    static let sharedRecipe = SharedRecipeDTO(
        code: "k3m9x2qa", title: "Omas Linsensuppe", description: "Wärmt von innen – mit Würstchen oder ohne.", imageUrl: photo("bowl"),
        servings: 4, prepMinutes: 45,
        ingredients: [ing("Tellerlinsen", 300), ing("Kartoffeln", 400), ing("Karotten", 2, "stk"), ing("Lauch", 1, "stk"),
                      ing("Gemüsebrühe", 1500, "ml"), ing("Essig", 2, "el")],
        steps: ["Gemüse würfeln.", "Mit Linsen und Brühe 30 Minuten köcheln.", "Mit Essig abschmecken."], fromHousehold: "Familie Müller")
}
