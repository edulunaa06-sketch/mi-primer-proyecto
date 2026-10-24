import SwiftUI

/// Barra de un macro: lo comido frente al objetivo.
struct MacroBar: View {
    let title: String
    let eaten: Double
    let target: Double
    var color: Color = Theme.accent

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, eaten / target))
    }

    private var exceeded: Bool { eaten > target + 0.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(Formatters.grams(eaten)) / \(Formatters.grams(target)) g")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(exceeded ? Theme.danger : Theme.text)
                    .contentTransition(.numericText())
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.cardElevated)
                    Capsule()
                        .fill(exceeded ? Theme.danger : color)
                        .frame(width: max(4, geometry.size.width * progress))
                        .animation(.easeOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 9)
        }
    }
}

/// Las tres barras de macros juntas.
struct MacroBars: View {
    let eaten: MacroTotals
    let targets: NutritionTargets

    var body: some View {
        VStack(spacing: 14) {
            MacroBar(title: "Proteína", eaten: eaten.protein, target: targets.protein, color: Theme.protein)
            MacroBar(title: "Carbohidratos", eaten: eaten.carbs, target: targets.carbs, color: Theme.carbs)
            MacroBar(title: "Grasa", eaten: eaten.fat, target: targets.fat, color: Theme.fat)
        }
    }
}

#Preview {
    MacroBars(eaten: MacroTotals(calories: 1200, protein: 90, carbs: 140, fat: 70),
              targets: NutritionTargets(calories: 2200, protein: 150, carbs: 200, fat: 61))
        .card()
        .padding()
        .frame(maxHeight: .infinity)
        .screenBackground()
}
