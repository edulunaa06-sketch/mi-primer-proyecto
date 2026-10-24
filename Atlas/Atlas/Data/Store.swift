import Foundation
import SwiftData

/// Catálogo de alimentos, menús e ideas de platos (de SeedCatalog.json, solo lectura).
final class Catalog {
    static let shared = Catalog()

    struct Food: Identifiable, Hashable {
        let id: String
        let name: String
        let per100: NutritionValues
        let basis: String
    }

    let foods: [Food]
    let menus: [SeedCatalog.Menu]
    let ideas: [SeedCatalog.Idea]
    private let byKey: [String: Food]

    private init() {
        let catalog = try? SeedCatalog.loadFromBundle()
        foods = (catalog?.foods ?? []).map { Food(id: $0.key, name: $0.name, per100: $0.per100, basis: $0.basis) }
        menus = catalog?.menus ?? []
        ideas = catalog?.ideas ?? []
        byKey = Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })
    }

    func food(_ key: String) -> Food? { byKey[key] }

    /// Ingredientes de un plato (comida de un menú o idea) con sus valores por 100 g.
    func items(_ items: [SeedCatalog.Item]) -> [(food: Food, grams: Double)] {
        items.compactMap { i in byKey[i.food].map { ($0, i.grams) } }
    }

    func values(_ items: [SeedCatalog.Item], factor: Double = 1) -> NutritionValues {
        NutritionMath.sum(self.items(items).map { $0.food.per100.scaled(toGrams: MealPlanner.grams($0.grams, factor: factor)) })
    }
}

/// Un plato que se puede añadir al diario: comida de un menú o idea suelta.
struct Dish: Identifiable, Hashable {
    let id: String
    let name: String
    let meal: MealType
    let items: [SeedCatalog.Item]
    let source: String

    static func == (a: Dish, b: Dish) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    static var all: [Dish] {
        let c = Catalog.shared
        var result: [Dish] = []
        for menu in c.menus {
            for meal in menu.meals {
                guard let type = MealType(rawValue: meal.type) else { continue }
                let names = c.items(meal.items).map(\.food.name)
                result.append(Dish(id: "menu-\(menu.number)-\(meal.type)", name: names.prefix(3).joined(separator: ", "),
                                   meal: type, items: meal.items, source: "Menú \(menu.number) · \(menu.name)"))
            }
        }
        for (i, idea) in c.ideas.enumerated() {
            guard let type = MealType(rawValue: idea.type) else { continue }
            result.append(Dish(id: "idea-\(i)", name: idea.name, meal: type, items: idea.items, source: "Idea de plato"))
        }
        return result
    }
}

@MainActor
enum Store {
    // MARK: Perfil

    static func profile(_ context: ModelContext) -> Profile {
        if let p = try? context.fetch(FetchDescriptor<Profile>()).first { return p }
        let p = Profile()
        context.insert(p)
        try? context.save()
        return p
    }

