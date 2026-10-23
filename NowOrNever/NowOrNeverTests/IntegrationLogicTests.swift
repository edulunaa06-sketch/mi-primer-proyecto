import XCTest
@testable import NowOrNever

final class StravaAPITests: XCTestCase {
    func testTokenRequestBodyGoesDirectlyToStrava() {
        let exchange = StravaAPI.tokenRequestBody(clientID: " 12345 ", clientSecret: "abcdef0123456789abcdef0123456789abcdef01", code: "c0de")
        XCTAssertEqual(exchange["client_id"], "12345")
        XCTAssertEqual(exchange["grant_type"], "authorization_code")
        XCTAssertEqual(exchange["code"], "c0de")
        XCTAssertNil(exchange["refresh_token"])
        let refresh = StravaAPI.tokenRequestBody(clientID: "12345", clientSecret: "abcdef0123456789abcdef0123456789abcdef01", refreshToken: "r")
        XCTAssertEqual(refresh["grant_type"], "refresh_token")
        XCTAssertEqual(refresh["refresh_token"], "r")
        XCTAssertEqual(StravaAPI.tokenURL.host, "www.strava.com")
    }

    func testCredentialValidation() {
        XCTAssertTrue(StravaAPI.isValidClientID("123456"))
        XCTAssertFalse(StravaAPI.isValidClientID("12a"))
        XCTAssertFalse(StravaAPI.isValidClientID(""))
        XCTAssertTrue(StravaAPI.isValidClientSecret("abcdef0123456789abcdef0123456789abcdef01"))
        XCTAssertFalse(StravaAPI.isValidClientSecret("secreto"))
        XCTAssertFalse(StravaAPI.isValidClientSecret("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"))
    }

    func testAuthorizeURLRequiresNumericClientID() {
        XCTAssertNil(StravaAPI.authorizeURL(clientID: "", state: "x"))
        XCTAssertNil(StravaAPI.authorizeURL(clientID: "abc", state: "x"))
        let url = StravaAPI.authorizeURL(clientID: "12345", state: "abc")
        XCTAssertNotNil(url)
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "client_id" }?.value, "12345")
        XCTAssertEqual(items.first { $0.name == "redirect_uri" }?.value, StravaAPI.redirectURI)
        XCTAssertEqual(items.first { $0.name == "response_type" }?.value, "code")
        XCTAssertEqual(items.first { $0.name == "state" }?.value, "abc")
        XCTAssertFalse(url!.absoluteString.contains("secret"))
    }

    func testCallbackSuccess() throws {
        let url = URL(string: "nowornever://localhost/strava?state=S1&code=CODE123&scope=read,activity:read_all")!
        XCTAssertEqual(try StravaAPI.parseCallback(url, expectedState: "S1"), "CODE123")
    }

    func testCallbackDenied() {
        let url = URL(string: "nowornever://localhost/strava?state=S1&error=access_denied")!
        XCTAssertThrowsError(try StravaAPI.parseCallback(url, expectedState: "S1")) { error in
            XCTAssertEqual(error as? StravaAPI.CallbackError, .denied)
        }
    }

    func testCallbackStateMismatch() {
        let url = URL(string: "nowornever://localhost/strava?state=OTHER&code=C&scope=activity:read")!
        XCTAssertThrowsError(try StravaAPI.parseCallback(url, expectedState: "S1")) { error in
            XCTAssertEqual(error as? StravaAPI.CallbackError, .stateMismatch)
        }
    }

    func testCallbackInsufficientScope() {
        let url = URL(string: "nowornever://localhost/strava?state=S1&code=C&scope=read")!
        XCTAssertThrowsError(try StravaAPI.parseCallback(url, expectedState: "S1")) { error in
            XCTAssertEqual(error as? StravaAPI.CallbackError, .insufficientScope("read"))
        }
    }

    func testDecodeActivitiesAndFilterRuns() throws {
        let json = """
        [
          {"id": 1, "name": "Carrera suave", "sport_type": "Run", "type": "Run", "start_date": "2026-10-19T06:30:00Z",
           "distance": 5230.4, "moving_time": 1800, "elapsed_time": 1900, "total_elevation_gain": 35.2},
          {"id": 2, "name": "Bici", "sport_type": "Ride", "type": "Ride", "start_date": "2026-10-20T06:30:00Z",
           "distance": 20000, "moving_time": 3600, "elapsed_time": 3700}
        ]
        """.data(using: .utf8)!
        let activities = try StravaAPI.decodeActivities(json)
        XCTAssertEqual(activities.count, 2)
        XCTAssertEqual(activities.filter(\.isRun).map(\.id), [1])
        XCTAssertEqual(activities[0].totalElevationGain, 35.2)
        XCTAssertNil(activities[1].totalElevationGain)
    }

    func testTokenDecoding() throws {
        let json = #"{"token_type":"Bearer","access_token":"a","refresh_token":"r","expires_at":1800000000,"expires_in":21600,"scope":"read,activity:read_all"}"#
        let token = try JSONDecoder().decode(StravaAPI.TokenResponse.self, from: Data(json.utf8))
        XCTAssertEqual(token.accessToken, "a")
        XCTAssertEqual(token.expirationDate, Date(timeIntervalSince1970: 1_800_000_000))
    }
}

final class RunMathTests: XCTestCase {
    func testPace() {
        XCTAssertEqual(RunMath.paceSecondsPerKm(distanceMeters: 5000, seconds: 1500), 300)
        XCTAssertNil(RunMath.paceSecondsPerKm(distanceMeters: 0, seconds: 1500))
        XCTAssertEqual(RunMath.formatPace(300), "5:00 /km")
        XCTAssertEqual(RunMath.formatPace(nil), "—")
        XCTAssertEqual(RunMath.formatDuration(3725), "1:02:05")
        XCTAssertEqual(RunMath.formatDuration(1805), "30:05")
    }
}

final class PhotoReminderPlannerTests: XCTestCase {
    private let now = DateUtils.calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 10))!

    func testDay22UsesSingleRepeatingTrigger() {
        let requests = PhotoReminderPlanner.requests(referenceDay: 22, hour: 20, from: now)
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests[0].repeats)
        XCTAssertEqual(requests[0].components.day, 22)
        XCTAssertEqual(requests[0].components.hour, 20)
        XCTAssertNil(requests[0].components.month)
    }

    func testDay31ClampsToMonthEnd() {
        let requests = PhotoReminderPlanner.requests(referenceDay: 31, hour: 20, from: now)
        XCTAssertFalse(requests.isEmpty)
        XCTAssertTrue(requests.allSatisfy { !$0.repeats })
        // Noviembre de 2026 tiene 30 días y febrero de 2027 tiene 28.
        XCTAssertEqual(requests.first { $0.components.month == 11 }?.components.day, 30)
        XCTAssertEqual(requests.first { $0.components.month == 2 }?.components.day, 28)
        XCTAssertEqual(Set(requests.map(\.identifier)).count, requests.count)
    }
}
