import XCTest
@testable import Atlas

/// Pruebas del núcleo de fuerza: series, 1RM estimado, resúmenes, tendencia,
/// récords y calculadora de discos.
final class OneRepMaxTests: XCTestCase {
    func testOneRepAtOneRepIsTheWeightItself() {
        XCTAssertEqual(OneRepMax.epley(weightKg: 100, reps: 1), 100)
        XCTAssertEqual(OneRepMax.brzycki(weightKg: 100, reps: 1), 100)
        XCTAssertEqual(OneRepMax.lombardi(weightKg: 100, reps: 1), 100)
        XCTAssertEqual(OneRepMax.estimate(weightKg: 100, reps: 1), 100)
    }

    func testEpleyAndBrzyckiKnownValues() {
        // Epley: 100 · (1 + 5/30) = 116,67
        XCTAssertEqual(OneRepMax.epley(weightKg: 100, reps: 5)!, 116.667, accuracy: 0.01)
        // Brzycki: 100 · 36/(37 − 5) = 112,5
        XCTAssertEqual(OneRepMax.brzycki(weightKg: 100, reps: 5)!, 112.5, accuracy: 0.001)
        // La estimación de referencia es la media de las dos.
        XCTAssertEqual(OneRepMax.estimate(weightKg: 100, reps: 5)!, 114.583, accuracy: 0.01)
    }

    func testInvalidInputsReturnNil() {
        XCTAssertNil(OneRepMax.epley(weightKg: 0, reps: 5))
        XCTAssertNil(OneRepMax.epley(weightKg: -10, reps: 5))
        XCTAssertNil(OneRepMax.epley(weightKg: 100, reps: 0))
        XCTAssertNil(OneRepMax.estimate(weightKg: 100, reps: 0))
        // Brzycki se rompe en 37 repeticiones: ahí no se usa.
        XCTAssertNil(OneRepMax.brzycki(weightKg: 100, reps: 37))
        XCTAssertNotNil(OneRepMax.brzycki(weightKg: 100, reps: 36))
    }

    func testEstimateFallsBackToEpleyWhenBrzyckiDoesNotApply() {
        // Con 40 repeticiones Brzycki no vale, así que la estimación es Epley sola.
        let estimate = OneRepMax.estimate(weightKg: 50, reps: 40)
        XCTAssertEqual(estimate!, OneRepMax.epley(weightKg: 50, reps: 40)!, accuracy: 0.0001)
    }

    func testRIRCountsAsExtraReps() {
        // 80 kg × 8 dejando 2 en reserva se estima como 80 × 10.
        let withRIR = OneRepMax.estimate(weightKg: 80, reps: 8, rir: 2)!
        let asTen = OneRepMax.estimate(weightKg: 80, reps: 10)!
        XCTAssertEqual(withRIR, asTen, accuracy: 0.0001)
        // Sin RIR o con RIR 0, no se añade nada.
        XCTAssertEqual(OneRepMax.estimate(weightKg: 80, reps: 8, rir: nil)!,
                       OneRepMax.estimate(weightKg: 80, reps: 8)!, accuracy: 0.0001)
        XCTAssertEqual(OneRepMax.estimate(weightKg: 80, reps: 8, rir: 0)!,
                       OneRepMax.estimate(weightKg: 80, reps: 8)!, accuracy: 0.0001)
    }

    func testNegativeRIRIsIgnoredInsteadOfLoweringTheEstimate() {
        XCTAssertEqual(OneRepMax.estimate(weightKg: 80, reps: 8, rir: -3)!,
                       OneRepMax.estimate(weightKg: 80, reps: 8)!, accuracy: 0.0001)
    }

    func testConfidenceDropsWithReps() {
        XCTAssertEqual(OneRepMax.confidence(reps: 3), .high)
        XCTAssertEqual(OneRepMax.confidence(reps: 6), .high)
        XCTAssertEqual(OneRepMax.confidence(reps: 7), .medium)
        XCTAssertEqual(OneRepMax.confidence(reps: 12), .medium)
        XCTAssertEqual(OneRepMax.confidence(reps: 13), .low)
    }

    func testPercentOfMaxAndWorkingWeightAreConsistent() {
        // 10 repeticiones ≈ 75 % del máximo.
        XCTAssertEqual(OneRepMax.percentOfMax(reps: 10)!, 0.75, accuracy: 0.0001)
        XCTAssertEqual(OneRepMax.workingWeight(oneRepMax: 100, reps: 10)!, 75, accuracy: 0.0001)
        XCTAssertEqual(OneRepMax.percentOfMax(reps: 1)!, 1, accuracy: 0.0001)
        XCTAssertNil(OneRepMax.workingWeight(oneRepMax: 0, reps: 5))
    }
}

