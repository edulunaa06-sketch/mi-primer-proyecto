import Foundation
import SwiftData

/// Los cuatro momentos del día.
enum MealType: String, CaseIterable, Identifiable, Codable {
    case breakfast, lunch, snack, dinner

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: return "Desayuno"
        case .lunch: return "Almuerzo"
        case .snack: return "Merienda"
        case .dinner: return "Cena"
        }
    }

    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "fork.knife"
        case .snack: return "cup.and.saucer.fill"
        case .dinner: return "moon.stars.fill"
        }
    }

    /// Orden en el que aparecen durante el día.
    var order: Int {
        switch self {
        case .breakfast: return 0
        case .lunch: return 1
        case .snack: return 2
        case .dinner: return 3
        }
    }

    /// Parte del total diario que le toca a cada comida.
    var shareOfDay: Double {
        switch self {
        case .breakfast: return 0.25
        case .lunch: return 0.35
        case .snack: return 0.10
        case .dinner: return 0.30
        }
    }
}

/// Suma de calorías y macros. Se usa en todas partes para acumular.
struct MacroTotals: Equatable {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0

    static let zero = MacroTotals()

    static func + (lhs: MacroTotals, rhs: MacroTotals) -> MacroTotals {
        MacroTotals(calories: lhs.calories + rhs.calories,
                    protein: lhs.protein + rhs.protein,
                    carbs: lhs.carbs + rhs.carbs,
                    fat: lhs.fat + rhs.fat)
    }

    static func += (lhs: inout MacroTotals, rhs: MacroTotals) {
        lhs = lhs + rhs
    }
}

/// Una comida del menú del día, ya con sus gramos calculados.
@Model
final class PlannedMeal {
    var typeRaw: String
    /// Identificador de la receta en la base de comidas (para poder cambiarla).
    var recipeID: String
    var name: String
    /// Ingredientes ya escalados, en texto: "150 g de pechuga de pollo".
    var ingredientLines: [String]
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    /// Marcada como hecha: solo entonces cuenta en Inicio.
    var done: Bool
    var day: DayPlan?

    init(type: MealType,
         recipeID: String,
         name: String,
         ingredientLines: [String],
         calories: Double,
         protein: Double,
         carbs: Double,
         fat: Double,
         done: Bool = false) {
        self.typeRaw = type.rawValue
        self.recipeID = recipeID
        self.name = name
        self.ingredientLines = ingredientLines
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.done = done
    }

    var type: MealType {
        get { MealType(rawValue: typeRaw) ?? .lunch }
        set { typeRaw = newValue.rawValue }
    }

    var totals: MacroTotals {
        MacroTotals(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }

    /// Sustituye el contenido por el de otra receta ya escalada.
    func apply(_ meal: ScaledRecipe) {
        let totals = meal.totals
        recipeID = meal.recipe.id
        name = meal.recipe.name
        ingredientLines = meal.ingredientLines
        calories = totals.calories.rounded()
        protein = totals.protein.rounded()
        carbs = totals.carbs.rounded()
        fat = totals.fat.rounded()
    }
}

/// El menú de un día concreto.
@Model
final class DayPlan {
    /// Siempre normalizada al inicio del día.
    @Attribute(.unique) var date: Date
    @Relationship(deleteRule: .cascade, inverse: \PlannedMeal.day)
    var meals: [PlannedMeal]

    init(date: Date, meals: [PlannedMeal] = []) {
        self.date = date
        self.meals = meals
    }

    /// Comidas ordenadas como transcurre el día.
    var sortedMeals: [PlannedMeal] {
        meals.sorted { $0.type.order < $1.type.order }
    }

    /// Suma de lo que está marcado como hecho.
    var eatenTotals: MacroTotals {
        meals.filter(\.done).reduce(into: MacroTotals.zero) { $0 += $1.totals }
    }

    /// Suma del menú completo, se haya comido o no.
    var plannedTotals: MacroTotals {
        meals.reduce(into: MacroTotals.zero) { $0 += $1.totals }
    }

    /// La primera comida del día que queda por hacer.
    var nextMeal: PlannedMeal? {
        sortedMeals.first { !$0.done }
    }
}

/// Algo que he comido fuera del menú y he apuntado a mano.
@Model
final class ManualFood {
    var date: Date
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var createdAt: Date

    init(date: Date,
         name: String,
         calories: Double,
         protein: Double,
         carbs: Double,
         fat: Double,
         createdAt: Date = .now) {
        self.date = date
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.createdAt = createdAt
    }

    var totals: MacroTotals {
        MacroTotals(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }
}
