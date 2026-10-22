import XCTest
@testable import NowOrNever

final class ClaudeAPITests: XCTestCase {
    func testEstimateRequestShape() throws {
        let body = ClaudeAPI.estimateRequest(description: "150 g de macarrones con tomate")
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertEqual(body["max_tokens"] as? Int, 16000)
        XCTAssertNil(body["thinking"], "Opus 5.5: el thinking no se desactiva; se omite")
        let output = try XCTUnwrap(body["output_config"] as? [String: Any])
        XCTAssertEqual(output["effort"] as? String, "low")
        let format = try XCTUnwrap(output["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["content"] as? String, "150 g de macarrones con tomate")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(body))
    }

    func testHeadersUseUserKeyAndFallbackBeta() {
        let h = ClaudeAPI.headers(apiKey: "sk-ant-test")
        XCTAssertEqual(h["x-api-key"], "sk-ant-test")
        XCTAssertEqual(h["anthropic-version"], "2026-10-21")
        XCTAssertEqual(h["anthropic-beta"], "server-side-fallback-2026-07-01")
    }

    func testSuggestRequestIncludesCatalogAndTarget() throws {
        let catalog = [ClaudeAPI.CatalogEntry(id: "f1", name: "Pechuga de pollo", basis: "en crudo",
                                              per100: NutritionValues(kcal: 120, protein: 22.5, carbs: 0, fat: 2.6))]
        let body = ClaudeAPI.suggestRequest(mealLabel: "Comida", target: NutritionValues(kcal: 700, protein: 50, carbs: 80, fat: 20),
                                            context: "Había apuntado 150 g de macarrones", catalog: catalog)
        let user = try XCTUnwrap((body["messages"] as? [[String: Any]])?.first?["content"] as? String)
        XCTAssertTrue(user.contains("f1 | Pechuga de pollo | en crudo | 120 kcal"))
        XCTAssertTrue(user.contains("700 kcal"))
        XCTAssertTrue(user.contains("macarrones"))
        XCTAssertEqual((body["output_config"] as? [String: Any])?["effort"] as? String, "medium")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(body))
    }

    private func response(_ text: String, stop: String = "end_turn") -> Data {
        let obj: [String: Any] = ["content": [["type": "thinking", "thinking": ""], ["type": "text", "text": text]], "stop_reason": stop]
        return try! JSONSerialization.data(withJSONObject: obj)
    }

    func testDecodeEstimate() throws {
        let json = #"{"items":[{"name":"Macarrones cocidos","grams":150,"kcal_per_100g":158,"protein_per_100g":5.8,"carbs_per_100g":30.9,"fat_per_100g":0.9}],"note":"Pasta cocida."}"#
        let estimate = try ClaudeAPI.decode(ClaudeAPI.Estimate.self, status: 200, data: response(json))
        XCTAssertEqual(estimate.items.count, 1)
        XCTAssertEqual(estimate.items[0].values.kcal, 237, accuracy: 0.01)
        XCTAssertTrue(estimate.items[0].isPlausible)
    }

    func testDecodeErrors() {
        XCTAssertThrowsError(try ClaudeAPI.decode(ClaudeAPI.Estimate.self, status: 200, data: response("{}", stop: "refusal"))) {
            XCTAssertEqual($0 as? ClaudeAPI.ClaudeError, .refused)
        }
        XCTAssertThrowsError(try ClaudeAPI.decode(ClaudeAPI.Estimate.self, status: 200, data: response("{", stop: "max_tokens"))) {
            XCTAssertEqual($0 as? ClaudeAPI.ClaudeError, .truncated)
        }
        XCTAssertThrowsError(try ClaudeAPI.decode(ClaudeAPI.Estimate.self, status: 200, data: response("no es json"))) {
            XCTAssertEqual($0 as? ClaudeAPI.ClaudeError, .badResponse)
        }
        XCTAssertThrowsError(try ClaudeAPI.decode(ClaudeAPI.Estimate.self, status: 401, data: Data())) {
            XCTAssertEqual($0 as? ClaudeAPI.ClaudeError, .invalidKey)
        }
        XCTAssertThrowsError(try ClaudeAPI.decode(ClaudeAPI.Estimate.self, status: 429, data: Data())) {
            XCTAssertEqual($0 as? ClaudeAPI.ClaudeError, .rateLimited)
        }
        let apiError = #"{"type":"error","error":{"type":"invalid_request_error","message":"bad request"}}"#
        XCTAssertThrowsError(try ClaudeAPI.decode(ClaudeAPI.Estimate.self, status: 400, data: Data(apiError.utf8))) {
            XCTAssertEqual($0 as? ClaudeAPI.ClaudeError, .api("bad request"))
        }
    }

    func testImplausibleEstimatesAreDetected() {
        let bad = ClaudeAPI.EstimatedItem(name: "x", grams: 100, kcalPer100g: 2000, proteinPer100g: 0, carbsPer100g: 0, fatPer100g: 0)
        let negative = ClaudeAPI.EstimatedItem(name: "x", grams: -5, kcalPer100g: 100, proteinPer100g: 1, carbsPer100g: 1, fatPer100g: 1)
        XCTAssertFalse(bad.isPlausible)
        XCTAssertFalse(negative.isPlausible)
    }

    func testResolveSuggestionOnlyUsesCatalog() {
        let catalog = [
            ClaudeAPI.CatalogEntry(id: "f1", name: "Pollo", basis: "en crudo", per100: NutritionValues(kcal: 120, protein: 22.5, carbs: 0, fat: 2.6)),
            ClaudeAPI.CatalogEntry(id: "f2", name: "Arroz", basis: "en seco", per100: NutritionValues(kcal: 360, protein: 6.5, carbs: 79.3, fat: 0.6)),
        ]
        let meal = ClaudeAPI.SuggestedMeal(name: "Pollo con arroz", why: "Proteína magra", items: [
            .init(foodId: "f1", grams: 180), .init(foodId: "f2", grams: 70), .init(foodId: "f99", grams: 50), .init(foodId: "f1", grams: -3),
        ])
        let lines = ClaudeAPI.resolve(meal, catalog: catalog)
        XCTAssertEqual(lines.map(\.entry.id), ["f1", "f2"])
        XCTAssertEqual(lines.map(\.grams), [180, 70])
    }
}

final class IdeasCatalogTests: XCTestCase {
    private func loadCatalog() throws -> SeedCatalog {
        if let catalog = try? SeedCatalog.loadFromBundle(.main) { return catalog }
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("NowOrNever/Resources/SeedCatalog.json")
        return try SeedCatalog.decode(from: Data(contentsOf: url))
    }

