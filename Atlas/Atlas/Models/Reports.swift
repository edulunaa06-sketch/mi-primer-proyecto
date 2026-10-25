import Foundation

/// Informes por periodo: junta entrenamiento, nutrición, cuerpo y recuperación.
///
/// Dos normas que se cumplen en todas las secciones:
/// · Si no hay datos suficientes, la sección lo dice. No se rellena con ceros ni con medias de nada.
/// · Se describen tendencias. No se afirma que una cosa haya causado otra.

enum ReportRange: String, CaseIterable, Identifiable {
    case week, month, quarter, year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: return "Semana"
        case .month: return "Mes"
        case .quarter: return "3 meses"
        case .year: return "Año"
        }
    }

    var days: Int {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        }
    }

    /// Periodo que termina hoy (incluido).
    func period(endingAt date: Date, calendar: Calendar = DateUtils.calendar) -> ReportPeriod {
        let end = DateUtils.startOfDay(date)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        return ReportPeriod(start: start, end: end, label: label)
    }

    /// El periodo anterior del mismo tamaño, para comparar.
    func previousPeriod(endingAt date: Date, calendar: Calendar = DateUtils.calendar) -> ReportPeriod {
        let current = period(endingAt: date, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: -1, to: current.start) ?? current.start
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        return ReportPeriod(start: start, end: end, label: "\(label) anterior")
    }
}

struct ReportPeriod: Equatable {
    let start: Date
    let end: Date
    let label: String

    func contains(_ date: Date) -> Bool {
        let day = DateUtils.startOfDay(date)
        return day >= DateUtils.startOfDay(start) && day <= DateUtils.startOfDay(end)
    }

    var dayCount: Int {
        let days = DateUtils.calendar.dateComponents([.day], from: DateUtils.startOfDay(start),
                                                     to: DateUtils.startOfDay(end)).day ?? 0
        return days + 1
    }

    var text: String { "\(DateUtils.dayMonth(start)) – \(DateUtils.dayMonth(end))" }
}

// MARK: - Entrada

/// Todo lo que hace falta para un informe, ya filtrado por periodo.
struct ReportInput {
    var period: ReportPeriod
    /// Trabajo de fuerza realizado.
    var work: [VolumeAnalytics.ExerciseWork] = []
    var sessionsCompleted: Int = 0
    var sessionsScheduled: Int = 0
    /// Series que pedía la rutina en el periodo.
    var programmedSets: Int = 0
    var records: [RecordCandidate] = []
    /// Días con nutrición apuntada.
    var nutritionDays: [NutritionDay] = []
    var kcalTarget: Double?
    var proteinTarget: Double?
    var weights: [WeightStats.Point] = []
    var recovery: [RecoveryEntry] = []
    var runKilometers: Double = 0
    var runs: Int = 0

    struct NutritionDay: Equatable {
        let date: Date
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }
}

// MARK: - Secciones

struct TrainingReport: Equatable {
    let sessionsCompleted: Int
    let sessionsScheduled: Int
    let workSets: Int
    let tonnageKg: Double
    let muscles: [VolumeAnalytics.MuscleVolume]
    let unclassifiedExercises: [String]
    let adherence: VolumeAnalytics.Adherence
    let newRecords: Int
    let runs: Int
    let runKilometers: Double

    var hasEnoughData: Bool { workSets > 0 || sessionsCompleted > 0 }

    /// Grupos sin ni una serie directa en el periodo.
    var untrainedGroups: [MuscleGroup] {
        let trained = Set(muscles.filter { $0.directSets > 0 }.map(\.group))
        return MuscleGroup.allCases.filter { !trained.contains($0) }
    }
}

struct NutritionReport: Equatable {
    let daysLogged: Int
    let daysInPeriod: Int
    let averageKcal: Double?
    let averageProtein: Double?
    let averageCarbs: Double?
    let averageFat: Double?
    let kcalTarget: Double?
    let proteinTarget: Double?

