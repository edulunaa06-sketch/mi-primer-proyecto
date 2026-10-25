import XCTest
@testable import Atlas

/// Pruebas del reparto de volumen por músculo y del motor de progresión.
final class VolumeAnalyticsTests: XCTestCase {
    private let monday = Date(timeIntervalSince1970: 1_700_000_000)
    private var tuesday: Date { monday.addingTimeInterval(86_400) }

    private func work(_ id: String, name: String = "", date: Date, sets: Int, volume: Double = 0) -> VolumeAnalytics.ExerciseWork {
        VolumeAnalytics.ExerciseWork(exerciseID: id, name: name, date: date, workSets: sets, volumeKg: volume)
    }

    func testPrimaryMuscleGetsFullSetsAndSecondariesHalf() {
        // Press de banca: pecho principal; deltoides anterior y tríceps como secundarios.
        let result = VolumeAnalytics.byMuscle([work("tue-bench-barbell", date: monday, sets: 4, volume: 3200)])
        let byGroup = Dictionary(result.muscles.map { ($0.group, $0) }, uniquingKeysWith: { a, _ in a })

        XCTAssertEqual(byGroup[.chest]!.directSets, 4)
        XCTAssertEqual(byGroup[.chest]!.totalSets, 4)
        XCTAssertEqual(byGroup[.chest]!.tonnageKg, 3200)
        // El trabajo indirecto cuenta media serie y NO cuenta como directo.
        XCTAssertEqual(byGroup[.triceps]!.directSets, 0)
        XCTAssertEqual(byGroup[.triceps]!.totalSets, 2)
        XCTAssertEqual(byGroup[.frontDelts]!.totalSets, 2)
        // El tonelaje solo se atribuye al músculo principal: repartirlo sería inventado.
        XCTAssertEqual(byGroup[.triceps]!.tonnageKg, 0)
    }

    func testUnknownExercisesGoToUnclassifiedInsteadOfBeingGuessed() {
        let result = VolumeAnalytics.byMuscle([
            work("custom-1234", name: "Invento del gimnasio", date: monday, sets: 3, volume: 300),
            work("tue-bench-barbell", date: monday, sets: 3, volume: 300),
        ])
        XCTAssertEqual(result.unclassified.count, 1)
        XCTAssertEqual(result.unclassified.first?.name, "Invento del gimnasio")
        XCTAssertEqual(result.muscles.first { $0.group == .chest }?.directSets, 3)
    }

    func testCustomExerciseIsClassifiedWhenItsNameMatchesTheCatalog() {
        // Un ejercicio creado por el usuario con el nombre de uno conocido sí se puede clasificar.
        let result = VolumeAnalytics.byMuscle([
            work("custom-abcd", name: "Press de banca con barra", date: monday, sets: 2, volume: 200),
        ])
        XCTAssertTrue(result.unclassified.isEmpty)
        XCTAssertEqual(result.muscles.first { $0.group == .chest }?.directSets, 2)
    }

    func testFrequencyCountsDistinctDaysNotSessions() {
        let result = VolumeAnalytics.byMuscle([
            work("tue-bench-barbell", date: monday, sets: 3),
            work("sat-machine-chest-press", date: monday, sets: 3),   // mismo día
            work("sat-smith-incline-press", date: tuesday, sets: 3),  // otro día
        ])
        let chest = result.muscles.first { $0.group == .chest }!
        XCTAssertEqual(chest.frequency, 2)
        XCTAssertEqual(chest.directSets, 9)
    }

    func testSetsWithoutWorkAreIgnored() {
        let result = VolumeAnalytics.byMuscle([work("tue-bench-barbell", date: monday, sets: 0, volume: 0)])
        XCTAssertTrue(result.muscles.isEmpty)
        XCTAssertTrue(result.unclassified.isEmpty)
    }

    func testTotalsAcrossEverything() {
        let items = [work("tue-bench-barbell", date: monday, sets: 3, volume: 2400),
                     work("thu-hack-squat", date: tuesday, sets: 4, volume: 5600)]
        XCTAssertEqual(VolumeAnalytics.totalTonnage(items), 8000)
        XCTAssertEqual(VolumeAnalytics.totalWorkSets(items), 7)
    }

    func testAdherenceComparesProgrammedWithPerformed() {
        let done = [work("tue-bench-barbell", date: monday, sets: 9)]
        let exact = VolumeAnalytics.adherence(programmedSets: 9, work: done)
        XCTAssertEqual(exact.fraction!, 1, accuracy: 0.0001)
        XCTAssertEqual(exact.difference, 0)
        XCTAssertEqual(exact.label, "Según lo programado")

        let short = VolumeAnalytics.adherence(programmedSets: 20, work: done)
        XCTAssertEqual(short.label, "Por debajo de lo programado")
        XCTAssertEqual(short.difference, -11)

        // Sin rutina programada no se puede calcular un porcentaje: se dice, no se inventa un 0 %.
        let none = VolumeAnalytics.adherence(programmedSets: 0, work: done)
        XCTAssertNil(none.fraction)
        XCTAssertEqual(none.label, "Sin rutina programada")
    }

