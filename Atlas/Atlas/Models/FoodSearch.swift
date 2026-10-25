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

    private static let stopwords: Set<String> = ["con", "sin", "del", "las", "los", "una", "unos", "para", "plancha", "asado", "asada", "hervido", "hervida"]

    /// El alimento del catálogo que mejor encaja con lo que ha escrito la persona («pollo a la plancha» →
    /// «Pechuga de pollo»). Cuenta las palabras que coinciden; en empate gana el que empieza por la
    /// primera palabra y luego el nombre más corto. nil si ninguna palabra coincide.
    static func bestMatch<T>(for query: String, in items: [T], name: (T) -> String) -> T? {
        let words = fold(query)
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 3 && !stopwords.contains($0) }
        guard !words.isEmpty else { return nil }
        let forms = words.map { word -> [String] in
            var list = [word]
            for (key, target) in aliases where word.hasPrefix(fold(key)) { list.append(fold(target)) }
            // Plural sencillo: «tomates» → «tomate», «fresas» → «fresa».
            if word.hasSuffix("s") { list.append(String(word.dropLast())) }
            return list
        }
        var best: (item: T, score: Int, starts: Bool, length: Int)?
        for item in items {
            let n = fold(name(item))
            let score = forms.filter { $0.contains { n.contains($0) } }.count
            guard score > 0 else { continue }
            let starts = forms[0].contains { n.hasPrefix($0) }
            let candidate = (item: item, score: score, starts: starts, length: n.count)
            if let current = best {
                let better = candidate.score != current.score ? candidate.score > current.score
                    : candidate.starts != current.starts ? candidate.starts
                    : candidate.length < current.length
                if better { best = candidate }
            } else {
                best = candidate
            }
        }
        return best?.item
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_ES"))
            .trimmingCharacters(in: .whitespaces)
    }
}
