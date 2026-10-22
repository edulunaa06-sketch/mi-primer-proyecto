import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import NowOrNever

final class SocialAPITests: XCTestCase {
    private let config = SocialAPI.Config(url: "https://abcd.supabase.co/", apiKey: "sb_publishable_1234567890abcdef")!
    private let session = SocialAPI.Session(accessToken: "tok", refreshToken: "ref", expiresAt: Date().addingTimeInterval(3600),
                                            userID: "aaaaaaaa-0000-0000-0000-000000000001", email: "a@b.c")

    func testConfigValidation() {
        XCTAssertNil(SocialAPI.Config(url: "http://abcd.supabase.co", apiKey: "sb_publishable_1234567890abcdef"), "Solo https")
        XCTAssertNil(SocialAPI.Config(url: "https://abcd.supabase.co", apiKey: "corta"))
        XCTAssertNil(SocialAPI.Config(url: "https://abcd.supabase.co", apiKey: "sb_secret_1234567890abcdefghij"), "Nunca la clave secreta")
        XCTAssertEqual(config.baseURL.absoluteString, "https://abcd.supabase.co")
    }

    func testUsernames() {
        XCTAssertEqual(SocialAPI.normalizeUsername(" @Edu.Luna "), "edu.luna")
        XCTAssertNil(SocialAPI.normalizeUsername("ab"))
        XCTAssertNil(SocialAPI.normalizeUsername("con espacio"))
        XCTAssertNil(SocialAPI.normalizeUsername("ñandú"))
    }

