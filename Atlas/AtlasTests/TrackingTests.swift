import XCTest
@testable import Atlas

/// Calendario, racha, objetivo adaptativo, avisos, medias de peso, resumen semanal, medallas y copia de seguridad.
final class TrackingTests: XCTestCase {
    private let cal = DateUtils.calendar

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func input(_ date: Date, meals: Int = 4, scheduled: Int = 1, completed: Int = 1,
                       steps: Int? = 8000, goal: Int = 8000, mark: DayMark? = nil) -> DayInput {
        DayInput(date: date, mealsCompleted: meals, sessionsScheduled: scheduled, sessionsCompleted: completed,
                 steps: steps, stepGoal: goal, explicitMark: mark)
    }

    // 2026-10-19 es lunes; 2026-10-23 es viernes.
    private var start: Date { day(2026, 10, 1) }
    private var today: Date { day(2026, 10, 25, hour: 18) }

    // MARK: Días

    func testFridayIsRestByDefaultButCanBeChanged() {
        let friday = day(2026, 10, 23)
        XCTAssertEqual(DateUtils.weekdayMondayBased(friday), 5)
        XCTAssertEqual(DayEvaluator.outcome(input(friday, meals: 0, completed: 0, steps: nil), today: today, trackingStart: start),
                       .excused(.rest))
        // Marcado como normal: se evalúa (y sin nada hecho, es fallo).
        XCTAssertEqual(DayEvaluator.outcome(input(friday, meals: 0, scheduled: 0, completed: 0, steps: nil, mark: .normal),
                                            today: today, trackingStart: start), .missed(0))
        // Entrenado un viernes (adelantar el sábado): cumplido.
        XCTAssertEqual(DayEvaluator.outcome(input(friday, meals: 0, completed: 0, mark: .trained), today: today, trackingStart: start),
                       .trained)
        XCTAssertEqual(DayMark.effective(explicit: nil, weekday: 5), .rest)
        XCTAssertEqual(DayMark.effective(explicit: nil, weekday: 2), .normal)
    }

    func testDoneMissedTodayAndFuture() {
        let monday = day(2026, 10, 19)
        XCTAssertEqual(DayEvaluator.outcome(input(monday), today: today, trackingStart: start), .done(1))
        // Comidas 2/4 (0,5), entreno 0/1 (0), pasos 4000/8000 (0,5) → 0,33: fallo.
        let bad = DayEvaluator.outcome(input(monday, meals: 2, completed: 0, steps: 4000), today: today, trackingStart: start)
        XCTAssertTrue(bad.isMissed)
        XCTAssertEqual(bad.fraction ?? -1, 1.0 / 3, accuracy: 0.001)
        // Hoy sin cumplir todavía: en curso, no fallo.
        let sunday = day(2026, 10, 25, hour: 9)
        XCTAssertEqual(DayEvaluator.outcome(input(sunday, meals: 1, completed: 0, steps: nil), today: today, trackingStart: start),
                       .today(0.125))
        XCTAssertEqual(DayEvaluator.outcome(input(day(2026, 10, 26)), today: today, trackingStart: start), .future)
        // Antes de empezar a usar la app no cuenta.
        XCTAssertEqual(DayEvaluator.outcome(input(day(2026, 9, 28), meals: 0, completed: 0, steps: nil), today: today, trackingStart: start),
                       .beforeStart)
    }

    func testSickAndWorkAreExcused() {
        let tuesday = day(2026, 10, 20)
        for mark in [DayMark.sick, .work, .rest] {
            XCTAssertEqual(DayEvaluator.outcome(input(tuesday, meals: 0, completed: 0, steps: 10, mark: mark), today: today, trackingStart: start),
                           .excused(mark))
            XCTAssertTrue(mark.isExcused)
        }
        XCTAssertFalse(DayMark.trained.isExcused)
        XCTAssertFalse(DayMark.normal.isExcused)
    }

    // MARK: Racha

