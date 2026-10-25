import Foundation

/// Valores nutricionales (kcal y macros en gramos). Lógica pura, sin dependencias de UI ni de SwiftData.
struct NutritionValues: Equatable, Codable {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    static let zero = NutritionValues(kcal: 0, protein: 0, carbs: 0, fat: 0)

    static func + (lhs: NutritionValues, rhs: NutritionValues) -> NutritionValues {
        NutritionValues(
            kcal: lhs.kcal + rhs.kcal,
            protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat
        )
    }

    static func += (lhs: inout NutritionValues, rhs: NutritionValues) {
        lhs = lhs + rhs
    }

    /// Escala valores expresados por 100 g a una cantidad concreta en gramos.
    func scaled(toGrams grams: Double) -> NutritionValues {
        let factor = max(grams, 0) / 100.0
        return NutritionValues(kcal: kcal * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor)
    }
}

enum NutritionMath {
    static func values(per100 values: NutritionValues, grams: Double) -> NutritionValues {
        values.scaled(toGrams: grams)
    }

    static func sum(_ items: [NutritionValues]) -> NutritionValues {
        items.reduce(.zero, +)
    }

    /// Fracción consumida/objetivo limitada a [0, 1]. Devuelve 0 si el objetivo no es válido.
    static func progress(consumed: Double, target: Double) -> Double {
        guard target > 0, consumed.isFinite else { return 0 }
        return min(max(consumed / target, 0), 1)
    }

    /// Energía teórica por macros (4/4/9). Útil para detectar valores incoherentes en el catálogo.
    static func kcalFromMacros(_ v: NutritionValues) -> Double {
        v.protein * 4 + v.carbs * 4 + v.fat * 9
    }
}

/// Indica a qué estado corresponde el peso que se pone en la báscula.
enum WeightBasis: String, Codable, CaseIterable, Identifiable {
    case raw
    case cooked
    case dry
    case drained
    case cookedDrained
    case edible
    case asWeighed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .raw: return "En crudo"
        case .cooked: return "Cocinado"
        case .dry: return "Peso en seco"
        case .drained: return "Peso escurrido"
        case .cookedDrained: return "Cocido y escurrido"
        case .edible: return "Parte comestible"
        case .asWeighed: return "Peso real en báscula"
        }
    }
}

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case snack
    case dinner

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: return "Desayuno"
        case .lunch: return "Almuerzo"
        case .snack: return "Merienda"
        case .dinner: return "Cena"
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .snack: return "cup.and.saucer.fill"
        case .dinner: return "moon.stars.fill"
        }
    }

    var order: Int {
        switch self {
        case .breakfast: return 0
        case .lunch: return 1
        case .snack: return 2
        case .dinner: return 3
        }
    }
}

// MARK: - Recetas

/// Cuentas de una receta: por ración y por 100 g del plato ya cocinado.
/// Lógica pura: ni inventa pesos ni rellena lo que no se ha pesado.
enum RecipeMath {
    /// Valores de una ración. nil si solo hay una ración (no hay nada que repartir)
    /// o si el número de raciones no tiene sentido.
    static func perServing(_ total: NutritionValues, servings: Int) -> NutritionValues? {
        guard servings > 1 else { return nil }
        return NutritionValues(kcal: total.kcal / Double(servings),
                               protein: total.protein / Double(servings),
                               carbs: total.carbs / Double(servings),
                               fat: total.fat / Double(servings))
    }

    /// Valores por 100 g del plato cocinado. Es lo único que permite volver a pesar
    /// una ración otro día y saber lo que llevas.
    static func per100gCooked(_ total: NutritionValues, cookedGrams: Double) -> NutritionValues? {
        guard cookedGrams > 0 else { return nil }
        let factor = 100 / cookedGrams
        return NutritionValues(kcal: total.kcal * factor,
                               protein: total.protein * factor,
                               carbs: total.carbs * factor,
                               fat: total.fat * factor)
    }

    /// Cuánto peso queda después de cocinar: 0,8 = se queda en el 80 % del peso crudo.
    /// Mayor que 1 si el alimento absorbe agua (arroz, pasta, legumbres).
    static func yieldFactor(rawGrams: Double, cookedGrams: Double) -> Double? {
        guard rawGrams > 0, cookedGrams > 0 else { return nil }
        return cookedGrams / rawGrams
    }

    /// Frase que explica el rendimiento, para no dejar un número suelto sin contexto.
    static func yieldText(_ factor: Double) -> String {
        if factor < 0.98 {
            return "Pierde agua al cocinarse: se queda en el \(NumberFormat.percent(factor)) del peso crudo."
        }
        if factor > 1.02 {
            return "Absorbe agua al cocinarse: pesa el \(NumberFormat.percent(factor)) del peso crudo."
        }
        return "Pesa prácticamente lo mismo cocinado que crudo."
    }

    /// Gramos de una ración del plato cocinado, si se ha pesado el total.
    static func gramsPerServing(cookedGrams: Double?, servings: Int) -> Double? {
        guard let cookedGrams, cookedGrams > 0, servings > 0 else { return nil }
        return cookedGrams / Double(servings)
    }
}
