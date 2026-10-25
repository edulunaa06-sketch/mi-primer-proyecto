import Foundation

/// Decide si toca subir carga, mantener, bajar o descargar, y SIEMPRE explica por qué.
///
/// Reglas que se respetan a propósito:
/// · Nunca sube el peso por una sola sesión buena si el esfuerzo dice que no toca.
/// · Nunca sube el peso si la última serie se fue al fallo sin llegar al rango de repeticiones.
/// · Nunca sube el peso si el usuario ha apuntado una molestia.
/// · Si faltan datos, lo dice en vez de inventar una recomendación.
/// La decisión es una propuesta: la app la muestra y el usuario decide.
enum ProgressionEngine {

    // MARK: Propuesta

    enum Action: String {
        /// Subir la carga en la próxima sesión.
        case increaseLoad
        /// Mismo peso, buscar más repeticiones dentro del rango.
        case addReps
        /// Repetir lo mismo: todavía no toca cambiar nada.
        case hold
        /// Bajar la carga: el rendimiento se está cayendo.
        case reduceLoad
        /// Semana de descarga.
        case deload
        /// No hay datos suficientes.
        case needMoreData

        var label: String {
            switch self {
            case .increaseLoad: return "Sube el peso"
            case .addReps: return "Mismo peso, más repeticiones"
            case .hold: return "Repite lo mismo"
            case .reduceLoad: return "Baja el peso"
            case .deload: return "Semana de descarga"
            case .needMoreData: return "Faltan datos"
            }
        }

        var symbol: String {
            switch self {
            case .increaseLoad: return "arrow.up.circle.fill"
            case .addReps: return "plus.circle.fill"
            case .hold: return "equal.circle.fill"
            case .reduceLoad: return "arrow.down.circle.fill"
            case .deload: return "moon.zzz.fill"
            case .needMoreData: return "questionmark.circle"
            }
        }
    }

    struct Advice: Equatable {
        let action: Action
        /// Por qué se propone esto, en una frase.
        let reason: String
        /// Peso propuesto, cuando la propuesta es un número concreto.
        let suggestedWeightKg: Double?
        /// Repeticiones a las que apuntar.
        let suggestedReps: Int?
        /// Cuántas sesiones se han mirado para decidir.
        let sessionsConsidered: Int

        var hasNumbers: Bool { suggestedWeightKg != nil || suggestedReps != nil }
    }

    // MARK: Entrada

    /// Rango de repeticiones que pide la rutina.
    struct RepTarget: Equatable {
        let min: Int
        let max: Int
        init(min: Int, max: Int) {
            self.min = Swift.max(min, 1)
            self.max = Swift.max(max, Swift.max(min, 1))
        }
    }

    /// Cuánto se sube de golpe según el material. Para barra se redondea a lo que se puede montar.
    static func increment(for equipment: Equipment?, currentKg: Double) -> Double {
        switch equipment {
        case .barbell, .smith, .ezBar:
            // Dos discos de 1,25 kg (uno por lado) es el salto fino habitual.
            return currentKg >= 60 ? 5 : 2.5
        case .dumbbell:
            // Las mancuernas van de 2 en 2 kg o de 2,5 en 2,5 kg en casi todos los gimnasios.
            return 2.5
        case .machine, .cable:
            // El paso lo marca la máquina; se propone un 5 % como referencia.
            return Swift.max((currentKg * 0.05 / 0.5).rounded() * 0.5, 1)
        case .bodyweight:
            return 0
        default:
            return 2.5
        }
    }

    // MARK: Decisión

