import Foundation
import SwiftData

/// Operaciones de datos reutilizables. Todas trabajan sobre el ModelContext principal.
enum DataStore {
    static let seedVersionKey = "seedCatalogVersion"
    static let routineSeededKey = "routineSeeded"

    // MARK: Inicialización

    /// Crea los ajustes si no existen e inserta el catálogo de ejemplo una única vez.
    /// Nunca sobrescribe datos existentes del usuario.
    @MainActor
    static func bootstrap(_ context: ModelContext) {
        _ = settings(context)
        seedRoutineIfNeeded(context)

        seedCatalogIfNeeded(context, defaults: .standard)
    }

    /// Primera vez: inserta alimentos, 9 menús e ideas. Versiones posteriores del catálogo:
    /// solo AÑADE lo nuevo (alimentos e ideas que falten), sin tocar lo que el usuario ya tiene o editó.
    @MainActor
    static func seedCatalogIfNeeded(_ context: ModelContext, defaults: UserDefaults, catalog provided: SeedCatalog? = nil) {
        let stored = defaults.integer(forKey: seedVersionKey)
        let existingFoods = (try? context.fetchCount(FetchDescriptor<FoodItem>())) ?? 0
        do {
            let catalog = try provided ?? SeedCatalog.loadFromBundle()
            if stored == 0 && existingFoods == 0 {
                seed(catalog, into: context)
            } else if stored < catalog.version {
                addMissingFoodsAndIdeas(catalog, into: context)
            } else {
                return
            }
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
        insertIdeas(catalog, foodsByKey: foodsByKey, into: context)
    }

    /// Actualización del catálogo para quien ya tenía la app: añade alimentos e ideas nuevos.
    @MainActor
    static func addMissingFoodsAndIdeas(_ catalog: SeedCatalog, into context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<FoodItem>())) ?? []
        var foodsByKey = Dictionary(existing.filter { !$0.seedKey.isEmpty }.map { ($0.seedKey, $0) }, uniquingKeysWith: { a, _ in a })
        for food in catalog.foods where foodsByKey[food.key] == nil {
            let item = FoodItem(name: food.name, per100: food.per100, basis: WeightBasis(rawValue: food.basis) ?? .raw,
                                macrosKnown: food.macrosKnown, isProvisional: food.provisional,
                                sourceNote: food.source, seedKey: food.key)
            context.insert(item)
            foodsByKey[food.key] = item
        }
        let hasIdeas = ((try? context.fetch(FetchDescriptor<MenuPlan>(predicate: #Predicate { $0.isLibrary }))) ?? []).isEmpty == false
        if !hasIdeas { insertIdeas(catalog, foodsByKey: foodsByKey, into: context) }
    }

    /// Cada idea se guarda como un "menú" de biblioteca con una sola comida (editable como cualquier menú).
    @MainActor
    private static func insertIdeas(_ catalog: SeedCatalog, foodsByKey: [String: FoodItem], into context: ModelContext) {
        for (index, idea) in catalog.ideas.enumerated() {
            guard let type = MealType(rawValue: idea.type) else { continue }
            let plan = MenuPlan(number: 100 + index, name: idea.name, note: "Idea de \(type.label.lowercased()) con pesos exactos.", isExample: true)
            plan.isLibrary = true
            context.insert(plan)
            let template = MealTemplate(mealType: type)
            context.insert(template)
            template.plan = plan
            for (order, entry) in idea.items.enumerated() {
                let item = MealItem(grams: entry.grams, order: order, food: foodsByKey[entry.food])
                context.insert(item)
                item.meal = template
            }
        }
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

    // MARK: Rutina personalizable

    /// Copia la rutina predeterminada a la base de datos una sola vez (no sobrescribe cambios).
    @MainActor
    static func seedRoutineIfNeeded(_ context: ModelContext, defaults: UserDefaults = .standard) {
        let existing = (try? context.fetchCount(FetchDescriptor<RoutineExercise>())) ?? 0
        guard !defaults.bool(forKey: routineSeededKey), existing == 0 else { return }
        for session in WeeklyRoutine.allSessions where session.kind == .strength {
            insertDefaults(for: session, in: context)
        }
        try? context.save()
        defaults.set(true, forKey: routineSeededKey)
    }

    @MainActor
    private static func insertDefaults(for session: SessionDefinition, in context: ModelContext) {
        for (order, ex) in session.exercises.enumerated() {
            let range = ExerciseDefinition.parseRange(ex.repRange) ?? (8, 12)
            context.insert(RoutineExercise(exerciseID: ex.id, sessionID: session.id, name: ex.name,
                                           sets: ex.sets, repMin: range.min, repMax: range.max, order: order))
        }
    }

    @MainActor
    static func routine(for sessionID: String, in context: ModelContext) -> [RoutineExercise] {
        let descriptor = FetchDescriptor<RoutineExercise>(
            predicate: #Predicate { $0.sessionID == sessionID },
            sortBy: [SortDescriptor(\.order)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @MainActor
    static func addExercise(to sessionID: String, name: String, sets: Int, repMin: Int, repMax: Int, in context: ModelContext) {
        let current = routine(for: sessionID, in: context)
        let ex = RoutineExercise(exerciseID: "custom-\(UUID().uuidString.lowercased())", sessionID: sessionID,
                                 name: name, sets: sets, repMin: repMin, repMax: repMax,
                                 order: (current.map(\.order).max() ?? -1) + 1)
        context.insert(ex)
        try? context.save()
    }

    /// Sustituir = ejercicio nuevo en la misma posición (ID nuevo: su progresión empieza de cero
    /// y el historial del ejercicio anterior se conserva).
    @MainActor
    static func substitute(_ exercise: RoutineExercise, withName name: String, in context: ModelContext) {
        let replacement = RoutineExercise(exerciseID: "custom-\(UUID().uuidString.lowercased())", sessionID: exercise.sessionID,
                                          name: name, sets: exercise.sets, repMin: exercise.repMin,
                                          repMax: exercise.repMax, order: exercise.order)
        context.delete(exercise)
        context.insert(replacement)
        try? context.save()
    }

    /// Elimina el ejercicio de la rutina. Los registros de semanas pasadas NO se borran.
    @MainActor
    static func removeExercise(_ exercise: RoutineExercise, in context: ModelContext) {
        let sessionID = exercise.sessionID
        context.delete(exercise)
        renumber(sessionID, in: context)
    }

    @MainActor
    static func moveExercises(in sessionID: String, from source: IndexSet, to destination: Int, in context: ModelContext) {
        var items = routine(for: sessionID, in: context)
        items.move(fromOffsets: source, toOffset: destination)
        for (i, item) in items.enumerated() { item.order = i }
        try? context.save()
    }

    @MainActor
    private static func renumber(_ sessionID: String, in context: ModelContext) {
        for (i, item) in routine(for: sessionID, in: context).enumerated() { item.order = i }
        try? context.save()
    }

    /// Vuelve a la rutina predeterminada de esa sesión (el historial no se toca).
    @MainActor
    static func restoreDefaultRoutine(for session: SessionDefinition, in context: ModelContext) {
        guard let base = WeeklyRoutine.session(id: session.id) else { return }
        routine(for: session.id, in: context).forEach { context.delete($0) }
        try? context.save()
        insertDefaults(for: base, in: context)
        try? context.save()
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
    /// `session` debe ser la sesión ya resuelta con la rutina personalizada.
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
            // Instantánea de la prescripción vigente esta semana.
            exLog.order = order
            exLog.name = exercise.name
            exLog.targetSets = exercise.sets
            exLog.repRange = exercise.repRange
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
        if let id = settings?.defaultPlanID, let plan = plans.first(where: { $0.id == id && !$0.isLibrary }) {
            return plan
        }
        return plans.filter { !$0.isLibrary }.sorted { $0.number < $1.number }.first
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

    // MARK: Comidas a elegir

    /// Las cuatro comidas del día: la elegida por el usuario o, si no hay, la del menú del día.
    @MainActor
    static func resolvedMeals(for date: Date, plans: [MenuPlan], selections: [DayPlanSelection],
                              choices: [DayMealChoice], settings: UserSettings?) -> [ResolvedMeal] {
        let key = DateUtils.dayKey(date)
        let dayPlan = plan(for: date, plans: plans, selections: selections, settings: settings)
        return MealType.allCases.compactMap { type in
            if let choice = choices.first(where: { $0.dayKey == key && $0.mealTypeRaw == type.rawValue }),
               let p = plans.first(where: { $0.id == choice.planID }), let t = p.meal(type) {
                return ResolvedMeal(type: type, template: t, plan: p, factor: choice.factor, isChoice: true)
            }
            guard let p = dayPlan, let t = p.meal(type) else { return nil }
            return ResolvedMeal(type: type, template: t, plan: p, factor: 1, isChoice: false)
        }
    }

    /// Todas las comidas de un tipo en los menús, como opciones (sin repetir comidas idénticas).
    @MainActor
    static func candidates(for type: MealType, plans: [MenuPlan]) -> [ResolvedMeal] {
        var seen = Set<String>()
        return plans.sorted { $0.number < $1.number }.compactMap { p in
            guard let t = p.meal(type) else { return nil }
            let signature = t.sortedItems.map { "\($0.food?.id.uuidString ?? "")-\($0.grams)" }.joined(separator: ",")
            guard seen.insert(signature).inserted else { return nil }
            return ResolvedMeal(type: type, template: t, plan: p, factor: 1, isChoice: false)
        }
    }

    /// Guarda la comida elegida para un día. Si ya estaba marcada como hecha, actualiza su registro.
    @MainActor
    static func choose(_ type: MealType, planID: UUID, factor: Double, on date: Date, in context: ModelContext) {
        let key = DayMealChoice.makeKey(dayKey: DateUtils.dayKey(date), mealType: type)
        var descriptor = FetchDescriptor<DayMealChoice>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.planID = planID
            existing.factor = factor
        } else {
            context.insert(DayMealChoice(dayKey: DateUtils.dayKey(date), mealType: type, planID: planID, factor: factor))
        }
        try? context.save()
    }

    // MARK: Lo que he comido (comida libre)

    @MainActor
    static func customItems(for type: MealType, on date: Date, in context: ModelContext) -> [CustomMealItem] {
        let key = DateUtils.dayKey(date)
        let raw = type.rawValue
        let descriptor = FetchDescriptor<CustomMealItem>(
            predicate: #Predicate { $0.dayKey == key && $0.mealTypeRaw == raw },
            sortBy: [SortDescriptor(\.order)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @MainActor
    static func addCustomItem(_ type: MealType, name: String, grams: Double, per100: NutritionValues,
                              source: CustomItemSource, on date: Date, in context: ModelContext) {
        let next = (customItems(for: type, on: date, in: context).map(\.order).max() ?? -1) + 1
        context.insert(CustomMealItem(dayKey: DateUtils.dayKey(date), mealType: type, name: name,
                                      grams: max(grams, 0), per100: per100, source: source, order: next))
        try? context.save()
    }

    /// Borra lo apuntado en esa comida: vuelve a mostrarse la comida del menú (o la elegida).
    @MainActor
    static func clearCustom(_ type: MealType, on date: Date, in context: ModelContext) {
        customItems(for: type, on: date, in: context).forEach { context.delete($0) }
        try? context.save()
    }

    /// Reajusta las comidas pendientes del día (sin lo apuntado a mano ni las ya marcadas como hechas):
    /// elige, en orden, la opción que mejor encaja con lo que queda.
    /// - Returns: las elecciones aplicadas.
    @MainActor
    @discardableResult
    static func rebalanceDay(_ date: Date, fixed: [MealType: NutritionValues], daily: NutritionValues,
                             plans: [MenuPlan], in context: ModelContext) -> [MealType: MealPlanner.Option] {
        var fixedValues = fixed
        var applied: [MealType: MealPlanner.Option] = [:]
        for type in MealType.allCases where fixedValues[type] == nil {
            let target = MealPlanner.target(for: type, daily: daily, fixed: fixedValues)
            guard let best = MealPlanner.rank(candidates(for: type, plans: plans).map(\.plannerCandidate), target: target, limit: 1).first,
                  let id = UUID(uuidString: best.id) else { continue }
            choose(type, planID: id, factor: best.factor, on: date, in: context)
            fixedValues[type] = best.values
            applied[type] = best
        }
        return applied
    }

    /// Quita la elección: vuelve la comida del menú del día.
    @MainActor
    static func clearChoice(_ type: MealType, on date: Date, in context: ModelContext) {
        let key = DayMealChoice.makeKey(dayKey: DateUtils.dayKey(date), mealType: type)
        let descriptor = FetchDescriptor<DayMealChoice>(predicate: #Predicate { $0.key == key })
        ((try? context.fetch(descriptor)) ?? []).forEach { context.delete($0) }
        try? context.save()
    }

    /// Marca o desmarca una comida del día con sus valores reales (ración incluida).
    @MainActor
    static func setMeal(_ type: MealType, values: NutritionValues, planName: String, completed: Bool,
                        on date: Date, in context: ModelContext) {
        let key = DateUtils.dayKey(date)
        let typeRaw = type.rawValue
        let descriptor = FetchDescriptor<MealRecord>(predicate: #Predicate { $0.dayKey == key && $0.mealTypeRaw == typeRaw })
        let existing = (try? context.fetch(descriptor)) ?? []
        if completed {
            if let record = existing.first {
                record.planName = planName
                record.kcal = values.kcal
                record.protein = values.protein
                record.carbs = values.carbs
                record.fat = values.fat
            } else {
                context.insert(MealRecord(date: date, mealType: type, planName: planName, values: values))
            }
        } else {
            existing.forEach { context.delete($0) }
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
        // Con objetivos automáticos, un peso nuevo recalcula kcal y macros.
        if settings(context).autoTargets { recalculateTargets(context) }
        return true
    }

    @MainActor
    static func latestWeight(_ context: ModelContext) -> Double? {
        var descriptor = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.weightKg
    }

    // MARK: Perfil y objetivos

    /// Recalcula y guarda los objetivos con Mifflin-St Jeor. Devuelve nil si el perfil está incompleto.
    @MainActor
    @discardableResult
    static func recalculateTargets(_ context: ModelContext) -> EnergyTargets? {
        let s = settings(context)
        guard let profile = s.bodyProfile(weightKg: latestWeight(context)) else { return nil }
        let targets = EnergyCalculator.targets(for: profile)
        s.apply(targets)
        try? context.save()
        return targets
    }

    // MARK: Ajuste de menús

    /// Escala proporcionalmente los gramos de un menú para acercar su total a `targetKcal`.
    /// Devuelve el factor aplicado (nil si no se pudo).
    @MainActor
    @discardableResult
    static func scale(_ plan: MenuPlan, toKcal targetKcal: Double, in context: ModelContext) -> Double? {
        guard let factor = MenuScaler.factor(currentKcal: plan.totals.kcal, targetKcal: targetKcal) else { return nil }
        for meal in plan.meals {
            for item in meal.items {
                item.grams = MenuScaler.scaledGrams(item.grams, factor: factor)
            }
        }
        try? context.save()
        return factor
    }
}
