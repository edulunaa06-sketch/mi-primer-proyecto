import XCTest
@testable import NowOrNever

final class EnergyCalculatorTests: XCTestCase {
    func testMifflinStJeorMale() {
        let p = BodyProfile(weightKg: 85.1, heightCm: 180, age: 30, sex: .male, activity: .moderate, goal: .recomposition)
        // 10×85,1 + 6,25×180 − 5×30 + 5 = 1831
        XCTAssertEqual(EnergyCalculator.bmr(p), 1831, accuracy: 0.001)
        let t = EnergyCalculator.targets(for: p)
        XCTAssertEqual(t.tdee, 1831 * 1.55, accuracy: 0.001)
        XCTAssertEqual(t.kcal, 2550)          // 2838 × 0,9 = 2554 → redondeo a 10
        XCTAssertEqual(t.protein, 170)        // 2,0 g/kg
        XCTAssertEqual(t.fat, 71)             // 25 % de 2550 / 9
        XCTAssertEqual(t.carbs, 308)          // (2550 − 680 − 639) / 4
    }

    func testMifflinStJeorFemale() {
        let p = BodyProfile(weightKg: 60, heightCm: 165, age: 25, sex: .female, activity: .sedentary, goal: .loseFat)
        XCTAssertEqual(EnergyCalculator.bmr(p), 1345.25, accuracy: 0.001)
        let t = EnergyCalculator.targets(for: p)
        XCTAssertEqual(t.kcal, ((1345.25 * 1.2 * 0.8) / 10).rounded() * 10)
        XCTAssertEqual(t.protein, 132) // 2,2 g/kg
    }

    func testGoalsChangeCalories() {
        var p = BodyProfile(weightKg: 80, heightCm: 178, age: 35, sex: .male, activity: .high, goal: .loseFat)
        let lose = EnergyCalculator.targets(for: p).kcal
        p.goal = .recomposition
        let recomp = EnergyCalculator.targets(for: p).kcal
        p.goal = .gainMuscle
        let gain = EnergyCalculator.targets(for: p).kcal
        XCTAssertLessThan(lose, recomp)
        XCTAssertLessThan(recomp, gain)
    }

    func testMacrosAddUpToCalories() {
        for goal in FitnessGoal.allCases {
            for activity in ActivityLevel.allCases {
                let p = BodyProfile(weightKg: 85.1, heightCm: 180, age: 30, sex: .male, activity: activity, goal: goal)
                let t = EnergyCalculator.targets(for: p)
                let fromMacros = t.protein * 4 + t.carbs * 4 + t.fat * 9
                XCTAssertEqual(fromMacros, t.kcal, accuracy: 15, "\(goal) \(activity)")
            }
        }
    }

    func testInvalidProfile() {
        XCTAssertFalse(BodyProfile(weightKg: 85, heightCm: 50, age: 30, sex: .male, activity: .light, goal: .loseFat).isValid)
        XCTAssertFalse(BodyProfile(weightKg: 85, heightCm: 180, age: 5, sex: .male, activity: .light, goal: .loseFat).isValid)
    }

    func testMenuScaler() {
        XCTAssertEqual(MenuScaler.factor(currentKcal: 2000, targetKcal: 2500)!, 1.25, accuracy: 0.0001)
        XCTAssertNil(MenuScaler.factor(currentKcal: 0, targetKcal: 2500))
        XCTAssertEqual(MenuScaler.factor(currentKcal: 1000, targetKcal: 5000), 2.0) // limitado
        XCTAssertEqual(MenuScaler.scaledGrams(5, factor: 1.25), 6)       // < 20 g → 1 g
        XCTAssertEqual(MenuScaler.scaledGrams(80, factor: 1.25), 100)    // 100 → paso de 10
        XCTAssertEqual(MenuScaler.scaledGrams(60, factor: 1.1), 65)      // 66 → paso de 5
        XCTAssertEqual(MenuScaler.scaledGrams(180, factor: 1.1), 200)    // 198 → paso de 10
        XCTAssertEqual(MenuScaler.scaledGrams(1, factor: 0.5), 1)        // nunca < 1 g
    }
}

final class RoutineEditingLogicTests: XCTestCase {
    func testParseRange() {
        XCTAssertEqual(ExerciseDefinition.parseRange("6–10")?.min, 6)
        XCTAssertEqual(ExerciseDefinition.parseRange("6–10")?.max, 10)
        XCTAssertEqual(ExerciseDefinition.parseRange("12-20")?.max, 20)
        XCTAssertEqual(ExerciseDefinition.parseRange("12")?.min, 12)
        XCTAssertNil(ExerciseDefinition.parseRange("10–6"))
        XCTAssertNil(ExerciseDefinition.parseRange("abc"))
        XCTAssertEqual(ExerciseDefinition.formatRange(min: 8, max: 12), "8–12")
        XCTAssertEqual(ExerciseDefinition.formatRange(min: 10, max: 10), "10")
    }

    func testAllDefaultRangesParse() {
        for ex in WeeklyRoutine.allSessions.flatMap(\.exercises) {
            let r = ExerciseDefinition.parseRange(ex.repRange)
            XCTAssertNotNil(r, ex.name)
            XCTAssertEqual(ExerciseDefinition.formatRange(min: r!.min, max: r!.max), ex.repRange)
        }
    }

    func testSessionWithCustomExercisesKeepsIdentity() {
        let base = WeeklyRoutine.tuesdayPushA
        let custom = base.with(exercises: [ExerciseDefinition(id: "x", name: "Fondos", sets: 3, repRange: "8–12")])
        XCTAssertEqual(custom.id, base.id)
        XCTAssertEqual(custom.weekday, base.weekday)
        XCTAssertEqual(custom.exercises.map(\.name), ["Fondos"])
    }

    func testDefaultExerciseLookup() {
        XCTAssertEqual(WeeklyRoutine.defaultExercise(id: "thu-hack-squat")?.name, "Hack squat")
        XCTAssertNil(WeeklyRoutine.defaultExercise(id: "nope"))
    }

    func testExerciseSessionSummary() {
        let date = Date(timeIntervalSince1970: 0)
        let s = ExerciseSessionSummary(date: date, sets: [
            .init(weightKg: 60, reps: 10),
            .init(weightKg: 65, reps: 8),
            .init(weightKg: 65, reps: 6),
            .init(weightKg: nil, reps: nil),
        ])!
        XCTAssertEqual(s.topWeightKg, 65)
        XCTAssertEqual(s.repsAtTopWeight, 8)
        XCTAssertEqual(s.volumeKg, 600 + 520 + 390)
        XCTAssertEqual(s.totalReps, 24)
        XCTAssertEqual(s.setsWithData, 3)
        XCTAssertEqual(s.estimatedOneRepMax!, 65 * (1 + 8.0 / 30), accuracy: 0.0001)
        XCTAssertNil(ExerciseSessionSummary(date: date, sets: [.init(weightKg: 50, reps: nil)]))
    }
}
