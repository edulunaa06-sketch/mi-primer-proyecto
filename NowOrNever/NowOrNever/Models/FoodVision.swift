import Foundation

/// Traduce lo que reconoce el iPhone en una foto (clasificador de imágenes de Apple, gratis y sin internet)
/// a alimentos de la tabla de la app. El clasificador da categorías generales en inglés («rice», «salad»,
/// «potato»…) y no sabe si algo está cocido o crudo: por eso se sugieren las versiones cocinadas y la
/// persona confirma, quita o añade alimentos y pone los gramos.
enum FoodVision {
    struct Label: Equatable {
        let identifier: String
        let confidence: Double
    }

    /// Palabra del clasificador → clave del alimento en la tabla. Las más concretas van primero
    /// («sweet_potato» antes que «potato»).
    static let keywords: [(word: String, food: String)] = [
        ("sweet_potato", "sweet_potato_baked"), ("yam", "sweet_potato_baked"),
        ("french_fries", "potato_boiled"), ("fries", "potato_boiled"), ("potato", "potato_boiled"),
        ("fried_rice", "rice_cooked"), ("risotto", "rice_cooked"), ("rice", "rice_cooked"),
        ("spaghetti", "pasta_cooked"), ("macaroni", "pasta_cooked"), ("noodle", "pasta_cooked"), ("pasta", "pasta_cooked"),
        ("quinoa", "quinoa_cooked"), ("couscous", "couscous"), ("oatmeal", "oats"), ("porridge", "oats"), ("oat", "oats"),
        ("toast", "bread_white"), ("baguette", "bread_white"), ("sandwich", "bread_white"), ("bread", "bread_white"),
        ("tortilla", "tortilla_ww"), ("wrap", "tortilla_ww"),
        ("chicken", "chicken_grilled"), ("poultry", "chicken_grilled"), ("turkey", "turkey_breast"),
        ("salmon", "salmon_grilled"), ("tuna", "tuna_drained"), ("sardine", "sardines"), ("shrimp", "shrimp"),
        ("prawn", "shrimp"), ("cod", "cod"), ("fish", "cod"),
        ("steak", "lean_beef"), ("beef", "lean_beef"), ("burger", "lean_beef"), ("hamburger", "lean_beef"),
        ("pork", "pork_loin"), ("ham", "cooked_ham"), ("tofu", "tofu"),
        ("omelet", "egg"), ("fried_egg", "egg"), ("egg", "egg_boiled"),
        ("cottage_cheese", "cottage"), ("cheese", "fresh_cheese"), ("yogurt", "greek_yogurt"), ("yoghurt", "greek_yogurt"),
        ("milk", "milk_semi"),
        ("hummus", "hummus"), ("chickpea", "chickpeas"), ("lentil", "lentils"), ("pea", "peas"),
        ("green_bean", "green_beans"), ("broccoli", "broccoli"), ("carrot", "carrot"), ("tomato", "tomato"),
        ("cucumber", "cucumber"), ("spinach", "spinach"), ("lettuce", "lettuce"), ("salad", "lettuce"),
        ("mushroom", "mushrooms"), ("onion", "onion"), ("bell_pepper", "red_pepper"), ("pepper", "red_pepper"),
        ("zucchini", "zucchini"), ("courgette", "zucchini"), ("avocado", "avocado"), ("guacamole", "avocado"),
        ("banana", "banana"), ("apple", "apple"), ("strawberry", "strawberries"), ("blueberry", "blueberries"),
        ("berry", "blueberries"), ("kiwi", "kiwi"), ("orange", "orange"), ("citrus", "orange"),
        ("pineapple", "pineapple"), ("mango", "mango"),
        ("almond", "almonds"), ("walnut", "walnuts"), ("nut", "walnuts"), ("peanut_butter", "peanut_butter"),
        ("honey", "honey"), ("olive_oil", "olive_oil"),
    ]

    /// Claves de la tabla para las etiquetas con confianza suficiente, sin repetir y de más a menos seguras.
    static func catalogKeys(for labels: [Label], minConfidence: Double = 0.12, limit: Int = 6) -> [String] {
        var keys: [String] = []
        for label in labels.sorted(by: { $0.confidence > $1.confidence }) where label.confidence >= minConfidence {
            let id = label.identifier.lowercased().replacingOccurrences(of: " ", with: "_")
            let words = Set(id.split(separator: "_").map(String.init))
            // Coincide la etiqueta entera, una palabra suelta («fried_rice» → «rice») o un plural («peas»).
            guard let match = keywords.first(where: { kw in
                id == kw.word || id.contains(kw.word) && kw.word.contains("_")
                    || words.contains(kw.word) || words.contains(kw.word + "s") || words.contains(kw.word + "es")
            }) else { continue }
            if !keys.contains(match.food) { keys.append(match.food) }
            if keys.count == limit { break }
        }
        return keys
    }
}
