import CoreMotion
import Foundation
import Observation

/// Pasos de hoy con el sensor de movimiento del iPhone (Movimiento y forma física).
/// No usa Apple Salud: con Sideloadly y una cuenta de Apple gratuita iOS no deja leerla.
/// Si no hay datos se muestra "—", nunca un número inventado.
@MainActor
@Observable
final class StepCounter {
    enum State: Equatable {
        case unavailable   // Sin sensor de pasos (p. ej. simulador o iPad)
        case denied        // Permiso de Movimiento y forma física denegado
        case ready
    }

    private let pedometer = CMPedometer()
    private var liveStart: Date?
    private var shownDay: Date?

    private(set) var todaySteps: Int?
    private(set) var state: State

    init() {
        state = CMPedometer.isStepCountingAvailable() ? .ready : .unavailable
        updateDenied()
    }

    private func updateDenied() {
        let status = CMPedometer.authorizationStatus()
        if status == .denied || status == .restricted { state = .denied }
    }

    /// Lee los pasos desde las 00:00 y sigue actualizándolos en vivo mientras la app está abierta.
    /// La primera llamada es la que muestra el permiso de Movimiento y forma física.
    func start() {
        guard state != .unavailable else { return }
        let startOfDay = DateUtils.startOfDay(Date())
        if liveStart == startOfDay { return }
        if liveStart != nil { pedometer.stopUpdates() }
        liveStart = startOfDay
        if shownDay != startOfDay { todaySteps = nil; shownDay = startOfDay }
        pedometer.startUpdates(from: startOfDay) { [weak self] data, error in
            let steps = data?.numberOfSteps.intValue
            Task { @MainActor in
                guard let self else { return }
                if let steps { self.todaySteps = steps; self.state = .ready }
                if error != nil { self.updateDenied() }
            }
        }
    }

    /// Al volver a la app (o al cambiar de día) se vuelve a empezar desde las 00:00 de hoy.
    func restart() {
        if liveStart != nil { pedometer.stopUpdates() }
        liveStart = nil
        start()
    }

    func stop() {
        pedometer.stopUpdates()
        liveStart = nil
    }
}