    /// Propuesta para la próxima sesión de un ejercicio.
    /// - Parameters:
    ///   - history: sesiones anteriores de ESE ejercicio, de la más antigua a la más reciente.
    ///   - target: rango de repeticiones de la rutina.
    ///   - equipment: material, para calcular el salto de peso.
    ///   - hasDiscomfort: el usuario apuntó una molestia en la última sesión.
    ///   - isDeloadWeek: la semana en curso ya está marcada como descarga.
    static func advise(history: [ExerciseSessionSummary], target: RepTarget,
                       equipment: Equipment? = nil, hasDiscomfort: Bool = false,
                       isDeloadWeek: Bool = false) -> Advice {
        let ordered = history.sorted { $0.date < $1.date }
        let considered = ordered.count

        if isDeloadWeek {
            return Advice(action: .deload, reason: "Semana de descarga: baja el peso o las series a propósito y no busques récords.",
                          suggestedWeightKg: nil, suggestedReps: nil, sessionsConsidered: considered)
        }

        guard let last = ordered.last else {
            return Advice(action: .needMoreData,
                          reason: "Todavía no hay ninguna sesión apuntada de este ejercicio. Apunta kilos y repeticiones y la próxima vez verás una propuesta.",
                          suggestedWeightKg: nil, suggestedReps: nil, sessionsConsidered: 0)
        }

        if hasDiscomfort {
            return Advice(action: .hold,
                          reason: "Apuntaste una molestia en la última sesión. Mantén el peso (o bájalo) hasta que desaparezca; subir ahora no compensa.",
                          suggestedWeightKg: last.topWeightKg, suggestedReps: target.min,
                          sessionsConsidered: considered)
        }

        guard let weight = last.topWeightKg, let reps = last.repsAtTopWeight else {
            return Advice(action: .needMoreData,
                          reason: "La última sesión no tiene kilos y repeticiones en ninguna serie, así que no se puede comparar nada.",
                          suggestedWeightKg: nil, suggestedReps: nil, sessionsConsidered: considered)
        }

        let rir = last.rirAtTopWeight
        let atFailure = (rir ?? 1) <= 0

        // 1. Por debajo del rango: el peso es demasiado para el rango que pide la rutina.
        if reps < target.min {
            let down = max(weight - increment(for: equipment, currentKg: weight), 0)
            return Advice(action: .reduceLoad,
                          reason: "La mejor serie fue de \(reps) repeticiones y la rutina pide \(target.min)–\(target.max). "
                          + "Con menos peso entrarás en el rango.",
                          suggestedWeightKg: down > 0 ? down : nil, suggestedReps: target.min,
                          sessionsConsidered: considered)
        }

        // 2. Ha llegado al tope del rango: toca subir, salvo que fuera al fallo justo.
        if reps >= target.max {
            if atFailure && reps == target.max {
                return Advice(action: .hold,
                              reason: "Llegaste a \(reps) repeticiones, pero al fallo (RIR 0). Repite el mismo peso buscando dejarte "
                              + "una repetición en reserva; cuando te sobre, sube.",
                              suggestedWeightKg: weight, suggestedReps: target.max,
                              sessionsConsidered: considered)
            }
            let step = increment(for: equipment, currentKg: weight)
            let next = equipment == .bodyweight ? nil : PlateMath.rounded(weight + step, barKg: barWeight(for: equipment))
            return Advice(action: .increaseLoad,
                          reason: "Hiciste \(reps) repeticiones con \(NumberFormat.weight(weight))"
                          + (rir.map { ", con RIR \($0)" } ?? "")
                          + ". Has cerrado el rango \(target.min)–\(target.max): toca subir.",
                          suggestedWeightKg: next, suggestedReps: target.min,
                          sessionsConsidered: considered)
        }

        // 3. Dentro del rango. Si hay margen de esfuerzo, buscar repeticiones con el mismo peso.
        if let rir, rir >= 3 {
            return Advice(action: .addReps,
                          reason: "Te quedaron \(rir) repeticiones en reserva: hay margen. Mismo peso, intenta llegar a \(target.max).",
                          suggestedWeightKg: weight, suggestedReps: min(reps + 2, target.max),
                          sessionsConsidered: considered)
        }

        // 4. ¿Estancado? Solo se mira con varias sesiones.
        let stall = stallReport(history: ordered)
        if stall.isStalled {
            return Advice(action: .hold,
                          reason: stall.message + " Antes de forzar: revisa el descanso entre series, el sueño y si te conviene una descarga.",
                          suggestedWeightKg: weight, suggestedReps: min(reps + 1, target.max),
                          sessionsConsidered: considered)
        }

        return Advice(action: .addReps,
                      reason: "Vas por \(reps) repeticiones con \(NumberFormat.weight(weight)) y el rango llega a \(target.max). "
                      + "Suma repeticiones antes de subir peso.",
                      suggestedWeightKg: weight, suggestedReps: min(reps + 1, target.max),
                      sessionsConsidered: considered)
    }

    /// Peso de la barra que se asume al redondear (la mancuerna o la máquina no tienen barra).
    static func barWeight(for equipment: Equipment?) -> Double {
        switch equipment {
        case .barbell, .smith: return 20
        case .ezBar: return 10
        default: return 0
        }
    }

    // MARK: Estancamiento

    struct StallReport: Equatable {
        let isStalled: Bool
        /// Sesiones seguidas sin mejorar.
        let sessionsWithoutProgress: Int
        let message: String
    }

    /// Hacen falta al menos tantas sesiones seguidas sin mejorar para hablar de estancamiento.
    static let stallSessions = 3
    /// Mejora mínima de 1RM estimado (en %) para considerar que hubo progreso.
    static let progressThresholdPercent = 1.0

