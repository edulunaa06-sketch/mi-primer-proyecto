import Foundation

/// Sexo usado SOLO por la fórmula de Mifflin-St Jeor (que distingue dos constantes).
enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? "Hombre" : "Mujer" }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary, light, moderate, high, veryHigh
    var id: String { rawValue }

    /// Factores de actividad habituales (multiplican la tasa metabólica basal).
    var factor: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .high: return 1.725
        case .veryHigh: return 1.9
        }
    }

    var label: String {
        switch self {
        case .sedentary: return "Sedentario"
        case .light: return "Ligero"
        case .moderate: return "Moderado"
        case .high: return "Alto"
        case .veryHigh: return "Muy alto"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: return "Trabajo sentado y poco ejercicio"
        case .light: return "Ejercicio 1–3 días por semana"
        case .moderate: return "Ejercicio 3–5 días por semana"
        case .high: return "Ejercicio intenso 6–7 días por semana"
        case .veryHigh: return "Entrenos dobles o trabajo físico duro"
        }
    }
}

enum FitnessGoal: String, Codable, CaseIterable, Identifiable {
    case loseFat, gainMuscle, recomposition
    var id: String { rawValue }

    var label: String {
        switch self {
        case .loseFat: return "Perder grasa"
        case .gainMuscle: return "Ganar músculo"
        case .recomposition: return "Recomposición"
        }
    }

    /// Ajuste sobre el gasto diario estimado.
    var calorieAdjustment: Double {
        switch self {
        case .loseFat: return -0.20
        case .gainMuscle: return 0.10
        case .recomposition: return -0.10
        }
    }

    /// Proteína en gramos por kg de peso corporal.
    var proteinPerKg: Double {
        switch self {
        case .loseFat: return 2.2
        case .gainMuscle: return 1.8
        case .recomposition: return 2.0
        }
    }
}

/// Datos del perfil necesarios para el cálculo.
struct BodyProfile: Equatable {
    var weightKg: Double
    var heightCm: Double
    var age: Int
    var sex: BiologicalSex
    var activity: ActivityLevel
    var goal: FitnessGoal

    var isValid: Bool {
        (30...300).contains(weightKg) && (120...230).contains(heightCm) && (14...100).contains(age)
    }
}

struct EnergyTargets: Equatable {
    let bmr: Double
    let tdee: Double
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}

/// Cálculo estimado (no clínico) de gasto energético y objetivos.
///
/// 1. Tasa metabólica basal (Mifflin-St Jeor):
///    10 × peso(kg) + 6,25 × altura(cm) − 5 × edad + 5 (hombre) / −161 (mujer)
/// 2. Gasto diario = basal × factor de actividad.
/// 3. Calorías objetivo = gasto × (1 + ajuste del objetivo): −20 % perder grasa, +10 % ganar músculo,
///    −10 % recomposición. Se redondea a 10 kcal.
/// 4. Proteína = g/kg según objetivo (2,2 / 1,8 / 2,0). Grasa = 25 % de las kcal (mínimo 0,6 g/kg).
///    Carbohidratos = kcal restantes / 4.
enum EnergyCalculator {
    static let fatShare = 0.25
    static let minFatPerKg = 0.6

    static func bmr(_ p: BodyProfile) -> Double {
        let base = 10 * p.weightKg + 6.25 * p.heightCm - 5 * Double(p.age)
        return base + (p.sex == .male ? 5 : -161)
    }

    static func targets(for p: BodyProfile) -> EnergyTargets {
        let basal = bmr(p)
        let tdee = basal * p.activity.factor
        let kcal = (tdee * (1 + p.goal.calorieAdjustment) / 10).rounded() * 10
        let protein = (p.weightKg * p.goal.proteinPerKg).rounded()
        let fat = max(kcal * fatShare / 9, p.weightKg * minFatPerKg).rounded()
        let carbs = max((kcal - protein * 4 - fat * 9) / 4, 0).rounded()
        return EnergyTargets(bmr: basal, tdee: tdee, kcal: kcal, protein: protein, carbs: carbs, fat: fat)
    }

    /// Reparte unas kcal elegidas a mano en macros, con el criterio del cálculo automático.
    /// Sin peso conocido: 30 % proteína, 25 % grasa y el resto carbohidratos.
    /// La proteína nunca pasa del 40 % de las kcal, para que siempre queden carbohidratos.
    static func macros(forKcal kcal: Double, weightKg: Double?, goal: FitnessGoal) -> (protein: Double, carbs: Double, fat: Double) {
        guard kcal > 0 else { return (0, 0, 0) }
        let protein: Double
        let fat: Double
        if let w = weightKg, w > 0 {
            protein = min(w * goal.proteinPerKg, kcal * 0.40 / 4).rounded()
            fat = min(max(kcal * fatShare / 9, w * minFatPerKg), kcal * 0.35 / 9).rounded()
        } else {
            protein = (kcal * 0.30 / 4).rounded()
            fat = (kcal * fatShare / 9).rounded()
        }
        let carbs = max((kcal - protein * 4 - fat * 9) / 4, 0).rounded()
        return (protein, carbs, fat)
    }
}

/// Ajuste proporcional de un menú a un objetivo de kcal.
enum MenuScaler {
    /// Factor para pasar de `currentKcal` a `targetKcal` (limitado a 0,5–2 para evitar menús absurdos).
    static func factor(currentKcal: Double, targetKcal: Double) -> Double? {
        guard currentKcal > 0, targetKcal > 0 else { return nil }
        return min(max(targetKcal / currentKcal, 0.5), 2.0)
    }

    /// Escala unos gramos y los redondea a una cantidad pesable:
    /// < 20 g → 1 g (aceite, frutos secos…), < 100 g → 5 g, resto → 10 g. Nunca baja de 1 g.
    static func scaledGrams(_ grams: Double, factor: Double) -> Double {
        let raw = grams * factor
        let step: Double = raw < 20 ? 1 : (raw < 100 ? 5 : 10)
        return max((raw / step).rounded() * step, 1)
    }
}
