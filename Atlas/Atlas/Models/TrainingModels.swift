import Foundation
import SwiftData

/// Lo que se guarda del entrenamiento de fuerza: cada serie, los récords, la recuperación
/// del día, los suplementos y las semanas marcadas como descarga.
///
/// Todas las propiedades tienen valor por defecto para que añadirlas no rompa la base de
/// datos de quien ya tiene la app instalada.

// MARK: - Serie registrada

@Model
final class SetLog {
    var id: UUID = UUID()
    var order: Int = 0
    var kindRaw: String = SetKind.effective.rawValue
    var weightKg: Double?
    var reps: Int?
    /// Repeticiones en reserva. 0 = al fallo.
    var rir: Int?
    var rpe: Double?
    var restSeconds: Int?
    var isCompleted: Bool = false
    var note: String = ""
    var completedAt: Date?
    var exercise: ExerciseLog?

    init(order: Int, kind: SetKind = .effective, weightKg: Double? = nil, reps: Int? = nil,
         rir: Int? = nil, restSeconds: Int? = nil) {
        self.id = UUID()
        self.order = order
        self.kindRaw = kind.rawValue
        self.weightKg = weightKg
        self.reps = reps
        self.rir = rir
        self.restSeconds = restSeconds
    }

    var kind: SetKind {
        get { SetKind(rawValue: kindRaw) ?? .effective }
        set { kindRaw = newValue.rawValue }
    }

    /// La misma serie como valor puro, que es con lo que trabajan los cálculos.
    var logged: LoggedSet {
        LoggedSet(order: order, kind: kind, weightKg: weightKg, reps: reps, rir: rir,
                  rpe: rpe, restSeconds: restSeconds, isCompleted: isCompleted, note: note)
    }

    func apply(_ set: LoggedSet) {
        order = set.order
        kind = set.kind
        weightKg = set.weightKg
        reps = set.reps
        rir = set.rir
        rpe = set.rpe
        restSeconds = set.restSeconds
        isCompleted = set.isCompleted
        note = set.note
    }

    /// Tiene algo escrito por el usuario (para no contar filas vacías como datos).
    var hasData: Bool { weightKg != nil || reps != nil || rir != nil || isCompleted || !note.isEmpty }

    func markCompleted(_ done: Bool, at date: Date = Date()) {
        isCompleted = done
        completedAt = done ? date : nil
    }
}

// MARK: - Récords personales

@Model
final class PersonalRecordEntry {
    /// "ejercicio|tipo": un récord por ejercicio y tipo.
    @Attribute(.unique) var key: String = ""
    var exerciseID: String = ""
    var exerciseName: String = ""
    var kindRaw: String = RecordKind.topWeight.rawValue
    var value: Double = 0
    var weightKg: Double?
    var reps: Int?
    var date: Date = Date()
    /// Valor que había antes (nil si fue el primero).
    var previousValue: Double?

    init(exerciseID: String, exerciseName: String, kind: RecordKind, value: Double,
         weightKg: Double? = nil, reps: Int? = nil, date: Date = Date(), previousValue: Double? = nil) {
        self.key = PersonalRecordEntry.makeKey(exerciseID: exerciseID, kind: kind)
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.kindRaw = kind.rawValue
        self.value = value
        self.weightKg = weightKg
        self.reps = reps
        self.date = date
        self.previousValue = previousValue
    }

    static func makeKey(exerciseID: String, kind: RecordKind) -> String { "\(exerciseID)|\(kind.rawValue)" }

    var kind: RecordKind { RecordKind(rawValue: kindRaw) ?? .topWeight }

    var valueText: String {
        switch kind {
        case .topWeight, .estimatedOneRepMax:
            return NumberFormat.weight(value)
        case .sessionVolume:
            return "\(NumberFormat.integer(value)) kg"
        case .repsAtWeight:
            return "\(NumberFormat.integer(value)) reps"
        }
    }
}

// MARK: - Recuperación

@Model
final class RecoveryLogEntry {
    @Attribute(.unique) var dayKey: String = ""
    var date: Date = Date()
    var sleepHours: Double?
    /// 1 muy mal … 5 muy bien.
    var sleepQuality: Int?
    var energy: Int?
    /// 1 nada … 5 mucho.
    var fatigue: Int?
    var stress: Int?
    var soreness: Int?
    var hasDiscomfort: Bool = false
    var note: String = ""
    var updatedAt: Date = Date()

