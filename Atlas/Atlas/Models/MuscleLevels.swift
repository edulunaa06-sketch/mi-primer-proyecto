import Foundation

/// Rango de cada músculo a partir de lo que has registrado en la app.
///
/// IMPORTANTE, y la pantalla lo dice: esto NO mide tu músculo ni lo compara con nadie.
/// Mide TU trabajo registrado aquí: cuántas series le has dedicado, durante cuántas semanas
/// y cuánto han subido tus pesos en los ejercicios de ese músculo. Si no lo apuntas, no cuenta.
///
/// Cómo se calcula, para que no sea una caja negra:
///  1. Cada músculo tiene una «semana productiva» propia (las series semanales que la referencia
///     de volumen considera un buen punto de partida). El pecho necesita 10 series; los oblicuos, 4.
///  2. Las series directas registradas se dividen entre esa cifra: salen «semanas productivas».
///  3. Se limitan a 1,5 por cada semana natural en la que has entrenado ese músculo, para que
///     meter 60 series en un día no valga por un mes de trabajo.
///  4. Si tus pesos suben en los ejercicios de ese músculo, los puntos suben hasta un 25 % más.
enum MuscleLevel {

    // MARK: Rangos

    enum Rank: Int, CaseIterable, Comparable, Identifiable {
        case novato, iniciado, intermedio, avanzado, veterano, elite

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .novato: return "Novato"
            case .iniciado: return "Iniciado"
            case .intermedio: return "Intermedio"
            case .avanzado: return "Avanzado"
            case .veterano: return "Veterano"
            case .elite: return "Élite"
            }
        }

        /// Puntos (semanas productivas) a partir de los cuales se tiene este rango.
        var threshold: Double {
            switch self {
            case .novato: return 0
            case .iniciado: return 4
            case .intermedio: return 12
            case .avanzado: return 26
            case .veterano: return 52
            case .elite: return 104
            }
        }

        var next: Rank? { Rank(rawValue: rawValue + 1) }

        static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }

        static func rank(forPoints points: Double) -> Rank {
            allCases.last { points >= $0.threshold } ?? .novato
        }
    }

    // MARK: Entrada y resultado

    /// Lo que se ha registrado de un músculo. `strengthGain` es cuánto han subido los pesos
    /// (1 = igual que al principio, 1,2 = un 20 % más); nil si no hay con qué comparar.
    struct Input: Equatable {
        let group: MuscleGroup
        let directSets: Double
        let tonnageKg: Double
        /// Semanas naturales distintas en las que se ha trabajado el músculo.
        let weeksTrained: Int
        let strengthGain: Double?

        init(group: MuscleGroup, directSets: Double, tonnageKg: Double = 0,
             weeksTrained: Int = 0, strengthGain: Double? = nil) {
            self.group = group
            self.directSets = directSets
            self.tonnageKg = tonnageKg
            self.weeksTrained = weeksTrained
            self.strengthGain = strengthGain
        }
    }

    struct Status: Equatable, Identifiable {
        let group: MuscleGroup
        let rank: Rank
        let points: Double
        /// 0…1 dentro del rango actual. En Élite vale 1.
        let progress: Double
        let nextRank: Rank?
        /// Puntos que faltan para el siguiente rango (nil en Élite).
        let pointsToNext: Double?
        let directSets: Double
        let tonnageKg: Double
        let weeksTrained: Int
        /// Lo que ha sumado la subida de pesos (0…0,25).
        let strengthBonus: Double

        var id: String { group.rawValue }

        /// Series semanales que cuentan como una semana productiva de este músculo.
        var weeklyUnit: Double { MuscleLevel.weeklyUnit(for: group) }

        /// Explicación en una línea de qué hace falta para subir.
        var advice: String {
            guard let nextRank, let pointsToNext else {
                return "Rango máximo con lo registrado. Sigue apuntando para mantenerlo."
            }
            let sets = pointsToNext * weeklyUnit
            return "Para \(nextRank.label.lowercased()): \(NumberFormat.oneDecimal(sets)) series directas más "
                + "(unas \(NumberFormat.oneDecimal(pointsToNext)) semanas a \(NumberFormat.integer(weeklyUnit)) series)."
        }
    }

    // MARK: Cálculo

    /// Series semanales que cuentan como «una semana productiva» de ese músculo.
    /// Sale de la referencia de volumen, con un mínimo de 4 para que los músculos pequeños
    /// no suban de rango demasiado rápido.
    static func weeklyUnit(for group: MuscleGroup) -> Double {
        max(VolumeReference.reference(for: group).typical.lowerBound, 4)
    }

    /// Cuánto suman los pesos que han subido: hasta un 25 % más de puntos cuando el 1RM estimado
    /// ha subido la mitad o más desde la primera vez.
    static func strengthBonus(gain: Double?) -> Double {
        guard let gain, gain.isFinite, gain > 1 else { return 0 }
        return min((gain - 1) / 0.5, 1) * 0.25
    }

    static func status(for input: Input) -> Status {
        let unit = weeklyUnit(for: input.group)
        let rawWeeks = input.directSets / unit
        // Tope por semanas naturales: el trabajo repartido vale más que el amontonado.
        let capped = input.weeksTrained > 0 ? min(rawWeeks, Double(input.weeksTrained) * 1.5) : min(rawWeeks, 1.5)
        let bonus = strengthBonus(gain: input.strengthGain)
        let points = capped * (1 + bonus)
        let rank = Rank.rank(forPoints: points)
        let next = rank.next
        let progress: Double
        if let next {
            let span = next.threshold - rank.threshold
            progress = span > 0 ? min(max((points - rank.threshold) / span, 0), 1) : 1
        } else {
            progress = 1
        }
        return Status(group: input.group, rank: rank, points: points, progress: progress,
                      nextRank: next, pointsToNext: next.map { max($0.threshold - points, 0) },
                      directSets: input.directSets, tonnageKg: input.tonnageKg,
                      weeksTrained: input.weeksTrained, strengthBonus: bonus)
    }

    /// Rango de los 18 músculos a partir de todo el trabajo registrado.
    /// Los ejercicios que no están ni en la biblioteca ni entre los tuyos no se reparten
    /// por músculo: no se adivina a qué grupo van.
    static func statuses(work: [VolumeAnalytics.ExerciseWork]) -> [Status] {
        var sets: [MuscleGroup: Double] = [:]
        var tonnage: [MuscleGroup: Double] = [:]
        var weeks: [MuscleGroup: Set<String>] = [:]
        /// Por músculo y ejercicio: el primer 1RM estimado y el mejor, para ver si suben los pesos.
        var oneRM: [MuscleGroup: [String: (first: Double, firstDate: Date, best: Double)]] = [:]

        for item in work {
            guard item.workSets > 0, let info = item.info else { continue }
            let group = info.primary
            sets[group, default: 0] += Double(item.workSets)
            tonnage[group, default: 0] += item.volumeKg
            weeks[group, default: []].insert(DateUtils.dayKey(DateUtils.startOfWeek(item.date)))

            if let e1rm = item.estimatedOneRepMax, e1rm > 0 {
                var byExercise = oneRM[group] ?? [:]
                if let existing = byExercise[item.exerciseID] {
                    byExercise[item.exerciseID] = (
                        first: item.date < existing.firstDate ? e1rm : existing.first,
                        firstDate: min(item.date, existing.firstDate),
                        best: max(existing.best, e1rm)
                    )
                } else {
                    byExercise[item.exerciseID] = (first: e1rm, firstDate: item.date, best: e1rm)
                }
                oneRM[group] = byExercise
            }
        }

        return MuscleGroup.allCases.map { group in
            status(for: Input(group: group,
                              directSets: sets[group] ?? 0,
                              tonnageKg: tonnage[group] ?? 0,
                              weeksTrained: weeks[group]?.count ?? 0,
                              strengthGain: gain(oneRM[group])))
        }
    }

    /// Cuánto han subido los pesos de un músculo: la media de lo que ha subido cada ejercicio
    /// comparándolo CONSIGO MISMO (comparar una extensión de cuádriceps con una sentadilla no
    /// diría nada). nil si ningún ejercicio tiene dos sesiones con peso y repeticiones.
    static func gain(_ byExercise: [String: (first: Double, firstDate: Date, best: Double)]?) -> Double? {
        guard let byExercise else { return nil }
        let gains = byExercise.values.filter { $0.first > 0 && $0.best > $0.first }.map { $0.best / $0.first }
        let compared = byExercise.values.filter { $0.first > 0 }
        guard !compared.isEmpty else { return nil }
        guard !gains.isEmpty else { return 1 }
        // Los ejercicios que no han subido cuentan como 1 (no han mejorado), no se ignoran.
        let total = gains.reduce(0, +) + Double(compared.count - gains.count)
        return total / Double(compared.count)
    }

    /// Resumen del cuerpo entero: cuántos músculos hay en cada rango.
    static func distribution(_ statuses: [Status]) -> [(rank: Rank, count: Int)] {
        Rank.allCases.map { rank in
            (rank: rank, count: statuses.filter { $0.rank == rank }.count)
        }
    }

    /// Los músculos con menos trabajo registrado (los que peor llevas), de menor a mayor.
    static func weakest(_ statuses: [Status], limit: Int = 3) -> [Status] {
        Array(statuses.sorted { ($0.points, $0.group.sortIndex) < ($1.points, $1.group.sortIndex) }.prefix(limit))
    }
}
