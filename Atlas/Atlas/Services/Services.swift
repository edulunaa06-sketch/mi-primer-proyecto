import Foundation
import SwiftData
import UIKit
import UniformTypeIdentifiers
import SwiftUI
import UserNotifications

// MARK: - Fotos de progreso (archivos dentro de la app)

enum PhotoFiles {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Guarda la foto reducida (lado largo 1600 px, JPEG 0,8) y devuelve el nombre del archivo.
    static func save(_ image: UIImage) -> String? {
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = resized.jpegData(compressionQuality: 0.8) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do { try data.write(to: folder.appendingPathComponent(name), options: .completeFileProtection) } catch { return nil }
        return name
    }

    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let img = UIImage(contentsOfFile: folder.appendingPathComponent(name).path) else { return nil }
        cache.setObject(img, forKey: name as NSString)
        return img
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
    }
}

// MARK: - Recordatorios

enum Reminders {
    enum Kind: String, CaseIterable {
        case weighIn, dinner, workout, creatine
        var id: String { "atlas.reminder." + rawValue }
        var title: String {
            switch self {
            case .weighIn: return "Pésate"
            case .dinner: return "¿Has apuntado lo de hoy?"
            case .workout: return "Hoy toca entrenar"
            case .creatine: return "Creatina"
            }
        }
        var body: String {
            switch self {
            case .weighIn: return "En ayunas y después del baño. 10 segundos y tu tendencia sigue al día."
            case .dinner: return "Apunta la cena ahora y mañana sabrás exactamente cómo vas."
            case .workout: return "Tu sesión de hoy te está esperando en ATLAS."
            case .creatine: return "3–5 g, todos los días, también en descanso."
            }
        }
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Programa (o quita) un recordatorio diario a la hora dada en minutos desde las 00:00 (-1 = quitar).
    static func set(_ kind: Kind, minutes: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [kind.id])
        guard minutes >= 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = kind.title
        content.body = kind.body
        content.sound = .default
        var comps = DateComponents()
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        center.add(UNNotificationRequest(identifier: kind.id, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)))
    }
}

// MARK: - Copia de seguridad

/// Todo ATLAS en un archivo JSON que puedes guardar en Archivos/iCloud y volver a cargar.
struct AtlasBackup: Codable {
    var version = 1
    var exportedAt = Date()
    var profile: ProfileDTO?
    var weights: [WeightDTO] = []
    var foods: [FoodDTO] = []
    var customFoods: [CustomFoodDTO] = []
    var water: [WaterDTO] = []
    var templates: [TemplateDTO] = []
    var workouts: [WorkoutDTO] = []
    var checkIns: [CheckInDTO] = []
    var savedMeals: [SavedMealDTO] = []

    struct ProfileDTO: Codable {
        var name: String, sexRaw: String, age: Int, heightCm: Double, activityRaw: String, goalRaw: String
        var kcal: Double, protein: Double, carbs: Double, fat: Double, manual: Bool, margin: Double
        var stepGoal: Int, waterGoal: Int
    }
    struct WeightDTO: Codable { var date: Date, kg: Double, waist: Double }
    struct FoodDTO: Codable {
        var dayKey: String, meal: String, name: String, grams: Double, foodKey: String
        var values: NutritionValues, per100: NutritionValues?, createdAt: Date
    }
    struct CustomFoodDTO: Codable { var name: String, per100: NutritionValues }
    struct WaterDTO: Codable { var dayKey: String, ml: Int }
    struct TemplateDTO: Codable {
        var id: UUID, seedID: String, name: String, kind: String, weekday: Int, detail: String, order: Int
        var exercises: [ExerciseDTO]
    }
    struct ExerciseDTO: Codable { var key: String, name: String, sets: Int, repRange: String, order: Int }
    struct WorkoutDTO: Codable {
        var templateID: UUID?, name: String, kind: String, startedAt: Date, finishedAt: Date?
        var runMeters: Double, runSeconds: Int, stravaID: Int64, sets: [SetDTO]
    }
    struct SetDTO: Codable {
        var key: String, name: String, order: Int, repRange: String, index: Int, kg: Double?, reps: Int?, done: Bool, record: Bool
    }
    struct CheckInDTO: Codable { var dayKey: String, sleep: Double, energy: Int, soreness: Int }
    struct SavedMealDTO: Codable { var name: String, items: [SavedMeal.Item] }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

@MainActor
enum BackupService {
    static func make(_ context: ModelContext) -> AtlasBackup {
        func all<T: PersistentModel>(_: T.Type) -> [T] { (try? context.fetch(FetchDescriptor<T>())) ?? [] }
        var b = AtlasBackup()
        if let p = all(Profile.self).first {
            b.profile = .init(name: p.name, sexRaw: p.sexRaw, age: p.age, heightCm: p.heightCm, activityRaw: p.activityRaw, goalRaw: p.goalRaw,
                              kcal: p.kcalTarget, protein: p.proteinTarget, carbs: p.carbsTarget, fat: p.fatTarget,
                              manual: p.manualTargets, margin: p.kcalMargin, stepGoal: p.stepGoal, waterGoal: p.waterGoalMl)
        }
        b.weights = all(WeightLog.self).map { .init(date: $0.date, kg: $0.kg, waist: $0.waistCm) }
        b.foods = all(FoodEntry.self).map { .init(dayKey: $0.dayKey, meal: $0.mealRaw, name: $0.name, grams: $0.grams, foodKey: $0.foodKey,
                                                  values: $0.values, per100: $0.per100, createdAt: $0.createdAt) }
        b.customFoods = all(CustomFood.self).map { .init(name: $0.name, per100: $0.per100) }
        b.water = all(WaterLog.self).map { .init(dayKey: $0.dayKey, ml: $0.ml) }
        b.templates = all(WorkoutTemplate.self).map { t in
            .init(id: t.id, seedID: t.seedID, name: t.name, kind: t.kindRaw, weekday: t.weekday, detail: t.detail, order: t.order,
                  exercises: t.sortedExercises.map { .init(key: $0.key, name: $0.name, sets: $0.sets, repRange: $0.repRange, order: $0.order) })
        }
        b.workouts = all(Workout.self).filter(\.isFinished).map { w in
            .init(templateID: w.templateID, name: w.name, kind: w.kindRaw, startedAt: w.startedAt, finishedAt: w.finishedAt,
                  runMeters: w.runMeters, runSeconds: w.runSeconds, stravaID: w.stravaID,
                  sets: w.sets.map { .init(key: $0.exerciseKey, name: $0.exerciseName, order: $0.exerciseOrder, repRange: $0.repRange,
                                           index: $0.index, kg: $0.kg, reps: $0.reps, done: $0.done, record: $0.isRecord) })
        }
        b.checkIns = all(CheckIn.self).map { .init(dayKey: $0.dayKey, sleep: $0.sleepHours, energy: $0.energy, soreness: $0.soreness) }
        b.savedMeals = all(SavedMeal.self).map { .init(name: $0.name, items: $0.items) }
        return b
    }

