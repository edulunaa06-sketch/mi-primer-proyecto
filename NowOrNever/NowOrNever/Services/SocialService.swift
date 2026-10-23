import Foundation
import Observation

/// Cuentas y amigos. Cada persona usa la app en su propio iPhone con su cuenta; los datos siguen guardados
/// en el móvil y solo se sube un resumen diario (entrenos hechos o no, comidas, kcal y pasos) que pueden ver
/// las personas que te siguen y a las que has aceptado.
///
/// Servidor: un proyecto gratuito de Supabase del usuario (URL + clave pública). La sesión se guarda en el Llavero.
@MainActor
@Observable
final class SocialService {
    private static let keychainService = "NowOrNever.Social"
    private static let sessionAccount = "session"
    private static let urlKey = "social.url"
    private static let apiKeyKey = "social.apiKey"
    private static let profileKey = "social.profile"
    private static let pendingProfileKey = "social.pendingProfile"
    static let shareKey = "social.share"

    private(set) var config: SocialAPI.Config?
    private(set) var session: SocialAPI.Session?
    private(set) var me: SocialAPI.Profile?
    /// Personas a las que sigo y que me han aceptado.
    private(set) var following: [SocialAPI.Profile] = []
    /// Solicitudes que he enviado y aún no han aceptado.
    private(set) var outgoing: [SocialAPI.Profile] = []
    /// Personas que quieren seguirme.
    private(set) var incoming: [SocialAPI.Profile] = []
    /// Personas que me siguen (aceptadas).
    private(set) var followers: [SocialAPI.Profile] = []
    private(set) var lastPublished: Date?
    private(set) var isWorking = false

    var isConfigured: Bool { config != nil }
    var isSignedIn: Bool { session != nil }
    var savedURL: String { UserDefaults.standard.string(forKey: Self.urlKey) ?? "" }
    var savedAPIKey: String { UserDefaults.standard.string(forKey: Self.apiKeyKey) ?? "" }

    init() {
        let defaults = UserDefaults.standard
        config = SocialAPI.Config(url: defaults.string(forKey: Self.urlKey) ?? "", apiKey: defaults.string(forKey: Self.apiKeyKey) ?? "")
            ?? SocialServer.builtIn
        if let data = KeychainStore.load(account: Self.sessionAccount, service: Self.keychainService) {
            session = try? JSONDecoder().decode(SocialAPI.Session.self, from: data)
        }
        if let data = defaults.data(forKey: Self.profileKey) {
            me = try? JSONDecoder().decode(SocialAPI.Profile.self, from: data)
        }
    }

    // MARK: Servidor

    func configure(url: String, apiKey: String) throws {
        guard let config = SocialAPI.Config(url: url, apiKey: apiKey) else {
            throw SocialAPI.SocialError.server("Revisa la URL (https://…supabase.co) y la clave pública (anon o publishable).")
        }
        if config != self.config { signOut() }
        UserDefaults.standard.set(config.baseURL.absoluteString, forKey: Self.urlKey)
        UserDefaults.standard.set(config.apiKey, forKey: Self.apiKeyKey)
        self.config = config
    }

    // MARK: Cuenta

    /// Crea la cuenta. Devuelve false si Supabase pide confirmar el correo antes de entrar.
    func signUp(email: String, password: String, username: String, displayName: String) async throws -> Bool {
        let config = try requireConfig()
        guard let name = SocialAPI.normalizeUsername(username) else { throw SocialAPI.SocialError.invalidUsername }
        guard password.count >= 6 else { throw SocialAPI.SocialError.weakPassword }
        let pending = SocialAPI.Profile(id: "", username: name, displayName: displayName.trimmingCharacters(in: .whitespaces))
        UserDefaults.standard.set(try? JSONEncoder().encode(pending), forKey: Self.pendingProfileKey)
        let (status, data) = try await perform(SocialAPI.signUp(config, email: email.trimmingCharacters(in: .whitespaces), password: password))
        guard let newSession = try SocialAPI.decodeSession(status: status, data: data) else { return false }
        store(newSession)
        try await finishSignIn()
        return true
    }

