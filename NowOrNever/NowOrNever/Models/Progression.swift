import Foundation

/// Resumen de una sesión de un ejercicio a partir de las series registradas (lógica pura).
struct ExerciseSessionSummary: Equatable {
    struct SetEntry: Equatable {
        let weightKg: Double?
        let reps: Int?
    }

    let date: Date
    /// Carga máxima usada en una serie con repeticiones registradas.
    let topWeightKg: Double?
    /// Repeticiones conseguidas con esa carga máxima.
    let repsAtTopWeight: Int?
    /// Suma de kg × reps de las series con ambos datos.
    let volumeKg: Double
    let totalReps: Int
    let setsWithData: Int

    init?(date: Date, sets: [SetEntry]) {
        let complete = sets.filter { ($0.weightKg ?? 0) > 0 && ($0.reps ?? 0) > 0 }
        let withReps = sets.filter { ($0.reps ?? 0) > 0 }
        guard !withReps.isEmpty else { return nil }
        self.date = date
        let top = complete.max { ($0.weightKg ?? 0, $0.reps ?? 0) < ($1.weightKg ?? 0, $1.reps ?? 0) }
        topWeightKg = top?.weightKg
        repsAtTopWeight = top?.reps
        volumeKg = complete.reduce(0) { $0 + ($1.weightKg ?? 0) * Double($1.reps ?? 0) }
        totalReps = withReps.reduce(0) { $0 + ($1.reps ?? 0) }
        setsWithData = withReps.count
    }

    /// 1RM estimado (Epley) de la mejor serie; solo orientativo.
    var estimatedOneRepMax: Double? {
        guard let w = topWeightKg, let r = repsAtTopWeight, r > 0 else { return nil }
        return r == 1 ? w : w * (1 + Double(r) / 30)
    }
}
