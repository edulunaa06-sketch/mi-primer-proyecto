import Foundation

// Lógica pura de ATLAS (sin SwiftData ni interfaz), probada en AtlasTests.

// MARK: - Estado de las calorías del día

enum CalorieStatus: Equatable {
    case plenty(left: Double)
    case approaching(left: Double)
    case onTarget(delta: Double)
    case over(excess: Double)

    static let defaultMargin = 100.0

    static func evaluate(consumed: Double, target: Double, margin: Double = defaultMargin) -> CalorieStatus {
        guard target > 0 else { return .plenty(left: 0) }
        let delta = consumed - target
        if abs(delta) <= max(margin, 0) { return .onTarget(delta: delta) }
        if delta > 0 { return .over(excess: delta) }
        return consumed >= target * 0.8 ? .approaching(left: -delta) : .plenty(left: -delta)
    }

    var label: String {
        switch self {
        case .plenty: return "Vas sobrado"
        case .approaching: return "Casi en tu objetivo"
        case .onTarget: return "Objetivo clavado"
        case .over: return "Por encima"
        }
    }
}

// MARK: - Peso de tendencia y gasto real

enum WeightTrend {
    struct Point: Equatable {
        let date: Date
        let kg: Double
    }

    /// Media móvil exponencial (suavizado 0,1 por día, como «The Hacker's Diet»): quita el ruido del agua
    /// y la comida del día a día. Devuelve un punto de tendencia por pesaje.
    static func smoothed(_ points: [Point], alpha: Double = 0.1) -> [Point] {
        let sorted = points.sorted { $0.date < $1.date }
        guard var trend = sorted.first?.kg else { return [] }
        var result: [Point] = []
        var lastDate = sorted.first!.date
        for p in sorted {
            // Si hay días sin pesarse, la tendencia se mueve como si se hubiera pesado esos días.
            let days = max(1, Int((p.date.timeIntervalSince(lastDate) / 86400).rounded()))
            let a = 1 - pow(1 - alpha, Double(days))
            trend += a * (p.kg - trend)
            result.append(Point(date: p.date, kg: trend))
            lastDate = p.date
        }
        return result
    }

    /// Cambio semanal de la tendencia (kg/semana) en los últimos `days` días. nil sin datos suficientes.
    static func weeklyRate(_ points: [Point], days: Int = 21, now: Date = Date()) -> Double? {
        let trend = smoothed(points)
        guard let last = trend.last else { return nil }
        let from = now.addingTimeInterval(-Double(days) * 86400)
        guard let first = trend.first(where: { $0.date >= from }), last.date.timeIntervalSince(first.date) >= 7 * 86400 else { return nil }
        let weeks = last.date.timeIntervalSince(first.date) / (7 * 86400)
        return (last.kg - first.kg) / weeks
    }
}

/// Gasto energético REAL estimado con tus datos (como hacen las apps de nutrición más avanzadas):
/// lo que comes de media menos lo que explica el cambio de tu peso de tendencia (≈ 7.700 kcal por kg).
enum AdaptiveExpenditure {
    static let kcalPerKg = 7700.0
    static let minimumDays = 14

    struct Result: Equatable {
        let kcal: Double
        let daysUsed: Int
        let averageIntake: Double
        let trendChangeKg: Double
    }

    /// `intake`: kcal registradas por día (solo días con comidas apuntadas). `weights`: pesajes.
    static func estimate(intake: [(day: Date, kcal: Double)], weights: [WeightTrend.Point], window: Int = 28, now: Date = Date()) -> Result? {
        let from = now.addingTimeInterval(-Double(window) * 86400)
        let days = intake.filter { $0.day >= from && $0.kcal > 300 }
        guard days.count >= minimumDays else { return nil }
        let trend = WeightTrend.smoothed(weights).filter { $0.date >= from }
        guard let first = trend.first, let last = trend.last else { return nil }
        let span = last.date.timeIntervalSince(first.date) / 86400
        guard span >= 10 else { return nil }
        let avg = days.map(\.kcal).reduce(0, +) / Double(days.count)
        let change = last.kg - first.kg
        let tdee = avg - change * kcalPerKg / span
        return Result(kcal: (tdee / 10).rounded() * 10, daysUsed: days.count, averageIntake: avg, trendChangeKg: change)
    }
}

// MARK: - Constancia: racha de semanas

/// Racha en SEMANAS (como los mejores planes de entreno): una semana cuenta si haces al menos el 75 % de
/// las sesiones que tienes planificadas. La semana en curso suma si ya lo has conseguido y no rompe si aún no.
enum WeekStreak {
    static func goal(planned: Int) -> Int { max(1, Int((Double(planned) * 0.75).rounded(.up))) }

    static func compute(workoutDays: [Date], planned: Int, now: Date = Date(), calendar: Calendar = DateUtils.calendar) -> (current: Int, best: Int, thisWeek: Int) {
        let goal = goal(planned: planned)
        var perWeek: [Date: Int] = [:]
        for d in workoutDays { perWeek[DateUtils.startOfWeek(d), default: 0] += 1 }
        let thisWeekStart = DateUtils.startOfWeek(now)
        let thisWeek = perWeek[thisWeekStart] ?? 0
        guard let earliest = perWeek.keys.min() else { return (0, 0, 0) }
        var best = 0, run = 0
        var week = earliest
        while week < thisWeekStart {
            if (perWeek[week] ?? 0) >= goal { run += 1; best = max(best, run) } else { run = 0 }
            week = calendar.date(byAdding: .day, value: 7, to: week) ?? thisWeekStart
        }
        if thisWeek >= goal { run += 1; best = max(best, run) }
        return (run, best, thisWeek)
    }
}