    func testIdeasLibrary() throws {
        let catalog = try loadCatalog()
        XCTAssertEqual(catalog.version, 3)
        XCTAssertEqual(catalog.validationErrors(), [])
        let counts = Dictionary(grouping: catalog.ideas, by: \.type).mapValues(\.count)
        XCTAssertEqual(counts["breakfast"], 12)
        XCTAssertEqual(counts["lunch"], 12)
        XCTAssertEqual(counts["snack"], 9)
        XCTAssertEqual(counts["dinner"], 11)
        let fruit = try XCTUnwrap(catalog.ideas.first { $0.name == "Plato de frutas con yogur" })
        XCTAssertEqual(catalog.totals(forIdea: fruit).kcal, 445, accuracy: 1)
        for idea in catalog.ideas {
            let kcal = catalog.totals(forIdea: idea).kcal
            XCTAssertTrue((100...800).contains(kcal), "\(idea.name): \(kcal) kcal")
        }
    }
}

final class FoodSearchTests: XCTestCase {
    func testCommonNamesFindCatalogFoods() {
        XCTAssertTrue(FoodSearch.matches(name: "Pasta de trigo", query: "macarrones"))
        XCTAssertTrue(FoodSearch.matches(name: "Plátano", query: "platano"))
        XCTAssertTrue(FoodSearch.matches(name: "Pechuga de pollo", query: "POLLO"))
        XCTAssertTrue(FoodSearch.matches(name: "Arroz", query: ""))
        XCTAssertFalse(FoodSearch.matches(name: "Arroz", query: "macarrones"))
    }
}

final class ManualKcalMacrosTests: XCTestCase {
    func testMacrosFromKcalAddUpAndUseWeight() {
        let m = EnergyCalculator.macros(forKcal: 2500, weightKg: 80, goal: .recomposition)
        XCTAssertEqual(m.protein, 188)            // 30 % de 2500 / 4
        let lower = EnergyCalculator.macros(forKcal: 2000, weightKg: 80, goal: .recomposition)
        XCTAssertEqual(lower.protein, 150, "La proteína cambia con las kcal")
        XCTAssertEqual(m.fat, 69)                 // 25 % de 2500 / 9
        XCTAssertEqual(m.protein * 4 + m.carbs * 4 + m.fat * 9, 2500, accuracy: 10)
    }

