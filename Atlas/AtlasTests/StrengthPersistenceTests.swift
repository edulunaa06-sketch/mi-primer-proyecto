#if canImport(SwiftData)
import SwiftData
import XCTest
@testable import Atlas

/// Pruebas de persistencia de la fuerza: series guardadas, historial entre semanas, récords,
/// cronómetro, recuperación, suplementos y copia de seguridad (se ejecutan en el simulador).
@MainActor
final class StrengthPersistenceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        container = try ModelContainer(for: AtlasApp.schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
        defaults = UserDefaults(suiteName: "strength-\(UUID().uuidString)")
        DataStore.seedRoutineIfNeeded(context, defaults: defaults)
    }

    private func routine() -> [RoutineExercise] {
        (try? context.fetch(FetchDescriptor<RoutineExercise>())) ?? []
    }

    /// Crea el registro de una sesión de fuerza de una semana concreta.
    private func makeLog(weeksAgo: Int = 0, session base: SessionDefinition = WeeklyRoutine.tuesdayPushA) -> WorkoutSessionLog {
        let week = DateUtils.calendar.date(byAdding: .day, value: -7 * weeksAgo,
                                           to: DateUtils.startOfWeek(Date()))!
        let resolved = base.resolved(with: routine())
        return DataStore.fetchOrCreateLog(for: resolved, weekStart: DateUtils.startOfWeek(week), in: context)
    }

    private func firstExercise(_ log: WorkoutSessionLog) -> ExerciseLog {
        log.sortedExercises.first!
    }

    // MARK: Series

    func testSetsAreCreatedForThePrescribedNumberOfSets() {
        let log = makeLog()
        let exercise = firstExercise(log)
        StrengthStore.ensureSets(for: exercise, in: context)
        XCTAssertEqual(exercise.sets.count, exercise.targetSets)
        XCTAssertGreaterThan(exercise.targetSets, 0)
        // Nacen vacías: los kilos los pone el usuario.
        XCTAssertFalse(exercise.hasLoggedData)
        XCTAssertEqual(exercise.workSets, 0)
    }

    func testEnsureSetsDoesNotDuplicateOrOverwrite() {
        let log = makeLog()
        let exercise = firstExercise(log)
        StrengthStore.ensureSets(for: exercise, in: context)
        exercise.sortedSets[0].weightKg = 80
        exercise.sortedSets[0].reps = 10
        try? context.save()

        StrengthStore.ensureSets(for: exercise, in: context)
        XCTAssertEqual(exercise.sets.count, exercise.targetSets, "No se añaden series de más")
        XCTAssertEqual(exercise.sortedSets[0].weightKg, 80, "No se pisa lo apuntado")
        XCTAssertEqual(exercise.sortedSets[0].reps, 10)
    }

    func testSetsSurviveSavingAndReloading() throws {
        let log = makeLog()
        let exercise = firstExercise(log)
        StrengthStore.ensureSets(for: exercise, in: context)
        exercise.sortedSets[0].weightKg = 82.5
        exercise.sortedSets[0].reps = 8
        exercise.sortedSets[0].rir = 2
        exercise.sortedSets[0].markCompleted(true)
        try context.save()

        // Se vuelve a leer desde la base de datos, no desde el objeto que ya teníamos.
        let reloaded = try context.fetch(FetchDescriptor<SetLog>()).first { $0.weightKg == 82.5 }
        XCTAssertNotNil(reloaded)
        XCTAssertEqual(reloaded?.reps, 8)
        XCTAssertEqual(reloaded?.rir, 2)
        XCTAssertEqual(reloaded?.isCompleted, true)
        XCTAssertNotNil(reloaded?.completedAt)
    }

    func testAddAndRemoveSetsKeepTheOrderTidy() {
        let log = makeLog()
        let exercise = firstExercise(log)
        StrengthStore.ensureSets(for: exercise, in: context)
        let initial = exercise.sets.count

        let added = StrengthStore.addSet(to: exercise, in: context)
        XCTAssertEqual(exercise.sets.count, initial + 1)
        XCTAssertEqual(added.order, initial)

        StrengthStore.removeSet(exercise.sortedSets[0], in: context)
        XCTAssertEqual(exercise.sets.count, initial)
        XCTAssertEqual(exercise.sortedSets.map(\.order), Array(0..<initial), "Los números no dejan huecos")
    }

    func testANewSetInheritsTheWeightOfTheLastOne() {
        let log = makeLog()
        let exercise = firstExercise(log)
        StrengthStore.ensureSets(for: exercise, in: context)
        exercise.sortedSets.last?.weightKg = 60
        let added = StrengthStore.addSet(to: exercise, in: context)
        XCTAssertEqual(added.weightKg, 60)
        XCTAssertNil(added.reps, "Las repeticiones no se heredan: cada serie es la suya")
    }

    func testWarmupSetsDoNotCountInTheSessionTotals() {
        let log = makeLog()
        let exercise = firstExercise(log)
        StrengthStore.ensureSets(for: exercise, in: context)
        exercise.sortedSets[0].kind = .warmup
        exercise.sortedSets[0].weightKg = 40
        exercise.sortedSets[0].reps = 10
        exercise.sortedSets[1].weightKg = 80
        exercise.sortedSets[1].reps = 10
        try? context.save()

        XCTAssertEqual(exercise.workSets, 1)
        XCTAssertEqual(exercise.volumeKg, 800)
        XCTAssertEqual(log.workSets, 1)
        XCTAssertEqual(log.tonnageKg, 800)
    }

    // MARK: Historial entre semanas

    func testHistoryGathersPreviousWeeksInOrder() {
        for weeksAgo in [2, 1] {
            let log = makeLog(weeksAgo: weeksAgo)
            log.isCompleted = true
            log.completedAt = log.weekStart
            let exercise = firstExercise(log)
            StrengthStore.ensureSets(for: exercise, in: context)
            exercise.sortedSets[0].weightKg = weeksAgo == 2 ? 70 : 75
            exercise.sortedSets[0].reps = 10
            try? context.save()
        }
        let id = firstExercise(makeLog()).exerciseID
        let history = StrengthStore.history(exerciseID: id, in: context)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.map(\.date), history.map(\.date).sorted(), "De la más antigua a la más reciente")
        XCTAssertEqual(history.last?.topWeightKg, 75)
    }

    func testPreviousSetsComeFromTheLastWeekWithData() {
        let old = makeLog(weeksAgo: 1)
        let oldExercise = firstExercise(old)
        StrengthStore.ensureSets(for: oldExercise, in: context)
        oldExercise.sortedSets[0].weightKg = 72.5
        oldExercise.sortedSets[0].reps = 9
        try? context.save()

        let current = makeLog()
        let previous = StrengthStore.previousSets(exerciseID: firstExercise(current).exerciseID,
                                                  before: current.weekStart, in: context)
        XCTAssertEqual(previous.first?.weightKg, 72.5)
        XCTAssertEqual(previous.first?.reps, 9)
    }

    func testNewSetsStartWithTheWeightSuggestedByProgression() {
        // La semana pasada cerró el rango: la progresión propone subir, y las series nuevas nacen con ese peso.
        let old = makeLog(weeksAgo: 1)
        old.isCompleted = true
        old.completedAt = old.weekStart
        let oldExercise = firstExercise(old)
        StrengthStore.ensureSets(for: oldExercise, in: context)
        let target = oldExercise.repTarget
        for set in oldExercise.sortedSets {
            set.weightKg = 80
            set.reps = target.max
            set.rir = 2
        }
        try? context.save()

        let current = makeLog()
        let exercise = firstExercise(current)
        StrengthStore.ensureSets(for: exercise, in: context)
        let advice = StrengthStore.advice(for: exercise, in: context)
        XCTAssertEqual(advice.action, .increaseLoad)
        XCTAssertEqual(exercise.sortedSets.first?.weightKg, advice.suggestedWeightKg)
        XCTAssertGreaterThan(exercise.sortedSets.first?.weightKg ?? 0, 80)
    }

    func testAdviceIgnoresTheSessionBeingLogged() {
        // Una sola sesión, la de esta semana: no hay nada anterior con lo que comparar.
        let current = makeLog()
        let exercise = firstExercise(current)
        StrengthStore.ensureSets(for: exercise, in: context)
        exercise.sortedSets[0].weightKg = 100
        exercise.sortedSets[0].reps = 12
        try? context.save()
        XCTAssertEqual(StrengthStore.advice(for: exercise, in: context).action, .needMoreData)
    }

    func testDiscomfortBlocksTheIncrease() {
        let old = makeLog(weeksAgo: 1)
        old.isCompleted = true
        old.completedAt = old.weekStart
        let oldExercise = firstExercise(old)
        StrengthStore.ensureSets(for: oldExercise, in: context)
        let target = oldExercise.repTarget
        oldExercise.sortedSets[0].weightKg = 80
        oldExercise.sortedSets[0].reps = target.max
        oldExercise.sortedSets[0].rir = 2
        try? context.save()

        let current = makeLog()
        let exercise = firstExercise(current)
        exercise.hasDiscomfort = true
        try? context.save()
        XCTAssertEqual(StrengthStore.advice(for: exercise, in: context).action, .hold)
    }

    // MARK: Cronómetro

    func testTheClockSurvivesClosingTheApp() {
        let log = makeLog()
        let start = Date()
        log.startOrResume(at: start)
        XCTAssertTrue(log.isRunning)
        // Diez minutos después, sin haber tocado nada.
        XCTAssertEqual(log.elapsedSeconds(at: start.addingTimeInterval(600)), 600)

        log.pause(at: start.addingTimeInterval(600))
        XCTAssertFalse(log.isRunning)
        XCTAssertEqual(log.accumulatedSeconds, 600)
        // En pausa el tiempo no corre.
        XCTAssertEqual(log.elapsedSeconds(at: start.addingTimeInterval(1200)), 600)

        log.startOrResume(at: start.addingTimeInterval(1200))
        XCTAssertEqual(log.elapsedSeconds(at: start.addingTimeInterval(1500)), 900)
    }

    func testFinishingStopsTheClockAndStampsTheTime() {
        let log = makeLog()
        log.startOrResume(at: Date().addingTimeInterval(-300))
        log.finish()
        XCTAssertFalse(log.isRunning)
        XCTAssertNotNil(log.finishedAt)
        XCTAssertGreaterThanOrEqual(log.accumulatedSeconds, 300)
    }

    // MARK: Récords

    func testFirstSessionCreatesStartingMarksAndTheNextOneBreaksThem() {
        let first = makeLog(weeksAgo: 1)
        first.completedAt = first.weekStart
        let firstExerciseLog = firstExercise(first)
        StrengthStore.ensureSets(for: firstExerciseLog, in: context)
        firstExerciseLog.sortedSets[0].weightKg = 80
        firstExerciseLog.sortedSets[0].reps = 8
        try? context.save()

        let starting = StrengthStore.updateRecords(from: first, in: context)
        XCTAssertFalse(starting.isEmpty)
        XCTAssertTrue(starting.allSatisfy(\.isFirstEver), "La primera vez son marcas de partida, no récords")

        let second = makeLog()
        second.completedAt = Date()
        let secondExerciseLog = firstExercise(second)
        StrengthStore.ensureSets(for: secondExerciseLog, in: context)
        secondExerciseLog.sortedSets[0].weightKg = 85
        secondExerciseLog.sortedSets[0].reps = 8
        try? context.save()

        let broken = StrengthStore.updateRecords(from: second, in: context)
        let weightRecord = broken.first { $0.kind == .topWeight }
        XCTAssertNotNil(weightRecord)
        XCTAssertEqual(weightRecord?.previous, 80)
        XCTAssertEqual(weightRecord?.improvement, 5)

        // Solo queda un registro por ejercicio y tipo, con el mejor valor.
        let stored = StrengthStore.records(in: context).filter { $0.kind == .topWeight }
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.value, 85)
        XCTAssertEqual(stored.first?.previousValue, 80)
    }

    func testASessionWithoutDataDoesNotCreateRecords() {
        let log = makeLog()
        log.completedAt = Date()
        StrengthStore.ensureSets(for: firstExercise(log), in: context)
        XCTAssertTrue(StrengthStore.updateRecords(from: log, in: context).isEmpty)
        XCTAssertTrue(StrengthStore.records(in: context).isEmpty)
    }

    // MARK: Volumen y descarga

    func testWorkInAPeriodFeedsTheVolumeByMuscle() {
        let log = makeLog()
        log.isCompleted = true
        log.completedAt = Date()
        let exercise = firstExercise(log)
        StrengthStore.ensureSets(for: exercise, in: context)
        for set in exercise.sortedSets {
            set.weightKg = 80
            set.reps = 10
        }
        try? context.save()

        let week = ReportRange.week.period(endingAt: Date())
        let work = StrengthStore.work(from: week.start, to: week.end, in: context)
        XCTAssertFalse(work.isEmpty)
        let volume = VolumeAnalytics.byMuscle(work)
        XCTAssertTrue(volume.unclassified.isEmpty, "Los ejercicios de la rutina están en la biblioteca")
        XCTAssertGreaterThan(volume.muscles.first { $0.group == .chest }?.directSets ?? 0, 0)
    }

    func testDeloadWeekIsStoredAndRead() {
        let week = DateUtils.startOfWeek(Date())
        XCTAssertFalse(StrengthStore.isDeloadWeek(week, in: context))
        StrengthStore.setDeload(true, weekStart: week, in: context)
        XCTAssertTrue(StrengthStore.isDeloadWeek(week, in: context))
        StrengthStore.setDeload(false, weekStart: week, in: context)
        XCTAssertFalse(StrengthStore.isDeloadWeek(week, in: context))
        // Un único registro por semana, no uno por cambio.
        XCTAssertEqual((try? context.fetchCount(FetchDescriptor<TrainingWeek>())) ?? -1, 1)
    }

    // MARK: Recuperación

    func testRecoveryIsOneRecordPerDayAndKeepsWhatYouWrite() {
        let entry = StrengthStore.fetchOrCreateRecovery(for: Date(), in: context)
        entry.sleepHours = 7.5
        entry.fatigue = 2
        try? context.save()

        let again = StrengthStore.fetchOrCreateRecovery(for: Date(), in: context)
        XCTAssertEqual(again.sleepHours, 7.5)
        XCTAssertEqual(again.fatigue, 2)
        XCTAssertEqual((try? context.fetchCount(FetchDescriptor<RecoveryLogEntry>())) ?? -1, 1)
        // Y el valor puro que usan los cálculos sale de ahí.
        XCTAssertEqual(again.entry.sleepHours, 7.5)
        XCTAssertFalse(again.entry.isEmpty)
    }

    func testRecoveryInAPeriodSkipsEmptyDays() {
        let empty = StrengthStore.fetchOrCreateRecovery(for: Date(), in: context)
        XCTAssertTrue(empty.entry.isEmpty)
        let week = ReportRange.week.period(endingAt: Date())
        XCTAssertTrue(StrengthStore.recovery(from: week.start, to: week.end, in: context).isEmpty,
                      "Un día abierto pero sin contestar no cuenta como día apuntado")
        empty.sleepHours = 8
        try? context.save()
        XCTAssertEqual(StrengthStore.recovery(from: week.start, to: week.end, in: context).count, 1)
    }

    // MARK: Suplementos

    func testAddingAndRemovingASupplementAlsoCleansItsIntakes() {
        let info = SupplementCatalog.info(id: "creatine")!
        StrengthStore.addSupplement(from: info, amount: 5, unit: .gram, in: context)
        let stored = StrengthStore.supplements(in: context)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.planItem.dailyAmount, 5)

        StrengthStore.setIntake(1, for: stored[0], on: Date(), in: context)
        XCTAssertEqual((try? context.fetchCount(FetchDescriptor<SupplementIntake>())) ?? -1, 1)

        StrengthStore.remove(stored[0], in: context)
        XCTAssertTrue(StrengthStore.supplements(in: context).isEmpty)
        XCTAssertEqual((try? context.fetchCount(FetchDescriptor<SupplementIntake>())) ?? -1, 0,
                       "No quedan tomas huérfanas")
    }

    func testIntakeIsOneRecordPerDayAndDisappearsAtZero() {
        let info = SupplementCatalog.info(id: "creatine")!
        StrengthStore.addSupplement(from: info, amount: 5, unit: .gram, in: context)
        let supplement = StrengthStore.supplements(in: context)[0]
        StrengthStore.setIntake(1, for: supplement, on: Date(), in: context)
        StrengthStore.setIntake(2, for: supplement, on: Date(), in: context)
        XCTAssertEqual(StrengthStore.intake(for: supplement, on: Date(), in: context)?.dosesTaken, 2)
        XCTAssertEqual((try? context.fetchCount(FetchDescriptor<SupplementIntake>())) ?? -1, 1)
        StrengthStore.setIntake(0, for: supplement, on: Date(), in: context)
        XCTAssertNil(StrengthStore.intake(for: supplement, on: Date(), in: context))
    }

    // MARK: Informe

    func testReportInputPullsEverythingTogether() {
        let log = makeLog()
        log.isCompleted = true
        log.completedAt = Date()
        let exercise = firstExercise(log)
        StrengthStore.ensureSets(for: exercise, in: context)
        exercise.sortedSets[0].weightKg = 80
        exercise.sortedSets[0].reps = 10
        DataStore.addWeight(80, waist: nil, date: Date(), in: context)
        let recovery = StrengthStore.fetchOrCreateRecovery(for: Date(), in: context)
        recovery.sleepHours = 8
        try? context.save()

        let input = StrengthStore.reportInput(range: .week, in: context)
        XCTAssertEqual(input.sessionsCompleted, 1)
        XCTAssertGreaterThan(input.programmedSets, 0)
        XCTAssertEqual(input.weights.count, 1)
        XCTAssertEqual(input.recovery.count, 1)
        XCTAssertNotNil(input.kcalTarget)

        let report = ReportBuilder.build(input)
        XCTAssertTrue(report.hasAnyData)
        XCTAssertTrue(report.training.hasEnoughData)
    }

    // MARK: Copia de seguridad

    func testBackupCarriesSetsRecordsRecoveryAndSupplements() throws {
        // Datos de todo tipo.
        let log = makeLog()
        log.isCompleted = true
        log.completedAt = Date()
        log.startOrResume(at: Date().addingTimeInterval(-600))
        log.finish()
        let exercise = firstExercise(log)
        exercise.note = "Buen día"
        exercise.hasDiscomfort = true
        StrengthStore.ensureSets(for: exercise, in: context)
        exercise.sortedSets[0].weightKg = 82.5
        exercise.sortedSets[0].reps = 8
        exercise.sortedSets[0].rir = 1
        exercise.sortedSets[0].markCompleted(true)
        try context.save()
        StrengthStore.updateRecords(from: log, in: context)
        let recovery = StrengthStore.fetchOrCreateRecovery(for: Date(), in: context)
        recovery.sleepHours = 7
        recovery.hasDiscomfort = true
        StrengthStore.addSupplement(from: SupplementCatalog.info(id: "creatine")!, amount: 5, unit: .gram, in: context)
        StrengthStore.setDeload(true, weekStart: DateUtils.startOfWeek(Date()), in: context)
        try context.save()

        let file = try BackupService.makeBackup(context)
        XCTAssertEqual(file.format, 2)
        let savedSets = file.sessionLogs.flatMap(\.exercises).compactMap(\.sets).flatMap { $0 }
        XCTAssertTrue(savedSets.contains { $0.weightKg == 82.5 && $0.reps == 8 && $0.rir == 1 })
        XCTAssertFalse(file.records?.isEmpty ?? true)
        XCTAssertFalse(file.recovery?.isEmpty ?? true)
        XCTAssertFalse(file.supplements?.isEmpty ?? true)
        XCTAssertEqual(file.trainingWeeks?.first?.isDeload, true)

        // El JSON va y vuelve sin perder nada.
        let restored = try BackupFile.decode(try file.encoded())
        XCTAssertEqual(restored, file)

        // Y al importarlo, los datos vuelven a estar.
        try BackupService.restore(restored, into: context)
        let sets = try context.fetch(FetchDescriptor<SetLog>())
        XCTAssertTrue(sets.contains { $0.weightKg == 82.5 && $0.reps == 8 })
        XCTAssertEqual((try context.fetchCount(FetchDescriptor<PersonalRecordEntry>())) > 0, true)
        XCTAssertEqual((try context.fetchCount(FetchDescriptor<SupplementEntry>())), 1)
        let restoredExercise = try context.fetch(FetchDescriptor<ExerciseLog>()).first { $0.hasDiscomfort }
        XCTAssertEqual(restoredExercise?.note, "Buen día")
        let restoredRecovery = StrengthStore.recoveryLog(for: Date(), in: context)
        XCTAssertEqual(restoredRecovery?.sleepHours, 7)
        XCTAssertEqual(restoredRecovery?.hasDiscomfort, true)
        XCTAssertTrue(StrengthStore.isDeloadWeek(DateUtils.startOfWeek(Date()), in: context))
        let restoredSession = try context.fetch(FetchDescriptor<WorkoutSessionLog>()).first { $0.isCompleted }
        XCTAssertGreaterThanOrEqual(restoredSession?.accumulatedSeconds ?? 0, 600)
        XCTAssertNotNil(restoredSession?.finishedAt)
    }

    func testOldBackupsWithoutTheNewFieldsStillImport() throws {
        // Una copia de formato 1: sin series, sin récords, sin recuperación ni suplementos.
        var file = BackupFile(createdAt: Date(), appVersion: "1.0", settings: oldSettings())
        file.format = 1
        file.sessionLogs = [BackupFile.SessionLog(
            weekStart: DateUtils.startOfWeek(Date()), sessionID: "tue-push-a", isCompleted: true,
            completedAt: Date(), notes: "", lastModified: Date(),
            exercises: [BackupFile.ExerciseLog(exerciseID: "tue-bench-barbell", order: 0, isCompleted: true,
                                               name: "Press de banca con barra", targetSets: 3, repRange: "6–10",
                                               sets: nil, note: nil, hasDiscomfort: nil)],
            accumulatedSeconds: nil, finishedAt: nil)]
        XCTAssertNoThrow(try BackupService.restore(file, into: context))
        let exercise = try context.fetch(FetchDescriptor<ExerciseLog>()).first
        XCTAssertEqual(exercise?.isCompleted, true)
        XCTAssertTrue(exercise?.sets.isEmpty ?? false, "Sin series, pero sin romperse")
        XCTAssertEqual(exercise?.note, "")
        XCTAssertEqual(exercise?.hasDiscomfort, false)
        let session = try context.fetch(FetchDescriptor<WorkoutSessionLog>()).first
        XCTAssertEqual(session?.accumulatedSeconds, 0)
        XCTAssertNil(session?.finishedAt)
    }

    private func oldSettings() -> BackupFile.Settings {
        BackupFile.Settings(kcalTarget: 2300, proteinTarget: 180, carbsTarget: 250, fatTarget: 65,
                            stepGoal: 8000, trackingStartDate: nil, onboardingCompleted: true,
                            creatineReminderEnabled: false, creatineHour: 9, creatineMinute: 0,
                            photoReminderEnabled: false, photoReminderHour: 20, defaultPlanID: nil,
                            stravaClientID: "", stravaBackendURL: "", heightCm: 180, age: 30,
                            sexRaw: "male", activityRaw: ActivityLevel.moderate.rawValue,
                            goalRaw: FitnessGoal.recomposition.rawValue, autoTargets: false,
                            stepGoalAdaptive: true, stepGoalAdjustedDayKey: "",
                            stepReminderEnabled: false, stepReminderFromMinutes: 0, stepReminderToMinutes: 0,
                            weightReminderEnabled: false, weightReminderFromMinutes: 0, weightReminderToMinutes: 0,
                            kcalMargin: nil)
    }
}
#endif