// MARK: - Entreno

enum WorkoutMath {
    /// Volumen total (kg × reps) de las series hechas.
    static func volume(_ sets: [SetSample]) -> Double { sets.reduce(0) { $0 + $1.kg * Double($1.reps) } }

    /// Duración legible: «1 h 05 min» o «48 min».
    static func duration(_ seconds: Int) -> String {
        let m = max(seconds, 0) / 60
        return m >= 60 ? String(format: "%d h %02d min", m / 60, m % 60) : "\(m) min"
    }

    /// Estimación de duración de una sesión: (series × (45 s de trabajo + descanso recomendado)).
    static func estimatedMinutes(_ exercises: [(sets: Int, repRange: String)]) -> Int {
        let seconds = exercises.reduce(0) { $0 + $1.sets * (45 + RestTimerLogic.defaultSeconds(repRange: $1.repRange)) }
        return max(5, Int((Double(seconds) / 60 / 5).rounded()) * 5)
    }
}

// MARK: - Agua y saludo

enum Hydration {
    /// 35 ml por kg, redondeado a 250 ml, entre 2 y 4 litros.
    static func goal(weightKg: Double?) -> Int {
        guard let w = weightKg, w > 0 else { return 2500 }
        let ml = (w * 35 / 250).rounded() * 250
        return Int(min(max(ml, 2000), 4000))
    }
}

enum Greeting {
    static func text(hour: Int) -> String {
        switch hour {
        case 5..<13: return "Buenos días"
        case 13..<21: return "Buenas tardes"
        default: return "Buenas noches"
        }
    }
}

// MARK: - Biblioteca de ejercicios

struct LibraryExercise: Identifiable, Hashable {
    let id: String
    let name: String
    let defaultSets: Int
    let defaultReps: String
    var muscle: Muscle? { Muscle.worked(by: name).first }
}

enum ExerciseLibrary {
    /// Ejercicios habituales para añadir a una rutina o a un entreno libre (además de los de tu rutina).
    static let all: [LibraryExercise] = [
        ("bench-press", "Press de banca con barra", 4, "6–10"), ("incline-db-press", "Press inclinado con mancuernas", 3, "8–12"),
        ("machine-chest-press", "Press de pecho en máquina", 3, "8–12"), ("cable-fly", "Aperturas en polea", 3, "12–15"),
        ("dips", "Fondos en paralelas", 3, "8–12"), ("pushups", "Flexiones", 3, "10–20"),
        ("pullups", "Dominadas", 4, "6–10"), ("lat-pulldown", "Jalón al pecho", 3, "8–12"),
        ("barbell-row", "Remo con barra", 4, "6–10"), ("seated-row", "Remo sentado en polea", 3, "8–12"),
        ("chest-supported-row", "Remo con pecho apoyado", 3, "8–12"), ("pullover", "Pullover en polea", 3, "12–15"),
        ("ohp", "Press militar con barra", 4, "6–10"), ("db-shoulder-press", "Press de hombros con mancuernas", 3, "8–12"),
        ("lateral-raise", "Elevaciones laterales con mancuernas", 3, "12–20"), ("cable-lateral", "Elevación lateral en polea", 3, "12–20"),
        ("rear-delt", "Pájaros en máquina / reverse pec deck", 3, "12–20"), ("face-pull", "Face pull", 3, "12–20"),
        ("barbell-curl", "Curl con barra", 3, "8–12"), ("db-curl", "Curl con mancuernas", 3, "10–15"),
        ("hammer-curl", "Curl martillo", 3, "10–15"), ("preacher-curl", "Curl predicador", 3, "8–12"),
        ("pushdown", "Extensión de tríceps con cuerda", 3, "10–15"), ("overhead-ext", "Extensión de tríceps por encima de la cabeza", 3, "10–15"),
        ("skullcrusher", "Press francés", 3, "8–12"),
        ("squat", "Sentadilla con barra", 4, "5–8"), ("hack-squat", "Hack squat", 3, "8–12"),
        ("leg-press", "Prensa de piernas", 3, "10–15"), ("bulgarian", "Sentadilla búlgara", 3, "8–12"),
        ("leg-ext", "Extensión de cuádriceps", 3, "12–15"), ("rdl", "Peso muerto rumano", 3, "6–10"),
        ("deadlift", "Peso muerto", 3, "3–5"), ("hip-thrust", "Hip thrust", 3, "8–12"),
        ("leg-curl", "Curl femoral tumbado", 3, "10–15"), ("calf-raise", "Elevación de gemelos de pie", 4, "10–15"),
        ("cable-crunch", "Crunch en polea", 3, "12–15"), ("plank", "Plancha (segundos como reps)", 3, "30–60"),
        ("ab-wheel", "Rueda abdominal", 3, "8–12"),
    ].map { LibraryExercise(id: "lib-" + $0.0, name: $0.1, defaultSets: $0.2, defaultReps: $0.3) }

    static func search(_ query: String, extra: [LibraryExercise] = []) -> [LibraryExercise] {
        var seen = Set<String>()
        let pool = (extra + all).filter { seen.insert($0.name.lowercased()).inserted }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return pool }
        return pool.filter { FoodSearch.matches(name: $0.name, query: q) }
    }
}