    func testMacrosFromKcalWithoutWeight() {
        let m = EnergyCalculator.macros(forKcal: 2000, weightKg: nil, goal: .loseFat)
        XCTAssertEqual(m.protein, 175)            // 35 % (perder grasa)
        XCTAssertEqual(m.fat, 56)                 // 25 %
        XCTAssertEqual(m.protein * 4 + m.carbs * 4 + m.fat * 9, 2000, accuracy: 10)
    }

    func testLowKcalNeverLeavesNegativeCarbs() {
        let m = EnergyCalculator.macros(forKcal: 1200, weightKg: 110, goal: .loseFat)
        XCTAssertLessThanOrEqual(m.protein * 4, 1200 * 0.40 + 2)
        XCTAssertGreaterThan(m.carbs, 0)
    }
}

final class MotivationTests: XCTestCase {
    func testQuotesAreUniqueAndNeverRepeatTwiceInARow() {
        XCTAssertGreaterThanOrEqual(Motivation.quotes.count, 30)
        XCTAssertEqual(Set(Motivation.quotes.map(\.text)).count, Motivation.quotes.count)
        XCTAssertNotEqual(Motivation.next(after: 5, random: { _ in 5 }), 5)
        XCTAssertEqual(Motivation.next(after: nil, random: { _ in 3 }), 3)
    }

