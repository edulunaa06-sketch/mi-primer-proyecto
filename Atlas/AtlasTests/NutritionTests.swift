import XCTest
@testable import Atlas

final class NutritionTests: XCTestCase {
    func testScalingMatchesUserExamples() {
        let chicken = NutritionValues(kcal: 120, protein: 22.5, carbs: 0, fat: 2.6)
        XCTAssertEqual(NutritionMath.values(per100: chicken, grams: 180).kcal, 216, accuracy: 0.001)
        let rice = NutritionValues(kcal: 360, protein: 6.5, carbs: 79.3, fat: 0.6)
        XCTAssertEqual(NutritionMath.values(per100: rice, grams: 80).kcal, 288, accuracy: 0.001)
        let oil = NutritionValues(kcal: 884, protein: 0, carbs: 0, fat: 100)
        XCTAssertEqual(NutritionMath.values(per100: oil, grams: 5).kcal, 44.2, accuracy: 0.001)
    }

    func testSumIsComputedNotTyped() {
        let a = NutritionValues(kcal: 100, protein: 10, carbs: 5, fat: 2)
        let b = NutritionValues(kcal: 50, protein: 1, carbs: 10, fat: 0.5)
        let total = NutritionMath.sum([a, b])
        XCTAssertEqual(total, NutritionValues(kcal: 150, protein: 11, carbs: 15, fat: 2.5))
    }

    func testChangingGramsUpdatesValues() {
        let food = NutritionValues(kcal: 200, protein: 20, carbs: 10, fat: 5)
        let before = NutritionMath.values(per100: food, grams: 100)
        let after = NutritionMath.values(per100: food, grams: 150)
        XCTAssertEqual(after.kcal, before.kcal * 1.5, accuracy: 0.0001)
        XCTAssertEqual(after.protein, 30, accuracy: 0.0001)
    }

    func testNegativeGramsClampToZero() {
        let food = NutritionValues(kcal: 200, protein: 20, carbs: 10, fat: 5)
        XCTAssertEqual(NutritionMath.values(per100: food, grams: -50), .zero)
    }

    func testProgressHandlesInvalidTargets() {
        XCTAssertEqual(NutritionMath.progress(consumed: 100, target: 0), 0)
        XCTAssertEqual(NutritionMath.progress(consumed: 3000, target: 2300), 1)
        XCTAssertEqual(NutritionMath.progress(consumed: 1150, target: 2300), 0.5, accuracy: 0.0001)
    }

    private func loadCatalog() throws -> SeedCatalog {
        // En Xcode el catálogo está en el bundle de la app (host de las pruebas).
        if let catalog = try? SeedCatalog.loadFromBundle(.main) { return catalog }
        // Ejecución fuera de Xcode: ruta relativa al archivo de pruebas.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Atlas/Resources/SeedCatalog.json")
        return try SeedCatalog.decode(from: Data(contentsOf: url))
    }

    func testSeedCatalogIsConsistent() throws {
        let catalog = try loadCatalog()
        XCTAssertEqual(catalog.validationErrors(), [])
        XCTAssertEqual(catalog.menus.count, 9)
        for menu in catalog.menus {
            XCTAssertEqual(menu.meals.count, 4, "Menú \(menu.number)")
        }
    }

    func testSeedMenuTotalsAreSumOfIngredients() throws {
        let catalog = try loadCatalog()
        let foods = Dictionary(uniqueKeysWithValues: catalog.foods.map { ($0.key, $0) })
        for menu in catalog.menus {
            var manual = 0.0
            for meal in menu.meals {
                for item in meal.items {
                    manual += (foods[item.food]?.kcal ?? 0) * item.grams / 100
                }
            }
            XCTAssertEqual(catalog.totals(forMenu: menu).kcal, manual, accuracy: 0.001)
            // Los menús de ejemplo deben estar en un rango razonable respecto al objetivo provisional.
            XCTAssertTrue((1900...2600).contains(manual), "Menú \(menu.number): \(manual) kcal")
        }
    }

    func testSeedFoodsHaveCoherentEnergy() throws {
        let catalog = try loadCatalog()
        for food in catalog.foods where food.kcal > 50 {
            let estimate = NutritionMath.kcalFromMacros(food.per100)
            XCTAssertLessThan(abs(estimate - food.kcal) / food.kcal, 0.15, food.name)
        }
    }

    func testCatalogWeightBasisRules() throws {
        let catalog = try loadCatalog()
        let basis = Dictionary(uniqueKeysWithValues: catalog.foods.map { ($0.key, $0.basis) })
        XCTAssertEqual(basis["rice"], WeightBasis.dry.rawValue)
        XCTAssertEqual(basis["pasta"], WeightBasis.dry.rawValue)
        XCTAssertEqual(basis["oats"], WeightBasis.dry.rawValue)
        XCTAssertEqual(basis["chicken_breast"], WeightBasis.raw.rawValue)
        XCTAssertEqual(basis["salmon"], WeightBasis.raw.rawValue)
        XCTAssertEqual(basis["chickpeas"], WeightBasis.cookedDrained.rawValue)
        XCTAssertEqual(basis["lentils"], WeightBasis.cookedDrained.rawValue)
        XCTAssertEqual(basis["tuna_drained"], WeightBasis.drained.rawValue)
        XCTAssertEqual(basis["olive_oil"], WeightBasis.asWeighed.rawValue)
    }
}

