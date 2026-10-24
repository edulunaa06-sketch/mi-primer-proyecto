import Foundation
import SwiftData

/// Sexo biológico, necesario para la fórmula de Mifflin-St Jeor.
enum Sex: String, CaseIterable, Identifiable, Codable {
    case male, female

    var id: String { rawValue }

    var label: String {
        switch self {
        case .male: return "Hombre"
        case .female: return "Mujer"
        }
    }
}

/// Nivel de actividad diaria y su factor sobre el metabolismo basal.
enum ActivityLevel: String, CaseIterable, Identifiable, Codable {
    case sedentary, light, moderate, high, veryHigh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sedentary: return "Sedentario"
        case .light: return "Ligero (1-2 días)"
        case .moderate: return "Moderado (3-4 días)"
        case .high: return "Alto (5-6 días)"
        case .veryHigh: return "Muy alto (7 días)"
        }
    }

    var factor: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .high: return 1.725
        case .veryHigh: return 1.9
        }
    }
}

/// Objetivo del usuario; ajusta las calorías sobre el gasto total.
enum Goal: String, CaseIterable, Identifiable, Codable {
    case loseFat, maintain, gainMuscle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .loseFat: return "Perder grasa"
        case .maintain: return "Mantener"
        case .gainMuscle: return "Ganar músculo"
        }
    }

    /// Kcal que se suman (o restan) al gasto total diario.
    var calorieAdjustment: Double {
        switch self {
        case .loseFat: return -400
        case .maintain: return 0
        case .gainMuscle: return 300
        }
    }
}

/// Perfil del usuario. Solo hay uno en la app.
@Model
final class UserProfile {
    var age: Int
    var sexRaw: String
    var heightCm: Double
    var weightKg: Double
    var activityRaw: String
    var goalRaw: String

    /// Si está activo, la app usa las calorías y macros escritos a mano.
    var manualOverride: Bool
    var manualCalories: Double
    var manualProtein: Double
    var manualCarbs: Double
    var manualFat: Double

    var createdAt: Date

    init(age: Int = 17,
         sex: Sex = .male,
         heightCm: Double = 175,
         weightKg: Double = 70,
         activity: ActivityLevel = .moderate,
         goal: Goal = .loseFat,
         manualOverride: Bool = false,
         manualCalories: Double = 2000,
         manualProtein: Double = 150,
         manualCarbs: Double = 200,
         manualFat: Double = 60,
         createdAt: Date = .now) {
        self.age = age
        self.sexRaw = sex.rawValue
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.activityRaw = activity.rawValue
        self.goalRaw = goal.rawValue
        self.manualOverride = manualOverride
        self.manualCalories = manualCalories
        self.manualProtein = manualProtein
        self.manualCarbs = manualCarbs
        self.manualFat = manualFat
        self.createdAt = createdAt
    }

    var sex: Sex {
        get { Sex(rawValue: sexRaw) ?? .male }
        set { sexRaw = newValue.rawValue }
    }

    var activity: ActivityLevel {
        get { ActivityLevel(rawValue: activityRaw) ?? .moderate }
        set { activityRaw = newValue.rawValue }
    }

    var goal: Goal {
        get { Goal(rawValue: goalRaw) ?? .maintain }
        set { goalRaw = newValue.rawValue }
    }

    // MARK: - Cálculo

    /// Metabolismo basal (Mifflin-St Jeor).
    var bmr: Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return sex == .male ? base + 5 : base - 161
    }

    /// Gasto energético total diario.
    var tdee: Double { bmr * activity.factor }

    /// Objetivos calculados a partir de los datos físicos.
    var calculatedTargets: NutritionTargets {
        NutritionTargets.calculated(weightKg: weightKg, tdee: tdee, goal: goal)
    }

    /// Objetivos que usa toda la app: los manuales si el interruptor está activo.
    var targets: NutritionTargets {
        if manualOverride {
            return NutritionTargets(calories: manualCalories,
                                    protein: manualProtein,
                                    carbs: manualCarbs,
                                    fat: manualFat)
        }
        return calculatedTargets
    }
}

/// Objetivo diario de calorías y macros.
struct NutritionTargets: Equatable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    static let zero = NutritionTargets(calories: 0, protein: 0, carbs: 0, fat: 0)

    /// Reparto estándar: 2 g de proteína por kg, 25 % de las kcal en grasa, el resto hidratos.
    static func calculated(weightKg: Double, tdee: Double, goal: Goal) -> NutritionTargets {
        let calories = max(1200, (tdee + goal.calorieAdjustment).rounded())
        let protein = (weightKg * 2).rounded()
        let fat = (calories * 0.25 / 9).rounded()
        let remaining = calories - protein * 4 - fat * 9
        let carbs = max(0, remaining / 4).rounded()
        return NutritionTargets(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }
}
