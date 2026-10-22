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
        XCTAssertEqual(s.proteinTarget, 170)

        DataStore.addWeight(80, waist: nil, date: Date().addingTimeInterval(60), in: context)
        let expected = EnergyCalculator.targets(for: BodyProfile(weightKg: 80, heightCm: 180, age: 30, sex: .male,
                                                                 activity: .moderate, goal: .recomposition))
        XCTAssertEqual(s.kcalTarget, expected.kcal)
        XCTAssertEqual(s.proteinTarget, 160)
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
        let plans = try seedCatalog()
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
}
#endif
