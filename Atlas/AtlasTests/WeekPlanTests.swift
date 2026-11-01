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

    func testEmpezarDesdeCeroDejaLaSemanaEnteraEnDescanso() {
        DataStore.setKind(.strength, for: mondayRun.id, in: context)
        DataStore.startRoutineFromScratch(in: context)

        // Ningún día puede quedar como entreno pendiente: la semana arranca en blanco.
        let kinds = DataStore.kindChoices(in: context)
        XCTAssertTrue(WeeklyRoutine.week(kinds: kinds).allSatisfy { $0.kind == .rest },
                      "Al empezar no puede venir ninguna rutina puesta")
        XCTAssertTrue(WeeklyRoutine.trainable(kinds: kinds).isEmpty)
    }

    func testEmpezarDesdeCeroDejaCadaDiaConSuNombre() {
        DataStore.startRoutineFromScratch(in: context)
        let titles = (try? context.fetch(FetchDescriptor<SessionTitle>())) ?? []
        XCTAssertEqual(mondayRun.renamed(titles).title, "Lunes")
        XCTAssertEqual(tuesdayStrength.renamed(titles).title, "Martes")
    }

    // MARK: Deportes

    func testLosTresPrimerosSonCarreraGimnasioYDescanso() {
        XCTAssertEqual(SessionKind.basics, [.run, .strength, .rest])
        XCTAssertEqual(SessionKind.basics.map(\.label), ["Carrera", "Gimnasio", "Descanso"])
        // Y los deportes son todo lo demás, sin solaparse.
        XCTAssertTrue(SessionKind.sports.allSatisfy { !SessionKind.basics.contains($0) })
        XCTAssertEqual(SessionKind.basics.count + SessionKind.sports.count, SessionKind.allCases.count)
    }

    func testUnDeporteSeComportaComoLaCarreraPeroConSuNombre() {
        for k in SessionKind.sports {
            XCTAssertTrue(k.isSport, "\(k.label) debería gestionarse como un deporte")
        }
        XCTAssertTrue(SessionKind.run.isSport)
        XCTAssertFalse(SessionKind.strength.isSport)
        XCTAssertFalse(SessionKind.rest.isSport)
    }

    /// Los tipos de Strava tienen que ser los de su lista oficial, o no se importaría nada.
    func testLosTiposDeStravaSonLosReales() {
        XCTAssertEqual(SessionKind.cycling.manualStravaType, "Ride", "Ordenar el conjunto daría EBikeRide")
        XCTAssertTrue(SessionKind.cycling.stravaTypes.contains("Ride"))
        XCTAssertTrue(SessionKind.swimming.stravaTypes.contains("Swim"))
        XCTAssertTrue(SessionKind.football.stravaTypes.contains("Soccer"))
        XCTAssertTrue(SessionKind.padel.stravaTypes.contains("Padel"))
        XCTAssertTrue(SessionKind.run.stravaTypes.contains("TrailRun"))
    }

    /// MMA y boxeo no existen en Strava. Mapearlos a «Workout» colaría como MMA cualquier
    /// entreno suelto importado, así que van vacíos y solo se apuntan a mano.
    func testMMAyBoxeoNoSeImportanDeStrava() {
        XCTAssertTrue(SessionKind.mma.stravaTypes.isEmpty)
        XCTAssertTrue(SessionKind.boxing.stravaTypes.isEmpty)
        XCTAssertEqual(SessionKind.mma.manualStravaType, "MMA")
        XCTAssertEqual(SessionKind.boxing.manualStravaType, "Boxing")
    }

    func testCadaDeporteSoloVeLoSuyo() {
        // Lo que se apunta a mano de un deporte no puede aparecer en otro.
        XCTAssertTrue(SessionKind.mma.activityTypes.contains("MMA"))
        XCTAssertFalse(SessionKind.run.activityTypes.contains("MMA"))
        XCTAssertFalse(SessionKind.cycling.activityTypes.contains("Run"))
        XCTAssertTrue(SessionKind.run.activityTypes.contains("Run"))
    }

    func testSoloSePidenKilometrosDondeTienenSentido() {
        XCTAssertTrue(SessionKind.run.hasDistance)
        XCTAssertTrue(SessionKind.cycling.hasDistance)
        XCTAssertTrue(SessionKind.swimming.hasDistance)
        XCTAssertFalse(SessionKind.mma.hasDistance, "De un entreno de MMA se apunta el tiempo")
        XCTAssertFalse(SessionKind.football.hasDistance)
        XCTAssertFalse(SessionKind.strength.hasDistance)
    }

    func testTodoTipoTieneNombreEIcono() {
        for k in SessionKind.allCases {
            XCTAssertFalse(k.label.isEmpty, "\(k.rawValue) sin nombre")
            XCTAssertFalse(k.symbol.isEmpty, "\(k.rawValue) sin icono")
        }
    }

    func testUnDiaPuestoEnFutbolCuentaComoEntreno() {
        let choice = SessionKindChoice(sessionID: WeeklyRoutine.fridayRest.id, kind: .football)
        let semana = WeeklyRoutine.week(kinds: [choice])
        let viernes = semana.first { $0.id == WeeklyRoutine.fridayRest.id }

        XCTAssertEqual(viernes?.kind, .football)
        XCTAssertTrue(WeeklyRoutine.trainable(kinds: [choice]).contains { $0.id == WeeklyRoutine.fridayRest.id })
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
