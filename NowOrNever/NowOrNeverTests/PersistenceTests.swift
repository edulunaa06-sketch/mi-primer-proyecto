#if canImport(SwiftData)
import SwiftData
import XCTest
@testable import NowOrNever

/// Pruebas de persistencia con SwiftData en memoria (se ejecutan en el simulador de iOS).
@MainActor
final class PersistenceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        container = try ModelContainer(for: NowOrNeverApp.schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
        defaults = UserDefaults(suiteName: "tests-\(UUID().uuidString)")
    }

    private func routine() -> [RoutineExercise] {
        (try? context.fetch(FetchDescriptor<RoutineExercise>())) ?? []
    }

    // MARK: Rutina

    func testRoutineSeedMatchesDefaultsAndRunsOnce() {
        DataStore.seedRoutineIfNeeded(context, defaults: defaults)
        let expected = WeeklyRoutine.allSessions.filter { $0.kind == .strength }.flatMap(\.exercises)
        XCTAssertEqual(routine().count, expected.count)
        for base in WeeklyRoutine.allSessions where base.kind == .strength {
            let resolved = base.resolved(with: routine())
            XCTAssertEqual(resolved.exercises, base.exercises, base.title)
        }
        // Segunda llamada: no duplica ni sobrescribe.
        DataStore.seedRoutineIfNeeded(context, defaults: defaults)
        XCTAssertEqual(routine().count, expected.count)
    }

    func testEditRoutineAddRemoveSubstituteMoveRestore() {
        DataStore.seedRoutineIfNeeded(context, defaults: defaults)
        let push = WeeklyRoutine.tuesdayPushA

        DataStore.addExercise(to: push.id, name: "Fondos en paralelas", sets: 3, repMin: 6, repMax: 10, in: context)
        var resolved = push.resolved(with: routine())
        XCTAssertEqual(resolved.exercises.count, 7)
        XCTAssertEqual(resolved.exercises.last?.name, "Fondos en paralelas")
        XCTAssertEqual(resolved.exercises.last?.repRange, "6–10")

        let bench = DataStore.routine(for: push.id, in: context)[0]
        DataStore.substitute(bench, withName: "Press de banca con mancuernas", in: context)
        resolved = push.resolved(with: routine())
        XCTAssertEqual(resolved.exercises.first?.name, "Press de banca con mancuernas")
        XCTAssertNotEqual(resolved.exercises.first?.id, "tue-bench-barbell")

        DataStore.moveExercises(in: push.id, from: IndexSet(integer: 6), to: 0, in: context)
        resolved = push.resolved(with: routine())
        XCTAssertEqual(resolved.exercises.first?.name, "Fondos en paralelas")

        let lateral = DataStore.routine(for: push.id, in: context).first { $0.exerciseID == "tue-cable-lateral-raise" }!
        lateral.sets = 4
        lateral.repMax = 25
        DataStore.removeExercise(DataStore.routine(for: push.id, in: context).last!, in: context)
        resolved = push.resolved(with: routine())
        XCTAssertEqual(resolved.exercises.count, 6)
        XCTAssertEqual(resolved.exercises.first { $0.id == "tue-cable-lateral-raise" }?.prescription, "4 × 12–25")
        XCTAssertEqual(DataStore.routine(for: push.id, in: context).map(\.order), Array(0..<6))

        DataStore.restoreDefaultRoutine(for: push, in: context)
        XCTAssertEqual(push.resolved(with: routine()).exercises, push.exercises)
        // Otras sesiones intactas.
        XCTAssertEqual(WeeklyRoutine.thursdayLegs.resolved(with: routine()).exercises, WeeklyRoutine.thursdayLegs.exercises)
    }

    // MARK: Registros semanales e historial

    func testWeeklyLogsHistoryAndSnapshots() throws {
        DataStore.seedRoutineIfNeeded(context, defaults: defaults)
        let base = WeeklyRoutine.tuesdayPushA
        let week1 = DateUtils.startOfWeek(DateUtils.calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))!)
        let week2 = DateUtils.calendar.date(byAdding: .day, value: 7, to: week1)!

        let log1 = DataStore.fetchOrCreateLog(for: base.resolved(with: routine()), weekStart: week1, in: context)
        XCTAssertFalse(log1.hasUserData, "Abrir una sesión no marca nada")
        let bench = log1.exercises.first { $0.exerciseID == "tue-bench-barbell" }!
        XCTAssertEqual(bench.sets.count, 3)
        XCTAssertEqual(bench.name, "Press de banca con barra")
        bench.sortedSets[0].weightKg = 60
        bench.sortedSets[0].reps = 8
        bench.sortedSets[0].isDone = true
        bench.isCompleted = true
        log1.isCompleted = true
        try context.save()

        // Se sustituye el ejercicio: el historial conserva el nombre antiguo.
        DataStore.substitute(DataStore.routine(for: base.id, in: context)[0], withName: "Press con mancuernas", in: context)

        let log2 = DataStore.fetchOrCreateLog(for: base.resolved(with: routine()), weekStart: week2, in: context)
        XCTAssertFalse(log2.isCompleted, "La semana nueva empieza sin marcar")
        XCTAssertFalse(log2.exercises.contains { $0.isCompleted })
        XCTAssertNil(log2.exercises.first { $0.exerciseID == "tue-bench-barbell" })

        let previous = DataStore.previousLog(for: base, before: week2, in: context)
        XCTAssertEqual(previous?.key, log1.key)
        XCTAssertEqual(previous?.exercises.first { $0.exerciseID == "tue-bench-barbell" }?.displayName, "Press de banca con barra")
        XCTAssertEqual(previous?.exercises.first { $0.exerciseID == "tue-bench-barbell" }?.sortedSets[0].weightKg, 60)

        // Progresión: los registros del ejercicio se pueden consultar por ID.
        let id = "tue-bench-barbell"
        let logs = try context.fetch(FetchDescriptor<ExerciseLog>(predicate: #Predicate { $0.exerciseID == id }))
        XCTAssertEqual(logs.count, 1)
    }

    func testSetsAddedWhenPrescriptionGrows() {
        DataStore.seedRoutineIfNeeded(context, defaults: defaults)
        let base = WeeklyRoutine.wednesdayPullA
        let week = DateUtils.startOfWeek(Date())
        let log = DataStore.fetchOrCreateLog(for: base.resolved(with: routine()), weekStart: week, in: context)
        let pulldown = DataStore.routine(for: base.id, in: context)[0]
        pulldown.sets = 5
        DataStore.ensureStructure(log, session: base.resolved(with: routine()), in: context)
        let exLog = log.exercises.first { $0.exerciseID == pulldown.exerciseID }!
        XCTAssertEqual(exLog.sets.count, 5)
        XCTAssertEqual(exLog.visibleSets.count, 5)
        XCTAssertEqual(exLog.targetSets, 5)
    }

    // MARK: Registro por foto

    func testLoggedFoodsUpdateTheDayTotalAndCanBeRemoved() throws {
        let day = Date()
        let chicken = NutritionValues(kcal: 165, protein: 31, carbs: 0, fat: 3.6)
        let rice = NutritionValues(kcal: 130, protein: 2.7, carbs: 28, fat: 0.3)
        DataStore.logFoods([(name: "Pollo", grams: 200, per100: chicken)], as: .lunch, on: day, in: context)
        DataStore.logFoods([(name: "Arroz cocido", grams: 150, per100: rice)], as: .lunch, on: day, in: context)
        var records = try context.fetch(FetchDescriptor<MealRecord>())
        XCTAssertEqual(records.count, 1, "Una comida, un registro con el total")
        XCTAssertEqual(records[0].kcal, 330 + 195, accuracy: 0.01)
        let rows = DataStore.customItems(for: .lunch, on: day, in: context)
        XCTAssertEqual(rows.count, 2)
        DataStore.removeLogged(rows[0], in: context)
        records = try context.fetch(FetchDescriptor<MealRecord>())
        XCTAssertEqual(records.first?.kcal ?? 0, 195, accuracy: 0.01)
        DataStore.removeLogged(DataStore.customItems(for: .lunch, on: day, in: context)[0], in: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<MealRecord>()).isEmpty)
    }

    // MARK: Nombres de sesión

    func testRenameSessionKeepsIdAndCanRestore() throws {
        DataStore.renameSession("tue-push-a", to: "  Pecho y hombro  ", in: context)
        var titles = try context.fetch(FetchDescriptor<SessionTitle>())
        let push = try XCTUnwrap(WeeklyRoutine.session(id: "tue-push-a"))
        XCTAssertEqual(push.resolved(with: [], titles: titles).title, "Pecho y hombro")
        XCTAssertEqual(push.resolved(with: [], titles: titles).id, "tue-push-a")
        DataStore.renameSession("tue-push-a", to: "Torso", in: context)
        titles = try context.fetch(FetchDescriptor<SessionTitle>())
        XCTAssertEqual(titles.count, 1)
        XCTAssertEqual(push.renamed(titles).title, "Torso")
        DataStore.renameSession("tue-push-a", to: "", in: context)
        titles = try context.fetch(FetchDescriptor<SessionTitle>())
        XCTAssertEqual(push.renamed(titles).title, push.title)
    }

    // MARK: Perfil y objetivos

    func testAutoTargetsRecalculateOnNewWeight() {
        let s = DataStore.settings(context)
        s.heightCm = 180
        s.age = 30
        s.sex = .male
        s.activity = .moderate
        s.goal = .recomposition
        s.autoTargets = true
        DataStore.addWeight(85.1, waist: nil, date: Date(), in: context)
        XCTAssertEqual(s.kcalTarget, 2550)
        XCTAssertEqual(s.proteinTarget, 191)

        DataStore.addWeight(80, waist: nil, date: Date().addingTimeInterval(60), in: context)
        let expected = EnergyCalculator.targets(for: BodyProfile(weightKg: 80, heightCm: 180, age: 30, sex: .male,
                                                                 activity: .moderate, goal: .recomposition))
        XCTAssertEqual(s.kcalTarget, expected.kcal)
        XCTAssertEqual(s.proteinTarget, 186)
    }

    func testManualTargetsAreNotOverwritten() {
        let s = DataStore.settings(context)
        s.heightCm = 180
        s.age = 30
        s.sex = .male
        s.autoTargets = false
        DataStore.addWeight(85.1, waist: nil, date: Date(), in: context)
        XCTAssertEqual(s.kcalTarget, 2300)
        XCTAssertEqual(s.proteinTarget, 180)
    }

    func testIncompleteProfileDoesNotCalculate() {
        let s = DataStore.settings(context)
        s.autoTargets = true
        DataStore.addWeight(85.1, waist: nil, date: Date(), in: context)
        XCTAssertNil(DataStore.recalculateTargets(context))
        XCTAssertEqual(s.kcalTarget, 2300)
    }

    func testDuplicateWeightSameDayIgnored() {
        let d = Date()
        XCTAssertTrue(DataStore.addWeight(85.1, waist: nil, date: d, in: context))
        XCTAssertFalse(DataStore.addWeight(85.1, waist: nil, date: d.addingTimeInterval(30), in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WeightEntry>()), 1)
    }

    // MARK: Nutrición

    private func seedCatalog() throws -> [MenuPlan] {
        DataStore.seed(try SeedCatalog.loadFromBundle(.main), into: context)
        try context.save()
        return try context.fetch(FetchDescriptor<MenuPlan>(sortBy: [SortDescriptor(\.number)]))
    }

    func testSeededMenusComputeTotalsAndScaleToTarget() throws {
        let plans = try seedCatalog().filter { !$0.isLibrary }
        XCTAssertEqual(plans.count, 9)
        XCTAssertTrue(plans.allSatisfy { $0.meals.count == 4 })
        for plan in plans {
            let factor = DataStore.scale(plan, toKcal: 2600, in: context)
            XCTAssertNotNil(factor)
            XCTAssertEqual(plan.totals.kcal, 2600, accuracy: 2600 * 0.04, "Menú \(plan.number)")
        }
    }

    func testEditingGramsUpdatesMealAndDayTotals() throws {
        let plan = try seedCatalog()[0]
        let lunch = plan.meal(.lunch)!
        let item = lunch.sortedItems[0]
        let mealBefore = lunch.totals.kcal
        let dayBefore = plan.totals.kcal
        let perGram = item.food!.kcalPer100 / 100
        item.grams += 50
        XCTAssertEqual(lunch.totals.kcal - mealBefore, perGram * 50, accuracy: 0.001)
        XCTAssertEqual(plan.totals.kcal - dayBefore, perGram * 50, accuracy: 0.001)
    }

    func testMarkMealCompletedOncePerDay() throws {
        let plan = try seedCatalog()[0]
        let breakfast = plan.meal(.breakfast)!
        let day = Date()
        DataStore.setMeal(breakfast, planName: plan.name, completed: true, on: day, in: context)
        DataStore.setMeal(breakfast, planName: plan.name, completed: true, on: day, in: context)
        var records = try context.fetch(FetchDescriptor<MealRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].kcal, breakfast.totals.kcal, accuracy: 0.001)
        DataStore.setMeal(breakfast, planName: plan.name, completed: false, on: day, in: context)
        records = try context.fetch(FetchDescriptor<MealRecord>())
        XCTAssertTrue(records.isEmpty)
    }

    // MARK: Comidas elegibles

    func testChoosingMealsOverridesMenuAndBuildsDay() throws {
        let plans = try seedCatalog()
        let settings = DataStore.settings(context)
        let day = Date()
        var meals = DataStore.resolvedMeals(for: day, plans: plans, selections: [], choices: [], settings: settings)
        XCTAssertEqual(meals.map(\.type), MealType.allCases)
        XCTAssertTrue(meals.allSatisfy { !$0.isChoice && $0.plan.number == 1 })

        // 9 opciones de desayuno (una por menú) y se elige una de las 4 mejores.
        let daily = NutritionValues(kcal: settings.kcalTarget, protein: settings.proteinTarget,
                                    carbs: settings.carbsTarget, fat: settings.fatTarget)
        let breakfasts = DataStore.candidates(for: .breakfast, plans: plans)
        XCTAssertGreaterThanOrEqual(breakfasts.count, 4)
        let target = MealPlanner.target(for: .breakfast, daily: daily, fixed: [:])
        let top = MealPlanner.rank(breakfasts.map(\.plannerCandidate), target: target)
        XCTAssertEqual(top.count, 4)
        DataStore.choose(.breakfast, planID: UUID(uuidString: top[0].id)!, factor: top[0].factor, on: day, in: context)

        let choices = try context.fetch(FetchDescriptor<DayMealChoice>())
        meals = DataStore.resolvedMeals(for: day, plans: plans, selections: [], choices: choices, settings: settings)
        let breakfast = meals.first { $0.type == .breakfast }!
        XCTAssertTrue(breakfast.isChoice)
        XCTAssertEqual(breakfast.factor, top[0].factor)
        XCTAssertEqual(breakfast.totals.kcal, top[0].values.kcal, accuracy: 0.001)

        // Marcar la comida guarda los valores de la ración elegida; cambiarla luego actualiza el registro.
        DataStore.setMeal(.breakfast, values: breakfast.totals, planName: breakfast.sourceName, completed: true, on: day, in: context)
        DataStore.setMeal(.breakfast, values: top[1].values, planName: "otra", completed: true, on: day, in: context)
        let records = try context.fetch(FetchDescriptor<MealRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].kcal, top[1].values.kcal, accuracy: 0.001)

        // Volver al menú quita la elección.
        DataStore.clearChoice(.breakfast, on: day, in: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<DayMealChoice>()).isEmpty)
    }

    func testSequentialChoicesFitDailyTargets() throws {
        let plans = try seedCatalog()
        let daily = NutritionValues(kcal: 2550, protein: 170, carbs: 308, fat: 71)
        var fixed: [MealType: NutritionValues] = [:]
        for type in MealType.allCases {
            let target = MealPlanner.target(for: type, daily: daily, fixed: fixed)
            let best = MealPlanner.rank(DataStore.candidates(for: type, plans: plans).map(\.plannerCandidate), target: target)[0]
            fixed[type] = best.values
        }
        let total = NutritionMath.sum(Array(fixed.values))
        XCTAssertEqual(total.kcal, daily.kcal, accuracy: daily.kcal * 0.08)
        XCTAssertGreaterThan(MealPlanner.fit(total, to: daily), 0.85)
    }

    // MARK: Biblioteca de ideas y comida libre

    func testIdeasSeededAsLibraryAndOfferedAsOptions() throws {
        let plans = try seedCatalog()
        XCTAssertEqual(plans.filter { !$0.isLibrary }.count, 9)
        XCTAssertEqual(plans.filter(\.isLibrary).count, 44)
        XCTAssertTrue(plans.filter(\.isLibrary).allSatisfy { $0.meals.count == 1 })
        let breakfasts = DataStore.candidates(for: .breakfast, plans: plans)
        XCTAssertTrue(breakfasts.contains { $0.plan.name == "Plato de frutas con yogur" })
        XCTAssertGreaterThanOrEqual(breakfasts.count, 15)
        // Una idea nunca se usa como menú del día.
        let s = DataStore.settings(context)
        s.defaultPlanID = plans.first(where: \.isLibrary)?.id
        XCTAssertFalse(DataStore.plan(for: Date(), plans: plans, selections: [], settings: s)?.isLibrary ?? true)
    }

    func testCatalogUpgradeAddsIdeasWithoutDuplicates() throws {
        let catalog = try SeedCatalog.loadFromBundle(.main)
        let defaults = try XCTUnwrap(self.defaults)
        DataStore.seedCatalogIfNeeded(context, defaults: defaults, catalog: catalog)
        let foodsBefore = try context.fetchCount(FetchDescriptor<FoodItem>())
        // Simula una instalación antigua (versión 1, sin ideas) con un alimento editado por el usuario.
        try context.fetch(FetchDescriptor<MenuPlan>()).filter(\.isLibrary).forEach { context.delete($0) }
        let chicken = try XCTUnwrap(try context.fetch(FetchDescriptor<FoodItem>()).first { $0.seedKey == "chicken_breast" })
        chicken.kcalPer100 = 110
        try context.save()
        defaults.set(1, forKey: DataStore.seedVersionKey)

        DataStore.seedCatalogIfNeeded(context, defaults: defaults, catalog: catalog)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FoodItem>()), foodsBefore)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MenuPlan>()).filter(\.isLibrary).count, 44)
        XCTAssertEqual(chicken.kcalPer100, 110, "No se sobrescriben los cambios del usuario")
        XCTAssertEqual(defaults.integer(forKey: DataStore.seedVersionKey), 3)

        // Actualización con ideas ya instaladas: solo se añaden las que faltan, sin duplicar.
        let breadIdea = try XCTUnwrap(try context.fetch(FetchDescriptor<MenuPlan>()).first { $0.name == "Pan blanco con jamón serrano y tomate" })
        context.delete(breadIdea)
        try context.save()
        defaults.set(2, forKey: DataStore.seedVersionKey)
        DataStore.seedCatalogIfNeeded(context, defaults: defaults, catalog: catalog)
        let library = try context.fetch(FetchDescriptor<MenuPlan>()).filter(\.isLibrary)
        XCTAssertEqual(library.count, 44)
        XCTAssertEqual(Set(library.map(\.name)).count, 44)
    }

    func testCustomMealAndRebalanceRestOfDay() throws {
        let plans = try seedCatalog()
        let day = Date()
        let daily = NutritionValues(kcal: 2550, protein: 170, carbs: 308, fat: 71)
        // "Hoy desayuno un plato de frutas": se apunta a mano.
        DataStore.addCustomItem(.breakfast, name: "Plato de frutas", grams: 600,
                                per100: NutritionValues(kcal: 55, protein: 0.8, carbs: 13, fat: 0.3), source: .manual, on: day, in: context)
        DataStore.addCustomItem(.breakfast, name: "Macarrones", grams: 150,
                                per100: NutritionValues(kcal: 158, protein: 5.8, carbs: 30.9, fat: 0.9), source: .claude, on: day, in: context)
        let items = DataStore.customItems(for: .breakfast, on: day, in: context)
        XCTAssertEqual(items.count, 2)
        let breakfast = NutritionMath.sum(items.map(\.values))
        XCTAssertEqual(breakfast.kcal, 330 + 237, accuracy: 0.01)

        let applied = DataStore.rebalanceDay(day, fixed: [.breakfast: breakfast], daily: daily, plans: plans, in: context)
        XCTAssertEqual(Set(applied.keys), [.lunch, .snack, .dinner])
        let total = NutritionMath.sum([breakfast] + applied.values.map(\.values))
        XCTAssertEqual(total.kcal, daily.kcal, accuracy: daily.kcal * 0.1)
        XCTAssertGreaterThan(MealPlanner.fit(total, to: daily), 0.8)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DayMealChoice>()), 3)

        DataStore.clearCustom(.breakfast, on: day, in: context)
        XCTAssertTrue(DataStore.customItems(for: .breakfast, on: day, in: context).isEmpty)
    }
}
#endif
