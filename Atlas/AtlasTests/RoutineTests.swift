import XCTest
@testable import Atlas

final class RoutineTests: XCTestCase {
    func testSaturdayHasTwoSeparateSessions() {
        let saturday = WeeklyRoutine.sessions(forWeekday: 6)
        XCTAssertEqual(saturday.count, 2)
        XCTAssertEqual(saturday.map(\.kind), [.run, .strength])
        XCTAssertNotEqual(saturday[0].id, saturday[1].id)
    }

    func testFridayIsRestWithoutStrength() {
        let friday = WeeklyRoutine.sessions(forWeekday: 5)
        XCTAssertEqual(friday.count, 1)
        XCTAssertEqual(friday.first?.kind, .rest)
        XCTAssertTrue(friday.first?.exercises.isEmpty ?? false)
    }

    func testTrainableSessionsCount() {
        // Lunes, martes, miércoles, jueves, sábado (2) y domingo.
        XCTAssertEqual(WeeklyRoutine.trainableSessions.count, 7)
    }

    func testSessionIDsAndExerciseIDsAreUnique() {
        let ids = WeeklyRoutine.allSessions.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        let exIDs = WeeklyRoutine.allSessions.flatMap { $0.exercises.map(\.id) }
        XCTAssertEqual(Set(exIDs).count, exIDs.count)
    }

    func testPushAExactPrescription() {
        let push = WeeklyRoutine.tuesdayPushA.exercises
        XCTAssertEqual(push.map(\.name), [
            "Press de banca con barra",
            "Press inclinado con mancuernas",
            "Press de hombros en máquina",
            "Elevaciones laterales en polea",
            "Extensión de tríceps por encima de la cabeza",
            "Extensión de tríceps con cuerda",
        ])
        XCTAssertEqual(push.map(\.sets), [3, 3, 2, 3, 2, 2])
        XCTAssertEqual(push.map(\.repRange), ["6–10", "8–12", "8–12", "12–20", "10–15", "10–15"])
    }

    func testPullAExactPrescription() {
        let pull = WeeklyRoutine.wednesdayPullA.exercises
        XCTAssertEqual(pull.map(\.sets), [3, 3, 2, 3, 3, 2])
        XCTAssertEqual(pull.map(\.repRange), ["8–12", "8–12", "10–15", "12–20", "8–12", "10–15"])
        XCTAssertEqual(pull.first?.name, "Jalón al pecho con agarre neutro")
    }

    func testLegsExactPrescription() {
        let legs = WeeklyRoutine.thursdayLegs.exercises
        XCTAssertEqual(legs.map(\.name), ["Hack squat", "Peso muerto rumano", "Curl femoral sentado",
                                          "Extensión de cuádriceps", "Elevación de gemelos de pie", "Crunch en polea"])
        XCTAssertEqual(legs.map(\.sets), [3, 3, 3, 2, 3, 3])
        XCTAssertEqual(legs.map(\.repRange), ["6–10", "6–10", "10–15", "10–15", "10–15", "10–20"])
    }

    func testSaturdayChestBackExactPrescription() {
        let s = WeeklyRoutine.saturdayChestBack.exercises
        XCTAssertEqual(s.map(\.name), ["Press inclinado en multipower", "Remo sentado en polea", "Press de pecho en máquina",
                                       "Jalón con agarre neutro", "Aperturas en polea"])
        XCTAssertEqual(s.map(\.sets), [3, 3, 2, 3, 2])
        XCTAssertEqual(s.map(\.repRange), ["6–10", "8–12", "8–12", "8–12", "12–15"])
    }

    func testSundayExactPrescription() {
        let s = WeeklyRoutine.sundayShouldersArms.exercises
        XCTAssertEqual(s.count, 8)
        XCTAssertEqual(s.map(\.sets), [3, 2, 3, 2, 2, 2, 2, 2])
        XCTAssertEqual(s.map(\.repRange), ["12–20", "12–20", "8–12", "10–15", "10–15", "10–15", "12–15", "12–20"])
        XCTAssertEqual(s.last?.name, "Curl de muñeca")
    }

    func testRunDurations() {
        XCTAssertTrue(WeeklyRoutine.mondayRun.detail.contains("25 y 35"))
        XCTAssertTrue(WeeklyRoutine.saturdayRun.detail.contains("20 y 30"))
    }
}

final class DateUtilsTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        DateUtils.calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testWeekStartsOnMonday() {
        // 22/10/2026 es jueves → la semana empieza el lunes 19/10/2026.
        let start = DateUtils.startOfWeek(date(2026, 10, 22))
        XCTAssertEqual(DateUtils.dayKey(start), "2026-10-19")
        XCTAssertEqual(DateUtils.weekdayMondayBased(date(2026, 10, 22)), 4)
        // El domingo pertenece a la misma semana.
        XCTAssertEqual(DateUtils.weekKey(date(2026, 10, 25)), "2026-10-19")
        // El lunes siguiente empieza semana nueva (casillas limpias).
        XCTAssertEqual(DateUtils.weekKey(date(2026, 10, 26)), "2026-10-26")
    }

    func testParseDecimalAcceptsComma() {
        XCTAssertEqual(NumberFormat.parseDecimal("85,1"), 85.1)
        XCTAssertEqual(NumberFormat.parseDecimal(" 85.1 "), 85.1)
        XCTAssertNil(NumberFormat.parseDecimal(""))
        XCTAssertNil(NumberFormat.parseDecimal("abc"))
    }
}
