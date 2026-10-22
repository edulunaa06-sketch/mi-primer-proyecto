import Foundation

/// Estructura del archivo `SeedCatalog.json` (catálogo y menús de EJEMPLO).
struct SeedCatalog: Codable {
    struct Food: Codable {
        let key: String
        let name: String
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let basis: String
        let provisional: Bool
        let macrosKnown: Bool
        let source: String

        var per100: NutritionValues { NutritionValues(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
    }

    struct Item: Codable {
        let food: String
        let grams: Double
    }

    struct Meal: Codable {
        let type: String
        let items: [Item]
    }

    struct Menu: Codable {
        let number: Int
        let name: String
        let note: String
        let meals: [Meal]
    }

    let version: Int
    let disclaimer: String
    let foods: [Food]
    let menus: [Menu]

    static func decode(from data: Data) throws -> SeedCatalog {
        try JSONDecoder().decode(SeedCatalog.self, from: data)
    }

    static func loadFromBundle(_ bundle: Bundle = .main) throws -> SeedCatalog {
        guard let url = bundle.url(forResource: "SeedCatalog", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(from: Data(contentsOf: url))
    }

    /// Totales calculados (no escritos a mano) de un menú. Se usa en pruebas.
    func totals(forMenu menu: Menu) -> NutritionValues {
        let byKey = Dictionary(uniqueKeysWithValues: foods.map { ($0.key, $0) })
        var total = NutritionValues.zero
        for meal in menu.meals {
            for item in meal.items {
                if let food = byKey[item.food] {
                    total += food.per100.scaled(toGrams: item.grams)
                }
            }
        }
        return total
    }

    /// Lista de problemas de coherencia (referencias rotas, tipos inválidos, etc.).
    func validationErrors() -> [String] {
        var errors: [String] = []
        let keys = Set(foods.map(\.key))
        if keys.count != foods.count { errors.append("Claves de alimento duplicadas") }
        for food in foods {
            if WeightBasis(rawValue: food.basis) == nil { errors.append("Base de peso inválida en \(food.key)") }
            if food.kcal < 0 || food.protein < 0 || food.carbs < 0 || food.fat < 0 {
                errors.append("Valores negativos en \(food.key)")
            }
        }
        if menus.count != 9 { errors.append("Se esperaban 9 menús y hay \(menus.count)") }
        for menu in menus {
            let types = menu.meals.map(\.type)
            if Set(types) != Set(MealType.allCases.map(\.rawValue)) || types.count != 4 {
                errors.append("El menú \(menu.number) no tiene exactamente desayuno, comida, merienda y cena")
            }
            for meal in menu.meals {
                for item in meal.items {
                    if !keys.contains(item.food) { errors.append("Alimento desconocido \(item.food) en menú \(menu.number)") }
                    if item.grams <= 0 { errors.append("Gramos no válidos en menú \(menu.number)") }
                }
            }
        }
        return errors
    }
}
