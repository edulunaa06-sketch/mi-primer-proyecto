import Foundation
import Observation

/// Claude dentro de la app: estima las kcal de lo que comes y propone comidas más saludables.
///
/// Usa TU clave de la API de Claude (console.anthropic.com), guardada solo en el Llavero del iPhone.
/// No va en el código de la app. Lo que se envía a Anthropic: el texto que escribes, tu objetivo
/// de macros para esa comida, la lista de alimentos del catálogo y, solo si usas «Foto del plato», esa foto
/// y su peso. Nunca se envían tus fotos de progreso, tu peso corporal ni datos de Salud.
@MainActor
@Observable
final class ClaudeService {
    private static let keychainService = "NowOrNever.Claude"
    private static let keyAccount = "anthropic.apiKey"

    private(set) var isConfigured = false
    private(set) var isWorking = false

    init() {
        isConfigured = KeychainStore.load(account: Self.keyAccount, service: Self.keychainService) != nil
    }

    func saveKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try KeychainStore.save(Data(trimmed.utf8), account: Self.keyAccount, service: Self.keychainService)
        isConfigured = true
    }

    func deleteKey() {
        KeychainStore.delete(account: Self.keyAccount, service: Self.keychainService)
        isConfigured = false
    }

    /// Desglosa un texto ("150 g de macarrones con tomate") en ingredientes con kcal y macros estimados.
    func estimate(_ description: String) async throws -> ClaudeAPI.Estimate {
        let result = try await send(ClaudeAPI.estimateRequest(description: description), as: ClaudeAPI.Estimate.self)
        return ClaudeAPI.Estimate(items: result.items.filter(\.isPlausible), note: result.note)
    }

    /// Propone comidas con alimentos del catálogo que se acerquen al objetivo de esa comida.
    func suggest(mealLabel: String, target: NutritionValues, context: String,
                 catalog: [ClaudeAPI.CatalogEntry]) async throws -> [ClaudeAPI.SuggestedMeal] {
        let request = ClaudeAPI.suggestRequest(mealLabel: mealLabel, target: target, context: context, catalog: catalog)
        return try await send(request, as: ClaudeAPI.Suggestions.self).meals
    }

    /// Analiza la foto de un plato pesado. Devuelve también el JSON crudo para poder responder a sus preguntas.
    func analyzePhoto(jpeg: Data, totalGrams: Double, comment: String, previous: String? = nil,
                      answers: [ClaudeAPI.Answer] = []) async throws -> (analysis: ClaudeAPI.PhotoAnalysis, raw: String) {
        let request = ClaudeAPI.photoRequest(imageBase64: jpeg.base64EncodedString(), totalGrams: totalGrams, comment: comment,
                                             previous: previous, answers: answers)
        let result = try await send(request, as: ClaudeAPI.PhotoAnalysis.self)
        let items = ClaudeAPI.scaled(result.items.filter(\.isPlausible), toTotal: totalGrams)
        let clean = ClaudeAPI.PhotoAnalysis(items: items, questions: Array(result.questions.prefix(3)), note: result.note)
        let raw = (try? JSONEncoder().encode(result)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return (clean, raw)
    }

    private func send<T: Decodable>(_ body: [String: Any], as type: T.Type) async throws -> T {
        guard let keyData = KeychainStore.load(account: Self.keyAccount, service: Self.keychainService),
              let key = String(data: keyData, encoding: .utf8), !key.isEmpty else {
            throw ClaudeAPI.ClaudeError.missingKey
        }
        isWorking = true
        defer { isWorking = false }
        var request = URLRequest(url: ClaudeAPI.endpoint, timeoutInterval: 180)
        request.httpMethod = "POST"
        for (field, value) in ClaudeAPI.headers(apiKey: key) { request.setValue(value, forHTTPHeaderField: field) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        return try ClaudeAPI.decode(type, status: status, data: data)
    }
}
