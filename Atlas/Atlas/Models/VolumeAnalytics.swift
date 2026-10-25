import Foundation

/// Cuánto trabajo ha recibido cada músculo. Lógica pura: recibe el trabajo ya hecho
/// y devuelve números, sin tocar la base de datos.
///
/// Dos formas de contar, y la app muestra las dos porque significan cosas distintas:
/// · Series directas: el músculo era el principal del ejercicio.
/// · Series totales: suma además media serie por cada vez que el músculo era secundario.
///   Es la convención habitual para contar el trabajo indirecto; es una estimación, no una medida.
enum VolumeAnalytics {
    /// Cuánto cuenta una serie para un músculo que solo ayudaba.
    static let indirectWeight = 0.5

    /// Trabajo realizado de un ejercicio en una sesión.
    struct ExerciseWork: Equatable {
        let exerciseID: String
        let name: String
        let date: Date
        /// Series de trabajo realmente apuntadas (sin calentamientos).
        let workSets: Int
        /// Kilos movidos (peso × repeticiones) en esas series.
        let volumeKg: Double
        let totalReps: Int

        init(exerciseID: String, name: String, date: Date, workSets: Int, volumeKg: Double, totalReps: Int = 0) {
            self.exerciseID = exerciseID
            self.name = name
            self.date = date
            self.workSets = workSets
            self.volumeKg = volumeKg
            self.totalReps = totalReps
        }

        init(summary: ExerciseSessionSummary, name: String) {
            self.init(exerciseID: summary.exerciseID, name: name, date: summary.date,
                      workSets: summary.workSets, volumeKg: summary.volumeKg, totalReps: summary.totalReps)
        }

        /// Ficha del ejercicio, si está en la biblioteca.
        var info: ExerciseInfo? { ExerciseCatalog.info(id: exerciseID, name: name) }
    }

    /// Resultado por músculo.
    struct MuscleVolume: Equatable, Identifiable {
        let group: MuscleGroup
        let directSets: Double
        /// Directas + media serie por cada aparición como secundario.
        let totalSets: Double
        let tonnageKg: Double
        /// Días distintos en los que se ha trabajado (frecuencia).
        let frequency: Int

        var id: String { group.rawValue }

        var reference: VolumeReference { VolumeReference.reference(for: group) }
        var verdict: VolumeReference.Verdict { reference.verdict(sets: directSets) }
    }

    /// Series y tonelaje por músculo a partir del trabajo de un periodo.
    /// Los ejercicios que no están en la biblioteca no se pueden repartir por músculo:
    /// se devuelven aparte en `unclassified` en vez de inventarse a qué grupo van.
    static func byMuscle(_ work: [ExerciseWork]) -> (muscles: [MuscleVolume], unclassified: [ExerciseWork]) {
        var direct: [MuscleGroup: Double] = [:]
        var total: [MuscleGroup: Double] = [:]
        var tonnage: [MuscleGroup: Double] = [:]
        var days: [MuscleGroup: Set<String>] = [:]
        var unclassified: [ExerciseWork] = []

        for item in work {
            guard item.workSets > 0 else { continue }
            guard let info = item.info else {
                unclassified.append(item)
                continue
            }
            let sets = Double(item.workSets)
            let dayKey = DateUtils.dayKey(item.date)

            direct[info.primary, default: 0] += sets
            total[info.primary, default: 0] += sets
            tonnage[info.primary, default: 0] += item.volumeKg
            days[info.primary, default: []].insert(dayKey)

            for muscle in info.secondary {
                total[muscle, default: 0] += sets * indirectWeight
                days[muscle, default: []].insert(dayKey)
            }
        }

        let groups = Set(direct.keys).union(total.keys)
        let muscles = groups.map { group in
            MuscleVolume(group: group,
                         directSets: direct[group] ?? 0,
                         totalSets: total[group] ?? 0,
                         tonnageKg: tonnage[group] ?? 0,
                         frequency: days[group]?.count ?? 0)
        }
        .sorted { $0.group < $1.group }
        return (muscles, unclassified)
    }

