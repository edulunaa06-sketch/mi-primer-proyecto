import XCTest
@testable import Atlas

/// Coach de cargas, récords, descanso, discos, calentamiento, músculos y predicción de carrera.
final class TrainingScienceTests: XCTestCase {
    func testDoubleProgression() {
        // Todas las series al tope (10) → sube 2,5 kg.
        let up = OverloadCoach.suggest(repRange: "6–10", last: [.init(kg: 60, reps: 10), .init(kg: 60, reps: 10), .init(kg: 60, reps: 10)])
        XCTAssertEqual(up?.kind, .increase)
        XCTAssertEqual(up?.kg, 62.5)
        // Cargas pequeñas (mancuernas) suben de 1 en 1.
        XCTAssertEqual(OverloadCoach.suggest(repRange: "8-12", last: [.init(kg: 14, reps: 12), .init(kg: 14, reps: 12)])?.kg, 15)
        // Dentro del rango → mismo peso y una rep más.
        let same = OverloadCoach.suggest(repRange: "6–10", last: [.init(kg: 60, reps: 8), .init(kg: 60, reps: 7)])
        XCTAssertEqual(same?.kind, .repeatWeight)
        XCTAssertEqual(same?.kg, 60)
        XCTAssertEqual(same?.repsMin, 9)
        // Alguna serie por debajo del mínimo → consolida.
        XCTAssertEqual(OverloadCoach.suggest(repRange: "6–10", last: [.init(kg: 60, reps: 8), .init(kg: 60, reps: 4)])?.kind, .consolidate)
        // Sin datos o rango ilegible → nada (no se inventa).
        XCTAssertNil(OverloadCoach.suggest(repRange: "6–10", last: []))
        XCTAssertNil(OverloadCoach.suggest(repRange: "al fallo", last: [.init(kg: 50, reps: 10)]))
        // Una serie de aproximación más ligera no impide subir si las de trabajo llegaron al tope… pero sí si no todas.
        XCTAssertEqual(OverloadCoach.suggest(repRange: "6–10", last: [.init(kg: 40, reps: 10), .init(kg: 60, reps: 10)])?.kind, .repeatWeight)
    }

    func testRecords() {
        XCTAssertEqual(PersonalRecords.e1rm(.init(kg: 100, reps: 1)), 100)
        XCTAssertEqual(PersonalRecords.e1rm(.init(kg: 100, reps: 10)), 100 * (1 + 10.0 / 30), accuracy: 0.001)
        XCTAssertEqual(PersonalRecords.e1rm(.init(kg: 50, reps: 30)), PersonalRecords.e1rm(.init(kg: 50, reps: 12)), "Limitado a 12 reps")
        XCTAssertEqual(PersonalRecords.e1rm(.init(kg: 0, reps: 10)), 0)
        let best = PersonalRecords.best([.init(kg: 80, reps: 8), .init(kg: 85, reps: 5)])
        XCTAssertTrue(PersonalRecords.isRecord(.init(kg: 85, reps: 8), previousBest: best))
        XCTAssertFalse(PersonalRecords.isRecord(.init(kg: 80, reps: 8), previousBest: best), "Igualar no es récord")
        XCTAssertFalse(PersonalRecords.isRecord(.init(kg: 200, reps: 5), previousBest: 0), "La primera vez no es récord")
    }

    func testSessionPacing() {
        XCTAssertEqual(SessionPacing.restSeconds(repRange: "3–5"), 180)
        XCTAssertEqual(SessionPacing.restSeconds(repRange: "6–10"), 120)
        XCTAssertEqual(SessionPacing.restSeconds(repRange: "10–15"), 90)
        XCTAssertEqual(SessionPacing.restSeconds(repRange: "12–20"), 60)
        // Solo sirve para estimar la duración: 4 × 8 repeticiones ≈ 4 × (45 s + 120 s).
        XCTAssertEqual(WorkoutMath.estimatedMinutes([(sets: 4, repRange: "6–10")]), 10)
    }

    func testPlates() {
        let r = PlateCalculator.load(target: 100)
        XCTAssertEqual(r.perSide, [25, 15])
        XCTAssertEqual(r.total, 100)
        XCTAssertFalse(r.isApproximate)
        XCTAssertEqual(PlateCalculator.load(target: 62.5).perSide, [20, 1.25])
        let odd = PlateCalculator.load(target: 61)
        XCTAssertTrue(odd.isApproximate)
        XCTAssertEqual(odd.total, 60)
        XCTAssertEqual(PlateCalculator.load(target: 20).perSide, [])
        XCTAssertTrue(PlateCalculator.load(target: 15).isApproximate)
    }