    /// Lo único que hace falta para empezar: tu @usuario y tu nombre. Crea una cuenta sin correo (la
    /// sesión queda en el Llavero) y guarda el perfil. Si el nombre está cogido, puedes probar otro.
    func start(username: String, displayName: String) async throws {
        let config = try requireConfig()
        guard SocialAPI.normalizeUsername(username) != nil else { throw SocialAPI.SocialError.invalidUsername }
        if session == nil {
            let (status, data) = try await perform(SocialAPI.signUpAnonymously(config))
            guard let newSession = try SocialAPI.decodeSession(status: status, data: data) else { throw SocialAPI.SocialError.badResponse }
            store(newSession)
        }
        try await saveProfile(username: username, displayName: displayName.trimmingCharacters(in: .whitespaces))
        try? await refreshFriends()
    }

    func search(_ text: String) async throws -> [SocialAPI.Profile] {
        let session = try await validSession()
        guard let request = SocialAPI.searchProfiles(try requireConfig(), session: session, query: text) else { return [] }
        let (status, data) = try await perform(request)
        return try SocialAPI.decodeRows(SocialAPI.Profile.self, status: status, data: data)
    }

    func follow(_ profile: SocialAPI.Profile) async throws {
        let session = try await validSession()
        let (status, data) = try await perform(SocialAPI.requestFollow(try requireConfig(), session: session, userID: profile.id))
        try SocialAPI.check(status: status, data: data)
        try await refreshFriends()
    }

    func signIn(email: String, password: String) async throws {
        let config = try requireConfig()
        let (status, data) = try await perform(SocialAPI.signIn(config, email: email.trimmingCharacters(in: .whitespaces), password: password))
        guard let newSession = try SocialAPI.decodeSession(status: status, data: data) else { throw SocialAPI.SocialError.emailNotConfirmed }
        store(newSession)
        try await finishSignIn()
    }

    /// Tras entrar: carga tu perfil o, si es la primera vez, lo crea con el usuario elegido al registrarte.
    private func finishSignIn() async throws {
        let session = try await validSession()
        let (status, data) = try await perform(SocialAPI.profiles(try requireConfig(), session: session, ids: [session.userID]))
        if let mine = try SocialAPI.decodeRows(SocialAPI.Profile.self, status: status, data: data).first {
            setMe(mine)
        } else if let data = UserDefaults.standard.data(forKey: Self.pendingProfileKey),
                  let pending = try? JSONDecoder().decode(SocialAPI.Profile.self, from: data) {
            try await saveProfile(username: pending.username, displayName: pending.displayName)
        }
        try? await refreshFriends()
    }

    func saveProfile(username: String, displayName: String) async throws {
        guard let name = SocialAPI.normalizeUsername(username) else { throw SocialAPI.SocialError.invalidUsername }
        let session = try await validSession()
        let (status, data) = try await perform(SocialAPI.createProfile(try requireConfig(), session: session, username: name, displayName: displayName))
        let rows = try SocialAPI.decodeRows(SocialAPI.Profile.self, status: status, data: data)
        setMe(rows.first ?? SocialAPI.Profile(id: session.userID, username: name, displayName: displayName))
        UserDefaults.standard.removeObject(forKey: Self.pendingProfileKey)
    }

    func signOut() {
        if let config, let session {
            let request = SocialAPI.signOut(config, accessToken: session.accessToken)
            Task { _ = try? await URLSession.shared.data(for: request) }
        }
        KeychainStore.delete(account: Self.sessionAccount, service: Self.keychainService)
        UserDefaults.standard.removeObject(forKey: Self.profileKey)
        session = nil
        me = nil
        following = []
        outgoing = []
        incoming = []
        followers = []
        lastPublished = nil
    }

    // MARK: Amigos

