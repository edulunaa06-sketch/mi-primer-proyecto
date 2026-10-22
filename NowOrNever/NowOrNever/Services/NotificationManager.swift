import Foundation
import Observation
import UserNotifications

/// Notificaciones locales (sin servidor). Usa identificadores fijos para que reprogramar
/// sustituya la notificación anterior en lugar de duplicarla.
@MainActor
@Observable
final class NotificationManager {
    static let creatineID = "now-or-never.creatine.daily"
    static let photoPrefix = PhotoReminderPlanner.idPrefix
    static let testID = "now-or-never.test"

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
        content.body = "Hora de tomar tu creatina. Now or Never."
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

    // MARK: Prueba

    /// Programa una notificación de prueba en 5 s. Devolver sin error significa que iOS ACEPTÓ
    /// programarla, no que ya se haya mostrado.
    func scheduleTest() async throws {
        try await ensureAuthorized()
        center.removePendingNotificationRequests(withIdentifiers: [Self.testID])
        let content = UNMutableNotificationContent()
        content.title = "Prueba de Now or Never"
        content.body = "Las notificaciones funcionan correctamente."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try await center.add(UNNotificationRequest(identifier: Self.testID, content: content, trigger: trigger))
        await refreshStatus()
    }

    enum NotificationError: LocalizedError {
        case notAuthorized
        var errorDescription: String? {
            "Las notificaciones están desactivadas. Actívalas en Ajustes › Notificaciones › Now or Never."
        }
    }
}
