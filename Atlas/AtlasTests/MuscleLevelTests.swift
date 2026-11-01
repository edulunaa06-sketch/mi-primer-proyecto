import XCTest
@testable import Atlas

/// Rango de cada músculo y dibujo del cuerpo.
final class MuscleLevelTests: XCTestCase {

    override func tearDown() {
        ExerciseCatalog.clearCustom()
        super.tearDown()
    }

    // MARK: Puntos y rangos

    func testWithoutAnythingLoggedEveryMuscleIsNovato() {
        let status = MuscleLevel.status(for: .init(group: .chest, directSets: 0))
        XCTAssertEqual(status.rank, .novato)
        XCTAssertEqual(status.points, 0)
        XCTAssertEqual(status.nextRank, .iniciado)
        XCTAssertEqual(status.pointsToNext, 4)
    }

    func testEachMuscleHasItsOwnProductiveWeek() {
        // El pecho necesita más series semanales que los oblicuos para el mismo punto.
        XCTAssertEqual(MuscleLevel.weeklyUnit(for: .chest), 10)
        XCTAssertEqual(MuscleLevel.weeklyUnit(for: .obliques), 4)
        XCTAssertGreaterThanOrEqual(MuscleLevel.weeklyUnit(for: .forearms), 4)
    }

    func testFourProductiveWeeksReachIniciado() {
        // 40 series de pecho repartidas en 4 semanas = 4 puntos.
        let status = MuscleLevel.status(for: .init(group: .chest, directSets: 40, weeksTrained: 4))
        XCTAssertEqual(status.points, 4, accuracy: 0.001)
        XCTAssertEqual(status.rank, .iniciado)
    }

    func testPilingUpSetsInOneWeekDoesNotCountAsMonthsOfWork() {
        let crammed = MuscleLevel.status(for: .init(group: .chest, directSets: 120, weeksTrained: 1))
        let spread = MuscleLevel.status(for: .init(group: .chest, directSets: 120, weeksTrained: 12))
        XCTAssertEqual(crammed.points, 1.5, accuracy: 0.001)
        XCTAssertEqual(spread.points, 12, accuracy: 0.001)
        XCTAssertLessThan(crammed.rank.rawValue, spread.rank.rawValue)
    }

    func testLiftingMoreWeightSpeedsUpTheRank() {
        let flat = MuscleLevel.status(for: .init(group: .chest, directSets: 100, weeksTrained: 10, strengthGain: 1))
        let better = MuscleLevel.status(for: .init(group: .chest, directSets: 100, weeksTrained: 10, strengthGain: 1.5))
        XCTAssertEqual(flat.points, 10, accuracy: 0.001)
        XCTAssertEqual(better.points, 12.5, accuracy: 0.001)
        XCTAssertEqual(better.strengthBonus, 0.25, accuracy: 0.001)
    }

    func testTheStrengthBonusIsCapped() {
        XCTAssertEqual(MuscleLevel.strengthBonus(gain: 10), 0.25, accuracy: 0.001)
        XCTAssertEqual(MuscleLevel.strengthBonus(gain: 0.5), 0)
        XCTAssertEqual(MuscleLevel.strengthBonus(gain: nil), 0)
    }

    func testRanksFollowTheirThresholds() {
        XCTAssertEqual(MuscleLevel.Rank.rank(forPoints: 0), .novato)
        XCTAssertEqual(MuscleLevel.Rank.rank(forPoints: 3.9), .novato)
        XCTAssertEqual(MuscleLevel.Rank.rank(forPoints: 12), .intermedio)
        XCTAssertEqual(MuscleLevel.Rank.rank(forPoints: 51), .avanzado)
        XCTAssertEqual(MuscleLevel.Rank.rank(forPoints: 500), .elite)
        XCTAssertNil(MuscleLevel.Rank.elite.next)
    }

    func testEliteIsFullAndSaysSo() {
        let status = MuscleLevel.status(for: .init(group: .chest, directSets: 2000, weeksTrained: 200))
        XCTAssertEqual(status.rank, .elite)
        XCTAssertEqual(status.progress, 1)
        XCTAssertNil(status.pointsToNext)
        XCTAssertTrue(status.advice.contains("máximo"))
    }

    func testTheAdviceSaysHowManySetsAreLeft() {
        let status = MuscleLevel.status(for: .init(group: .chest, directSets: 20, weeksTrained: 4))
        XCTAssertEqual(status.points, 2, accuracy: 0.001)
        // Faltan 2 puntos × 10 series = 20 series.
        XCTAssertTrue(status.advice.contains("20"), status.advice)
    }

    // MARK: A partir de lo registrado

    private func work(_ exerciseID: String, _ name: String, day: Int, sets: Int, volume: Double,
                      e1rm: Double? = nil) -> VolumeAnalytics.ExerciseWork {
        VolumeAnalytics.ExerciseWork(exerciseID: exerciseID, name: name,
                                     date: Date(timeIntervalSince1970: Double(day) * 86_400),
                                     workSets: sets, volumeKg: volume, totalReps: sets * 10,
                                     estimatedOneRepMax: e1rm)
    }