    /// Con menos de este número de días apuntados, una media diaria engaña más que ayuda.
    static let minimumDays = 4

    var hasEnoughData: Bool { daysLogged >= Self.minimumDays }

    /// Qué parte del periodo está realmente apuntada.
    var coverage: Double? {
        guard daysInPeriod > 0 else { return nil }
        return Double(daysLogged) / Double(daysInPeriod)
    }

    var kcalDifference: Double? {
        guard let averageKcal, let kcalTarget else { return nil }
        return averageKcal - kcalTarget
    }

    var proteinDifference: Double? {
        guard let averageProtein, let proteinTarget else { return nil }
        return averageProtein - proteinTarget
    }
}

struct BodyReport: Equatable {
    let weighIns: Int
    let firstWeight: Double?
    let lastWeight: Double?
    /// Cambio entre la primera y la última media semanal (no entre dos pesajes sueltos).
    let change: Double?
    let weeklyAverages: [WeightStats.Point]

    /// Hacen falta pesajes en al menos dos semanas distintas para hablar de cambio.
    static let minimumWeeks = 2

    var hasEnoughData: Bool { weeklyAverages.count >= Self.minimumWeeks }

    /// Cambio por semana, que es lo que de verdad se compara con un objetivo.
    var changePerWeek: Double? {
        guard let change, weeklyAverages.count >= 2 else { return nil }
        return change / Double(weeklyAverages.count - 1)
    }
}

struct RecoveryReport: Equatable {
    let averages: RecoveryAnalysis.Averages
    let daysInPeriod: Int

    static let minimumDays = 3

    var hasEnoughData: Bool { averages.daysLogged >= Self.minimumDays }
}

// MARK: - Informe

struct PeriodReport: Equatable {
    let period: ReportPeriod
    let training: TrainingReport
    let nutrition: NutritionReport
    let body: BodyReport
    let recovery: RecoveryReport
    /// Frases con lo más destacable, ya redactadas.
    let highlights: [String]
    /// Lo que falta para que el informe sea fiable.
    let caveats: [String]

    var hasAnyData: Bool {
        training.hasEnoughData || nutrition.daysLogged > 0 || body.weighIns > 0 || recovery.averages.daysLogged > 0
    }
}