    func testStreakExcusedDaysDoNotBreakIt() {
        let r = Streak.compute([.done(1), .missed(0.2), .done(0.8), .excused(.sick), .excused(.sick), .trained, .done(0.9), .today(0.1)])
        XCTAssertEqual(r.current, 3)
        XCTAssertEqual(r.best, 3)
        XCTAssertEqual(Streak.compute([.done(1), .done(1), .missed(0)]), Streak.Result(current: 0, best: 2))
        XCTAssertEqual(Streak.compute([.beforeStart, .excused(.rest), .done(1)]).current, 1)
        XCTAssertEqual(Streak.compute([]).current, 0)
    }

    // MARK: Objetivo de pasos

    func testAdaptiveStepGoal() {
        XCTAssertNil(AdaptiveStepGoal.suggest(recentDailySteps: [9000, 9000]), "Menos de 3 días: no cambia")
        XCTAssertNil(AdaptiveStepGoal.suggest(recentDailySteps: [9000, 0, 0, 9000]), "Los días a 0 no cuentan")
        // Media 9000 → +5 % = 9450 → redondeado a 250 = 9500.
        XCTAssertEqual(AdaptiveStepGoal.suggest(recentDailySteps: [8000, 9000, 10000]), 9500)
        XCTAssertEqual(AdaptiveStepGoal.suggest(recentDailySteps: [500, 600, 700]), 3000, "Mínimo 3.000")
        XCTAssertEqual(AdaptiveStepGoal.suggest(recentDailySteps: [40000, 40000, 40000]), 20000, "Máximo 20.000")
    }

    // MARK: Avisos

    func testReminderTimeStaysInRangeAndIsStable() {
        let from = ClockTime(hour: 18, minute: 30), to = ClockTime(hour: 19, minute: 30)
        for d in 1...28 {
            let key = String(format: "2026-10-%02d", d)
            let t = ReminderTiming.time(forDayKey: key, from: from, to: to)
            XCTAssertGreaterThanOrEqual(t.minutesOfDay, from.minutesOfDay)
            XCTAssertLessThanOrEqual(t.minutesOfDay, to.minutesOfDay)
            XCTAssertEqual(t, ReminderTiming.time(forDayKey: key, from: from, to: to), "Misma hora para el mismo día")
        }
        XCTAssertEqual(ReminderTiming.time(forDayKey: "2026-10-01", from: from, to: from), from, "Hora exacta")
        XCTAssertEqual(ReminderTiming.time(forDayKey: "2026-10-01", from: to, to: from), to, "Rango al revés: la primera hora")
        XCTAssertEqual(ClockTime(minutesOfDay: 18 * 60 + 5).text, "18:05")
    }

    func testStepsBelowHalf() {
        XCTAssertTrue(ReminderTiming.stepsBelowHalf(steps: 3999, goal: 8000))
        XCTAssertFalse(ReminderTiming.stepsBelowHalf(steps: 4000, goal: 8000))
        XCTAssertFalse(ReminderTiming.stepsBelowHalf(steps: nil, goal: 8000), "Sin datos no se avisa")
    }

    // MARK: Peso

    func testMonthlyAveragesAndTrend() {
        let points = [
            WeightStats.Point(date: day(2026, 9, 5), kg: 82),
            WeightStats.Point(date: day(2026, 9, 25), kg: 80),
            WeightStats.Point(date: day(2026, 10, 2), kg: 79),
            WeightStats.Point(date: day(2026, 10, 9), kg: 78),
            WeightStats.Point(date: day(2026, 10, 10), kg: 77),
        ]
        let months = WeightStats.monthlyAverages(points)
        XCTAssertEqual(months.map(\.month), [9, 10])
        XCTAssertEqual(months[0].averageKg, 81, accuracy: 0.0001)
        XCTAssertEqual(months[1].averageKg, 78, accuracy: 0.0001)
        XCTAssertEqual(months[1].count, 3)
        XCTAssertEqual(cal.component(.day, from: months[1].start), 1)
        XCTAssertEqual(cal.component(.day, from: months[1].end), 31)

        let trend = WeightStats.movingAverage(points, days: 7)
        XCTAssertEqual(trend.count, points.count)
        XCTAssertEqual(trend[0].kg, 82, accuracy: 0.0001)
        // 9 y 10 de octubre: ventana de 7 días con 78 y 77 (el 2 queda fuera para el 10).
        XCTAssertEqual(trend[4].kg, 77.5, accuracy: 0.0001)
    }