    func testProgrammedByMuscleUsesTheRoutineNotTheLogs() {
        let programmed = VolumeAnalytics.programmedByMuscle([
            (id: "tue-bench-barbell", name: "Press de banca con barra", sets: 3),
            (id: "thu-hack-squat", name: "Hack squat", sets: 4),
        ])
        XCTAssertEqual(programmed[.chest], 3)
        XCTAssertEqual(programmed[.quads], 4)
    }

    func testWarningsForTooFewAndTooManySets() {
        let few = VolumeAnalytics.byMuscle([work("tue-bench-barbell", date: monday, sets: 3)]).muscles
        let belowWarnings = VolumeAnalytics.warnings(week: few)
        XCTAssertTrue(belowWarnings.contains { $0.kind == .belowReference && $0.group == .chest })

        let many = VolumeAnalytics.byMuscle([work("tue-bench-barbell", date: monday, sets: 30)]).muscles
        let aboveWarnings = VolumeAnalytics.warnings(week: many)
        XCTAssertTrue(aboveWarnings.contains { $0.kind == .aboveReference && $0.group == .chest })
    }

    func testWarningForASuddenJumpBetweenWeeks() {
        let previous = VolumeAnalytics.byMuscle([work("tue-bench-barbell", date: monday, sets: 4)]).muscles
        let current = VolumeAnalytics.byMuscle([work("tue-bench-barbell", date: monday, sets: 12)]).muscles
        let warnings = VolumeAnalytics.warnings(week: current, previous: previous)
        XCTAssertTrue(warnings.contains { $0.kind == .bigJump && $0.group == .chest })

        // Una subida pequeña no avisa de nada.
        let gentle = VolumeAnalytics.byMuscle([work("tue-bench-barbell", date: monday, sets: 6)]).muscles
        XCTAssertFalse(VolumeAnalytics.warnings(week: gentle, previous: previous).contains { $0.kind == .bigJump })
    }

    func testFirstWeekIsNotComparedWithAnything() {
        let current = VolumeAnalytics.byMuscle([work("tue-bench-barbell", date: monday, sets: 12)]).muscles
        XCTAssertFalse(VolumeAnalytics.warnings(week: current).contains { $0.kind == .bigJump })
    }

    func testVolumeReferenceVerdicts() {
        let chest = VolumeReference.reference(for: .chest)
        XCTAssertEqual(chest.verdict(sets: 0), .none)
        XCTAssertEqual(chest.verdict(sets: 3), .below)
        XCTAssertEqual(chest.verdict(sets: 14), .inRange)
        XCTAssertEqual(chest.verdict(sets: 40), .above)
        // Todos los grupos tienen referencia, aunque sea la genérica.
        for group in MuscleGroup.allCases {
            XCTAssertGreaterThan(VolumeReference.reference(for: group).high, 0, "\(group.label) sin referencia")
        }
    }
}

final class ProgressionEngineTests: XCTestCase {
    private let target = ProgressionEngine.RepTarget(min: 8, max: 12)

    private func summary(dayOffset: Int, weight: Double, reps: Int, rir: Int? = nil) -> ExerciseSessionSummary {
        let date = Date(timeIntervalSince1970: 1_700_000_000 + Double(dayOffset) * 604_800)
        return ExerciseSessionSummary(date: date, exerciseID: "bench-barbell",
                                      sets: [LoggedSet(order: 0, weightKg: weight, reps: reps, rir: rir)])!
    }

    func testNoHistoryAsksForData() {
        let advice = ProgressionEngine.advise(history: [], target: target)
        XCTAssertEqual(advice.action, .needMoreData)
        XCTAssertEqual(advice.sessionsConsidered, 0)
        XCTAssertFalse(advice.hasNumbers)
    }

    func testSessionWithoutWeightAndRepsCannotBeCompared() {
        let bodyweight = ExerciseSessionSummary(date: Date(), exerciseID: "pull-up",
                                                sets: [LoggedSet(order: 0, reps: 10)])!
        XCTAssertEqual(ProgressionEngine.advise(history: [bodyweight], target: target).action, .needMoreData)
    }

