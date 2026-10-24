import Foundation
import SwiftData

/// Operaciones sobre la base de datos que usan varias pantallas:
/// crear la rutina inicial, generar el menú de un día y cambiar comidas.
enum PlanService {

    // MARK: - Datos iniciales

    /// Carga la rutina semanal la primera vez que se abre la app.
    static func seedRoutineIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<WorkoutDayPlan>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard existing.isEmpty else { return }
        for day in RoutineData.makeWeek() {
            context.insert(day)
        }
        try? context.save()
    }

    // MARK: - Menú del día

    /// Devuelve el menú de un día; si no existe, lo genera.
    @discardableResult
    static func dayPlan(for date: Date,
                        profile: UserProfile?,
                        context: ModelContext) -> DayPlan {
        let day = DateHelper.startOfDay(date)
        let descriptor = FetchDescriptor<DayPlan>(predicate: #Predicate { $0.date == day })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let plan = DayPlan(date: day)
        context.insert(plan)
        fill(plan, targets: profile?.targets ?? NutritionTargets.calculated(weightKg: 70, tdee: 2400, goal: .maintain))
        try? context.save()
        return plan
    }

    /// Rellena un menú vacío con los platos del día.
    private static func fill(_ plan: DayPlan, targets: NutritionTargets) {
        let meals = MenuPlanner.plan(for: plan.date, targets: targets).map { $0.makePlannedMeal() }
        for meal in meals {
            meal.day = plan
        }
        plan.meals = meals
    }

    /// Vuelve a generar el menú de un día (pierde las marcas de hecho).
    static func regenerate(_ plan: DayPlan, profile: UserProfile?, context: ModelContext) {
        for meal in plan.meals {
            context.delete(meal)
        }
        plan.meals = []
        fill(plan, targets: profile?.targets ?? NutritionTargets.calculated(weightKg: 70, tdee: 2400, goal: .maintain))
        try? context.save()
    }

    /// Cambia una comida por otra receta del mismo tipo.
    static func swap(_ meal: PlannedMeal, to recipe: Recipe, profile: UserProfile?, context: ModelContext) {
        let targets = profile?.targets ?? NutritionTargets.calculated(weightKg: 70, tdee: 2400, goal: .maintain)
        meal.apply(MenuPlanner.scale(recipe, targets: targets))
        try? context.save()
    }

    // MARK: - Entrenos

    /// Devuelve la sesión de hoy para un día de la rutina; si no existe, la crea.
    static func session(for day: WorkoutDayPlan, on date: Date, context: ModelContext) -> WorkoutSession {
        let start = DateHelper.startOfDay(date)
        let weekday = day.weekday
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date == start && $0.weekday == weekday }
        )
        if let existing = try? context.fetch(descriptor).first {
            syncSets(of: day, in: existing, context: context)
            return existing
        }
        let session = WorkoutSession(date: start, weekday: weekday, title: day.name)
        context.insert(session)
        syncSets(of: day, in: session, context: context)
        try? context.save()
        return session
    }

    /// Crea las series que falten para que cada ejercicio tenga sus huecos.
    static func syncSets(of day: WorkoutDayPlan, in session: WorkoutSession, context: ModelContext) {
        for exercise in day.sortedExercises {
            let existing = session.logs(for: exercise.name)
            if existing.count < exercise.sets {
                for index in existing.count..<exercise.sets {
                    let log = SetLog(exerciseName: exercise.name, setIndex: index)
                    log.session = session
                    session.setLogs.append(log)
                }
            }
        }
    }

    /// Última sesión anterior en la que se apuntó ese ejercicio.
    static func lastSession(for exerciseName: String,
                            before date: Date,
                            context: ModelContext) -> (session: WorkoutSession, logs: [SetLog])? {
        let start = DateHelper.startOfDay(date)
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date < start },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 30
        let sessions = (try? context.fetch(descriptor)) ?? []
        for session in sessions {
            let logs = session.logs(for: exerciseName).filter(\.isFilled)
            if !logs.isEmpty { return (session, logs) }
        }
        return nil
    }

    /// Si la última vez completó todas las series en el tope del rango, toca subir peso.
    static func shouldIncreaseWeight(for exercise: ExercisePlan,
                                     lastLogs: [SetLog]) -> Bool {
        guard !lastLogs.isEmpty, lastLogs.count >= exercise.sets else { return false }
        return lastLogs.allSatisfy { $0.reps >= exercise.repsMax }
    }

    // MARK: - Peso

    /// Guarda el peso del día (si ya hay uno, lo actualiza).
    static func saveWeight(_ kg: Double, on date: Date, context: ModelContext) {
        let day = DateHelper.startOfDay(date)
        let descriptor = FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.date == day })
        if let existing = try? context.fetch(descriptor).first {
            existing.kg = kg
        } else {
            context.insert(WeightEntry(date: day, kg: kg))
        }
        try? context.save()
    }
}