enum ReportBuilder {
    static func build(_ input: ReportInput) -> PeriodReport {
        let volume = VolumeAnalytics.byMuscle(input.work)
        let training = TrainingReport(
            sessionsCompleted: input.sessionsCompleted,
            sessionsScheduled: input.sessionsScheduled,
            workSets: VolumeAnalytics.totalWorkSets(input.work),
            tonnageKg: VolumeAnalytics.totalTonnage(input.work),
            muscles: volume.muscles,
            unclassifiedExercises: Array(Set(volume.unclassified.map(\.name))).sorted(),
            adherence: VolumeAnalytics.adherence(programmedSets: input.programmedSets, work: input.work),
            newRecords: input.records.filter { !$0.isFirstEver }.count,
            runs: input.runs,
            runKilometers: input.runKilometers
        )

        let days = input.nutritionDays
        func mean(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        let nutrition = NutritionReport(
            daysLogged: days.count,
            daysInPeriod: input.period.dayCount,
            averageKcal: mean(days.map(\.kcal)),
            averageProtein: mean(days.map(\.protein)),
            averageCarbs: mean(days.map(\.carbs)),
            averageFat: mean(days.map(\.fat)),
            kcalTarget: input.kcalTarget,
            proteinTarget: input.proteinTarget
        )

        let weekly = weeklyAverages(input.weights)
        let body = BodyReport(
            weighIns: input.weights.count,
            firstWeight: weekly.first?.kg,
            lastWeight: weekly.last?.kg,
            change: weekly.count >= 2 ? (weekly.last!.kg - weekly.first!.kg) : nil,
            weeklyAverages: weekly
        )

        let recovery = RecoveryReport(averages: RecoveryAnalysis.averages(input.recovery),
                                      daysInPeriod: input.period.dayCount)

        return PeriodReport(period: input.period, training: training, nutrition: nutrition,
                            body: body, recovery: recovery,
                            highlights: highlights(training: training, nutrition: nutrition, body: body, recovery: recovery),
                            caveats: caveats(training: training, nutrition: nutrition, body: body, recovery: recovery))
    }

    /// Media del peso por semana. Un pesaje suelto varía por el agua y la comida del día:
    /// la media semanal es lo que permite ver una tendencia.
    static func weeklyAverages(_ points: [WeightStats.Point], calendar: Calendar = DateUtils.calendar) -> [WeightStats.Point] {
        let groups = Dictionary(grouping: points) { DateUtils.startOfWeek($0.date) }
        return groups.keys.sorted().map { week in
            let values = groups[week]!.map(\.kg)
            return WeightStats.Point(date: week, kg: values.reduce(0, +) / Double(values.count))
        }
    }

    // MARK: Frases

    static func highlights(training: TrainingReport, nutrition: NutritionReport,
                           body: BodyReport, recovery: RecoveryReport) -> [String] {
        var out: [String] = []

        if training.hasEnoughData {
            out.append("\(training.sessionsCompleted) sesiones y \(training.workSets) series de trabajo, "
                       + "\(NumberFormat.integer(training.tonnageKg)) kg movidos en total.")
            if let fraction = training.adherence.fraction {
                out.append("Cumplimiento de la rutina: \(NumberFormat.percent(fraction)) de las series programadas.")
            }
            if training.newRecords > 0 {
                out.append(NumberFormat.plural(training.newRecords, "récord personal batido", "récords personales batidos") + ".")
            }
            if let top = training.muscles.max(by: { $0.directSets < $1.directSets }) {
                out.append("El grupo con más trabajo directo ha sido \(top.group.label.lowercased()) "
                           + "con \(NumberFormat.oneDecimal(top.directSets)) series.")
            }
            if training.runKilometers > 0 {
                out.append("\(NumberFormat.oneDecimal(training.runKilometers)) km corridos en "
                       + NumberFormat.plural(training.runs, "salida", "salidas") + ".")
            }
        }

        if nutrition.hasEnoughData, let kcal = nutrition.averageKcal {
            var line = "Media de \(NumberFormat.integer(kcal)) kcal al día en \(nutrition.daysLogged) días apuntados."
            if let diff = nutrition.kcalDifference {
                let sense = diff > 0 ? "por encima" : "por debajo"
                line += " Eso queda \(NumberFormat.integer(abs(diff))) kcal \(sense) de tu objetivo."
            }
            out.append(line)
            if let protein = nutrition.averageProtein {
                out.append("Proteína media: \(NumberFormat.integer(protein)) g al día.")
            }
        }

        if body.hasEnoughData, let change = body.change {
            let direction = change > 0 ? "subido" : (change < 0 ? "bajado" : "quedado igual")
            var line = "El peso ha \(direction) \(NumberFormat.kg(abs(change))) kg comparando medias semanales."
            if let perWeek = body.changePerWeek {
                line += " Son \(NumberFormat.signedKg(perWeek)) por semana."
            }
            out.append(line)
        }

        if recovery.hasEnoughData {
            if let sleep = recovery.averages.sleepHours {
                out.append("Has dormido \(NumberFormat.oneDecimal(sleep)) horas de media.")
            }
            if recovery.averages.daysWithDiscomfort > 0 {
                out.append(NumberFormat.plural(recovery.averages.daysWithDiscomfort,
                                       "día con alguna molestia apuntada",
                                       "días con alguna molestia apuntada") + ".")
            }
        }

        return out
    }

    static func caveats(training: TrainingReport, nutrition: NutritionReport,
                        body: BodyReport, recovery: RecoveryReport) -> [String] {
        var out: [String] = []

        if !training.hasEnoughData {
            out.append("No hay entrenamientos apuntados en este periodo, así que no hay nada que resumir de fuerza.")
        } else if !training.unclassifiedExercises.isEmpty {
            out.append("Estos ejercicios no están en la biblioteca, así que sus series no se reparten por músculo: "
                       + training.unclassifiedExercises.joined(separator: ", ") + ".")
        }

        if !nutrition.hasEnoughData {
            if nutrition.daysLogged == 0 {
                out.append("No hay comidas apuntadas: no se puede decir nada de calorías ni de macros.")
            } else {
                out.append("Solo hay " + NumberFormat.plural(nutrition.daysLogged, "día", "días")
                           + " de comidas apuntados de \(nutrition.daysInPeriod). "
                           + "Una media con tan pocos días no representa lo que comes de verdad.")
            }
        } else if let coverage = nutrition.coverage, coverage < 0.7 {
            out.append("Están apuntados \(NumberFormat.percent(coverage)) de los días: la media es orientativa.")
        }

        if !body.hasEnoughData {
            out.append(body.weighIns == 0 ? "Sin pesajes en el periodo."
                       : "Hacen falta pesajes en al menos dos semanas distintas para ver una tendencia de peso.")
        }

        if !recovery.hasEnoughData {
            out.append("Con " + NumberFormat.plural(recovery.averages.daysLogged, "día", "días")
                       + " de recuperación apuntados no hay base para una media.")
        }

        if training.hasEnoughData && nutrition.hasEnoughData && body.hasEnoughData {
            out.append("El informe describe lo que ha pasado a la vez; no demuestra que una cosa haya causado otra.")
        }
        return out
    }
}

// MARK: - Comparar periodos

struct ReportComparison: Equatable {
    struct Delta: Equatable {
        let label: String
        let current: Double
        let previous: Double
        /// true si subir es mejor; nil si no hay un «mejor» claro (como el peso).
        let higherIsBetter: Bool?

