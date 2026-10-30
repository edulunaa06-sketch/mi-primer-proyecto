import XCTest
@testable import Atlas

/// Pruebas de los informes. Lo que más se comprueba es que, sin datos suficientes,
/// el informe lo diga en vez de inventarse medias y conclusiones.
final class ReportTests: XCTestCase {
    private let today = DateUtils.startOfDay(Date(timeIntervalSince1970: 1_700_000_000))
    private func day(_ offset: Int) -> Date { today.addingTimeInterval(Double(offset) * 86_400) }

    private func period(_ range: ReportRange = .week) -> ReportPeriod { range.period(endingAt: today) }

    // MARK: Periodos

    func testWeekPeriodCoversSevenDaysEndingToday() {
        let week = ReportRange.week.period(endingAt: today)
        XCTAssertEqual(week.dayCount, 7)
        XCTAssertTrue(week.contains(today))
        XCTAssertTrue(week.contains(day(-6)))
        XCTAssertFalse(week.contains(day(-7)))
        XCTAssertFalse(week.contains(day(1)))
    }

    func testPreviousPeriodEndsRightBeforeTheCurrentOne() {
        let current = ReportRange.week.period(endingAt: today)
        let previous = ReportRange.week.previousPeriod(endingAt: today)
        XCTAssertEqual(previous.dayCount, 7)
        XCTAssertEqual(DateUtils.calendar.date(byAdding: .day, value: 1, to: previous.end), current.start)
        XCTAssertFalse(previous.contains(current.start))
    }

    func testEveryRangeHasALabelAndDays() {
        for range in ReportRange.allCases {
            XCTAssertFalse(range.label.isEmpty)
            XCTAssertGreaterThan(range.days, 0)
            XCTAssertEqual(range.period(endingAt: today).dayCount, range.days)
        }
    }

    // MARK: Informe vacío

    func testEmptyPeriodSaysThereIsNothingInsteadOfShowingZeros() {
        let report = ReportBuilder.build(ReportInput(period: period()))
        XCTAssertFalse(report.hasAnyData)
        XCTAssertFalse(report.training.hasEnoughData)
        XCTAssertFalse(report.nutrition.hasEnoughData)
        XCTAssertFalse(report.body.hasEnoughData)
        XCTAssertFalse(report.recovery.hasEnoughData)
        XCTAssertTrue(report.highlights.isEmpty)
        // Y explica qué falta en cada sección.
        XCTAssertTrue(report.caveats.contains { $0.contains("No hay entrenamientos") })
        XCTAssertTrue(report.caveats.contains { $0.contains("No hay comidas") })
        XCTAssertTrue(report.caveats.contains { $0.contains("Sin pesajes") })
    }

    // MARK: Entrenamiento

    private var sampleWork: [VolumeAnalytics.ExerciseWork] {
        [VolumeAnalytics.ExerciseWork(exerciseID: "tue-bench-barbell", name: "Press de banca con barra",
                                      date: day(-3), workSets: 3, volumeKg: 2400),
         VolumeAnalytics.ExerciseWork(exerciseID: "thu-hack-squat", name: "Hack squat",
                                      date: day(-1), workSets: 4, volumeKg: 5600)]
    }

    func testTrainingSectionAddsUpSetsAndTonnage() {
        var input = ReportInput(period: period())
        input.work = sampleWork
        input.sessionsCompleted = 2
        input.sessionsScheduled = 3
        input.programmedSets = 7
        let report = ReportBuilder.build(input)

        XCTAssertTrue(report.training.hasEnoughData)
        XCTAssertEqual(report.training.workSets, 7)
        XCTAssertEqual(report.training.tonnageKg, 8000)
        XCTAssertEqual(report.training.adherence.fraction!, 1, accuracy: 0.0001)
        XCTAssertTrue(report.highlights.contains { $0.contains("8.000 kg") || $0.contains("8000 kg") })
    }

    func testUntrainedGroupsAreListed() {
        var input = ReportInput(period: period())
        input.work = sampleWork
        let report = ReportBuilder.build(input)
        // Se ha entrenado pecho y cuádriceps, así que el bíceps aparece sin trabajo directo.
        XCTAssertTrue(report.training.untrainedGroups.contains(.biceps))
        XCTAssertFalse(report.training.untrainedGroups.contains(.chest))
    }

