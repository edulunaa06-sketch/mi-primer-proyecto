import XCTest

/// Recorre la app como un usuario real en el simulador: perfil → objetivos calculados,
/// edición de rutina, marcar ejercicios, comidas y peso. Verifica lo que aparece en pantalla.
final class UserFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AtlasSkipOnboarding"]
        app.launch()
    }

    private static let barTabIDs = ["Hoy": "tab.home", "Comer": "tab.nutrition",
                                    "Entrenar": "tab.training", "Progreso": "tab.progress"]

    /// Va a una sección. Las cuatro de la barra tienen su botón; Calendario y Ajustes se abren
    /// desde los dos botones de la cabecera de Hoy.
    private func tab(_ title: String) {
        if let id = Self.barTabIDs[title] {
            let button = app.descendants(matching: .any).matching(identifier: id).firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 10), "Pestaña \(title)")
            button.tap()
            return
        }
        tab("Hoy")
        let id = title == "Calendario" ? "open.calendar" : "open.settings"
        let button = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Botón de \(title)")
        button.tap()
    }

    private func element(containing text: String) -> XCUIElement {
        // Sin distinguir mayúsculas: algunos títulos se muestran en MAYÚSCULAS.
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// Cierra el teclado numérico con el botón "Listo" de la barra del teclado.
    private func dismissKeyboard() {
        let done = app.toolbars.buttons["Listo"].firstMatch
        if done.exists { done.tap() }
    }

    /// Comprueba que aparece; si no, vuelca el árbol de accesibilidad al log para diagnosticar.
    private func assertAppears(_ element: XCUIElement, timeout: TimeInterval = 5, _ message: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        if !element.waitForExistence(timeout: timeout) {
            print("UI-DUMP \(message):\n\(app.debugDescription)")
            XCTFail(message, file: file, line: line)
        }
    }

    /// Desplaza hacia abajo hasta que el elemento sea pulsable.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 12) -> XCUIElement {
        var swipes = 0
        // Visible = pulsable y por encima de la barra de pestañas propia (que tapa la parte inferior).
        let bar = app.descendants(matching: .any).matching(identifier: "tab.home").firstMatch
        let tabBarTop = bar.exists ? bar.frame.minY - 8 : .greatestFiniteMagnitude
        func visible() -> Bool { element.exists && element.isHittable && element.frame.maxY < tabBarTop }
        while !visible() && swipes < maxSwipes {
            app.swipeUp(velocity: .slow)
            swipes += 1
        }
        // Espera a que termine la inercia: un toque durante el desplazamiento solo lo frena.
        if swipes > 0 { Thread.sleep(forTimeInterval: 1.0) }
        if !element.exists { print("UI-DUMP scroll:\n\(app.debugDescription)") }
        XCTAssertTrue(element.exists, "No se encontró \(element)")
        return element
    }

    private func type(_ text: String, into field: XCUIElement) {
        scrollTo(field).tap()
        if let current = field.value as? String, !current.isEmpty, current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    func test1_ProfileCalculatesTargets() {
        tab("Ajustes")
        // Consulta solo entre botones: más rápida que buscar en toda la pantalla.
        let profile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Perfil personal")).firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 20))
        profile.tap()

        type("85.1", into: app.textFields["kg"])
        type("180", into: app.textFields["cm"])
        type("30", into: app.textFields["años"])
        dismissKeyboard()
        scrollTo(app.buttons["Hombre"]).tap()

        // Vista previa calculada con Mifflin-St Jeor (actividad moderada, recomposición por defecto).
        XCTAssertTrue(scrollTo(element(containing: "2550 kcal")).exists)

        scrollTo(app.buttons["Guardar perfil"]).tap()
        assertAppears(element(containing: "Objetivos: 2550 kcal"), "Mensaje de objetivos guardados")
        XCTAssertTrue(element(containing: "P 191 g").exists)

        // El peso del perfil queda en el historial de Progreso.
        app.navigationBars.buttons.firstMatch.tap()
        tab("Progreso")
        XCTAssertTrue(element(containing: "85,1 kg").waitForExistence(timeout: 5))

        // Inicio refleja el nuevo objetivo calórico.
        tab("Hoy")
        let goal = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "2550", "Objetivo")).firstMatch
        XCTAssertTrue(goal.waitForExistence(timeout: 5), "Objetivo de 2550 kcal en Inicio")
    }

    func test2_EditRoutineAndTickExercises() {
        tab("Entrenar")
        let push = element(containing: "Push A")
        XCTAssertTrue(push.waitForExistence(timeout: 10))
        scrollTo(push).tap()

        app.buttons["Editar"].tap()
        let add = app.buttons["Añadir ejercicio"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let name = app.textFields["Nombre del ejercicio"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Fondos en paralelas")
        app.buttons["Guardar"].tap()
        XCTAssertTrue(element(containing: "Fondos en paralelas").waitForExistence(timeout: 5))
        app.buttons["Hecho"].tap()

        // El ejercicio nuevo aparece en la sesión.
        XCTAssertTrue(scrollTo(element(containing: "Fondos en paralelas")).exists)

        // ATLAS no pide kilos: basta con marcar el ejercicio.
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        XCTAssertFalse(app.buttons["Marcar serie terminada"].firstMatch.exists, "Ya no se marcan series sueltas")
        app.buttons["Marcar ejercicio completado"].firstMatch.tap()
        XCTAssertTrue(element(containing: "1 de 7 ejercicios").waitForExistence(timeout: 5))
    }

    func test3_MarkMealCompleted() {
        tab("Comer")
        let mark = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Marcar'")).firstMatch
        XCTAssertTrue(scrollTo(mark).exists)
        mark.tap()
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        XCTAssertTrue(element(containing: "1 de 4 comidas completadas").waitForExistence(timeout: 5))
    }

    func test4_BuildDayStepByStepAndSwap() {
        tab("Comer")
        let builder = app.buttons["Elegir mis comidas paso a paso"]
        XCTAssertTrue(builder.waitForExistence(timeout: 10))
        builder.tap()
        // Si la pulsación llega mientras la pantalla aún se está cargando, se repite una vez.
        if !element(containing: "Objetivo para tu desayuno").waitForExistence(timeout: 5) { builder.tap() }

        // Cuatro pasos: desayuno, almuerzo, merienda y cena; en cada uno se elige la primera opción.
        for meal in ["desayuno", "almuerzo", "merienda", "cena"] {
            assertAppears(element(containing: "Objetivo para tu \(meal)"), "Paso de \(meal)")
            let options = app.buttons.matching(NSPredicate(format: "label == %@", "Elegir esta opción"))
            XCTAssertGreaterThanOrEqual(options.count, 4, "Al menos 4 opciones de \(meal)")
            options.firstMatch.tap()
        }
        assertAppears(element(containing: "Resumen del día"), "Resumen")
        app.buttons["Guardar mi día"].tap()

        // Las comidas del día ahora son las elegidas y se pueden volver a cambiar.
        let swap = app.buttons["Cambiar almuerzo"]
        XCTAssertTrue(scrollTo(swap).exists)
        swap.tap()
        assertAppears(element(containing: "Objetivo para tu almuerzo"), "Selector de almuerzo")
        app.buttons.matching(NSPredicate(format: "label == %@", "Elegir esta opción")).element(boundBy: 1).tap()
        XCTAssertTrue(scrollTo(app.buttons["Volver al menú"].firstMatch).exists)
    }

    func test5_LogWhatIEatAndRebalance() {
        tab("Comer")
        let custom = app.buttons["Como otra cosa: apuntarla"].firstMatch
        XCTAssertTrue(scrollTo(custom).exists)
        custom.tap()
        assertAppears(element(containing: "Lo que como"), "Pantalla de comida libre")
        app.buttons["Manual"].tap()
        let name = app.textFields["Nombre (p. ej. bocadillo de lomo)"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Bocadillo de lomo")
        let numbers = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "0"))
        type("200", into: numbers.element(boundBy: 0))
        type("500", into: numbers.element(boundBy: 1))
        app.toolbars.buttons["Listo"].firstMatch.tap()
        scrollTo(app.buttons["Añadir"].firstMatch).tap()
        // Sin deslizar hacia abajo: en una hoja, ese gesto puede cerrarla.
        assertAppears(element(containing: "Total: 500 kcal"), "Total de lo apuntado")
        app.buttons["Hecho"].tap()

        assertAppears(element(containing: "Apuntado por ti"), "Tarjeta de comida libre")
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        let rebalance = app.buttons["Reajustar el resto del día a mis macros"]
        XCTAssertTrue(scrollTo(rebalance).exists)
        rebalance.tap()
        // Lo apuntado a mano no se reajusta. Si las otras comidas ya las elegiste tú (pruebas anteriores),
        // tampoco: entonces el mensaje dice que no queda nada que reajustar.
        let message = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Reajustado:", "No quedan comidas que reajustar")).firstMatch
        assertAppears(message, "Mensaje de reajuste")
    }

    private func sessionRow(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "session.\(id)").firstMatch
    }

    /// Arrastra la fila hacia la derecha `points` puntos y se queda quieto un momento antes de soltar (sin «lanzarla»).
    private func swipeRight(_ row: XCUIElement, points: CGFloat) {
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: points, dy: 0)),
                    withVelocity: 500, thenHoldForDuration: 0.2)
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func assertLabel(_ row: XCUIElement, contains text: String, _ message: String) {
        let ok = NSPredicate(format: "label CONTAINS %@", text)
        expectation(for: ok, evaluatedWith: row)
        waitForExpectations(timeout: 5) { error in
            if error != nil { print("UI-DUMP \(message): \(row.label)") }
        }
    }

    func test6_SwipeRightToCompleteSessions() {
        tab("Entrenar")
        let run = sessionRow("sat-run"), chest = sessionRow("sat-chest-back")
        XCTAssertTrue(scrollTo(chest).exists, "Fila de pecho y espalda del sábado")
        assertLabel(run, contains: "pendiente", "Carrera pendiente al empezar")
        assertLabel(chest, contains: "pendiente", "Pecho pendiente al empezar")

        // Un arrastre corto no cambia nada ni abre la sesión.
        swipeRight(run, points: 40)
        assertLabel(run, contains: "pendiente", "Arrastre corto: sigue pendiente")
        XCTAssertTrue(app.navigationBars["Entrenamientos"].exists, "Arrastrar no abre la sesión")

        // Deslizar del todo: cada actividad del mismo día por separado.
        swipeRight(run, points: 180)
        assertLabel(run, contains: "hecha", "Carrera hecha al deslizar")
        assertLabel(chest, contains: "pendiente", "El pecho sigue pendiente (son independientes)")
        XCTAssertTrue(app.navigationBars["Entrenamientos"].exists, "Deslizar no abre la sesión")
        swipeRight(chest, points: 180)
        assertLabel(chest, contains: "hecha", "Pecho hecho al deslizar")

        // El mismo gesto deshace.
        swipeRight(run, points: 180)
        assertLabel(run, contains: "pendiente", "Deslizar otra vez la desmarca")

        // Tocar sigue abriendo la sesión.
        run.tap()
        let back = app.navigationBars.buttons["Entrenamientos"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Tocar abre la sesión")
        back.tap()

        // Al cerrar y volver a abrir la app se mantiene.
        app.terminate()
        app.launch()
        tab("Entrenar")
        XCTAssertTrue(scrollTo(chest).exists)
        assertLabel(chest, contains: "hecha", "Se guarda al cerrar la app")
        assertLabel(run, contains: "pendiente", "La desmarcada sigue desmarcada")
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        assertAppears(element(containing: "1 de "), "Cuenta una sesión hecha en el resumen semanal")
    }

    func test7_StrengthSessionCompletesItself() {
        tab("Entrenar")
        let push = element(containing: "Push A")
        XCTAssertTrue(push.waitForExistence(timeout: 10))
        scrollTo(push).tap()
        XCTAssertFalse(app.buttons["Marcar sesión completa"].exists, "Ya no hay botón de completar en fuerza")
        var taps = 0
        while taps < 20 {
            let next = app.buttons["Marcar ejercicio completado"].firstMatch
            guard next.exists else { break }
            scrollTo(next).tap()
            taps += 1
        }
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        assertAppears(element(containing: "Sesión completada"), "Se completa sola al marcar todos los ejercicios")
    }

    func test8_CalendarMarkTodayAsWork() {
        tab("Calendario")
        let today = Date().formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "es_ES")))
        let cell = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", today + ":")).firstMatch
        assertAppears(cell, "Casilla de hoy en el calendario")
        cell.tap()
        let work = app.buttons["Trabajando"].firstMatch
        assertAppears(work, "Opción Trabajando")
        work.tap()
        app.buttons["Guardar"].firstMatch.tap()
        assertAppears(app.buttons.matching(NSPredicate(format: "label == %@", today + ": trabajando")).firstMatch,
                      "Hoy queda marcado como trabajando")
        // Inicio lo refleja en la racha.
        tab("Hoy")
        XCTAssertTrue(scrollTo(element(containing: "Hoy: trabajando")).exists)
    }

    func test9_ProgressSections() {
        tab("Progreso")
        app.buttons["Semana"].firstMatch.tap()
        assertAppears(element(containing: "Media de pasos"), "Resumen semanal")
        XCTAssertTrue(element(containing: "Días cumplidos").exists)
        app.buttons["Medallas"].firstMatch.tap()
        assertAppears(element(containing: "Carrera más larga"), "Medallas")
        app.buttons["Peso"].firstMatch.tap()
        // Con pesajes sale la gráfica; sin ninguno (si una prueba anterior no llegó a guardarlo), el aviso.
        let weight = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Línea verde", "Sin pesajes")).firstMatch
        assertAppears(weight, "Gráfica de peso")
    }

    func test10_RebalanceKeepsMealsIChanged() {
        tab("Comer")
        let swap = app.buttons["Cambiar cena"].firstMatch
        XCTAssertTrue(scrollTo(swap).exists)
        swap.tap()
        let pick = app.buttons["Elegir esta opción"].firstMatch
        assertAppears(pick, "Opciones de cena")
        pick.tap()
        assertAppears(element(containing: "Cambiada por ti"), "La cena queda marcada como cambiada por ti")
        app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown()
        let rebalance = app.buttons["Reajustar el resto del día a mis macros"]
        XCTAssertTrue(scrollTo(rebalance).exists)
        rebalance.tap()
        assertAppears(element(containing: "las cambiaste tú): cena"), "Reajustar no toca la cena cambiada")
    }

    /// Con 8 meses de datos y el sensor de pasos actualizándose 3 veces por segundo, cada pantalla
    /// tiene que abrirse y responder rápido (se ejecuta la última: deja esos datos para las capturas).
    /// Cada pestaña se baja hasta el final y se guarda una captura: lo último tiene que quedar por encima de la barra.
    func test11_ScrollToTheBottomOfEveryTab() {
        for name in ["Hoy", "Entrenar", "Comer", "Progreso", "Calendario", "Ajustes"] {
            tab(name)
            for _ in 0..<10 { app.swipeUp(velocity: .fast) }
            Thread.sleep(forTimeInterval: 1.5)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "final-\(name)"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }

    /// Colores con significado: estado de las calorías (con texto), racha con llama y medallas doradas o pendientes.
    func test12_VisualStates() {
        tab("Hoy")
        let status = app.descendants(matching: .any).matching(identifier: "kcal.status").firstMatch
        XCTAssertTrue(scrollTo(status).exists, "Estado de las calorías")
        let states = ["Margen amplio", "Te acercas al objetivo", "Objetivo cumplido", "Por encima del objetivo"]
        XCTAssertTrue(states.contains { status.label.contains($0) }, "Estado con texto, no solo color: \(status.label)")
        XCTAssertTrue(element(containing: "Proteínas").exists && element(containing: "Carbohidratos").exists
                      && element(containing: "Grasas").exists, "Los tres macros")
        XCTAssertTrue(scrollTo(element(containing: "Racha:")).exists, "Tarjeta de racha")
        tab("Progreso")
        app.buttons["Medallas"].firstMatch.tap()
        let medal = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Racha más larga:")).firstMatch
        assertAppears(medal, "Medalla de racha con su estado")
        XCTAssertTrue(medal.label.contains("pendiente") || medal.label.contains("Bronce") || medal.label.contains("Plata")
                      || medal.label.contains("Oro"), medal.label)
    }

    func testZ_FluidWithLotsOfData() {
        app.terminate()
        app.launchArguments = ["-AtlasSkipOnboarding", "-AtlasDemoData", "-AtlasFakeSteps", "-AtlasClearHangs"]
        app.launch()
        assertAppears(app.buttons["Progreso"].firstMatch, timeout: 60, "La app arranca con muchos datos")
        // Los 8 meses de datos se crean al arrancar: se espera a que estén (la racha deja de ser 0 en el calendario)
        // antes de medir, para medir las pantallas y no la creación de los datos.
        tab("Calendario")
        let loaded = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Mejor racha")).firstMatch
        assertAppears(loaded, timeout: 60, "Calendario con datos")
        _ = element(containing: "fallados").waitForExistence(timeout: 30)
        tab("Hoy")

        var slow: [String] = []
        func timed(_ name: String, limit: TimeInterval = 6, _ block: () -> Void) {
            let start = Date()
            block()
            let seconds = Date().timeIntervalSince(start)
            print("PERF \(name): \(String(format: "%.1f", seconds)) s")
            if seconds >= limit { slow.append("\(name) (\(String(format: "%.1f", seconds)) s)") }
        }
        func appears(_ text: String) {
            assertAppears(element(containing: text), timeout: 15, text)
        }

        timed("Abrir Progreso") { tab("Progreso"); appears("Línea verde") }
        timed("Semana") { app.buttons["Semana"].firstMatch.tap(); appears("Media de pasos") }
        timed("Medallas") { app.buttons["Medallas"].firstMatch.tap(); appears("Carrera más larga") }
        timed("Fotos") { app.buttons["Fotos"].firstMatch.tap(); appears("Privacidad") }
        timed("Peso") { app.buttons["Peso"].firstMatch.tap(); appears("Media mensual") }
        timed("Abrir Nutrición") { tab("Comer"); appears("Reajustar el resto del día") }
        // Cada deslizamiento tarda ~2,7 s en el simulador en cualquier pantalla (animación + espera del test).
        timed("Desplazar Nutrición", limit: 25) {
            for _ in 0..<3 { app.swipeUp() }
            for _ in 0..<3 { app.swipeDown() }
        }
        timed("Cambiar cena", limit: 30) {
            let swap = app.buttons["Cambiar cena"].firstMatch
            scrollTo(swap).tap()
            assertAppears(app.buttons["Elegir esta opción"].firstMatch, timeout: 10, "Opciones de cena")
            app.buttons["Cancelar"].firstMatch.tap()
        }
        timed("Abrir Calendario") { tab("Calendario"); appears("Racha actual") }
        timed("Mes anterior") { app.buttons["Mes anterior"].firstMatch.tap(); app.buttons["Mes anterior"].firstMatch.tap() }
        timed("Abrir Inicio") { tab("Hoy"); appears("PASOS DE HOY") }
        timed("Abrir Entreno") { tab("Entrenar"); appears("Historial") }
        timed("Volver a Progreso") { tab("Progreso"); appears("Línea verde") }

        // El detector de bloqueos de la propia app: ninguna pantalla congelada 2 s o más.
        tab("Ajustes")
        let diagnostics = element(containing: "Diagnóstico de fluidez")
        scrollTo(diagnostics)
        for _ in 0..<2 { app.swipeUp() }
        let hangs = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+,[0-9] s$")).allElementsBoundByIndex.map(\.label)
        print("HANGS detectados: \(hangs)")
        let long = hangs.compactMap { Double($0.replacingOccurrences(of: " s", with: "").replacingOccurrences(of: ",", with: ".")) }.filter { $0 >= 2 }
        XCTAssertTrue(long.isEmpty, "La app se congeló: \(hangs)")
        XCTAssertTrue(slow.isEmpty, "Pantallas lentas: \(slow.joined(separator: ", "))")
    }
}
