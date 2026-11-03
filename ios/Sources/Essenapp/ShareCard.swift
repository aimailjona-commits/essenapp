import SwiftUI

// Feature 10: Rezept als Bildkarte teilen (1080×1350 px).

/// Karte in 360×450 pt, gerendert mit Faktor 3. Feste Textgröße, damit Dynamic Type das Bild nicht sprengt.
struct RecipeShareCard: View {
    let meal: MealDTO
    let photo: UIImage?  // vorher geladen – AsyncImage rendert im ImageRenderer nicht

    private var recipe: RecipeDTO { meal.recipe }

    var body: some View {
        let words = recipe.title.split(separator: " ")
        let shown = Array(recipe.ingredients.prefix(10))
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill().frame(width: 150, height: 150).clipShape(Circle()).floatShadow()
                } else {
                    Plate(url: nil, size: 150, seed: recipe.title)
                }
            }
            .frame(maxWidth: .infinity)
            (Text(words.prefix(1).joined()).font(.system(.title2, weight: .bold))
                + Text(" " + words.dropFirst().joined(separator: " ")).font(.system(.title2, weight: .regular)).foregroundStyle(Theme.C.text2))
                .lineLimit(2).minimumScaleFactor(0.8)
            HStack(spacing: 12) {
                Label("\(recipe.prepMinutes) min", systemImage: "clock")
                if let kcal = recipe.nutrition?.kcal { Label("\(Int(kcal.rounded())) kcal", systemImage: "flame.fill") }
                Label("\(euro(Int(Double(meal.costCents) / meal.basePortions))) / Portion", systemImage: "eurosign.circle")
            }
            .font(Theme.F.caption).foregroundStyle(Theme.C.text1)
            HStack(alignment: .top, spacing: 12) {
                ingredientColumn(Array(shown.prefix(5)))
                ingredientColumn(Array(shown.dropFirst(5)))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(radius: Theme.R.tile)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                AppIconMark()
                Text("Mit Essenapp geplant").font(Theme.F.caption).foregroundStyle(Theme.C.text2)
            }
        }
        .padding(22)
        .frame(width: 360, height: 450)
        .background(Theme.C.bg)
        .foregroundStyle(Theme.C.text1)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.colorScheme, .light)
    }

    private func ingredientColumn(_ items: [IngredientDTO]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(items, id: \.self) { ing in
                HStack(spacing: 6) {
                    Circle().fill(Theme.C.accent).frame(width: 5, height: 5)
                    Text(ing.name).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(qty(ing.amount * meal.scale, ing.unit)).foregroundStyle(Theme.C.text2).monospacedDigit()
                }
            }
        }
        .font(Theme.F.micro)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

/// App-Icon aus dem Bundle (von xtool gesetzt), sonst Marken-Kachel – Fußzeile der Bildkarten (10, 55).
struct AppIconMark: View {
    var body: some View {
        icon.frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder private var icon: some View {
        let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any]
        let files = (icons?["CFBundlePrimaryIcon"] as? [String: Any])?["CFBundleIconFiles"] as? [String]
        if let image = files?.last.flatMap({ name in UIImage(named: name) }) {
            Image(uiImage: image).resizable()
        } else {
            Image(systemName: "fork.knife").font(Theme.F.micro).foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.C.accent)
        }
    }
}

/// Vorschau der Bildkarte + Teilen über das System-Sheet (WhatsApp, Instagram-Story, In Fotos sichern).
struct ShareCardSheet: View {
    let meal: MealDTO

    var body: some View {
        ImageShareSheet(name: meal.recipe.title) {
            var photo: UIImage?
            if let url = mediaURL(meal.recipe.imageUrl), let loaded = try? await URLSession.shared.data(from: url) {
                photo = UIImage(data: loaded.0)
            }
            return ImageShareSheet.snapshot(RecipeShareCard(meal: meal, photo: photo))
        }
    }
}

/// Bildkarte als Vorschau + „Teilen“ (Rezept 10, Wochenrückblick 55).
struct ImageShareSheet: View {
    let name: String
    let render: @MainActor () async -> UIImage?
    @State private var image: UIImage?

    /// 360×450 pt mit Faktor 3 → 1080×1350 px.
    @MainActor static func snapshot(_ card: some View) -> UIImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Als Bild teilen").font(Theme.F.title).frame(maxWidth: .infinity, alignment: .leading)
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.R.tile, style: .continuous))
                    .softShadow()
                    .accessibilityLabel("Bildkarte \(name)")
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                Spacer(minLength: 0)
                ShareLink(item: Image(uiImage: image), preview: SharePreview(name, image: Image(uiImage: image))) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                SkeletonCard(height: 420)
                Spacer(minLength: 0)
            }
        }
        .padding(Theme.pagePadding)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.C.bg)
        .animation(Theme.spring, value: image)
        .task { image = await render() }
    }
}
