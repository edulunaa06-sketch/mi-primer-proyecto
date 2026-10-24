import XCTest

/// Recorre la app como un usuario real en el simulador: perfil → objetivos calculados,
/// edición de rutina, registro de series, comidas y peso. Verifica lo que aparece en pantalla.
final class UserFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-NNSkipOnboarding"]
        app.launch()
    }

    private func tab(_ title: String) {
        let button = app.buttons[title].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Pestaña \(title)")
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
        let tabBarTop = app.buttons["Inicio"].firstMatch.exists ? app.buttons["Inicio"].firstMatch.frame.minY - 8 : .greatestFiniteMagnitude
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
        tab("Inicio")
        XCTAssertTrue(element(containing: "Objetivo 2550").waitForExistence(timeout: 5))
    }

    func test2_EditRoutineAndLogSets() {
        tab("Entreno")
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

        // Registrar la primera serie del primer ejercicio.
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        type("60", into: app.textFields["kg"].firstMatch)
        type("8", into: app.textFields["reps"].firstMatch)
        dismissKeyboard()
        app.buttons["Marcar serie terminada"].firstMatch.tap()
        app.buttons["Marcar ejercicio completado"].firstMatch.tap()
        XCTAssertTrue(element(containing: "1 de 7 ejercicios").waitForExistence(timeout: 5))

        // Progresión de cargas del ejercicio.
        scrollTo(app.buttons["Ver progresión de cargas"].firstMatch).tap()
        assertAppears(element(containing: "60 kg × 8"), "Mejor serie en la progresión")
    }

    func test3_MarkMealCompleted() {
        tab("Nutrición")
        let mark = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Marcar'")).firstMatch
        XCTAssertTrue(scrollTo(mark).exists)
        mark.tap()
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        XCTAssertTrue(element(containing: "1 de 4 comidas completadas").waitForExistence(timeout: 5))
    }

    func test4_BuildDayStepByStepAndSwap() {
        tab("Nutrición")
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
        tab("Nutrición")
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
        tab("Entreno")
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
        tab("Entreno")
        XCTAssertTrue(scrollTo(chest).exists)
        assertLabel(chest, contains: "hecha", "Se guarda al cerrar la app")
        assertLabel(run, contains: "pendiente", "La desmarcada sigue desmarcada")
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        assertAppears(element(containing: "1 de "), "Cuenta una sesión hecha en el resumen semanal")
    }

    func test7_StrengthSessionCompletesItself() {
        tab("Entreno")
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
        tab("Inicio")
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
        tab("Nutrición")
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
        for name in ["Inicio", "Entreno", "Nutrición", "Progreso", "Calendario", "Ajustes"] {
            tab(name)
            for _ in 0..<10 { app.swipeUp(velocity: .fast) }
            Thread.sleep(forTimeInterval: 1.5)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "final-\(name)"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }

    func testZ_FluidWithLotsOfData() {
        app.terminate()
        app.launchArguments = ["-NNSkipOnboarding", "-NNDemoData", "-NNFakeSteps", "-NNClearHangs"]
        app.launch()
        assertAppears(app.buttons["Progreso"].firstMatch, timeout: 60, "La app arranca con muchos datos")
        // Los 8 meses de datos se crean al arrancar: se espera a que estén (la racha deja de ser 0 en el calendario)
        // antes de medir, para medir las pantallas y no la creación de los datos.
        tab("Calendario")
        let loaded = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Mejor racha")).firstMatch
        assertAppears(loaded, timeout: 60, "Calendario con datos")
        _ = element(containing: "fallados").waitForExistence(timeout: 30)
        tab("Inicio")

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
        timed("Abrir Nutrición") { tab("Nutrición"); appears("Reajustar el resto del día") }
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
        timed("Abrir Inicio") { tab("Inicio"); appears("PASOS DE HOY") }
        timed("Abrir Entreno") { tab("Entreno"); appears("Historial") }
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