final class LoggedSetTests: XCTestCase {
    func testVolumeNeedsBothWeightAndReps() {
        XCTAssertEqual(LoggedSet(order: 0, weightKg: 80, reps: 10).volumeKg, 800)
        XCTAssertEqual(LoggedSet(order: 0, weightKg: 80, reps: nil).volumeKg, 0)
        XCTAssertEqual(LoggedSet(order: 0, weightKg: nil, reps: 10).volumeKg, 0)
        XCTAssertEqual(LoggedSet(order: 0, weightKg: 0, reps: 10).volumeKg, 0)
    }

    func testWarmupSetsDoNotCountAsVolume() {
        XCTAssertEqual(LoggedSet(order: 0, kind: .warmup, weightKg: 40, reps: 10).volumeKg, 0)
        XCTAssertFalse(SetKind.warmup.countsAsWork)
        // Drop y back-off sí son trabajo real.
        XCTAssertEqual(LoggedSet(order: 0, kind: .dropset, weightKg: 40, reps: 10).volumeKg, 400)
        XCTAssertEqual(LoggedSet(order: 0, kind: .backoff, weightKg: 40, reps: 10).volumeKg, 400)
    }

    func testEffortRPEDerivedFromRIR() {
        XCTAssertEqual(LoggedSet(order: 0, rir: 0).effortRPE, 10)
        XCTAssertEqual(LoggedSet(order: 0, rir: 3).effortRPE, 7)
        // Un RPE escrito a mano manda sobre el derivado.
        XCTAssertEqual(LoggedSet(order: 0, rir: 3, rpe: 9).effortRPE, 9)
        XCTAssertNil(LoggedSet(order: 0).effortRPE)
        // Nunca baja de 1.
        XCTAssertEqual(LoggedSet(order: 0, rir: 20).effortRPE, 1)
    }

    func testRepsToFailure() {
        XCTAssertEqual(LoggedSet(order: 0, reps: 8, rir: 2).repsToFailure, 10)
        XCTAssertEqual(LoggedSet(order: 0, reps: 8).repsToFailure, 8)
        XCTAssertNil(LoggedSet(order: 0).repsToFailure)
    }
}

final class ExerciseSessionSummaryTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    func testNoSetsWithRepsMeansNoSummary() {
        XCTAssertNil(ExerciseSessionSummary(date: day, exerciseID: "bench-barbell", sets: []))
        // Solo pesos apuntados, sin repeticiones: no es una sesión.
        let onlyWeights = [LoggedSet(order: 0, weightKg: 80), LoggedSet(order: 1, weightKg: 80)]
        XCTAssertNil(ExerciseSessionSummary(date: day, exerciseID: "bench-barbell", sets: onlyWeights))
        // Solo calentamientos: tampoco.
        let onlyWarmups = [LoggedSet(order: 0, kind: .warmup, weightKg: 40, reps: 10)]
        XCTAssertNil(ExerciseSessionSummary(date: day, exerciseID: "bench-barbell", sets: onlyWarmups))
    }

    func testTopSetIsTheHeaviestAndThenTheOneWithMoreReps() {
        let sets = [
            LoggedSet(order: 0, kind: .warmup, weightKg: 100, reps: 5),   // no cuenta aunque pese más
            LoggedSet(order: 1, weightKg: 80, reps: 8, rir: 2),
            LoggedSet(order: 2, weightKg: 80, reps: 10, rir: 1),           // mismo peso, más reps
            LoggedSet(order: 3, weightKg: 75, reps: 12),
        ]
        let summary = ExerciseSessionSummary(date: day, exerciseID: "bench-barbell", sets: sets)!
        XCTAssertEqual(summary.topWeightKg, 80)
        XCTAssertEqual(summary.repsAtTopWeight, 10)
        XCTAssertEqual(summary.rirAtTopWeight, 1)
    }

    func testVolumeAndRepsOnlyCountWorkSets() {
        let sets = [
            LoggedSet(order: 0, kind: .warmup, weightKg: 40, reps: 10),
            LoggedSet(order: 1, weightKg: 80, reps: 10, rir: 2),
            LoggedSet(order: 2, weightKg: 80, reps: 8, rir: 0),
            LoggedSet(order: 3, reps: 12),                                  // peso corporal: suma reps, no kilos
        ]
        let summary = ExerciseSessionSummary(date: day, exerciseID: "x", sets: sets)!
        XCTAssertEqual(summary.volumeKg, 800 + 640)
        XCTAssertEqual(summary.totalReps, 10 + 8 + 12)
        XCTAssertEqual(summary.workSets, 3)
        XCTAssertEqual(summary.averageRIR!, 1, accuracy: 0.0001)
    }

    func testAverageRIRIsNilWhenNobodyWroteIt() {
        let sets = [LoggedSet(order: 0, weightKg: 80, reps: 10)]
        XCTAssertNil(ExerciseSessionSummary(date: day, exerciseID: "x", sets: sets)!.averageRIR)
    }

    func testEstimatedOneRepMaxUsesTopSetWithItsRIR() {
        let sets = [LoggedSet(order: 0, weightKg: 100, reps: 5, rir: 1)]
        let summary = ExerciseSessionSummary(date: day, exerciseID: "x", sets: sets)!
        XCTAssertEqual(summary.estimatedOneRepMax!, OneRepMax.estimate(weightKg: 100, reps: 6)!, accuracy: 0.0001)
        // 5 + 1 = 6 repeticiones efectivas: fiabilidad todavía alta.
        XCTAssertEqual(summary.oneRepMaxConfidence, .high)
        XCTAssertEqual(summary.topSetText, "100 kg × 5 (RIR 1)")
    }

    func testBodyweightOnlySummaryHasNoOneRepMax() {
        let sets = [LoggedSet(order: 0, reps: 15)]
        let summary = ExerciseSessionSummary(date: day, exerciseID: "pull-up", sets: sets)!
        XCTAssertNil(summary.estimatedOneRepMax)
        XCTAssertNil(summary.topSetText)
        XCTAssertEqual(summary.totalReps, 15)
    }
}