    /// Mira las últimas sesiones y dice si el ejercicio está parado.
    /// Un ejercicio no está estancado por una sesión mala: hacen falta varias.
    static func stallReport(history: [ExerciseSessionSummary]) -> StallReport {
        let ordered = history.sorted { $0.date < $1.date }
        let maxes: [Double] = ordered.compactMap(\.estimatedOneRepMax)
        guard maxes.count >= stallSessions else {
            return StallReport(isStalled: false, sessionsWithoutProgress: 0,
                              message: "Aún no hay sesiones suficientes para saber si estás estancado.")
        }

        // Cuenta hacia atrás cuántas sesiones llevan sin superar el mejor valor anterior.
        var best = maxes[0]
        var withoutProgress = 0
        for value in maxes.dropFirst() {
            if value > best * (1 + progressThresholdPercent / 100) {
                best = value
                withoutProgress = 0
            } else {
                withoutProgress += 1
                best = max(best, value)
            }
        }

        if withoutProgress >= stallSessions {
            return StallReport(isStalled: true, sessionsWithoutProgress: withoutProgress,
                               message: "Llevas \(withoutProgress) sesiones sin mejorar la mejor serie de este ejercicio.")
        }
        return StallReport(isStalled: false, sessionsWithoutProgress: withoutProgress,
                           message: withoutProgress == 0 ? "La última sesión mejoró." :
                            "\(withoutProgress) sesión(es) sin mejorar: todavía es pronto para hablar de estancamiento.")
    }

    // MARK: Descarga

    struct DeloadSuggestion: Equatable {
        let isRecommended: Bool
        let reason: String
        /// Qué hacer esa semana.
        let plan: String
    }

    /// Semanas seguidas de trabajo duro a partir de las que conviene plantearse una descarga.
    static let deloadAfterWeeks = 6

    /// Propone (o no) una semana de descarga. Mira tres cosas: semanas acumuladas,
    /// ejercicios estancados y volumen por encima de la referencia.
    /// Es una sugerencia; nunca cambia la rutina por su cuenta.
    static func deloadSuggestion(hardWeeksInARow: Int, stalledExercises: Int,
                                 musclesAboveReference: Int, fallingTrends: Int = 0) -> DeloadSuggestion {
        let plan = "Durante una semana: mismas sesiones, la mitad de series efectivas y un 10–20 % menos de peso, "
            + "dejando 3–4 repeticiones en reserva. No busques récords. A la semana siguiente vuelves a donde estabas."

        if fallingTrends >= 2 {
            return DeloadSuggestion(isRecommended: true,
                                    reason: "Hay \(fallingTrends) ejercicios en los que la fuerza está bajando, no estancada. Eso suele ser fatiga acumulada.",
                                    plan: plan)
        }
        if hardWeeksInARow >= deloadAfterWeeks {
            return DeloadSuggestion(isRecommended: true,
                                    reason: "Llevas \(hardWeeksInARow) semanas seguidas entrenando duro sin bajar el pie.",
                                    plan: plan)
        }
        if stalledExercises >= 3 {
            return DeloadSuggestion(isRecommended: true,
                                    reason: "Hay \(stalledExercises) ejercicios estancados a la vez, que suele ser señal de fatiga más que de falta de estímulo.",
                                    plan: plan)
        }
        if musclesAboveReference >= 3 {
            return DeloadSuggestion(isRecommended: true,
                                    reason: "Hay \(musclesAboveReference) grupos musculares por encima de la referencia de volumen varias semanas.",
                                    plan: plan)
        }
        return DeloadSuggestion(isRecommended: false,
                                reason: "Por ahora no hay señales de que haga falta descargar: la fuerza no baja y el volumen está en rango.",
                                plan: plan)
    }

    // MARK: Objetivo de la próxima sesión

    /// Qué apuntar como objetivo de cada serie de la próxima sesión, a partir de la anterior.
    /// Devuelve la lista de series con el peso y las repeticiones a las que apuntar.
    static func plannedSets(previous: [LoggedSet], advice: Advice, targetSets: Int, target: RepTarget) -> [LoggedSet] {
        let previousWork = previous.filter { $0.kind.countsAsWork }
        return (0..<max(targetSets, 0)).map { index in
            let old = index < previousWork.count ? previousWork[index] : previousWork.last
            let weight: Double?
            switch advice.action {
            case .increaseLoad, .reduceLoad:
                weight = advice.suggestedWeightKg ?? old?.weightKg
            case .deload:
                weight = old?.weightKg.map { ($0 * 0.85 / 0.5).rounded() * 0.5 }
            default:
                weight = old?.weightKg
            }
            return LoggedSet(order: index, kind: .effective, weightKg: weight,
                             reps: nil, rir: nil, rpe: nil, restSeconds: old?.restSeconds,
                             isCompleted: false, note: "")
        }
    }
}
