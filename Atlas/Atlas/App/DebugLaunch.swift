#if DEBUG
import Foundation
import SwiftData

/// SOLO en Debug (pruebas y capturas del CI; nunca en el IPA):
/// -AtlasDemo (8 semanas de datos), -AtlasSkipOnboarding, -AtlasTab <today|food|train|progress>,
/// -AtlasLive (abre un entreno), -AtlasSheet <quick|food|menus|weight|run|profile>.
@MainActor
enum DebugLaunch {
    static var args: [String] { ProcessInfo.processInfo.arguments }

    static func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func apply(context: ModelContext, app: AppState) {
        Store.seedTemplatesIfNeeded(context)
        if args.contains("-AtlasDemo") { seedDemo(context) }
        if args.contains("-AtlasSkipOnboarding") || args.contains("-AtlasDemo") {
            Store.profile(context).onboarded = true
            try? context.save()
        }
        if let tab = value("-AtlasTab").flatMap(AppTab.init(rawValue:)) { app.tab = tab }
        if args.contains("-AtlasLive") {
            let t = Store.templates(context).first { $0.kind == .strength && !$0.exercises.isEmpty }
            app.liveWorkout = Store.startWorkout(from: t, in: context)
        }
        let today = DateUtils.dayKey(Date())
        switch value("-AtlasSheet") {
        case "quick": app.showQuickAdd = true
        case "food": app.foodSheet = FoodSheetRequest(meal: .lunch, dayKey: today)
        case "menus": app.foodSheet = FoodSheetRequest(meal: .lunch, dayKey: today, startWithMenus: true)
        case "weight": app.showWeight = true
        case "run": app.runTemplate = RunRequest(template: nil)
        case "profile": app.showProfile = true
        default: break
        }
    }

    static func seedDemo(_ context: ModelContext) {
        guard ((try? context.fetchCount(FetchDescriptor<Workout>())) ?? 0) == 0 else { return }
        let p = Store.profile(context)
        p.name = "Edu"
        p.age = 27; p.heightCm = 180; p.goalRaw = FitnessGoal.recomposition.rawValue
        let cal = DateUtils.calendar
        let now = Date()
        // Pesos: 8 semanas bajando ~0,3 kg/semana con ruido.
        for d in stride(from: 56, through: 0, by: -1) where d % 2 == 0 || d < 7 {
            let date = cal.date(byAdding: .day, value: -d, to: now)!.addingTimeInterval(-3600 * 3)
            let kg = 82.0 - Double(56 - d) * 0.045 + (d % 3 == 0 ? 0.5 : d % 3 == 1 ? -0.3 : 0.1)
            context.insert(WeightLog(date: date, kg: (kg * 10).rounded() / 10))
        }
        p.recalculate(weightKg: 79.5)
        // Comidas de los últimos 20 días (y algo de hoy).
        let foods = Catalog.shared.foods
        for d in 0..<20 {
            let key = DateUtils.dayKey(cal.date(byAdding: .day, value: -d, to: now)!)
            for (i, meal) in MealType.allCases.enumerated() where d > 0 || i < 2 {
                for j in 0..<2 {
                    let f = foods[(d * 7 + i * 3 + j * 5) % foods.count]
                    let g = Double(80 + ((d + i + j) % 5) * 30)
                    context.insert(FoodEntry(dayKey: key, meal: meal, name: f.name, grams: g, per100: f.per100,
                                             values: f.per100.scaled(toGrams: g), foodKey: f.id))
                }
            }
        }
        context.insert(WaterLog(dayKey: DateUtils.dayKey(now), ml: 1250))
        // Entrenos: 8 semanas de la rutina con cargas que suben poco a poco.
        let templates = Store.templates(context)
        for week in stride(from: 7, through: 0, by: -1) {
            let weekStart = cal.date(byAdding: .day, value: -7 * week, to: DateUtils.startOfWeek(now))!
            for t in templates where t.kind != .rest {
                let date = cal.date(byAdding: .day, value: t.weekday - 1, to: weekStart)!.addingTimeInterval(18 * 3600)
                guard date < now.addingTimeInterval(-3600), (week + t.weekday) % 6 != 0 else { continue }
                if t.kind == .run {
                    Store.logRun(meters: 5000 + Double((7 - week) * 150), seconds: 1680 - (7 - week) * 15, date: date, template: t, in: context)
                    continue
                }
                let w = Workout(name: t.name, kind: .strength, templateID: t.id, startedAt: date.addingTimeInterval(-3600))
                context.insert(w)
                for (order, ex) in t.sortedExercises.enumerated() {
                    for i in 0..<ex.sets {
                        let s = WorkoutSet(exerciseKey: ex.key, exerciseName: ex.name, exerciseOrder: order, repRange: ex.repRange, index: i)
                        let base = 20.0 + Double(order * 7 % 40)
                        s.kg = base + Double(7 - week) * 2.5
                        s.reps = (ExerciseDefinition.parseRange(ex.repRange)?.max ?? 10) - (i % 2)
                        s.done = true
                        s.isRecord = week == 0 && i == 0
                        context.insert(s)
                        s.workout = w
                    }
                }
                w.finishedAt = date
            }
        }
        try? context.save()
    }
}
#endif
