import Foundation

/// Arma el menú de cada día: elige platos y ajusta los gramos
/// para que el día cuadre con las calorías y los macros del perfil.
enum MenuPlanner {

    /// Cuántos platos se barajan para cada comida antes de elegir.
    private static let candidateCount = 4

    /// Salto diario dentro de la lista de recetas. Primo con el número de
    /// platos de cada tipo para que el menú no se repita de un día para otro.
    private static func dailyStride(for type: MealType) -> Int {
        switch type {
        case .breakfast: return 3
        case .lunch: return 5
        case .snack: return 7
        case .dinner: return 5
        }
    }

    /// Menú completo de un día.
    static func plan(for date: Date, targets: NutritionTargets) -> [ScaledRecipe] {
        MealType.allCases
            .sorted { $0.order < $1.order }
            .map { meal(for: $0, date: date, targets: targets) }
    }

    /// Elige el plato de una comida concreta y lo ajusta al objetivo.
    static func meal(for type: MealType,
                     date: Date,
                     targets: NutritionTargets,
                     excluding excluded: Set<String> = []) -> ScaledRecipe {
        let list = FoodDatabase.recipes(for: type)
        guard !list.isEmpty else {
            return ScaledRecipe(recipe: Recipe(id: "vacio", name: type.label, type: type, ingredients: []),
                                ingredients: [])
        }

        let targetCalories = targets.calories * type.shareOfDay
        let targetProtein = targets.protein * type.shareOfDay
        let targetFat = targets.fat * type.shareOfDay

        let day = DateHelper.dayNumber(date)
        let offset = ((day * dailyStride(for: type)) % list.count + list.count) % list.count

        var candidates: [Recipe] = []
        var index = 0
        while candidates.count < min(candidateCount, list.count) && index < list.count {
            let recipe = list[(offset + index) % list.count]
            if !excluded.contains(recipe.id) { candidates.append(recipe) }
            index += 1
        }
        if candidates.isEmpty { candidates = [list[offset]] }

        let best = candidates
            .map { ($0, score($0, targetCalories: targetCalories, targetProtein: targetProtein, targetFat: targetFat)) }
            .min { $0.1 < $1.1 }?.0 ?? candidates[0]

        return best.scaled(toCalories: targetCalories)
    }

    /// Otras opciones del mismo tipo, ya ajustadas, para el botón "Cambiar".
    static func alternatives(for type: MealType,
                             targets: NutritionTargets,
                             currentID: String) -> [ScaledRecipe] {
        let targetCalories = targets.calories * type.shareOfDay
        return FoodDatabase.recipes(for: type)
            .filter { $0.id != currentID }
            .map { $0.scaled(toCalories: targetCalories) }
    }

    /// Ajusta un plato concreto al objetivo de su comida.
    static func scale(_ recipe: Recipe, targets: NutritionTargets) -> ScaledRecipe {
        recipe.scaled(toCalories: targets.calories * recipe.type.shareOfDay)
    }

    /// Cuanto más bajo, mejor encaja el plato: manda la proteína,
    /// después las calorías, y se penaliza pasarse de grasa.
    private static func score(_ recipe: Recipe,
                              targetCalories: Double,
                              targetProtein: Double,
                              targetFat: Double) -> Double {
        let totals = recipe.scaled(toCalories: targetCalories).totals
        let proteinGap = abs(totals.protein - targetProtein) / max(1, targetProtein)
        let calorieGap = abs(totals.calories - targetCalories) / max(1, targetCalories)
        let fatExcess = max(0, totals.fat - targetFat) / max(1, targetFat)
        return proteinGap * 2 + calorieGap + fatExcess * 0.8
    }
}