    /// Tonelaje total del periodo (suma de peso × repeticiones de todas las series de trabajo).
    static func totalTonnage(_ work: [ExerciseWork]) -> Double {
        work.reduce(0) { $0 + $1.volumeKg }
    }

    static func totalWorkSets(_ work: [ExerciseWork]) -> Int {
        work.reduce(0) { $0 + $1.workSets }
    }

    // MARK: Programado frente a realizado

    /// Lo que la rutina pedía frente a lo que se ha hecho.
    struct Adherence: Equatable {
        let programmedSets: Int
        let performedSets: Int

        /// nil si no había nada programado (no se puede calcular un porcentaje sobre cero).
        var fraction: Double? {
            guard programmedSets > 0 else { return nil }
            return Double(performedSets) / Double(programmedSets)
        }

        var difference: Int { performedSets - programmedSets }

        var label: String {
            guard let fraction else { return "Sin rutina programada" }
            if fraction >= 0.95 && fraction <= 1.15 { return "Según lo programado" }
            return fraction < 0.95 ? "Por debajo de lo programado" : "Por encima de lo programado"
        }
    }

    static func adherence(programmedSets: Int, work: [ExerciseWork]) -> Adherence {
        Adherence(programmedSets: programmedSets, performedSets: totalWorkSets(work))
    }

    /// Series programadas por músculo según la rutina (sin contar lo realizado).
    static func programmedByMuscle(_ exercises: [(id: String, name: String, sets: Int)]) -> [MuscleGroup: Double] {
        var out: [MuscleGroup: Double] = [:]
        for ex in exercises {
            guard let info = ExerciseCatalog.info(id: ex.id, name: ex.name) else { continue }
            out[info.primary, default: 0] += Double(ex.sets)
        }
        return out
    }

    // MARK: Avisos

    /// Avisos de volumen de una semana. Son avisos, no diagnósticos: se limitan a extremos claros.
    struct Warning: Equatable, Identifiable {
        enum Kind: String {
            case noWork, belowReference, aboveReference, bigJump
        }
        let kind: Kind
        let group: MuscleGroup
        let message: String
        var id: String { "\(kind.rawValue)-\(group.rawValue)" }
    }

    /// Compara una semana con la referencia y con la semana anterior.
    /// `previous` puede ir vacío (la primera semana no se compara con nada).
    static func warnings(week: [MuscleVolume], previous: [MuscleVolume] = []) -> [Warning] {
        var out: [Warning] = []
        let previousByGroup = Dictionary(previous.map { ($0.group, $0) }, uniquingKeysWith: { a, _ in a })

        for volume in week {
            let reference = volume.reference
            switch volume.verdict {
            case .below:
                out.append(Warning(kind: .belowReference, group: volume.group,
                                   message: "\(volume.group.label): \(NumberFormat.oneDecimal(volume.directSets)) series directas, "
                                   + "por debajo de la referencia habitual (\(NumberFormat.integer(reference.low))+)."))
            case .above:
                out.append(Warning(kind: .aboveReference, group: volume.group,
                                   message: "\(volume.group.label): \(NumberFormat.oneDecimal(volume.directSets)) series directas, "
                                   + "por encima de la referencia (\(NumberFormat.integer(reference.high))). Vigila la recuperación."))
            case .none, .inRange:
                break
            }

            // Subida brusca: más del 50 % respecto a la semana anterior y al menos 4 series más.
            if let old = previousByGroup[volume.group], old.directSets >= 2 {
                let jump = volume.directSets - old.directSets
                if jump >= 4, volume.directSets > old.directSets * 1.5 {
                    out.append(Warning(kind: .bigJump, group: volume.group,
                                       message: "\(volume.group.label): has subido de \(NumberFormat.oneDecimal(old.directSets)) "
                                       + "a \(NumberFormat.oneDecimal(volume.directSets)) series en una semana. "
                                       + "Subir poco a poco se recupera mejor."))
                }
            }
        }
        return out
    }
}
