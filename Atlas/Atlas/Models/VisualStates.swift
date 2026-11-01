import Foundation

// MARK: - Estado de las calorías del día

/// En qué punto estás respecto a tu objetivo de calorías. Cada estado tiene su color (azul, amarillo dorado,
/// verde o rojo) y su texto, para no depender solo del color.
enum CalorieStatus: Equatable {
    /// Todavía queda bastante margen.
    case plenty(left: Double)
    /// Te estás acercando al objetivo.
    case approaching(left: Double)
    /// Objetivo alcanzado o a menos del margen configurado (por arriba o por abajo). `delta` = comido − objetivo.
    case onTarget(delta: Double)
    /// Te has pasado más del margen. `excess` = kcal exactas por encima del objetivo.
    case over(excess: Double)

    /// Margen por defecto (± kcal) dentro del que el día cuenta como objetivo cumplido.
    static let defaultMargin = 100.0
    /// A partir de este porcentaje del objetivo se considera que te estás acercando.
    static let approachingFraction = 0.8

    static func evaluate(consumed: Double, target: Double, margin: Double = defaultMargin) -> CalorieStatus {
        guard target > 0 else { return .plenty(left: 0) }
        let margin = max(margin, 0)
        let delta = consumed - target
        if abs(delta) <= margin { return .onTarget(delta: delta) }
        if delta > margin { return .over(excess: delta) }
        let left = -delta
        return consumed >= target * approachingFraction ? .approaching(left: left) : .plenty(left: left)
    }

    /// Para animar el cambio de color solo cuando cambia el estado (no con cada kcal).
    var kind: Int {
        switch self {
        case .plenty: return 0
        case .approaching: return 1
        case .onTarget: return 2
        case .over: return 3
        }
    }

    var title: String {
        switch self {
        case .plenty: return "Margen amplio"
        case .approaching: return "Te acercas al objetivo"
        case .onTarget: return "Objetivo cumplido"
        case .over: return "Por encima del objetivo"
        }
    }

    var symbol: String {
        switch self {
        case .plenty: return "circle.dashed"
        case .approaching: return "arrow.up.right.circle.fill"
        case .onTarget: return "checkmark.circle.fill"
        case .over: return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Racha: animación y récord

/// Decide si toca animar la llama o celebrar un récord. Se compara con lo último que se vio en este iPhone,
/// así cada subida se celebra una sola vez (abrir la app no suma nada: la racha sale de los datos reales).
enum StreakFeedback: Equatable {
    case none
    /// La racha ha subido desde la última vez.
    case grew
    /// La racha ha subido y supera tu mejor marca anterior.
    case newRecord

    /// `lastSeenCurrent` / `lastSeenBest`: lo que se mostró la última vez (nil = primera vez: no se celebra nada).
    static func evaluate(current: Int, best: Int, lastSeenCurrent: Int?, lastSeenBest: Int?) -> StreakFeedback {
        guard let lastSeenCurrent, let lastSeenBest else { return .none }
        guard current > lastSeenCurrent else { return .none }
        if current == best, best > lastSeenBest, lastSeenBest > 0 { return .newRecord }
        return .grew
    }
}

// MARK: - Medallas nuevas

enum MedalUnlocks {
    /// Medallas que han subido de nivel desde la última vez que se vieron. `seen` = nivel visto por medalla
    /// (nil = primera vez: se guardan las actuales sin celebrar, para no felicitar por logros antiguos).
    static func newlyUnlocked(_ medals: [Medal], seen: [String: Int]?) -> [Medal] {
        guard let seen else { return [] }
        return medals.filter { $0.tier != .locked && $0.tier.rawValue > (seen[$0.id] ?? 0) }
    }

    /// Lo que se guarda tras mostrar: nunca baja (una celebración no se repite aunque cambien los datos).
    static func updatedSeen(_ medals: [Medal], seen: [String: Int]?) -> [String: Int] {
        var result = seen ?? [:]
        for m in medals { result[m.id] = max(result[m.id] ?? 0, m.tier.rawValue) }
        return result
    }
}

extension Medal {
    /// Qué hay que hacer para conseguirla, en una frase.
    var summary: String {
        switch id {
        case "longest-run": return "Tu carrera más larga: 5, 10 y 21,1 km."
        case "best-5k-pace": return "Tu mejor ritmo en carreras de 5 km o más."
        case "most-steps": return "Tu día con más pasos: 10 000, 15 000 y 20 000."
        case "best-streak": return "Días seguidos cumpliendo: 7, 30 y 100."
        case "total-km": return "Kilómetros corridos en total: 50, 200 y 500."
        case "strength": return "Sesiones de fuerza completadas: 10, 50 y 150."
        case "weigh-ins": return "Pesajes apuntados: 10, 30 y 100."
        case "photo-months": return "Meses con las tres fotos: 1, 3 y 6."
        default: return source
        }
    }
}
