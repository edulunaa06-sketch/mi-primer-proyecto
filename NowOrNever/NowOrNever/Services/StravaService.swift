import Foundation
import Observation
import SwiftData
import UIKit

/// Apertura de la app de Strava. Funciona sin OAuth ni credenciales.
@MainActor
enum StravaLauncher {
    enum Outcome {
        case openedRecordLink
        case openedApp
        case notInstalled
    }

    static var isInstalled: Bool {
        guard let url = URL(string: "strava://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    /// Strava no publica un enlace profundo documentado para iniciar una grabación.
    /// Se intenta `strava://record` (no documentado oficialmente) y, si iOS no puede abrirlo,
    /// se abre la app con `strava://`. Si Strava no está instalada se devuelve `.notInstalled`.
    static func openRecording() async -> Outcome {
        guard isInstalled else { return .notInstalled }
        if let record = URL(string: "strava://record"), await UIApplication.shared.open(record) {
            return .openedRecordLink
        }
        if let app = URL(string: "strava://"), await UIApplication.shared.open(app) {
            return .openedApp
        }
        return .notInstalled
    }

    static func openWebsite() {
        UIApplication.shared.open(StravaAPI.websiteURL)
    }

    static func openAppStore() {
        UIApplication.shared.open(StravaAPI.appStoreURL)
    }
}

/// Conexión OAuth 2.0 con la API oficial de Strava.
///
/// El intercambio del código por tokens requiere el `client_secret`, que NUNCA se incluye en la app.
/// Lo realiza un backend propio (ver docs/strava-backend). Sin client_id y backend configurados,
/// la integración queda en estado "pendiente de configuración" y no se importa nada.
@MainActor
@Observable
final class StravaService {
    enum Status: Equatable {
        case notConfigured
        case disconnected
        case connected(expires: Date)
    }

    private static let tokenAccount = "strava.token"

    private(set) var status: Status = .notConfigured
    private(set) var isWorking = false
    private(set) var lastSync: Date?
    var lastError: String?

    private var pendingState: String?
    private var clientID = ""
    private var backendURL: URL?

    func configure(clientID: String, backendURL: String) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = backendURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme == "https", url.host != nil {
            self.backendURL = url
        } else {
            self.backendURL = nil
        }
        updateStatus()
    }

    var isConfigured: Bool { !clientID.isEmpty && backendURL != nil }

    private func updateStatus() {
        guard isConfigured else { status = .notConfigured; return }
        if let token = storedToken() {
            status = .connected(expires: token.expirationDate)
        } else {
            status = .disconnected
        }
    }

    // MARK: OAuth

    /// URL de autorización con un `state` aleatorio que se valida en el callback.
    func makeAuthorizationURL() -> URL? {
        guard isConfigured else { return nil }
        let state = UUID().uuidString
        pendingState = state
        return StravaAPI.authorizeURL(clientID: clientID, state: state)
    }

    func handleCallback(_ url: URL) async {
        guard let expected = pendingState else {
            lastError = "No hay ninguna conexión con Strava en curso."
            return
        }
        pendingState = nil
        do {
            let code = try StravaAPI.parseCallback(url, expectedState: expected)
            isWorking = true
            defer { isWorking = false }
            let token = try await exchange(path: "strava/token", body: ["code": code])
            try store(token)
            lastError = nil
            updateStatus()
        } catch {
            lastError = error.localizedDescription
            updateStatus()
        }
    }

    func disconnect() async {
        if let token = storedToken() {
            var request = URLRequest(url: StravaAPI.deauthorizeURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
        KeychainStore.delete(account: Self.tokenAccount)
        updateStatus()
    }

    // MARK: Importación de carreras

    /// Descarga las últimas actividades y guarda solo las carreras. Devuelve cuántas se importaron.
    @discardableResult
    func syncRuns(into context: ModelContext, pages: Int = 2) async -> Int {
        guard isConfigured else {
            lastError = "Strava no está configurado. Añade el Client ID y la URL de tu backend en Ajustes."
            return 0
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let token = try await validToken()
            var imported = 0
            for page in 1...max(pages, 1) {
                var comps = URLComponents(url: StravaAPI.activitiesURL, resolvingAgainstBaseURL: false)
                comps?.queryItems = [
                    URLQueryItem(name: "per_page", value: "50"),
                    URLQueryItem(name: "page", value: String(page)),
                ]
                guard let url = comps?.url else { break }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.shared.data(for: request)
                try Self.check(response, data: data)
                let activities = try StravaAPI.decodeActivities(data)
                for activity in activities where activity.isRun {
                    upsert(activity, in: context)
                    imported += 1
                }
                if activities.count < 50 { break }
            }
            try context.save()
            lastSync = Date()
            lastError = nil
            return imported
        } catch {
            lastError = error.localizedDescription
            updateStatus()
            return 0
        }
    }

    private func upsert(_ a: StravaAPI.Activity, in context: ModelContext) {
        let id = a.id
        var descriptor = FetchDescriptor<StravaActivityRecord>(predicate: #Predicate { $0.stravaID == id })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.name = a.name
            existing.sportType = a.effectiveType
            existing.startDate = a.startDate
            existing.distanceMeters = a.distance
            existing.movingTimeSeconds = a.movingTime
            existing.elapsedTimeSeconds = a.elapsedTime
            existing.elevationGainMeters = a.totalElevationGain
            existing.importedAt = Date()
        } else {
            context.insert(StravaActivityRecord(
                stravaID: a.id, name: a.name, sportType: a.effectiveType, startDate: a.startDate,
                distanceMeters: a.distance, movingTimeSeconds: a.movingTime,
                elapsedTimeSeconds: a.elapsedTime, elevationGainMeters: a.totalElevationGain
            ))
        }
    }

    // MARK: Tokens

    private func validToken() async throws -> StravaAPI.TokenResponse {
        guard let token = storedToken() else { throw StravaError.notConnected }
        if token.expirationDate.timeIntervalSinceNow > 120 { return token }
        let refreshed = try await exchange(path: "strava/refresh", body: ["refresh_token": token.refreshToken])
        try store(refreshed)
        return refreshed
    }

    private func exchange(path: String, body: [String: String]) async throws -> StravaAPI.TokenResponse {
        guard let base = backendURL else { throw StravaError.notConfigured }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data: data)
        do {
            return try JSONDecoder().decode(StravaAPI.TokenResponse.self, from: data)
        } catch {
            throw StravaError.badBackendResponse
        }
    }

    private func store(_ token: StravaAPI.TokenResponse) throws {
        try KeychainStore.save(JSONEncoder().encode(token), account: Self.tokenAccount)
    }

    private func storedToken() -> StravaAPI.TokenResponse? {
        guard let data = KeychainStore.load(account: Self.tokenAccount) else { return nil }
        return try? JSONDecoder().decode(StravaAPI.TokenResponse.self, from: data)
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw StravaError.http(-1) }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw StravaError.unauthorized
        case 429: throw StravaError.rateLimited
        default: throw StravaError.http(http.statusCode)
        }
    }

    enum StravaError: LocalizedError {
        case notConfigured, notConnected, unauthorized, rateLimited, badBackendResponse
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Strava no está configurado (falta Client ID o backend)."
            case .notConnected: return "No hay ninguna cuenta de Strava conectada."
            case .unauthorized: return "Strava rechazó la autorización. Vuelve a conectar tu cuenta."
            case .rateLimited: return "Se ha superado el límite de peticiones de Strava. Inténtalo más tarde."
            case .badBackendResponse: return "El backend no devolvió un token válido de Strava."
            case .http(let code): return "Error de red (HTTP \(code))."
            }
        }
    }
}
