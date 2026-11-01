import Foundation

// MARK: - Marca manual de un día (calendario)

/// Lo que el usuario dice de un día. Descanso, enfermo y trabajando no cuentan como fallo
/// ni rompen la racha; entrenado cuenta como día cumplido.
enum DayMark: String, Codable, CaseIterable, Identifiable {
    /// Día normal: se evalúa con lo registrado (sirve también para quitar el descanso del viernes).
    case normal
    case rest
    case trained
    case sick
    case work

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .rest: return "Descanso"
        case .trained: return "Entrenado"
        case .sick: return "Malo / enfermo"
        case .work: return "Trabajando"
        }
    }

    var symbol: String {
        switch self {
        case .normal: return "calendar"
        case .rest: return "bed.double.fill"
        case .trained: return "dumbbell.fill"
        case .sick: return "cross.case.fill"
        case .work: return "briefcase.fill"
        }
    }

    /// No cuenta como fallo ni rompe la racha.
    var isExcused: Bool { self == .rest || self == .sick || self == .work }

    /// Los viernes son descanso salvo que el usuario diga otra cosa.
    static let defaultRestWeekday = 5

    /// Marca efectiva: la elegida o, si no hay, descanso los viernes y normal el resto.
    static func effective(explicit: DayMark?, weekday: Int) -> DayMark {
        if let explicit { return explicit }
        return weekday == defaultRestWeekday ? .rest : .normal
    }
}

// MARK: - Evaluación de un día

/// Lo registrado un día, sin SwiftData (para poder probarlo).
struct DayInput: Equatable {
    var date: Date
    var mealsCompleted: Int
    var sessionsScheduled: Int
    var sessionsCompleted: Int
    var steps: Int?
    var stepGoal: Int
    var explicitMark: DayMark?
}

enum DayOutcome: Equatable {
    /// Antes de empezar a usar la app: sin color, no cuenta.
    case beforeStart
    case future
    /// Hoy, todavía sin cumplir: no rompe la racha.
    case today(Double)
    case done(Double)
    case trained
    case excused(DayMark)
    case missed(Double)

    var fraction: Double? {
        switch self {
        case .today(let f), .done(let f), .missed(let f): return f
        case .trained: return 1
        default: return nil
        }
    }

    var isDone: Bool {
        switch self {
        case .done, .trained: return true
        default: return false
        }
    }

    var isExcused: Bool {
        if case .excused = self { return true }
        return false
    }

    var isMissed: Bool {
        if case .missed = self { return true }
        return false
    }
}

enum DayEvaluator {
    /// Un día cuenta como cumplido con el 70 % o más del cumplimiento diario.
    static let doneThreshold = 0.7

    static func compliance(_ input: DayInput) -> DailyCompliance {
        DailyCompliance(mealsCompleted: input.mealsCompleted,
                        sessionsCompleted: input.sessionsCompleted,
                        sessionsScheduled: input.sessionsScheduled,
                        steps: input.steps,
                        stepGoal: input.stepGoal)
    }

    static func outcome(_ input: DayInput, today: Date, trackingStart: Date, calendar: Calendar = DateUtils.calendar) -> DayOutcome {
        let day = calendar.startOfDay(for: input.date)
        let todayStart = calendar.startOfDay(for: today)
        if day > todayStart { return .future }
        // Antes de empezar solo cuentan los días que el usuario marque a mano.
        if (input.explicitMark ?? .normal) == .normal, day < calendar.startOfDay(for: trackingStart) { return .beforeStart }
        let weekday = DateUtils.weekdayMondayBased(day)
        let mark = DayMark.effective(explicit: input.explicitMark, weekday: weekday)
        if mark == .trained { return .trained }
        if mark.isExcused { return .excused(mark) }
        let fraction = compliance(input).fraction
        if fraction >= doneThreshold { return .done(fraction) }
        return day == todayStart ? .today(fraction) : .missed(fraction)
    }
}

// MARK: - Racha

enum Streak {
    struct Result: Equatable {
        var current: Int
        var best: Int
    }

    /// `outcomes` en orden cronológico (del más antiguo a hoy).
    /// Cumplido suma 1; descanso, enfermo o trabajando no suman ni rompen; un fallo la reinicia.
    /// Hoy sin cumplir todavía no rompe la racha.
    static func compute(_ outcomes: [DayOutcome]) -> Result {
        var run = 0
        var best = 0
        for outcome in outcomes {
            switch outcome {
            case .done, .trained:
                run += 1
                best = max(best, run)
            case .missed:
                run = 0
            case .excused, .today, .future, .beforeStart:
                continue
            }
        }
        return Result(current: run, best: best)
    }
}

