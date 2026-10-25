import Foundation

/// Sueño, fatiga, energía, estrés y agujetas. Todo lo apunta el usuario a mano.
///
/// Lo que esto NO es: un diagnóstico. No convierte una puntuación en un veredicto médico
/// ni interpreta síntomas. Resume lo que has escrito, avisa de extremos y, cuando hay señales
/// que no son de entrenamiento, dice que eso lo mira un profesional sanitario.

/// Escala de 1 a 5 que usan casi todas las preguntas.
enum RecoveryScale {
    static let range = 1...5

    /// Etiquetas para una escala en la que más es MEJOR (calidad de sueño, energía).
    static func betterLabel(_ value: Int) -> String {
        switch value {
        case 1: return "Muy mal"
        case 2: return "Mal"
        case 3: return "Normal"
        case 4: return "Bien"
        default: return "Muy bien"
        }
    }

    /// Etiquetas para una escala en la que más es PEOR (fatiga, estrés, agujetas).
    static func worseLabel(_ value: Int) -> String {
        switch value {
        case 1: return "Nada"
        case 2: return "Poco"
        case 3: return "Algo"
        case 4: return "Bastante"
        default: return "Mucho"
        }
    }
}

/// Lo apuntado un día.
struct RecoveryEntry: Equatable {
    var date: Date
    /// Horas dormidas.
    var sleepHours: Double?
    /// 1 muy mal … 5 muy bien.
    var sleepQuality: Int?
    /// 1 sin energía … 5 con mucha.
    var energy: Int?
    /// 1 nada cansado … 5 muy cansado.
    var fatigue: Int?
    /// 1 sin estrés … 5 mucho.
    var stress: Int?
    /// 1 sin agujetas … 5 muchas.
    var soreness: Int?
    /// Una molestia o dolor, que no es lo mismo que agujetas.
    var hasDiscomfort: Bool
    var note: String

    init(date: Date, sleepHours: Double? = nil, sleepQuality: Int? = nil, energy: Int? = nil,
         fatigue: Int? = nil, stress: Int? = nil, soreness: Int? = nil,
         hasDiscomfort: Bool = false, note: String = "") {
        self.date = date
        self.sleepHours = sleepHours
        self.sleepQuality = sleepQuality
        self.energy = energy
        self.fatigue = fatigue
        self.stress = stress
        self.soreness = soreness
        self.hasDiscomfort = hasDiscomfort
        self.note = note
    }

    /// Cuántas de las seis preguntas están contestadas.
    var answeredCount: Int {
        [sleepHours != nil, sleepQuality != nil, energy != nil,
         fatigue != nil, stress != nil, soreness != nil].filter { $0 }.count
    }

    var isEmpty: Bool { answeredCount == 0 && !hasDiscomfort && note.isEmpty }
}

// MARK: - Resumen del día

struct Readiness: Equatable {
    enum Verdict: String {
        case good, fair, low, unknown

        var label: String {
            switch self {
            case .good: return "Buena"
            case .fair: return "Regular"
            case .low: return "Baja"
            case .unknown: return "Sin datos suficientes"
            }
        }

        var symbol: String {
            switch self {
            case .good: return "checkmark.circle.fill"
            case .fair: return "minus.circle.fill"
            case .low: return "exclamationmark.triangle.fill"
            case .unknown: return "questionmark.circle"
            }
        }
    }

    /// 0 a 100. nil si no hay respuestas suficientes.
    let score: Int?
    /// Cuántas respuestas se han usado para calcularlo.
    let inputsUsed: Int
    let verdict: Verdict
    /// Qué se puede decir con esto, dicho con prudencia.
    let message: String
    /// Avisos que no son una puntuación: molestias, poco sueño mantenido…
    let warnings: [String]

    /// Por debajo de dos respuestas no se da ningún veredicto.
    static let minimumInputs = 2
}

enum RecoveryAnalysis {
    /// Horas de sueño a partir de las cuales se considera descanso completo.
    static let sleepTarget = 8.0
    /// Por debajo de esto, el sueño cuenta como muy escaso.
    static let sleepFloor = 4.0

    /// Normaliza una respuesta de 1 a 5 en la que más es mejor.
    static func normalizedBetter(_ value: Int?) -> Double? {
        guard let value, RecoveryScale.range.contains(value) else { return nil }
        return Double(value - 1) / 4
    }

    /// Normaliza una respuesta de 1 a 5 en la que más es peor.
    static func normalizedWorse(_ value: Int?) -> Double? {
        guard let value, RecoveryScale.range.contains(value) else { return nil }
        return Double(5 - value) / 4
    }