    func testWarmup() {
        let w = Warmup.sets(working: 100)
        XCTAssertEqual(w.map(\.kg), [20, 50, 70, 85])
        XCTAssertEqual(w.map(\.reps), [10, 8, 5, 3])
        XCTAssertTrue(Warmup.sets(working: 20).isEmpty)
        XCTAssertTrue(Warmup.sets(working: 30).allSatisfy { $0.kg < 30 })
    }

    func testMusclesForEveryDefaultExercise() {
        for session in WeeklyRoutine.allSessions {
            for ex in session.exercises {
                XCTAssertFalse(Muscle.worked(by: ex.name).isEmpty, "Sin músculo: \(ex.name)")
            }
        }
        XCTAssertEqual(Muscle.worked(by: "Press de banca con barra").first, .chest)
        XCTAssertEqual(Muscle.worked(by: "Jalón al pecho con agarre neutro").first, .back, "«pecho» en un jalón es espalda")
        XCTAssertEqual(Muscle.worked(by: "Curl femoral sentado").first, .hamstrings, "Curl femoral no es bíceps")
        XCTAssertEqual(Muscle.worked(by: "Curl inverso con barra EZ").first, .forearms)
        XCTAssertEqual(Muscle.worked(by: "Pájaros en máquina / reverse pec deck").first, .shoulders)
        let v = WeeklyVolume.sets([("Press de banca con barra", 4), ("Jalón con agarre neutro", 3)])
        XCTAssertEqual(v[.chest], 4)
        XCTAssertEqual(v[.triceps], 2)
        XCTAssertEqual(v[.back], 3)
        XCTAssertEqual(v[.biceps], 1.5)
    }

    func testRacePredictor() {
        // 10 km en 50:00 → 5 km ≈ 24:00, media ≈ 1:50:21.
        XCTAssertEqual(RacePredictor.predict(fromMeters: 10000, seconds: 3000, toMeters: 5000)!, 1440, accuracy: 5)
        XCTAssertEqual(RacePredictor.predict(fromMeters: 10000, seconds: 3000, toMeters: 21097.5)!, 6621, accuracy: 10)
        XCTAssertNil(RacePredictor.predict(fromMeters: 500, seconds: 120, toMeters: 5000), "Muy corta para predecir")
        let now = Date()
        let runs = [RunSample(date: now, meters: 5000, seconds: 1800), RunSample(date: now, meters: 10000, seconds: 3000),
                    RunSample(date: now, meters: 2000, seconds: 400)]
        XCTAssertEqual(RacePredictor.reference(runs)?.meters, 10000, "La de mejor rendimiento, ignorando las de menos de 3 km")
        XCTAssertNil(RacePredictor.reference([]))
    }
}

final class StravaAPITests: XCTestCase {
    func testAuthorizeURLAndCallback() throws {
        XCTAssertNil(StravaAPI.authorizeURL(clientID: "abc", state: "s"))
        let url = StravaAPI.authorizeURL(clientID: "12345", state: "xyz")!
        XCTAssertTrue(url.absoluteString.contains("redirect_uri=atlas://localhost/strava"))
        let ok = URL(string: "atlas://localhost/strava?state=xyz&code=CODE&scope=read,activity:read_all")!
        XCTAssertEqual(try StravaAPI.parseCallback(ok, expectedState: "xyz"), "CODE")
        XCTAssertThrowsError(try StravaAPI.parseCallback(ok, expectedState: "otro"))
        let denied = URL(string: "atlas://localhost/strava?error=access_denied&state=xyz")!
        XCTAssertThrowsError(try StravaAPI.parseCallback(denied, expectedState: "xyz"))
    }

    func testRunsAreDecoded() throws {
        let json = """
        [{"id": 1, "name": "Rodaje", "sport_type": "Run", "start_date": "2026-10-20T07:00:00Z", "distance": 8000, "moving_time": 2400, "elapsed_time": 2500},
         {"id": 2, "name": "Bici", "sport_type": "Ride", "start_date": "2026-10-21T07:00:00Z", "distance": 30000, "moving_time": 3600, "elapsed_time": 3700}]
        """
        let list = try StravaAPI.decodeActivities(Data(json.utf8))
        XCTAssertEqual(list.filter(\.isRun).map(\.id), [1])
    }
}