    init(date: Date) {
        self.date = DateUtils.startOfDay(date)
        self.dayKey = DateUtils.dayKey(date)
    }

    /// Lo mismo como valor puro, que es con lo que trabaja el análisis.
    var entry: RecoveryEntry {
        RecoveryEntry(date: date, sleepHours: sleepHours, sleepQuality: sleepQuality, energy: energy,
                      fatigue: fatigue, stress: stress, soreness: soreness,
                      hasDiscomfort: hasDiscomfort, note: note)
    }

    func apply(_ entry: RecoveryEntry) {
        sleepHours = entry.sleepHours
        sleepQuality = entry.sleepQuality
        energy = entry.energy
        fatigue = entry.fatigue
        stress = entry.stress
        soreness = entry.soreness
        hasDiscomfort = entry.hasDiscomfort
        note = entry.note
        updatedAt = Date()
    }
}

// MARK: - Suplementos

@Model
final class SupplementEntry {
    var id: UUID = UUID()
    /// Identificador del catálogo, vacío si es uno que ha escrito el usuario.
    var catalogID: String = ""
    var name: String = ""
    var ingredient: String = ""
    var amountPerDose: Double = 0
    var unitRaw: String = DoseUnit.gram.rawValue
    var dosesPerDay: Double = 1
    /// Horas del día separadas por comas ("9,19"), para avisar de la cafeína por la tarde.
    var hoursRaw: String = ""
    var packagePrice: Double?
    var packageDays: Int?
    var isActive: Bool = true
    var note: String = ""
    var createdAt: Date = Date()

    init(catalogID: String = "", name: String, ingredient: String, amountPerDose: Double,
         unit: DoseUnit, dosesPerDay: Double = 1, hours: [Int] = [],
         packagePrice: Double? = nil, packageDays: Int? = nil) {
        self.id = UUID()
        self.catalogID = catalogID
        self.name = name
        self.ingredient = ingredient
        self.amountPerDose = amountPerDose
        self.unitRaw = unit.rawValue
        self.dosesPerDay = dosesPerDay
        self.hoursRaw = hours.map(String.init).joined(separator: ",")
        self.packagePrice = packagePrice
        self.packageDays = packageDays
    }

    var unit: DoseUnit {
        get { DoseUnit(rawValue: unitRaw) ?? .gram }
        set { unitRaw = newValue.rawValue }
    }

    var hours: [Int] {
        get { hoursRaw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) } }
        set { hoursRaw = newValue.map(String.init).joined(separator: ",") }
    }

    var planItem: SupplementPlanItem {
        SupplementPlanItem(id: id.uuidString, catalogID: catalogID.isEmpty ? nil : catalogID,
                           name: name, ingredient: ingredient, amountPerDose: amountPerDose,
                           unit: unit, dosesPerDay: dosesPerDay, hours: hours,
                           packagePrice: packagePrice, packageDays: packageDays)
    }
}

/// Lo tomado un día concreto, para llevar la cuenta de la constancia.
@Model
final class SupplementIntake {
    /// "yyyy-MM-dd|uuid".
    @Attribute(.unique) var key: String = ""
    var dayKey: String = ""
    var date: Date = Date()
    var supplementID: UUID = UUID()
    var dosesTaken: Double = 0

    init(date: Date, supplementID: UUID, dosesTaken: Double) {
        self.key = SupplementIntake.makeKey(dayKey: DateUtils.dayKey(date), supplementID: supplementID)
        self.dayKey = DateUtils.dayKey(date)
        self.date = DateUtils.startOfDay(date)
        self.supplementID = supplementID
        self.dosesTaken = dosesTaken
    }

    static func makeKey(dayKey: String, supplementID: UUID) -> String { "\(dayKey)|\(supplementID.uuidString)" }
}

// MARK: - Semana de entrenamiento

/// Marcas de una semana: por ahora, si es semana de descarga y una nota.
@Model
final class TrainingWeek {
    @Attribute(.unique) var weekKey: String = ""
    var weekStart: Date = Date()
    var isDeload: Bool = false
    var note: String = ""

    init(weekStart: Date, isDeload: Bool = false, note: String = "") {
        self.weekStart = DateUtils.startOfWeek(weekStart)
        self.weekKey = DateUtils.dayKey(DateUtils.startOfWeek(weekStart))
        self.isDeload = isDeload
        self.note = note
    }
}
