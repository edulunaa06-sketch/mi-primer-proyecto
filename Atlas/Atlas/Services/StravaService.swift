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

/// Conexión OAuth 2.0 con la API oficial de Strava, directamente desde el iPhone (sin servidor).
///
/// Necesita el ID y el secreto de cliente de una «aplicación de API» que el usuario crea una vez en
/// strava.com/settings/api con su propia cuenta. El secreto se guarda en el Llavero de este iPhone
/// (nunca en el código ni en la copia de seguridad). Es una app de uso personal: solo tú la usas.
@MainActor
@Observable
final class StravaService {
    enum Status: Equatable {
        case notConfigured
        case disconnected
        case connected(expires: Date)
    }

    private static let tokenAccount = "strava.token"
    private static let secretAccount = "strava.clientSecret"
    private static let lastAutoSyncKey = "strava.lastAutoSync"

    private(set) var status: Status = .notConfigured
    private(set) var isWorking = false
    private(set) var lastSync: Date?
    var lastError: String?

    private var pendingState: String?
    private(set) var clientID = UserDefaults.standard.string(forKey: "strava.clientID") ?? ""

    init() { updateStatus() }

    func configure(clientID: String) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(self.clientID, forKey: "strava.clientID")
        updateStatus()
    }

    /// Guarda el ID (en los ajustes) y el secreto (en el Llavero). Devuelve un error legible si no son válidos.
    func saveCredentials(clientID: String, clientSecret: String) -> String? {
        guard StravaAPI.isValidClientID(clientID) else { return "El ID de cliente son solo números (por ejemplo, 123456)." }
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !secret.isEmpty {
            guard StravaAPI.isValidClientSecret(secret) else {
                return "El secreto de cliente no parece correcto: son unos 40 caracteres de números y letras de la a a la f. Pulsa «mostrar» en Strava y cópialo entero."
            }
            do { try KeychainStore.save(Data(secret.utf8), account: Self.secretAccount) } catch { return error.localizedDescription }
        } else if storedSecret() == nil {
            return "Falta el secreto de cliente."
        }
        configure(clientID: clientID)
        return nil
    }

    var hasSecret: Bool { storedSecret() != nil }

    private func storedSecret() -> String? {
        KeychainStore.load(account: Self.secretAccount).flatMap { String(data: $0, encoding: .utf8) }
    }

    var isConfigured: Bool { StravaAPI.isValidClientID(clientID) && storedSecret() != nil }

    private func updateStatus() {
        guard isConfigured else { status = .notConfigured; return }
        if let token = storedToken() {
            status = .connected(expires: token.expirationDate)
        } else {
            status = .disconnected
        }
    }

    /// Importa sola las carreras al abrir la app (como mucho cada 30 minutos) si Strava está conectado.
    func autoSyncIfNeeded(into context: ModelContext) async {
        guard case .connected = status, !isWorking else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastAutoSyncKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 30 * 60 else { return }
        UserDefaults.standard.set(Date(), forKey: Self.lastAutoSyncKey)
        await syncRuns(into: context, pages: 1)
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
            let token = try await exchange(code: code)
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

    /// Borra también el ID y el secreto de este iPhone.
    func forgetCredentials() async {
        await disconnect()
        KeychainStore.delete(account: Self.secretAccount)
        configure(clientID: "")
    }

    // MARK: Importación de carreras

    /// Descarga las últimas actividades y guarda solo las carreras. Devuelve cuántas se importaron.
    @discardableResult
    func syncRuns(into context: ModelContext, pages: Int = 2) async -> Int {
        guard isConfigured else {
            lastError = "Strava no está configurado. Pon el ID y el secreto de cliente en Perfil › Strava."
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

    /// Cada carrera de Strava se guarda una sola vez como entreno de carrera (si ya estaba, se actualiza).
    private func upsert(_ a: StravaAPI.Activity, in context: ModelContext) {
        let id = a.id
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.stravaID == id })
        descriptor.fetchLimit = 1
        let w: Workout
        if let existing = try? context.fetch(descriptor).first {
            w = existing
        } else {
            w = Workout(name: a.name, kind: .run, templateID: nil, startedAt: a.startDate)
            w.stravaID = a.id
            context.insert(w)
        }
        w.name = a.name
        w.startedAt = a.startDate
        w.runMeters = a.distance
        w.runSeconds = a.movingTime
        w.finishedAt = a.startDate.addingTimeInterval(TimeInterval(a.elapsedTime))
        w.note = "Strava"
    }

    // MARK: Tokens

    private func validToken() async throws -> StravaAPI.TokenResponse {
        guard let token = storedToken() else { throw StravaError.notConnected }
        if token.expirationDate.timeIntervalSinceNow > 120 { return token }
        let refreshed = try await exchange(refreshToken: token.refreshToken)
        try store(refreshed)
        return refreshed
    }

    /// Pide los tokens directamente a Strava con el ID y el secreto guardados en el iPhone.
    private func exchange(code: String? = nil, refreshToken: String? = nil) async throws -> StravaAPI.TokenResponse {
        guard let secret = storedSecret(), StravaAPI.isValidClientID(clientID) else { throw StravaError.notConfigured }
        var request = URLRequest(url: StravaAPI.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            StravaAPI.tokenRequestBody(clientID: clientID, clientSecret: secret, code: code, refreshToken: refreshToken))
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 400 || http.statusCode == 401 {
            throw StravaError.badCredentials
        }
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
        case notConfigured, notConnected, unauthorized, rateLimited, badBackendResponse, badCredentials
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Strava no está configurado (falta el ID o el secreto de cliente)."
            case .notConnected: return "No hay ninguna cuenta de Strava conectada."
            case .unauthorized: return "Strava rechazó la autorización. Vuelve a conectar tu cuenta."
            case .rateLimited: return "Se ha superado el límite de peticiones de Strava. Inténtalo más tarde."
            case .badBackendResponse: return "Strava no devolvió un token válido. Inténtalo de nuevo."
            case .badCredentials: return "Strava no acepta el ID o el secreto de cliente. Revisa que los has copiado bien (Perfil › Strava)."
            case .http(let code): return "Error de red (HTTP \(code))."
            }
        }
    }
}
