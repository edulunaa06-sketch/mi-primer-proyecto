import Foundation
import SwiftData

/// Operaciones de datos reutilizables. Todas trabajan sobre el ModelContext principal.
enum DataStore {
    static let seedVersionKey = "seedCatalogVersion"

    // MARK: Inicialización

    /// Crea los ajustes si no existen e inserta el catálogo de ejemplo una única vez.
    /// Nunca sobrescribe datos existentes del usuario.
    @MainActor
    static func bootstrap(_ context: ModelContext) {
        _ = settings(context)

        let defaults = UserDefaults.standard
        let alreadySeeded = defaults.integer(forKey: seedVersionKey) > 0
        let existingFoods = (try? context.fetchCount(FetchDescriptor<FoodItem>())) ?? 0
        guard !alreadySeeded, existingFoods == 0 else { return }

        do {
            let catalog = try SeedCatalog.loadFromBundle()
            seed(catalog, into: context)
            try context.save()
            defaults.set(catalog.version, forKey: seedVersionKey)
        } catch {
            print("[NowOrNever] No se pudo cargar el catálogo de ejemplo: \(error)")
        }
    }

    @MainActor
    static func seed(_ catalog: SeedCatalog, into context: ModelContext) {
        var foodsByKey: [String: FoodItem] = [:]
        for food in catalog.foods {
            let item = FoodItem(
                name: food.name,
                per100: food.per100,
                basis: WeightBasis(rawValue: food.basis) ?? .raw,
                macrosKnown: food.macrosKnown,
                isProvisional: food.provisional,
                sourceNote: food.source,
                seedKey: food.key
            )
            context.insert(item)
            foodsByKey[food.key] = item
        }
        var firstPlan: MenuPlan?
        for menu in catalog.menus {
            let plan = MenuPlan(number: menu.number, name: menu.name, note: menu.note, isExample: true)
            context.insert(plan)
            for meal in menu.meals {
                guard let type = MealType(rawValue: meal.type) else { continue }
                let template = MealTemplate(mealType: type)
                context.insert(template)
                template.plan = plan
                for (index, entry) in meal.items.enumerated() {
                    let item = MealItem(grams: entry.grams, order: index, food: foodsByKey[entry.food])
                    context.insert(item)
                    item.meal = template
                }
            }
            if firstPlan == nil { firstPlan = plan }
        }
        let s = settings(context)
        if s.defaultPlanID == nil { s.defaultPlanID = firstPlan?.id }
    }

    @MainActor
    @discardableResult
    static func settings(_ context: ModelContext) -> UserSettings {
        if let existing = try? context.fetch(FetchDescriptor<UserSettings>()).first {
            return existing
        }
        let s = UserSettings()
        context.insert(s)
        try? context.save()
        return s
    }

    // MARK: Entrenamiento

    @MainActor
    static func sessionLog(for session: SessionDefinition, weekStart: Date, in context: ModelContext) -> WorkoutSessionLog? {
        let key = WorkoutSessionLog.makeKey(weekStart: weekStart, sessionID: session.id)
        var descriptor = FetchDescriptor<WorkoutSessionLog>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Devuelve el registro de la semana o lo crea vacío (sin nada marcado).
    @MainActor
    static func fetchOrCreateLog(for session: SessionDefinition, weekStart: Date, in context: ModelContext) -> WorkoutSessionLog {
        if let existing = sessionLog(for: session, weekStart: weekStart, in: context) {
            ensureStructure(existing, session: session, in: context)
            return existing
        }
        let log = WorkoutSessionLog(weekStart: weekStart, sessionID: session.id)
        context.insert(log)
        ensureStructure(log, session: session, in: context)
        try? context.save()
        return log
    }

    /// Garantiza que existe un ExerciseLog por ejercicio y un SetLog por serie prescrita.
    @MainActor
    static func ensureStructure(_ log: WorkoutSessionLog, session: SessionDefinition, in context: ModelContext) {
        for (order, exercise) in session.exercises.enumerated() {
            let exLog: ExerciseLog
            if let found = log.exercises.first(where: { $0.exerciseID == exercise.id }) {
                exLog = found
            } else {
                exLog = ExerciseLog(exerciseID: exercise.id, order: order)
                context.insert(exLog)
                exLog.session = log
            }
            let existing = Set(exLog.sets.map(\.index))
            for index in 0..<exercise.sets where !existing.contains(index) {
                let set = SetLog(index: index)
                context.insert(set)
                set.exercise = exLog
            }
        }
    }

    /// Última sesión anterior con datos reales del usuario.
    @MainActor
    static func previousLog(for session: SessionDefinition, before weekStart: Date, in context: ModelContext) -> WorkoutSessionLog? {
        let sessionID = session.id
        let descriptor = FetchDescriptor<WorkoutSessionLog>(
            predicate: #Predicate { $0.sessionID == sessionID && $0.weekStart < weekStart },
            sortBy: [SortDescriptor(\.weekStart, order: .reverse)]
        )
        let logs = (try? context.fetch(descriptor)) ?? []
        return logs.first { $0.hasUserData }
    }

    // MARK: Nutrición

    @MainActor
    static func plan(for date: Date, plans: [MenuPlan], selections: [DayPlanSelection], settings: UserSettings?) -> MenuPlan? {
        let key = DateUtils.dayKey(date)
        if let sel = selections.first(where: { $0.dayKey == key }),
           let plan = plans.first(where: { $0.id == sel.planID }) {
            return plan
        }
        if let id = settings?.defaultPlanID, let plan = plans.first(where: { $0.id == id }) {
            return plan
        }
        return plans.sorted { $0.number < $1.number }.first
    }

    @MainActor
    static func select(plan: MenuPlan, for date: Date, in context: ModelContext) {
        let key = DateUtils.dayKey(date)
        var descriptor = FetchDescriptor<DayPlanSelection>(predicate: #Predicate { $0.dayKey == key })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.planID = plan.id
        } else {
            context.insert(DayPlanSelection(dayKey: key, planID: plan.id))
        }
        try? context.save()
    }

    /// Marca o desmarca una comida del día. Al marcar se guarda una copia de sus valores.
    @MainActor
    static func setMeal(_ meal: MealTemplate, planName: String, completed: Bool, on date: Date, in context: ModelContext) {
        let key = DateUtils.dayKey(date)
        let typeRaw = meal.mealTypeRaw
        let descriptor = FetchDescriptor<MealRecord>(predicate: #Predicate { $0.dayKey == key && $0.mealTypeRaw == typeRaw })
        let existing = (try? context.fetch(descriptor)) ?? []
        if completed {
            if existing.isEmpty {
                context.insert(MealRecord(date: date, mealType: meal.mealType, planName: planName, values: meal.totals))
            }
        } else {
            existing.forEach { context.delete($0) }
        }
        try? context.save()
    }

    // MARK: Peso

    /// Añade un pesaje evitando duplicar exactamente el mismo valor en el mismo día.
    @MainActor
    @discardableResult
    static func addWeight(_ kg: Double, waist: Double?, date: Date, in context: ModelContext) -> Bool {
        let start = DateUtils.startOfDay(date)
        guard let end = DateUtils.calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        let descriptor = FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.date >= start && $0.date < end })
        let sameDay = (try? context.fetch(descriptor)) ?? []
        if sameDay.contains(where: { abs($0.weightKg - kg) < 0.001 && $0.waistCm == waist }) {
            return false
        }
        context.insert(WeightEntry(date: date, weightKg: kg, waistCm: waist))
        try? context.save()
        return true
    }
}
