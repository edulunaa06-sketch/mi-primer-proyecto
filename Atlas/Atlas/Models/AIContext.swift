import Foundation

/// Lo que la IA puede ver de tus datos, con tipos y sin sorpresas.
///
/// Reglas de este módulo:
/// · **Solo lectura.** No existe ninguna vía para que la IA escriba en la base de datos.
///   Lo que proponga llega como texto y lo aplicas tú si te convence.
/// · **Nada se envía por defecto.** El contexto se construye y se muestra en pantalla antes
///   de enviarlo, así que siempre se puede ver exactamente qué sale del teléfono.
/// · **Los huecos van declarados.** Si falta información, viaja en `caveats` en lugar de
///   mandar ceros que la IA pueda confundir con datos reales.
/// · Fotos de progreso y claves nunca entran aquí.
struct AIContext: Codable, Equatable {
    let generatedAt: Date
    let periodDays: Int
    let profile: Profile?
    let training: Training
    let exercises: [Exercise]
    let nutrition: Nutrition
    let body: Body
    let recovery: Recovery
    /// Qué falta para que lo de arriba sea fiable. Se envía tal cual.
    let caveats: [String]

    // MARK: Piezas

    struct Profile: Codable, Equatable {
        let sex: String?
        let age: Int?
        let heightCm: Double?
        let weightKg: Double?
        let activity: String
        let goal: String
        let kcalTarget: Double
        let proteinTarget: Double
        let carbsTarget: Double
        let fatTarget: Double
        /// true si los objetivos los calcula la app; false si los ha escrito el usuario.
        let automaticTargets: Bool
    }

    struct MuscleLine: Codable, Equatable {
        let muscle: String
        let directSets: Double
        let totalSets: Double
        let frequency: Int
        /// «en la referencia», «por debajo», «por encima» o «sin series».
        let verdict: String
    }

    struct Training: Codable, Equatable {
        let sessionsCompleted: Int
        let sessionsScheduled: Int
        let workSets: Int
        let tonnageKg: Double
        let adherencePercent: Double?
        let isDeloadWeek: Bool
        let muscles: [MuscleLine]
        /// Ejercicios apuntados que no están en la biblioteca (sus series no se reparten por músculo).
        let unclassifiedExercises: [String]
    }

    struct Exercise: Codable, Equatable {
        let name: String
        let muscle: String?
        let lastTopSet: String?
        let estimatedOneRepMax: Double?
        /// Fiabilidad de ese 1RM estimado.
        let oneRepMaxConfidence: String?
        let sessionsLogged: Int
        let trend: String
        let changePercent: Double?
        let isStalled: Bool
        let suggestedAction: String
        let suggestedReason: String
    }

    struct Nutrition: Codable, Equatable {
        let daysLogged: Int
        let daysInPeriod: Int
        let averageKcal: Double?
        let averageProtein: Double?
        let averageCarbs: Double?
        let averageFat: Double?
        let kcalTarget: Double?
        let proteinTarget: Double?
        var hasEnoughData: Bool { daysLogged >= NutritionReport.minimumDays }
    }

    struct Body: Codable, Equatable {
        let weighIns: Int
        let lastWeightKg: Double?
        let changeKg: Double?
        let changePerWeekKg: Double?
    }

    struct Recovery: Codable, Equatable {
        let daysLogged: Int
        let averageSleepHours: Double?
        let averageSleepQuality: Double?
        let averageFatigue: Double?
        let averageStress: Double?
        let daysWithDiscomfort: Int
    }

    // MARK: Construcción

    /// Monta el contexto a partir de un informe ya calculado y del estado de los ejercicios.
    /// No hace cuentas nuevas: reutiliza las mismas que ve el usuario en pantalla,
    /// de modo que lo que lee la IA y lo que lees tú no pueden discrepar.
    init(report: PeriodReport, profile: Profile?, exercises: [Exercise],
         isDeloadWeek: Bool, generatedAt: Date = Date()) {
        self.generatedAt = generatedAt
        self.periodDays = report.period.dayCount
        self.profile = profile
        self.exercises = exercises
        self.training = Training(
            sessionsCompleted: report.training.sessionsCompleted,
            sessionsScheduled: report.training.sessionsScheduled,
            workSets: report.training.workSets,
            tonnageKg: report.training.tonnageKg,
            adherencePercent: report.training.adherence.fraction.map { $0 * 100 },
            isDeloadWeek: isDeloadWeek,
            muscles: report.training.muscles.map {
                MuscleLine(muscle: $0.group.label, directSets: $0.directSets, totalSets: $0.totalSets,
                           frequency: $0.frequency, verdict: $0.verdict.label)
            },
            unclassifiedExercises: report.training.unclassifiedExercises
        )
        self.nutrition = Nutrition(
            daysLogged: report.nutrition.daysLogged,
            daysInPeriod: report.nutrition.daysInPeriod,
            averageKcal: report.nutrition.hasEnoughData ? report.nutrition.averageKcal : nil,
            averageProtein: report.nutrition.hasEnoughData ? report.nutrition.averageProtein : nil,
            averageCarbs: report.nutrition.hasEnoughData ? report.nutrition.averageCarbs : nil,
            averageFat: report.nutrition.hasEnoughData ? report.nutrition.averageFat : nil,
            kcalTarget: report.nutrition.kcalTarget,
            proteinTarget: report.nutrition.proteinTarget
        )
        self.body = Body(
            weighIns: report.body.weighIns,
            lastWeightKg: report.body.lastWeight,
            changeKg: report.body.hasEnoughData ? report.body.change : nil,
            changePerWeekKg: report.body.hasEnoughData ? report.body.changePerWeek : nil
        )
        let averages = report.recovery.averages
        self.recovery = Recovery(
            daysLogged: averages.daysLogged,
            averageSleepHours: report.recovery.hasEnoughData ? averages.sleepHours : nil,
            averageSleepQuality: report.recovery.hasEnoughData ? averages.sleepQuality : nil,
            averageFatigue: report.recovery.hasEnoughData ? averages.fatigue : nil,
            averageStress: report.recovery.hasEnoughData ? averages.stress : nil,
            daysWithDiscomfort: averages.daysWithDiscomfort
        )
        self.caveats = report.caveats
    }

