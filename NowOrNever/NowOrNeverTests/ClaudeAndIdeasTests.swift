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
        XCTAssertEqual(catalog.version, 2)
        XCTAssertEqual(catalog.validationErrors(), [])
        let counts = Dictionary(grouping: catalog.ideas, by: \.type).mapValues(\.count)
        XCTAssertEqual(counts["breakfast"], 10)
        XCTAssertEqual(counts["lunch"], 10)
        XCTAssertEqual(counts["snack"], 8)
        XCTAssertEqual(counts["dinner"], 10)
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
