import XCTest
@testable import Atlas

final class ExpertLogicTests: XCTestCase {
    func testOpenFoodFacts() {
        XCTAssertNil(OpenFoodFacts.url(barcode: "123"))
        XCTAssertEqual(OpenFoodFacts.url(barcode: "8410000810004")?.host, "world.openfoodfacts.org")
        let json = """
        {"status":1,"product":{"product_name":"Yogur griego","brands":"Hacendado, Mercadona",
         "nutriments":{"energy-kcal_100g":121,"proteins_100g":"5,2","carbohydrates_100g":4,"fat_100g":10}}}
        """
        let p = OpenFoodFacts.parse(Data(json.utf8))
        XCTAssertEqual(p?.name, "Yogur griego (Hacendado)")
        XCTAssertEqual(p?.per100.kcal, 121)
        XCTAssertEqual(p?.per100.protein, 5.2)
        // Solo kJ → se convierte a kcal.
        let kj = #"{"status":1,"product":{"product_name":"Pan","nutriments":{"energy_100g":1046}}}"#
        XCTAssertEqual(OpenFoodFacts.parse(Data(kj.utf8))?.per100.kcal, 250)
        XCTAssertNil(OpenFoodFacts.parse(Data(#"{"status":0}"#.utf8)), "Producto no encontrado")
        XCTAssertNil(OpenFoodFacts.parse(Data(#"{"status":1,"product":{"product_name":"X","nutriments":{}}}"#.utf8)), "Sin calorías no se inventa")
    }

    func testReadiness() {
        XCTAssertEqual(Readiness.score(sleepHours: 8, energy: 5, soreness: 1), 100)
        XCTAssertEqual(Readiness.score(sleepHours: 4, energy: 1, soreness: 5), 0)
        XCTAssertGreaterThan(Readiness.score(sleepHours: 7.5, energy: 4, soreness: 2), 75)
        XCTAssertEqual(Readiness.advice(90).title, "Listo para apretar")
        XCTAssertEqual(Readiness.advice(20).title, "Prioriza recuperar")
    }

    func testRunningLoad() {
        let now = DateUtils.startOfWeek(Date()).addingTimeInterval(3 * 86400)
        func run(_ weeksAgo: Int, _ km: Double) -> (date: Date, meters: Double) {
            (now.addingTimeInterval(-Double(weeksAgo) * 7 * 86400), km * 1000)
        }
        let r = RunningLoad.compute([run(0, 30), run(1, 20), run(2, 20), run(3, 20), run(4, 20)], now: now)
        XCTAssertEqual(r.lastWeekKm, 20)
        XCTAssertEqual(r.fourWeekAverageKm, 20)
        XCTAssertEqual(r.nextWeekMaxKm, 22)
        XCTAssertTrue(r.isSpike, "30 km frente a 20 de media es un pico")
        XCTAssertEqual(RunningLoad.compute([], now: now).nextWeekMaxKm, 5)
    }

    func testProteinPerMeal() {
        XCTAssertEqual(ProteinPlan.perMeal(dailyProtein: 180), 45)
        XCTAssertEqual(ProteinPlan.perMeal(dailyProtein: 60), 25)
        XCTAssertEqual(ProteinPlan.perMeal(dailyProtein: 0), 0)
    }
}
