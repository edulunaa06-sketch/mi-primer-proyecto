import Foundation

/// Lógica de fuerza: series, cargas, 1RM estimado, tonelaje y tendencia.
/// Todo son funciones puras sobre valores, sin base de datos ni interfaz, para poder probarlas.

// MARK: - Tipo de serie

enum SetKind: String, Codable, CaseIterable, Identifiable {
    /// Aproximación: sube la temperatura y el peso, pero no es trabajo efectivo.
    case warmup
    /// Serie de trabajo. Es la que cuenta para el volumen.
    case effective
    /// Serie inmediata con menos peso tras llevar una al límite.
    case dropset
    /// Serie con menos peso después de la pesada, para acumular trabajo.
    case backoff

    var id: String { rawValue }

    var label: String {
        switch self {
        case .warmup: return "Calentamiento"
        case .effective: return "Efectiva"
        case .dropset: return "Drop set"
        case .backoff: return "Back-off"
        }
    }

    var shortLabel: String {
        switch self {
        case .warmup: return "Cal."
        case .effective: return "Efec."
        case .dropset: return "Drop"
        case .backoff: return "Back"
        }
    }

    /// Las series de calentamiento no suman volumen de entrenamiento.
    /// Drop y back-off sí: son trabajo real, aunque sea con menos peso.
    var countsAsWork: Bool { self != .warmup }
}

// MARK: - Una serie registrada

/// Una serie tal y como la ha apuntado el usuario. Todo es opcional a propósito:
/// se puede apuntar solo las repeticiones (peso corporal) o solo el peso (serie en curso).
struct LoggedSet: Equatable, Codable {
    var order: Int
    var kind: SetKind
    var weightKg: Double?
    var reps: Int?
    /// Repeticiones en reserva (las que te habrían quedado). 0 = al fallo.
    var rir: Int?
    /// Esfuerzo percibido de 1 a 10. Se deriva de RIR si no se escribe.
    var rpe: Double?
    var restSeconds: Int?
    var isCompleted: Bool
    var note: String

    init(order: Int, kind: SetKind = .effective, weightKg: Double? = nil, reps: Int? = nil,
         rir: Int? = nil, rpe: Double? = nil, restSeconds: Int? = nil,
         isCompleted: Bool = false, note: String = "") {
        self.order = order
        self.kind = kind
        self.weightKg = weightKg
        self.reps = reps
        self.rir = rir
        self.rpe = rpe
        self.restSeconds = restSeconds
        self.isCompleted = isCompleted
        self.note = note
    }

    /// Tiene los dos datos que hacen falta para calcular volumen y 1RM.
    var hasLoadAndReps: Bool { (weightKg ?? 0) > 0 && (reps ?? 0) > 0 }

    /// Repeticiones apuntadas, con o sin peso (sirve para el peso corporal).
    var hasReps: Bool { (reps ?? 0) > 0 }

    /// Kilos levantados en la serie (peso × repeticiones). 0 si falta algún dato.
    var volumeKg: Double {
        guard hasLoadAndReps, kind.countsAsWork else { return 0 }
        return (weightKg ?? 0) * Double(reps ?? 0)
    }

    /// RPE equivalente al RIR apuntado (RIR 0 → RPE 10, RIR 3 → RPE 7).
    /// Si el usuario escribió un RPE, manda el suyo.
    var effortRPE: Double? {
        if let rpe { return rpe }
        guard let rir else { return nil }
        return max(10 - Double(rir), 1)
    }

    /// Repeticiones que probablemente habrías podido hacer (las hechas más las que quedaban).
    /// Es lo que permite estimar el máximo de una serie que no se ha llevado al fallo.
    var repsToFailure: Int? {
        guard let reps, reps > 0 else { return nil }
        return reps + max(rir ?? 0, 0)
    }
}

// MARK: - 1RM estimado

/// Fiabilidad de una estimación de 1RM: cuantas más repeticiones, menos fiable.
enum OneRepMaxConfidence: String {
    case high, medium, low

    var label: String {
        switch self {
        case .high: return "Fiabilidad alta"
        case .medium: return "Fiabilidad media"
        case .low: return "Orientativo"
        }
    }

