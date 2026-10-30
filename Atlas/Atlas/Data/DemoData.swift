#if DEBUG
import Foundation
import SwiftData

/// SOLO en Debug (pruebas del CI, nunca en el IPA): mete meses de datos para comprobar que la app va fluida
/// con un uso real (pesos, comidas, entrenos, pasos, carreras, días marcados y elecciones de comidas).
extension DataStore {
    @MainActor
    static func seedDemoData(_ context: ModelContext, days: Int = 240) {
        let s = settings(context)
        guard ((try? context.fetchCount(FetchDescriptor<DailySteps>())) ?? 0) < 30 else { return }
        let today = DateUtils.startOfDay(Date())
        let start = DateUtils.calendar.date(byAdding: .day, value: -days, to: today) ?? today
        s.trackingStartDate = start
        s.onboardingCompleted = true
        let plans = ((try? context.fetch(FetchDescriptor<MenuPlan>())) ?? []).filter { !$0.isLibrary }
        let routine = (try? context.fetch(FetchDescriptor<RoutineExercise>())) ?? []
        var kg = 88.0
        for offset in 0...days {
            guard let day = DateUtils.calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let noon = day.addingTimeInterval(9 * 3600)
            if offset % 2 == 0 {
                kg -= 0.04 + Double(offset % 5) * 0.01
                context.insert(WeightEntry(date: noon, weightKg: kg + Double(offset % 3) * 0.2))
            }
            context.insert(DailySteps(date: day, steps: 4000 + (offset * 37) % 9000, goal: 8000))
            for (i, type) in MealType.allCases.enumerated() where (offset + i) % 5 != 0 {
                context.insert(MealRecord(date: day, mealType: type, planName: "Demo",
                                          values: NutritionValues(kcal: 550, protein: 40, carbs: 60, fat: 15)))
            }
            if offset % 9 == 0, let plan = plans.randomElement() {
                context.insert(DayMealChoice(dayKey: DateUtils.dayKey(day), mealType: .dinner, planID: plan.id, factor: 1.1))
            }
            if offset % 17 == 0 { context.insert(DayMarkRecord(date: day, mark: offset % 2 == 0 ? .sick : .work)) }
            if offset % 4 == 0 {
                context.insert(StravaActivityRecord(stravaID: -Int64(offset + 1), name: "Carrera demo", sportType: "Run",
                                                    startDate: noon, distanceMeters: 5000 + Double(offset % 7) * 1000,
                                                    movingTimeSeconds: 1700 + offset % 400, elapsedTimeSeconds: 1800,
                                                    elevationGainMeters: nil))
            }
        }
        // Entrenos de las últimas semanas, con series rellenas.
        for week in 0..<Int(days / 7) {
            guard let weekDate = DateUtils.calendar.date(byAdding: .day, value: -7 * week, to: today) else { continue }
            let weekStart = DateUtils.startOfWeek(weekDate)
            for base in WeeklyRoutine.trainableSessions where week % 3 != 2 {
                let session = base.resolved(with: routine)
                let log = fetchOrCreateLog(for: session, weekStart: weekStart, in: context)
                log.isCompleted = true
                for ex in log.exercises { ex.isCompleted = true }
            }
        }
        try? context.save()
    }
}
#endif
