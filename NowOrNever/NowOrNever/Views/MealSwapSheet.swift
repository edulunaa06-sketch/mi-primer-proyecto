import SwiftUI

/// Otras opciones del mismo tipo de comida, para cambiar un plato del menú.
struct MealSwapSheet: View {
    @Environment(\.dismiss) private var dismiss

    let meal: PlannedMeal
    let targets: NutritionTargets
    let onSelect: (Recipe) -> Void

    @State private var onlyQuick = false

    private var options: [ScaledRecipe] {
        MenuPlanner.alternatives(for: meal.type, targets: targets, currentID: meal.recipeID)
            .filter { !onlyQuick || $0.recipe.quick }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ahora mismo: \(meal.name)")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)

                    Toggle("Solo opciones rápidas", isOn: $onlyQuick)
                        .font(Theme.body)
                        .foregroundStyle(Theme.text)
                        .tint(Theme.accent)
                        .padding(.bottom, 4)

                    ForEach(options) { option in
                        Button {
                            onSelect(option.recipe)
                            dismiss()
                        } label: {
                            optionCard(option)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.Spacing.screen)
            }
            .screenBackground()
            .navigationTitle("Cambiar \(meal.type.label.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.background)
    }

    private func optionCard(_ option: ScaledRecipe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(option.name)
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if option.recipe.quick {
                    TagLabel(text: "Rápido")
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(option.ingredientLines, id: \.self) { line in
                    Text("· \(line)")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            MacroChips(totals: option.totals)
        }
        .card()
    }
}

#Preview {
    MealSwapSheet(meal: PlannedMeal(type: .breakfast,
                                    recipeID: "des-pan-serrano",
                                    name: "Pan con jamón serrano",
                                    ingredientLines: ["90 g de pan de barra"],
                                    calories: 520,
                                    protein: 30,
                                    carbs: 55,
                                    fat: 18),
                  targets: NutritionTargets(calories: 2200, protein: 150, carbs: 200, fat: 61),
                  onSelect: { _ in })
        .preferredColorScheme(.dark)
}
