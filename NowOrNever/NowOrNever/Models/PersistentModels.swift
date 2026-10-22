import Foundation
import SwiftData

// MARK: - Ajustes

@Model
final class UserSettings {
    var kcalTarget: Double = 2300
    var proteinTarget: Double = 180
    var carbsTarget: Double = 250
    var fatTarget: Double = 65
    var stepGoal: Int = 8000

    /// Fecha de inicio del seguimiento. Solo se rellena si el usuario la introduce.
    var trackingStartDate: Date?
    var onboardingCompleted: Bool = false

    var creatineReminderEnabled: Bool = false
    var creatineHour: Int = 9
    var creatineMinute: Int = 0

    var photoReminderEnabled: Bool = false
    var photoReminderHour: Int = 20

    /// Menú seleccionado por defecto para los días sin selección propia.
    var defaultPlanID: UUID?

    /// Configuración de Strava (el client_id es público; el client_secret NUNCA va en la app).
    var stravaClientID: String = ""
    var stravaBackendURL: String = ""

    init() {}
}

// MARK: - Peso

@Model
final class WeightEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var weightKg: Double = 0
    var waistCm: Double?
    var note: String = ""

    init(date: Date, weightKg: Double, waistCm: Double? = nil, note: String = "") {
        self.id = UUID()
        self.date = date
        self.weightKg = weightKg
        self.waistCm = waistCm
        self.note = note
    }
}

// MARK: - Entrenamiento

/// Registro de una sesión en una semana concreta. Clave = semana + sesión,
/// así cada semana empieza con casillas limpias sin borrar las anteriores.
@Model
final class WorkoutSessionLog {
    @Attribute(.unique) var key: String = ""
    var weekStart: Date = Date()
    var sessionID: String = ""
    var isCompleted: Bool = false
    var completedAt: Date?
    var notes: String = ""
    var lastModified: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ExerciseLog.session)
    var exercises: [ExerciseLog] = []

    init(weekStart: Date, sessionID: String) {
        self.weekStart = weekStart
        self.sessionID = sessionID
        self.key = WorkoutSessionLog.makeKey(weekStart: weekStart, sessionID: sessionID)
    }

    static func makeKey(weekStart: Date, sessionID: String) -> String {
        "\(DateUtils.dayKey(weekStart))|\(sessionID)"
    }

    var sortedExercises: [ExerciseLog] { exercises.sorted { $0.order < $1.order } }

    /// Tiene algún dato real introducido por el usuario.
    var hasUserData: Bool {
        isCompleted || exercises.contains { $0.isCompleted || $0.sets.contains { $0.hasData } }
    }
}

@Model
final class ExerciseLog {
    var exerciseID: String = ""
    var order: Int = 0
    var isCompleted: Bool = false
    var session: WorkoutSessionLog?

    @Relationship(deleteRule: .cascade, inverse: \SetLog.exercise)
    var sets: [SetLog] = []

    init(exerciseID: String, order: Int) {
        self.exerciseID = exerciseID
        self.order = order
    }

    var sortedSets: [SetLog] { sets.sorted { $0.index < $1.index } }
}

@Model
final class SetLog {
    var index: Int = 0
    var weightKg: Double?
    var reps: Int?
    var isDone: Bool = false
    var exercise: ExerciseLog?

    init(index: Int) {
        self.index = index
    }

    var hasData: Bool { isDone || weightKg != nil || reps != nil }
}

// MARK: - Nutrición

@Model
final class FoodItem {
    var id: UUID = UUID()
    /// Clave del catálogo de ejemplo (vacía para alimentos creados por el usuario).
    var seedKey: String = ""
    var name: String = ""
    var kcalPer100: Double = 0
    var proteinPer100: Double = 0
    var carbsPer100: Double = 0
    var fatPer100: Double = 0
    /// false si no se dispone de macros fiables (solo kcal).
    var macrosKnown: Bool = true
    var basisRaw: String = WeightBasis.raw.rawValue
    /// Valor provisional: debe revisarse con la etiqueta o una base de datos fiable.
    var isProvisional: Bool = true
    var isUserEdited: Bool = false
    var sourceNote: String = ""

    @Relationship(deleteRule: .nullify, inverse: \MealItem.food)
    var usages: [MealItem] = []

    init(name: String, per100: NutritionValues, basis: WeightBasis, macrosKnown: Bool = true,
         isProvisional: Bool = true, sourceNote: String = "", seedKey: String = "") {
        self.id = UUID()
        self.name = name
        self.kcalPer100 = per100.kcal
        self.proteinPer100 = per100.protein
        self.carbsPer100 = per100.carbs
        self.fatPer100 = per100.fat
        self.basisRaw = basis.rawValue
        self.macrosKnown = macrosKnown
        self.isProvisional = isProvisional
        self.sourceNote = sourceNote
        self.seedKey = seedKey
    }

    var basis: WeightBasis {
        get { WeightBasis(rawValue: basisRaw) ?? .raw }
        set { basisRaw = newValue.rawValue }
    }

    var per100: NutritionValues {
        NutritionValues(kcal: kcalPer100, protein: proteinPer100, carbs: carbsPer100, fat: fatPer100)
    }
}

@Model
final class MenuPlan {
    var id: UUID = UUID()
    var number: Int = 0
    var name: String = ""
    var note: String = ""
    /// Menú de ejemplo: los valores deben revisarse antes de considerarlos definitivos.
    var isExample: Bool = true