    func refreshFriends() async throws {
        let session = try await validSession()
        let config = try requireConfig()
        var (status, data) = try await perform(SocialAPI.follows(config, session: session))
        let follows = try SocialAPI.decodeRows(SocialAPI.Follow.self, status: status, data: data)
        let others = Set(follows.flatMap { [$0.follower, $0.followee] }).subtracting([session.userID])
        var byID: [String: SocialAPI.Profile] = [:]
        if !others.isEmpty {
            (status, data) = try await perform(SocialAPI.profiles(config, session: session, ids: others.sorted()))
            for profile in try SocialAPI.decodeRows(SocialAPI.Profile.self, status: status, data: data) { byID[profile.id] = profile }
        }
        func people(_ list: [SocialAPI.Follow], _ key: (SocialAPI.Follow) -> String) -> [SocialAPI.Profile] {
            list.compactMap { byID[key($0)] }.sorted { $0.shownName.localizedCaseInsensitiveCompare($1.shownName) == .orderedAscending }
        }
        let mine = follows.filter { $0.follower == session.userID }
        let theirs = follows.filter { $0.followee == session.userID }
        following = people(mine.filter(\.isAccepted), \.followee)
        outgoing = people(mine.filter { !$0.isAccepted }, \.followee)
        followers = people(theirs.filter(\.isAccepted), \.follower)
        incoming = people(theirs.filter { !$0.isAccepted }, \.follower)
    }

    func follow(username: String) async throws {
        guard let name = SocialAPI.normalizeUsername(username) else { throw SocialAPI.SocialError.invalidUsername }
        let session = try await validSession()
        let config = try requireConfig()
        var (status, data) = try await perform(SocialAPI.findProfile(config, session: session, username: name))
        guard let profile = try SocialAPI.decodeRows(SocialAPI.Profile.self, status: status, data: data).first,
              profile.id != session.userID else { throw SocialAPI.SocialError.userNotFound }
        (status, data) = try await perform(SocialAPI.requestFollow(config, session: session, userID: profile.id))
        try SocialAPI.check(status: status, data: data)
        try await refreshFriends()
    }

    /// Acepta su solicitud y, si quieres, le pides tú también seguirle.
    func accept(_ profile: SocialAPI.Profile, followBack: Bool) async throws {
        let session = try await validSession()
        let config = try requireConfig()
        var (status, data) = try await perform(SocialAPI.accept(config, session: session, followerID: profile.id))
        try SocialAPI.check(status: status, data: data)
        if followBack, !following.contains(profile), !outgoing.contains(profile) {
            (status, data) = try await perform(SocialAPI.requestFollow(config, session: session, userID: profile.id))
            try SocialAPI.check(status: status, data: data)
        }
        try await refreshFriends()
    }

    /// Rechaza una solicitud o deja de permitir que alguien te siga.
    func removeFollower(_ profile: SocialAPI.Profile) async throws {
        let session = try await validSession()
        let (status, data) = try await perform(SocialAPI.removeFollow(try requireConfig(), session: session, follower: profile.id, followee: session.userID))
        try SocialAPI.check(status: status, data: data)
        try await refreshFriends()
    }

    func unfollow(_ profile: SocialAPI.Profile) async throws {
        let session = try await validSession()
        let (status, data) = try await perform(SocialAPI.removeFollow(try requireConfig(), session: session, follower: session.userID, followee: profile.id))
        try SocialAPI.check(status: status, data: data)
        try await refreshFriends()
    }

    func summaries(of profile: SocialAPI.Profile, days: Int = 14) async throws -> [SocialAPI.DaySummary] {
        let session = try await validSession()
        let since = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Date()) ?? Date()
        let (status, data) = try await perform(SocialAPI.summaries(try requireConfig(), session: session, userID: profile.id,
                                                                   since: SocialAPI.dayString(since)))
        return try SocialAPI.decodeRows(SocialAPI.DayRow.self, status: status, data: data).map(\.data)
    }

    /// Sube tus resúmenes (si compartir está activado y tienes perfil). Los errores no interrumpen el uso de la app.
    func publish(_ summaries: [SocialAPI.DaySummary]) async throws {
        guard UserDefaults.standard.object(forKey: Self.shareKey) as? Bool ?? true, me != nil, !summaries.isEmpty else { return }
        let session = try await validSession()
        let (status, data) = try await perform(SocialAPI.publish(try requireConfig(), session: session, summaries: summaries))
        try SocialAPI.check(status: status, data: data)
        lastPublished = Date()
    }

    // MARK: Interno

    private func requireConfig() throws -> SocialAPI.Config {
        guard let config else { throw SocialAPI.SocialError.notConfigured }
        return config
    }

    /// Devuelve una sesión válida, renovándola si ha caducado (los tokens duran una hora).
    func currentSession() async throws -> SocialAPI.Session { try await validSession() }

    private func validSession() async throws -> SocialAPI.Session {
        guard let current = session else { throw SocialAPI.SocialError.notSignedIn }
        guard current.isExpired() else { return current }
        let (status, data) = try await perform(SocialAPI.refresh(try requireConfig(), refreshToken: current.refreshToken))
        guard (200..<300).contains(status), let renewed = try SocialAPI.decodeSession(status: status, data: data) else {
            signOut()
            throw SocialAPI.SocialError.notSignedIn
        }
        store(renewed)
        return renewed
    }

    func send(_ request: URLRequest) async throws -> (Int, Data) { try await perform(request) }

    private func perform(_ request: URLRequest) async throws -> (Int, Data) {
        isWorking = true
        defer { isWorking = false }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
    }

    private func store(_ newSession: SocialAPI.Session) {
        session = newSession
        if let data = try? JSONEncoder().encode(newSession) {
            try? KeychainStore.save(data, account: Self.sessionAccount, service: Self.keychainService)
        }
    }

    func updateMe(_ profile: SocialAPI.Profile) { setMe(profile) }

    private func setMe(_ profile: SocialAPI.Profile) {
        me = profile
        UserDefaults.standard.set(try? JSONEncoder().encode(profile), forKey: Self.profileKey)
    }
}

