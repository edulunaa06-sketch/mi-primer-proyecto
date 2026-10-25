import XCTest
@testable import Atlas

/// Pruebas de lo que la IA puede ver. Lo importante aquí no es el formato: es que no se filtre
/// una media inventada cuando no hay datos, y que los huecos viajen declarados.
final class AIContextTests: XCTestCase {
    private let today = DateUtils.startOfDay(Date(timeIntervalSince1970: 1_700_000_000))
    private func day(_ offset: Int) -> Date { today.addingTimeInterval(Double(offset) * 86_400) }

    private func report(_ input: ReportInput) -> PeriodReport { ReportBuilder.build(input) }

    private var emptyReport: PeriodReport {
        report(ReportInput(period: ReportRange.month.period(endingAt: today)))
    }

    private var sampleProfile: AIContext.Profile {
        AIContext.Profile(sex: "Hombre", age: 30, heightCm: 180, weightKg: 80,
                          activity: "Moderada", goal: "Recomposición",
                          kcalTarget: 2300, proteinTarget: 180, carbsTarget: 250, fatTarget: 65,
                          automaticTargets: true)
    }

    // MARK: Vacío

    func testEmptyContextDeclaresWhatIsMissingInsteadOfSendingZeros() {
        let context = AIContext(report: emptyReport, profile: nil, exercises: [], isDeloadWeek: false)
        XCTAssertNil(context.profile)
        XCTAssertNil(context.nutrition.averageKcal)
        XCTAssertNil(context.body.changeKg)
        XCTAssertFalse(context.caveats.isEmpty)
        XCTAssertTrue(context.isTooEmptyToBeUseful)
        XCTAssertEqual(context.filledSections, 0)

        let text = context.compactText
        XCTAssertTrue(text.contains("PERFIL: incompleto"))
        XCTAssertTrue(text.contains("no hay media fiable"))
        XCTAssertTrue(text.contains("no hay tendencia fiable"))
        XCTAssertTrue(text.contains("LO QUE FALTA"))
        // Y le dice explícitamente que no rellene los huecos.
        XCTAssertTrue(text.contains("no lo rellenes con suposiciones"))
    }

    func testFewNutritionDaysNeverTravelAsAnAverage() {
        var input = ReportInput(period: ReportRange.month.period(endingAt: today))
        // Tres días apuntados: por debajo del mínimo para una media.
        input.nutritionDays = (0..<3).map {
            ReportInput.NutritionDay(date: day(-$0), kcal: 4000, protein: 50, carbs: 500, fat: 150)
        }
        let context = AIContext(report: report(input), profile: nil, exercises: [], isDeloadWeek: false)
        XCTAssertFalse(context.nutrition.hasEnoughData)
        XCTAssertNil(context.nutrition.averageKcal, "Con 3 días no se envía ninguna media")
        XCTAssertFalse(context.compactText.contains("4.000"))
        XCTAssertTrue(context.compactText.contains("3 de 30 días apuntados"))
    }

    func testWeightWithoutTwoWeeksNeverTravelsAsATrend() {
        var input = ReportInput(period: ReportRange.month.period(endingAt: today))
        let monday = DateUtils.startOfWeek(today)
        input.weights = [.init(date: monday, kg: 80), .init(date: monday.addingTimeInterval(86_400), kg: 79)]
        let context = AIContext(report: report(input), profile: nil, exercises: [], isDeloadWeek: false)
        XCTAssertNil(context.body.changeKg)
        XCTAssertEqual(context.body.weighIns, 2)
        XCTAssertTrue(context.compactText.contains("2 pesaje(s)"))
    }

    // MARK: Con datos

