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

// MARK: - Ejercicio creado por el usuario

/// Un ejercicio que no está en la biblioteca y que el usuario se crea, diciendo qué músculo
/// trabaja. Así cuenta en el volumen por músculo, en el mapa del cuerpo y en los informes.
///
/// El enganche con lo registrado es el NOMBRE (el catálogo busca por nombre cuando no reconoce
/// el identificador). Por eso, al renombrarlo, el nombre anterior se guarda en `previousNames`:
/// lo que ya habías apuntado sigue contando.
@Model
final class CustomExercise {
    @Attribute(.unique) var id: String = ""
    var name: String = ""
    var primaryRaw: String = MuscleGroup.chest.rawValue
    /// Músculos secundarios separados por "|".
    var secondaryRaw: String = ""
    var patternRaw: String = MovementPattern.horizontalPush.rawValue
    var equipmentRaw: String = Equipment.machine.rawValue
    var isUnilateral: Bool = false
    var defaultSets: Int = 3
    var defaultRepMin: Int = 8
    var defaultRepMax: Int = 12
    /// Nota del usuario: cómo lo hace él (ángulo, agarre, máquina concreta…).
    var note: String = ""
    /// Nombres que tuvo antes, separados por "|".
    var previousNames: String = ""
    var createdAt: Date = Date()

    init(name: String, primary: MuscleGroup, secondary: [MuscleGroup] = [],
         pattern: MovementPattern, equipment: Equipment, unilateral: Bool = false,
         sets: Int = 3, repMin: Int = 8, repMax: Int = 12, note: String = "") {
        self.id = "mio-" + UUID().uuidString.lowercased()
        self.name = name
        self.primaryRaw = primary.rawValue
        self.secondaryRaw = CustomExercise.join(secondary.map(\.rawValue))
        self.patternRaw = pattern.rawValue
        self.equipmentRaw = equipment.rawValue
        self.isUnilateral = unilateral
        self.defaultSets = sets
        self.defaultRepMin = repMin
        self.defaultRepMax = repMax
        self.note = note
        self.createdAt = Date()
    }

    static func join(_ parts: [String]) -> String { parts.joined(separator: "|") }
    static func split(_ text: String) -> [String] {
        text.split(separator: "|").map(String.init).filter { !$0.isEmpty }
    }

    var primary: MuscleGroup {
        get { MuscleGroup(rawValue: primaryRaw) ?? .chest }
        set { primaryRaw = newValue.rawValue }
    }

    var secondary: [MuscleGroup] {
        get { CustomExercise.split(secondaryRaw).compactMap(MuscleGroup.init(rawValue:)) }
        set { secondaryRaw = CustomExercise.join(newValue.map(\.rawValue)) }
    }

    var pattern: MovementPattern {
        get { MovementPattern(rawValue: patternRaw) ?? .horizontalPush }
        set { patternRaw = newValue.rawValue }
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .machine }
        set { equipmentRaw = newValue.rawValue }
    }

    var aliases: [String] { CustomExercise.split(previousNames) }

    /// Guarda el nombre viejo como alias antes de cambiarlo.
    func rename(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, ExerciseCatalog.normalize(trimmed) != ExerciseCatalog.normalize(name) else { return }
        var previous = aliases
        if !previous.contains(name) { previous.append(name) }
        previousNames = CustomExercise.join(previous)
        name = trimmed
    }

    /// Ficha para la biblioteca y para el reparto de volumen.
    var info: ExerciseInfo {
        CustomExerciseRules.info(id: id, name: name, primary: primary, secondary: secondary,
                                 pattern: pattern, equipment: equipment, unilateral: isUnilateral,
                                 sets: defaultSets, repMin: defaultRepMin, repMax: defaultRepMax,
                                 note: note, aliases: aliases)
    }
}
