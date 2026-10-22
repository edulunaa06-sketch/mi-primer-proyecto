import Foundation
import Observation

/// Claude dentro de la app: estima las kcal de lo que comes y propone comidas más saludables.
///
/// Usa TU clave de la API de Claude (console.anthropic.com), guardada solo en el Llavero del iPhone.
/// No va en el código de la app. Lo que se envía a Anthropic: el texto que escribes, tu objetivo
/// de macros para esa comida y la lista de alimentos del catálogo. Nunca se envían fotos, peso ni datos de Salud.
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