    func testFullContextCarriesTheNumbersTheUserSeesOnScreen() {
        var input = ReportInput(period: ReportRange.month.period(endingAt: today))
        input.work = [VolumeAnalytics.ExerciseWork(exerciseID: "tue-bench-barbell", name: "Press de banca con barra",
                                                   date: day(-3), workSets: 4, volumeKg: 3200)]
        input.sessionsCompleted = 8
        input.sessionsScheduled = 10
        input.programmedSets = 4
        input.nutritionDays = (0..<20).map {
            ReportInput.NutritionDay(date: day(-$0), kcal: 2500, protein: 190, carbs: 260, fat: 70)
        }
        input.kcalTarget = 2300
        input.weights = [.init(date: day(-20), kg: 82), .init(date: day(0), kg: 80)]
        input.recovery = (0..<5).map { RecoveryEntry(date: day(-$0), sleepHours: 7.5, fatigue: 2) }

        let built = report(input)
        let context = AIContext(report: built, profile: sampleProfile, exercises: [], isDeloadWeek: true)

        XCTAssertEqual(context.training.sessionsCompleted, 8)
        XCTAssertEqual(context.training.workSets, 4)
        XCTAssertEqual(context.training.tonnageKg, 3200)
        XCTAssertTrue(context.training.isDeloadWeek)
        XCTAssertEqual(context.nutrition.averageKcal, 2500)
        XCTAssertEqual(context.body.changeKg, -2)
        XCTAssertEqual(context.recovery.averageSleepHours, 7.5)
        XCTAssertFalse(context.isTooEmptyToBeUseful)
        XCTAssertEqual(context.filledSections, 5)

        let text = context.compactText
        XCTAssertTrue(text.contains("8 de 10 sesiones"))
        XCTAssertTrue(text.contains("DESCARGA"))
        XCTAssertTrue(text.contains("Pecho"))
        XCTAssertTrue(text.contains("2.500 kcal/día") || text.contains("2500 kcal/día"))
        XCTAssertTrue(text.contains("Hombre"))
        XCTAssertTrue(text.contains("Recomposición"))
    }

    func testExerciseLinesSayWhenTheOneRepMaxIsAnEstimate() {
        let exercise = AIContext.Exercise(
            name: "Press de banca con barra", muscle: "Pecho", lastTopSet: "80 kg × 8 (RIR 2)",
            estimatedOneRepMax: 100, oneRepMaxConfidence: OneRepMaxConfidence.medium.label,
            sessionsLogged: 5, trend: StrengthTrend.Verdict.flat.label, changePercent: 0.5,
            isStalled: true, suggestedAction: ProgressionEngine.Action.hold.label,
            suggestedReason: "Llevas 3 sesiones sin mejorar.")
        let context = AIContext(report: emptyReport, profile: nil, exercises: [exercise], isDeloadWeek: false)
        let text = context.compactText
        XCTAssertTrue(text.contains("1RM estimado 100 kg"))
        XCTAssertTrue(text.contains("Fiabilidad media"))
        XCTAssertTrue(text.contains("ESTANCADO"))
        XCTAssertTrue(text.contains("Propuesta de la app"))
        XCTAssertTrue(text.contains("sin mejorar"))
    }

    func testUnclassifiedExercisesAreDeclaredSoTheAIDoesNotCountThem() {
        var input = ReportInput(period: ReportRange.week.period(endingAt: today))
        input.work = [VolumeAnalytics.ExerciseWork(exerciseID: "custom-1", name: "Invento raro",
                                                   date: day(-1), workSets: 3, volumeKg: 300)]
        let context = AIContext(report: report(input), profile: nil, exercises: [], isDeloadWeek: false)
        XCTAssertEqual(context.training.unclassifiedExercises, ["Invento raro"])
        XCTAssertTrue(context.compactText.contains("SIN CLASIFICAR"))
    }

    // MARK: Formato