    var note: String {
        switch self {
        case .high: return "Estimado con una serie de pocas repeticiones: es donde las fórmulas aciertan más."
        case .medium: return "Estimado con una serie de 7 a 12 repeticiones: puede desviarse algo."
        case .low: return "Estimado con muchas repeticiones: tómalo solo como referencia."
        }
    }
}

/// Estimaciones de una repetición máxima. Son fórmulas, no una medición:
/// sirven para ver la tendencia, no para decidir un intento real a una repetición.
enum OneRepMax {
    /// Epley: w · (1 + r/30). La más usada.
    static func epley(weightKg: Double, reps: Int) -> Double? {
        guard weightKg > 0, reps >= 1 else { return nil }
        if reps == 1 { return weightKg }
        return weightKg * (1 + Double(reps) / 30)
    }

    /// Brzycki: w · 36/(37 − r). Solo tiene sentido por debajo de 37 repeticiones.
    static func brzycki(weightKg: Double, reps: Int) -> Double? {
        guard weightKg > 0, reps >= 1, reps < 37 else { return nil }
        if reps == 1 { return weightKg }
        return weightKg * 36 / (37 - Double(reps))
    }

    /// Lombardi: w · r^0,10.
    static func lombardi(weightKg: Double, reps: Int) -> Double? {
        guard weightKg > 0, reps >= 1 else { return nil }
        if reps == 1 { return weightKg }
        return weightKg * pow(Double(reps), 0.10)
    }

    /// Estimación de referencia: media de Epley y Brzycki (se compensan entre sí).
    /// Si Brzycki no aplica, se queda con Epley.
    static func estimate(weightKg: Double, reps: Int) -> Double? {
        guard let e = epley(weightKg: weightKg, reps: reps) else { return nil }
        guard let b = brzycki(weightKg: weightKg, reps: reps) else { return e }
        return (e + b) / 2
    }

    /// Estimación contando las repeticiones que quedaban (RIR): una serie de 8 con 2 en reserva
    /// se estima como una de 10. Es la forma honesta de comparar series que no van al fallo.
    static func estimate(weightKg: Double, reps: Int, rir: Int?) -> Double? {
        let effective = reps + max(rir ?? 0, 0)
        return estimate(weightKg: weightKg, reps: effective)
    }

    static func confidence(reps: Int) -> OneRepMaxConfidence {
        if reps <= 6 { return .high }
        if reps <= 12 { return .medium }
        return .low
    }

    /// Porcentaje del 1RM que suele corresponder a un número de repeticiones (inversa de Epley).
    /// 1 → 100 %, 5 → ~86 %, 10 → ~75 %.
    static func percentOfMax(reps: Int) -> Double? {
        guard reps >= 1 else { return nil }
        // Una repetición es el 100 %: así cuadra con `epley`, que ahí devuelve el propio peso.
        if reps == 1 { return 1 }
        return 1 / (1 + Double(reps) / 30)
    }

    /// Peso aproximado para hacer `reps` repeticiones con un 1RM dado.
    static func workingWeight(oneRepMax: Double, reps: Int) -> Double? {
        guard oneRepMax > 0, let p = percentOfMax(reps: reps) else { return nil }
        return oneRepMax * p
    }
}

// MARK: - Resumen de un ejercicio en una sesión

/// Lo que dio de sí un ejercicio en una sesión concreta. Se calcula siempre a partir
/// de las series; nunca se guarda un total escrito a mano.
struct ExerciseSessionSummary: Equatable {
    let date: Date
    let exerciseID: String
    /// Serie más pesada con repeticiones apuntadas (a igual peso, la de más repeticiones).
    let topWeightKg: Double?
    let repsAtTopWeight: Int?
    let rirAtTopWeight: Int?
    /// Kilos totales movidos en las series de trabajo (peso × reps).
    let volumeKg: Double
    let totalReps: Int
    /// Series de trabajo con repeticiones apuntadas (sin calentamientos).
    let workSets: Int
    /// Media de RIR de las series de trabajo que lo tengan.
    let averageRIR: Double?

