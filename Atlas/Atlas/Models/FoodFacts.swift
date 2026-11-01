import Foundation

/// Lectura de códigos de barras de alimentos contra Open Food Facts.
///
/// Open Food Facts es una base de datos abierta y gratuita de productos de alimentación
/// (https://world.openfoodfacts.org). No hace falta clave. Los datos los suben personas
/// voluntarias y la propia etiqueta del producto puede cambiar, así que la app SIEMPRE enseña
/// lo que ha encontrado y deja corregirlo antes de apuntarlo. Si un producto no está, no se
/// inventa nada: se dice que no está y se puede escribir a mano.
///
/// Este archivo es lógica pura (analizar la respuesta y validar el código); la llamada de red
/// está en `Services/BarcodeLookup.swift`.
enum OpenFoodFacts {
    static let host = "world.openfoodfacts.org"

    /// Producto tal y como lo devuelve la base de datos, con lo que falta señalado.
    struct Product: Equatable {
        let barcode: String
        let name: String
        let brand: String
        /// Por 100 g (o 100 ml) de producto.
        let per100: NutritionValues
        /// Lo que pone el envase: "500 g", "33 cl"…
        let quantity: String
        /// Macros que el producto NO trae (vienen a 0 porque no se saben, no porque valgan 0).
        let missingMacros: [String]

        /// Nombre para enseñar: marca y producto.
        var displayName: String {
            let parts = [brand, name].filter { !$0.isEmpty }
            return parts.isEmpty ? barcode : parts.joined(separator: " · ")
        }

        var hasAllMacros: Bool { missingMacros.isEmpty }
    }

    enum LookupError: Error, Equatable {
        /// El código no existe en la base de datos.
        case notFound(String)
        /// El producto está, pero no tiene las calorías por 100 g.
        case noEnergy(String)
        case badBarcode(String)
        case badResponse
        case network(String)

        var message: String {
            switch self {
            case .notFound(let code):
                return "El código \(code) no está en Open Food Facts. Puedes apuntar el alimento a mano con los datos de la etiqueta."
            case .noEnergy(let name):
                return "«\(name)» está en Open Food Facts, pero sin las calorías por 100 g. Míralas en la etiqueta y apúntalas a mano."
            case .badBarcode(let code):
                return "«\(code)» no parece un código de barras de producto."
            case .badResponse:
                return "Open Food Facts ha contestado algo que no se ha podido leer. Inténtalo de nuevo."
            case .network(let detail):
                return "No se ha podido consultar Open Food Facts: \(detail)"
            }
        }
    }

    /// Dirección de consulta. Se piden solo los campos que usa la app.
    static func url(for barcode: String) -> URL? {
        let fields = "code,product_name,product_name_es,generic_name_es,brands,quantity,nutriments"
        return URL(string: "https://\(host)/api/v2/product/\(barcode).json?fields=\(fields)")
    }

    /// Identificación de la app, que Open Food Facts pide a quien usa su API.
    static func userAgent(version: String) -> String {
        "NowOrNever/\(version) (app personal de entrenamiento y nutrición)"
    }

    // MARK: Validación del código

    /// Solo dígitos y una longitud de código de producto (EAN-8, UPC-A, EAN-13, GTIN-14).
    static func isPlausible(_ barcode: String) -> Bool {
        let digits = barcode.trimmingCharacters(in: .whitespaces)
        guard digits.allSatisfy(\.isNumber), !digits.isEmpty else { return false }
        return [8, 12, 13, 14].contains(digits.count)
    }

    /// Dígito de control del código (EAN/UPC): pesos 3 y 1 alternos empezando por la derecha.
    /// Sirve para no consultar códigos mal leídos.
    static func hasValidCheckDigit(_ barcode: String) -> Bool {
        guard isPlausible(barcode) else { return false }
        let digits = barcode.compactMap { $0.wholeNumberValue }
        guard digits.count == barcode.count, let check = digits.last else { return false }
        let body = digits.dropLast().reversed()
        var sum = 0
        for (index, digit) in body.enumerated() {
            sum += digit * (index % 2 == 0 ? 3 : 1)
        }
        return (10 - sum % 10) % 10 == check
    }

    // MARK: Lectura de la respuesta

    /// Analiza el JSON de Open Food Facts. No rellena huecos: lo que no viene, no viene.
    static func parse(_ data: Data, barcode: String) throws -> Product {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw LookupError.badResponse
        }
        // status: 1 encontrado, 0 no encontrado.
        if let status = number(root["status"]), status == 0 { throw LookupError.notFound(barcode) }
        guard let product = root["product"] as? [String: Any] else { throw LookupError.notFound(barcode) }

        let name = firstText(product, ["product_name_es", "product_name", "generic_name_es"])
        let brand = firstText(product, ["brands"]).split(separator: ",").first.map {
            $0.trimmingCharacters(in: .whitespaces)
        } ?? ""
        let quantity = firstText(product, ["quantity"])
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]

        guard let kcal = energyPer100(nutriments) else {
            throw LookupError.noEnergy(name.isEmpty ? barcode : name)
        }
        var missing: [String] = []
        func macro(_ keys: [String], _ label: String) -> Double {
            guard let value = firstNumber(nutriments, keys) else {
                missing.append(label)
                return 0
            }
            return value
        }
        let per100 = NutritionValues(
            kcal: kcal,
            protein: macro(["proteins_100g"], "proteínas"),
            carbs: macro(["carbohydrates_100g"], "carbohidratos"),
            fat: macro(["fat_100g"], "grasas")
        )
        return Product(barcode: barcode, name: name, brand: brand, per100: per100,
                       quantity: quantity, missingMacros: missing)
    }

    /// Kilocalorías por 100 g. Si solo viene la energía en kJ, se convierte (1 kcal = 4,184 kJ).
    static func energyPer100(_ nutriments: [String: Any]) -> Double? {
        if let kcal = firstNumber(nutriments, ["energy-kcal_100g"]), kcal > 0 { return kcal }
        if let kj = firstNumber(nutriments, ["energy-kj_100g", "energy_100g"]), kj > 0 { return kj / 4.184 }
        return nil
    }

    private static func firstText(_ dict: [String: Any], _ keys: [String]) -> String {
        for key in keys {
            if let text = dict[key] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return ""
    }

    private static func firstNumber(_ dict: [String: Any], _ keys: [String]) -> Double? {
        for key in keys {
            if let value = number(dict[key]) { return value }
        }
        return nil
    }

    /// Open Food Facts devuelve a veces los números como texto.
    private static func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }
}
