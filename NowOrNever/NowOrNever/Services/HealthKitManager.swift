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
    private(set) var history: [DaySteps] = []
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    init() {
        if !HKHealthStore.isHealthDataAvailable() { state = .unavailable }
    }

    func refreshAuthorizationState() async {
        guard isAvailable else { state = .unavailable; return }
        do {
            let status = try await store.statusForAuthorizationRequest(toShare: [], read: [stepType])
            switch status {
            case .shouldRequest: state = .notDetermined
            case .unnecessary: state = .requested
            case .unknown: state = .notDetermined
            @unknown default: state = .notDetermined
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func requestAuthorization() async {
        guard isAvailable else { state = .unavailable; return }
        do {
            try await store.requestAuthorization(toShare: [], read: [stepType])
            state = .requested
            await refresh()
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func refresh(historyDays: Int = 30) async {
        guard isAvailable else { return }
        isLoading = true
        defer { isLoading = false }
        let now = Date()
        let startToday = DateUtils.startOfDay(now)
        todaySteps = await sumSteps(from: startToday, to: now)
        history = await dailySteps(days: historyDays, endingAt: now)
        lastUpdated = now
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