    static func latestWeight(_ context: ModelContext) -> WeightLog? {
        var d = FetchDescriptor<WeightLog>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// Un pesaje por día: si ya hay uno hoy, se sustituye.
    static func logWeight(_ kg: Double, date: Date = Date(), in context: ModelContext) {
        let start = DateUtils.startOfDay(date)
        let end = start.addingTimeInterval(86400)
        let sameDay = (try? context.fetch(FetchDescriptor<WeightLog>(predicate: #Predicate { $0.date >= start && $0.date < end }))) ?? []
        sameDay.forEach(context.delete)
        context.insert(WeightLog(date: date, kg: kg))
        let p = profile(context)
        p.recalculate(weightKg: kg)
        try? context.save()
    }

    // MARK: Comida

    static func entries(_ dayKey: String, in context: ModelContext) -> [FoodEntry] {
        (try? context.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.dayKey == dayKey },
                                                        sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    static func addFood(name: String, per100: NutritionValues?, grams: Double, quick: NutritionValues? = nil,
                        meal: MealType, dayKey: String, foodKey: String, in context: ModelContext) {
        let values = quick ?? per100?.scaled(toGrams: grams) ?? .zero
        context.insert(FoodEntry(dayKey: dayKey, meal: meal, name: name, grams: grams, per100: per100, values: values, foodKey: foodKey))
        try? context.save()
    }

    /// Añade un plato (de un menú o idea) ajustado con `factor` a la comida elegida.
    static func addDish(_ dish: Dish, factor: Double, meal: MealType, dayKey: String, in context: ModelContext) {
        for (food, grams) in Catalog.shared.items(dish.items) {
            let g = MealPlanner.grams(grams, factor: factor)
            context.insert(FoodEntry(dayKey: dayKey, meal: meal, name: food.name, grams: g, per100: food.per100,
                                     values: food.per100.scaled(toGrams: g), foodKey: food.id))
        }
        try? context.save()
    }

    /// Copia las comidas de un día a otro (p. ej. «repetir ayer»).
    static func copyDay(from source: String, to target: String, in context: ModelContext) -> Int {
        let list = entries(source, in: context)
        for e in list {
            let copy = FoodEntry(dayKey: target, meal: e.meal, name: e.name, grams: e.grams, per100: e.per100, values: e.values, foodKey: e.foodKey)
            context.insert(copy)
        }
        try? context.save()
        return list.count
    }

    /// Alimentos usados recientemente (para apuntar en dos toques).
    static func recentFoods(limit: Int = 12, in context: ModelContext) -> [FoodEntry] {
        var d = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        d.fetchLimit = 200
        var seen = Set<String>()
        return ((try? context.fetch(d)) ?? []).filter { !$0.foodKey.isEmpty && seen.insert($0.foodKey).inserted }.prefix(limit).map { $0 }
    }

    /// kcal por día registradas (para el gasto real estimado).
    static func dailyIntake(days: Int = 35, in context: ModelContext) -> [(day: Date, kcal: Double)] {
        let all = (try? context.fetch(FetchDescriptor<FoodEntry>())) ?? []
        let byDay = Dictionary(grouping: all, by: \.dayKey)
        let from = Date().addingTimeInterval(-Double(days) * 86400)
        return byDay.compactMap { key, entries in
            guard let d = DateUtils.date(fromDayKey: key), d >= from, !DateUtils.calendar.isDateInToday(d) else { return nil }
            return (d, entries.reduce(0) { $0 + $1.kcal })
        }
    }

    static func water(_ dayKey: String, in context: ModelContext) -> WaterLog {
        if let w = try? context.fetch(FetchDescriptor<WaterLog>(predicate: #Predicate { $0.dayKey == dayKey })).first { return w }
        let w = WaterLog(dayKey: dayKey, ml: 0)
        context.insert(w)
        return w
    }

    // MARK: Rutina

    /// La primera vez se crea tu rutina de siempre (la de Now or Never) como plantillas editables.
    static func seedTemplatesIfNeeded(_ context: ModelContext) {
        guard ((try? context.fetchCount(FetchDescriptor<WorkoutTemplate>())) ?? 0) == 0 else { return }
        for (i, s) in WeeklyRoutine.allSessions.enumerated() {
            let t = WorkoutTemplate(name: s.title, kind: s.kind, weekday: s.weekday, detail: s.detail, seedID: s.id, order: i)
            context.insert(t)
            for (j, e) in s.exercises.enumerated() {
                let ex = TemplateExercise(key: e.id, name: e.name, sets: e.sets, repRange: e.repRange, order: j)
                context.insert(ex)
                ex.template = t
            }
        }
        try? context.save()
    }

    static func templates(_ context: ModelContext) -> [WorkoutTemplate] {
        (try? context.fetch(FetchDescriptor<WorkoutTemplate>(sortBy: [SortDescriptor(\.order)]))) ?? []
    }

    // MARK: Entrenos

    static func finishedWorkouts(in context: ModelContext) -> [Workout] {
        (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.finishedAt != nil },
                                                     sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))) ?? []
    }

    /// Empieza un entreno desde una plantilla (o vacío). Las series empiezan sin datos: se rellenan al entrenar.
    static func startWorkout(from template: WorkoutTemplate?, in context: ModelContext) -> Workout {
        let w = Workout(name: template?.name ?? "Entreno libre", kind: template?.kind ?? .strength, templateID: template?.id)
        context.insert(w)
        for (order, ex) in (template?.sortedExercises ?? []).enumerated() {
            addExercise(key: ex.key, name: ex.name, sets: ex.sets, repRange: ex.repRange, order: order, to: w, in: context)
        }
        try? context.save()
        return w
    }

    static func addExercise(key: String, name: String, sets: Int, repRange: String, order: Int? = nil, to w: Workout, in context: ModelContext) {
        let o = order ?? ((w.sets.map(\.exerciseOrder).max() ?? -1) + 1)
        for i in 0..<max(sets, 1) {
            let s = WorkoutSet(exerciseKey: key, exerciseName: name, exerciseOrder: o, repRange: repRange, index: i)
            context.insert(s)
            s.workout = w
        }
    }

    static func addSet(toExercise key: String, in w: Workout, context: ModelContext) {
        let existing = w.sets.filter { $0.exerciseKey == key }
        guard let last = existing.max(by: { $0.index < $1.index }) else { return }
        let s = WorkoutSet(exerciseKey: key, exerciseName: last.exerciseName, exerciseOrder: last.exerciseOrder, repRange: last.repRange, index: last.index + 1)
        s.kg = last.kg
        s.reps = last.reps
        context.insert(s)
        s.workout = w
    }

    /// Series de la última vez que hiciste este ejercicio (sin contar el entreno actual).
    static func lastPerformance(_ key: String, excluding current: Workout?, in context: ModelContext) -> [SetSample] {
        let sets = (try? context.fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.exerciseKey == key && $0.done }))) ?? []
        let currentID = current?.persistentModelID
        let byWorkout = Dictionary(grouping: sets.filter { $0.workout?.persistentModelID != currentID && $0.workout?.finishedAt != nil },
                                   by: { $0.workout!.persistentModelID })
        guard let latest = byWorkout.values.max(by: { ($0.first?.workout?.startedAt ?? .distantPast) < ($1.first?.workout?.startedAt ?? .distantPast) })
        else { return [] }
        return latest.sorted { $0.index < $1.index }.compactMap(\.sample)
    }

    /// Mejor 1RM estimado histórico del ejercicio (sin contar el entreno actual).
    static func bestE1RM(_ key: String, excluding current: Workout?, in context: ModelContext) -> Double {
        let sets = (try? context.fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.exerciseKey == key && $0.done }))) ?? []
        let currentID = current?.persistentModelID
        return PersonalRecords.best(sets.filter { $0.workout?.persistentModelID != currentID }.compactMap(\.sample))
    }

    static func finish(_ w: Workout, in context: ModelContext) {
        // Las series vacías no se guardan.
        for s in w.sets where !s.done && s.kg == nil && s.reps == nil { context.delete(s) }
        w.finishedAt = Date()
        try? context.save()
    }

    static func discard(_ w: Workout, in context: ModelContext) {
        context.delete(w)
        try? context.save()
    }

    /// Marca una sesión como hecha sin apuntar series (o una carrera con su distancia y tiempo).
    static func quickComplete(_ t: WorkoutTemplate, meters: Double = 0, seconds: Int = 0, date: Date = Date(), in context: ModelContext) {
        let w = Workout(name: t.name, kind: t.kind, templateID: t.id, startedAt: date.addingTimeInterval(-Double(max(seconds, 60))))
        w.runMeters = meters
        w.runSeconds = seconds
        w.finishedAt = date
        context.insert(w)
        try? context.save()
    }

    static func logRun(meters: Double, seconds: Int, date: Date = Date(), template: WorkoutTemplate?, in context: ModelContext) {
        let w = Workout(name: template?.name ?? "Carrera", kind: .run, templateID: template?.id, startedAt: date.addingTimeInterval(-Double(seconds)))
        w.runMeters = meters
        w.runSeconds = seconds
        w.finishedAt = date
        context.insert(w)
        try? context.save()
    }

    /// Entrenos hechos esta semana de una plantilla.
    static func doneThisWeek(_ t: WorkoutTemplate, workouts: [Workout]) -> Workout? {
        let start = DateUtils.startOfWeek(Date())
        return workouts.first { $0.templateID == t.id && $0.isFinished && $0.startedAt >= start }
    }

    // MARK: Borrar todo

    static func eraseAll(_ context: ModelContext) {
        try? context.delete(model: WorkoutSet.self)
        try? context.delete(model: Workout.self)
        try? context.delete(model: TemplateExercise.self)
        try? context.delete(model: WorkoutTemplate.self)
        try? context.delete(model: FoodEntry.self)
        try? context.delete(model: CustomFood.self)
        try? context.delete(model: WaterLog.self)
        try? context.delete(model: WeightLog.self)
        try? context.delete(model: Profile.self)
        try? context.save()
    }
}
