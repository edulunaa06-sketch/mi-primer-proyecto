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

    /// Idea de comida suelta (biblioteca para elegir y combinar).
    struct Idea: Codable {
        let type: String
        let name: String
        let items: [Item]
    }

    let version: Int
    let disclaimer: String
    let foods: [Food]
    let menus: [Menu]
    /// Desde la versión 2 del catálogo.
    var ideas: [Idea] = []

    enum CodingKeys: String, CodingKey { case version, disclaimer, foods, menus, ideas }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        disclaimer = try c.decode(String.self, forKey: .disclaimer)
        foods = try c.decode([Food].self, forKey: .foods)
        menus = try c.decode([Menu].self, forKey: .menus)
        ideas = try c.decodeIfPresent([Idea].self, forKey: .ideas) ?? []
    }

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
        for idea in ideas {
            if MealType(rawValue: idea.type) == nil { errors.append("Tipo de comida inválido en idea \(idea.name)") }
            if idea.items.isEmpty { errors.append("Idea sin ingredientes: \(idea.name)") }
            for item in idea.items where !keys.contains(item.food) || item.grams <= 0 {
                errors.append("Ingrediente no válido (\(item.food)) en idea \(idea.name)")
            }
        }
        return errors
    }

    func totals(forIdea idea: Idea) -> NutritionValues {
        let byKey = Dictionary(uniqueKeysWithValues: foods.map { ($0.key, $0) })
        return NutritionMath.sum(idea.items.compactMap { item in byKey[item.food].map { $0.per100.scaled(toGrams: item.grams) } })
    }
}