// MARK: - Perfil: foto, altura y peso, fotos de progreso

extension SocialService {
    static let shareStatsKey = "social.shareStats"
    /// nil = aún no se ha preguntado. Las fotos de progreso son sensibles: se pide permiso la primera vez.
    static let sharePhotosKey = "social.sharePhotos"
    private static let uploadedPhotosKey = "social.uploadedPhotos"

    var sharesStats: Bool { UserDefaults.standard.object(forKey: Self.shareStatsKey) as? Bool ?? true }
    var sharesPhotos: Bool? { UserDefaults.standard.object(forKey: Self.sharePhotosKey) as? Bool }

    struct LocalPhoto {
        let month: String
        let view: String
        let takenOn: String
        let version: String
        let jpeg: () -> Data?
    }

    /// Sube altura, peso y las fotos de progreso nuevas o cambiadas (solo si compartes cada cosa).
    func syncProfile(heightCm: Double?, weightKg: Double?, photos: [LocalPhoto]) async throws {
        guard isSignedIn, me != nil, let config else { return }
        let session = try await currentSession()
        if sharesStats {
            let (status, data) = try await send(SocialAPI.upsertStats(config, session: session, heightCm: heightCm, weightKg: weightKg))
            try SocialAPI.check(status: status, data: data)
        }
        guard sharesPhotos == true else { return }
        var uploaded = UserDefaults.standard.dictionary(forKey: Self.uploadedPhotosKey) as? [String: String] ?? [:]
        let localKeys = Set(photos.map { "\($0.month)|\($0.view)" })
        for photo in photos {
            let key = "\(photo.month)|\(photo.view)"
            guard uploaded[key] != photo.version, let jpeg = photo.jpeg() else { continue }
            let path = SocialAPI.storagePath(userID: session.userID, month: photo.month, view: photo.view)
            var (status, data) = try await send(SocialAPI.upload(config, session: session, bucket: "progress", path: path, jpeg: jpeg))
            try SocialAPI.check(status: status, data: data)
            (status, data) = try await send(SocialAPI.upsertPhotos(config, session: session, rows: [
                SocialAPI.PhotoRow(userID: session.userID, month: photo.month, view: photo.view, takenOn: photo.takenOn, path: path),
            ]))
            try SocialAPI.check(status: status, data: data)
            uploaded[key] = photo.version
            UserDefaults.standard.set(uploaded, forKey: Self.uploadedPhotosKey)
        }
        // Fotos borradas en el iPhone: también se borran del servidor.
        for key in uploaded.keys where !localKeys.contains(key) {
            let parts = key.split(separator: "|").map(String.init)
            guard parts.count == 2 else { continue }
            try await removeRemotePhoto(month: parts[0], view: parts[1], session: session, config: config)
            uploaded.removeValue(forKey: key)
            UserDefaults.standard.set(uploaded, forKey: Self.uploadedPhotosKey)
        }
    }

