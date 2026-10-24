import Foundation
import SwiftData

/// Tipo de sesión de un día de la semana.
enum WorkoutKind: String, CaseIterable, Identifiable, Codable {
    case strength        // solo pesas
    case cardio          // solo correr
    case strengthCardio  // pesas y después carrera
    case rest            // descanso

    var id: String { rawValue }

    var label: String {
        switch self {
        case .strength: return "Pesas"
        case .cardio: return "Carrera"
        case .strengthCardio: return "Pesas + carrera"
        case .rest: return "Descanso"
        }
    }

    var icon: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .cardio: return "figure.run"
        case .strengthCardio: return "flame.fill"
        case .rest: return "moon.zzz.fill"
        }
    }

    /// Si hay que apuntar kilómetros y tiempo.
    var hasCardio: Bool {
        self == .cardio || self == .strengthCardio
    }

    /// Si hay ejercicios con series.
    var hasExercises: Bool {
        self == .strength || self == .strengthCardio
    }
}

/// Un día de la rutina semanal. Todo editable.
@Model
final class WorkoutDayPlan {
    /// 1 = lunes ... 7 = domingo.
    @Attribute(.unique) var weekday: Int
    var name: String
    var kindRaw: String
    /// Nota libre, por ejemplo "20-30 min de carrera suave al terminar".
    var note: String
    @Relationship(deleteRule: .cascade, inverse: \ExercisePlan.day)
    var exercises: [ExercisePlan]

    init(weekday: Int,
         name: String,
         kind: WorkoutKind,
         note: String = "",
         exercises: [ExercisePlan] = []) {
        self.weekday = weekday
        self.name = name
        self.kindRaw = kind.rawValue
        self.note = note
        self.exercises = exercises
    }

    var kind: WorkoutKind {
        get { WorkoutKind(rawValue: kindRaw) ?? .strength }
        set { kindRaw = newValue.rawValue }
    }

    var sortedExercises: [ExercisePlan] {
        exercises.sorted { $0.order < $1.order }
    }

    /// "Lunes", "Martes"...
    var weekdayName: String { DateHelper.weekdayName(weekday) }

    /// Título para Inicio: "Push", "Descanso"...
    var shortTitle: String { name }
}

/// Un ejercicio dentro de un día, con sus series y rango de repeticiones.
@Model
final class ExercisePlan {
    var name: String
    var sets: Int
    var repsMin: Int
    var repsMax: Int
    /// Descanso sugerido entre series, en segundos.
    var restSeconds: Int
    var order: Int
    var day: WorkoutDayPlan?

    init(name: String,
         sets: Int,
         repsMin: Int,
         repsMax: Int,
         restSeconds: Int,
         order: Int) {
        self.name = name
        self.sets = sets
        self.repsMin = repsMin
        self.repsMax = repsMax
        self.restSeconds = restSeconds
        self.order = order
    }

    /// "3 × 8-10"
    var schemeText: String {
        repsMin == repsMax ? "\(sets) × \(repsMax)" : "\(sets) × \(repsMin)-\(repsMax)"
    }

    var restText: String { DateHelper.restText(restSeconds) }
}

/// Un entreno realizado un día concreto.
@Model
final class WorkoutSession {
    /// Normalizada al inicio del día.
    var date: Date
    /// Día de la rutina al que corresponde (1 = lunes).
    var weekday: Int
    var title: String
    var distanceKm: Double
    var durationMinutes: Double
    var notes: String
    @Relationship(deleteRule: .cascade, inverse: \SetLog.session)
    var setLogs: [SetLog]

    init(date: Date,
         weekday: Int,
         title: String,
         distanceKm: Double = 0,
         durationMinutes: Double = 0,
         notes: String = "",
         setLogs: [SetLog] = []) {
        self.date = date
        self.weekday = weekday
        self.title = title
        self.distanceKm = distanceKm
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.setLogs = setLogs
    }

    /// Series apuntadas de un ejercicio, en orden.
    func logs(for exerciseName: String) -> [SetLog] {
        setLogs
            .filter { $0.exerciseName == exerciseName }
            .sorted { $0.setIndex < $1.setIndex }
    }

    /// Si se ha apuntado algo (series o carrera).
    var hasContent: Bool {
        distanceKm > 0 || durationMinutes > 0 || setLogs.contains { $0.isFilled }
    }

    /// Peso total movido, por si sirve de referencia.
    var volume: Double {
        setLogs.reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }
}

/// Una serie apuntada: peso y repeticiones.
@Model
final class SetLog {
    var exerciseName: String
    var setIndex: Int
    var weightKg: Double
    var reps: Int
    var session: WorkoutSession?

    init(exerciseName: String,
         setIndex: Int,
         weightKg: Double = 0,
         reps: Int = 0) {
        self.exerciseName = exerciseName
        self.setIndex = setIndex
        self.weightKg = weightKg
        self.reps = reps
    }

    /// Una serie cuenta cuando tiene repeticiones.
    var isFilled: Bool { reps > 0 }

    /// "60 kg × 10"
    var summary: String {
        guard isFilled else { return "—" }
        return "\(Formatters.weight(weightKg)) kg × \(reps)"
    }
}

/// Un peso corporal apuntado un día.
@Model
final class WeightEntry {
    @Attribute(.unique) var date: Date
    var kg: Double

    init(date: Date, kg: Double) {
        self.date = date
        self.kg = kg
    }
}
