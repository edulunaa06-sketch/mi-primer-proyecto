import Foundation
import SwiftData

// Datos de ATLAS (SwiftData, solo en el iPhone). Todos los campos tienen valor por defecto para que
// las actualizaciones de la app no pierdan datos.

@Model
final class Profile {
    var name: String = ""
    var sexRaw: String = BiologicalSex.male.rawValue
    var age: Int = 30
    var heightCm: Double = 175
    var activityRaw: String = ActivityLevel.moderate.rawValue
    var goalRaw: String = FitnessGoal.recomposition.rawValue
    var kcalTarget: Double = 2300
    var proteinTarget: Double = 160
    var carbsTarget: Double = 250
    var fatTarget: Double = 70
    /// true = objetivos escritos a mano (no se recalculan solos).
    var manualTargets: Bool = false
    var kcalMargin: Double = 100
    var stepGoal: Int = 8000
    var waterGoalMl: Int = 2500
    var onboarded: Bool = false
    var createdAt: Date = Date()

    init() {}

    var sex: BiologicalSex { BiologicalSex(rawValue: sexRaw) ?? .male }
    var activity: ActivityLevel { ActivityLevel(rawValue: activityRaw) ?? .moderate }
    var goal: FitnessGoal { FitnessGoal(rawValue: goalRaw) ?? .recomposition }
    var targets: NutritionValues { NutritionValues(kcal: kcalTarget, protein: proteinTarget, carbs: carbsTarget, fat: fatTarget) }

    /// Recalcula los objetivos con el perfil y el peso (si no son manuales).
    func recalculate(weightKg: Double?) {
        guard !manualTargets, let w = weightKg else { return }
        let body = BodyProfile(weightKg: w, heightCm: heightCm, age: age, sex: sex, activity: activity, goal: goal)
        guard body.isValid else { return }
        let t = EnergyCalculator.targets(for: body)
        kcalTarget = t.kcal; proteinTarget = t.protein; carbsTarget = t.carbs; fatTarget = t.fat
        waterGoalMl = Hydration.goal(weightKg: w)
    }
}

@Model
final class WeightLog {
    var date: Date = Date()
    var kg: Double = 0
    init(date: Date, kg: Double) { self.date = date; self.kg = kg }
}

/// Lo que comes: cada alimento apuntado guarda sus valores (así el historial no cambia si cambia el catálogo).
@Model
final class FoodEntry {
    var id: UUID = UUID()
    var dayKey: String = ""
    var mealRaw: String = MealType.breakfast.rawValue
    var name: String = ""
    var grams: Double = 0
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    /// Clave del catálogo o id de alimento propio (vacío = añadido rápido).
    var foodKey: String = ""
    /// Valores por 100 g para poder cambiar los gramos después (0 = añadido rápido).
    var kcalPer100: Double = 0
    var proteinPer100: Double = 0
    var carbsPer100: Double = 0
    var fatPer100: Double = 0
    var createdAt: Date = Date()

    init(dayKey: String, meal: MealType, name: String, grams: Double, per100: NutritionValues?, values: NutritionValues, foodKey: String) {
        self.dayKey = dayKey
        self.mealRaw = meal.rawValue
        self.name = name
        self.grams = grams
        self.foodKey = foodKey
        if let p = per100 { kcalPer100 = p.kcal; proteinPer100 = p.protein; carbsPer100 = p.carbs; fatPer100 = p.fat }
        kcal = values.kcal; protein = values.protein; carbs = values.carbs; fat = values.fat
    }

