import XCTest
@testable import Atlas

final class AtlasLogicTests: XCTestCase {
    private let day = 86400.0

    /// Al escribir las calorías a mano, los macros se reparten solos y cuadran con esas kcal.
    func testManualCaloriesResplitTheMacros() {
        for kcal in [1600.0, 2000, 2400, 3000] {
            let m = EnergyCalculator.macros(forKcal: kcal, weightKg: 80, goal: .recomposition)
            let sum = m.protein * 4 + m.carbs * 4 + m.fat * 9
            XCTAssertEqual(sum, kcal, accuracy: 20, "Los macros suman las kcal pedidas (\(kcal))")
            XCTAssertGreaterThan(m.protein, 0)
            XCTAssertGreaterThan(m.carbs, 0)
            XCTAssertGreaterThan(m.fat, 0)
        }
        // Menos calorías → menos de cada macro.
        let low = EnergyCalculator.macros(forKcal: 1800, weightKg: 80, goal: .recomposition)
        let high = EnergyCalculator.macros(forKcal: 2600, weightKg: 80, goal: .recomposition)
        XCTAssertLessThan(low.carbs, high.carbs)
        XCTAssertLessThanOrEqual(low.protein, high.protein)
        XCTAssertEqual(EnergyCalculator.macros(forKcal: 0, weightKg: 80, goal: .loseFat).carbs, 0)
    }

    func testCalorieStatus() {
        XCTAssertEqual(CalorieStatus.evaluate(consumed: 800, target: 2000), .plenty(left: 1200))
        XCTAssertEqual(CalorieStatus.evaluate(consumed: 1700, target: 2000), .approaching(left: 300))
        XCTAssertEqual(CalorieStatus.evaluate(consumed: 2080, target: 2000), .onTarget(delta: 80))
        XCTAssertEqual(CalorieStatus.evaluate(consumed: 2300, target: 2000), .over(excess: 300))
    }

    func testTrendIgnoresNoise() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // Peso estable de 80 kg con ruido de ±1 kg: la tendencia se queda cerca de 80.
        let points = (0..<30).map { WeightTrend.Point(date: start.addingTimeInterval(Double($0) * day), kg: 80 + ($0 % 2 == 0 ? 1 : -1)) }
        let trend = WeightTrend.smoothed(points)
        XCTAssertEqual(trend.count, 30)
        XCTAssertEqual(trend.last!.kg, 80, accuracy: 0.8)
        XCTAssertTrue(trend.map(\.kg).max()! - trend.map(\.kg).min()! < 1.5, "Mucho menos ruido que los pesajes")
        // Bajando 0,5 kg por semana → ritmo negativo cercano a −0,5 (la tendencia va algo retrasada).
        let losing = (0..<42).map { WeightTrend.Point(date: start.addingTimeInterval(Double($0) * day), kg: 85 - Double($0) * 0.5 / 7) }
        let rate = WeightTrend.weeklyRate(losing, days: 21, now: losing.last!.date)!
        XCTAssertEqual(rate, -0.5, accuracy: 0.15)
        XCTAssertNil(WeightTrend.weeklyRate(Array(losing.prefix(3)), now: losing[2].date), "Con pocos días no se calcula")
    }

    func testAdaptiveExpenditure() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // 28 días comiendo 2.200 kcal y bajando 1 kg de tendencia → gasto ≈ 2.200 + 7.700/28 ≈ 2.475.
        let intake = (0..<28).map { (day: now.addingTimeInterval(-Double($0) * day), kcal: 2200.0) }
        let weights = (0..<28).reversed().map { WeightTrend.Point(date: now.addingTimeInterval(-Double($0) * day), kg: 80 - Double(27 - $0) / 27) }
        let r = AdaptiveExpenditure.estimate(intake: intake, weights: weights, now: now)!
        XCTAssertGreaterThan(r.kcal, 2300)
        XCTAssertLessThan(r.kcal, 2600)
        XCTAssertEqual(r.daysUsed, 28)
        // Pocos días con comidas apuntadas → no se inventa.
        XCTAssertNil(AdaptiveExpenditure.estimate(intake: Array(intake.prefix(10)), weights: weights, now: now))
    }

    func testWeekStreak() {
        let cal = DateUtils.calendar
        let now = DateUtils.startOfWeek(Date()).addingTimeInterval(2 * day + 3600) // miércoles de esta semana
        func week(_ ago: Int, _ n: Int) -> [Date] {
            (0..<n).map { cal.date(byAdding: .day, value: -7 * ago + $0, to: DateUtils.startOfWeek(now))! }
        }
        // Plan de 4 sesiones → objetivo 3 por semana.
        XCTAssertEqual(WeekStreak.goal(planned: 4), 3)
        let days = week(3, 3) + week(2, 4) + week(1, 3) + week(0, 1)
        let r = WeekStreak.compute(workoutDays: days, planned: 4, now: now)
        XCTAssertEqual(r.current, 3, "La semana en curso aún no cumple, pero no rompe")
        XCTAssertEqual(r.best, 3)
        XCTAssertEqual(r.thisWeek, 1)
        // Una semana sin llegar rompe la racha.
        let broken = week(3, 3) + week(2, 1) + week(1, 3)
        XCTAssertEqual(WeekStreak.compute(workoutDays: broken, planned: 4, now: now).current, 1)
        XCTAssertEqual(WeekStreak.compute(workoutDays: [], planned: 4, now: now).current, 0)
    }

    func testWorkoutMathAndHydration() {
        XCTAssertEqual(WorkoutMath.volume([.init(kg: 100, reps: 5), .init(kg: 50, reps: 10)]), 1000)
        XCTAssertEqual(WorkoutMath.duration(3900), "1 h 05 min")
        XCTAssertEqual(WorkoutMath.duration(2880), "48 min")
        XCTAssertEqual(WorkoutMath.estimatedMinutes([(sets: 3, repRange: "8–12")]), 5)
        XCTAssertEqual(WorkoutMath.estimatedMinutes([(sets: 4, repRange: "6–10"), (sets: 3, repRange: "8–12")]), 20)
        XCTAssertEqual(Hydration.goal(weightKg: 80), 2750)
        XCTAssertEqual(Hydration.goal(weightKg: 40), 2000)
        XCTAssertEqual(Hydration.goal(weightKg: nil), 2500)
        XCTAssertEqual(Greeting.text(hour: 8), "Buenos días")
        XCTAssertEqual(Greeting.text(hour: 23), "Buenas noches")
    }

    func testLibraryAndSeedCatalog() throws {
        XCTAssertEqual(Set(ExerciseLibrary.all.map(\.id)).count, ExerciseLibrary.all.count, "Ids únicos")
        for e in ExerciseLibrary.all {
            XCTAssertNotNil(ExerciseDefinition.parseRange(e.defaultReps), e.name)
            XCTAssertNotNil(e.muscle, "Sin músculo: \(e.name)")
        }
        XCTAssertTrue(ExerciseLibrary.search("curl").allSatisfy { $0.name.lowercased().contains("curl") })
        let url = Bundle(for: Self.self).url(forResource: "SeedCatalog", withExtension: "json")
            ?? Bundle.main.url(forResource: "SeedCatalog", withExtension: "json")
        if let url {
            let catalog = try SeedCatalog.decode(from: Data(contentsOf: url))
            XCTAssertEqual(catalog.validationErrors(), [])
        }
    }
}