    func testClosingTheRepRangeMeansGoUp() {
        let advice = ProgressionEngine.advise(history: [summary(dayOffset: 0, weight: 80, reps: 12, rir: 2)],
                                              target: target, equipment: .barbell)
        XCTAssertEqual(advice.action, .increaseLoad)
        // 80 kg + 5 kg, redondeado a lo que se puede montar con una barra de 20.
        XCTAssertEqual(advice.suggestedWeightKg!, 85, accuracy: 0.0001)
        XCTAssertEqual(advice.suggestedReps, 8)
        XCTAssertTrue(advice.reason.contains("12"))
    }

    func testReachingTheTopOfTheRangeAtFailureHoldsInstead() {
        // 12 repeticiones pero al fallo (RIR 0): primero hay que poder hacerlas con margen.
        let advice = ProgressionEngine.advise(history: [summary(dayOffset: 0, weight: 80, reps: 12, rir: 0)],
                                              target: target, equipment: .barbell)
        XCTAssertEqual(advice.action, .hold)
        XCTAssertEqual(advice.suggestedWeightKg, 80)
    }

    func testPassingTheRangeGoesUpEvenAtFailure() {
        // 14 repeticiones es pasarse del rango: el peso es claramente bajo.
        let advice = ProgressionEngine.advise(history: [summary(dayOffset: 0, weight: 80, reps: 14, rir: 0)],
                                              target: target, equipment: .barbell)
        XCTAssertEqual(advice.action, .increaseLoad)
    }

    func testBelowTheRangeMeansGoDown() {
        let advice = ProgressionEngine.advise(history: [summary(dayOffset: 0, weight: 100, reps: 5)],
                                              target: target, equipment: .barbell)
        XCTAssertEqual(advice.action, .reduceLoad)
        XCTAssertEqual(advice.suggestedWeightKg!, 95, accuracy: 0.0001)
        XCTAssertEqual(advice.suggestedReps, 8)
    }

    func testPlentyOfRepsInReserveMeansAddRepsNotWeight() {
        let advice = ProgressionEngine.advise(history: [summary(dayOffset: 0, weight: 80, reps: 9, rir: 4)],
                                              target: target, equipment: .barbell)
        XCTAssertEqual(advice.action, .addReps)
        XCTAssertEqual(advice.suggestedWeightKg, 80)
        XCTAssertEqual(advice.suggestedReps, 11)
    }

    func testDiscomfortNeverIncreasesTheLoad() {
        let advice = ProgressionEngine.advise(history: [summary(dayOffset: 0, weight: 80, reps: 12, rir: 3)],
                                              target: target, equipment: .barbell, hasDiscomfort: true)
        XCTAssertEqual(advice.action, .hold)
        XCTAssertTrue(advice.reason.lowercased().contains("molestia"))
    }

    func testDeloadWeekOverridesEverything() {
        let advice = ProgressionEngine.advise(history: [summary(dayOffset: 0, weight: 80, reps: 12, rir: 3)],
                                              target: target, equipment: .barbell, isDeloadWeek: true)
        XCTAssertEqual(advice.action, .deload)
    }

    func testIncrementsDependOnTheEquipment() {
        XCTAssertEqual(ProgressionEngine.increment(for: .barbell, currentKg: 80), 5)
        XCTAssertEqual(ProgressionEngine.increment(for: .barbell, currentKg: 40), 2.5)
        XCTAssertEqual(ProgressionEngine.increment(for: .dumbbell, currentKg: 20), 2.5)
        XCTAssertEqual(ProgressionEngine.increment(for: .bodyweight, currentKg: 0), 0)
        // En máquina el paso lo marca la máquina: se propone un 5 % con un mínimo de 1 kg.
        XCTAssertEqual(ProgressionEngine.increment(for: .machine, currentKg: 100), 5)
        XCTAssertEqual(ProgressionEngine.increment(for: .machine, currentKg: 10), 1)
    }

    // MARK: Estancamiento

    func testTwoSessionsAreNotAStall() {
        let report = ProgressionEngine.stallReport(history: [summary(dayOffset: 0, weight: 80, reps: 10),
                                                             summary(dayOffset: 1, weight: 80, reps: 10)])
        XCTAssertFalse(report.isStalled)
    }

    func testThreeSessionsWithoutProgressIsAStall() {
        let history = [summary(dayOffset: 0, weight: 80, reps: 10),
                       summary(dayOffset: 1, weight: 80, reps: 10),
                       summary(dayOffset: 2, weight: 80, reps: 10),
                       summary(dayOffset: 3, weight: 80, reps: 10)]
        let report = ProgressionEngine.stallReport(history: history)
        XCTAssertTrue(report.isStalled)
        XCTAssertEqual(report.sessionsWithoutProgress, 3)
    }

