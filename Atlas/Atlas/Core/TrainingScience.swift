import Foundation

/// Ciencia del entrenamiento de ATLAS (lógica pura, probada en AtlasTests/TrainingScienceTests).

/// Una serie con peso y repeticiones.
struct SetSample: Equatable {
    let kg: Double
    let reps: Int
}

// MARK: - Coach de sobrecarga progresiva (doble progresión)

/// Qué hacer hoy en un ejercicio según la última vez:
/// · Si todas las series llegaron al tope del rango → sube el peso.
/// · Si alguna se quedó por debajo del mínimo → mantén el peso y consolida.
/// · Si no → mismo peso, intenta sumar una repetición.
enum OverloadCoach {
    struct Suggestion: Equatable {
        enum Kind: Equatable { case increase, repeatWeight, consolidate }
        let kind: Kind
        let kg: Double
        let repsMin: Int
        let repsMax: Int
        let reason: String
    }

    /// Incremento razonable: 2,5 kg con barra o máquina; 1 kg con cargas pequeñas (mancuernas, poleas ligeras).
    static func increment(for kg: Double) -> Double { kg >= 20 ? 2.5 : 1 }

    static func suggest(repRange: String, last: [SetSample]) -> Suggestion? {
        guard let range = ExerciseDefinition.parseRange(repRange) else { return nil }
        let work = last.filter { $0.kg > 0 && $0.reps > 0 }
        guard let top = work.map(\.kg).max() else { return nil }
        let atTop = work.filter { $0.kg == top }
        if atTop.count == work.count, work.allSatisfy({ $0.reps >= range.max }) {
            let next = round2(top + increment(for: top))
            return Suggestion(kind: .increase, kg: next, repsMin: range.min, repsMax: range.max,
                              reason: "Llegaste a \(range.max) reps en todas las series: toca subir.")
        }
        if atTop.contains(where: { $0.reps < range.min }) {
            return Suggestion(kind: .consolidate, kg: top, repsMin: range.min, repsMax: range.max,
                              reason: "Alguna serie se quedó por debajo de \(range.min) reps: consolida este peso.")
        }
        let best = atTop.map(\.reps).max() ?? range.min
        let goal = min(best + 1, range.max)
        return Suggestion(kind: .repeatWeight, kg: top, repsMin: goal, repsMax: range.max,
                          reason: "Mismo peso: busca \(goal) reps o más en cada serie.")
    }

    private static func round2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
}

// MARK: - Récords personales

enum PersonalRecords {
    /// 1RM estimado (Epley). Con 1 repetición es el propio peso. Más allá de 12 reps es poco fiable: se limita.
    static func e1rm(_ s: SetSample) -> Double {
        guard s.kg > 0, s.reps > 0 else { return 0 }
        let reps = min(s.reps, 12)
        return reps == 1 ? s.kg : s.kg * (1 + Double(reps) / 30)
    }

    /// Mejor 1RM estimado de una lista de series (0 si no hay).
    static func best(_ sets: [SetSample]) -> Double { sets.map(e1rm).max() ?? 0 }

    /// ¿Esta serie supera tu mejor marca anterior? Sin historial no hay «récord» (la primera vez no cuenta).
    static func isRecord(_ s: SetSample, previousBest: Double) -> Bool {
        previousBest > 0 && e1rm(s) > previousBest + 0.01
    }
}

// MARK: - Ritmo de la sesión

/// ATLAS no cronometra el descanso: cada uno descansa lo que le pide el cuerpo. Estos segundos se usan
/// solo para estimar cuánto dura una sesión en la pantalla de Entrenar.
enum SessionPacing {
    /// Descanso típico según las repeticiones: pesado → más descanso.
    static func restSeconds(repRange: String) -> Int {
        guard let r = ExerciseDefinition.parseRange(repRange) else { return 90 }
        switch r.max {
        case ...6: return 180
        case ...10: return 120
        case ...15: return 90
        default: return 60
        }
    }
}

// MARK: - Discos y calentamiento

enum PlateCalculator {
    static let standardPlates: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    struct Result: Equatable {
        /// Discos por lado, de mayor a menor.
        let perSide: [Double]
        /// Peso total que se consigue con esos discos.
        let total: Double
        /// true si el peso pedido no se puede hacer exacto con los discos disponibles.
        let isApproximate: Bool
    }

