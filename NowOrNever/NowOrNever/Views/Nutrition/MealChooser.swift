import SwiftUI

/// Tarjeta de una opción de comida con su ración ajustada, ingredientes y macros.
struct MealOptionCard: View {
    let meal: ResolvedMeal
    let option: MealPlanner.Option
    let target: NutritionValues
    /// Total del día si se elige esta opción (para comparar con el objetivo diario).
    var dayTotal: NutritionValues?
    var daily: NutritionValues?
    let onPick: () -> Void

    var body: some View {
        let scaled = ResolvedMeal(type: meal.type, template: meal.template, plan: meal.plan, factor: option.factor, isChoice: true)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.sourceName).font(.subheadline.weight(.semibold))
                    Text(abs(option.factor - 1) < 0.001 ? "Ración del menú" : "Ración al \(Int((option.factor * 100).rounded())) %")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("Encaja \(NumberFormat.percent(option.fit))")
                    .font(.caption.weight(.heavy))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(option.fit >= 0.85 ? Theme.lime : Theme.limeDim, in: Capsule())
                    .foregroundStyle(option.fit >= 0.85 ? Color.black : Theme.lime)
            }
            ForEach(scaled.lines, id: \.item.persistentModelID) { line in
                HStack {
                    Text(line.item.food?.name ?? "—").font(.caption)
                    Spacer()
                    Text("\(NumberFormat.oneDecimal(line.grams)) g · \(NumberFormat.integer(line.values.kcal)) kcal")
                        .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                }
            }
            Divider().overlay(Color.white.opacity(0.08))
            macroLine("Esta comida", option.values, target: target)
            if let dayTotal, let daily {
                macroLine("Día completo", dayTotal, target: daily)
            }
            Button("Elegir esta opción", action: onPick)
                .buttonStyle(LimeButtonStyle())
        }
        .card()
    }

    private func macroLine(_ title: String, _ v: NutritionValues, target t: NutritionValues) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.weight(.bold)).foregroundStyle(Theme.lime)
            Text("\(NumberFormat.integer(v.kcal))/\(NumberFormat.integer(t.kcal)) kcal · P \(NumberFormat.integer(v.protein))/\(NumberFormat.integer(t.protein)) · C \(NumberFormat.integer(v.carbs))/\(NumberFormat.integer(t.carbs)) · G \(NumberFormat.integer(v.fat))/\(NumberFormat.integer(t.fat))")
                .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary)
        }
    }
}

/// Elegir una comida concreta entre las opciones que mejor cuadran con el resto del día.
struct MealChooserSheet: View {
    let type: MealType
    let target: NutritionValues
    let dayTotalsWithoutThis: NutritionValues
    let daily: NutritionValues
    let candidates: [ResolvedMeal]
    var subtitle: String
    let onPick: (MealPlanner.Option) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showAll = false

    var body: some View {
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.plan.id.uuidString, $0) })
        let options = MealPlanner.rank(candidates.map(\.plannerCandidate), target: target, limit: showAll ? candidates.count : 4)
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    TargetHeader(title: "Objetivo para tu \(type.label.lowercased())", subtitle: subtitle, target: target)
                    ForEach(options, id: \.id) { option in
                        if let meal = byID[option.id] {
                            MealOptionCard(meal: meal, option: option, target: target,
                                           dayTotal: dayTotalsWithoutThis + option.values, daily: daily) {
                                onPick(option)
                                dismiss()
                            }
                        }
                    }
                    if !showAll && candidates.count > 4 {
                        Button("Ver las \(candidates.count) opciones") { showAll = true }
                            .buttonStyle(LimeButtonStyle(filled: false))
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Cambiar \(type.label.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
        }
    }
}