    func testExercisesOutsideTheLibraryAreReportedAsSuch() {
        var input = ReportInput(period: period())
        input.work = [VolumeAnalytics.ExerciseWork(exerciseID: "custom-1", name: "Invento raro",
                                                   date: day(-1), workSets: 3, volumeKg: 100)]
        let report = ReportBuilder.build(input)
        XCTAssertEqual(report.training.unclassifiedExercises, ["Invento raro"])
        XCTAssertTrue(report.caveats.contains { $0.contains("no están en la biblioteca") })
    }

    func testOnlyBrokenRecordsAreCountedNotFirstEverValues() {
        var input = ReportInput(period: period())
        input.work = sampleWork
        input.records = [
            RecordCandidate(kind: .topWeight, exerciseID: "a", exerciseName: "A", value: 100,
                            weightKg: 100, reps: 5, date: day(-1), previous: 95),
            RecordCandidate(kind: .topWeight, exerciseID: "b", exerciseName: "B", value: 50,
                            weightKg: 50, reps: 5, date: day(-1), previous: nil),
        ]
        XCTAssertEqual(ReportBuilder.build(input).training.newRecords, 1)
    }

    // MARK: Nutrición

    private func nutritionDays(_ count: Int, kcal: Double = 2300, protein: Double = 180) -> [ReportInput.NutritionDay] {
        (0..<count).map { ReportInput.NutritionDay(date: day(-$0), kcal: kcal, protein: protein, carbs: 250, fat: 65) }
    }

    func testFewLoggedDaysMeansNoReliableAverage() {
        var input = ReportInput(period: period())
        input.nutritionDays = nutritionDays(2)
        let report = ReportBuilder.build(input)
        XCTAssertFalse(report.nutrition.hasEnoughData)
        XCTAssertTrue(report.caveats.contains { $0.contains("no representa lo que comes") })
        // Y sin datos suficientes no se saca ninguna frase de nutrición.
        XCTAssertFalse(report.highlights.contains { $0.contains("kcal al día") })
    }

    func testEnoughDaysGivesAveragesAndCompareWithTheTarget() {
        var input = ReportInput(period: period())
        input.nutritionDays = nutritionDays(6, kcal: 2500)
        input.kcalTarget = 2300
        input.proteinTarget = 180
        let report = ReportBuilder.build(input)
        XCTAssertTrue(report.nutrition.hasEnoughData)
        XCTAssertEqual(report.nutrition.averageKcal!, 2500, accuracy: 0.0001)
        XCTAssertEqual(report.nutrition.kcalDifference!, 200, accuracy: 0.0001)
        XCTAssertEqual(report.nutrition.proteinDifference!, 0, accuracy: 0.0001)
        XCTAssertTrue(report.highlights.contains { $0.contains("por encima") })
    }

    func testPartialCoverageIsFlaggedEvenWithEnoughDays() {
        var input = ReportInput(period: ReportRange.month.period(endingAt: today))
        input.nutritionDays = nutritionDays(5)
        let report = ReportBuilder.build(input)
        XCTAssertTrue(report.nutrition.hasEnoughData)
        XCTAssertLessThan(report.nutrition.coverage!, 0.7)
        XCTAssertTrue(report.caveats.contains { $0.contains("orientativa") })
    }

    func testTargetsAreOptional() {
        var input = ReportInput(period: period())
        input.nutritionDays = nutritionDays(6)
        let report = ReportBuilder.build(input)
        XCTAssertNil(report.nutrition.kcalDifference)
    }

    // MARK: Cuerpo

    func testWeightNeedsTwoWeeksToShowATrend() {
        var input = ReportInput(period: period())
        // Tres pesajes, pero todos de la misma semana: se cuelgan del lunes de esta semana
        // para que la prueba no dependa de en qué día caiga «hoy».
        let monday = DateUtils.startOfWeek(today)
        func inThisWeek(_ days: Int) -> Date { monday.addingTimeInterval(Double(days) * 86_400) }
        input.weights = [.init(date: inThisWeek(0), kg: 80), .init(date: inThisWeek(1), kg: 80.4),
                         .init(date: inThisWeek(2), kg: 79.8)]
        let report = ReportBuilder.build(input)
        XCTAssertEqual(report.body.weighIns, 3)
        XCTAssertFalse(report.body.hasEnoughData)
        XCTAssertNil(report.body.change)
        XCTAssertTrue(report.caveats.contains { $0.contains("dos semanas distintas") })
    }

