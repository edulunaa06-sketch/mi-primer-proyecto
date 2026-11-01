import Foundation

/// Elige comidas que cuadren con los macros del día (lógica pura, sin SwiftData ni UI).
///
/// Cada opción es una comida de los menús. Para cada una se calcula una ración ajustada
/// (factor entre 0,75 y 1,35, en pasos de 0,05) y se puntúa cuánto se acerca su resultado
/// (con gramos redondeados a cantidades pesables) al objetivo de esa comida.
enum MealPlanner {
    struct Item: Equatable {
        let per100: NutritionValues
        let grams: Double
    }

    struct Candidate: Equatable {
        let id: String
        let items: [Item]
    }

    struct Option: Equatable {
        let id: String
        let factor: Double
        let values: NutritionValues
        /// 0…1: 1 = coincide exactamente con el objetivo de la comida.
        let fit: Double
    }

    /// Reparto orientativo de las kcal y macros del día entre las cuatro comidas.
    static let share: [MealType: Double] = [.breakfast: 0.25, .lunch: 0.35, .snack: 0.15, .dinner: 0.25]
    static let factorRange: ClosedRange<Double> = 0.75...1.35
    static let factorStep = 0.05

    /// Gramos que se pesan con una ración: sin cambios si el factor es 1.
    static func grams(_ grams: Double, factor: Double) -> Double {
        abs(factor - 1) < 0.001 ? grams : MenuScaler.scaledGrams(grams, factor: factor)
    }

    static func values(of candidate: Candidate, factor: Double) -> NutritionValues {
        NutritionMath.sum(candidate.items.map { $0.per100.scaled(toGrams: grams($0.grams, factor: factor)) })
    }

    /// Objetivo para una comida cuando las comidas de `fixed` ya están decididas:
    /// lo que queda del día se reparte entre las comidas pendientes según `share`.
    /// Si es la última comida pendiente, recibe todo lo que queda.
    static func target(for meal: MealType, daily: NutritionValues, fixed: [MealType: NutritionValues]) -> NutritionValues {
        let used = NutritionMath.sum(Array(fixed.filter { $0.key != meal }.values))
        let remaining = NutritionValues(
            kcal: max(daily.kcal - used.kcal, 0),
            protein: max(daily.protein - used.protein, 0),
            carbs: max(daily.carbs - used.carbs, 0),
            fat: max(daily.fat - used.fat, 0)
        )
        let pending = MealType.allCases.filter { $0 == meal || fixed[$0] == nil }
        let pendingShare = pending.reduce(0) { $0 + (share[$1] ?? 0) }
        guard pendingShare > 0 else { return remaining }
        let fraction = (share[meal] ?? 0) / pendingShare
        return NutritionValues(kcal: remaining.kcal * fraction, protein: remaining.protein * fraction,
                               carbs: remaining.carbs * fraction, fat: remaining.fat * fraction)
    }

    /// Puntuación de ajuste: 1 − media de los errores relativos de kcal, proteína, carbohidratos y grasa.
    static func fit(_ v: NutritionValues, to target: NutritionValues) -> Double {
        func err(_ a: Double, _ b: Double, floor: Double) -> Double { min(abs(a - b) / max(b, floor), 1) }
        let e = (err(v.kcal, target.kcal, floor: 100) + err(v.protein, target.protein, floor: 10)
                 + err(v.carbs, target.carbs, floor: 10) + err(v.fat, target.fat, floor: 5)) / 4
        return max(0, 1 - e)
    }

    /// Mejor ración posible de una opción para el objetivo.
    static func bestOption(_ candidate: Candidate, target: NutritionValues) -> Option? {
        let base = values(of: candidate, factor: 1)
        guard base.kcal > 0 else { return nil }
        var best: Option?
        var f = factorRange.lowerBound
        while f <= factorRange.upperBound + 0.0001 {
            let v = values(of: candidate, factor: f)
            let score = fit(v, to: target)
            if best == nil || score > best!.fit + 0.0001 || (abs(score - best!.fit) <= 0.0001 && abs(f - 1) < abs(best!.factor - 1)) {
                best = Option(id: candidate.id, factor: (f * 100).rounded() / 100, values: v, fit: score)
            }
            f += factorStep
        }
        return best
    }

    /// Las `limit` opciones que mejor encajan, de mejor a peor.
    static func rank(_ candidates: [Candidate], target: NutritionValues, limit: Int = 4) -> [Option] {
        Array(candidates.compactMap { bestOption($0, target: target) }
            .sorted { $0.fit > $1.fit }
            .prefix(limit))
    }
}
