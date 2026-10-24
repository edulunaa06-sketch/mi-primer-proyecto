import Foundation

// Lo que añadió la «reunión de expertos» (nutricionista, culturista, atleta híbrido y entrenador).
// Lógica pura, probada en AtlasTests/ExpertLogicTests.

// MARK: - Código de barras (Open Food Facts)

/// Lee la respuesta de Open Food Facts (base de datos abierta y gratuita de productos del súper).
enum OpenFoodFacts {
    static func url(barcode: String) -> URL? {
        let code = barcode.filter(\.isNumber)
        guard (8...14).contains(code.count) else { return nil }
        return URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,product_name_es,brands,nutriments")
    }

    struct Product: Equatable {
        let name: String
        let per100: NutritionValues
    }

    /// nil si el producto no existe o no tiene calorías por 100 g.
    static func parse(_ data: Data) -> Product? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["status"] as? Int ?? 1) == 1,
              let product = root["product"] as? [String: Any],
              let n = product["nutriments"] as? [String: Any] else { return nil }
        func num(_ key: String) -> Double? {
            if let d = n[key] as? Double { return d }
            if let i = n[key] as? Int { return Double(i) }
            if let s = n[key] as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
            return nil
        }
        guard let kcal = num("energy-kcal_100g") ?? num("energy_100g").map({ $0 / 4.184 }), kcal >= 0 else { return nil }
        let name = [product["product_name_es"], product["product_name"]].compactMap { $0 as? String }.first { !$0.isEmpty } ?? "Producto"
        let brand = (product["brands"] as? String)?.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) }
        let full = brand.map { name.localizedCaseInsensitiveContains($0) ? name : "\(name) (\($0))" } ?? name
        return Product(name: full, per100: NutritionValues(kcal: kcal.rounded(), protein: num("proteins_100g") ?? 0,
                                                           carbs: num("carbohydrates_100g") ?? 0, fat: num("fat_100g") ?? 0))
    }
}

// MARK: - Recuperación del día

/// Chequeo de 10 segundos: horas de sueño, energía (1–5) y agujetas (1–5) → preparación 0–100 y consejo.
enum Readiness {
    static func score(sleepHours: Double, energy: Int, soreness: Int) -> Int {
        let sleep = min(max((sleepHours - 4) / 4, 0), 1)          // 4 h → 0, 8 h o más → 1
        let e = Double(min(max(energy, 1), 5) - 1) / 4
        let s = 1 - Double(min(max(soreness, 1), 5) - 1) / 4
        return Int(((sleep * 0.45 + e * 0.30 + s * 0.25) * 100).rounded())
    }

    static func advice(_ score: Int) -> (title: String, text: String) {
        switch score {
        case 75...: return ("Listo para apretar", "Buen día para buscar un récord o subir el peso.")
        case 50..<75: return ("Entrena normal", "Haz tu sesión como está planificada, sin forzar series al fallo.")
        case 30..<50: return ("Día suave", "Mantén los pesos y quita una serie por ejercicio, o cambia la carrera por un rodaje fácil.")
        default: return ("Prioriza recuperar", "Hoy mejor descanso activo: paseo, movilidad y dormir pronto.")
        }
    }
}

// MARK: - Carga de carrera (regla del 10 %)

enum RunningLoad {
    struct Result: Equatable {
        let thisWeekKm: Double
        let lastWeekKm: Double
        let fourWeekAverageKm: Double
        /// Máximo recomendado para la semana que viene.
        let nextWeekMaxKm: Double
        /// Esta semana vas más de un 30 % por encima de tu media: riesgo de lesión.
        let isSpike: Bool
    }

    /// `runs`: carreras (fecha y metros). Las semanas empiezan en lunes.
    static func compute(_ runs: [(date: Date, meters: Double)], now: Date = Date()) -> Result {
        let cal = DateUtils.calendar
        let thisWeek = DateUtils.startOfWeek(now)
        func km(weeksAgo: Int) -> Double {
            let start = cal.date(byAdding: .day, value: -7 * weeksAgo, to: thisWeek) ?? thisWeek
            let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
            return runs.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.meters } / 1000
        }
        let current = km(weeksAgo: 0)
        let previous = (1...4).map { km(weeksAgo: $0) }
        let avg = previous.reduce(0, +) / 4
        let base = max(previous[0], avg)
        let nextMax = max(base * 1.1, 5)
        return Result(thisWeekKm: current, lastWeekKm: previous[0], fourWeekAverageKm: avg,
                      nextWeekMaxKm: (nextMax * 10).rounded() / 10, isSpike: avg > 0 && current > avg * 1.3)
    }
}

// MARK: - Proteína por comida

enum ProteinPlan {
    /// Reparto en 4 comidas, con un mínimo útil de 25 g por toma (lo que mejor aprovecha el músculo).
    static func perMeal(dailyProtein: Double, meals: Int = 4) -> Int {
        guard dailyProtein > 0, meals > 0 else { return 0 }
        return max(25, Int((dailyProtein / Double(meals) / 5).rounded()) * 5)
    }
}
