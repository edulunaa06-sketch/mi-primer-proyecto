import XCTest
@testable import Atlas

/// Pruebas de recuperación y suplementación. Se comprueba sobre todo lo que la app NO debe hacer:
/// dar veredictos sin datos, convertir una puntuación en diagnóstico o vender como probado
/// algo que no lo está.
final class RecoveryTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_700_000_000)
    private func day(_ offset: Int) -> Date { today.addingTimeInterval(Double(offset) * 86_400) }

    func testOneAnswerIsNotEnoughForAVerdict() {
        let entry = RecoveryEntry(date: today, sleepHours: 8)
        let readiness = RecoveryAnalysis.readiness(entry)
        XCTAssertNil(readiness.score)
        XCTAssertEqual(readiness.verdict, .unknown)
        XCTAssertEqual(readiness.inputsUsed, 1)
    }

    func testEmptyEntryGivesNoScore() {
        let readiness = RecoveryAnalysis.readiness(RecoveryEntry(date: today))
        XCTAssertNil(readiness.score)
        XCTAssertEqual(readiness.inputsUsed, 0)
        XCTAssertTrue(RecoveryEntry(date: today).isEmpty)
    }

    func testGoodDayScoresHigh() {
        let entry = RecoveryEntry(date: today, sleepHours: 8.5, sleepQuality: 5, energy: 5,
                                  fatigue: 1, stress: 1, soreness: 1)
        let readiness = RecoveryAnalysis.readiness(entry)
        XCTAssertEqual(readiness.score, 100)
        XCTAssertEqual(readiness.verdict, .good)
        XCTAssertEqual(readiness.inputsUsed, 6)
        // Nunca se presenta como diagnóstico.
        XCTAssertTrue(readiness.message.contains("no es un diagnóstico"))
    }

    func testBadDayScoresLowAndSuggestsTakingItEasy() {
        let entry = RecoveryEntry(date: today, sleepHours: 4, sleepQuality: 1, energy: 1,
                                  fatigue: 5, stress: 5, soreness: 5)
        let readiness = RecoveryAnalysis.readiness(entry)
        XCTAssertEqual(readiness.score, 0)
        XCTAssertEqual(readiness.verdict, .low)
        XCTAssertTrue(readiness.message.contains("reserva"))
    }

    func testOnlyAnsweredQuestionsCount() {
        // Dos respuestas buenas y nada más: el resto no se rellena con medias inventadas.
        let entry = RecoveryEntry(date: today, sleepQuality: 5, energy: 5)
        let readiness = RecoveryAnalysis.readiness(entry)
        XCTAssertEqual(readiness.inputsUsed, 2)
        XCTAssertEqual(readiness.score, 100)
    }

    func testScalesAreNormalizedInTheRightDirection() {
        XCTAssertEqual(RecoveryAnalysis.normalizedBetter(1), 0)
        XCTAssertEqual(RecoveryAnalysis.normalizedBetter(5), 1)
        XCTAssertEqual(RecoveryAnalysis.normalizedWorse(1), 1)
        XCTAssertEqual(RecoveryAnalysis.normalizedWorse(5), 0)
        // Valores fuera de la escala se ignoran en lugar de falsear la cuenta.
        XCTAssertNil(RecoveryAnalysis.normalizedBetter(0))
        XCTAssertNil(RecoveryAnalysis.normalizedBetter(6))
        XCTAssertNil(RecoveryAnalysis.normalizedWorse(nil))
    }

    func testSleepIsClampedAtBothEnds() {
        XCTAssertEqual(RecoveryAnalysis.normalizedSleep(2), 0)
        XCTAssertEqual(RecoveryAnalysis.normalizedSleep(4), 0)
        XCTAssertEqual(RecoveryAnalysis.normalizedSleep(6), 0.5)
        XCTAssertEqual(RecoveryAnalysis.normalizedSleep(8), 1)
        XCTAssertEqual(RecoveryAnalysis.normalizedSleep(12), 1)
        XCTAssertNil(RecoveryAnalysis.normalizedSleep(0))
    }

    func testDiscomfortAlwaysSendsYouToAProfessionalAndNeverDiagnoses() {
        let entry = RecoveryEntry(date: today, sleepQuality: 5, energy: 5, hasDiscomfort: true)
        let readiness = RecoveryAnalysis.readiness(entry)
        let warning = readiness.warnings.first { $0.contains("molestia") }
        XCTAssertNotNil(warning)
        XCTAssertTrue(warning!.contains("profesional sanitario"))
        XCTAssertTrue(warning!.contains("no diagnostica"))
    }

    func testThreeShortNightsInARowWarn() {
        let recent = [RecoveryEntry(date: day(-1), sleepHours: 5),
                      RecoveryEntry(date: day(-2), sleepHours: 5.5)]
        let entry = RecoveryEntry(date: today, sleepHours: 5, energy: 2)
        let readiness = RecoveryAnalysis.readiness(entry, recent: recent)
        XCTAssertTrue(readiness.warnings.contains { $0.contains("durmiendo menos") })
    }

    func testOneShortNightDoesNotWarn() {
        let recent = [RecoveryEntry(date: day(-1), sleepHours: 8),
                      RecoveryEntry(date: day(-2), sleepHours: 8)]
        let entry = RecoveryEntry(date: today, sleepHours: 5, energy: 3)
        XCTAssertFalse(RecoveryAnalysis.readiness(entry, recent: recent).warnings.contains { $0.contains("durmiendo menos") })
    }

    func testStressAndFatigueTogetherWarn() {
        let entry = RecoveryEntry(date: today, fatigue: 4, stress: 4)
        XCTAssertTrue(RecoveryAnalysis.readiness(entry).warnings.contains { $0.contains("estrés y mucha fatiga") })
    }

    func testAveragesIgnoreMissingAnswers() {
        let entries = [RecoveryEntry(date: day(0), sleepHours: 8, fatigue: 2),
                       RecoveryEntry(date: day(-1), sleepHours: 6),
                       RecoveryEntry(date: day(-2), hasDiscomfort: true)]
        let averages = RecoveryAnalysis.averages(entries)
        XCTAssertEqual(averages.sleepHours!, 7, accuracy: 0.0001)
        XCTAssertEqual(averages.fatigue!, 2, accuracy: 0.0001)
        XCTAssertNil(averages.energy)
        XCTAssertEqual(averages.daysLogged, 3)
        XCTAssertEqual(averages.daysWithDiscomfort, 1)
    }

    func testTipsAreAllFilledIn() {
        XCTAssertFalse(RecoveryTips.all.isEmpty)
        for tip in RecoveryTips.all {
            XCTAssertFalse(tip.title.isEmpty)
            XCTAssertFalse(tip.detail.isEmpty)
            XCTAssertFalse(tip.symbol.isEmpty)
        }
    }
}

