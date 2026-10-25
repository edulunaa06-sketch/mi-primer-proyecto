import Foundation
import Observation
import UserNotifications

/// Notificaciones locales (sin servidor). Usa identificadores fijos para que reprogramar
/// sustituya la notificación anterior en lugar de duplicarla.
@MainActor
@Observable
final class NotificationManager {
    static let creatineID = "atlas.creatine.daily"
    static let photoPrefix = PhotoReminderPlanner.idPrefix
    static let testID = "atlas.test"

    private let center = UNUserNotificationCenter.current()

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var pendingIDs: [String] = []

    var isAuthorized: Bool {
        authorization == .authorized || authorization == .provisional || authorization == .ephemeral
    }

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
        pendingIDs = await center.pendingNotificationRequests().map(\.identifier)
    }

    /// Pide permiso si aún no se ha pedido. Devuelve true si las notificaciones están permitidas.
    func ensurePermission() async -> Bool {
        await refreshStatus()
        if authorization == .notDetermined { _ = await requestAuthorization() }
        return isAuthorized
    }

    /// Solicita permiso. Devuelve true solo si iOS lo concede.
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshStatus()
            return granted
        } catch {
            await refreshStatus()
            return false
        }
    }

    private func ensureAuthorized() async throws {
        await refreshStatus()
        if authorization == .notDetermined {
            _ = await requestAuthorization()
        }
        guard isAuthorized else { throw NotificationError.notAuthorized }
    }

    // MARK: Creatina

    /// Programa (o reprograma) el recordatorio diario. Elimina antes el anterior: nunca hay duplicados.
    func scheduleCreatine(hour: Int, minute: Int) async throws {
        try await ensureAuthorized()
        center.removePendingNotificationRequests(withIdentifiers: [Self.creatineID])

        let content = UNMutableNotificationContent()
        content.title = "Creatina"
        content.body = "Hora de tomar tu creatina. ATLAS."
        content.sound = .default

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        try await center.add(UNNotificationRequest(identifier: Self.creatineID, content: content, trigger: trigger))
        await refreshStatus()
    }

    func cancelCreatine() async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.creatineID])
        await refreshStatus()
    }

    // MARK: Fotos mensuales

    /// Programa el recordatorio mensual de fotos.
    /// - Si el día de referencia es ≤ 28 se usa un disparador mensual repetitivo (existe en todos los meses).
    /// - Si es 29, 30 o 31, iOS saltaría los meses sin ese día; en ese caso se programan los
    ///   próximos 12 meses individualmente, usando el último día del mes cuando haga falta.
    ///   Se reprograman cada vez que se abre la app.
    func schedulePhotoReminders(referenceDay: Int, hour: Int, from now: Date = Date()) async throws {
        try await ensureAuthorized()
        await cancelPhotoReminders()

        let content = UNMutableNotificationContent()
        content.title = "Fotos de progreso"
        content.body = "Registra tus tres fotos del mes: frente, lateral y espalda."
        content.sound = .default

        for request in PhotoReminderPlanner.requests(referenceDay: referenceDay, hour: hour, from: now) {
            let trigger = UNCalendarNotificationTrigger(dateMatching: request.components, repeats: request.repeats)
            try await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
        }
        await refreshStatus()
    }

    func cancelPhotoReminders() async {
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.photoPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        await refreshStatus()
    }

    // MARK: Avisos inteligentes (pasos y peso)

    static let stepsPrefix = "atlas.steps."
    static let weightPrefix = "atlas.weight."

    private func removePending(prefix: String) async {
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Aviso de pasos de HOY. Solo se programa si a la hora de comprobarlo los pasos están por debajo
    /// de la mitad del objetivo y aún no ha llegado la hora del aviso. Se vuelve a comprobar cada vez
    /// que abres o cierras la app (y cuando iOS deja a la app actualizarse en segundo plano).
    func updateStepReminder(enabled: Bool, steps: Int?, goal: Int, from: ClockTime, to: ClockTime, now: Date = Date()) async {
        await removePending(prefix: Self.stepsPrefix)
        guard enabled, isAuthorized, ReminderTiming.stepsBelowHalf(steps: steps, goal: goal), let steps else {
            await refreshStatus()
            return
        }
        let dayKey = DateUtils.dayKey(now)
        let time = ReminderTiming.time(forDayKey: dayKey, from: from, to: to)
        var comps = DateUtils.calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = time.hour
        comps.minute = time.minute
        guard let fireDate = DateUtils.calendar.date(from: comps), fireDate > now else {
            await refreshStatus()
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Vas corto de pasos"
        content.body = "A las \(now.formatted(date: .omitted, time: .shortened)) llevabas \(NumberFormat.integer(steps)) de \(NumberFormat.integer(goal)) pasos. Si aún no has llegado a \(NumberFormat.integer(goal / 2)), un paseo te pone al día."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: Self.stepsPrefix + dayKey, content: content, trigger: trigger))
        await refreshStatus()
    }

    /// Avisos de peso de los próximos 7 días a la hora elegida. Si hoy ya te has pesado, hoy no se avisa.
    /// Como pesarse se apunta en la app, al abrirla se rehacen y nunca avisa de un día ya pesado.
    func updateWeightReminders(enabled: Bool, weighedToday: Bool, from: ClockTime, to: ClockTime, now: Date = Date()) async {
        await removePending(prefix: Self.weightPrefix)
        guard enabled, isAuthorized else {
            await refreshStatus()
            return
        }
        let today = DateUtils.startOfDay(now)
        for offset in 0..<7 {
            if offset == 0 && weighedToday { continue }
            guard let day = DateUtils.calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let dayKey = DateUtils.dayKey(day)
            let time = ReminderTiming.time(forDayKey: dayKey, from: from, to: to)
            var comps = DateUtils.calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = time.hour
            comps.minute = time.minute
            guard let fireDate = DateUtils.calendar.date(from: comps), fireDate > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "¿Te has pesado hoy?"
            content.body = "Todavía no hay pesaje de hoy. Apúntalo en Progreso › Peso."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: Self.weightPrefix + dayKey, content: content, trigger: trigger))
        }
        await refreshStatus()
    }

    // MARK: Prueba

    /// Programa una notificación de prueba en 5 s. Devolver sin error significa que iOS ACEPTÓ
    /// programarla, no que ya se haya mostrado.
    func scheduleTest() async throws {
        try await ensureAuthorized()
        center.removePendingNotificationRequests(withIdentifiers: [Self.testID])
        let content = UNMutableNotificationContent()
        content.title = "Prueba de ATLAS"
        content.body = "Las notificaciones funcionan correctamente."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try await center.add(UNNotificationRequest(identifier: Self.testID, content: content, trigger: trigger))
        await refreshStatus()
    }

    enum NotificationError: LocalizedError {
        case notAuthorized
        var errorDescription: String? {
            "Las notificaciones están desactivadas. Actívalas en Ajustes › Notificaciones › ATLAS."
        }
    }
}