/// Construir el día comida a comida: cada paso propone opciones según lo que ya has elegido.
struct DayBuilderSheet: View {
    let daily: NutritionValues
    let plans: [MenuPlan]
    let onFinish: ([(MealType, MealPlanner.Option)]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var picks: [MealType: MealPlanner.Option] = [:]
    @State private var showAll = false

    private let order = MealType.allCases

    private var fixed: [MealType: NutritionValues] { picks.mapValues(\.values) }
    private var chosenTotal: NutritionValues { NutritionMath.sum(Array(fixed.values)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    progressHeader
                    if step < order.count {
                        stepView(order[step])
                    } else {
                        summary
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(step < order.count ? "Elige tu \(order[step].label.lowercased())" : "Tu día")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                if step > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Atrás") { goBack() }
                    }
                }
            }
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Array(order.enumerated()), id: \.offset) { index, type in
                    VStack(spacing: 4) {
                        Image(systemName: picks[type] != nil ? "checkmark.circle.fill" : type.symbol)
                            .foregroundStyle(index == step ? Theme.lime : (picks[type] != nil ? Theme.lime : Theme.textTertiary))
                        Text(type.label).font(.caption2)
                            .foregroundStyle(index == step ? Theme.textPrimary : Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if !picks.isEmpty {
                Text("Llevas \(NumberFormat.integer(chosenTotal.kcal)) de \(NumberFormat.integer(daily.kcal)) kcal · P \(NumberFormat.integer(chosenTotal.protein))/\(NumberFormat.integer(daily.protein)) · C \(NumberFormat.integer(chosenTotal.carbs))/\(NumberFormat.integer(daily.carbs)) · G \(NumberFormat.integer(chosenTotal.fat))/\(NumberFormat.integer(daily.fat))")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }

    @ViewBuilder
    private func stepView(_ type: MealType) -> some View {
        let candidates = DataStore.candidates(for: type, plans: plans)
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.plan.id.uuidString, $0) })
        // Las comidas posteriores aún no elegidas no cuentan: se reserva su parte del día.
        let previous = picks.filter { order.firstIndex(of: $0.key)! < step }.mapValues(\.values)
        let target = MealPlanner.target(for: type, daily: daily, fixed: previous)
        let options = MealPlanner.rank(candidates.map(\.plannerCandidate), target: target, limit: showAll ? candidates.count : 4)
        TargetHeader(title: "Objetivo para tu \(type.label.lowercased())",
                     subtitle: step == 0 ? "Elige una de estas opciones" : (type == .dinner ? "La cena cuadra con lo que te falta del día" : "Según lo que ya has elegido"),
                     target: target)
        ForEach(options, id: \.id) { option in
            if let meal = byID[option.id] {
                MealOptionCard(meal: meal, option: option, target: target) {
                    picks[type] = option
                    // Al cambiar una comida anterior se descartan las siguientes (sus opciones dependían de ella).
                    for later in order.dropFirst(step + 1) { picks[later] = nil }
                    showAll = false
                    withAnimation { step += 1 }
                }
            }
        }
        if !showAll && candidates.count > 4 {
            Button("Ver las \(candidates.count) opciones") { showAll = true }
                .buttonStyle(LimeButtonStyle(filled: false))
        }
    }

    private var summary: some View {
        let total = chosenTotal
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Resumen del día", subtitle: "Ajuste con tus objetivos: \(NumberFormat.percent(MealPlanner.fit(total, to: daily)))")
            MacroRow(name: "Calorías", consumed: total.kcal, target: daily.kcal, unit: "kcal")
            MacroRow(name: "Proteínas", consumed: total.protein, target: daily.protein)
            MacroRow(name: "Carbohidratos", consumed: total.carbs, target: daily.carbs)
            MacroRow(name: "Grasas", consumed: total.fat, target: daily.fat)
            Button("Guardar mi día") {
                onFinish(order.compactMap { type in picks[type].map { (type, $0) } })
                dismiss()
            }
            .buttonStyle(LimeButtonStyle())
            Text("Después puedes marcar cada comida como hecha o cambiar cualquiera con «Cambiar».")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .card()
    }

    private func goBack() {
        showAll = false
        withAnimation { step = max(step - 1, 0) }
    }
}

struct TargetHeader: View {
    let title: String
    let subtitle: String
    let target: NutritionValues

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: title, subtitle: subtitle)
            Text("≈ \(NumberFormat.integer(target.kcal)) kcal · P \(NumberFormat.integer(target.protein)) g · C \(NumberFormat.integer(target.carbs)) g · G \(NumberFormat.integer(target.fat)) g")
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .card()
    }
}
