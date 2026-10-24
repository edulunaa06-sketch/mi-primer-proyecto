import Foundation
import SwiftData

/// Datos de ejemplo para las previews de Xcode. No se usan en la app real.
@MainActor
enum SampleData {

    /// Contenedor en memoria con perfil, rutina, menú de hoy, un entreno y pesos.
    static let container: ModelContainer = {
        let container = makeContainer()
        populate(container.mainContext)
        return container
    }()

    /// Rellena un contexto con datos de ejemplo. Lo usan las previews y el
    /// modo demo con el que se hacen las capturas en el simulador.
    nonisolated static func populate(_ context: ModelContext) {
        let profile = UserProfile(age: 17,
                                  sex: .male,
                                  heightCm: 178,
                                  weightKg: 74.5,
                                  activity: .high,
                                  goal: .loseFat)
        context.insert(profile)

        PlanService.seedRoutineIfNeeded(context: context)

        // Menú de hoy, con el desayuno ya hecho.
        let plan = PlanService.dayPlan(for: .now, profile: profile, context: context)
        plan.sortedMeals.first?.done = true

        // Algo apuntado a mano.
        context.insert(ManualFood(date: DateHelper.startOfDay(),
                                  name: "Café con leche",
                                  calories: 90,
                                  protein: 5,
                                  carbs: 8,
                                  fat: 4))

        // Pesos de los últimos meses.
        let weights: [(Int, Double)] = [(-120, 81.2), (-90, 79.4), (-60, 77.8), (-30, 76.1), (0, 74.5)]
        for (offset, kg) in weights {
            context.insert(WeightEntry(date: DateHelper.addDays(offset, to: DateHelper.startOfDay()), kg: kg))
        }

        // Un entreno de Push de la semana pasada, para que se vea el historial.
        let pushDay = (try? context.fetch(FetchDescriptor<WorkoutDayPlan>()))?.first { $0.weekday == 2 }
        if let pushDay {
            let session = WorkoutSession(date: DateHelper.addDays(-7, to: DateHelper.startOfDay()),
                                         weekday: 2,
                                         title: pushDay.name)
            context.insert(session)
            for exercise in pushDay.sortedExercises {
                for index in 0..<exercise.sets {
                    let log = SetLog(exerciseName: exercise.name,
                                     setIndex: index,
                                     weightKg: exercise.name == "Press banca" ? 60 : 20,
                                     reps: exercise.repsMax)
                    log.session = session
                    session.setLogs.append(log)
                }
            }
        }

        try? context.save()
    }

    /// Contenedor vacío, para ver la pantalla de bienvenida.
    static let emptyContainer: ModelContainer = makeContainer()

    /// Perfil de ejemplo listo para pasar a las vistas.
    static var profile: UserProfile {
        let context = container.mainContext
        if let existing = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            return existing
        }
        let profile = UserProfile()
        context.insert(profile)
        return profile
    }

    /// Menú de hoy de ejemplo.
    static var todayPlan: DayPlan {
        PlanService.dayPlan(for: .now, profile: profile, context: container.mainContext)
    }

    /// Día de rutina de ejemplo (Push).
    static var pushDay: WorkoutDayPlan {
        let context = container.mainContext
        let days = (try? context.fetch(FetchDescriptor<WorkoutDayPlan>())) ?? []
        return days.first { $0.weekday == 2 } ?? WorkoutDayPlan(weekday: 2, name: "Push", kind: .strength)
    }

    private static func makeContainer() -> ModelContainer {
        let configuration = ModelConfiguration(schema: NowOrNeverApp.schema, isStoredInMemoryOnly: true)
        // En previews no hay nada que salvar: si falla, es un error de programación.
        return try! ModelContainer(for: NowOrNeverApp.schema, configurations: configuration)
    }
}
