import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Cuentas y amigos sobre Supabase (Auth + base de datos con reglas de acceso por fila).
/// Lógica pura: construye las peticiones y lee las respuestas; la red está en `SocialService`.
/// El esquema y las reglas de privacidad están en `docs/supabase/schema.sql`.
enum SocialAPI {
    // MARK: Configuración

    struct Config: Equatable {
        let baseURL: URL
        let apiKey: String

        /// Acepta la URL del proyecto (https://xxxx.supabase.co) y su clave pública (anon o publishable).
        init?(url: String, apiKey: String) {
            let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = URL(string: trimmedURL), parsed.scheme == "https", parsed.host?.isEmpty == false,
                  key.count >= 20, !key.hasPrefix("sb_secret_") else { return nil }
            baseURL = parsed
            self.apiKey = key
        }

        /// Sin validar (pruebas contra un servidor local).
        init(unchecked baseURL: URL, apiKey: String) {
            self.baseURL = baseURL
            self.apiKey = apiKey
        }
    }

    // MARK: Modelos

    struct Session: Codable, Equatable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
        let userID: String
        let email: String?

        func isExpired(now: Date = Date()) -> Bool { now.addingTimeInterval(60) >= expiresAt }
    }

    struct Profile: Codable, Hashable, Identifiable {
        let id: String
        let username: String
        let displayName: String
        var avatarPath: String? = nil

        enum CodingKeys: String, CodingKey {
            case id, username
            case displayName = "display_name"
            case avatarPath = "avatar_path"
        }

        var shownName: String { displayName.isEmpty ? "@\(username)" : displayName }
    }

    struct Follow: Codable, Hashable {
        let follower: String
        let followee: String
        let status: String
        var isAccepted: Bool { status == "accepted" }
    }

    /// Lo que se comparte de un día. Sin fotos, sin peso corporal y sin datos de Salud salvo los pasos.
    struct DaySummary: Codable, Equatable {
        struct SessionItem: Codable, Equatable {
            let title: String
            let kind: String
            let completed: Bool
            let exercisesDone: Int
            let exercisesTotal: Int
            /// Mejores series, p. ej. «Press banca · 60 kg × 8».
            let highlights: [String]
        }

        struct MealItem: Codable, Equatable {
            let type: String
            let name: String
            let kcal: Double
            let eaten: Bool
        }

        let day: String
        let sessions: [SessionItem]
        let meals: [MealItem]
        let kcalEaten: Double
        let proteinEaten: Double
        let kcalTarget: Double
        let steps: Int?
        let stepGoal: Int

        var trainingPlanned: Int { sessions.count }
        var trainingDone: Int { sessions.filter(\.completed).count }
        var mealsEaten: Int { meals.filter(\.eaten).count }
    }

    struct DayRow: Codable, Equatable {
        let userID: String
        let day: String
        let data: DaySummary

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case day, data
        }
    }

    // MARK: Errores

    enum SocialError: LocalizedError, Equatable {
        case notConfigured
        case notSignedIn
        case emailNotConfirmed
        case confirmEmail
        case invalidCredentials
        case weakPassword
        case emailTaken
        case usernameTaken
        case invalidUsername
        case userNotFound
        case anonymousDisabled
        case invalidPhone
        case phoneTaken
        case contactsDenied
        case badResponse
        case server(String)
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Falta conectar el servidor de amigos (Ajustes › Amigos)."
            case .notSignedIn: return "Inicia sesión para ver a tus amigos."
            case .emailNotConfirmed: return "Confirma tu correo con el enlace que te ha llegado y vuelve a iniciar sesión."
            case .confirmEmail: return "Cuenta creada. Abre el enlace del correo que te ha llegado y luego inicia sesión."
            case .invalidCredentials: return "Correo o contraseña incorrectos."
            case .weakPassword: return "La contraseña debe tener al menos 6 caracteres."
            case .emailTaken: return "Ya existe una cuenta con ese correo. Inicia sesión."
            case .usernameTaken: return "Ese nombre de usuario ya está cogido. Prueba otro."
            case .invalidUsername: return "El usuario debe tener de 3 a 20 caracteres: letras minúsculas, números, punto o guion bajo."
            case .userNotFound: return "No hay nadie con ese usuario."
            case .anonymousDisabled: return "El servidor no deja entrar solo con nombre: en Supabase activa Authentication › Sign In / Providers › «Allow anonymous sign-ins»."
            case .invalidPhone: return "Ese número no parece válido. Escríbelo con prefijo si no es de España (p. ej. +52…)."
            case .phoneTaken: return "Ese número ya está en otra cuenta."
            case .contactsDenied: return "Sin permiso para ver tus contactos. Actívalo en Ajustes › Now or Never › Contactos."
            case .badResponse: return "No se pudo leer la respuesta del servidor."
            case .server(let message): return "Error del servidor: \(message)"
            case .http(let code): return "Error de red (HTTP \(code))."
            }
        }
    }

    /// «@Edu.Luna » → «edu.luna». Devuelve nil si no es válido.
    static func normalizeUsername(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.hasPrefix("@") { name.removeFirst() }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_.")
        guard (3...20).contains(name.count), name.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return name
    }

    /// «Edu Luna» → «eduluna» (sugerencia de @usuario a partir del nombre).
    static func suggestUsername(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES")).lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_.")
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter { allowed.contains($0) }).prefix(20))
    }

    // MARK: Teléfono

    /// «+34 600 11 12 22», «0034600111222» y «600111222» → «34600111222». Sin prefijo se asume España.
    /// nil si no queda un número de 8 a 15 cifras.
    static func normalizePhone(_ raw: String, defaultCountryCode: String = "34") -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var digits = String(trimmed.filter { $0.isASCII && $0.isNumber })
        if trimmed.hasPrefix("+") {
            // Ya trae el prefijo del país.
        } else if digits.hasPrefix("00") {
            digits.removeFirst(2)
        } else if digits.count == 9 {
            digits = defaultCountryCode + digits
        }
        return (8...15).contains(digits.count) ? digits : nil
    }

    /// Texto del que se calcula el resumen SHA-256 que se guarda en el servidor (nunca el número).
    static func phoneHashInput(_ normalized: String) -> Data { Data("nowornever:\(normalized)".utf8) }

    static func setMyPhone(_ config: Config, session: Session, hash: String?) -> URLRequest {
        let body = try? JSONSerialization.data(withJSONObject: ["hash": hash as Any? ?? NSNull()])
        return rest(config, accessToken: session.accessToken, method: "POST", table: "rpc/set_my_phone", body: body)
    }

    static func findByPhones(_ config: Config, session: Session, hashes: [String]) -> URLRequest {
        let body = try? JSONSerialization.data(withJSONObject: ["hashes": Array(hashes.prefix(2000))])
        return rest(config, accessToken: session.accessToken, method: "POST", table: "rpc/find_by_phones", body: body)
    }

    // MARK: Peticiones de cuenta (Supabase Auth)

    static func signUp(_ config: Config, email: String, password: String) -> URLRequest {
        auth(config, path: "auth/v1/signup", query: [], body: ["email": email, "password": password])
    }

    /// Cuenta sin correo ni contraseña: solo se elige un nombre. Requiere «Allow anonymous sign-ins» en Supabase.
    /// La sesión se guarda en el Llavero del iPhone.
    static func signUpAnonymously(_ config: Config) -> URLRequest {
        auth(config, path: "auth/v1/signup", query: [], body: [:])
    }

    static func signIn(_ config: Config, email: String, password: String) -> URLRequest {
        auth(config, path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")],
             body: ["email": email, "password": password])
    }

    static func refresh(_ config: Config, refreshToken: String) -> URLRequest {
        auth(config, path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
             body: ["refresh_token": refreshToken])
    }

    static func signOut(_ config: Config, accessToken: String) -> URLRequest {
        var request = auth(config, path: "auth/v1/logout", query: [], body: [:])
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func auth(_ config: Config, path: String, query: [URLQueryItem], body: [String: String]) -> URLRequest {
        var request = URLRequest(url: url(config, path: path, query: query), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    private struct TokenResponse: Decodable {
        struct User: Decodable {
            let id: String
            let email: String?
        }
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Double?
        let user: User?
        // Registro con confirmación por correo: devuelve el usuario sin sesión.
        let id: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case user, id
        }
    }

    /// Lee la respuesta de registro o inicio de sesión. nil = cuenta creada pero falta confirmar el correo.
    static func decodeSession(status: Int, data: Data, now: Date = Date()) throws -> Session? {
        guard (200..<300).contains(status) else { throw authError(status: status, data: data) }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data) else { throw SocialError.badResponse }
        guard let access = token.accessToken, let refresh = token.refreshToken, let user = token.user else {
            if token.id != nil || token.user != nil { return nil }
            throw SocialError.badResponse
        }
        return Session(accessToken: access, refreshToken: refresh, expiresAt: now.addingTimeInterval(token.expiresIn ?? 3600),
                       userID: user.id, email: user.email)
    }

    private struct AuthErrorBody: Decodable {
        let errorCode: String?
        let msg: String?
        let error: String?
        let errorDescription: String?
        let message: String?

        enum CodingKeys: String, CodingKey {
            case errorCode = "error_code"
            case msg, error, message
            case errorDescription = "error_description"
        }
    }

    static func authError(status: Int, data: Data) -> SocialError {
        let body = try? JSONDecoder().decode(AuthErrorBody.self, from: data)
        let code = body?.errorCode ?? body?.error ?? ""
        let text = body?.msg ?? body?.errorDescription ?? body?.message ?? ""
        switch code {
        case "invalid_credentials", "invalid_grant": return .invalidCredentials
        case "email_not_confirmed": return .emailNotConfirmed
        case "weak_password": return .weakPassword
        case "user_already_exists", "email_exists": return .emailTaken
        case "anonymous_provider_disabled": return .anonymousDisabled
        default:
            if text.localizedCaseInsensitiveContains("not confirmed") { return .emailNotConfirmed }
            if text.localizedCaseInsensitiveContains("invalid login") { return .invalidCredentials }
            if text.localizedCaseInsensitiveContains("already registered") { return .emailTaken }
            if text.localizedCaseInsensitiveContains("password") && status == 422 { return .weakPassword }
            return text.isEmpty ? .http(status) : .server(text)
        }
    }

    // MARK: Peticiones de datos (base de datos)

    static func rest(_ config: Config, accessToken: String, method: String, table: String,
                     query: [URLQueryItem] = [], body: Data? = nil, prefer: String? = nil) -> URLRequest {
        var request = URLRequest(url: url(config, path: "rest/v1/\(table)", query: query), timeoutInterval: 30)
        request.httpMethod = method
        request.setValue(config.apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        request.httpBody = body
        return request
    }

    static func createProfile(_ config: Config, session: Session, username: String, displayName: String) -> URLRequest {
        let body = try? JSONSerialization.data(withJSONObject: [
            "id": session.userID, "username": username, "display_name": String(displayName.prefix(40)),
        ])
        return rest(config, accessToken: session.accessToken, method: "POST", table: "profiles",
                    query: [URLQueryItem(name: "on_conflict", value: "id")], body: body,
                    prefer: "resolution=merge-duplicates,return=representation")
    }

    static func profiles(_ config: Config, session: Session, ids: [String]) -> URLRequest {
        rest(config, accessToken: session.accessToken, method: "GET", table: "profiles", query: [
            URLQueryItem(name: "select", value: "id,username,display_name,avatar_path"),
            URLQueryItem(name: "id", value: "in.(\(ids.joined(separator: ",")))"),
        ])
    }

    static func findProfile(_ config: Config, session: Session, username: String) -> URLRequest {
        rest(config, accessToken: session.accessToken, method: "GET", table: "profiles", query: [
            URLQueryItem(name: "select", value: "id,username,display_name,avatar_path"),
            URLQueryItem(name: "username", value: "eq.\(username)"),
        ])
    }

    /// Busca por @usuario o por nombre (contiene, sin distinguir mayúsculas). Máximo 20 resultados.
    static func searchProfiles(_ config: Config, session: Session, query: String) -> URLRequest? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._"))
        var text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("@") { text.removeFirst() }
        text = String(text.unicodeScalars.filter(allowed.contains).prefix(40)).trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { return nil }
        let pattern = "*\(text)*"
        return rest(config, accessToken: session.accessToken, method: "GET", table: "profiles", query: [
            URLQueryItem(name: "select", value: "id,username,display_name,avatar_path"),
            URLQueryItem(name: "or", value: "(username.ilike.\(pattern),display_name.ilike.\(pattern))"),
            URLQueryItem(name: "id", value: "neq.\(session.userID)"),
            URLQueryItem(name: "order", value: "username"),
            URLQueryItem(name: "limit", value: "20"),
        ])
    }

    static func follows(_ config: Config, session: Session) -> URLRequest {
        rest(config, accessToken: session.accessToken, method: "GET", table: "follows", query: [
            URLQueryItem(name: "select", value: "follower,followee,status"),
            URLQueryItem(name: "or", value: "(follower.eq.\(session.userID),followee.eq.\(session.userID))"),
        ])
    }

    static func requestFollow(_ config: Config, session: Session, userID: String) -> URLRequest {
        let body = try? JSONSerialization.data(withJSONObject: ["follower": session.userID, "followee": userID])
        return rest(config, accessToken: session.accessToken, method: "POST", table: "follows", body: body,
                    prefer: "resolution=ignore-duplicates")
    }

    static func accept(_ config: Config, session: Session, followerID: String) -> URLRequest {
        rest(config, accessToken: session.accessToken, method: "PATCH", table: "follows", query: [
            URLQueryItem(name: "follower", value: "eq.\(followerID)"),
            URLQueryItem(name: "followee", value: "eq.\(session.userID)"),
        ], body: try? JSONSerialization.data(withJSONObject: ["status": "accepted"]))
    }

    /// Deja de seguir (o rechaza / elimina a un seguidor).
    static func removeFollow(_ config: Config, session: Session, follower: String, followee: String) -> URLRequest {
        rest(config, accessToken: session.accessToken, method: "DELETE", table: "follows", query: [
            URLQueryItem(name: "follower", value: "eq.\(follower)"),
            URLQueryItem(name: "followee", value: "eq.\(followee)"),
        ])
    }

    static func publish(_ config: Config, session: Session, summaries: [DaySummary]) -> URLRequest {
        let rows = summaries.map { DayRow(userID: session.userID, day: $0.day, data: $0) }
        return rest(config, accessToken: session.accessToken, method: "POST", table: "daily_summaries",
                    query: [URLQueryItem(name: "on_conflict", value: "user_id,day")],
                    body: try? JSONEncoder().encode(rows), prefer: "resolution=merge-duplicates")
    }

    static func summaries(_ config: Config, session: Session, userID: String, since day: String) -> URLRequest {
        rest(config, accessToken: session.accessToken, method: "GET", table: "daily_summaries", query: [
            URLQueryItem(name: "select", value: "user_id,day,data"),
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "day", value: "gte.\(day)"),
            URLQueryItem(name: "order", value: "day.desc"),
        ])
    }

    // MARK: Perfil: altura y peso, fotos de progreso, foto de perfil y contadores

    struct Stats: Codable, Equatable {
        let userID: String
        let heightCm: Double?
        let weightKg: Double?

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case heightCm = "height_cm"
            case weightKg = "weight_kg"
        }
    }

    struct PhotoRow: Codable, Equatable, Hashable {
        let userID: String
        let month: String
        let view: String
        let takenOn: String
        let path: String
        var updatedAt: String? = nil

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case month, view, path
            case takenOn = "taken_on"
            case updatedAt = "updated_at"
        }
    }

    struct Counts: Codable, Equatable {
        let followers: Int
        let following: Int
    }

    static func upsertStats(_ config: Config, session: Session, heightCm: Double?, weightKg: Double?) -> URLRequest {
        let row = Stats(userID: session.userID, heightCm: heightCm, weightKg: weightKg)
        return rest(config, accessToken: session.accessToken, method: "POST", table: "profile_stats",
                    query: [URLQueryItem(name: "on_conflict", value: "user_id")],
                    body: try? JSONEncoder().encode([row]), prefer: "resolution=merge-duplicates")
    }

    static func stats(_ config: Config, session: Session, userID: String) -> URLRequest {
        rest(config, accessToken: session.accessToken, method: "GET", table: "profile_stats", query: [
            URLQueryItem(name: "select", value: "user_id,height_cm,weight_kg"),
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
        ])
    }

    static func upsertPhotos(_ config: Config, session: Session, rows: [PhotoRow]) -> URLRequest {
        let clean = rows.map { PhotoRow(userID: session.userID, month: $0.month, view: $0.view, takenOn: $0.takenOn, path: $0.path) }
        let body = try? JSONSerialization.data(withJSONObject: clean.map {
            ["user_id": $0.userID, "month": $0.month, "view": $0.view, "taken_on": $0.takenOn, "path": $0.path,
             "updated_at": ISO8601DateFormatter().string(from: Date())]
        })
        return rest(config, accessToken: session.accessToken, method: "POST", table: "progress_photos",
                    query: [URLQueryItem(name: "on_conflict", value: "user_id,month,view")], body: body,
                    prefer: "resolution=merge-duplicates")
    }

    static func photos(_ config: Config, session: Session, userID: String) -> URLRequest {
        rest(config, accessToken: session.accessToken, method: "GET", table: "progress_photos", query: [
            URLQueryItem(name: "select", value: "user_id,month,view,taken_on,path,updated_at"),
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "order", value: "month.desc"),
        ])
    }

    static func deletePhoto(_ config: Config, session: Session, month: String, view: String) -> URLRequest {
        rest(config, accessToken: session.accessToken, method: "DELETE", table: "progress_photos", query: [
            URLQueryItem(name: "user_id", value: "eq.\(session.userID)"),
            URLQueryItem(name: "month", value: "eq.\(month)"),
            URLQueryItem(name: "view", value: "eq.\(view)"),
        ])
    }

    static func setAvatar(_ config: Config, session: Session, path: String?) -> URLRequest {
        rest(config, accessToken: session.accessToken, method: "PATCH", table: "profiles",
             query: [URLQueryItem(name: "id", value: "eq.\(session.userID)")],
             body: try? JSONSerialization.data(withJSONObject: ["avatar_path": path.map { $0 as Any } ?? NSNull()]))
    }

    static func followCounts(_ config: Config, session: Session, userID: String) -> URLRequest {
        rest(config, accessToken: session.accessToken, method: "POST", table: "rpc/follow_counts",
             body: try? JSONSerialization.data(withJSONObject: ["target": userID]))
    }

    /// Fotos agrupadas por mes (el más reciente primero), con el día en que se hicieron.
    static func groupedByMonth(_ rows: [PhotoRow]) -> [(month: String, takenOn: String, photos: [PhotoRow])] {
        let order = ["front": 0, "side": 1, "back": 2]
        return Dictionary(grouping: rows, by: \.month)
            .map { month, list in
                (month: month, takenOn: list.map(\.takenOn).max() ?? "", photos: list.sorted { (order[$0.view] ?? 3) < (order[$1.view] ?? 3) })
            }
            .sorted { $0.month > $1.month }
    }

    // MARK: Archivos (Supabase Storage)

    static func storagePath(userID: String, month: String, view: String) -> String { "\(userID)/\(month)-\(view).jpg" }

    static func upload(_ config: Config, session: Session, bucket: String, path: String, jpeg: Data) -> URLRequest {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("storage/v1/object/\(bucket)/\(path)"), timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = jpeg
        return request
    }

    static func download(_ config: Config, session: Session, bucket: String, path: String) -> URLRequest {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("storage/v1/object/authenticated/\(bucket)/\(path)"), timeoutInterval: 60)
        request.setValue(config.apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func deleteFile(_ config: Config, session: Session, bucket: String, path: String) -> URLRequest {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("storage/v1/object/\(bucket)/\(path)"), timeoutInterval: 30)
        request.httpMethod = "DELETE"
        request.setValue(config.apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private struct RestErrorBody: Decodable {
        let code: String?
        let message: String?
    }

    /// Comprueba el código HTTP de la base de datos y decodifica la lista devuelta.
    static func decodeRows<T: Decodable>(_ type: T.Type, status: Int, data: Data) throws -> [T] {
        try check(status: status, data: data)
        if data.isEmpty { return [] }
        guard let rows = try? JSONDecoder().decode([T].self, from: data) else { throw SocialError.badResponse }
        return rows
    }

    static func check(status: Int, data: Data) throws {
        guard !(200..<300).contains(status) else { return }
        let body = try? JSONDecoder().decode(RestErrorBody.self, from: data)
        if status == 401 { throw SocialError.notSignedIn }
        if body?.code == "23505" { throw SocialError.usernameTaken }
        if body?.code == "23514" { throw SocialError.invalidUsername }
        if let message = body?.message { throw SocialError.server(message) }
        throw SocialError.http(status)
    }

    private static func url(_ config: Config, path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents(url: config.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    // MARK: Fechas

    static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