    static func load(target: Double, bar: Double = 20, plates: [Double] = standardPlates) -> Result {
        guard target > bar else { return Result(perSide: [], total: bar, isApproximate: target < bar) }
        var remaining = (target - bar) / 2
        var side: [Double] = []
        for p in plates.sorted(by: >) {
            while remaining + 0.0001 >= p {
                side.append(p)
                remaining -= p
            }
        }
        let total = bar + side.reduce(0, +) * 2
        return Result(perSide: side, total: total, isApproximate: abs(total - target) > 0.001)
    }
}

enum Warmup {
    /// Series de aproximación hasta el peso de trabajo: barra × 10, 50 % × 8, 70 % × 5, 85 % × 3,
    /// redondeadas a 2,5 kg y sin repetir ni pasarse del peso de trabajo.
    static func sets(working: Double, bar: Double = 20) -> [SetSample] {
        guard working > bar else { return [] }
        var result = [SetSample(kg: bar, reps: 10)]
        for (pct, reps) in [(0.5, 8), (0.7, 5), (0.85, 3)] {
            let kg = (working * pct / 2.5).rounded() * 2.5
            if kg > (result.last?.kg ?? 0), kg < working { result.append(SetSample(kg: kg, reps: reps)) }
        }
        return result
    }
}

// MARK: - Series por músculo

enum Muscle: String, CaseIterable {
    case chest = "Pecho", back = "Espalda", shoulders = "Hombros", biceps = "Bíceps", triceps = "Tríceps"
    case quads = "Cuádriceps", hamstrings = "Femoral y glúteo", calves = "Gemelos", core = "Abdomen", forearms = "Antebrazo"

    /// Músculos que trabaja un ejercicio, por su nombre (también sirve para ejercicios que añadas tú).
    static func worked(by name: String) -> [Muscle] {
        let n = name.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_ES"))
        func has(_ words: String...) -> Bool { words.contains { n.contains($0) } }
        if has("muneca", "inverso") { return [.forearms] }
        if has("gemelo", "calf") { return [.calves] }
        if has("crunch", "abdom", "plancha", "rueda") { return [.core] }
        if has("femoral", "rumano", "hip thrust", "gluteo", "peso muerto") { return [.hamstrings] }
        if has("sentadilla", "squat", "prensa", "cuadriceps", "zancada", "bulgara") { return [.quads, .hamstrings] }
        if has("triceps", "fondos", "frances") { return [.triceps] }
        if has("curl", "biceps") { return [.biceps] }
        if has("lateral", "hombro", "militar", "pajaros", "reverse pec deck", "face pull") { return [.shoulders] }
        if has("jalon", "remo", "dominada", "pullover") { return [.back, .biceps] }
        if has("press", "aperturas", "pecho", "banca", "fly", "flexion") { return [.chest, .triceps] }
        return []
    }
}

enum WeeklyVolume {
    /// Rango orientativo de series efectivas por músculo y semana para ganar músculo.
    static let target = 10...20

    /// Series hechas por músculo. El primer músculo de cada ejercicio cuenta la serie entera; los secundarios, media.
    static func sets(_ exercises: [(name: String, sets: Int)]) -> [Muscle: Double] {
        var result: [Muscle: Double] = [:]
        for e in exercises where e.sets > 0 {
            for (i, m) in Muscle.worked(by: e.name).enumerated() {
                result[m, default: 0] += i == 0 ? Double(e.sets) : Double(e.sets) / 2
            }
        }
        return result
    }
}

// MARK: - Carrera: predicción de tiempos

/// Predicción de tiempos con la fórmula de Riegel (T2 = T1 · (D2/D1)^1,06) a partir de tu mejor carrera reciente.
enum RacePredictor {
    static let distances: [(name: String, meters: Double)] = [("5 km", 5000), ("10 km", 10000), ("Media maratón", 21097.5), ("Maratón", 42195)]

    static func predict(fromMeters d1: Double, seconds t1: Int, toMeters d2: Double) -> Int? {
        guard d1 >= 1000, t1 > 0, d2 > 0 else { return nil }
        return Int((Double(t1) * pow(d2 / d1, 1.06)).rounded())
    }

    /// La carrera de referencia: la de mejor rendimiento equivalente (la que predice el 10 km más rápido),
    /// entre las de al menos 3 km. nil si no hay ninguna.
    static func reference(_ runs: [RunSample]) -> RunSample? {
        runs.filter { $0.meters >= 3000 && $0.seconds > 0 }
            .min { (predict(fromMeters: $0.meters, seconds: $0.seconds, toMeters: 10000) ?? .max)
                < (predict(fromMeters: $1.meters, seconds: $1.seconds, toMeters: 10000) ?? .max) }
    }
}
