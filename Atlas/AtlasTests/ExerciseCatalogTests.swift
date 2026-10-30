import XCTest
@testable import Atlas

/// Pruebas de la biblioteca de ejercicios: que no haya fichas duplicadas ni incompletas,
/// que la rutina predeterminada esté cubierta y que las sustituciones tengan sentido.
final class ExerciseCatalogTests: XCTestCase {

    func testNoDuplicateIdentifiers() {
        var seen = Set<String>()
        for info in ExerciseCatalog.all {
            XCTAssertTrue(seen.insert(info.id).inserted, "Identificador repetido: \(info.id)")
            for alias in info.aliases {
                XCTAssertTrue(seen.insert(alias).inserted, "Alias repetido: \(alias)")
            }
        }
    }

    func testNoDuplicateNames() {
        var seen = Set<String>()
        for info in ExerciseCatalog.all {
            let key = ExerciseCatalog.normalize(info.name)
            XCTAssertTrue(seen.insert(key).inserted, "Nombre repetido: \(info.name)")
        }
    }

    func testEveryEntryIsComplete() {
        for info in ExerciseCatalog.all {
            XCTAssertFalse(info.name.isEmpty, "\(info.id) sin nombre")
            XCTAssertFalse(info.execution.isEmpty, "\(info.id) sin instrucciones")
            XCTAssertFalse(info.mistakes.isEmpty, "\(info.id) sin errores frecuentes")
            XCTAssertFalse(info.trait.isEmpty, "\(info.id) sin explicación de en qué se diferencia")
            XCTAssertGreaterThan(info.defaultSets, 0, "\(info.id) con 0 series")
            XCTAssertGreaterThanOrEqual(info.defaultRepMax, info.defaultRepMin, "\(info.id) con rango invertido")
            // El músculo principal no puede repetirse entre los secundarios.
            XCTAssertFalse(info.secondary.contains(info.primary), "\(info.id) repite el músculo principal")
        }
    }

    func testEveryDefaultRoutineExerciseHasACatalogEntry() {
        let exercises = WeeklyRoutine.allSessions.flatMap(\.exercises)
        XCTAssertFalse(exercises.isEmpty)
        for exercise in exercises {
            XCTAssertNotNil(ExerciseCatalog.info(id: exercise.id, name: exercise.name),
                            "La rutina usa «\(exercise.name)» (\(exercise.id)) y no está en la biblioteca")
        }
    }

    func testRoutineIdentifiersAreResolvedWithoutTheWeekdayPrefix() {
        XCTAssertEqual(ExerciseCatalog.canonicalID("tue-bench-barbell"), "bench-barbell")
        XCTAssertEqual(ExerciseCatalog.canonicalID("sun-wrist-curl"), "wrist-curl")
        // Un identificador sin prefijo de día se queda igual.
        XCTAssertEqual(ExerciseCatalog.canonicalID("bench-barbell"), "bench-barbell")
        XCTAssertEqual(ExerciseCatalog.canonicalID("custom-1234"), "custom-1234")
        XCTAssertEqual(ExerciseCatalog.info(id: "tue-bench-barbell")?.id, "bench-barbell")
    }

    func testAliasesPointToTheSameExercise() {
        // La rutina llama al jalón neutro de dos formas según el día.
        let a = ExerciseCatalog.info(id: "wed-neutral-lat-pulldown")
        let b = ExerciseCatalog.info(id: "sat-neutral-pulldown")
        XCTAssertNotNil(a)
        XCTAssertEqual(a?.id, b?.id)
    }

    func testLookupByNameIgnoresAccentsAndCase() {
        XCTAssertNotNil(ExerciseCatalog.info(named: "press de banca con barra"))
        XCTAssertNotNil(ExerciseCatalog.info(named: "PRESS DE BANCA CON BARRA"))
        XCTAssertNotNil(ExerciseCatalog.info(named: "Hack squat"))
        XCTAssertNil(ExerciseCatalog.info(named: "Ejercicio que no existe"))
    }

    func testCustomExerciseFallsBackToItsName() {
        let info = ExerciseCatalog.info(id: "custom-9999", name: "Press de banca con barra")
        XCTAssertEqual(info?.id, "bench-barbell")
        XCTAssertNil(ExerciseCatalog.info(id: "custom-9999", name: "Mi invento"))
    }

    func testSearchFiltersByMusclePatternAndEquipment() {
        let chest = ExerciseCatalog.search("", muscle: .chest)
        XCTAssertFalse(chest.isEmpty)
        XCTAssertTrue(chest.allSatisfy { $0.allMuscles.contains(.chest) })

        let barbellPushes = ExerciseCatalog.search("", pattern: .horizontalPush, equipment: .barbell)
        XCTAssertTrue(barbellPushes.allSatisfy { $0.pattern == .horizontalPush && $0.equipment == .barbell })

        let byText = ExerciseCatalog.search("banca")
        XCTAssertTrue(byText.contains { $0.id == "bench-barbell" })

        // Sin resultados no se devuelve nada en lugar de algo aproximado.
        XCTAssertTrue(ExerciseCatalog.search("zzzz").isEmpty)
    }

