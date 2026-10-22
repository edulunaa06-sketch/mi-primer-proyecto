import Foundation

/// Peticiones a la API de Claude (Messages API por HTTP: Swift no tiene SDK oficial).
/// Lógica pura: construye el cuerpo de la petición y lee la respuesta. La llamada de red está en `ClaudeService`.
///
/// - Modelo: `claude-opus-5-5`, con salida estructurada (JSON Schema) para que la respuesta se pueda leer
///   sin adivinar el formato.
/// - `fallbacks: "default"`: si los filtros de seguridad rechazan la petición, la API la reintenta con
///   el modelo alternativo recomendado.
/// - Las sugerencias de comidas solo pueden usar alimentos del catálogo (por su id). Los gramos los
///   propone Claude, pero las kcal y los macros se calculan en la app con los valores del catálogo.
enum ClaudeAPI {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let model = "claude-opus-5-5"
    static let apiVersion = "2026-10-21"
    static let fallbackBeta = "server-side-fallback-2026-07-01"

    // MARK: Estimar lo que como

    struct EstimatedItem: Codable, Equatable {
        let name: String
        let grams: Double
        let kcalPer100g: Double
        let proteinPer100g: Double
        let carbsPer100g: Double
        let fatPer100g: Double

        enum CodingKeys: String, CodingKey {
            case name, grams
            case kcalPer100g = "kcal_per_100g"
            case proteinPer100g = "protein_per_100g"
            case carbsPer100g = "carbs_per_100g"
            case fatPer100g = "fat_per_100g"
        }

        var per100: NutritionValues {
            NutritionValues(kcal: kcalPer100g, protein: proteinPer100g, carbs: carbsPer100g, fat: fatPer100g)
        }
        var values: NutritionValues { per100.scaled(toGrams: grams) }

        /// Descarta cifras imposibles (negativas, gramos absurdos o más de 900 kcal/100 g).
        var isPlausible: Bool {
            grams > 0 && grams <= 3000 && kcalPer100g >= 0 && kcalPer100g <= 900
                && proteinPer100g >= 0 && carbsPer100g >= 0 && fatPer100g >= 0
                && proteinPer100g + carbsPer100g + fatPer100g <= 101
        }
    }

    struct Estimate: Codable, Equatable {
        let items: [EstimatedItem]
        let note: String
    }

    static let estimateSystem = """
    Eres el asistente de nutrición de la app Now or Never. El usuario describe en español lo que come o va a comer.
    Desglósalo en ingredientes con su peso estimado en gramos y sus valores por 100 g (kcal, proteínas, carbohidratos y grasas)
    según tablas de composición de referencia (BEDCA, USDA).
    - Si el usuario indica gramos, úsalos tal cual. Si no, estima una ración normal y dilo en la nota.
    - Si el alimento está cocinado (por ejemplo, pasta cocida), usa los valores del alimento cocinado; si dice "en seco" o "en crudo", los del alimento crudo o seco.
    - Incluye el aceite, las salsas o el queso añadidos si se mencionan o son habituales en ese plato, y dilo en la nota.
    - En la nota (máximo 2 frases, en español) explica las suposiciones. Son estimaciones, no valores exactos.
    """