    // MARK: Para enseñar y para enviar

    /// Resumen legible, que es también lo que se envía. Compacto a propósito: menos texto,
    /// menos coste y menos sitio donde esconder algo.
    var compactText: String {
        var lines: [String] = []
        lines.append("PERIODO: últimos \(periodDays) días.")

        if let profile {
            var parts: [String] = []
            if let sex = profile.sex { parts.append(sex) }
            if let age = profile.age { parts.append("\(age) años") }
            if let height = profile.heightCm { parts.append("\(NumberFormat.integer(height)) cm") }
            if let weight = profile.weightKg { parts.append(NumberFormat.weight(weight)) }
            lines.append("PERFIL: " + parts.joined(separator: ", ")
                         + ". Actividad: \(profile.activity). Objetivo: \(profile.goal).")
            lines.append("OBJETIVOS: \(NumberFormat.integer(profile.kcalTarget)) kcal, "
                         + "\(NumberFormat.integer(profile.proteinTarget)) g de proteína, "
                         + "\(NumberFormat.integer(profile.carbsTarget)) g de hidratos, "
                         + "\(NumberFormat.integer(profile.fatTarget)) g de grasa"
                         + (profile.automaticTargets ? " (calculados por la app)." : " (puestos a mano)."))
        } else {
            lines.append("PERFIL: incompleto (falta altura, edad, sexo o peso).")
        }

        lines.append("ENTRENAMIENTO: \(training.sessionsCompleted) de \(training.sessionsScheduled) sesiones, "
                     + "\(training.workSets) series de trabajo, \(NumberFormat.integer(training.tonnageKg)) kg movidos"
                     + (training.adherencePercent.map { ", \(NumberFormat.integer($0)) % de lo programado" } ?? "")
                     + (training.isDeloadWeek ? ". Semana marcada como DESCARGA." : "."))

        if !training.muscles.isEmpty {
            lines.append("SERIES POR MÚSCULO (directas/total, frecuencia, veredicto):")
            for muscle in training.muscles {
                lines.append("· \(muscle.muscle): \(NumberFormat.oneDecimal(muscle.directSets))"
                             + "/\(NumberFormat.oneDecimal(muscle.totalSets)), "
                             + "\(muscle.frequency) día(s), \(muscle.verdict)")
            }
        }
        if !training.unclassifiedExercises.isEmpty {
            lines.append("SIN CLASIFICAR (no están en la biblioteca): "
                         + training.unclassifiedExercises.joined(separator: ", "))
        }

        if !exercises.isEmpty {
            lines.append("EJERCICIOS:")
            for exercise in exercises {
                var line = "· \(exercise.name)"
                if let muscle = exercise.muscle { line += " [\(muscle)]" }
                if let top = exercise.lastTopSet { line += ": última mejor serie \(top)" }
                if let max1 = exercise.estimatedOneRepMax {
                    line += ", 1RM estimado \(NumberFormat.weight(max1))"
                    if let confidence = exercise.oneRepMaxConfidence { line += " (\(confidence))" }
                }
                line += ". \(exercise.sessionsLogged) sesión(es), tendencia \(exercise.trend)"
                if let change = exercise.changePercent { line += " (\(NumberFormat.oneDecimal(change)) %)" }
                if exercise.isStalled { line += ", ESTANCADO" }
                line += ". Propuesta de la app: \(exercise.suggestedAction) — \(exercise.suggestedReason)"
                lines.append(line)
            }
        }

        if nutrition.hasEnoughData, let kcal = nutrition.averageKcal {
            lines.append("NUTRICIÓN: \(NumberFormat.integer(kcal)) kcal/día de media "
                         + "en \(nutrition.daysLogged) de \(nutrition.daysInPeriod) días"
                         + (nutrition.averageProtein.map { ". Proteína: \(NumberFormat.integer($0)) g/día" } ?? "")
                         + (nutrition.averageCarbs.map { ", hidratos \(NumberFormat.integer($0)) g" } ?? "")
                         + (nutrition.averageFat.map { ", grasa \(NumberFormat.integer($0)) g" } ?? "") + ".")
        } else {
            lines.append("NUTRICIÓN: solo \(nutrition.daysLogged) de \(nutrition.daysInPeriod) días apuntados; "
                         + "no hay media fiable.")
        }

        if let change = body.changeKg {
            lines.append("PESO: \(NumberFormat.signedKg(change)) en el periodo"
                         + (body.changePerWeekKg.map { " (\(NumberFormat.signedKg($0))/semana)" } ?? "")
                         + (body.lastWeightKg.map { ", media actual \(NumberFormat.weight($0))" } ?? "") + ".")
        } else {
            lines.append("PESO: \(body.weighIns) pesaje(s); no hay tendencia fiable.")
        }

        if recovery.daysLogged > 0 {
            var line = "RECUPERACIÓN: \(recovery.daysLogged) día(s) apuntados"
            if let sleep = recovery.averageSleepHours { line += ", sueño \(NumberFormat.oneDecimal(sleep)) h" }
            if let fatigue = recovery.averageFatigue { line += ", fatiga \(NumberFormat.oneDecimal(fatigue))/5" }
            if let stress = recovery.averageStress { line += ", estrés \(NumberFormat.oneDecimal(stress))/5" }
            if recovery.daysWithDiscomfort > 0 { line += ", \(recovery.daysWithDiscomfort) día(s) con molestias" }
            lines.append(line + ".")
        } else {
            lines.append("RECUPERACIÓN: sin datos apuntados.")
        }

        if !caveats.isEmpty {
            lines.append("LO QUE FALTA (no lo rellenes con suposiciones):")
            for caveat in caveats { lines.append("· \(caveat)") }
        }
        return lines.joined(separator: "\n")
    }

