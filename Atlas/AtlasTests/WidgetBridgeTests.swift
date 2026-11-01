#if canImport(SwiftData)
import SwiftData
import XCTest
@testable import Atlas

/// El puente con el widget. Lo que se prueba aquí es que la foto que publica la app se pueda
/// leer tal cual, y sobre todo que nada de esto reviente si el App Group no está disponible.
@MainActor
final class WidgetBridgeTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try ModelContainer(for: AtlasApp.schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
    }

    private func ejemplo() -> WidgetSnapshot {
        WidgetSnapshot(actualizado: Date(timeIntervalSince1970: 1_762_000_000),
                       kcalComidas: 1840, kcalObjetivo: 2300,
                       proteinaG: 128, proteinaObjetivoG: 180,
                       aguaMl: 1500, aguaObjetivoMl: 2500,
                       entrenoNombre: "Pierna", entrenoTipo: "strength",
                       entrenoHecho: false, rachaDias: 12)
    }

    func testLaFotoSobreviveAIrYVolverDeJSON() throws {
        let original = ejemplo()
        let datos = try JSONEncoder().encode(original)
        let vuelta = try JSONDecoder().decode(WidgetSnapshot.self, from: datos)
        XCTAssertEqual(original, vuelta)
    }

    /// El widget guarda el tipo de día como texto. Si ese texto no casa con SessionKind,
    /// el widget pintaría el icono equivocado.
    func testElTipoDeDiaViajaComoTextoQueSessionKindEntiende() {
        for k in SessionKind.allCases {
            XCTAssertEqual(SessionKind(rawValue: k.rawValue), k)
        }
        XCTAssertNotNil(SessionKind(rawValue: ejemplo().entrenoTipo))
    }

    /// Lo importante: publicar no puede romper la app aunque no haya carpeta compartida
    /// (que es lo que pasa si la firma no trae el permiso de App Group).
    func testPublicarNuncaRevientaAunqueNoHayaCarpetaCompartida() {
        DataStore.bootstrap(context)
        XCTAssertNoThrow(WidgetBridge.publicarHoy(context: context))
    }

    func testPublicarConDatosDeHoyNoFalla() {
        DataStore.bootstrap(context)
        DataStore.addWeight(80, waist: nil, date: Date(), in: context)
        _ = DataStore.changeWater(500, in: context)
        XCTAssertNoThrow(WidgetBridge.publicarHoy(context: context))
    }

    /// Si la app y el widget dejan de entenderse, el widget tiene que quedarse en blanco,
    /// no enseñar datos falsos.
    func testUnaFotoIlegibleSeDescartaEnVezDeInventarse() {
        let basura = Data("esto no es una foto".utf8)
        XCTAssertNil(try? JSONDecoder().decode(WidgetSnapshot.self, from: basura))
    }
}
#endif