final class StrengthTrendTests: XCTestCase {
    private func summary(dayOffset: Int, weight: Double, reps: Int) -> ExerciseSessionSummary {
        let date = Date(timeIntervalSince1970: 1_700_000_000 + Double(dayOffset) * 86_400)
        return ExerciseSessionSummary(date: date, exerciseID: "bench-barbell",
                                      sets: [LoggedSet(order: 0, weightKg: weight, reps: reps)])!
    }

    func testTwoSessionsAreNotEnoughToTalkAboutTrend() {
        let trend = StrengthTrend(summaries: [summary(dayOffset: 0, weight: 80, reps: 8),
                                              summary(dayOffset: 7, weight: 85, reps: 8)])
        XCTAssertEqual(trend.verdict, .notEnoughData)
        XCTAssertNil(trend.changePercent)
    }

    func testRisingTrend() {
        let trend = StrengthTrend(summaries: [summary(dayOffset: 0, weight: 80, reps: 8),
                                              summary(dayOffset: 7, weight: 85, reps: 8),
                                              summary(dayOffset: 14, weight: 90, reps: 8)])
        XCTAssertEqual(trend.verdict, .rising)
        XCTAssertEqual(trend.changePercent!, 12.5, accuracy: 0.001)
        XCTAssertGreaterThan(trend.kgPerWeek!, 0)
        XCTAssertEqual(trend.points.count, 3)
    }

    func testFallingTrend() {
        let trend = StrengthTrend(summaries: [summary(dayOffset: 0, weight: 90, reps: 8),
                                              summary(dayOffset: 7, weight: 85, reps: 8),
                                              summary(dayOffset: 14, weight: 80, reps: 8)])
        XCTAssertEqual(trend.verdict, .falling)
        XCTAssertLessThan(trend.kgPerWeek!, 0)
    }

    func testTinyChangesCountAsFlat() {
        // Menos del 2 % de cambio es ruido, no tendencia.
        let trend = StrengthTrend(summaries: [summary(dayOffset: 0, weight: 100, reps: 8),
                                              summary(dayOffset: 7, weight: 100, reps: 8),
                                              summary(dayOffset: 14, weight: 101, reps: 8)])
        XCTAssertEqual(trend.verdict, .flat)
    }

    func testPointsAreSortedOldestFirstEvenIfInputIsNot() {
        let trend = StrengthTrend(summaries: [summary(dayOffset: 14, weight: 90, reps: 8),
                                              summary(dayOffset: 0, weight: 80, reps: 8),
                                              summary(dayOffset: 7, weight: 85, reps: 8)])
        XCTAssertEqual(trend.points.map(\.date), trend.points.map(\.date).sorted())
        XCTAssertEqual(trend.verdict, .rising)
    }

    func testSlopeOfAFlatSeriesIsZero() {
        let points = [StrengthTrend.Point(date: Date(timeIntervalSince1970: 0), oneRepMax: 100),
                      StrengthTrend.Point(date: Date(timeIntervalSince1970: 604_800), oneRepMax: 100)]
        XCTAssertEqual(StrengthTrend.slopePerWeek(points)!, 0, accuracy: 0.0001)
    }
}