// MARK: - Objetivo de pasos adaptativo

enum AdaptiveStepGoal {
    static let minimumDays = 3
    static let range = 3000...20000

    /// Media de los días con datos de la última semana + 5 %, redondeada a 250 pasos.
    /// nil si hay menos de 3 días con datos (se mantiene el objetivo actual).
    static func suggest(recentDailySteps: [Int]) -> Int? {
        let days = recentDailySteps.filter { $0 > 0 }
        guard days.count >= minimumDays else { return nil }
        let average = Double(days.reduce(0, +)) / Double(days.count)
        let target = (average * 1.05 / 250).rounded() * 250
        return min(max(Int(target), range.lowerBound), range.upperBound)
    }
}

// MARK: - Hora de los recordatorios

struct ClockTime: Equatable, Codable {
    var hour: Int
    var minute: Int

    var minutesOfDay: Int { hour * 60 + minute }

    init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    init(minutesOfDay: Int) {
        let m = min(max(minutesOfDay, 0), 23 * 60 + 59)
        self.init(hour: m / 60, minute: m % 60)
    }

    var text: String { String(format: "%02d:%02d", hour, minute) }
}

enum ReminderTiming {
    /// Hora del aviso de un día: exacta si «desde» y «hasta» coinciden (o el rango no es válido);
    /// si no, una hora dentro del rango que cambia de un día a otro pero siempre es la misma para ese día.
    static func time(forDayKey dayKey: String, from: ClockTime, to: ClockTime) -> ClockTime {
        let span = to.minutesOfDay - from.minutesOfDay
        guard span > 0 else { return from }
        let offset = stableHash(dayKey) % (span + 1)
        return ClockTime(minutesOfDay: from.minutesOfDay + offset)
    }

    /// Hash estable (no cambia entre ejecuciones, a diferencia de `hashValue`).
    static func stableHash(_ text: String) -> Int {
        var h: UInt64 = 1469598103934665603
        for byte in text.utf8 {
            h ^= UInt64(byte)
            h = h &* 1099511628211
        }
        return Int(h % 1_000_003)
    }

    /// Aviso de pasos: solo si se conocen los pasos y van por debajo de la mitad del objetivo.
    static func stepsBelowHalf(steps: Int?, goal: Int) -> Bool {
        guard let steps, goal > 0 else { return false }
        return Double(steps) < Double(goal) / 2
    }
}

// MARK: - Peso: medias mensuales y tendencia

extension WeightStats {
    struct MonthAverage: Equatable, Identifiable {
        var id: String { String(format: "%04d-%02d", year, month) }
        let year: Int
        let month: Int
        let averageKg: Double
        let count: Int
        let start: Date
        let end: Date
    }

    /// Media de los pesajes de cada mes, del más antiguo al más reciente.
    static func monthlyAverages(_ points: [Point], calendar: Calendar = DateUtils.calendar) -> [MonthAverage] {
        var groups: [String: [Point]] = [:]
        for p in points {
            let c = calendar.dateComponents([.year, .month], from: p.date)
            groups[String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0), default: []].append(p)
        }
        return groups.keys.sorted().compactMap { key in
            guard let list = groups[key], let first = list.first else { return nil }
            let c = calendar.dateComponents([.year, .month], from: first.date)
            guard let start = calendar.date(from: DateComponents(year: c.year, month: c.month, day: 1)),
                  let next = calendar.date(byAdding: .month, value: 1, to: start),
                  let end = calendar.date(byAdding: .second, value: -1, to: next) else { return nil }
            let avg = list.map(\.kg).reduce(0, +) / Double(list.count)
            return MonthAverage(year: c.year ?? 0, month: c.month ?? 0, averageKg: avg, count: list.count, start: start, end: end)
        }
    }

    /// Media móvil de los pesajes de los últimos `days` días (incluido el propio), uno por pesaje.
    static func movingAverage(_ points: [Point], days: Int = 7, calendar: Calendar = DateUtils.calendar) -> [Point] {
        let sorted = points.sorted { $0.date < $1.date }
        return sorted.map { p in
            let from = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: p.date)) ?? p.date
            let window = sorted.filter { $0.date >= from && $0.date <= p.date }
            return Point(date: p.date, kg: window.map(\.kg).reduce(0, +) / Double(window.count))
        }
    }

    /// Cambio de peso en una semana: último pesaje de la semana menos el último anterior a ella;
    /// si no hay ninguno anterior, último menos primero de la semana. nil si no hay datos suficientes.
    static func weekChange(_ points: [Point], weekStart: Date, weekEnd: Date) -> Double? {
        let sorted = points.sorted { $0.date < $1.date }
        let inWeek = sorted.filter { $0.date >= weekStart && $0.date < weekEnd }
        guard let last = inWeek.last else { return nil }
        if let before = sorted.last(where: { $0.date < weekStart }) { return last.kg - before.kg }
        guard inWeek.count > 1, let first = inWeek.first else { return nil }
        return last.kg - first.kg
    }
}

