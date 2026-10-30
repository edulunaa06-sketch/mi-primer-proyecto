#if canImport(SwiftData)
import SwiftData
import XCTest
@testable import Atlas

/// Montar la semana a tu manera: decidir qué día es de fuerza, de carrera o de descanso,
/// sin perder el historial de lo ya entrenado.
@MainActor
final class WeekPlanTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try ModelContainer(for: AtlasApp.schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
    }

    /// El lunes viene de carrera y el martes de fuerza en la rutina de serie. Si esto cambiara,
    /// las pruebas de abajo dejarían de probar lo que creen probar.
    private var mondayRun: SessionDefinition { WeeklyRoutine.mondayRun }
    private var tuesdayStrength: SessionDefinition { WeeklyRoutine.tuesdayPushA }

    func testLaRutinaDeSerieEsLaQueEsperanEstasPruebas() {
        XCTAssertEqual(mondayRun.kind, .run)
        XCTAssertEqual(tuesdayStrength.kind, .strength)
    }

    // MARK: Cambiar el tipo de día

    func testSinCambiosCadaDiaMantieneSuTipo() {
        let resolved = mondayRun.resolved(with: [], titles: [], kinds: [])
        XCTAssertEqual(resolved.kind, .run)
    }

    func testUnDiaDeCarreraSePuedePasarAFuerzaConSusEjercicios() {
        let choice = SessionKindChoice(sessionID: mondayRun.id, kind: .strength)
        let mio = RoutineExercise(exerciseID: "custom-1", sessionID: mondayRun.id,
                                  name: "Sentadilla búlgara", sets: 4, repMin: 8, repMax: 10, order: 0)
        let resolved = mondayRun.resolved(with: [mio], titles: [], kinds: [choice])

        XCTAssertEqual(resolved.kind, .strength)
        XCTAssertEqual(resolved.exercises.map(\.name), ["Sentadilla búlgara"])
        XCTAssertEqual(resolved.exercises.first?.sets, 4)
        XCTAssertEqual(resolved.exercises.first?.repRange, "8–10")
    }

    func testUnDiaDeFuerzaPasadoADescansoSeQuedaSinEjercicios() {
        let choice = SessionKindChoice(sessionID: tuesdayStrength.id, kind: .rest)
        let mio = RoutineExercise(exerciseID: "custom-2", sessionID: tuesdayStrength.id,
                                  name: "Press banca", sets: 3, repMin: 6, repMax: 8, order: 0)
        let resolved = tuesdayStrength.resolved(with: [mio], titles: [], kinds: [choice])

        XCTAssertEqual(resolved.kind, .rest)
        XCTAssertTrue(resolved.exercises.isEmpty, "Un día de descanso no puede arrastrar ejercicios")
    }

    func testAlCambiarDeTipoSeBorraLaDescripcionDelDiaOriginal() {
        XCTAssertFalse(mondayRun.detail.isEmpty, "El lunes de serie trae una descripción de carrera")
        let choice = SessionKindChoice(sessionID: mondayRun.id, kind: .strength)
        let resolved = mondayRun.resolved(with: [], titles: [], kinds: [choice])
        XCTAssertTrue(resolved.detail.isEmpty,
                      "La descripción de correr no puede quedarse en un día que ahora es de fuerza")
    }

    func testElNombrePropioSobreviveAlCambioDeTipo() {
        let choice = SessionKindChoice(sessionID: mondayRun.id, kind: .strength)
        let title = SessionTitle(sessionID: mondayRun.id, title: "Glúteo")
        let resolved = mondayRun.resolved(with: [], titles: [title], kinds: [choice])

        XCTAssertEqual(resolved.title, "Glúteo")
        XCTAssertEqual(resolved.kind, .strength)
    }

    // MARK: Lo que cuenta para el cumplimiento

    func testUnDiaPuestoEnDescansoDejaDeContarComoEntrenoPendiente() {
        let antes = WeeklyRoutine.trainable().count
        let choice = SessionKindChoice(sessionID: tuesdayStrength.id, kind: .rest)
        let despues = WeeklyRoutine.trainable(kinds: [choice]).count

        XCTAssertEqual(despues, antes - 1, "Si lo pones en descanso, no te lo puede seguir exigiendo")
    }

    func testUnDescansoPuestoComoFuerzaSeSumaAlCumplimiento() {
        let antes = WeeklyRoutine.trainable().count
        let choice = SessionKindChoice(sessionID: WeeklyRoutine.fridayRest.id, kind: .strength)
        let despues = WeeklyRoutine.trainable(kinds: [choice]).count

        XCTAssertEqual(despues, antes + 1)
    }

    // MARK: Guardado

    func testGuardarElTipoYVolverALeerlo() {
        DataStore.setKind(.strength, for: mondayRun.id, in: context)
        let choices = DataStore.kindChoices(in: context)

        XCTAssertEqual(choices.count, 1)
        XCTAssertEqual(choices.first?.sessionID, mondayRun.id)
        XCTAssertEqual(choices.first?.kind, .strength)
    }

    func testVolverAlTipoOriginalNoDejaBasuraGuardada() {
        DataStore.setKind(.strength, for: mondayRun.id, in: context)
        XCTAssertEqual(DataStore.kindChoices(in: context).count, 1)

        // El lunes es de carrera de serie: volver a carrera debe borrar la excepción, no guardarla.
        DataStore.setKind(.run, for: mondayRun.id, in: context)
        XCTAssertTrue(DataStore.kindChoices(in: context).isEmpty)
    }

    func testCambiarDeIdeaDosVecesNoCreaDosRegistros() {
        DataStore.setKind(.strength, for: mondayRun.id, in: context)
        DataStore.setKind(.rest, for: mondayRun.id, in: context)

        let choices = DataStore.kindChoices(in: context)
        XCTAssertEqual(choices.count, 1)
        XCTAssertEqual(choices.first?.kind, .rest)
    }

    func testEmpezarDesdeCeroOlvidaLosTiposElegidos() {
        DataStore.setKind(.rest, for: tuesdayStrength.id, in: context)
        XCTAssertEqual(DataStore.kindChoices(in: context).count, 1)

        DataStore.startRoutineFromScratch(in: context)
        XCTAssertTrue(DataStore.kindChoices(in: context).isEmpty,
                      "«Desde cero» tiene que dejar la semana como recién instalada")
    }

    /// La copia de seguridad tiene que llevarse la semana montada. Si no, al restaurar
    /// aparecería otra vez la rutina de serie y habría que montarlo todo de nuevo.
    func testLaCopiaDeSeguridadSeLlevaLaSemanaMontada() throws {
        DataStore.setKind(.strength, for: mondayRun.id, in: context)
        DataStore.setKind(.rest, for: tuesdayStrength.id, in: context)

        let data = try BackupService.makeBackup(context).encoded()

        // Se deshacen los cambios…
        DataStore.setKind(.run, for: mondayRun.id, in: context)
        DataStore.setKind(.strength, for: tuesdayStrength.id, in: context)
        XCTAssertTrue(DataStore.kindChoices(in: context).isEmpty)

        // …y al restaurar vuelven.
        try BackupService.restore(try BackupFile.decode(data), into: context)
        let restored = Dictionary(uniqueKeysWithValues:
            DataStore.kindChoices(in: context).map { ($0.sessionID, $0.kind) })
        XCTAssertEqual(restored[mondayRun.id], .strength)
        XCTAssertEqual(restored[tuesdayStrength.id], .rest)
    }

    /// Una copia hecha ANTES de que existiera esto no trae el campo. Tiene que poder leerse igual.
    func testUnaCopiaAntiguaSinTiposDeDiaSeSigueLeyendo() throws {
        var file = try BackupFile(createdAt: Date(), appVersion: "1.0",
                                  settings: BackupService.makeBackup(context).settings)
        file.sessionKinds = nil
        let data = try file.encoded()

        XCTAssertNoThrow(try BackupFile.decode(data))
        try BackupService.restore(try BackupFile.decode(data), into: context)
        XCTAssertTrue(DataStore.kindChoices(in: context).isEmpty)
    }

    /// Lo importante de todo esto: cambiar el día NO puede tocar lo ya entrenado.
    func testCambiarElTipoDeDiaNoBorraElHistorial() {
        let weekStart = DateUtils.startOfWeek(Date())
        let log = WorkoutSessionLog(weekStart: weekStart, sessionID: tuesdayStrength.id)
        log.isCompleted = true
        context.insert(log)
        try? context.save()

        DataStore.setKind(.run, for: tuesdayStrength.id, in: context)

        let saved = (try? context.fetch(FetchDescriptor<WorkoutSessionLog>())) ?? []
        XCTAssertEqual(saved.count, 1)
        XCTAssertTrue(saved.first?.isCompleted == true)
        XCTAssertEqual(saved.first?.sessionID, tuesdayStrength.id)
    }
}
#endif