    func testAuthRequests() throws {
        let signIn = SocialAPI.signIn(config, email: "a@b.c", password: "secreto1")
        XCTAssertEqual(signIn.url?.absoluteString, "https://abcd.supabase.co/auth/v1/token?grant_type=password")
        XCTAssertEqual(signIn.httpMethod, "POST")
        XCTAssertEqual(signIn.value(forHTTPHeaderField: "apikey"), config.apiKey)
        XCTAssertNil(signIn.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: signIn.httpBody ?? Data()) as? [String: String])
        XCTAssertEqual(body, ["email": "a@b.c", "password": "secreto1"])
    }

    func testDecodeSessionAndSignUpWithoutSession() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let ok = #"{"access_token":"A","refresh_token":"R","expires_in":3600,"token_type":"bearer","user":{"id":"u1","email":"a@b.c"}}"#
        let s = try XCTUnwrap(SocialAPI.decodeSession(status: 200, data: Data(ok.utf8), now: now))
        XCTAssertEqual(s.userID, "u1")
        XCTAssertEqual(s.expiresAt, now.addingTimeInterval(3600))
        let pending = #"{"id":"u1","email":"a@b.c","confirmation_sent_at":"2026-10-22T10:00:00Z"}"#
        XCTAssertNil(try SocialAPI.decodeSession(status: 200, data: Data(pending.utf8)))
    }

    func testAuthErrors() {
        let invalid = Data(#"{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials"}"#.utf8)
        XCTAssertEqual(SocialAPI.authError(status: 400, data: invalid), .invalidCredentials)
        let legacy = Data(#"{"error":"invalid_grant","error_description":"Email not confirmed"}"#.utf8)
        XCTAssertEqual(SocialAPI.authError(status: 400, data: legacy), .invalidCredentials)
        let unconfirmed = Data(#"{"error_code":"email_not_confirmed","msg":"Email not confirmed"}"#.utf8)
        XCTAssertEqual(SocialAPI.authError(status: 400, data: unconfirmed), .emailNotConfirmed)
    }

    func testRestRequests() throws {
        let follows = SocialAPI.follows(config, session: session)
        XCTAssertEqual(follows.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        let query = try XCTUnwrap(URLComponents(url: follows.url!, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertTrue(query.contains(URLQueryItem(name: "or", value: "(follower.eq.\(session.userID),followee.eq.\(session.userID))")))
        let publish = SocialAPI.publish(config, session: session, summaries: [Self.summary(day: "2026-10-22")])
        XCTAssertEqual(publish.value(forHTTPHeaderField: "Prefer"), "resolution=merge-duplicates")
        XCTAssertTrue(publish.url!.absoluteString.hasSuffix("/rest/v1/daily_summaries?on_conflict=user_id,day"))
        let rows = try JSONSerialization.jsonObject(with: publish.httpBody!) as? [[String: Any]]
        XCTAssertEqual(rows?.first?["user_id"] as? String, session.userID)
    }

    func testDuplicateUsernameError() {
        let body = Data(#"{"code":"23505","message":"duplicate key value violates unique constraint"}"#.utf8)
        XCTAssertThrowsError(try SocialAPI.check(status: 409, data: body)) { XCTAssertEqual($0 as? SocialAPI.SocialError, .usernameTaken) }
    }

    static func summary(day: String, done: Bool = true) -> SocialAPI.DaySummary {
        SocialAPI.DaySummary(
            day: day,
            sessions: [.init(title: "Push A", kind: "strength", completed: done, exercisesDone: done ? 6 : 1, exercisesTotal: 6,
                             highlights: ["Press banca · 60 kg × 8"])],
            meals: [.init(type: "Desayuno", name: "Plato de frutas con yogur", kcal: 445, eaten: true)],
            kcalEaten: 445, proteinEaten: 25, kcalTarget: 2550, steps: 9000, stepGoal: 8000)
    }
}

/// Prueba de punta a punta contra un PostgREST local con el esquema de docs/supabase/schema.sql.
/// Solo se ejecuta si existen NN_SOCIAL_URL, NN_SOCIAL_TOKEN_A y NN_SOCIAL_TOKEN_B (tokens JWT de dos usuarios).
final class SocialIntegrationTests: XCTestCase {
    func testTwoAccountsFollowAndShare() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let base = env["NN_SOCIAL_URL"].flatMap(URL.init(string:)), let tokenA = env["NN_SOCIAL_TOKEN_A"],
              let tokenB = env["NN_SOCIAL_TOKEN_B"] else { throw XCTSkip("Sin servidor local de pruebas") }
        let config = SocialAPI.Config(unchecked: base, apiKey: "local-test-key-0000000000")
        let a = SocialAPI.Session(accessToken: tokenA, refreshToken: "", expiresAt: .distantFuture,
                                  userID: "aaaaaaaa-0000-0000-0000-000000000001", email: nil)
        let b = SocialAPI.Session(accessToken: tokenB, refreshToken: "", expiresAt: .distantFuture,
                                  userID: "bbbbbbbb-0000-0000-0000-000000000002", email: nil)

        func run(_ request: URLRequest) async throws -> (Int, Data) {
            let (data, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
        }

        var (status, data) = try await run(SocialAPI.createProfile(config, session: a, username: "edu", displayName: "Edu"))
        try SocialAPI.check(status: status, data: data)
        (status, data) = try await run(SocialAPI.createProfile(config, session: b, username: "edu", displayName: "Copia"))
        XCTAssertThrowsError(try SocialAPI.check(status: status, data: data)) { XCTAssertEqual($0 as? SocialAPI.SocialError, .usernameTaken) }
        (status, data) = try await run(SocialAPI.createProfile(config, session: b, username: "novia", displayName: "Novia"))
        try SocialAPI.check(status: status, data: data)

        (status, data) = try await run(SocialAPI.publish(config, session: a, summaries: [SocialAPITests.summary(day: "2026-10-21", done: false),
                                                                                           SocialAPITests.summary(day: "2026-10-22")]))
        try SocialAPI.check(status: status, data: data)

        (status, data) = try await run(SocialAPI.findProfile(config, session: b, username: "edu"))
        let found = try SocialAPI.decodeRows(SocialAPI.Profile.self, status: status, data: data)
        XCTAssertEqual(found.first?.id, a.userID)

        (status, data) = try await run(SocialAPI.requestFollow(config, session: b, userID: a.userID))
        try SocialAPI.check(status: status, data: data)
        (status, data) = try await run(SocialAPI.summaries(config, session: b, userID: a.userID, since: "2026-10-01"))
        XCTAssertEqual(try SocialAPI.decodeRows(SocialAPI.DayRow.self, status: status, data: data).count, 0, "Sin aceptar no ve nada")

        (status, data) = try await run(SocialAPI.follows(config, session: a))
        let pending = try SocialAPI.decodeRows(SocialAPI.Follow.self, status: status, data: data)
        XCTAssertEqual(pending, [SocialAPI.Follow(follower: b.userID, followee: a.userID, status: "pending")])
        (status, data) = try await run(SocialAPI.accept(config, session: a, followerID: b.userID))
        try SocialAPI.check(status: status, data: data)

        (status, data) = try await run(SocialAPI.summaries(config, session: b, userID: a.userID, since: "2026-10-01"))
        let rows = try SocialAPI.decodeRows(SocialAPI.DayRow.self, status: status, data: data)
        XCTAssertEqual(rows.map(\.day), ["2026-10-22", "2026-10-21"])
        XCTAssertEqual(rows.last?.data.trainingDone, 0, "Se ve el día que no entrenó")
        XCTAssertEqual(rows.first?.data.meals.first?.name, "Plato de frutas con yogur")

        // Volver a publicar el mismo día lo actualiza (no duplica).
        (status, data) = try await run(SocialAPI.publish(config, session: a, summaries: [SocialAPITests.summary(day: "2026-10-21", done: true)]))
        try SocialAPI.check(status: status, data: data)
        (status, data) = try await run(SocialAPI.summaries(config, session: b, userID: a.userID, since: "2026-10-21"))
        let updated = try SocialAPI.decodeRows(SocialAPI.DayRow.self, status: status, data: data)
        XCTAssertEqual(updated.count, 2)
        XCTAssertEqual(updated.last?.data.trainingDone, 1)

        (status, data) = try await run(SocialAPI.profiles(config, session: b, ids: [a.userID, b.userID]))
        XCTAssertEqual(Set(try SocialAPI.decodeRows(SocialAPI.Profile.self, status: status, data: data).map(\.username)), ["edu", "novia"])

        (status, data) = try await run(SocialAPI.removeFollow(config, session: b, follower: b.userID, followee: a.userID))
        try SocialAPI.check(status: status, data: data)
        (status, data) = try await run(SocialAPI.summaries(config, session: b, userID: a.userID, since: "2026-10-01"))
        XCTAssertEqual(try SocialAPI.decodeRows(SocialAPI.DayRow.self, status: status, data: data).count, 0, "Al dejar de seguir ya no ve nada")
    }
}