// MARK: - Resumen semanal

struct RunSample: Equatable {
    let date: Date
    let meters: Double
    let seconds: Int
}

struct WeeklySummary: Equatable {
    var averageSteps: Int?
    var daysWithSteps: Int
    var kilometers: Double
    var runs: Int
    var weightChange: Double?
    var daysDone: Int
    var daysExcused: Int
    var daysMissed: Int
    var daysCounted: Int

    /// `stepsByDay`: pasos de cada día de la semana con datos. `outcomes`: los 7 días de la semana.
    static func make(stepsByDay: [Int], runs: [RunSample], weights: [WeightStats.Point],
                     outcomes: [DayOutcome], weekStart: Date, weekEnd: Date) -> WeeklySummary {
        let steps = stepsByDay.filter { $0 > 0 }
        let weekRuns = runs.filter { $0.date >= weekStart && $0.date < weekEnd }
        return WeeklySummary(
            averageSteps: steps.isEmpty ? nil : Int((Double(steps.reduce(0, +)) / Double(steps.count)).rounded()),
            daysWithSteps: steps.count,
            kilometers: weekRuns.map(\.meters).reduce(0, +) / 1000,
            runs: weekRuns.count,
            weightChange: WeightStats.weekChange(weights, weekStart: weekStart, weekEnd: weekEnd),
            daysDone: outcomes.filter(\.isDone).count,
            daysExcused: outcomes.filter(\.isExcused).count,
            daysMissed: outcomes.filter(\.isMissed).count,
            daysCounted: outcomes.filter { $0.isDone || $0.isExcused || $0.isMissed }.count
        )
    }
}

// MARK: - Medallas

enum MedalTier: Int, Comparable, Codable {
    case locked = 0, bronze, silver, gold

    static func < (a: MedalTier, b: MedalTier) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .locked: return "Bloqueada"
        case .bronze: return "Bronce"
        case .silver: return "Plata"
        case .gold: return "Oro"
        }
    }
}

struct Medal: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let tier: MedalTier
    /// Mejor marca actual («12,4 km»), o nil si no hay datos.
    let value: String?
    /// Cuándo se consiguió la mejor marca.
    let date: Date?
    /// Qué falta para el siguiente nivel («Oro: 21,1 km»), nil si ya es oro.
    let nextGoal: String?
    /// Progreso hacia el siguiente nivel (0…1).
    let progress: Double
    let source: String
}

struct MedalInput {
    var runs: [RunSample] = []
    var dailySteps: [(date: Date, steps: Int)] = []
    var bestStreak: Int = 0
    var strengthSessions: Int = 0
    var weighIns: Int = 0
    var completePhotoMonths: Int = 0
}

enum Medals {
    /// Niveles: [bronce, plata, oro]. `higherIsBetter = false` para ritmos (menos es mejor).
    static func tier(_ value: Double, thresholds: [Double], higherIsBetter: Bool = true) -> MedalTier {
        var result = MedalTier.locked
        for (i, t) in thresholds.enumerated() {
            let reached = higherIsBetter ? value >= t : value <= t
            if reached { result = MedalTier(rawValue: i + 1) ?? .gold }
        }
        return result
    }

    static func progress(_ value: Double, thresholds: [Double], higherIsBetter: Bool = true) -> (next: Double?, fraction: Double) {
        let t = tier(value, thresholds: thresholds, higherIsBetter: higherIsBetter)
        guard t.rawValue < thresholds.count else { return (nil, 1) }
        let next = thresholds[t.rawValue]
        if higherIsBetter {
            return (next, next > 0 ? min(max(value / next, 0), 1) : 0)
        }
        // Ritmo: progreso desde 1,5 veces el objetivo hasta el objetivo.
        let start = next * 1.5
        return (next, min(max((start - value) / (start - next), 0), 1))
    }

    static let fiveK = 5000.0

