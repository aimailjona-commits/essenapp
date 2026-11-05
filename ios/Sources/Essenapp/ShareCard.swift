import SwiftUI

// Feature 10: Rezept als Bildkarte teilen (1080×1350 px).

/// Karte in 360×450 pt, gerendert mit Faktor 3. Look wie die Bildkarte in f.html (Teilen-Sheet), Maße × 1,32 (272 → 360).
/// Feste Textgröße, damit Dynamic Type das Bild nicht sprengt.
struct RecipeShareCard: View {
    let meal: MealDTO
    let photo: UIImage?  // vorher geladen – AsyncImage rendert im ImageRenderer nicht

    private var recipe: RecipeDTO { meal.recipe }

    var body: some View {
        let shown = Array(recipe.ingredients.prefix(8))
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.title).font(Theme.F.serif(26)).lineLimit(3).minimumScaleFactor(0.8)
                Text(Labels.meal(recipe.mealType)).font(Theme.F.text(14, .semibold)).foregroundStyle(Theme.C.ink2)
            }
            .frame(width: 190, alignment: .leading)
            .frame(height: 150, alignment: .topLeading)
            HStack(alignment: .top, spacing: 18) {
                stat("Zeit", "\(recipe.prepMinutes) min")
                stat("p. P.", euro(Int(Double(meal.costCents) / meal.basePortions)))
                if let kcal = recipe.nutrition?.kcal { stat("kcal", "\(Int(kcal.rounded()))") }
            }
            VStack(spacing: 0) {
                ForEach(shown, id: \.self) { ing in
                    HStack {
                        Text(ing.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(qty(ing.amount * meal.scale, ing.unit)).foregroundStyle(Theme.C.ink2).monospacedDigit()
                    }
                    .font(Theme.F.text(13, .bold))
                    .frame(height: 22)
                    .overlay(alignment: .top) { Hairline() }
                }
            }
            .padding(.top, 16)
            Spacer(minLength: 0)
            HStack {
                HStack(spacing: 6) {
                    Icon(.fork, size: 18)
                    Text("Mit Essenapp geplant")
                }
                Spacer()
                AppIconMark()
            }
            .font(Theme.F.text(14, .extrabold))
        }
        .padding(24)
        .frame(width: 360, height: 450, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            Group {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill().plate(103).frame(width: 103, height: 103)
                } else {
                    // ohne AsyncImage: der ImageRenderer liefert sonst kein Bild
                    Theme.C.blue1.overlay { Ill("pot").padding(10) }.plate(103).frame(width: 103, height: 103)
                }
            }
            .offset(x: 235, y: 32)
        }
        .background(alignment: .topLeading) {
            Circle().fill(Theme.C.blue).frame(width: 264, height: 264).offset(x: 185, y: -98)
        }
        .background(Theme.C.card)
        .clipped()
        .foregroundStyle(Theme.C.ink)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.colorScheme, .light)
    }

    /// Kleine `.stat`: Haarlinie in Tinte, Label 13/700, Zahl rechts.
    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Hairline(color: Theme.C.ink)
            Text(label).font(Theme.F.text(13, .bold))
            Text(value).font(Theme.F.num(30)).tracking(Theme.F.numTracking(30)).lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
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
        ImageShareSheet(name: meal.recipe.title, preview: AnyView(RecipeShareCard(meal: meal, photo: nil))) {
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
    var preview: AnyView?  // Karte direkt anzeigen, solange (oder falls) das Bild nicht fertig ist
    let render: @MainActor () async -> UIImage?
    @State private var image: UIImage?

    /// 360×450 pt mit Faktor 3 → 1080×1350 px.
    @MainActor static func snapshot(_ card: some View) -> UIImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Als Bild teilen").font(Theme.F.t2).foregroundStyle(Theme.C.ink)
                Spacer()
                CloseButton { dismiss() }
            }
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: Theme.C.ink.opacity(0.14), radius: 15, y: 14)
                        .accessibilityLabel("Bildkarte \(name)")
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                } else if let preview {
                    preview.frame(width: 360, height: 450)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .scaleEffect(272 * 1.2 / 360)
                        .frame(width: 272 * 1.2, height: 450 * 272 * 1.2 / 360)
                        .accessibilityLabel("Bildkarte \(name)")
                } else {
                    Skeleton8(height: 340).aspectRatio(0.8, contentMode: .fit)
                }
            }
            .frame(maxWidth: 272 * 1.2, maxHeight: .infinity)
            .padding(.top, 18)
            if let image {
                ShareLink(item: Image(uiImage: image), preview: SharePreview(name, image: Image(uiImage: image))) {
                    HStack(spacing: 8) {
                        Icon(.share, size: 20)
                        Text("Teilen")
                    }
                    .font(Theme.F.button).foregroundStyle(Theme.C.onInk)
                    .frame(maxWidth: .infinity, minHeight: Theme.S.button)
                    .background(Theme.C.ink, in: Capsule())
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 22)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .sheet8()
        .animation(Theme.spring, value: image)
        .task { image = await render() }
    }
}