    static func normalizedSleep(_ hours: Double?) -> Double? {
        guard let hours, hours > 0 else { return nil }
        let clamped = min(max(hours, sleepFloor), sleepTarget)
        return (clamped - sleepFloor) / (sleepTarget - sleepFloor)
    }

    /// Resumen del día. Solo usa lo que está contestado: no rellena huecos con medias inventadas.
    static func readiness(_ entry: RecoveryEntry, recent: [RecoveryEntry] = []) -> Readiness {
        let parts = [normalizedSleep(entry.sleepHours),
                     normalizedBetter(entry.sleepQuality),
                     normalizedBetter(entry.energy),
                     normalizedWorse(entry.fatigue),
                     normalizedWorse(entry.stress),
                     normalizedWorse(entry.soreness)].compactMap { $0 }

        let warnings = self.warnings(entry, recent: recent)

        guard parts.count >= Readiness.minimumInputs else {
            return Readiness(score: nil, inputsUsed: parts.count, verdict: .unknown,
                             message: "Contesta al menos dos preguntas y verás un resumen del día. "
                             + "Con una sola respuesta no se puede decir nada útil.",
                             warnings: warnings)
        }

        let score = Int((parts.reduce(0, +) / Double(parts.count) * 100).rounded())
        let verdict: Readiness.Verdict = score >= 70 ? .good : (score >= 45 ? .fair : .low)
        let message: String
        switch verdict {
        case .good:
            message = "Por lo que has apuntado, hoy estás para entrenar bien. Esto resume tus respuestas: no es un diagnóstico."
        case .fair:
            message = "Vas regular. Puedes entrenar igual, y si alguna serie no sale, no pasa nada: "
                + "mantener el peso una sesión también es progresar. Esto resume tus respuestas, no es un diagnóstico."
        case .low:
            message = "Lo que has apuntado apunta a poca recuperación. Plantéate bajar las series efectivas o "
                + "dejar más repeticiones en reserva hoy. Esto resume tus respuestas, no es un diagnóstico."
        case .unknown:
            message = ""
        }
        return Readiness(score: score, inputsUsed: parts.count, verdict: verdict, message: message, warnings: warnings)
    }

    /// Noches seguidas por debajo de este sueño que hacen falta para avisar.
    static let shortSleepStreak = 3
    static let shortSleepHours = 6.0

    static func warnings(_ entry: RecoveryEntry, recent: [RecoveryEntry]) -> [String] {
        var out: [String] = []

        if entry.hasDiscomfort {
            out.append("Has apuntado una molestia. Las agujetas se van en unos días; un dolor que va a más, "
                       + "que es agudo o que te limita el movimiento lo tiene que ver un profesional sanitario. "
                       + "ATLAS no diagnostica ni trata lesiones.")
        }

        // Sueño corto mantenido: se mira el día de hoy y los anteriores seguidos.
        let ordered = ([entry] + recent.sorted { $0.date > $1.date }).prefix(shortSleepStreak)
        let hours = ordered.compactMap(\.sleepHours)
        if hours.count == shortSleepStreak, hours.allSatisfy({ $0 < shortSleepHours }) {
            out.append("Llevas \(shortSleepStreak) días durmiendo menos de \(NumberFormat.oneDecimal(shortSleepHours)) horas. "
                       + "Es lo que más suele frenar la recuperación y el rendimiento.")
        }

        if let stress = entry.stress, let fatigue = entry.fatigue, stress >= 4, fatigue >= 4 {
            out.append("Mucho estrés y mucha fatiga a la vez. Una sesión más corta y con margen suele sentar mejor "
                       + "que forzar y tener que parar la semana siguiente.")
        }

        if let soreness = entry.soreness, soreness == 5 {
            out.append("Agujetas muy fuertes: deja ese grupo muscular para más adelante o baja series. "
                       + "Entrenar con agujetas fuertes no es peligroso, pero sí suele restar rendimiento.")
        }
        return out
    }

    // MARK: Medias y tendencias

    struct Averages: Equatable {
        let sleepHours: Double?
        let sleepQuality: Double?
        let energy: Double?
        let fatigue: Double?
        let stress: Double?
        let soreness: Double?
        let daysLogged: Int
        let daysWithDiscomfort: Int
    }