    func testImprovingResetsTheStallCount() {
        let history = [summary(dayOffset: 0, weight: 80, reps: 10),
                       summary(dayOffset: 1, weight: 80, reps: 10),
                       summary(dayOffset: 2, weight: 80, reps: 10),
                       summary(dayOffset: 3, weight: 90, reps: 10)]   // mejora clara
        let report = ProgressionEngine.stallReport(history: history)
        XCTAssertFalse(report.isStalled)
        XCTAssertEqual(report.sessionsWithoutProgress, 0)
    }

    func testStalledHistoryMakesTheAdviceHoldAndSayWhy() {
        let history = [summary(dayOffset: 0, weight: 80, reps: 10, rir: 1),
                       summary(dayOffset: 1, weight: 80, reps: 10, rir: 1),
                       summary(dayOffset: 2, weight: 80, reps: 10, rir: 1),
                       summary(dayOffset: 3, weight: 80, reps: 10, rir: 1)]
        let advice = ProgressionEngine.advise(history: history, target: target, equipment: .barbell)
        XCTAssertEqual(advice.action, .hold)
        XCTAssertTrue(advice.reason.contains("sin mejorar"))
        XCTAssertEqual(advice.sessionsConsidered, 4)
    }

    // MARK: Descarga

    func testDeloadIsNotSuggestedWithoutSignals() {
        let suggestion = ProgressionEngine.deloadSuggestion(hardWeeksInARow: 2, stalledExercises: 0, musclesAboveReference: 0)
        XCTAssertFalse(suggestion.isRecommended)
    }

    func testDeloadSignals() {
        XCTAssertTrue(ProgressionEngine.deloadSuggestion(hardWeeksInARow: 6, stalledExercises: 0, musclesAboveReference: 0).isRecommended)
        XCTAssertTrue(ProgressionEngine.deloadSuggestion(hardWeeksInARow: 1, stalledExercises: 3, musclesAboveReference: 0).isRecommended)
        XCTAssertTrue(ProgressionEngine.deloadSuggestion(hardWeeksInARow: 1, stalledExercises: 0, musclesAboveReference: 3).isRecommended)
        // La fuerza bajando pesa más que cualquier otra señal.
        let falling = ProgressionEngine.deloadSuggestion(hardWeeksInARow: 1, stalledExercises: 0,
                                                         musclesAboveReference: 0, fallingTrends: 2)
        XCTAssertTrue(falling.isRecommended)
        XCTAssertTrue(falling.reason.contains("bajando"))
        XCTAssertFalse(falling.plan.isEmpty)
    }

    // MARK: Series planificadas

    func testPlannedSetsCarryTheSuggestedWeight() {
        let previous = [LoggedSet(order: 0, weightKg: 80, reps: 12, rir: 2, restSeconds: 120),
                        LoggedSet(order: 1, weightKg: 80, reps: 11, rir: 1, restSeconds: 120)]
        let advice = ProgressionEngine.advise(history: [summary(dayOffset: 0, weight: 80, reps: 12, rir: 2)],
                                              target: target, equipment: .barbell)
        let planned = ProgressionEngine.plannedSets(previous: previous, advice: advice, targetSets: 3, target: target)
        XCTAssertEqual(planned.count, 3)
        XCTAssertTrue(planned.allSatisfy { $0.weightKg == 85 })
        // Nada se marca como hecho ni trae repeticiones: eso lo pone el usuario al entrenar.
        XCTAssertTrue(planned.allSatisfy { !$0.isCompleted && $0.reps == nil })
        XCTAssertEqual(planned.first?.restSeconds, 120)
    }

    func testPlannedSetsForADeloadLowerTheWeight() {
        let previous = [LoggedSet(order: 0, weightKg: 100, reps: 10)]
        let advice = ProgressionEngine.advise(history: [summary(dayOffset: 0, weight: 100, reps: 10)],
                                              target: target, isDeloadWeek: true)
        let planned = ProgressionEngine.plannedSets(previous: previous, advice: advice, targetSets: 2, target: target)
        XCTAssertEqual(planned.first?.weightKg, 85)
    }

    func testPlannedSetsWithoutHistoryAreEmptyRows() {
        let advice = ProgressionEngine.advise(history: [], target: target)
        let planned = ProgressionEngine.plannedSets(previous: [], advice: advice, targetSets: 3, target: target)
        XCTAssertEqual(planned.count, 3)
        XCTAssertTrue(planned.allSatisfy { $0.weightKg == nil })
    }

    func testRepTargetNeverInverts() {
        let weird = ProgressionEngine.RepTarget(min: 12, max: 5)
        XCTAssertEqual(weird.min, 12)
        XCTAssertEqual(weird.max, 12)
        let zero = ProgressionEngine.RepTarget(min: 0, max: 0)
        XCTAssertEqual(zero.min, 1)
    }
}