    static func all(_ input: MedalInput) -> [Medal] {
        var medals: [Medal] = []
        let runSource = "Strava o carreras apuntadas a mano"

        // Carrera más larga
        let longest = input.runs.max { $0.meters < $1.meters }
        medals.append(make(id: "longest-run", title: "Carrera más larga", symbol: "figure.run",
                           value: longest.map { $0.meters / 1000 }, date: longest?.date,
                           thresholds: [5, 10, 21.1], format: { km($0) }, source: runSource))

        // Mejor ritmo en carreras de 5 km o más
        let paced = input.runs.filter { $0.meters >= fiveK && $0.seconds > 0 }
            .map { (run: $0, pace: Double($0.seconds) / ($0.meters / 1000)) }
        let fastest = paced.min { $0.pace < $1.pace }
        medals.append(make(id: "best-5k-pace", title: "Mejor ritmo en 5 km", symbol: "stopwatch.fill",
                           value: fastest?.pace, date: fastest?.run.date,
                           thresholds: [420, 360, 300], higherIsBetter: false,
                           format: { pace($0) + " · 5 km en " + RunMath.formatDuration(Int(($0 * 5).rounded())) },
                           goalFormat: { pace($0) },
                           source: "Ritmo medio de carreras de 5 km o más (\(runSource))"))

        // Día con más pasos
        let bestDay = input.dailySteps.max { $0.steps < $1.steps }
        medals.append(make(id: "most-steps", title: "Día con más pasos", symbol: "shoeprints.fill",
                           value: bestDay.map { Double($0.steps) }, date: bestDay?.date,
                           thresholds: [10000, 15000, 20000], format: { NumberFormat.integer($0) + " pasos" },
                           source: "Sensor de pasos del iPhone"))

        // Racha más larga
        medals.append(make(id: "best-streak", title: "Racha más larga", symbol: "flame.fill",
                           value: input.bestStreak > 0 ? Double(input.bestStreak) : nil, date: nil,
                           thresholds: [7, 30, 100], format: { days($0) }, source: "Calendario"))

        // Kilómetros totales
        let totalKm = input.runs.map(\.meters).reduce(0, +) / 1000
        medals.append(make(id: "total-km", title: "Kilómetros corridos", symbol: "map.fill",
                           value: totalKm > 0 ? totalKm : nil, date: nil,
                           thresholds: [50, 200, 500], format: { km($0) }, source: runSource))

        // Sesiones de fuerza
        medals.append(make(id: "strength", title: "Sesiones de fuerza", symbol: "dumbbell.fill",
                           value: input.strengthSessions > 0 ? Double(input.strengthSessions) : nil, date: nil,
                           thresholds: [10, 50, 150], format: { NumberFormat.integer($0) + " sesiones" }, source: "Entreno"))

        // Pesajes
        medals.append(make(id: "weigh-ins", title: "Constancia en la báscula", symbol: "scalemass.fill",
                           value: input.weighIns > 0 ? Double(input.weighIns) : nil, date: nil,
                           thresholds: [10, 30, 100], format: { NumberFormat.integer($0) + " pesajes" }, source: "Progreso › Peso"))

        // Meses con las tres fotos
        medals.append(make(id: "photo-months", title: "Meses con fotos completas", symbol: "camera.fill",
                           value: input.completePhotoMonths > 0 ? Double(input.completePhotoMonths) : nil, date: nil,
                           thresholds: [1, 3, 6], format: { NumberFormat.integer($0) + ($0 == 1 ? " mes" : " meses") },
                           source: "Progreso › Fotos (frente, lateral y espalda)"))
        return medals
    }

    private static func make(id: String, title: String, symbol: String, value: Double?, date: Date?,
                             thresholds: [Double], higherIsBetter: Bool = true,
                             format: @escaping (Double) -> String, goalFormat: ((Double) -> String)? = nil,
                             source: String) -> Medal {
        let goalText = goalFormat ?? format
        guard let value else {
            return Medal(id: id, title: title, symbol: symbol, tier: .locked, value: nil, date: nil,
                         nextGoal: "Bronce: " + goalText(thresholds[0]), progress: 0, source: source)
        }
        let level = Medals.tier(value, thresholds: thresholds, higherIsBetter: higherIsBetter)
        let p = progress(value, thresholds: thresholds, higherIsBetter: higherIsBetter)
        let nextLabel = MedalTier(rawValue: level.rawValue + 1)?.label ?? ""
        return Medal(id: id, title: title, symbol: symbol, tier: level, value: format(value), date: date,
                     nextGoal: p.next.map { "\(nextLabel): " + goalText($0) }, progress: p.fraction, source: source)
    }

    static func km(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "es_ES"))) + " km"
    }

    static func pace(_ secondsPerKm: Double) -> String { RunMath.formatPace(secondsPerKm) }

    static func days(_ value: Double) -> String {
        let n = Int(value.rounded())
        return "\(n) " + (n == 1 ? "día" : "días")
    }
}
