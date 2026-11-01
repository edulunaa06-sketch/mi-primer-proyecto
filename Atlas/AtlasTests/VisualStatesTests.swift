import XCTest
@testable import Atlas

/// Estados de color de las calorías, celebraciones de racha y medallas nuevas.
final class VisualStatesTests: XCTestCase {
    func testCalorieStatusBands() {
        // Objetivo 2000 kcal, margen ±100.
        XCTAssertEqual(CalorieStatus.evaluate(consumed: 800, target: 2000, margin: 100), .plenty(left: 1200))
        XCTAssertEqual(CalorieStatus.evaluate(consumed: 1600, target: 2000, margin: 100), .approaching(left: 400))
        XCTAssertEqual(CalorieStatus.evaluate(consumed: 1899, target: 2000, margin: 100), .approaching(left: 101))
        XCTAssertEqual(CalorieStatus.evaluate(consumed: 1900, target: 2000, margin: 100), .onTarget(delta: -100))
        XCTAssertEqual(CalorieStatus.evaluate(consumed: 2000, target: 2000, margin: 100), .onTarget(delta: 0))
        // Un exceso pequeño, dentro del margen, sigue siendo verde.
        XCTAssertEqual(CalorieStatus.evaluate(consumed: 2060, target: 2000, margin: 100), .onTarget(delta: 60))
        XCTAssertEqual(CalorieStatus.evaluate(consumed: 2100, target: 2000, margin: 100), .onTarget(delta: 100))
        // Pasado el margen: rojo con el exceso exacto.
        XCTAssertEqual(CalorieStatus.evaluate(consumed: 2101, target: 2000, margin: 100), .over(excess: 101))
        XCTAssertEqual(CalorieStatus.evaluate(consumed: 2350, target: 2000, margin: 50), .over(excess: 350))
        // Sin objetivo: nada que juzgar.
        XCTAssertEqual(CalorieStatus.evaluate(consumed: 500, target: 0), .plenty(left: 0))
    }

    func testStreakFeedbackOnlyOncePerIncrease() {
        // Primera vez en este iPhone: no se celebra lo que ya había.
        XCTAssertEqual(StreakFeedback.evaluate(current: 12, best: 12, lastSeenCurrent: nil, lastSeenBest: nil), .none)
        // Misma racha que la última vez (abrir la app otra vez): nada.
        XCTAssertEqual(StreakFeedback.evaluate(current: 5, best: 9, lastSeenCurrent: 5, lastSeenBest: 9), .none)
        // Sube pero sin récord: llama animada.
        XCTAssertEqual(StreakFeedback.evaluate(current: 6, best: 9, lastSeenCurrent: 5, lastSeenBest: 9), .grew)
        // Supera la mejor marca anterior: récord.
        XCTAssertEqual(StreakFeedback.evaluate(current: 10, best: 10, lastSeenCurrent: 9, lastSeenBest: 9), .newRecord)
        // La primera racha de todas no es un «récord» (no había marca anterior).
        XCTAssertEqual(StreakFeedback.evaluate(current: 1, best: 1, lastSeenCurrent: 0, lastSeenBest: 0), .grew)
        // Se pierde: sin celebración.
        XCTAssertEqual(StreakFeedback.evaluate(current: 0, best: 10, lastSeenCurrent: 10, lastSeenBest: 10), .none)
    }

    func testMedalUnlocksAreCelebratedOnce() {
        let input = MedalInput(bestStreak: 8, strengthSessions: 12, weighIns: 3)
        let medals = Medals.all(input)
        // Primera vez: se guardan sin celebrar.
        XCTAssertTrue(MedalUnlocks.newlyUnlocked(medals, seen: nil).isEmpty)
        let seen = MedalUnlocks.updatedSeen(medals, seen: nil)
        XCTAssertEqual(seen["best-streak"], MedalTier.bronze.rawValue)
        XCTAssertTrue(MedalUnlocks.newlyUnlocked(medals, seen: seen).isEmpty, "No se repite")

        // Sube la racha a 30 días: solo esa medalla es nueva (plata).
        let better = Medals.all(MedalInput(bestStreak: 30, strengthSessions: 12, weighIns: 3))
        XCTAssertEqual(MedalUnlocks.newlyUnlocked(better, seen: seen).map(\.id), ["best-streak"])
        let seen2 = MedalUnlocks.updatedSeen(better, seen: seen)
        XCTAssertTrue(MedalUnlocks.newlyUnlocked(better, seen: seen2).isEmpty)
        // Aunque los datos bajen, lo visto no baja (no se vuelve a celebrar al recuperarlo).
        XCTAssertEqual(MedalUnlocks.updatedSeen(medals, seen: seen2)["best-streak"], MedalTier.silver.rawValue)
        XCTAssertTrue(MedalUnlocks.newlyUnlocked(better, seen: MedalUnlocks.updatedSeen(medals, seen: seen2)).isEmpty)
    }

    func testEveryMedalHasADescription() {
        for medal in Medals.all(MedalInput()) {
            XCTAssertFalse(medal.summary.isEmpty, medal.id)
            XCTAssertNotEqual(medal.summary, medal.source, "Descripción propia para \(medal.id)")
        }
    }
}