    /// Cuántos datos reales hay. Con muy poco, la app avisa antes de preguntar a la IA.
    var filledSections: Int {
        var count = 0
        if profile != nil { count += 1 }
        if training.workSets > 0 { count += 1 }
        if nutrition.hasEnoughData { count += 1 }
        if body.changeKg != nil { count += 1 }
        if recovery.daysLogged > 0 { count += 1 }
        return count
    }

    var isTooEmptyToBeUseful: Bool { filledSections < 2 }
}

// MARK: - Qué puede consultar la IA

/// Catálogo de lo que la IA ve, para poder enseñárselo al usuario antes de enviar nada.
/// Es la lista real: cada entrada corresponde a un campo de `AIContext`.
enum AIDataScope: String, CaseIterable, Identifiable {
    case profile, targets, sessions, volume, exercises, progression, nutrition, body, recovery, gaps

    var id: String { rawValue }

    var label: String {
        switch self {
        case .profile: return "Perfil"
        case .targets: return "Objetivos de kcal y macros"
        case .sessions: return "Sesiones del periodo"
        case .volume: return "Series por grupo muscular y frecuencia"
        case .exercises: return "Mejor serie y 1RM estimado por ejercicio"
        case .progression: return "Propuesta de progresión y estancamientos"
        case .nutrition: return "Medias de kcal y macros"
        case .body: return "Peso y su tendencia"
        case .recovery: return "Sueño, fatiga, estrés y molestias"
        case .gaps: return "Lo que falta por apuntar"
        }
    }

    var detail: String {
        switch self {
        case .profile: return "Sexo, edad, altura y peso, si los has rellenado."
        case .targets: return "Tus objetivos diarios y si los calcula la app o los has puesto tú."
        case .sessions: return "Cuántas sesiones has hecho de las previstas, series y kilos movidos."
        case .volume: return "Series directas e indirectas por músculo y en cuántos días distintos."
        case .exercises: return "Tu mejor serie de cada ejercicio y el 1RM que se estima de ella."
        case .progression: return "Lo que la app propone para cada ejercicio y por qué."
        case .nutrition: return "Medias del periodo, solo si hay días suficientes apuntados."
        case .body: return "Tu peso medio y cuánto ha cambiado por semana."
        case .recovery: return "Lo que has contestado en Recuperación."
        case .gaps: return "Los avisos de «faltan datos», para que la IA no se los invente."
        }
    }
}

/// Lo que NUNCA sale del teléfono, dicho con nombres y apellidos.
enum AIDataExclusions {
    static let all = [
        "Tus fotos de progreso.",
        "La clave de la IA y los tokens de Strava (viven en el Llavero).",
        "Tus registros día a día: solo van medias y totales del periodo.",
        "Nada si no pulsas «Preguntar»: el contexto se construye en el teléfono y se te enseña antes.",
    ]
}