final class RecoveryPerformanceTests: XCTestCase {
    func testPerfectCorrelation() {
        XCTAssertEqual(RecoveryPerformance.correlation([1, 2, 3], [2, 4, 6])!, 1, accuracy: 0.0001)
        XCTAssertEqual(RecoveryPerformance.correlation([1, 2, 3], [6, 4, 2])!, -1, accuracy: 0.0001)
    }

    func testCorrelationNeedsVariationAndTwoPoints() {
        // Una serie constante no tiene correlación definida.
        XCTAssertNil(RecoveryPerformance.correlation([5, 5, 5], [1, 2, 3]))
        XCTAssertNil(RecoveryPerformance.correlation([1], [1]))
        XCTAssertNil(RecoveryPerformance.correlation([1, 2], [1, 2, 3]))
    }

    func testFewWeeksMeansNoClaimAtAll() {
        let relation = RecoveryPerformance.sleepVersusTonnage(sleep: [7, 8, 6], tonnage: [1000, 1200, 900])
        XCTAssertFalse(relation.hasEnoughData)
        XCTAssertNil(relation.coefficient)
        XCTAssertTrue(relation.summary.contains("Hacen falta"))
    }

    func testWithEnoughWeeksItReportsTheRelationAndWarnsAboutCausality() {
        let sleep = [7.0, 7.5, 8.0, 6.5, 7.0, 8.5]
        let tonnage = [10_000.0, 11_000, 12_500, 9_000, 10_500, 13_000]
        let relation = RecoveryPerformance.sleepVersusTonnage(sleep: sleep, tonnage: tonnage)
        XCTAssertTrue(relation.hasEnoughData)
        XCTAssertGreaterThan(relation.coefficient!, 0.5)
        XCTAssertEqual(relation.points, 6)
        XCTAssertTrue(relation.summary.contains("no quiere decir que una cause la otra"))
    }
}

