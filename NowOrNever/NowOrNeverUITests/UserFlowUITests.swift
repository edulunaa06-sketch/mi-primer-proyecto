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
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
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
        let profile = element(containing: "Perfil personal")
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
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
        XCTAssertTrue(element(containing: "P 170 g").exists)

        // El peso del perfil queda en el historial de Progreso.
        app.navigationBars.buttons.firstMatch.tap()
        tab("Progreso")
        XCTAssertTrue(element(containing: "85,1 kg").waitForExistence(timeout: 5))

        // Inicio refleja el nuevo objetivo calórico.
        tab("Inicio")
        XCTAssertTrue(element(containing: "/ 2550 kcal").waitForExistence(timeout: 5))
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

        // Cuatro pasos: desayuno, comida, merienda y cena; en cada uno se elige la primera opción.
        for meal in ["desayuno", "comida", "merienda", "cena"] {
            assertAppears(element(containing: "Objetivo para tu \(meal)"), "Paso de \(meal)")
            let options = app.buttons.matching(NSPredicate(format: "label == %@", "Elegir esta opción"))
            XCTAssertGreaterThanOrEqual(options.count, 4, "Al menos 4 opciones de \(meal)")
            options.firstMatch.tap()
        }
        assertAppears(element(containing: "Resumen del día"), "Resumen")
        app.buttons["Guardar mi día"].tap()

        // Las comidas del día ahora son las elegidas y se pueden volver a cambiar.
        let swap = app.buttons["Cambiar comida"]
        XCTAssertTrue(scrollTo(swap).exists)
        swap.tap()
        assertAppears(element(containing: "Objetivo para tu comida"), "Selector de comida")
        app.buttons.matching(NSPredicate(format: "label == %@", "Elegir esta opción")).element(boundBy: 1).tap()
        XCTAssertTrue(scrollTo(app.buttons["Volver al menú"].firstMatch).exists)
    }
}
