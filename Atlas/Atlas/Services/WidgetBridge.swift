import Foundation
import SwiftData
import WidgetKit

/// Lo que el widget enseña en la pantalla de inicio.
///
/// Es una foto pequeña y plana a propósito. El widget NO abre la base de datos de la app:
/// mover el almacén de SwiftData a una carpeta compartida sería la forma «normal» de hacerlo,
/// pero eso cambia dónde vive tu historial y un fallo ahí te lo borra. Así que la app escribe
/// este resumen y el widget solo lo lee.
///
/// IMPORTANTE: esta estructura está duplicada en `AtlasWidgets/WidgetShared.swift`, porque el
/// widget es otro programa y no comparte código con la app. Si cambias una, cambia la otra.
/// Si se desincronizan no se rompe nada: el widget no sabrá leerla y enseñará el estado vacío.
struct WidgetSnapshot: Codable, Equatable {
    var actualizado: Date
    var kcalComidas: Double
    var kcalObjetivo: Double
    var proteinaG: Double
    var proteinaObjetivoG: Double
    var aguaMl: Int
    var aguaObjetivoMl: Int
    /// Nombre del día de hoy («Pierna», «Carrera suave»…). Vacío si no hay nada puesto.
    var entrenoNombre: String
    /// `SessionKind.rawValue`, para que el widget pinte el icono correcto.
    var entrenoTipo: String
    var entrenoHecho: Bool
    var rachaDias: Int
}

/// El puente entre la app y el widget.
///
/// Todo aquí es opcional y tolerante a fallos: si la firma de la app no trae el permiso de
/// App Group, `UserDefaults(suiteName:)` devuelve nil y simplemente no se publica nada. La app
/// sigue funcionando igual y el widget enseña «abre la app». Nunca revienta.
enum WidgetBridge {
    static let appGroup = "group.com.example.atlas"
    static let clave = "widget.snapshot"

    private static var compartido: UserDefaults? { UserDefaults(suiteName: appGroup) }

    /// ¿Está disponible la carpeta compartida? Si no, el widget no puede funcionar.
    static var disponible: Bool { compartido != nil }

    static func guardar(_ foto: WidgetSnapshot) {
        guard let compartido, let datos = try? JSONEncoder().encode(foto) else { return }
        compartido.set(datos, forKey: clave)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func leer() -> WidgetSnapshot? {
        guard let datos = compartido?.data(forKey: clave) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: datos)
    }

    /// Arma la foto con los datos de hoy y la publica. Se llama al abrir la app y al salir de
    /// ella; el widget se refresca por su cuenta cada poco, no hace falta más.
    @MainActor
    static func publicarHoy(context: ModelContext) {
        let ajustes = DataStore.settings(context)
        let hoy = Date()
        let clave = DateUtils.dayKey(hoy)

        let todasComidas = (try? context.fetch(FetchDescriptor<MealRecord>())) ?? []
        let comidas = todasComidas.filter { $0.dayKey == clave }
        let totales = NutritionMath.sum(comidas.map(\.values))

        let agua = ((try? context.fetch(FetchDescriptor<WaterLog>())) ?? [])
            .first { $0.dayKey == clave }?.ml ?? 0

        // El día de hoy, con los tipos que haya elegido el usuario.
        let routine = (try? context.fetch(FetchDescriptor<RoutineExercise>())) ?? []
        let titles = (try? context.fetch(FetchDescriptor<SessionTitle>())) ?? []
        let kinds = DataStore.kindChoices(in: context)
        let weekday = DateUtils.weekdayMondayBased(hoy)
        let delDia = WeeklyRoutine.sessions(forWeekday: weekday)
            .map { $0.resolved(with: routine, titles: titles, kinds: kinds) }
        // Si el día tiene varias sesiones se enseña la primera que no sea descanso.
        let sesion = delDia.first { $0.kind != .rest } ?? delDia.first

        let registros = (try? context.fetch(FetchDescriptor<WorkoutSessionLog>())) ?? []
        var hecho = false
        if let sesion {
            let key = WorkoutSessionLog.makeKey(weekStart: DateUtils.startOfWeek(hoy), sessionID: sesion.id)
            hecho = registros.first { $0.key == key }?.isCompleted ?? false
        }

        // La racha, con la misma cuenta que la pantalla de Hoy.
        let pasos = (try? context.fetch(FetchDescriptor<DailySteps>())) ?? []
        let marcas = (try? context.fetch(FetchDescriptor<DayMarkRecord>())) ?? []
        let foto = TrackingSnapshot(meals: todasComidas, logs: registros, steps: pasos, marks: marcas,
                                    stepGoal: ajustes.stepGoal,
                                    trackingStart: DataStore.trackingStart(context),
                                    kinds: kinds)

        guardar(WidgetSnapshot(
            actualizado: hoy,
            kcalComidas: totales.kcal,
            kcalObjetivo: ajustes.kcalTarget,
            proteinaG: totales.protein,
            proteinaObjetivoG: ajustes.proteinTarget,
            aguaMl: agua,
            aguaObjetivoMl: ajustes.waterGoalMl,
            entrenoNombre: sesion?.title ?? "",
            entrenoTipo: (sesion?.kind ?? .rest).rawValue,
            entrenoHecho: hecho,
            rachaDias: foto.streak.current))
    }
}