    func testByMuscleOnlyReturnsExercisesWhereItIsThePrimaryOne() {
        let triceps = ExerciseCatalog.byMuscle(.triceps)
        XCTAssertFalse(triceps.isEmpty)
        XCTAssertTrue(triceps.allSatisfy { $0.primary == .triceps })
        // El press de banca trabaja el tríceps, pero no es un ejercicio de tríceps.
        XCTAssertFalse(triceps.contains { $0.id == "bench-barbell" })
    }

    func testEveryMuscleGroupHasAtLeastOneExercise() {
        for group in MuscleGroup.allCases {
            XCTAssertFalse(ExerciseCatalog.byMuscle(group).isEmpty,
                           "No hay ningún ejercicio cuyo músculo principal sea \(group.label)")
        }
    }

    func testAlternativesKeepThePrimaryMuscle() {
        let bench = ExerciseCatalog.info(id: "bench-barbell")!
        let alternatives = ExerciseCatalog.alternatives(to: bench)
        XCTAssertFalse(alternatives.isEmpty)
        XCTAssertTrue(alternatives.allSatisfy { $0.primary == .chest })
        // Un ejercicio nunca es alternativa de sí mismo.
        XCTAssertFalse(alternatives.contains { $0.id == bench.id })
        // Los del mismo patrón van primero.
        XCTAssertEqual(alternatives.first?.pattern, bench.pattern)
    }

    func testAlternativesCanBeFilteredByAvailableEquipment() {
        let bench = ExerciseCatalog.info(id: "bench-barbell")!
        let onlyMachines = ExerciseCatalog.alternatives(to: bench, equipment: .machine)
        XCTAssertFalse(onlyMachines.isEmpty)
        XCTAssertTrue(onlyMachines.allSatisfy { $0.equipment == .machine })
    }

    func testAlternativesForARoutineIdentifier() {
        let alternatives = ExerciseCatalog.alternatives(forRoutineID: "thu-hack-squat")
        XCTAssertFalse(alternatives.isEmpty)
        XCTAssertTrue(alternatives.allSatisfy { $0.primary == .quads })
        XCTAssertTrue(ExerciseCatalog.alternatives(forRoutineID: "custom-0000", name: "Nada").isEmpty)
    }

    func testDifferenceNeverClaimsTwoExercisesAreIdentical() {
        let bench = ExerciseCatalog.info(id: "bench-barbell")!
        for other in ExerciseCatalog.alternatives(to: bench) {
            let notes = ExerciseCatalog.difference(from: bench, to: other)
            XCTAssertFalse(notes.isEmpty, "Sin diferencias explicadas entre \(bench.name) y \(other.name)")
            XCTAssertFalse(notes.joined().lowercased().contains("idéntic"))
        }
    }

    func testDifferenceMentionsTheChangeOfEquipment() {
        let bench = ExerciseCatalog.info(id: "bench-barbell")!
        let machine = ExerciseCatalog.info(id: "machine-chest-press")!
        let notes = ExerciseCatalog.difference(from: bench, to: machine).joined(separator: " ")
        XCTAssertTrue(notes.contains("Barra"))
        XCTAssertTrue(notes.contains("Máquina"))
    }

    func testDifferenceMentionsWhenItBecomesOneSideAtATime() {
        let row = ExerciseCatalog.info(id: "chest-supported-row")!
        let oneArm = ExerciseCatalog.info(id: "db-row")!
        let notes = ExerciseCatalog.difference(from: row, to: oneArm).joined(separator: " ")
        XCTAssertTrue(notes.contains("lado"))
    }

    func testUnilateralExercisesAreMarked() {
        XCTAssertTrue(ExerciseCatalog.info(id: "db-row")!.isUnilateral)
        XCTAssertTrue(ExerciseCatalog.info(id: "bulgarian-split-squat")!.isUnilateral)
        XCTAssertFalse(ExerciseCatalog.info(id: "bench-barbell")!.isUnilateral)
    }

    func testDefaultRepRangeIsReadable() {
        XCTAssertEqual(ExerciseCatalog.info(id: "bench-barbell")!.defaultRepRange, "6–10")
        XCTAssertEqual(ExerciseCatalog.info(id: "plank")!.defaultRepRange, "1")
    }

    func testMusclesKnowTheirRegion() {
        XCTAssertEqual(MuscleGroup.chest.region, .push)
        XCTAssertEqual(MuscleGroup.lats.region, .pull)
        XCTAssertEqual(MuscleGroup.quads.region, .legs)
        XCTAssertEqual(MuscleGroup.abs.region, .core)
        // Todos los grupos caen en alguna región y tienen nombre.
        for group in MuscleGroup.allCases {
            XCTAssertFalse(group.label.isEmpty)
            XCTAssertFalse(group.shortLabel.isEmpty)
            XCTAssertTrue(MuscleRegion.allCases.contains(group.region))
        }
    }

    func testEveryEquipmentExplainsWhatItChanges() {
        for equipment in Equipment.allCases {
            XCTAssertFalse(equipment.label.isEmpty)
            XCTAssertFalse(equipment.trait.isEmpty, "\(equipment.rawValue) sin explicación")
            XCTAssertFalse(equipment.symbol.isEmpty)
        }
    }

    func testEveryPatternHasALabel() {
        for pattern in MovementPattern.allCases {
            XCTAssertFalse(pattern.label.isEmpty)
        }
    }
}