    func testContextSurvivesEncodingAndDecoding() throws {
        var input = ReportInput(period: ReportRange.week.period(endingAt: today))
        input.sessionsCompleted = 3
        input.work = [VolumeAnalytics.ExerciseWork(exerciseID: "tue-bench-barbell", name: "Press de banca con barra",
                                                   date: day(-1), workSets: 3, volumeKg: 2400)]
        let context = AIContext(report: report(input), profile: sampleProfile, exercises: [], isDeloadWeek: false)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let restored = try decoder.decode(AIContext.self, from: try encoder.encode(context))
        XCTAssertEqual(restored, context)
    }

    func testTheScopeListAndTheExclusionsAreFilledIn() {
        XCTAssertFalse(AIDataScope.allCases.isEmpty)
        for scope in AIDataScope.allCases {
            XCTAssertFalse(scope.label.isEmpty)
            XCTAssertFalse(scope.detail.isEmpty)
        }
        XCTAssertFalse(AIDataExclusions.all.isEmpty)
        // Lo más sensible, dicho con nombre y apellidos.
        XCTAssertTrue(AIDataExclusions.all.contains { $0.lowercased().contains("fotos de progreso") })
        XCTAssertTrue(AIDataExclusions.all.contains { $0.lowercased().contains("clave") })
    }
}

/// Pruebas de la petición que se envía: el contrato con la API, sin red.
final class CoachRequestTests: XCTestCase {
    func testTheRequestCarriesTheContextAndTheQuestion() throws {
        let body = ClaudeAPI.coachRequest(question: "¿Por qué me he estancado?", context: "ENTRENAMIENTO: 3 sesiones.")
        let messages = body["messages"] as? [[String: Any]]
        let user = messages?.first?["content"] as? String
        XCTAssertNotNil(user)
        XCTAssertTrue(user!.contains("¿Por qué me he estancado?"))
        XCTAssertTrue(user!.contains("ENTRENAMIENTO: 3 sesiones."))
        // Y le dice que SOLO puede usar eso.
        XCTAssertTrue(user!.contains("lo único que puedes usar"))
    }

    func testTheSystemPromptForbidsTheThingsThatMatter() {
        let system = ClaudeAPI.coachSystem.lowercased()
        XCTAssertTrue(system.contains("solo los datos del contexto"))
        XCTAssertTrue(system.contains("no diagnostiques"))
        XCTAssertTrue(system.contains("profesional sanitario"))
        XCTAssertTrue(system.contains("coincidencia con causa"))
        XCTAssertTrue(system.contains("propuesta"))
        XCTAssertTrue(system.contains("estimado, no medido"))
    }

    func testTheSchemaDemandsTheDataItUsedAndWhatIsMissing() throws {
        let required = ClaudeAPI.coachSchema["required"] as? [String]
        XCTAssertEqual(Set(required ?? []), ["answer", "data_used", "assumptions", "missing_data"])
        let properties = ClaudeAPI.coachSchema["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["proposal"], "La propuesta es opcional pero tiene que existir en el esquema")
        XCTAssertEqual(ClaudeAPI.coachSchema["additionalProperties"] as? Bool, false)
    }

    func testTheAnswerDecodesWithAndWithoutAProposal() throws {
        let withProposal = """
        {"answer":"Sube 2,5 kg.","data_used":["80 kg × 12"],"assumptions":[],
         "proposal":"Pasa a 82,5 kg","missing_data":["Sueño"]}
        """
        let decoded = try JSONDecoder().decode(ClaudeAPI.CoachAnswer.self, from: Data(withProposal.utf8))
        XCTAssertEqual(decoded.proposal, "Pasa a 82,5 kg")
        XCTAssertEqual(decoded.dataUsed, ["80 kg × 12"])
        XCTAssertEqual(decoded.missingData, ["Sueño"])

        let withoutProposal = """
        {"answer":"Vas bien.","data_used":[],"assumptions":[],"proposal":null,"missing_data":[]}
        """
        XCTAssertNil(try JSONDecoder().decode(ClaudeAPI.CoachAnswer.self, from: Data(withoutProposal.utf8)).proposal)
    }
}