    var meal: MealType { MealType(rawValue: mealRaw) ?? .snack }
    var values: NutritionValues { NutritionValues(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
    var per100: NutritionValues? {
        kcalPer100 > 0 ? NutritionValues(kcal: kcalPer100, protein: proteinPer100, carbs: carbsPer100, fat: fatPer100) : nil
    }

    func setGrams(_ g: Double) {
        guard let p = per100 else { return }
        grams = max(g, 0)
        let v = p.scaled(toGrams: grams)
        kcal = v.kcal; protein = v.protein; carbs = v.carbs; fat = v.fat
    }
}

/// Alimentos que crea la persona (valores por 100 g).
@Model
final class CustomFood {
    var id: UUID = UUID()
    var name: String = ""
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    init(name: String, per100: NutritionValues) {
        self.name = name; kcal = per100.kcal; protein = per100.protein; carbs = per100.carbs; fat = per100.fat
    }
    var per100: NutritionValues { NutritionValues(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
}

@Model
final class WaterLog {
    var dayKey: String = ""
    var ml: Int = 0
    init(dayKey: String, ml: Int) { self.dayKey = dayKey; self.ml = ml }
}

/// Plantilla de entreno (la rutina): nombre, día de la semana y ejercicios.
@Model
final class WorkoutTemplate {
    var id: UUID = UUID()
    /// Id estable de la rutina original («tue-push-a»…) o vacío si la creaste tú.
    var seedID: String = ""
    var name: String = ""
    var kindRaw: String = SessionKind.strength.rawValue
    /// 1 = lunes … 7 = domingo; 0 = sin día fijo.
    var weekday: Int = 0
    var detail: String = ""
    var order: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template)
    var exercises: [TemplateExercise] = []

    init(name: String, kind: SessionKind, weekday: Int, detail: String = "", seedID: String = "", order: Int = 0) {
        self.name = name; self.kindRaw = kind.rawValue; self.weekday = weekday; self.detail = detail; self.seedID = seedID; self.order = order
    }

    var kind: SessionKind { SessionKind(rawValue: kindRaw) ?? .strength }
    var sortedExercises: [TemplateExercise] { exercises.sorted { $0.order < $1.order } }
}

@Model
final class TemplateExercise {
    /// Clave estable del ejercicio (historial, récords y coach la usan).
    var key: String = ""
    var name: String = ""
    var sets: Int = 3
    var repRange: String = "8–12"
    var order: Int = 0
    var template: WorkoutTemplate?
    init(key: String, name: String, sets: Int, repRange: String, order: Int) {
        self.key = key; self.name = name; self.sets = sets; self.repRange = repRange; self.order = order
    }
}

/// Un entreno hecho (o en curso).
@Model
final class Workout {
    var id: UUID = UUID()
    var templateID: UUID?
    var name: String = ""
    var kindRaw: String = SessionKind.strength.rawValue
    var startedAt: Date = Date()
    var finishedAt: Date?
    /// Carreras: distancia y tiempo.
    var runMeters: Double = 0
    var runSeconds: Int = 0
    var note: String = ""
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.workout)
    var sets: [WorkoutSet] = []

    init(name: String, kind: SessionKind, templateID: UUID?, startedAt: Date = Date()) {
        self.name = name; self.kindRaw = kind.rawValue; self.templateID = templateID; self.startedAt = startedAt
    }

    var kind: SessionKind { SessionKind(rawValue: kindRaw) ?? .strength }
    var isFinished: Bool { finishedAt != nil }
    var doneSets: [WorkoutSet] { sets.filter(\.done) }
    var samples: [SetSample] { doneSets.compactMap(\.sample) }
    var volume: Double { WorkoutMath.volume(samples) }
    var durationSeconds: Int { Int((finishedAt ?? Date()).timeIntervalSince(startedAt)) }
    var recordCount: Int { sets.filter(\.isRecord).count }

    /// Ejercicios en orden, con sus series.
    var exerciseGroups: [ExerciseGroup] {
        let grouped = Dictionary(grouping: sets, by: \.exerciseKey)
        return grouped.map { key, sets in
            let sorted = sets.sorted { $0.index < $1.index }
            return ExerciseGroup(key: key, name: sorted.first?.exerciseName ?? "", repRange: sorted.first?.repRange ?? "", sets: sorted)
        }
        .sorted { ($0.sets.first?.exerciseOrder ?? 0) < ($1.sets.first?.exerciseOrder ?? 0) }
    }
}

struct ExerciseGroup: Identifiable {
    let key: String
    let name: String
    let repRange: String
    let sets: [WorkoutSet]
    var id: String { key }
}

@Model
final class WorkoutSet {
    var exerciseKey: String = ""
    var exerciseName: String = ""
    var exerciseOrder: Int = 0
    var repRange: String = ""
    var index: Int = 0
    var kg: Double?
    var reps: Int?
    var done: Bool = false
    var isRecord: Bool = false
    var workout: Workout?

    init(exerciseKey: String, exerciseName: String, exerciseOrder: Int, repRange: String, index: Int) {
        self.exerciseKey = exerciseKey; self.exerciseName = exerciseName; self.exerciseOrder = exerciseOrder
        self.repRange = repRange; self.index = index
    }

    var sample: SetSample? {
        guard let kg, let reps, reps > 0 else { return nil }
        return SetSample(kg: kg, reps: reps)
    }
}

enum AtlasSchema {
    static let models: [any PersistentModel.Type] = [
        Profile.self, WeightLog.self, FoodEntry.self, CustomFood.self, WaterLog.self,
        WorkoutTemplate.self, TemplateExercise.self, Workout.self, WorkoutSet.self,
    ]
}