        var difference: Double { current - previous }

        var percent: Double? {
            guard previous != 0 else { return nil }
            return (current - previous) / abs(previous) * 100
        }
    }

    let current: PeriodReport
    let previous: PeriodReport
    let deltas: [Delta]
}

enum ReportComparer {
    /// Compara dos informes del mismo tamaño. Solo compara lo que tiene datos en los dos.
    static func compare(current: PeriodReport, previous: PeriodReport) -> ReportComparison {
        var deltas: [ReportComparison.Delta] = []

        if current.training.hasEnoughData && previous.training.hasEnoughData {
            deltas.append(.init(label: "Sesiones", current: Double(current.training.sessionsCompleted),
                                previous: Double(previous.training.sessionsCompleted), higherIsBetter: true))
            deltas.append(.init(label: "Series de trabajo", current: Double(current.training.workSets),
                                previous: Double(previous.training.workSets), higherIsBetter: true))
            deltas.append(.init(label: "Kilos movidos", current: current.training.tonnageKg,
                                previous: previous.training.tonnageKg, higherIsBetter: true))
        }
        if current.nutrition.hasEnoughData, previous.nutrition.hasEnoughData,
           let a = current.nutrition.averageKcal, let b = previous.nutrition.averageKcal {
            deltas.append(.init(label: "Kcal al día", current: a, previous: b, higherIsBetter: nil))
        }
        if current.nutrition.hasEnoughData, previous.nutrition.hasEnoughData,
           let a = current.nutrition.averageProtein, let b = previous.nutrition.averageProtein {
            deltas.append(.init(label: "Proteína al día", current: a, previous: b, higherIsBetter: true))
        }
        if let a = current.body.lastWeight, let b = previous.body.lastWeight {
            deltas.append(.init(label: "Peso", current: a, previous: b, higherIsBetter: nil))
        }
        if current.recovery.hasEnoughData, previous.recovery.hasEnoughData,
           let a = current.recovery.averages.sleepHours, let b = previous.recovery.averages.sleepHours {
            deltas.append(.init(label: "Horas de sueño", current: a, previous: b, higherIsBetter: true))
        }

        return ReportComparison(current: current, previous: previous, deltas: deltas)
    }
}