    @Relationship(deleteRule: .cascade, inverse: \MealTemplate.plan)
    var meals: [MealTemplate] = []

    init(number: Int, name: String, note: String = "", isExample: Bool = true) {
        self.id = UUID()
        self.number = number
        self.name = name
        self.note = note
        self.isExample = isExample
    }

    var sortedMeals: [MealTemplate] { meals.sorted { $0.mealType.order < $1.mealType.order } }

    func meal(_ type: MealType) -> MealTemplate? { meals.first { $0.mealType == type } }

    var totals: NutritionValues { NutritionMath.sum(meals.map(\.totals)) }

    var hasProvisionalValues: Bool { meals.contains { $0.hasProvisionalValues } }
}

@Model
final class MealTemplate {
    var mealTypeRaw: String = MealType.breakfast.rawValue
    var plan: MenuPlan?

    @Relationship(deleteRule: .cascade, inverse: \MealItem.meal)
    var items: [MealItem] = []

    init(mealType: MealType) {
        self.mealTypeRaw = mealType.rawValue
    }

    var mealType: MealType { MealType(rawValue: mealTypeRaw) ?? .breakfast }

    var sortedItems: [MealItem] { items.sorted { $0.order < $1.order } }

    /// Suma automática de los ingredientes (nunca un total escrito a mano).
    var totals: NutritionValues { NutritionMath.sum(items.map(\.values)) }

    var hasProvisionalValues: Bool { items.contains { $0.food?.isProvisional ?? true } }
}

@Model
final class MealItem {
    var grams: Double = 0
    var order: Int = 0
    var food: FoodItem?
    var meal: MealTemplate?

    init(grams: Double, order: Int, food: FoodItem?) {
        self.grams = grams
        self.order = order
        self.food = food
    }

    var values: NutritionValues {
        guard let food else { return .zero }
        return NutritionMath.values(per100: food.per100, grams: grams)
    }
}

/// Registro de una comida realizada. Guarda una copia de los valores en el momento
/// de marcarla para que el historial no cambie si luego se edita el menú.
@Model
final class MealRecord {
    var dayKey: String = ""
    var date: Date = Date()
    var mealTypeRaw: String = MealType.breakfast.rawValue
    var planName: String = ""
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var completedAt: Date = Date()

    init(date: Date, mealType: MealType, planName: String, values: NutritionValues) {
        self.date = DateUtils.startOfDay(date)
        self.dayKey = DateUtils.dayKey(date)
        self.mealTypeRaw = mealType.rawValue
        self.planName = planName
        self.kcal = values.kcal
        self.protein = values.protein
        self.carbs = values.carbs
        self.fat = values.fat
        self.completedAt = Date()
    }

    var mealType: MealType { MealType(rawValue: mealTypeRaw) ?? .breakfast }
    var values: NutritionValues { NutritionValues(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
}

/// Menú elegido para un día concreto.
@Model
final class DayPlanSelection {
    @Attribute(.unique) var dayKey: String = ""
    var planID: UUID = UUID()

    init(dayKey: String, planID: UUID) {
        self.dayKey = dayKey
        self.planID = planID
    }
}

// MARK: - Fotos de progreso

enum PhotoView: String, Codable, CaseIterable, Identifiable {
    case front, side, back
    var id: String { rawValue }
    var label: String {
        switch self {
        case .front: return "Frente"
        case .side: return "Lateral"
        case .back: return "Espalda"
        }
    }
}

@Model
final class ProgressPhoto {
    /// "yyyy-MM|vista": impide duplicados por mes y vista.
    @Attribute(.unique) var key: String = ""
    var year: Int = 0
    var month: Int = 0
    var viewRaw: String = PhotoView.front.rawValue
    var fileName: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(year: Int, month: Int, view: PhotoView, fileName: String) {
        self.year = year
        self.month = month
        self.viewRaw = view.rawValue
        self.fileName = fileName
        self.key = ProgressPhoto.makeKey(year: year, month: month, view: view)
    }

    static func makeKey(year: Int, month: Int, view: PhotoView) -> String {
        String(format: "%04d-%02d", year, month) + "|" + view.rawValue
    }

    var view: PhotoView { PhotoView(rawValue: viewRaw) ?? .front }
}

// MARK: - Strava

/// Carrera importada desde la API oficial de Strava (solo existe si hay conexión OAuth real).
@Model
final class StravaActivityRecord {
    @Attribute(.unique) var stravaID: Int64 = 0
    var name: String = ""
    var sportType: String = ""
    var startDate: Date = Date()
    var distanceMeters: Double = 0
    var movingTimeSeconds: Int = 0
    var elapsedTimeSeconds: Int = 0
    var elevationGainMeters: Double?
    var importedAt: Date = Date()

    init(stravaID: Int64, name: String, sportType: String, startDate: Date, distanceMeters: Double,
         movingTimeSeconds: Int, elapsedTimeSeconds: Int, elevationGainMeters: Double?) {
        self.stravaID = stravaID
        self.name = name
        self.sportType = sportType
        self.startDate = startDate
        self.distanceMeters = distanceMeters
        self.movingTimeSeconds = movingTimeSeconds
        self.elapsedTimeSeconds = elapsedTimeSeconds
        self.elevationGainMeters = elevationGainMeters
        self.importedAt = Date()
    }

    /// Ritmo medio en segundos por km, calculado con el tiempo en movimiento.
    var paceSecondsPerKm: Double? { RunMath.paceSecondsPerKm(distanceMeters: distanceMeters, seconds: movingTimeSeconds) }
}