final class PersonalRecordsTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    private var summary: ExerciseSessionSummary {
        ExerciseSessionSummary(date: day, exerciseID: "bench-barbell",
                               sets: [LoggedSet(order: 0, weightKg: 100, reps: 5)])!
    }

    func testFirstEverValuesAreMarkedAsSuchAndNotAsBrokenRecords() {
        let candidates = PersonalRecords.candidates(from: summary, exerciseName: "Press de banca", previousBest: [:])
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.allSatisfy(\.isFirstEver))
        XCTAssertTrue(candidates.allSatisfy { $0.improvement == nil })
    }

    func testBeatingAPreviousBestIsARecordWithItsImprovement() {
        let candidates = PersonalRecords.candidates(from: summary, exerciseName: "Press de banca",
                                                    previousBest: [.topWeight: 95])
        let weightRecord = candidates.first { $0.kind == .topWeight }
        XCTAssertNotNil(weightRecord)
        XCTAssertEqual(weightRecord!.improvement!, 5, accuracy: 0.0001)
        XCTAssertFalse(weightRecord!.isFirstEver)
    }

    func testEqualOrWorseValuesAreNotRecords() {
        let candidates = PersonalRecords.candidates(from: summary, exerciseName: "Press de banca",
                                                    previousBest: [.topWeight: 100, .estimatedOneRepMax: 999,
                                                                   .sessionVolume: 999])
        XCTAssertTrue(candidates.isEmpty)
    }

    func testRepsRecordOnlyCountsAtTheSameWeight() {
        XCTAssertTrue(PersonalRecords.repsRecord(weightKg: 80, reps: 10, previousRepsAtSameWeight: 8))
        XCTAssertFalse(PersonalRecords.repsRecord(weightKg: 80, reps: 8, previousRepsAtSameWeight: 8))
        // Sin referencia previa con ese peso no hay récord que batir.
        XCTAssertFalse(PersonalRecords.repsRecord(weightKg: 80, reps: 10, previousRepsAtSameWeight: nil))
        XCTAssertFalse(PersonalRecords.repsRecord(weightKg: 0, reps: 10, previousRepsAtSameWeight: 5))
    }
}

final class PlateMathTests: XCTestCase {
    func testExactLoads() {
        let hundred = PlateMath.plates(forTotal: 100)!
        XCTAssertEqual(hundred.perSide, [25, 15])
        XCTAssertEqual(hundred.achievedKg, 100)
        XCTAssertTrue(hundred.isExact)

        let fine = PlateMath.plates(forTotal: 102.5)!
        XCTAssertEqual(fine.perSide, [25, 15, 1.25])
        XCTAssertTrue(fine.isExact)
    }

    func testBarAloneAndBelowTheBar() {
        let bar = PlateMath.plates(forTotal: 20)!
        XCTAssertTrue(bar.perSide.isEmpty)
        XCTAssertEqual(bar.achievedKg, 20)
        // Por debajo de la barra no hay reparto posible.
        XCTAssertNil(PlateMath.plates(forTotal: 15))
    }

    func testImpossibleWeightSaysWhatItReallyAchieves() {
        // 100,3 kg no se puede montar con discos normales: se queda en 100 y lo dice.
        let result = PlateMath.plates(forTotal: 100.3)!
        XCTAssertFalse(result.isExact)
        XCTAssertEqual(result.achievedKg, 100)
        XCTAssertEqual(result.differenceKg, -0.3, accuracy: 0.0001)
    }

    func testCustomBarAndPlates() {
        // Barra de 10 kg y solo discos de 5: 40 kg = 15 por lado → 5+5+5.
        let result = PlateMath.plates(forTotal: 40, barKg: 10, available: [5])!
        XCTAssertEqual(result.perSide, [5, 5, 5])
        XCTAssertTrue(result.isExact)
    }

    func testPerSideTextListsPlatesFromBigToSmall() {
        XCTAssertEqual(PlateMath.plates(forTotal: 102.5)!.perSideText, "25 + 15 + 1,25")
    }

    func testNextAchievableAlwaysGoesUp() {
        XCTAssertEqual(PlateMath.nextAchievable(above: 100)!, 101)
        XCTAssertGreaterThan(PlateMath.nextAchievable(above: 100.5)!, 100.5)
        XCTAssertGreaterThan(PlateMath.nextAchievable(above: 20)!, 20)
    }

    func testRoundedNeverGoesOverTheAskedWeight() {
        XCTAssertEqual(PlateMath.rounded(101.3), 101)
        XCTAssertEqual(PlateMath.rounded(100), 100)
        // Por debajo de la barra se devuelve tal cual (no hay discos que quitar).
        XCTAssertEqual(PlateMath.rounded(15), 15)
    }
}