    static func averages(_ entries: [RecoveryEntry]) -> Averages {
        func mean(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        let logged = entries.filter { !$0.isEmpty }
        return Averages(
            sleepHours: mean(entries.compactMap(\.sleepHours)),
            sleepQuality: mean(entries.compactMap(\.sleepQuality).map(Double.init)),
            energy: mean(entries.compactMap(\.energy).map(Double.init)),
            fatigue: mean(entries.compactMap(\.fatigue).map(Double.init)),
            stress: mean(entries.compactMap(\.stress).map(Double.init)),
            soreness: mean(entries.compactMap(\.soreness).map(Double.init)),
            daysLogged: logged.count,
            daysWithDiscomfort: entries.filter(\.hasDiscomfort).count
        )
    }
}

// MARK: - Recuperación y rendimiento

/// Relaciona lo apuntado de recuperación con lo que ha dado el entrenamiento.
/// Dice si dos cosas se mueven juntas, y deja claro que eso NO significa que una cause la otra.
enum RecoveryPerformance {
    /// Semanas mínimas para intentar relacionar dos series. Con menos no se dice nada.
    static let minimumPoints = 6
    /// A partir de aquí se considera que hay relación apreciable.
    static let noticeable = 0.5

    struct Relation: Equatable {
        /// Coeficiente de correlación de Pearson (−1 a 1). nil si no hay datos suficientes.
        let coefficient: Double?
        let points: Int
        let summary: String

        var hasEnoughData: Bool { coefficient != nil }
    }

    /// Correlación de Pearson entre dos series del mismo tamaño.
    static func correlation(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 2 else { return nil }
        let n = Double(xs.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var num = 0.0, denX = 0.0, denY = 0.0
        for (x, y) in zip(xs, ys) {
            num += (x - meanX) * (y - meanY)
            denX += (x - meanX) * (x - meanX)
            denY += (y - meanY) * (y - meanY)
        }
        guard denX > 0.000_001, denY > 0.000_001 else { return nil }
        return num / (denX * denY).squareRoot()
    }

    /// Relaciona el sueño medio semanal con el tonelaje semanal.
    static func sleepVersusTonnage(sleep: [Double], tonnage: [Double]) -> Relation {
        guard sleep.count == tonnage.count, sleep.count >= minimumPoints,
              let r = correlation(sleep, tonnage) else {
            return Relation(coefficient: nil, points: min(sleep.count, tonnage.count),
                            summary: "Hacen falta al menos \(minimumPoints) semanas con sueño y entrenamiento apuntados "
                            + "para mirar si se mueven juntos.")
        }
        let strength = abs(r) >= noticeable ? "se mueven bastante juntos" : "no se mueven juntos de forma apreciable"
        let direction = r > 0 ? "más sueño coincide con más trabajo" : "más sueño coincide con menos trabajo"
        let detail = abs(r) >= noticeable ? " En tus semanas, \(direction)." : ""
        return Relation(coefficient: r, points: sleep.count,
                        summary: "Sueño y volumen \(strength) (r = \(NumberFormat.oneDecimal(r))).\(detail) "
                        + "Que dos cosas coincidan no quiere decir que una cause la otra: "
                        + "podría haber un tercer motivo detrás.")
    }
}

// MARK: - Movilidad y descanso

/// Sugerencias generales, iguales para todo el mundo y sin pretensión clínica.
enum RecoveryTips {
    struct Tip: Identifiable, Equatable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
    }

    static let all: [Tip] = [
        Tip(id: "sleep", title: "El sueño es lo primero",
            detail: "Es la palanca con más efecto y la más barata. Una hora más de sueño suele notarse en el gimnasio "
            + "más que cualquier suplemento.", symbol: "moon.stars.fill"),
        Tip(id: "walk", title: "Moverse suave en los días libres",
            detail: "Un paseo de 20–30 minutos ayuda a llevar mejor las agujetas sin añadir fatiga.", symbol: "figure.walk"),
        Tip(id: "mobility", title: "Movilidad donde te falta",
            detail: "Dedica unos minutos a la articulación que te limita en tus ejercicios (cadera, tobillo u hombro). "
            + "Estirar por estirar, sin un objetivo, aporta poco.", symbol: "figure.cooldown"),
        Tip(id: "food", title: "Comer y beber suficiente",
            detail: "Un déficit muy agresivo y poca proteína hacen que todo cueste más y que la fuerza se caiga.",
            symbol: "fork.knife"),
        Tip(id: "deload", title: "Bajar el pie a tiempo",
            detail: "Una semana más suave cada cierto tiempo no es perder el trabajo hecho: es lo que permite seguir subiendo.",
            symbol: "arrow.down.circle"),
        Tip(id: "pain", title: "Dolor no es agujetas",
            detail: "Las agujetas aparecen al día siguiente y se van solas. Un dolor localizado, agudo o que va a más "
            + "lo tiene que ver un profesional sanitario.", symbol: "cross.case.fill"),
    ]
}