    static let estimateSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["items", "note"],
        "properties": [
            "items": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["name", "grams", "kcal_per_100g", "protein_per_100g", "carbs_per_100g", "fat_per_100g"],
                    "properties": [
                        "name": ["type": "string"],
                        "grams": ["type": "number"],
                        "kcal_per_100g": ["type": "number"],
                        "protein_per_100g": ["type": "number"],
                        "carbs_per_100g": ["type": "number"],
                        "fat_per_100g": ["type": "number"],
                    ],
                ],
            ],
            "note": ["type": "string"],
        ],
    ]

    static func estimateRequest(description: String) -> [String: Any] {
        body(system: estimateSystem, user: description, schema: estimateSchema, effort: "low")
    }

    // MARK: Foto del plato

    /// Resultado de analizar la foto de un plato: ingredientes con gramos y valores por 100 g,
    /// y preguntas cuando Claude no está seguro de algún alimento (p. ej. «¿es queso cottage o requesón?»).
    struct PhotoAnalysis: Codable, Equatable {
        let items: [EstimatedItem]
        let questions: [String]
        let note: String
    }

    /// Una pregunta de Claude y la respuesta del usuario.
    struct Answer: Equatable {
        let question: String
        let answer: String
    }

    static let photoSystem = """
    Eres el asistente de nutrición de la app Now or Never. Recibes la foto de un plato y el peso total de la comida en gramos
    (pesada en báscula, sin el plato). Identifica cada alimento visible (por ejemplo: pollo a la plancha, boniato asado,
    queso cottage, arroz, aceite) y reparte el peso total entre ellos según lo que ves.
    - La suma de los gramos de todos los ingredientes debe ser igual al peso total indicado.
    - Usa valores por 100 g del alimento tal y como está en el plato (cocinado si está cocinado), según tablas de referencia (BEDCA, USDA).
    - Si hay aceite o salsa visibles o probables, inclúyelos como ingrediente con una cantidad prudente y dilo en la nota.
    - Si dudas de qué es un alimento, de cómo está cocinado o de una cantidad importante, haz una pregunta corta y concreta
      en "questions" (máximo 3) y da igualmente tu mejor estimación. Si no tienes dudas, deja "questions" vacío.
    - Si el usuario ya ha respondido a tus preguntas, usa sus respuestas y no vuelvas a preguntar lo mismo.
    - Si la foto no muestra comida, devuelve "items" vacío y explícalo en la nota.
    - Nota en español, máximo 2 frases. Son estimaciones, no valores exactos.
    """

    static let photoSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["items", "questions", "note"],
        "properties": [
            "items": (estimateSchema["properties"] as! [String: Any])["items"]!,
            "questions": ["type": "array", "items": ["type": "string"]],
            "note": ["type": "string"],
        ],
    ]

    /// Primera petición con la foto; si ya hubo preguntas, se añade la respuesta anterior y las respuestas del usuario.
    static func photoRequest(imageBase64: String, mediaType: String = "image/jpeg", totalGrams: Double, comment: String,
                             previous: String? = nil, answers: [Answer] = []) -> [String: Any] {
        let intro = """
        Peso total de la comida (sin el plato): \(Int(totalGrams.rounded())) g.
        \(comment.isEmpty ? "" : "Comentario del usuario: \(comment)")
        """
        var messages: [[String: Any]] = [[
            "role": "user",
            "content": [
                ["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": imageBase64]],
                ["type": "text", "text": intro],
            ],
        ]]
        if let previous, !answers.isEmpty {
            messages.append(["role": "assistant", "content": previous])
            let text = answers.map { "- \($0.question)\n  Respuesta: \($0.answer)" }.joined(separator: "\n")
            messages.append(["role": "user", "content": "Mis respuestas:\n\(text)\nRecalcula el plato con esta información."])
        }
        var request = body(system: photoSystem, user: "", schema: photoSchema, effort: "medium")
        request["messages"] = messages
        return request
    }

    /// Ajusta los gramos para que sumen exactamente el peso de la báscula (Claude reparte «a ojo»).
    static func scaled(_ items: [EstimatedItem], toTotal total: Double) -> [EstimatedItem] {
        let sum = items.reduce(0) { $0 + $1.grams }
        guard sum > 0, total > 0, abs(sum - total) >= 1 else { return items }
        let factor = total / sum
        return items.map {
            EstimatedItem(name: $0.name, grams: ($0.grams * factor).rounded(), kcalPer100g: $0.kcalPer100g,
                          proteinPer100g: $0.proteinPer100g, carbsPer100g: $0.carbsPer100g, fatPer100g: $0.fatPer100g)
        }
    }

    // MARK: Proponer comidas más saludables

    struct CatalogEntry: Equatable {
        let id: String
        let name: String
        let basis: String
        let per100: NutritionValues
    }

    struct SuggestedItem: Codable, Equatable {
        let foodId: String
        let grams: Double
        enum CodingKeys: String, CodingKey {
            case foodId = "food_id"
            case grams
        }
    }

    struct SuggestedMeal: Codable, Equatable {
        let name: String
        let why: String
        let items: [SuggestedItem]
    }

    struct Suggestions: Codable, Equatable {
        let meals: [SuggestedMeal]
    }

    static let suggestSystem = """
    Eres el asistente de nutrición de la app Now or Never. Propón comidas sencillas, saludables y realistas en España
    que se acerquen al objetivo de kcal y macros indicado para esa comida.
    - Usa EXCLUSIVAMENTE alimentos del catálogo, por su id exacto. Nunca inventes ids.
    - Indica los gramos tal y como se pesan en la báscula, según el estado que marca el catálogo (en seco, en crudo, escurrido...), en múltiplos de 5 g (aceite en múltiplos de 1 g).
    - Entre 2 y 6 ingredientes por comida. Prioriza proteína magra, verdura, fruta, legumbre e hidratos integrales.
    - Si el usuario ha comido o quiere comer algo concreto, propón alternativas más saludables y parecidas en sabor o tipo de plato.
    - "why": una frase en español explicando por qué es mejor o cómo encaja con los macros.
    """

    static let suggestSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": ["meals"],
        "properties": [
            "meals": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["name", "why", "items"],
                    "properties": [
                        "name": ["type": "string"],
                        "why": ["type": "string"],
                        "items": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "additionalProperties": false,
                                "required": ["food_id", "grams"],
                                "properties": [
                                    "food_id": ["type": "string"],
                                    "grams": ["type": "number"],
                                ],
                            ],
                        ],
                    ],
                ],
            ],
        ],
    ]

    static func catalogText(_ catalog: [CatalogEntry]) -> String {
        catalog.map { e in
            let v = e.per100
            return "\(e.id) | \(e.name) | \(e.basis) | \(Int(v.kcal.rounded())) kcal, P \(fmt(v.protein)), C \(fmt(v.carbs)), G \(fmt(v.fat))"
        }.joined(separator: "\n")
    }

    static func suggestRequest(mealLabel: String, target: NutritionValues, context: String, catalog: [CatalogEntry]) -> [String: Any] {
        let user = """
        Comida: \(mealLabel)
        Objetivo aproximado para esta comida: \(Int(target.kcal.rounded())) kcal, proteínas \(fmt(target.protein)) g, carbohidratos \(fmt(target.carbs)) g, grasas \(fmt(target.fat)) g.
        \(context.isEmpty ? "" : "Contexto del usuario: \(context)\n")
        Propón 3 comidas distintas.

        Catálogo (id | nombre | cómo se pesa | valores por 100 g):
        \(catalogText(catalog))
        """
        return body(system: suggestSystem, user: user, schema: suggestSchema, effort: "medium")
    }

    /// Valida una sugerencia contra el catálogo: descarta ids desconocidos y gramos no razonables.
    static func resolve(_ meal: SuggestedMeal, catalog: [CatalogEntry]) -> [(entry: CatalogEntry, grams: Double)] {
        let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        return meal.items.compactMap { item in
            guard let entry = byID[item.foodId], item.grams > 0, item.grams <= 1500 else { return nil }
            return (entry, item.grams.rounded())
        }
    }

    // MARK: Petición y respuesta

    static func body(system: String, user: String, schema: [String: Any], effort: String) -> [String: Any] {
        [
            "model": model,
            "max_tokens": 16000,
            "fallbacks": "default",
            "system": system,
            "output_config": [
                "effort": effort,
                "format": ["type": "json_schema", "schema": schema],
            ],
            "messages": [["role": "user", "content": user]],
        ]
    }

    static func headers(apiKey: String) -> [String: String] {
        [
            "content-type": "application/json",
            "x-api-key": apiKey,
            "anthropic-version": apiVersion,
            "anthropic-beta": fallbackBeta,
        ]
    }

    struct Response: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    struct APIErrorBody: Decodable {
        struct Detail: Decodable {
            let type: String
            let message: String
        }
        let error: Detail
    }

    enum ClaudeError: LocalizedError, Equatable {
        case missingKey
        case invalidKey
        case rateLimited
        case overloaded
        case refused
        case truncated
        case badResponse
        case api(String)
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .missingKey: return "Añade tu clave de la API de Claude en Ajustes › Claude (IA)."
            case .invalidKey: return "La clave de la API de Claude no es válida. Revísala en Ajustes."
            case .rateLimited: return "Has hecho muchas peticiones seguidas. Espera un momento y vuelve a intentarlo."
            case .overloaded: return "Claude está saturado ahora mismo. Inténtalo de nuevo en unos segundos."
            case .refused: return "Claude no ha podido responder a esta petición. Prueba a describirla de otra forma."
            case .truncated: return "La respuesta de Claude llegó incompleta. Inténtalo de nuevo."
            case .badResponse: return "No se pudo leer la respuesta de Claude."
            case .api(let message): return "Error de la API de Claude: \(message)"
            case .http(let code): return "Error de red (HTTP \(code))."
            }
        }
    }

    /// Lee la respuesta (cuerpo y código HTTP) y decodifica el JSON estructurado de la respuesta.
    static func decode<T: Decodable>(_ type: T.Type, status: Int, data: Data) throws -> T {
        switch status {
        case 200: break
        case 401, 403: throw ClaudeError.invalidKey
        case 429: throw ClaudeError.rateLimited
        case 529: throw ClaudeError.overloaded
        default:
            if let body = try? JSONDecoder().decode(APIErrorBody.self, from: data) { throw ClaudeError.api(body.error.message) }
            throw ClaudeError.http(status)
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw ClaudeError.badResponse }
        if response.stopReason == "refusal" { throw ClaudeError.refused }
        if response.stopReason == "max_tokens" { throw ClaudeError.truncated }
        guard let text = response.content.last(where: { $0.type == "text" })?.text,
              let json = text.data(using: .utf8),
              let value = try? JSONDecoder().decode(T.self, from: json) else { throw ClaudeError.badResponse }
        return value
    }

    private static func fmt(_ v: Double) -> String { String(format: "%.1f", v) }
}