    func testWeeklyAveragesSmoothOutDailyNoise() {
        let points: [WeightStats.Point] = [.init(date: day(-13), kg: 80), .init(date: day(-12), kg: 81),
                                           .init(date: day(-1), kg: 79), .init(date: day(0), kg: 79)]
        let weekly = ReportBuilder.weeklyAverages(points)
        XCTAssertEqual(weekly.count, 2)
        XCTAssertEqual(weekly.first!.kg, 80.5, accuracy: 0.0001)
        XCTAssertEqual(weekly.last!.kg, 79, accuracy: 0.0001)
        // Y están ordenadas de la más antigua a la más reciente.
        XCTAssertLessThan(weekly.first!.date, weekly.last!.date)
    }

    func testWeightChangeUsesWeeklyAveragesNotSinglePoints() {
        var input = ReportInput(period: ReportRange.month.period(endingAt: today))
        input.weights = [.init(date: day(-20), kg: 82), .init(date: day(-19), kg: 82),
                         .init(date: day(-1), kg: 80), .init(date: day(0), kg: 80)]
        let report = ReportBuilder.build(input)
        XCTAssertTrue(report.body.hasEnoughData)
        XCTAssertEqual(report.body.change!, -2, accuracy: 0.0001)
        XCTAssertNotNil(report.body.changePerWeek)
        XCTAssertTrue(report.highlights.contains { $0.contains("bajado") })
    }

    // MARK: Recuperación

    func testRecoveryNeedsAFewDays() {
        var input = ReportInput(period: period())
        input.recovery = [RecoveryEntry(date: day(0), sleepHours: 8)]
        let report = ReportBuilder.build(input)
        XCTAssertFalse(report.recovery.hasEnoughData)
        XCTAssertTrue(report.caveats.contains { $0.contains("no hay base para una media") })
    }

    func testRecoveryAveragesAppearWithEnoughDays() {
        var input = ReportInput(period: period())
        input.recovery = (0..<4).map { RecoveryEntry(date: day(-$0), sleepHours: 7.5, energy: 4) }
        let report = ReportBuilder.build(input)
        XCTAssertTrue(report.recovery.hasEnoughData)
        XCTAssertTrue(report.highlights.contains { $0.contains("horas de media") })
    }

    // MARK: Causalidad

    func testAFullReportWarnsAgainstReadingCauseIntoIt() {
        var input = ReportInput(period: ReportRange.month.period(endingAt: today))
        input.work = sampleWork
        input.sessionsCompleted = 2
        input.nutritionDays = nutritionDays(25)
        input.weights = [.init(date: day(-20), kg: 82), .init(date: day(0), kg: 80)]
        let report = ReportBuilder.build(input)
        XCTAssertTrue(report.caveats.contains { $0.contains("no demuestra que una cosa haya causado otra") })
    }

    // MARK: Comparar

    func testComparisonOnlyIncludesWhatBothPeriodsHave() {
        var current = ReportInput(period: period())
        current.work = sampleWork
        current.sessionsCompleted = 3
        var previous = ReportInput(period: ReportRange.week.previousPeriod(endingAt: today))
        previous.work = [VolumeAnalytics.ExerciseWork(exerciseID: "tue-bench-barbell", name: "Press de banca con barra",
                                                      date: day(-9), workSets: 2, volumeKg: 1600)]
        previous.sessionsCompleted = 1

        let comparison = ReportComparer.compare(current: ReportBuilder.build(current),
                                                previous: ReportBuilder.build(previous))
        let sessions = comparison.deltas.first { $0.label == "Sesiones" }!
        XCTAssertEqual(sessions.difference, 2)
        XCTAssertEqual(sessions.percent!, 200, accuracy: 0.0001)
        XCTAssertEqual(sessions.higherIsBetter, true)
        // Sin nutrición en ninguno de los dos, no hay nada que comparar de nutrición.
        XCTAssertFalse(comparison.deltas.contains { $0.label == "Kcal al día" })
    }

    func testWeightComparisonHasNoBetterDirection() {
        var current = ReportInput(period: period())
        current.weights = [.init(date: day(0), kg: 80)]
        var previous = ReportInput(period: ReportRange.week.previousPeriod(endingAt: today))
        previous.weights = [.init(date: day(-8), kg: 82)]
        let comparison = ReportComparer.compare(current: ReportBuilder.build(current),
                                                previous: ReportBuilder.build(previous))
        let weight = comparison.deltas.first { $0.label == "Peso" }!
        XCTAssertNil(weight.higherIsBetter)
        XCTAssertEqual(weight.difference, -2, accuracy: 0.0001)
    }

    func testPercentIsNilWhenThereIsNothingToCompareAgainst() {
        let delta = ReportComparison.Delta(label: "Series", current: 10, previous: 0, higherIsBetter: true)
        XCTAssertNil(delta.percent)
        XCTAssertEqual(delta.difference, 10)
    }
}
