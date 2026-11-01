import XCTest
@testable import Atlas

/// Lectura de códigos de barras y de lo que contesta Open Food Facts.
/// Aquí no se llama a internet: se comprueba que lo que llega se interpreta bien
/// y que lo que falta se señala en vez de rellenarse con ceros a la callada.
final class BarcodeTests: XCTestCase {

    // MARK: El código

    func testOnlyProductBarcodeLengthsAreAccepted() {
        XCTAssertTrue(OpenFoodFacts.isPlausible("8410076472014"))  // EAN-13
        XCTAssertTrue(OpenFoodFacts.isPlausible("20033313"))       // EAN-8
        XCTAssertFalse(OpenFoodFacts.isPlausible("123"))
        XCTAssertFalse(OpenFoodFacts.isPlausible("84100764720AB"))
        XCTAssertFalse(OpenFoodFacts.isPlausible(""))
    }

    func testCheckDigit() {
        // Códigos con su dígito de control correcto.
        XCTAssertTrue(OpenFoodFacts.hasValidCheckDigit("4006381333931"))
        XCTAssertTrue(OpenFoodFacts.hasValidCheckDigit("5000159484695"))
        // El mismo con el último dígito cambiado.
        XCTAssertFalse(OpenFoodFacts.hasValidCheckDigit("4006381333932"))
    }

    func testTheUrlPointsAtOpenFoodFactsAndAsksForTheFieldsItNeeds() {
        let url = OpenFoodFacts.url(for: "4006381333931")
        XCTAssertEqual(url?.host, "world.openfoodfacts.org")
        XCTAssertTrue(url?.absoluteString.contains("/api/v2/product/4006381333931.json") ?? false)
        XCTAssertTrue(url?.absoluteString.contains("nutriments") ?? false)
    }

    func testTheAppIdentifiesItself() {
        XCTAssertTrue(OpenFoodFacts.userAgent(version: "1.1").hasPrefix("NowOrNever/1.1"))
    }

    // MARK: La respuesta

    private func json(_ text: String) -> Data { Data(text.utf8) }

    func testReadsAProductWithEverything() throws {
        let data = json("""
        {"status":1,"product":{"product_name":"Atún claro en aceite de oliva","brands":"Calvo, Otra",
        "quantity":"3 x 80 g","nutriments":{"energy-kcal_100g":186,"proteins_100g":24.5,
        "carbohydrates_100g":0.5,"fat_100g":9.8}}}
        """)
        let product = try OpenFoodFacts.parse(data, barcode: "8410076472014")
        XCTAssertEqual(product.name, "Atún claro en aceite de oliva")
        XCTAssertEqual(product.brand, "Calvo")
        XCTAssertEqual(product.quantity, "3 x 80 g")
        XCTAssertEqual(product.per100.kcal, 186)
        XCTAssertEqual(product.per100.protein, 24.5)
        XCTAssertTrue(product.hasAllMacros)
        XCTAssertEqual(product.displayName, "Calvo · Atún claro en aceite de oliva")
    }

    func testPrefersTheSpanishName() throws {
        let data = json("""
        {"status":1,"product":{"product_name":"Tuna","product_name_es":"Atún","brands":"",
        "nutriments":{"energy-kcal_100g":100}}}
        """)
        XCTAssertEqual(try OpenFoodFacts.parse(data, barcode: "1").name, "Atún")
    }

    func testMissingMacrosAreFlaggedInsteadOfInvented() throws {
        let data = json("""
        {"status":1,"product":{"product_name":"Galletas","nutriments":{"energy-kcal_100g":450,"fat_100g":20}}}
        """)
        let product = try OpenFoodFacts.parse(data, barcode: "1")
        XCTAssertEqual(product.per100.kcal, 450)
        XCTAssertEqual(product.per100.fat, 20)
        XCTAssertEqual(product.missingMacros, ["proteínas", "carbohidratos"])
        XCTAssertFalse(product.hasAllMacros)
    }

    func testEnergyInKilojoulesIsConverted() throws {
        let data = json("""
        {"status":1,"product":{"product_name":"Zumo","nutriments":{"energy_100g":188}}}
        """)
        let product = try OpenFoodFacts.parse(data, barcode: "1")
        XCTAssertEqual(product.per100.kcal, 188 / 4.184, accuracy: 0.01)
    }

    func testNumbersThatComeAsTextAreRead() throws {
        let data = json("""
        {"status":1,"product":{"product_name":"Pan","nutriments":{"energy-kcal_100g":"265","proteins_100g":"9,0"}}}
        """)
        let product = try OpenFoodFacts.parse(data, barcode: "1")
        XCTAssertEqual(product.per100.kcal, 265)
        XCTAssertEqual(product.per100.protein, 9)
    }

    func testAProductThatIsNotThereIsReportedAsMissing() {
        let data = json("""
        {"status":0,"status_verbose":"product not found"}
        """)
        XCTAssertThrowsError(try OpenFoodFacts.parse(data, barcode: "0000000000000")) { error in
            XCTAssertEqual(error as? OpenFoodFacts.LookupError, .notFound("0000000000000"))
        }
    }

    func testAProductWithoutCaloriesIsNotGuessed() {
        let data = json("""
        {"status":1,"product":{"product_name":"Agua mineral","nutriments":{"proteins_100g":0}}}
        """)
        XCTAssertThrowsError(try OpenFoodFacts.parse(data, barcode: "1")) { error in
            XCTAssertEqual(error as? OpenFoodFacts.LookupError, .noEnergy("Agua mineral"))
        }
    }

    func testRubbishIsNotTakenForAProduct() {
        XCTAssertThrowsError(try OpenFoodFacts.parse(json("no soy json"), barcode: "1")) { error in
            XCTAssertEqual(error as? OpenFoodFacts.LookupError, .badResponse)
        }
    }

    func testEveryErrorExplainsItselfInSpanish() {
        let errors: [OpenFoodFacts.LookupError] = [
            .notFound("123"), .noEnergy("Pan"), .badBarcode("abc"), .badResponse, .network("sin red"),
        ]
        for error in errors {
            XCTAssertFalse(error.message.isEmpty)
            XCTAssertTrue(error.message.count > 20, "Un error tiene que decir qué hacer: \(error.message)")
        }
    }
}
