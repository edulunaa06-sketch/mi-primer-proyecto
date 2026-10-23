import CoreMotion
import Foundation
import HealthKit
import Observation

/// Lectura real de pasos desde Apple Salud (HealthKit). Solo lectura: la app no escribe en Salud.
///
/// Nota de privacidad de Apple: iOS NO revela si el usuario ha denegado el permiso de LECTURA.
/// Si el permiso está denegado, las consultas simplemente no devuelven muestras. Por eso la app
/// muestra "sin datos" (nunca un número inventado) y explica cómo revisar el permiso.
@MainActor
@Observable
final class HealthKitManager {
    enum State: Equatable {
        case unavailable          // Dispositivo sin HealthKit (p. ej. iPad antiguo)
        case notDetermined        // Aún no se ha mostrado la solicitud de permiso
        case requested            // Ya se mostró la solicitud (concedido o denegado: iOS no lo dice)
        /// Esta instalación no puede usar Salud (p. ej. firmada con una cuenta de Apple gratuita, que quita
        /// el permiso de HealthKit). Los pasos salen del sensor de movimiento del iPhone (últimos 7 días).
        case motionOnly
        case error(String)
    }

    struct DaySteps: Identifiable, Equatable {
        var id: Date { date }
        let date: Date
        let steps: Int
    }

    private let store = HKHealthStore()
    private let stepType = HKQuantityType(.stepCount)

    private(set) var state: State = .notDetermined
    /// nil = Salud no ha devuelto datos para hoy (no se muestra un 0 ficticio).
    private(set) var todaySteps: Int?
    /// De dónde salen los pasos de hoy: Apple Salud o, si Salud no da datos, el sensor de movimiento del iPhone.
    private(set) var stepsSource: String?
    private let pedometer = CMPedometer()
    private(set) var history: [DaySteps] = []
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    /// El usuario ha denegado Movimiento y forma física: sin Salud no hay de dónde sacar pasos.
    var motionDenied: Bool { CMPedometer.authorizationStatus() == .denied || CMPedometer.authorizationStatus() == .restricted }

    /// Un fallo de HealthKit (casi siempre "Missing com.apple.developer.healthkit entitlement" al instalar
    /// con Sideloadly o SideStore) no se enseña como error: se pasa al sensor del iPhone si lo hay.
    private func healthFailed(_ error: Error) {
        state = CMPedometer.isStepCountingAvailable() ? .motionOnly : .error(error.localizedDescription)
    }

    init() {
        if !HKHealthStore.isHealthDataAvailable() { state = .unavailable }
    }

    func refreshAuthorizationState() async {
        guard isAvailable else { state = CMPedometer.isStepCountingAvailable() ? .motionOnly : .unavailable; return }
        if state == .motionOnly { return }
        do {
            let status = try await store.statusForAuthorizationRequest(toShare: [], read: [stepType])
            switch status {
            case .shouldRequest: state = .notDetermined
            case .unnecessary: state = .requested
            case .unknown: state = .notDetermined
            @unknown default: state = .notDetermined
            }
        } catch {
            healthFailed(error)
        }
    }

    func requestAuthorization() async {
        guard isAvailable, state != .motionOnly else {
            if CMPedometer.isStepCountingAvailable() { state = .motionOnly }
            // La primera consulta al podómetro es la que muestra el permiso de Movimiento y forma física.
            await refresh()
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: [stepType])
            state = .requested
        } catch {
            healthFailed(error)
        }
        await refresh()
    }

    func refresh(historyDays: Int = 30) async {
        isLoading = true
        defer { isLoading = false }
        let now = Date()
        let startToday = DateUtils.startOfDay(now)
        let canReadHealth = isAvailable && state == .requested
        todaySteps = canReadHealth ? await sumSteps(from: startToday, to: now) : nil
        stepsSource = todaySteps == nil ? nil : "Apple Salud"
        if todaySteps == nil, let motion = await pedometerSteps(from: startToday, to: now) {
            todaySteps = motion
            stepsSource = "Sensor del iPhone"
        }
        if canReadHealth {
            history = await dailySteps(days: historyDays, endingAt: now)
        } else {
            history = await pedometerHistory(endingAt: now)
        }
        lastUpdated = now
    }

    /// El podómetro solo guarda 7 días; los días sin pasos no se añaden.
    private func pedometerHistory(endingAt now: Date) async -> [DaySteps] {
        var result: [DaySteps] = []
        for offset in 0..<7 {
            guard let day = DateUtils.calendar.date(byAdding: .day, value: -offset, to: DateUtils.startOfDay(now)) else { continue }
            let end = offset == 0 ? now : DateUtils.calendar.date(byAdding: .day, value: 1, to: day) ?? now
            if let steps = await pedometerSteps(from: day, to: end), steps > 0 {
                result.append(DaySteps(date: day, steps: steps))
            }
        }
        return result
    }

    /// Respaldo sin Apple Salud: el podómetro del iPhone (Movimiento y forma física) guarda los últimos 7 días.
    private func pedometerSteps(from start: Date, to end: Date) async -> Int? {
        guard CMPedometer.isStepCountingAvailable(),
              CMPedometer.authorizationStatus() != .denied, CMPedometer.authorizationStatus() != .restricted else { return nil }
        let pedometer = pedometer
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, _ in
                continuation.resume(returning: data.map { $0.numberOfSteps.intValue })
            }
        }
    }

    /// Suma acumulada (deduplicada por HealthKit entre iPhone y Apple Watch).
    private func sumSteps(from start: Date, to end: Date) async -> Int? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                if let sum = stats?.sumQuantity() {
                    continuation.resume(returning: Int(sum.doubleValue(for: .count())))
                } else {
                    continuation.resume(returning: nil)
                }
            }
            store.execute(query)
        }
    }

    private func dailySteps(days: Int, endingAt end: Date) async -> [DaySteps] {
        let cal = DateUtils.calendar
        let anchor = cal.startOfDay(for: end)
        guard let start = cal.date(byAdding: .day, value: -(days - 1), to: anchor) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                var result: [DaySteps] = []
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let sum = stats.sumQuantity() {
                        result.append(DaySteps(date: stats.startDate, steps: Int(sum.doubleValue(for: .count()))))
                    }
                }
                continuation.resume(returning: result.sorted { $0.date > $1.date })
            }
            store.execute(query)
        }
    }
}