    /// nil si no hay ni una serie con repeticiones: una sesión sin datos no es una sesión.
    init?(date: Date, exerciseID: String, sets: [LoggedSet]) {
        let work = sets.filter { $0.kind.countsAsWork && $0.hasReps }
        guard !work.isEmpty else { return nil }
        self.date = date
        self.exerciseID = exerciseID

        let complete = work.filter(\.hasLoadAndReps)
        let top = complete.max { a, b in
            (a.weightKg ?? 0, a.reps ?? 0) < (b.weightKg ?? 0, b.reps ?? 0)
        }
        topWeightKg = top?.weightKg
        repsAtTopWeight = top?.reps
        rirAtTopWeight = top?.rir
        volumeKg = complete.reduce(0) { $0 + $1.volumeKg }
        totalReps = work.reduce(0) { $0 + ($1.reps ?? 0) }
        workSets = work.count
        let rirs = work.compactMap(\.rir)
        averageRIR = rirs.isEmpty ? nil : Double(rirs.reduce(0, +)) / Double(rirs.count)
    }

    /// 1RM estimado de la mejor serie, contando el RIR si lo hay.
    var estimatedOneRepMax: Double? {
        guard let w = topWeightKg, let r = repsAtTopWeight else { return nil }
        return OneRepMax.estimate(weightKg: w, reps: r, rir: rirAtTopWeight)
    }

    var oneRepMaxConfidence: OneRepMaxConfidence? {
        guard let r = repsAtTopWeight else { return nil }
        return OneRepMax.confidence(reps: r + max(rirAtTopWeight ?? 0, 0))
    }

    /// Texto corto de la mejor serie: «80 kg × 8 (RIR 2)».
    var topSetText: String? {
        guard let w = topWeightKg, let r = repsAtTopWeight else { return nil }
        var text = "\(NumberFormat.weight(w)) × \(r)"
        if let rir = rirAtTopWeight { text += " (RIR \(rir))" }
        return text
    }
}

// MARK: - Tendencia de fuerza

/// Cómo va la fuerza de un ejercicio a lo largo de varias sesiones.
/// Nunca saca conclusiones de una sola sesión.
struct StrengthTrend: Equatable {
    /// Un punto de la serie: el 1RM estimado de una sesión.
    struct Point: Equatable {
        let date: Date
        let oneRepMax: Double
    }

    enum Verdict: String {
        case rising, flat, falling, notEnoughData

        var label: String {
            switch self {
            case .rising: return "Subiendo"
            case .flat: return "Estable"
            case .falling: return "Bajando"
            case .notEnoughData: return "Sin datos suficientes"
            }
        }
    }

    /// Serie de 1RM estimado, de la sesión más antigua a la más reciente.
    let points: [Point]
    let verdict: Verdict
    /// Cambio porcentual entre la primera y la última sesión comparada.
    let changePercent: Double?
    /// Cambio en kilos por semana (pendiente de la recta de ajuste).
    let kgPerWeek: Double?

    /// Hacen falta al menos tres sesiones con 1RM estimable para hablar de tendencia.
    static let minimumSessions = 3
    /// Por debajo de este cambio total, se considera estable (ruido de medición).
    static let flatThresholdPercent = 2.0

    init(summaries: [ExerciseSessionSummary]) {
        let ordered = summaries.sorted { $0.date < $1.date }
        let pts: [Point] = ordered.compactMap { s in
            guard let max1 = s.estimatedOneRepMax else { return nil }
            return Point(date: s.date, oneRepMax: max1)
        }
        points = pts
        guard pts.count >= Self.minimumSessions, let first = pts.first, let last = pts.last, first.oneRepMax > 0 else {
            verdict = .notEnoughData
            changePercent = nil
            kgPerWeek = nil
            return
        }
        let change = (last.oneRepMax - first.oneRepMax) / first.oneRepMax * 100
        changePercent = change
        kgPerWeek = Self.slopePerWeek(pts)
        if abs(change) < Self.flatThresholdPercent {
            verdict = .flat
        } else {
            verdict = change > 0 ? .rising : .falling
        }
    }