final class ComplianceTests: XCTestCase {
    func testRestDayExcludesTraining() {
        let c = DailyCompliance(mealsCompleted: 2, sessionsCompleted: 0, sessionsScheduled: 0, steps: 4000, stepGoal: 8000)
        XCTAssertEqual(c.components.map(\.name), ["Comidas", "Pasos"])
        XCTAssertEqual(c.fraction, 0.5, accuracy: 0.0001)
    }

    func testMissingStepsAreNotInvented() {
        let c = DailyCompliance(mealsCompleted: 4, sessionsCompleted: 1, sessionsScheduled: 2, steps: nil, stepGoal: 8000)
        XCTAssertEqual(c.components.count, 2)
        XCTAssertEqual(c.fraction, 0.75, accuracy: 0.0001)
    }

    func testStepsCappedAtHundredPercent() {
        let c = DailyCompliance(mealsCompleted: 0, sessionsCompleted: 0, sessionsScheduled: 0, steps: 20000, stepGoal: 8000)
        XCTAssertEqual(c.components.last?.fraction, 1)
    }

    func testWeightChanges() {
        let cal = DateUtils.calendar
        let base = cal.date(from: DateComponents(year: 2026, month: 10, day: 22))!
        let points = [
            WeightStats.Point(date: base, kg: 85.1),
            WeightStats.Point(date: cal.date(byAdding: .day, value: 7, to: base)!, kg: 84.6),
            WeightStats.Point(date: cal.date(byAdding: .day, value: 14, to: base)!, kg: 84.2),
        ]
        XCTAssertEqual(WeightStats.first(points)?.kg, 85.1)
        XCTAssertEqual(WeightStats.latest(points)?.kg, 84.2)
        XCTAssertEqual(WeightStats.change(points: points, days: 7)!, -0.4, accuracy: 0.0001)
        XCTAssertNil(WeightStats.change(points: points, days: 30))
    }
}

/// Pruebas de las cuentas de una receta: por ración y por 100 g cocinados.
final class RecipeMathTests: XCTestCase {
    private let total = NutritionValues(kcal: 1200, protein: 90, carbs: 120, fat: 30)

    func testPerServingSplitsTheTotal() {
        let perServing = RecipeMath.perServing(total, servings: 4)!
        XCTAssertEqual(perServing.kcal, 300, accuracy: 0.0001)
        XCTAssertEqual(perServing.protein, 22.5, accuracy: 0.0001)
        XCTAssertEqual(perServing.carbs, 30, accuracy: 0.0001)
        XCTAssertEqual(perServing.fat, 7.5, accuracy: 0.0001)
    }

    func testOneServingHasNothingToSplit() {
        XCTAssertNil(RecipeMath.perServing(total, servings: 1))
        XCTAssertNil(RecipeMath.perServing(total, servings: 0))
        XCTAssertNil(RecipeMath.perServing(total, servings: -3))
    }

    func testPer100gCookedNeedsTheCookedWeight() {
        // 1200 kcal en 800 g cocinados = 150 kcal / 100 g.
        let per100 = RecipeMath.per100gCooked(total, cookedGrams: 800)!
        XCTAssertEqual(per100.kcal, 150, accuracy: 0.0001)
        XCTAssertEqual(per100.protein, 11.25, accuracy: 0.0001)
        // Sin peso cocinado no se calcula nada: no se inventa.
        XCTAssertNil(RecipeMath.per100gCooked(total, cookedGrams: 0))
        XCTAssertNil(RecipeMath.per100gCooked(total, cookedGrams: -200))
    }

    func testYieldFactorAndItsExplanation() {
        // La carne pierde agua.
        let meat = RecipeMath.yieldFactor(rawGrams: 1000, cookedGrams: 750)!
        XCTAssertEqual(meat, 0.75, accuracy: 0.0001)
        XCTAssertTrue(RecipeMath.yieldText(meat).contains("Pierde agua"))
        // El arroz la absorbe.
        let rice = RecipeMath.yieldFactor(rawGrams: 100, cookedGrams: 250)!
        XCTAssertEqual(rice, 2.5, accuracy: 0.0001)
        XCTAssertTrue(RecipeMath.yieldText(rice).contains("Absorbe agua"))
        // Y hay platos que pesan casi lo mismo.
        XCTAssertTrue(RecipeMath.yieldText(1.0).contains("prácticamente lo mismo"))
        XCTAssertNil(RecipeMath.yieldFactor(rawGrams: 0, cookedGrams: 100))
    }

    func testGramsPerServing() {
        XCTAssertEqual(RecipeMath.gramsPerServing(cookedGrams: 800, servings: 4)!, 200, accuracy: 0.0001)
        XCTAssertNil(RecipeMath.gramsPerServing(cookedGrams: nil, servings: 4))
        XCTAssertNil(RecipeMath.gramsPerServing(cookedGrams: 800, servings: 0))
    }

    func testTheTotalIsNeverInventedFromTheCookedWeightAlone() {
        // Con un total de cero, las cuentas dan cero, no un número cualquiera.
        let zero = RecipeMath.per100gCooked(.zero, cookedGrams: 500)!
        XCTAssertEqual(zero.kcal, 0)
    }
}
