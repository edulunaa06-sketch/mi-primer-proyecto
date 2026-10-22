import Foundation

/// Búsqueda en el catálogo que entiende nombres comunes («macarrones» → pasta).
enum FoodSearch {
    /// Palabra que escribe la persona → palabra que aparece en el catálogo.
    static let aliases: [String: String] = [
        "macarr": "pasta", "espagu": "pasta", "tallar": "pasta", "fideo": "pasta", "penne": "pasta",
        "pechuga": "pollo", "filete": "ternera", "platano": "plátano", "banana": "plátano",
        "huevos": "huevo", "claras": "clara", "tostada": "pan", "bocadillo": "pan",
    ]

    static func matches(name: String, query: String) -> Bool {
        let q = fold(query)
        guard !q.isEmpty else { return true }
        let n = fold(name)
        if n.contains(q) { return true }
        return aliases.contains { key, target in q.hasPrefix(fold(key)) && n.contains(fold(target)) }
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_ES"))
            .trimmingCharacters(in: .whitespaces)
    }
}