    func testStepEstimates() {
        XCTAssertEqual(StepEstimates.kilometers(10_000), 7.6, accuracy: 0.001)
        XCTAssertEqual(StepEstimates.kcal(10_000), 400, accuracy: 0.001)
        XCTAssertEqual(StepEstimates.fraction(12_000, goal: 8_000), 1)
        XCTAssertEqual(StepEstimates.fraction(4_000, goal: 8_000), 0.5)
    }
}

final class PhotoMealTests: XCTestCase {
    func testPhotoRequestSendsImageAndWeight() throws {
        let body = ClaudeAPI.photoRequest(imageBase64: "QUJD", totalGrams: 420, comment: "lleva salsa")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        let content = try XCTUnwrap(messages[0]["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["type"] as? String, "image")
        let source = try XCTUnwrap(content[0]["source"] as? [String: Any])
        XCTAssertEqual(source["data"] as? String, "QUJD")
        XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
        let text = try XCTUnwrap(content[1]["text"] as? String)
        XCTAssertTrue(text.contains("420 g"))
        XCTAssertTrue(text.contains("lleva salsa"))
        let output = try XCTUnwrap(body["output_config"] as? [String: Any])
        let format = try XCTUnwrap(output["format"] as? [String: Any])
        let schema = try XCTUnwrap(format["schema"] as? [String: Any])
        XCTAssertEqual(schema["required"] as? [String], ["items", "questions", "note"])
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    func testFollowUpIncludesPreviousAnswerAndUserReplies() throws {
        let body = ClaudeAPI.photoRequest(imageBase64: "QUJD", totalGrams: 300, comment: "", previous: "{\"items\":[]}",
                                          answers: [ClaudeAPI.Answer(question: "¿Es queso cottage o requesón?", answer: "cottage")])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["user", "assistant", "user"])
        XCTAssertTrue((messages[2]["content"] as? String ?? "").contains("cottage"))
    }

    func testItemsAreScaledToTheScaleWeight() {
        let items = [
            ClaudeAPI.EstimatedItem(name: "Pollo", grams: 150, kcalPer100g: 165, proteinPer100g: 31, carbsPer100g: 0, fatPer100g: 3.6),
            ClaudeAPI.EstimatedItem(name: "Boniato", grams: 250, kcalPer100g: 90, proteinPer100g: 2, carbsPer100g: 20.7, fatPer100g: 0.2),
        ]
        let scaled = ClaudeAPI.scaled(items, toTotal: 480)
        XCTAssertEqual(scaled.map(\.grams), [180, 300])
        XCTAssertEqual(ClaudeAPI.scaled(items, toTotal: 400).map(\.grams), [150, 250])
    }

    func testDecodePhotoAnalysisWithQuestions() throws {
        let inner = #"{"items":[{"name":"Queso cottage","grams":100,"kcal_per_100g":98,"protein_per_100g":11,"carbs_per_100g":3.4,"fat_per_100g":4.3}],"questions":["¿Es queso cottage o requesón?"],"note":"Estimación."}"#
        let response: [String: Any] = ["content": [["type": "text", "text": inner]], "stop_reason": "end_turn"]
        let data = try JSONSerialization.data(withJSONObject: response)
        let result = try ClaudeAPI.decode(ClaudeAPI.PhotoAnalysis.self, status: 200, data: data)
        XCTAssertEqual(result.items.first?.name, "Queso cottage")
        XCTAssertEqual(result.questions, ["¿Es queso cottage o requesón?"])
    }
}

final class MealLogTests: XCTestCase {
    func testDetectRequestAsksOnlyForNames() throws {
        let body = ClaudeAPI.detectRequest(imageBase64: "QUJD")
        let output = try XCTUnwrap(body["output_config"] as? [String: Any])
        let schema = try XCTUnwrap((output["format"] as? [String: Any])?["schema"] as? [String: Any])
        XCTAssertEqual(schema["required"] as? [String], ["ingredients", "note"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual((messages[0]["content"] as? [[String: Any]])?.first?["type"] as? String, "image")
    }

    func testCalculateSendsUserGramsAndKeepsThem() throws {
        let weighed = [ClaudeAPI.WeighedIngredient(name: "Pollo a la plancha", grams: 180),
                       ClaudeAPI.WeighedIngredient(name: "Atún al natural", grams: 60)]
        let body = ClaudeAPI.calculateRequest(weighed, imageBase64: nil)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let text = try XCTUnwrap(messages[0]["content"] as? String)
        XCTAssertTrue(text.contains("1. Pollo a la plancha: 180 g"))
        XCTAssertTrue(text.contains("2. Atún al natural: 60 g"))

        // Aunque Claude devuelva otros gramos, mandan los que pesó el usuario.
        let fromClaude = [
            ClaudeAPI.EstimatedItem(name: "Pollo", grams: 150, kcalPer100g: 165, proteinPer100g: 31, carbsPer100g: 0, fatPer100g: 3.6),
            ClaudeAPI.EstimatedItem(name: "Atún", grams: 80, kcalPer100g: 116, proteinPer100g: 25.5, carbsPer100g: 0, fatPer100g: 0.8),
        ]
        let items = ClaudeAPI.apply(fromClaude, to: weighed)
        XCTAssertEqual(items.map(\.grams), [180, 60])
        XCTAssertEqual(items.map(\.name), ["Pollo a la plancha", "Atún al natural"])
        XCTAssertEqual(NutritionMath.sum(items.map(\.values)).kcal, 297 + 69.6, accuracy: 0.01)
    }

    func testDayKeyRoundTrip() {
        let date = DateUtils.date(fromDayKey: "2026-10-22")!
        XCTAssertEqual(DateUtils.dayKey(date), "2026-10-22")
        XCTAssertNil(DateUtils.date(fromDayKey: "hoy"))
    }
}
