import SwiftUI

/// Lo que te queda por comer hoy: objetivo − comido, en kcal y macros. Sin anillos.
struct CaloriesLeftCard: View {
    let consumed: NutritionValues
    let target: NutritionValues
    var title = "Hoy"
    /// Muestra el botón «Cambiar» para poner tú las calorías que quieres comer.
    var editable = true
    @State private var editing = false

    var body: some View {
        let left = target.kcal - consumed.kcal
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title.uppercased()).font(.caption.weight(.heavy)).foregroundStyle(Theme.lime)
                Spacer()
                if editable {
                    Button { editing = true } label: {
                        Label("Cambiar", systemImage: "pencil").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .tint(Theme.lime)
                    .accessibilityIdentifier("kcal.edit")
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(left >= 0 ? "Te quedan" : "Te has pasado").font(.subheadline).foregroundStyle(Theme.textSecondary)
                Text("\(NumberFormat.integer(abs(left))) kcal")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(left >= 0 ? Theme.textPrimary : Theme.warning)
                    .accessibilityIdentifier("kcal.left")
                Text("Objetivo \(NumberFormat.integer(target.kcal)) − comido \(NumberFormat.integer(consumed.kcal))")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 10) {
                macro("Proteínas", consumed.protein, target.protein)
                macro("Carbohidratos", consumed.carbs, target.carbs)
                macro("Grasas", consumed.fat, target.fat)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .sheet(isPresented: $editing) { TargetsEditorSheet() }
    }

    private func macro(_ name: String, _ eaten: Double, _ goal: Double) -> some View {
        let left = goal - eaten
        return VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            Text("\(NumberFormat.integer(abs(left))) g").font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(left >= 0 ? Theme.textPrimary : Theme.warning)
            Text(left >= 0 ? "quedan de \(NumberFormat.integer(goal))" : "de más (\(NumberFormat.integer(goal)))")
                .font(.caption2).foregroundStyle(Theme.textTertiary).lineLimit(1).minimumScaleFactor(0.8)
            ProgressBar(fraction: goal > 0 ? eaten / goal : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
