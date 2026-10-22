import XCTest
@testable import NowOrNever

final class MealPlannerTests: XCTestCase {
    private let daily = NutritionValues(kcal: 2400, protein: 180, carbs: 260, fat: 70)
    private let oats = NutritionValues(kcal: 389, protein: 16.9, carbs: 66.3, fat: 6.9)
    private let chicken = NutritionValues(kcal: 120, protein: 22.5, carbs: 0, fat: 2.6)
    private let rice = NutritionValues(kcal: 360, protein: 6.5, carbs: 79.3, fat: 0.6)
    private let oil = NutritionValues(kcal: 884, protein: 0, carbs: 0, fat: 100)

    func testFirstMealTargetUsesShare() {
        let t = MealPlanner.target(for: .breakfast, daily: daily, fixed: [:])
        XCTAssertEqual(t.kcal, 600, accuracy: 0.001)      // 25 %
        XCTAssertEqual(t.protein, 45, accuracy: 0.001)
    }

    func testNextMealTargetDependsOnPreviousChoice() {
        let bigBreakfast = NutritionValues(kcal: 900, protein: 40, carbs: 120, fat: 20)
        let t = MealPlanner.target(for: .lunch, daily: daily, fixed: [.breakfast: bigBreakfast])
        // Quedan 1500 kcal para comida+merienda+cena (35/75 para la comida).
        XCTAssertEqual(t.kcal, 1500 * 0.35 / 0.75, accuracy: 0.001)
        XCTAssertEqual(t.protein, 140 * 0.35 / 0.75, accuracy: 0.001)
    }

    func testLastMealGetsEverythingLeft() {
        let fixed: [MealType: NutritionValues] = [
            .breakfast: NutritionValues(kcal: 600, protein: 45, carbs: 70, fat: 15),
            .lunch: NutritionValues(kcal: 800, protein: 60, carbs: 90, fat: 25),
            .snack: NutritionValues(kcal: 300, protein: 25, carbs: 30, fat: 8),
        ]
        let t = MealPlanner.target(for: .dinner, daily: daily, fixed: fixed)
        XCTAssertEqual(t, NutritionValues(kcal: 700, protein: 50, carbs: 70, fat: 22))
    }

    func testOverspentDayNeverGivesNegativeTargets() {
        let t = MealPlanner.target(for: .dinner, daily: daily,
                                   fixed: [.breakfast: NutritionValues(kcal: 3000, protein: 200, carbs: 300, fat: 90)])
        XCTAssertGreaterThanOrEqual(t.kcal, 0)
        XCTAssertGreaterThanOrEqual(t.fat, 0)
    }

    func testBestOptionScalesPortionTowardsTarget() {
        let lunch = MealPlanner.Candidate(id: "a", items: [.init(per100: chicken, grams: 150), .init(per100: rice, grams: 70), .init(per100: oil, grams: 5)])
        let base = MealPlanner.values(of: lunch, factor: 1)
        let target = NutritionValues(kcal: base.kcal * 1.2, protein: base.protein * 1.2, carbs: base.carbs * 1.2, fat: base.fat * 1.2)
        let option = MealPlanner.bestOption(lunch, target: target)!
        XCTAssertEqual(option.factor, 1.2, accuracy: 0.051)
        XCTAssertGreaterThan(option.fit, 0.95)
        XCTAssertTrue(MealPlanner.factorRange.contains(option.factor))
    }

    func testRankPrefersMatchingMacros() {
        let proteinHeavy = MealPlanner.Candidate(id: "protein", items: [.init(per100: chicken, grams: 250), .init(per100: rice, grams: 40)])
        let carbHeavy = MealPlanner.Candidate(id: "carbs", items: [.init(per100: oats, grams: 120), .init(per100: oil, grams: 10)])
        let target = NutritionValues(kcal: 450, protein: 55, carbs: 30, fat: 8)
        let ranked = MealPlanner.rank([carbHeavy, proteinHeavy], target: target)
        XCTAssertEqual(ranked.map(\.id), ["protein", "carbs"])
        XCTAssertGreaterThan(ranked[0].fit, ranked[1].fit)
    }

    func testRankLimitsToFourOptions() {
        let candidates = (0..<9).map { MealPlanner.Candidate(id: "\($0)", items: [.init(per100: rice, grams: Double(50 + $0 * 10))]) }
        XCTAssertEqual(MealPlanner.rank(candidates, target: NutritionValues(kcal: 300, protein: 6, carbs: 65, fat: 1)).count, 4)
    }

    func testOptionValuesMatchWeighableGrams() {
        let c = MealPlanner.Candidate(id: "x", items: [.init(per100: rice, grams: 83)])
        let v = MealPlanner.values(of: c, factor: 1.1)
        // 83 × 1,1 = 91,3 → se redondea a 90 g pesables
        XCTAssertEqual(v.kcal, 360 * 0.9, accuracy: 0.001)
        XCTAssertEqual(MealPlanner.values(of: c, factor: 1).kcal, 360 * 0.83, accuracy: 0.001)
    }
}