final class SupplementTests: XCTestCase {
    func testCatalogIsCompleteAndHonest() {
        XCTAssertFalse(SupplementCatalog.all.isEmpty)
        var ids = Set<String>()
        for info in SupplementCatalog.all {
            XCTAssertTrue(ids.insert(info.id).inserted, "Suplemento repetido: \(info.id)")
            XCTAssertFalse(info.name.isEmpty)
            XCTAssertFalse(info.ingredient.isEmpty)
            XCTAssertFalse(info.benefits.isEmpty, "\(info.id) sin nada que decir a favor")
            // Lo importante: todos tienen límites escritos, también los de evidencia sólida.
            XCTAssertFalse(info.limits.isEmpty, "\(info.id) sin límites declarados")
        }
    }

    func testStrongEvidenceIsOnlyForTheOnesThatHaveIt() {
        let strong = SupplementCatalog.all.filter { $0.evidence == .strong }.map(\.id)
        XCTAssertTrue(strong.contains("creatine"))
        XCTAssertTrue(strong.contains("caffeine"))
        // Y lo que no tiene base, marcado como tal.
        XCTAssertEqual(SupplementCatalog.info(id: "bcaa")?.evidence, .insufficient)
        XCTAssertEqual(SupplementCatalog.info(id: "glutamine")?.evidence, .insufficient)
    }

    func testLookupByIdAndIngredient() {
        XCTAssertEqual(SupplementCatalog.info(id: "creatine")?.name, "Creatina monohidrato")
        XCTAssertEqual(SupplementCatalog.info(ingredient: "creatina")?.id, "creatine")
        XCTAssertEqual(SupplementCatalog.info(ingredient: "CREATINA")?.id, "creatine")
        XCTAssertNil(SupplementCatalog.info(id: "no-existe"))
    }

    func testEvidenceLevelsAreOrdered() {
        XCTAssertLessThan(EvidenceLevel.strong, EvidenceLevel.moderate)
        XCTAssertLessThan(EvidenceLevel.limited, EvidenceLevel.insufficient)
    }

    func testDailyAmountAndUnitConversion() {
        let creatine = SupplementPlanItem(catalogID: "creatine", name: "Creatina", ingredient: "creatina",
                                          amountPerDose: 5, unit: .gram, dosesPerDay: 1)
        XCTAssertEqual(creatine.dailyAmount, 5)
        XCTAssertEqual(creatine.dailyMilligrams, 5000)
        // Las cápsulas no se pueden convertir a miligramos sin saber qué llevan dentro.
        let capsules = SupplementPlanItem(name: "Algo", ingredient: "algo", amountPerDose: 2, unit: .capsule)
        XCTAssertNil(capsules.dailyMilligrams)
    }

