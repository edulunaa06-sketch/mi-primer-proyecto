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
