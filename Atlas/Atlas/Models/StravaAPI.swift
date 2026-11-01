import Foundation

/// Partes puras (sin UI) de la integración con la API oficial de Strava:
/// construcción de URLs OAuth, lectura del callback y decodificación de actividades.
enum StravaAPI {
    static let callbackScheme = "atlas"
    /// El dominio de callback configurado en Strava debe ser "localhost".
    static let redirectURI = "atlas://localhost/strava"
    static let requestedScope = "read,activity:read_all"
    static let appStoreURL = URL(string: "https://apps.apple.com/app/strava-run-bike-hike/id426826309")!
    static let websiteURL = URL(string: "https://www.strava.com")!
    static let activitiesURL = URL(string: "https://www.strava.com/api/v3/athlete/activities")!
    static let deauthorizeURL = URL(string: "https://www.strava.com/oauth/deauthorize")!
    static let tokenURL = URL(string: "https://www.strava.com/oauth/token")!
    static let apiSettingsURL = URL(string: "https://www.strava.com/settings/api")!

    /// Cuerpo de la petición de tokens a Strava (sin servidor intermedio): cambiar el código
    /// de autorización por tokens, o renovar el token con el refresh token.
    static func tokenRequestBody(clientID: String, clientSecret: String, code: String? = nil, refreshToken: String? = nil) -> [String: String] {
        var body = ["client_id": clientID.trimmingCharacters(in: .whitespacesAndNewlines),
                    "client_secret": clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)]
        if let code {
            body["code"] = code
            body["grant_type"] = "authorization_code"
        } else if let refreshToken {
            body["refresh_token"] = refreshToken
            body["grant_type"] = "refresh_token"
        }
        return body
    }

    /// El ID de cliente de Strava es un número; el secreto, 40 caracteres hexadecimales.
    static func isValidClientID(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && t.allSatisfy(\.isNumber)
    }

    static func isValidClientSecret(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count >= 20 && t.allSatisfy(\.isHexDigit)
    }

    /// Tipos de actividad que se consideran carrera.
    static let runSportTypes: Set<String> = ["Run", "TrailRun", "VirtualRun"]

    static func authorizeURL(clientID: String, state: String) -> URL? {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber) else { return nil }
        var comps = URLComponents(string: "https://www.strava.com/oauth/mobile/authorize")
        comps?.queryItems = [
            URLQueryItem(name: "client_id", value: trimmed),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "approval_prompt", value: "auto"),
            URLQueryItem(name: "scope", value: requestedScope),
            URLQueryItem(name: "state", value: state),
        ]
        return comps?.url
    }

    enum CallbackError: LocalizedError, Equatable {
        case denied
        case stateMismatch
        case missingCode
        case insufficientScope(String)
        case notACallback

        var errorDescription: String? {
            switch self {
            case .denied: return "Has cancelado o denegado el acceso en Strava."
            case .stateMismatch: return "La respuesta de Strava no coincide con la solicitud (state). Inténtalo de nuevo."
            case .missingCode: return "Strava no devolvió un código de autorización."
            case .insufficientScope(let s): return "Strava concedió permisos insuficientes (\(s)). Marca la casilla de leer actividades."
            case .notACallback: return "La URL recibida no es un callback de Strava."
            }
        }
    }

    /// Extrae el código de autorización del callback validando state y permisos concedidos.
    static func parseCallback(_ url: URL, expectedState: String) throws -> String {
        guard url.scheme == callbackScheme else { throw CallbackError.notACallback }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if value("error") != nil { throw CallbackError.denied }
        guard value("state") == expectedState else { throw CallbackError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw CallbackError.missingCode }
        let scope = value("scope") ?? ""
        let granted = Set(scope.split(separator: ",").map(String.init))
        guard granted.contains("activity:read") || granted.contains("activity:read_all") else {
            throw CallbackError.insufficientScope(scope.isEmpty ? "ninguno" : scope)
        }
        return code
    }

    /// Respuesta de token de Strava.
    struct TokenResponse: Codable, Equatable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: TimeInterval
        let scope: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresAt = "expires_at"
            case scope
        }

        var expirationDate: Date { Date(timeIntervalSince1970: expiresAt) }
    }

    struct Activity: Decodable, Equatable {
        let id: Int64
        let name: String
        let sportType: String?
        let type: String?
        let startDate: Date
        let distance: Double
        let movingTime: Int
        let elapsedTime: Int
        let totalElevationGain: Double?

        enum CodingKeys: String, CodingKey {
            case id, name, type, distance
            case sportType = "sport_type"
            case startDate = "start_date"
            case movingTime = "moving_time"
            case elapsedTime = "elapsed_time"
            case totalElevationGain = "total_elevation_gain"
        }

        var effectiveType: String { sportType ?? type ?? "" }
        var isRun: Bool { StravaAPI.runSportTypes.contains(effectiveType) }
    }

    static func decodeActivities(_ data: Data) throws -> [Activity] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Activity].self, from: data)
    }
}
