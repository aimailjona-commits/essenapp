import SwiftUI

/// S1 Start.
struct StartView: View {
    @Environment(AppStore.self) private var store
    @Binding var showGenerator: Bool
    @State private var search = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Spacer()
                    NavigationLink { SettingsView() } label: {
                        Text("J").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(Color(hex: 0x4A6B3A), in: Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 3)).softShadow()
                    }
                    .accessibilityLabel("Einstellungen")
                }
                DisplayHeader(line1: "Was kochen wir", line2: "diese Woche?")
                SearchField(text: $search, placeholder: "Gericht oder Angebot suchen")

                if let error = store.error, store.plan == nil {
                    ErrorState(message: error) { Task { await store.loadAll() } }
                } else if store.generating && store.plan == nil {
                    SkeletonCard(height: 300)
                } else if let plan = store.plan {
                    if let meal = store.todayMeal {
                        HStack {
                            Text("Heute · \(Labels.dayNames[meal.day])").font(Theme.F.headline)
                            Spacer()
                            Text(Labels.meal(meal.mealType)).font(Theme.F.micro).padding(.horizontal, 12).frame(height: 30)
                                .background(Theme.C.cardTop, in: Capsule())
                        }
                        NavigationLink { RecipeDetailView(meal: meal) } label: { MealCardBig(meal: meal) }
                            .buttonStyle(.plain).padding(.top, 70)
                    }
                    HStack {
                        Text("Diese Woche").font(Theme.F.headline)
                        Spacer()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(Array(plan.entries.enumerated()), id: \.offset) { _, meal in
                                NavigationLink { RecipeDetailView(meal: meal) } label: { MealCardSmall(meal: meal) }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.pagePadding).padding(.top, 40).padding(.bottom, 16)
                    }
                    .padding(.horizontal, -Theme.pagePadding)
                    BudgetCard(plan: plan, budgetCents: store.household?.budgetFoodWeekCents ?? 0)
                } else {
                    EmptyState(symbol: "fork.knife", title: "Noch kein Wochenplan",
                               text: "Wir planen deine Woche mit den aktuellen Angeboten.",
                               buttonTitle: "Plan erstellen") { showGenerator = true }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 120)
        }
        .refreshable { await store.loadAll() }
    }
}

struct MealCardBig: View {
    let meal: MealDTO

    var body: some View {
        VStack(spacing: 4) {
            Plate(url: URL(string: meal.recipe.imageUrl), size: 170).padding(.top, -78).padding(.bottom, 12)
            Text(meal.recipe.title).font(.system(.title3, weight: .bold)).multilineTextAlignment(.center)
            Text("\(meal.recipe.prepMinutes) min · \(euro(meal.costCents / max(meal.recipe.servings, 1))) pro Portion")
                .font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            let deals = meal.recipe.ingredients.filter { $0.offerId != nil }.count
            if deals > 0 {
                DealBadge(text: "\(deals) Zutaten im Angebot", style: .soft).padding(.top, 10)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .card()
    }
}

struct MealCardSmall: View {
    let meal: MealDTO

    var body: some View {
        VStack(spacing: 4) {
            Plate(url: URL(string: meal.recipe.imageUrl), size: 96).padding(.top, -36)
            Text(meal.recipe.title).font(.system(.subheadline, weight: .bold)).lineLimit(2)
                .multilineTextAlignment(.center).frame(minHeight: 36)
            Text("\(euro(meal.costCents)) · \(meal.recipe.prepMinutes) min").font(Theme.F.micro).foregroundStyle(Theme.C.text2)
        }
        .padding(14)
        .frame(width: 150)
        .overlay(alignment: .topLeading) {
            Text(Labels.days[meal.day].uppercased()).font(Theme.F.micro).foregroundStyle(Theme.C.text2).padding(12)
        }
        .card()
    }
}

struct BudgetCard: View {
    let plan: PlanDTO
    let budgetCents: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Budget \(plan.week.replacingOccurrences(of: "-W", with: " · KW "))").font(.system(.body, weight: .bold))
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(euro(plan.totalCents)).font(.system(size: 30, weight: .heavy)).monospacedDigit()
                Text("von \(euro(budgetCents))").font(.system(.subheadline, weight: .semibold)).foregroundStyle(Theme.C.text2)
            }
            ProgressView(value: min(Double(plan.totalCents) / Double(max(budgetCents, 1)), 1))
                .tint(plan.totalCents > budgetCents ? Theme.C.danger : Theme.C.accent)
            if plan.savedCents > 0 {
                Label("\(euro(plan.savedCents)) gespart durch Angebote", systemImage: "checkmark")
                    .font(Theme.F.callout).foregroundStyle(Theme.C.success)
            }
        }
        .padding(18)
        .card()
    }
}