    func testTheWholeBodyIsCalculatedFromWhatIsLogged() {
        let statuses = MuscleLevel.statuses(work: [
            work("bench-barbell", "Press de banca con barra", day: 0, sets: 4, volume: 1600, e1rm: 100),
            work("bench-barbell", "Press de banca con barra", day: 30, sets: 4, volume: 1800, e1rm: 110),
        ])
        XCTAssertEqual(statuses.count, MuscleGroup.allCases.count)
        let chest = statuses.first { $0.group == .chest }
        XCTAssertEqual(chest?.directSets, 8)
        XCTAssertEqual(chest?.tonnageKg, 3400)
        XCTAssertEqual(chest?.weeksTrained, 2)
        XCTAssertGreaterThan(chest?.strengthBonus ?? 0, 0, "Si los pesos suben, tiene que notarse")
        XCTAssertEqual(statuses.first { $0.group == .calves }?.rank, .novato)
    }

    func testExercisesThatAreNotInTheLibraryDoNotInventAMuscle() {
        let statuses = MuscleLevel.statuses(work: [
            work("custom-1", "Un invento mío sin ficha", day: 0, sets: 10, volume: 1000),
        ])
        XCTAssertTrue(statuses.allSatisfy { $0.directSets == 0 })
    }

    func testGainComparesEachExerciseWithItself() {
        let date = Date()
        // Uno sube de 100 a 120 (1,2) y otro se queda igual (1): la media es 1,1.
        let gain = MuscleLevel.gain([
            "a": (first: 100, firstDate: date, best: 120),
            "b": (first: 50, firstDate: date, best: 50),
        ])
        XCTAssertEqual(gain ?? 0, 1.1, accuracy: 0.0001)
        XCTAssertNil(MuscleLevel.gain(nil))
        XCTAssertNil(MuscleLevel.gain([:]))
    }

    func testTheWeakestMusclesComeFirst() {
        let statuses = MuscleLevel.statuses(work: [
            work("bench-barbell", "Press de banca con barra", day: 0, sets: 20, volume: 8000),
        ])
        let weakest = MuscleLevel.weakest(statuses, limit: 3)
        XCTAssertEqual(weakest.count, 3)
        XCTAssertFalse(weakest.contains { $0.group == .chest })
    }

    func testCustomExercisesAlsoMoveTheirMusclesRank() {
        ExerciseCatalog.useCustom([
            CustomExerciseRules.info(id: "mio-1", name: "Jalón espalda alta", primary: .upperBack,
                                     secondary: [], pattern: .verticalPull, equipment: .cable,
                                     unilateral: false, sets: 3, repMin: 8, repMax: 12, note: "", aliases: []),
        ])
        let statuses = MuscleLevel.statuses(work: [
            work("custom-zzz", "Jalón espalda alta", day: 0, sets: 10, volume: 2000),
        ])
        XCTAssertEqual(statuses.first { $0.group == .upperBack }?.directSets, 10)
    }

    // MARK: El dibujo del cuerpo

    func testEveryMuscleIsDrawnSomewhere() {
        XCTAssertTrue(BodyMap.notDrawn.isEmpty, "Faltan por dibujar: \(BodyMap.notDrawn.map(\.label))")
    }

    func testAllThePointsAreInsideTheCanvas() {
        for piece in BodyMap.silhouettePieces + BodyMap.pieces(.front) + BodyMap.pieces(.back) {
            XCTAssertGreaterThanOrEqual(piece.points.count, 3, piece.name)
            for point in piece.points {
                XCTAssertTrue((0...1).contains(point.x), "\(piece.name) se sale por x: \(point.x)")
                XCTAssertTrue((0...1).contains(point.y), "\(piece.name) se sale por y: \(point.y)")
            }
        }
    }

    func testTheBodyIsSymmetrical() {
        let front = BodyMap.pieces(.front)
        // Cada pieza reflejada tiene su pareja.
        let mirrored = front.filter { $0.name.hasSuffix("-izq") }
        XCTAssertFalse(mirrored.isEmpty)
        for piece in mirrored {
            let original = String(piece.name.dropLast(4))
            XCTAssertTrue(front.contains { $0.name == original }, "Falta el original de \(piece.name)")
        }
    }

    func testPiecesHaveUniqueNames() {
        for side in BodyMap.Side.allCases {
            let names = BodyMap.pieces(side).map(\.name)
            XCTAssertEqual(Set(names).count, names.count, "Nombres repetidos en \(side.label)")
        }
    }

    func testBothSidesShowTheMusclesYouExpect() {
        XCTAssertTrue(BodyMap.visibleMuscles(.front).contains(.chest))
        XCTAssertTrue(BodyMap.visibleMuscles(.front).contains(.quads))
        XCTAssertTrue(BodyMap.visibleMuscles(.back).contains(.lats))
        XCTAssertTrue(BodyMap.visibleMuscles(.back).contains(.glutes))
        XCTAssertFalse(BodyMap.visibleMuscles(.front).contains(.lats))
    }
}
