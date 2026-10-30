#if canImport(SwiftData)
import SwiftData
import XCTest
@testable import Atlas

/// Copia de seguridad y datos de seguimiento con SwiftData en memoria (se ejecutan en el simulador de iOS).
@MainActor
final class BackupPersistenceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try ModelContainer(for: AtlasApp.schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
    }

    private func count<T: PersistentModel>(_ type: T.Type) -> Int {
        (try? context.fetchCount(FetchDescriptor<T>())) ?? -1
    }

    func testExportWipeImportRestoresEverything() throws {
        let defaults = UserDefaults(suiteName: "backup-\(UUID().uuidString)")!
        DataStore.seedRoutineIfNeeded(context, defaults: defaults)
        DataStore.seedCatalogIfNeeded(context, defaults: defaults)
        let s = DataStore.settings(context)
        s.stepGoal = 9250
        s.weightReminderEnabled = true
        DataStore.addWeight(80.4, waist: 85, date: Date(), in: context)
        let push = WeeklyRoutine.tuesdayPushA.resolved(with: (try? context.fetch(FetchDescriptor<RoutineExercise>())) ?? [])
        let log = DataStore.fetchOrCreateLog(for: push, weekStart: DateUtils.startOfWeek(Date()), in: context)
        log.isCompleted = true
        log.exercises.first?.isCompleted = true
        DataStore.saveSteps(7345, for: Date(), goal: 9250, in: context)
        DataStore.setMark(.sick, from: Date(), through: Date(), in: context)
        context.insert(StravaActivityRecord(stravaID: -1, name: "Carrera apuntada a mano", sportType: "Run", startDate: Date(),
                                            distanceMeters: 5200, movingTimeSeconds: 1800, elapsedTimeSeconds: 1800, elevationGainMeters: nil))
        try context.save()

        let before = (foods: count(FoodItem.self), plans: count(MenuPlan.self), items: count(MealItem.self),
                      routine: count(RoutineExercise.self), exercises: count(ExerciseLog.self))
        let data = try BackupService.makeBackup(context).encoded()

        // Se cambia todo después de exportar…
        s.stepGoal = 4000
        DataStore.addWeight(99, waist: nil, date: Date().addingTimeInterval(-86400), in: context)
        DataStore.setMark(.work, from: Date(), through: Date(), in: context)

        // …y al importar vuelve a estar como en la copia.
        try BackupService.restore(try BackupFile.decode(data), into: context)
        XCTAssertEqual(DataStore.settings(context).stepGoal, 9250)
        XCTAssertTrue(DataStore.settings(context).weightReminderEnabled)
        let weights = try context.fetch(FetchDescriptor<WeightEntry>())
        XCTAssertEqual(weights.map(\.weightKg), [80.4])
        XCTAssertEqual(weights.first?.waistCm, 85)
        XCTAssertEqual(count(FoodItem.self), before.foods)
        XCTAssertEqual(count(MenuPlan.self), before.plans)
        XCTAssertEqual(count(MealItem.self), before.items)
        XCTAssertEqual(count(RoutineExercise.self), before.routine)
        XCTAssertEqual(count(ExerciseLog.self), before.exercises)
        let logs = try context.fetch(FetchDescriptor<WorkoutSessionLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertTrue(logs[0].isCompleted)
        XCTAssertTrue(logs[0].exercises.contains(where: \.isCompleted))
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailySteps>()).map(\.steps), [7345])
        XCTAssertEqual(try context.fetch(FetchDescriptor<DayMarkRecord>()).map(\.mark), [.sick])
        XCTAssertEqual(try context.fetch(FetchDescriptor<StravaActivityRecord>()).first?.isManual, true)
        // Los alimentos siguen enlazados a los menús (mismos ids).
        let items = try context.fetch(FetchDescriptor<MealItem>())
        XCTAssertFalse(items.isEmpty)
        XCTAssertTrue(items.allSatisfy { $0.food != nil })
    }

    func testMarksDefaultsAndRanges() throws {
        let cal = DateUtils.calendar
        // 2026-10-21 (miércoles) … 2026-10-24 (sábado): el viernes 23 queda en el medio.
        let wednesday = cal.date(from: DateComponents(year: 2026, month: 10, day: 21))!
        let saturday = cal.date(from: DateComponents(year: 2026, month: 10, day: 24))!
        DataStore.setMark(.sick, from: wednesday, through: saturday, in: context)
        XCTAssertEqual(count(DayMarkRecord.self), 4)
        // Marcar el viernes como descanso = su valor por defecto: no se guarda nada.
        let friday = cal.date(from: DateComponents(year: 2026, month: 10, day: 23))!
        DataStore.setMark(.rest, from: friday, through: friday, in: context)
        XCTAssertEqual(count(DayMarkRecord.self), 3)
        // Normal en un miércoles = por defecto: se borra la marca.
        DataStore.setMark(.normal, from: wednesday, through: wednesday, in: context)
        XCTAssertEqual(count(DayMarkRecord.self), 2)
        // Normal en un viernes sí se guarda (quita el descanso).
        DataStore.setMark(.normal, from: friday, through: friday, in: context)
        XCTAssertEqual(count(DayMarkRecord.self), 3)
    }

    func testStepsNeverGoDownAndAdaptiveGoal() throws {
        let today = Date()
        DataStore.saveSteps(5000, for: today, goal: 8000, in: context)
        DataStore.saveSteps(4000, for: today, goal: 8000, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DailySteps>()).first?.steps, 5000)

        for offset in 1...3 {
            let day = DateUtils.calendar.date(byAdding: .day, value: -offset, to: today)!
            DataStore.saveSteps(10000, for: day, goal: 8000, in: context)
        }
        let s = DataStore.settings(context)
        s.stepGoalAdaptive = true
        XCTAssertEqual(DataStore.updateAdaptiveStepGoal(context, today: today), 10500)
        XCTAssertEqual(s.stepGoal, 10500)
        XCTAssertNil(DataStore.updateAdaptiveStepGoal(context, today: today), "Solo una vez al día")
        s.stepGoalAdaptive = false
        s.stepGoalAdjustedDayKey = ""
        s.stepGoal = 7000
        XCTAssertNil(DataStore.updateAdaptiveStepGoal(context, today: today), "Manual: no se toca")
        XCTAssertEqual(s.stepGoal, 7000)
    }

    func testStrengthMarkedDoneFromTheWeekMarksEveryExercise() throws {
        let defaults = UserDefaults(suiteName: "week-\(UUID().uuidString)")!
        DataStore.seedRoutineIfNeeded(context, defaults: defaults)
        let push = WeeklyRoutine.tuesdayPushA.resolved(with: (try? context.fetch(FetchDescriptor<RoutineExercise>())) ?? [])
        let log = DataStore.fetchOrCreateLog(for: push, weekStart: DateUtils.startOfWeek(Date()), in: context)

        log.toggleDoneFromWeek(session: push)
        XCTAssertTrue(log.isCompleted)
        XCTAssertNotNil(log.completedAt)
        XCTAssertTrue(SessionProgress(session: push, log: log).isComplete, "Todos los ejercicios quedan marcados")

        log.toggleDoneFromWeek(session: push)
        XCTAssertFalse(log.isCompleted)
        XCTAssertEqual(SessionProgress(session: push, log: log).completedExercises, 0)
    }

    func testSwipeToggleReusesTheWeekLogAndPersists() throws {
        let defaults = UserDefaults(suiteName: "swipe-\(UUID().uuidString)")!
        DataStore.seedRoutineIfNeeded(context, defaults: defaults)
        let routine = (try? context.fetch(FetchDescriptor<RoutineExercise>())) ?? []
        let week = DateUtils.startOfWeek(Date())
        let run = WeeklyRoutine.saturdayRun
        let chest = WeeklyRoutine.saturdayChestBack.resolved(with: routine)
        let exercisesBefore = chest.exercises.map(\.id)

        // Carrera y pecho del mismo día, cada una por separado; marcar, desmarcar y volver a marcar.
        DataStore.fetchOrCreateLog(for: run, weekStart: week, in: context).toggleDoneFromWeek(session: run)
        DataStore.fetchOrCreateLog(for: run, weekStart: week, in: context).toggleDoneFromWeek(session: run)
        DataStore.fetchOrCreateLog(for: run, weekStart: week, in: context).toggleDoneFromWeek(session: run)
        DataStore.fetchOrCreateLog(for: chest, weekStart: week, in: context).toggleDoneFromWeek(session: chest)
        try context.save()

        XCTAssertEqual(count(WorkoutSessionLog.self), 2, "Un registro por sesión y semana, sin duplicados")
        XCTAssertEqual(DataStore.sessionLog(for: run, weekStart: week, in: context)?.isCompleted, true)
        XCTAssertEqual(DataStore.sessionLog(for: chest, weekStart: week, in: context)?.isCompleted, true)
        XCTAssertEqual(DataStore.sessionLog(for: run, weekStart: week, in: context)?.weekStart, week, "La fecha no cambia")
        XCTAssertEqual(WeeklyRoutine.saturdayChestBack.resolved(with: routine).exercises.map(\.id), exercisesBefore,
                       "La rutina no se toca")

        // Con un contexto nuevo (como al volver a abrir la app) sigue guardado.
        let fresh = ModelContext(container)
        let logs = try fresh.fetch(FetchDescriptor<WorkoutSessionLog>())
        XCTAssertEqual(Set(logs.filter(\.isCompleted).map(\.sessionID)), ["sat-run", "sat-chest-back"])
    }
}
#endif
