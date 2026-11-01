#if canImport(SwiftData)
import SwiftData
import XCTest
@testable import Atlas

/// Recetas y menús propios: crear, duplicar, borrar y que las cuentas por ración salgan
/// de los ingredientes (se ejecutan en el simulador).
@MainActor
final class RecipePersistenceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try ModelContainer(for: AtlasApp.schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
    }

    private func food(_ name: String, kcal: Double, protein: Double) -> FoodItem {
        let item = FoodItem(name: name,
                            per100: NutritionValues(kcal: kcal, protein: protein, carbs: 0, fat: 0),
                            basis: .raw, isProvisional: false)
        context.insert(item)
        return item
    }

    private func addIngredient(_ plan: MenuPlan, _ item: FoodItem, grams: Double) {
        guard let meal = plan.sortedMeals.first else { return XCTFail("La receta no tiene comidas") }
        let line = MealItem(grams: grams, order: meal.items.count, food: item)
        context.insert(line)
        line.meal = meal
        try? context.save()
    }

    // MARK: Crear

    func testCreatingARecipeLeavesItEmptyAndMarkedAsMine() {
        let plan = DataStore.createRecipe(name: "Pollo con arroz", mealType: .lunch, servings: 4, in: context)
        XCTAssertTrue(plan.isLibrary, "Una receta va a la biblioteca de ideas")
        XCTAssertFalse(plan.isExample, "No es de ejemplo: la ha hecho el usuario")
        XCTAssertEqual(plan.servings, 4)
        XCTAssertEqual(plan.meals.count, 1)
        XCTAssertEqual(plan.sortedMeals.first?.mealType, .lunch)
        XCTAssertTrue(plan.sortedMeals.first?.items.isEmpty ?? false)
        XCTAssertEqual(plan.totals, .zero, "Sin ingredientes, el total es cero y no un número inventado")
    }

    func testCreatingAMenuGivesTheFourMeals() {
        let plan = DataStore.createMenu(name: "Mi menú", in: context)
        XCTAssertFalse(plan.isLibrary)
        XCTAssertEqual(plan.meals.count, MealType.allCases.count)
        XCTAssertEqual(Set(plan.meals.map(\.mealType)), Set(MealType.allCases))
    }

    func testNumbersDoNotCollideWithTheExamples() {
        let first = DataStore.createMenu(name: "A", in: context)
        let second = DataStore.createMenu(name: "B", in: context)
        XCTAssertNotEqual(first.number, second.number)
        let recipe = DataStore.createRecipe(name: "C", mealType: .dinner, in: context)
        let recipe2 = DataStore.createRecipe(name: "D", mealType: .dinner, in: context)
        XCTAssertNotEqual(recipe.number, recipe2.number)
    }

    func testEmptyNameIsIgnoredWhenRenaming() {
        let plan = DataStore.createRecipe(name: "Tortilla", mealType: .dinner, in: context)
        DataStore.rename(plan, to: "   ", in: context)
        XCTAssertEqual(plan.name, "Tortilla")
        DataStore.rename(plan, to: "Tortilla de claras", in: context)
        XCTAssertEqual(plan.name, "Tortilla de claras")
    }

    // MARK: Cuentas

    func testTotalsAndPerServingComeFromTheIngredients() {
        let plan = DataStore.createRecipe(name: "Pollo con arroz", mealType: .lunch, servings: 4, in: context)
        addIngredient(plan, food("Pollo", kcal: 165, protein: 31), grams: 600)
        addIngredient(plan, food("Arroz", kcal: 350, protein: 7), grams: 200)

        // 600 g de pollo = 990 kcal; 200 g de arroz = 700 kcal.
        XCTAssertEqual(plan.totals.kcal, 1690, accuracy: 0.001)
        XCTAssertEqual(plan.rawGrams, 800, accuracy: 0.001)
        let perServing = plan.perServing!
        XCTAssertEqual(perServing.kcal, 422.5, accuracy: 0.001)

        // Sin pesar el resultado no hay valores por 100 g cocinados.
        XCTAssertNil(plan.per100gCooked)
        XCTAssertNil(plan.yieldFactor)

        plan.cookedWeightGrams = 700
        try? context.save()
        XCTAssertEqual(plan.per100gCooked!.kcal, 1690 / 7, accuracy: 0.001)
        XCTAssertEqual(plan.yieldFactor!, 0.875, accuracy: 0.001)
    }

    func testOneServingMeansNoPerServingBreakdown() {
        let plan = DataStore.createRecipe(name: "Batido", mealType: .snack, servings: 1, in: context)
        addIngredient(plan, food("Leche", kcal: 50, protein: 3.4), grams: 300)
        XCTAssertNil(plan.perServing, "Con una ración no hay nada que repartir")
        XCTAssertEqual(plan.totals.kcal, 150, accuracy: 0.001)
    }

    // MARK: Duplicar

    func testDuplicatingCopiesTheIngredientsWithoutTouchingTheOriginal() {
        let plan = DataStore.createRecipe(name: "Pollo con arroz", mealType: .lunch, servings: 4, in: context)
        addIngredient(plan, food("Pollo", kcal: 165, protein: 31), grams: 600)
        plan.cookedWeightGrams = 500
        try? context.save()

        let copy = DataStore.duplicate(plan, in: context)
        XCTAssertEqual(copy.name, "Pollo con arroz (copia)")
        XCTAssertEqual(copy.servings, 4)
        XCTAssertEqual(copy.cookedWeightGrams, 500)
        XCTAssertEqual(copy.totals, plan.totals)
        XCTAssertFalse(copy.isExample)
        XCTAssertNotEqual(copy.id, plan.id)

        // Cambiar la copia no cambia el original.
        copy.sortedMeals.first?.sortedItems.first?.grams = 100
        try? context.save()
        XCTAssertEqual(plan.totals.kcal, 990, accuracy: 0.001)
        XCTAssertEqual(copy.totals.kcal, 165, accuracy: 0.001)
    }

    // MARK: Borrar

    func testDeletingAMenuCleansItsReferences() throws {
        let plan = DataStore.createMenu(name: "Mi menú", in: context)
        let settings = DataStore.settings(context)
        settings.defaultPlanID = plan.id
        DataStore.select(plan: plan, for: Date(), in: context)
        DataStore.choose(.lunch, planID: plan.id, factor: 1, on: Date(), in: context)
        try context.save()

        DataStore.delete(plan, in: context)

        XCTAssertNil(DataStore.settings(context).defaultPlanID, "Deja de ser el menú predeterminado")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DayPlanSelection>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DayMealChoice>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MenuPlan>()), 0)
        // Y los ingredientes y comidas se van con él (borrado en cascada).
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MealTemplate>()), 0)
    }

    func testDeletingDoesNotTouchWhatIsAlreadyInTheHistory() throws {
        let plan = DataStore.createRecipe(name: "Tortilla", mealType: .dinner, in: context)
        addIngredient(plan, food("Huevo", kcal: 155, protein: 13), grams: 200)
        // Se marca como comida: el registro guarda su propia copia de los valores.
        DataStore.setMeal(plan.sortedMeals.first!, planName: plan.displayName, completed: true,
                          on: Date(), in: context)
        try context.save()
        let before = try context.fetch(FetchDescriptor<MealRecord>())
        XCTAssertEqual(before.count, 1)
        XCTAssertEqual(before.first?.kcal ?? 0, 310, accuracy: 0.001)

        DataStore.delete(plan, in: context)

        let after = try context.fetch(FetchDescriptor<MealRecord>())
        XCTAssertEqual(after.count, 1, "El historial no se borra con la receta")
        XCTAssertEqual(after.first?.kcal ?? 0, 310, accuracy: 0.001)
    }

    // MARK: Copia de seguridad

    func testBackupKeepsServingsAndCookedWeight() throws {
        let plan = DataStore.createRecipe(name: "Pollo con arroz", mealType: .lunch, servings: 3, in: context)
        addIngredient(plan, food("Pollo", kcal: 165, protein: 31), grams: 600)
        plan.cookedWeightGrams = 450
        try context.save()

        let file = try BackupService.makeBackup(context)
        let saved = file.plans.first { $0.name == "Pollo con arroz" }
        XCTAssertEqual(saved?.servings, 3)
        XCTAssertEqual(saved?.cookedWeightGrams, 450)

        try BackupService.restore(try BackupFile.decode(try file.encoded()), into: context)
        let restored = try context.fetch(FetchDescriptor<MenuPlan>()).first { $0.name == "Pollo con arroz" }
        XCTAssertEqual(restored?.servings, 3)
        XCTAssertEqual(restored?.cookedWeightGrams, 450)
        XCTAssertEqual(restored?.totals.kcal ?? 0, 990, accuracy: 0.001)
    }
}
#endif
