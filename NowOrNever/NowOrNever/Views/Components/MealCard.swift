import SwiftUI

/// Tarjeta de una comida del menú: ingredientes, macros, check y "Cambiar".
struct MealCard: View {
    let meal: PlannedMeal
    var onToggle: () -> Void
    var onSwap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Image(systemName: meal.type.icon)
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(Theme.accent)
                        Text(meal.type.label.uppercased())
                            .font(Theme.overline)
                            .kerning(1.3)
                            .foregroundStyle(Theme.accent)
                    }
                    Text(meal.name)
                        .font(Theme.cardTitle)
                        .foregroundStyle(meal.done ? Theme.textSecondary : Theme.text)
                        .strikethrough(meal.done, color: Theme.textTertiary)
                }
                Spacer(minLength: 0)
                CheckButton(isOn: meal.done, action: onToggle)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(meal.ingredientLines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 7) {
                        Circle()
                            .fill(Theme.accent.opacity(0.7))
                            .frame(width: 4, height: 4)
                            .padding(.top, 7)
                        Text(line)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            MacroChips(totals: meal.totals)

            Button(action: onSwap) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Cambiar")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(meal.done ? Theme.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
    }
}

/// Check amarillo redondo.
struct CheckButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(isOn ? Theme.accent : Theme.textTertiary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MealCard(meal: PlannedMeal(type: .lunch,
                               recipeID: "alm-pollo-arroz",
                               name: "Pollo con arroz y brócoli",
                               ingredientLines: ["180 g de pechuga de pollo",
                                                 "90 g de arroz blanco (en crudo)",
                                                 "150 g de brócoli",
                                                 "10 g de aceite de oliva"],
                               calories: 780,
                               protein: 62,
                               carbs: 78,
                               fat: 20),
             onToggle: {},
             onSwap: {})
        .padding()
        .frame(maxHeight: .infinity)
        .screenBackground()
}
