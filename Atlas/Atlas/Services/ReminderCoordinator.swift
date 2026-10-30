import BackgroundTasks
import Foundation
import SwiftData

/// Rehace los avisos de pasos y peso con los datos actuales. Se llama al abrir y cerrar la app,
/// al cambiar los ajustes y cuando iOS deja a la app actualizarse en segundo plano
/// (eso lo decide iOS: puede no ocurrir si la app lleva días sin abrirse o con el modo de bajo consumo).
@MainActor
enum ReminderCoordinator {
    static let refreshTaskID = "atlas.reminders.refresh"

    static func refresh(context: ModelContext, notifications: NotificationManager, todaySteps: Int?, now: Date = Date()) async {
        let s = DataStore.settings(context)
        await notifications.refreshStatus()
        await notifications.updateStepReminder(
            enabled: s.stepReminderEnabled, steps: todaySteps, goal: s.stepGoal,
            from: ClockTime(minutesOfDay: s.stepReminderFromMinutes), to: ClockTime(minutesOfDay: s.stepReminderToMinutes), now: now)
        await notifications.updateWeightReminders(
            enabled: s.weightReminderEnabled, weighedToday: weighedToday(context, now: now),
            from: ClockTime(minutesOfDay: s.weightReminderFromMinutes), to: ClockTime(minutesOfDay: s.weightReminderToMinutes), now: now)
        if s.stepReminderEnabled || s.weightReminderEnabled { scheduleBackgroundRefresh() }
    }

    static func weighedToday(_ context: ModelContext, now: Date = Date()) -> Bool {
        let start = DateUtils.startOfDay(now)
        guard let end = DateUtils.calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        let descriptor = FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.date >= start && $0.date < end })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Pide a iOS una actualización en segundo plano dentro de ~1 hora (iOS decide cuándo, si llega).
    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Trabajo en segundo plano: lee los pasos de hoy, los guarda y rehace los avisos.
    static func backgroundRefresh(container: ModelContainer) async {
        let context = container.mainContext
        let steps = await StepCounter.stepsToday()
        let s = DataStore.settings(context)
        if let steps { DataStore.saveSteps(steps, for: Date(), goal: s.stepGoal, in: context) }
        await refresh(context: context, notifications: NotificationManager(), todaySteps: steps)
    }
}
