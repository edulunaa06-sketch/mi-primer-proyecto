import XCTest

/// Recorre ATLAS como una persona real en el simulador.
final class AtlasFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ extra: [String] = []) {
        app.launchArguments = ["-AtlasInMemory", "-AtlasSkipIntro"] + extra
        app.launch()
    }

    private func el(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func containing(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func tab(_ title: String) {
        let b = app.buttons[title].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 10), "Pestaña \(title)")
        b.tap()
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    @discardableResult
    private func scrollTo(_ e: XCUIElement, max: Int = 10) -> XCUIElement {
        var n = 0
        while !(e.exists && e.isHittable) && n < max { app.swipeUp(velocity: .slow); n += 1 }
        if n > 0 { Thread.sleep(forTimeInterval: 0.8) }
        XCTAssertTrue(e.exists, "No se encontró \(e)")
        return e
    }

    func test1_OnboardingBuildsThePlan() {
        launch()
        let next = el("onboarding.next")
        XCTAssertTrue(next.waitForExistence(timeout: 15), "Bienvenida")
        shot("onboarding-1")
        next.tap()
        let name = el("onboarding.name")
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Edu")
        app.swipeDown()
        next.tap()
        shot("onboarding-3")
        next.tap()
        XCTAssertTrue(containing("kcal al día").waitForExistence(timeout: 5), "Plan calculado")
        shot("onboarding-4")
        next.tap()
        XCTAssertTrue(el("kcal.left").waitForExistence(timeout: 10), "Llega a Hoy")
        XCTAssertTrue(containing("Edu").exists, "Saluda por el nombre")
    }

    func test2_LogFoodUpdatesCalories() {
        launch(["-AtlasSkipOnboarding"])
        let left = el("kcal.left")
        XCTAssertTrue(left.waitForExistence(timeout: 10))
        let before = left.label
        tab("Comer")
        let add = el("add.lunch")
        XCTAssertTrue(scrollTo(add).exists)
        add.tap()
        let search = el("food.search")
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("pollo")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "pollo")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Resultado de pollo")
        row.tap()
        let addButton = el("amount.add")
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        shot("food-amount")
        addButton.tap()
        tab("Hoy")
        XCTAssertTrue(left.waitForExistence(timeout: 5))
        XCTAssertNotEqual(left.label, before, "Las calorías libres cambian al apuntar")
    }

    func test3_MenuOfDishes() {
        launch(["-AtlasSkipOnboarding"])
        tab("Comer")
        el("food.menus").tap()
        let first = containing("kcal").firstMatch
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Menú")).firstMatch.waitForExistence(timeout: 8), "Platos de los menús")
        shot("menus")
        _ = first
        let card = app.buttons.matching(identifier: "dish.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        let addDish = el("dish.add")
        XCTAssertTrue(addDish.waitForExistence(timeout: 5))
        shot("dish")
        addDish.tap()
        XCTAssertTrue(el("kcal.left").waitForExistence(timeout: 8))
    }

    func test4_LiveWorkoutWithCoachAndRecords() {
        launch(["-AtlasDemo", "-AtlasLive"])
        let check = el("set.check")
        XCTAssertTrue(check.waitForExistence(timeout: 20), "Entreno en curso")
        XCTAssertTrue(el("coach.suggestion").exists, "El coach sugiere el peso de hoy")
        shot("live")
        check.tap()
        Thread.sleep(forTimeInterval: 0.8)
        XCTAssertFalse(el("rest.time").exists, "Ya no hay cuenta atrás de descanso")
        shot("live-set-done")
        let finish = el("live.finish")
        scrollTo(finish)
        finish.tap()
        let done = el("summary.done")
        XCTAssertTrue(done.waitForExistence(timeout: 8), "Resumen del entreno")
        shot("summary")
        done.tap()
    }

    func test5_WaterWeightAndProgress() {
        launch(["-AtlasDemo"])
        tab("Progreso")
        XCTAssertTrue(el("expenditure").waitForExistence(timeout: 10))
        shot("progress-body")
        for (i, area) in ["Fuerza", "Carrera", "Constancia"].enumerated() {
            app.buttons[area].firstMatch.tap()
            Thread.sleep(forTimeInterval: 1)
            shot("progress-\(i)")
        }
        XCTAssertTrue(el("heatmap").exists)
        tab("Hoy")
        let addWater = el("water.add")
        scrollTo(addWater)
        let water = el("water.today")
        let beforeWater = water.label
        addWater.tap()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertNotEqual(water.label, beforeWater, "Beber suma 250 ml")
        shot("water")
        el("water.remove").tap()
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertEqual(water.label, beforeWater, "Restar deshace el toque sin querer")
        let tile = el("weight.tile")
        scrollTo(tile).tap()
        let field = el("weight.field")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        el("weight.save").tap()
    }

    func test6_EveryTabScrollsToTheEnd() {
        launch(["-AtlasDemo"])
        for t in ["Hoy", "Comer", "Entrenar", "Progreso"] {
            tab(t)
            Thread.sleep(forTimeInterval: 1)
            shot("tab-\(t)")
            for _ in 0..<8 { app.swipeUp(velocity: .fast) }
            Thread.sleep(forTimeInterval: 1.2)
            shot("tab-\(t)-final")
        }
        el("tab.add").tap()
        XCTAssertTrue(containing("¿Qué apuntamos?").waitForExistence(timeout: 5))
        shot("quick-add")
    }
}
