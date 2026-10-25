#if canImport(SwiftData)
import SwiftData
import XCTest
@testable import Atlas

/// Datos con SwiftData en memoria (se ejecutan en el simulador de iOS).
@MainActor
final class AtlasStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try ModelContainer(for: Schema(AtlasSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
    }

    func testYourRoutineIsSeededOnce() {
        Store.seedTemplatesIfNeeded(context)
        Store.seedTemplatesIfNeeded(context)
        let templates = Store.templates(context)
        XCTAssertEqual(templates.count, WeeklyRoutine.allSessions.count, "Tu rutina de siempre, sin duplicados")
        let push = templates.first { $0.seedID == "tue-push-a" }
        XCTAssertEqual(push?.sortedExercises.map(\.key), WeeklyRoutine.tuesdayPushA.exercises.map(\.id))
        XCTAssertEqual(push?.weekday, 2)
    }

    func testOneWeightPerDayAndTargetsFollow() {
        let p = Store.profile(context)
        p.age = 30; p.heightCm = 180; p.sexRaw = BiologicalSex.male.rawValue
        Store.logWeight(85, in: context)
        Store.logWeight(84.6, in: context)
        XCTAssertEqual((try? context.fetchCount(FetchDescriptor<WeightLog>())) ?? 0, 1)
        XCTAssertEqual(Store.latestWeight(context)?.kg, 84.6)
        XCTAssertGreaterThan(p.kcalTarget, 1500)
        p.manualTargets = true
        p.kcalTarget = 2000
        Store.logWeight(80, in: context)
        XCTAssertEqual(p.kcalTarget, 2000, "Los objetivos manuales no se tocan")
    }

    func testFoodDishAndCopyDay() {
        let key = DateUtils.dayKey(Date())
        let chicken = Catalog.shared.food("chicken_breast")!
        Store.addFood(name: chicken.name, per100: chicken.per100, grams: 200, meal: .lunch, dayKey: key, foodKey: chicken.id, in: context)
        let e = Store.entries(key, in: context).first!
        XCTAssertEqual(e.kcal, chicken.per100.kcal * 2, accuracy: 0.01)
        e.setGrams(100)
        XCTAssertEqual(e.kcal, chicken.per100.kcal, accuracy: 0.01)
        let dish = Dish.all.first { $0.meal == .dinner }!
        Store.addDish(dish, factor: 1.1, meal: .dinner, dayKey: key, in: context)
        let dinner = Store.entries(key, in: context).filter { $0.meal == .dinner }
        XCTAssertEqual(dinner.count, Catalog.shared.items(dish.items).count, "Cada ingrediente del plato con sus gramos")
        let tomorrow = DateUtils.dayKey(Date().addingTimeInterval(86400))
        XCTAssertEqual(Store.copyDay(from: key, to: tomorrow, in: context), Store.entries(key, in: context).count)
        XCTAssertFalse(Dish.all.isEmpty)
        XCTAssertEqual(Set(Dish.all.map(\.id)).count, Dish.all.count)
    }

    func testWorkoutHistoryRecordsAndCoach() {
        Store.seedTemplatesIfNeeded(context)
        let push = Store.templates(context).first { $0.seedID == "tue-push-a" }!
        let first = Store.startWorkout(from: push, in: context)
        XCTAssertEqual(first.sets.count, push.sortedExercises.reduce(0) { $0 + $1.sets })
        let key = push.sortedExercises[0].key
        for s in first.sets where s.exerciseKey == key { s.kg = 60; s.reps = 10; s.done = true }
        Store.finish(first, in: context)
        XCTAssertTrue(first.sets.allSatisfy { $0.exerciseKey == key }, "Las series vacías no se guardan")

        let second = Store.startWorkout(from: push, in: context)
        let last = Store.lastPerformance(key, excluding: second, in: context)
        XCTAssertEqual(last.first, SetSample(kg: 60, reps: 10))
        XCTAssertEqual(Store.bestE1RM(key, excluding: second, in: context), PersonalRecords.e1rm(.init(kg: 60, reps: 10)), accuracy: 0.01)
        let range = push.sortedExercises[0].repRange
        let suggestion = OverloadCoach.suggest(repRange: range, last: last)
        XCTAssertNotNil(suggestion)
        Store.discard(second, in: context)
        XCTAssertEqual(Store.finishedWorkouts(in: context).count, 1)
    }

    func testWaterAddsAndSubtractsWithoutGoingNegative() {
        let day = DateUtils.dayKey(Date())
        XCTAssertEqual(Store.changeWater(250, dayKey: day, in: context), 250)
        XCTAssertEqual(Store.changeWater(250, dayKey: day, in: context), 500)
        XCTAssertEqual(Store.changeWater(-250, dayKey: day, in: context), 250, "Restar deshace un toque sin querer")
        XCTAssertEqual(Store.changeWater(-250, dayKey: day, in: context), 0)
        XCTAssertEqual(Store.changeWater(-250, dayKey: day, in: context), 0, "Nunca baja de 0")
        XCTAssertEqual(Store.water(day, in: context).ml, 0, "Se guarda un único registro por día")
    }

    func testQuickCompleteAndRuns() {
        Store.seedTemplatesIfNeeded(context)
        let run = Store.templates(context).first { $0.kind == .run }!
        Store.logRun(meters: 5000, seconds: 1500, template: run, in: context)
        let workouts = Store.finishedWorkouts(in: context)
        XCTAssertNotNil(Store.doneThisWeek(run, workouts: workouts))
        XCTAssertEqual(workouts.first?.runMeters, 5000)
    }
}
#endif