    func testMonthlyCostNeedsPriceAndDuration() {
        let withPrice = SupplementPlanItem(name: "Creatina", ingredient: "creatina", amountPerDose: 5,
                                           unit: .gram, packagePrice: 20, packageDays: 60)
        XCTAssertEqual(withPrice.monthlyCost!, 10, accuracy: 0.0001)
        let withoutPrice = SupplementPlanItem(name: "Creatina", ingredient: "creatina", amountPerDose: 5, unit: .gram)
        XCTAssertNil(withoutPrice.monthlyCost)
    }

    func testTotalCostSaysHowManyItemsHaveNoPrice() {
        let items = [SupplementPlanItem(name: "A", ingredient: "a", amountPerDose: 1, unit: .gram,
                                        packagePrice: 30, packageDays: 30),
                     SupplementPlanItem(name: "B", ingredient: "b", amountPerDose: 1, unit: .gram)]
        let cost = SupplementChecks.monthlyCost(items)
        XCTAssertEqual(cost.total, 30, accuracy: 0.0001)
        XCTAssertEqual(cost.itemsWithoutPrice, 1)
    }

    func testDuplicateIngredientIsDetected() {
        let items = [SupplementPlanItem(name: "Preentreno", ingredient: "cafeína", amountPerDose: 200, unit: .milligram),
                     SupplementPlanItem(name: "Pastillas de cafeína", ingredient: "Cafeína", amountPerDose: 100, unit: .milligram)]
        XCTAssertEqual(SupplementChecks.duplicates(items).count, 1)
        XCTAssertTrue(SupplementChecks.warnings(items).contains { $0.kind == .duplicate })
    }

    func testTooMuchCaffeineWarns() {
        let items = [SupplementPlanItem(catalogID: "caffeine", name: "Preentreno", ingredient: "cafeína",
                                        amountPerDose: 300, unit: .milligram, dosesPerDay: 2)]
        let warnings = SupplementChecks.warnings(items)
        XCTAssertTrue(warnings.contains { $0.kind == .tooMuch })
    }

    func testNormalCaffeineDoseDoesNotWarn() {
        let items = [SupplementPlanItem(catalogID: "caffeine", name: "Preentreno", ingredient: "cafeína",
                                        amountPerDose: 200, unit: .milligram, hours: [9])]
        let warnings = SupplementChecks.warnings(items)
        XCTAssertFalse(warnings.contains { $0.kind == .tooMuch })
        XCTAssertFalse(warnings.contains { $0.kind == .timing })
    }

    func testAfternoonCaffeineWarnsAboutSleep() {
        let items = [SupplementPlanItem(catalogID: "caffeine", name: "Preentreno", ingredient: "cafeína",
                                        amountPerDose: 200, unit: .milligram, hours: [19])]
        XCTAssertTrue(SupplementChecks.warnings(items).contains { $0.kind == .timing })
    }

    func testThingsWorthAskingAboutAreFlagged() {
        let items = [SupplementPlanItem(catalogID: "ashwagandha", name: "Ashwagandha", ingredient: "ashwagandha",
                                        amountPerDose: 600, unit: .milligram)]
        let warnings = SupplementChecks.warnings(items)
        let consult = warnings.first { $0.kind == .consult }
        XCTAssertNotNil(consult)
        XCTAssertTrue(consult!.message.contains("dietista-nutricionista"))
    }

    func testSupplementsWithoutEvidenceAreCalledOut() {
        let items = [SupplementPlanItem(catalogID: "bcaa", name: "BCAA", ingredient: "bcaa",
                                        amountPerDose: 10, unit: .gram)]
        XCTAssertTrue(SupplementChecks.warnings(items).contains { $0.kind == .noEvidence })
    }

    func testCreatineRaisesNoWarnings() {
        let items = [SupplementPlanItem(catalogID: "creatine", name: "Creatina", ingredient: "creatina",
                                        amountPerDose: 5, unit: .gram)]
        XCTAssertTrue(SupplementChecks.warnings(items).isEmpty)
    }
}