    func setSharesStats(_ value: Bool) async {
        UserDefaults.standard.set(value, forKey: Self.shareStatsKey)
        guard !value, let config, let session = try? await currentSession() else { return }
        _ = try? await send(SocialAPI.upsertStats(config, session: session, heightCm: nil, weightKg: nil))
    }

    /// Al dejar de compartir fotos se borran del servidor (en el iPhone se quedan).
    func setSharesPhotos(_ value: Bool) async {
        UserDefaults.standard.set(value, forKey: Self.sharePhotosKey)
        guard !value, let config, let session = try? await currentSession() else { return }
        let uploaded = UserDefaults.standard.dictionary(forKey: Self.uploadedPhotosKey) as? [String: String] ?? [:]
        for key in uploaded.keys {
            let parts = key.split(separator: "|").map(String.init)
            if parts.count == 2 { try? await removeRemotePhoto(month: parts[0], view: parts[1], session: session, config: config) }
        }
        UserDefaults.standard.removeObject(forKey: Self.uploadedPhotosKey)
    }

    private func removeRemotePhoto(month: String, view: String, session: SocialAPI.Session, config: SocialAPI.Config) async throws {
        _ = try await send(SocialAPI.deleteFile(config, session: session, bucket: "progress",
                                                path: SocialAPI.storagePath(userID: session.userID, month: month, view: view)))
        let (status, data) = try await send(SocialAPI.deletePhoto(config, session: session, month: month, view: view))
        try SocialAPI.check(status: status, data: data)
    }

    func uploadAvatar(_ jpeg: Data) async throws {
        guard let config, let me else { throw SocialAPI.SocialError.notSignedIn }
        let session = try await currentSession()
        let path = "\(session.userID)/avatar-\(Int(Date().timeIntervalSince1970)).jpg"
        var (status, data) = try await send(SocialAPI.upload(config, session: session, bucket: "avatars", path: path, jpeg: jpeg))
        try SocialAPI.check(status: status, data: data)
        (status, data) = try await send(SocialAPI.setAvatar(config, session: session, path: path))
        try SocialAPI.check(status: status, data: data)
        if let old = me.avatarPath { _ = try? await send(SocialAPI.deleteFile(config, session: session, bucket: "avatars", path: old)) }
        var updated = me
        updated.avatarPath = path
        updateMe(updated)
    }

    struct ProfileDetail {
        var stats: SocialAPI.Stats?
        var counts: SocialAPI.Counts?
        var photos: [SocialAPI.PhotoRow] = []
    }

    func profileDetail(of userID: String) async throws -> ProfileDetail {
        guard let config else { throw SocialAPI.SocialError.notConfigured }
        let session = try await currentSession()
        var detail = ProfileDetail()
        var (status, data) = try await send(SocialAPI.stats(config, session: session, userID: userID))
        detail.stats = try SocialAPI.decodeRows(SocialAPI.Stats.self, status: status, data: data).first
        (status, data) = try await send(SocialAPI.followCounts(config, session: session, userID: userID))
        detail.counts = try SocialAPI.decodeRows(SocialAPI.Counts.self, status: status, data: data).first
        (status, data) = try await send(SocialAPI.photos(config, session: session, userID: userID))
        detail.photos = try SocialAPI.decodeRows(SocialAPI.PhotoRow.self, status: status, data: data)
        return detail
    }

    /// Descarga una imagen privada (foto de perfil o de progreso) respetando las reglas de acceso.
    func image(bucket: String, path: String, version: String? = nil) async -> Data? {
        let key = path + "|" + (version ?? "")
        if let cached = ImageCache.shared.data(for: key) { return cached }
        guard let config, let session = try? await currentSession(),
              let response = try? await send(SocialAPI.download(config, session: session, bucket: bucket, path: path)),
              (200..<300).contains(response.0), !response.1.isEmpty else { return nil }
        let data = response.1
        ImageCache.shared.store(data, for: key)
        return data
    }
}

/// Caché en memoria de imágenes descargadas (se vacía al cerrar la app).
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, NSData>()

    func data(for key: String) -> Data? { cache.object(forKey: key as NSString) as Data? }
    func store(_ data: Data, for key: String) { cache.setObject(data as NSData, forKey: key as NSString, cost: data.count) }
    func remove(_ key: String) { cache.removeObject(forKey: key as NSString) }
}