    /// Pendiente por mínimos cuadrados, en kg por semana.
    static func slopePerWeek(_ points: [Point]) -> Double? {
        guard points.count >= 2, let base = points.first?.date else { return nil }
        let week = 7.0 * 24 * 3600
        let xs = points.map { $0.date.timeIntervalSince(base) / week }
        let ys = points.map(\.oneRepMax)
        let n = Double(points.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (x, y) in zip(xs, ys) {
            num += (x - meanX) * (y - meanY)
            den += (x - meanX) * (x - meanX)
        }
        guard den > 0.000_001 else { return nil }
        return num / den
    }
}

// MARK: - Récords personales

/// Tipos de récord que la app reconoce. Todos salen de series realmente apuntadas.
enum RecordKind: String, Codable, CaseIterable, Identifiable {
    /// Peso más alto movido en una serie con repeticiones.
    case topWeight
    /// 1RM estimado más alto.
    case estimatedOneRepMax
    /// Más kilos totales en una sesión de ese ejercicio.
    case sessionVolume
    /// Más repeticiones con un mismo peso.
    case repsAtWeight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .topWeight: return "Peso máximo"
        case .estimatedOneRepMax: return "1RM estimado"
        case .sessionVolume: return "Volumen en una sesión"
        case .repsAtWeight: return "Repeticiones con el mismo peso"
        }
    }

    var symbol: String {
        switch self {
        case .topWeight: return "scalemass.fill"
        case .estimatedOneRepMax: return "bolt.fill"
        case .sessionVolume: return "chart.bar.fill"
        case .repsAtWeight: return "repeat"
        }
    }

    /// El 1RM es una estimación, no una medición: hay que decirlo.
    var isEstimate: Bool { self == .estimatedOneRepMax }
}

/// Un récord batido, listo para guardar o celebrar.
struct RecordCandidate: Equatable {
    let kind: RecordKind
    let exerciseID: String
    let exerciseName: String
    let value: Double
    let weightKg: Double?
    let reps: Int?
    let date: Date
    /// Valor anterior, si había. nil = primer registro (no se celebra como récord).
    let previous: Double?

    var isFirstEver: Bool { previous == nil }

    var improvement: Double? {
        guard let previous, previous > 0 else { return nil }
        return value - previous
    }
}

enum PersonalRecords {
    /// Compara el resumen de una sesión con los mejores valores previos y devuelve los récords batidos.
    /// `previousBest` lleva el mejor valor anterior de cada tipo (nil si no había).
    /// Un primer registro se devuelve marcado como tal: es una marca de partida, no un récord batido.
    static func candidates(from summary: ExerciseSessionSummary, exerciseName: String,
                           previousBest: [RecordKind: Double]) -> [RecordCandidate] {
        var out: [RecordCandidate] = []

        func consider(_ kind: RecordKind, value: Double?, weight: Double? = nil, reps: Int? = nil) {
            guard let value, value > 0 else { return }
            let previous = previousBest[kind]
            // Margen pequeño para que un redondeo no cuente como récord.
            guard previous == nil || value > (previous ?? 0) + 0.001 else { return }
            out.append(RecordCandidate(kind: kind, exerciseID: summary.exerciseID, exerciseName: exerciseName,
                                       value: value, weightKg: weight, reps: reps,
                                       date: summary.date, previous: previous))
        }

        consider(.topWeight, value: summary.topWeightKg, weight: summary.topWeightKg, reps: summary.repsAtTopWeight)
        consider(.estimatedOneRepMax, value: summary.estimatedOneRepMax,
                 weight: summary.topWeightKg, reps: summary.repsAtTopWeight)
        consider(.sessionVolume, value: summary.volumeKg > 0 ? summary.volumeKg : nil)
        return out
    }

    /// Récord de repeticiones con un peso concreto: solo cuenta si el peso es el mismo
    /// (comparar reps con pesos distintos no dice nada).
    static func repsRecord(weightKg: Double, reps: Int, previousRepsAtSameWeight: Int?) -> Bool {
        guard weightKg > 0, reps > 0 else { return false }
        guard let previous = previousRepsAtSameWeight else { return false }
        return reps > previous
    }
}

// MARK: - Calculadora de discos

/// Qué discos poner en la barra para llegar a un peso. Solo aritmética: si no se puede
/// llegar exacto, lo dice en vez de inventarse un peso.
enum PlateMath {
    /// Discos de gimnasio habituales en kilos, de mayor a menor.
    static let commonPlatesKg: [Double] = [25, 20, 15, 10, 5, 2.5, 2, 1.25, 1, 0.5]

    struct Result: Equatable {
        /// Discos de UN lado, de mayor a menor.
        let perSide: [Double]
        /// Peso al que se llega de verdad con esos discos.
        let achievedKg: Double
        /// Lo que falta (o sobra) respecto al pedido. 0 = exacto.
        let differenceKg: Double

        var isExact: Bool { abs(differenceKg) < 0.001 }