    func testWeekChange() {
        let weekStart = cal.startOfDay(for: day(2026, 10, 19))
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart)!
        let before = WeightStats.Point(date: day(2026, 10, 15), kg: 80)
        let inWeek = [WeightStats.Point(date: day(2026, 10, 20), kg: 79.6), WeightStats.Point(date: day(2026, 10, 24), kg: 79.2)]
        XCTAssertEqual(WeightStats.weekChange([before] + inWeek, weekStart: weekStart, weekEnd: weekEnd)!, -0.8, accuracy: 0.0001)
        XCTAssertEqual(WeightStats.weekChange(inWeek, weekStart: weekStart, weekEnd: weekEnd)!, -0.4, accuracy: 0.0001)
        XCTAssertNil(WeightStats.weekChange([before], weekStart: weekStart, weekEnd: weekEnd))
    }

    // MARK: Resumen semanal

    func testWeeklySummary() {
        let weekStart = cal.startOfDay(for: day(2026, 10, 19))
        let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart)!
        let runs = [RunSample(date: day(2026, 10, 19), meters: 5200, seconds: 1800),
                    RunSample(date: day(2026, 10, 24), meters: 8000, seconds: 2900),
                    RunSample(date: day(2026, 10, 12), meters: 10000, seconds: 3600)]
        let outcomes: [DayOutcome] = [.done(1), .missed(0.3), .done(0.8), .trained, .excused(.rest), .excused(.sick), .today(0.2)]
        let s = WeeklySummary.make(stepsByDay: [8000, 0, 10000, 6000], runs: runs, weights: [],
                                   outcomes: outcomes, weekStart: weekStart, weekEnd: weekEnd)
        XCTAssertEqual(s.averageSteps, 8000)
        XCTAssertEqual(s.daysWithSteps, 3)
        XCTAssertEqual(s.runs, 2)
        XCTAssertEqual(s.kilometers, 13.2, accuracy: 0.0001)
        XCTAssertNil(s.weightChange)
        XCTAssertEqual(s.daysDone, 3)
        XCTAssertEqual(s.daysExcused, 2)
        XCTAssertEqual(s.daysMissed, 1)
        XCTAssertEqual(s.daysCounted, 6)
    }

    // MARK: Medallas

    func testMedalTiers() {
        XCTAssertEqual(Medals.tier(4.9, thresholds: [5, 10, 21.1]), .locked)
        XCTAssertEqual(Medals.tier(10, thresholds: [5, 10, 21.1]), .silver)
        XCTAssertEqual(Medals.tier(25, thresholds: [5, 10, 21.1]), .gold)
        // Ritmo: menos es mejor (7:00, 6:00, 5:00 /km).
        XCTAssertEqual(Medals.tier(350, thresholds: [420, 360, 300], higherIsBetter: false), .silver)
        XCTAssertEqual(Medals.tier(450, thresholds: [420, 360, 300], higherIsBetter: false), .locked)
        XCTAssertEqual(Medals.progress(7.5, thresholds: [5, 10, 21.1]).fraction, 0.75, accuracy: 0.0001)
        XCTAssertNil(Medals.progress(30, thresholds: [5, 10, 21.1]).next)
    }

    func testMedalsFromData() {
        var input = MedalInput()
        input.runs = [RunSample(date: day(2026, 10, 5), meters: 12000, seconds: 4200),   // 5:50 /km
                      RunSample(date: day(2026, 10, 12), meters: 4000, seconds: 1000),   // < 5 km: no cuenta para el ritmo
                      RunSample(date: day(2026, 10, 19), meters: 6000, seconds: 2400)]   // 6:40 /km
        input.dailySteps = [(date: day(2026, 10, 1), steps: 9000), (date: day(2026, 10, 2), steps: 16000)]
        input.bestStreak = 8
        input.strengthSessions = 3
        let medals = Dictionary(uniqueKeysWithValues: Medals.all(input).map { ($0.id, $0) })
        XCTAssertEqual(medals["longest-run"]?.tier, .silver)
        XCTAssertEqual(medals["longest-run"]?.date, day(2026, 10, 5))
        XCTAssertEqual(medals["best-5k-pace"]?.tier, .silver, "5:50 /km")
        XCTAssertEqual(medals["best-5k-pace"]?.date, day(2026, 10, 5))
        XCTAssertEqual(medals["most-steps"]?.tier, .silver)
        XCTAssertEqual(medals["best-streak"]?.tier, .bronze)
        XCTAssertEqual(medals["total-km"]?.tier, .locked)
        XCTAssertEqual(medals["strength"]?.tier, .locked)
        XCTAssertNotNil(medals["strength"]?.value)
        XCTAssertNil(medals["weigh-ins"]?.value, "Sin datos: sin valor inventado")
        XCTAssertEqual(medals.count, 8)
    }

    // MARK: Copia de seguridad

    func testBackupRoundTripAndValidation() throws {
        let settings = BackupFile.Settings(
            kcalTarget: 2300, proteinTarget: 180, carbsTarget: 250, fatTarget: 65, stepGoal: 9500,
            trackingStartDate: day(2026, 10, 1), onboardingCompleted: true, creatineReminderEnabled: false,
            creatineHour: 9, creatineMinute: 0, photoReminderEnabled: false, photoReminderHour: 20, defaultPlanID: UUID(),
            stravaClientID: "", stravaBackendURL: "", heightCm: 180, age: 30, sexRaw: "male", activityRaw: "moderate",
            goalRaw: "recomposition", autoTargets: true, stepGoalAdaptive: true, stepGoalAdjustedDayKey: "2026-10-23",
            stepReminderEnabled: true, stepReminderFromMinutes: 1110, stepReminderToMinutes: 1170,
            weightReminderEnabled: true, weightReminderFromMinutes: 600, weightReminderToMinutes: 600)
        var file = BackupFile(createdAt: day(2026, 10, 23), appVersion: "1.1", settings: settings)
        file.weights = [.init(id: UUID(), date: day(2026, 10, 2), weightKg: 79.4, waistCm: nil, note: "")]
        file.sessionLogs = [.init(weekStart: cal.startOfDay(for: day(2026, 10, 19)), sessionID: "tue-push-a", isCompleted: true,
                                  completedAt: day(2026, 10, 20), notes: "", lastModified: day(2026, 10, 20),
                                  exercises: [.init(exerciseID: "x", order: 0, isCompleted: true, name: "Press", targetSets: 3,
                                                    repRange: "8–12")])]
        file.photos = [.init(year: 2026, month: 10, viewRaw: "front", fileName: "a.jpg", createdAt: day(2026, 10, 1),
                             updatedAt: day(2026, 10, 1), imageData: Data([0xFF, 0xD8, 0xFF, 0x00]))]
        file.dayMarks = [.init(dayKey: "2026-10-20", date: day(2026, 10, 20, hour: 0), markRaw: "sick")]
        file.dailySteps = [.init(dayKey: "2026-10-20", date: day(2026, 10, 20, hour: 0), steps: 7300, goal: 8000)]

        let data = try file.encoded()
        let back = try BackupFile.decode(data)
        XCTAssertEqual(back, file)
        XCTAssertTrue(back.summary.contains("1 pesajes"))

        XCTAssertThrowsError(try BackupFile.decode(Data("{\"hola\":1}".utf8))) { error in
            XCTAssertEqual(error as? BackupFile.BackupError, .notABackup)
        }
        var newer = file
        newer.format = BackupFile.currentFormat + 1
        XCTAssertThrowsError(try BackupFile.decode(try newer.encoded())) { error in
            XCTAssertEqual(error as? BackupFile.BackupError, .newerFormat(BackupFile.currentFormat + 1))
        }
        XCTAssertEqual(BackupFile.suggestedFileName(for: day(2026, 10, 23)), "NowOrNever-copia-2026-10-23.json")
    }
}
