#if canImport(SwiftData)
import SwiftData
import XCTest
@testable import Atlas

/// «Mis alimentos»: lo que escaneas o apuntas tú queda guardado con sus calorías por 100 g,
/// para que otro día solo haya que poner los gramos.
@MainActor
final class MyFoodsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try ModelContainer(for: AtlasApp.schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
    }

    private func per100(_ kcal: Double) -> NutritionValues {
        NutritionValues(kcal: kcal, protein: 10, carbs: 20, fat: 5)
    }

    // MARK: Escanear y volver a usarlo

    func testAScannedProductIsSavedAndFoundAgainWithoutInternet() {
        DataStore.saveScanned(barcode: "8410076472014", name: "Atún claro", brand: "Calvo",
                              per100: per100(186), source: "Open Food Facts", in: context)
        let again = DataStore.food(withBarcode: "8410076472014", in: context)
        XCTAssertEqual(again?.name, "Atún claro")
        XCTAssertEqual(again?.kcalPer100, 186)
        XCTAssertEqual(again?.displayName, "Calvo · Atún claro")
        XCTAssertTrue(again?.isScanned ?? false)
    }

    func testTheGramsYouUsedComeBackNextTime() {
        let food = DataStore.saveScanned(barcode: "1234567890128", name: "Tortitas de arroz", brand: "",
                                         per100: per100(380), source: "Open Food Facts", in: context)
        XCTAssertEqual(food.lastGrams, 100, "Por defecto, 100 g")
        DataStore.recordUse(of: food, grams: 50, in: context)
        let again = DataStore.food(withBarcode: "1234567890128", in: context)
        XCTAssertEqual(again?.lastGrams, 50, "La próxima vez propone los gramos de la última")
        XCTAssertEqual(again?.timesUsed, 1)
    }

    func testScanningTheSameCodeTwiceDoesNotDuplicateIt() {
        DataStore.saveScanned(barcode: "4006381333931", name: "Galletas", brand: "",
                              per100: per100(450), source: "Open Food Facts", in: context)
        DataStore.saveScanned(barcode: "4006381333931", name: "Galletas", brand: "",
                              per100: per100(450), source: "Open Food Facts", in: context)
        XCTAssertEqual(DataStore.myFoods(in: context).count, 1)
    }

    // MARK: Apuntado a mano, sin código

    func testSomethingWithoutABarcodeIsSavedByName() {
        DataStore.saveScanned(barcode: "", name: "Tortilla de mi madre", brand: "",
                              per100: per100(210), source: "Etiqueta (lo has puesto tú)", in: context)
        DataStore.saveScanned(barcode: "", name: "  tortilla de mi madre  ", brand: "",
                              per100: per100(210), source: "Etiqueta (lo has puesto tú)", in: context)
        let mine = DataStore.myFoods(in: context)
        XCTAssertEqual(mine.count, 1, "El mismo nombre no se guarda dos veces")
        XCTAssertFalse(mine[0].isScanned, "Sin código de barras")
        XCTAssertTrue(mine[0].isMine)
    }

    // MARK: Lo tuyo y lo que trae la app

    func testMyFoodsLeavesOutTheOnesTheAppBringsByDefault() {
        let preset = FoodItem(name: "Arroz blanco", per100: per100(360), basis: .raw, seedKey: "arroz-blanco")
        context.insert(preset)
        DataStore.saveScanned(barcode: "5000159484695", name: "Barrita", brand: "",
                              per100: per100(500), source: "Open Food Facts", in: context)
        let mine = DataStore.myFoods(in: context)
        XCTAssertEqual(mine.map(\.name), ["Barrita"])
        XCTAssertFalse(preset.isMine, "Los de serie no son tuyos")
    }

    // MARK: Lo que corriges tú manda

    func testYourOwnValuesAreNotOverwrittenByOpenFoodFacts() {
        let food = DataStore.saveScanned(barcode: "8410076472014", name: "Atún", brand: "",
                                         per100: per100(186), source: "Open Food Facts", in: context)
        food.isUserEdited = true
        food.kcalPer100 = 120
        DataStore.saveScanned(barcode: "8410076472014", name: "Atún de otra forma", brand: "Otra",
                              per100: per100(999), source: "Open Food Facts", in: context)
        let again = DataStore.food(withBarcode: "8410076472014", in: context)
        XCTAssertEqual(again?.kcalPer100, 120, "Lo que pusiste con la etiqueta no se pisa")
        XCTAssertEqual(again?.name, "Atún")
    }
}
#endif