    /// Sustituye todos los datos por los de la copia (las fotos no van en la copia y se conservan).
    static func restore(_ b: AtlasBackup, into context: ModelContext) {
        try? context.delete(model: WorkoutSet.self)
        try? context.delete(model: Workout.self)
        try? context.delete(model: TemplateExercise.self)
        try? context.delete(model: WorkoutTemplate.self)
        try? context.delete(model: FoodEntry.self)
        try? context.delete(model: CustomFood.self)
        try? context.delete(model: WaterLog.self)
        try? context.delete(model: WeightLog.self)
        try? context.delete(model: CheckIn.self)
        try? context.delete(model: SavedMeal.self)
        let p = Store.profile(context)
        if let d = b.profile {
            p.name = d.name; p.sexRaw = d.sexRaw; p.age = d.age; p.heightCm = d.heightCm; p.activityRaw = d.activityRaw; p.goalRaw = d.goalRaw
            p.kcalTarget = d.kcal; p.proteinTarget = d.protein; p.carbsTarget = d.carbs; p.fatTarget = d.fat
            p.manualTargets = d.manual; p.kcalMargin = d.margin; p.stepGoal = d.stepGoal; p.waterGoalMl = d.waterGoal
            p.onboarded = true
        }
        for w in b.weights { context.insert(WeightLog(date: w.date, kg: w.kg, waistCm: w.waist)) }
        for f in b.foods {
            let e = FoodEntry(dayKey: f.dayKey, meal: MealType(rawValue: f.meal) ?? .snack, name: f.name, grams: f.grams,
                              per100: f.per100, values: f.values, foodKey: f.foodKey)
            e.createdAt = f.createdAt
            context.insert(e)
        }
        for c in b.customFoods { context.insert(CustomFood(name: c.name, per100: c.per100)) }
        for w in b.water { context.insert(WaterLog(dayKey: w.dayKey, ml: w.ml)) }
        for t in b.templates {
            let tpl = WorkoutTemplate(name: t.name, kind: SessionKind(rawValue: t.kind) ?? .strength, weekday: t.weekday,
                                      detail: t.detail, seedID: t.seedID, order: t.order)
            tpl.id = t.id
            context.insert(tpl)
            for e in t.exercises {
                let ex = TemplateExercise(key: e.key, name: e.name, sets: e.sets, repRange: e.repRange, order: e.order)
                context.insert(ex)
                ex.template = tpl
            }
        }
        for w in b.workouts {
            let wk = Workout(name: w.name, kind: SessionKind(rawValue: w.kind) ?? .strength, templateID: w.templateID, startedAt: w.startedAt)
            wk.finishedAt = w.finishedAt; wk.runMeters = w.runMeters; wk.runSeconds = w.runSeconds; wk.stravaID = w.stravaID
            context.insert(wk)
            for s in w.sets {
                let set = WorkoutSet(exerciseKey: s.key, exerciseName: s.name, exerciseOrder: s.order, repRange: s.repRange, index: s.index)
                set.kg = s.kg; set.reps = s.reps; set.done = s.done; set.isRecord = s.record
                context.insert(set)
                set.workout = wk
            }
        }
        for c in b.checkIns { context.insert(CheckIn(dayKey: c.dayKey, sleepHours: c.sleep, energy: c.energy, soreness: c.soreness)) }
        for m in b.savedMeals { context.insert(SavedMeal(name: m.name, items: m.items)) }
        try? context.save()
    }
}

/// Documento para exportar/importar la copia con los diálogos de Archivos de iOS.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let d = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = d
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