        /// «20 + 10 + 2,5» (por lado).
        var perSideText: String {
            perSide.map(NumberFormat.plate).joined(separator: " + ")
        }
    }

    /// Reparte el peso en discos por lado.
    /// - Returns: nil si el peso pedido no llega ni a la barra sola.
    static func plates(forTotal totalKg: Double, barKg: Double = 20,
                       available: [Double] = commonPlatesKg) -> Result? {
        guard totalKg >= barKg, barKg >= 0 else { return nil }
        let perSideTarget = (totalKg - barKg) / 2
        guard perSideTarget >= 0 else { return nil }
        var remaining = perSideTarget
        var used: [Double] = []
        for plate in available.sorted(by: >) where plate > 0 {
            while remaining >= plate - 0.001 {
                used.append(plate)
                remaining -= plate
            }
        }
        let achievedPerSide = used.reduce(0, +)
        let achieved = barKg + achievedPerSide * 2
        return Result(perSide: used, achievedKg: achieved, differenceKg: achieved - totalKg)
    }

    /// Siguiente peso alcanzable por encima del actual con los discos disponibles.
    /// Útil para que la progresión no proponga kilos imposibles de montar.
    static func nextAchievable(above currentKg: Double, barKg: Double = 20,
                               available: [Double] = commonPlatesKg) -> Double? {
        guard let smallest = available.filter({ $0 > 0 }).min() else { return nil }
        // El salto mínimo real es dos discos pequeños (uno por lado).
        let step = smallest * 2
        let base = max(currentKg, barKg)
        let next = (base / step).rounded(.down) * step + step
        return next > currentKg ? next : next + step
    }

    /// Redondea un peso al múltiplo montable más cercano (hacia abajo, para no pasarse).
    static func rounded(_ kg: Double, barKg: Double = 20, available: [Double] = commonPlatesKg) -> Double {
        guard let smallest = available.filter({ $0 > 0 }).min(), kg > barKg else { return max(kg, 0) }
        let step = smallest * 2
        let plates = ((kg - barKg) / step).rounded(.down) * step
        return barKg + max(plates, 0)
    }
}

// MARK: - Reloj de la sesión

/// Cuánto ha durado una sesión, aunque se pause o se cierre la app en medio.
/// Se guarda lo acumulado y, si está en marcha, desde cuándo: así el tiempo
/// sobrevive a cerrar la app y nunca se cuenta dos veces.
struct SessionClock: Equatable {
    /// Segundos ya contados antes de la última pausa.
    var accumulatedSeconds: Int
    /// Momento en que se puso en marcha. nil = está en pausa.
    var runningSince: Date?

    init(accumulatedSeconds: Int = 0, runningSince: Date? = nil) {
        self.accumulatedSeconds = max(accumulatedSeconds, 0)
        self.runningSince = runningSince
    }

    var isRunning: Bool { runningSince != nil }

    /// Segundos totales a día de hoy. Un reloj del futuro (cambio de hora) no resta tiempo.
    func elapsed(at now: Date) -> Int {
        guard let runningSince else { return accumulatedSeconds }
        return accumulatedSeconds + max(Int(now.timeIntervalSince(runningSince)), 0)
    }

    func started(at now: Date) -> SessionClock {
        isRunning ? self : SessionClock(accumulatedSeconds: accumulatedSeconds, runningSince: now)
    }

    func paused(at now: Date) -> SessionClock {
        guard isRunning else { return self }
        return SessionClock(accumulatedSeconds: elapsed(at: now), runningSince: nil)
    }

    func toggled(at now: Date) -> SessionClock {
        isRunning ? paused(at: now) : started(at: now)
    }

    /// Texto «1 h 12 min» o «48 min».
    static func text(seconds: Int) -> String {
        let total = max(seconds, 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours) h \(minutes) min" }
        if minutes > 0 { return "\(minutes) min" }
        return "\(total) s"
    }
}

/// Cuánto se suele tardar en una sesión, para enseñar una estimación antes de empezar.
enum SessionPacing {
    /// Segundos por serie de trabajo, contando ejecución y descanso.
    static let secondsPerSet = 150
    /// Lo que se tarda en llegar, cambiarse y calentar.
    static let overheadSeconds = 420

    static func estimate(workSets: Int) -> Int {
        guard workSets > 0 else { return 0 }
        return overheadSeconds + workSets * secondsPerSet
    }
}
