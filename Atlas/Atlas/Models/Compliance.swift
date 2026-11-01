import Foundation

/// Cálculo transparente del cumplimiento diario.
/// Media de los componentes disponibles:
///  • Comidas completadas / 4
///  • Sesiones completadas / sesiones programadas (se omite en el día de descanso)
///  • Pasos / objetivo (máx. 100 %; se omite si Salud no devuelve datos)
struct DailyCompliance: Equatable {
    var mealsCompleted: Int
    var mealsTotal: Int = MealType.allCases.count
    var sessionsCompleted: Int
    var sessionsScheduled: Int
    var steps: Int?
    var stepGoal: Int

    struct Component: Equatable {
        let name: String
        let fraction: Double
    }

    var components: [Component] {
        var result: [Component] = []
        if mealsTotal > 0 {
            result.append(Component(name: "Comidas", fraction: clamp(Double(mealsCompleted) / Double(mealsTotal))))
        }
        if sessionsScheduled > 0 {
            result.append(Component(name: "Entrenamiento", fraction: clamp(Double(sessionsCompleted) / Double(sessionsScheduled))))
        }
        if let steps, stepGoal > 0 {
            result.append(Component(name: "Pasos", fraction: clamp(Double(steps) / Double(stepGoal))))
        }
        return result
    }

    var fraction: Double {
        let comps = components
        guard !comps.isEmpty else { return 0 }
        return comps.map(\.fraction).reduce(0, +) / Double(comps.count)
    }

    private func clamp(_ v: Double) -> Double { min(max(v.isFinite ? v : 0, 0), 1) }
}

enum WeightStats {
    struct Point: Equatable {
        let date: Date
        let kg: Double
    }

    /// Diferencia entre el valor más reciente y el más reciente anterior o igual a (último - días).
    /// Devuelve nil si no hay suficientes datos en ese periodo.
    static func change(points: [Point], days: Int, calendar: Calendar = DateUtils.calendar) -> Double? {
        let sorted = points.sorted { $0.date < $1.date }
        guard let latest = sorted.last,
              let cutoff = calendar.date(byAdding: .day, value: -days, to: latest.date) else { return nil }
        guard let reference = sorted.last(where: { $0.date <= cutoff }) else { return nil }
        return latest.kg - reference.kg
    }

    static func first(_ points: [Point]) -> Point? { points.min { $0.date < $1.date } }
    static func latest(_ points: [Point]) -> Point? { points.max { $0.date < $1.date } }
}
