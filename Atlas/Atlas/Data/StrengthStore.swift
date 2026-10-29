import Foundation
import SwiftData

/// Operaciones de datos del entrenamiento de fuerza: series, historial por ejercicio,
/// récords, recuperación, suplementos y la entrada de los informes.
/// Es la capa que une la base de datos con los cálculos puros.
enum StrengthStore {

    // MARK: Series de una sesión

    /// Todo lo que hace falta saber de un ejercicio para abrir su tarjeta, con UNA sola
    /// lectura del historial. Antes se leía tres veces por ejercicio (series, propuesta y
    /// sesión anterior), y con varios meses apuntados eso se notaba al abrir el entreno.
    struct ExerciseContext {
        /// Sesiones anteriores a la semana en curso, de la más antigua a la más reciente.
        let history: [ExerciseSessionSummary]
        /// Series de la última sesión anterior con datos.
        let previousSets: [LoggedSet]
        let advice: ProgressionEngine.Advice
    }

    @MainActor
    static func exerciseContext(for exerciseLog: ExerciseLog, in context: ModelContext) -> ExerciseContext {
        let exerciseID = exerciseLog.exerciseID
        let weekStart = exerciseLog.session?.weekStart ?? Date()
        let descriptor = FetchDescriptor<ExerciseLog>(predicate: #Predicate { $0.exerciseID == exerciseID })
        let logs = (try? context.fetch(descriptor)) ?? []

        // Solo lo ANTERIOR a esta semana: la sesión de hoy no se compara consigo misma.
        let earlier = logs.compactMap { log -> (date: Date, log: ExerciseLog)? in
            guard let session = log.session, session.weekStart < weekStart else { return nil }
            return (session.completedAt ?? session.finishedAt ?? session.weekStart, log)
        }
        .sorted { $0.date < $1.date }

        let history = earlier.compactMap { $0.log.summary(on: $0.date) }
        let previousSets = earlier.last { $0.log.hasLoggedData }?.log.loggedSets ?? []
        let advice = ProgressionEngine.advise(history: history, target: exerciseLog.repTarget,
                                              equipment: exerciseLog.equipment,
                                              hasDiscomfort: exerciseLog.hasDiscomfort,
                                              isDeloadWeek: isDeloadWeek(weekStart, in: context))
        return ExerciseContext(history: history, previousSets: previousSets, advice: advice)
    }

    /// Crea las filas de serie que faltan para un ejercicio, con el peso propuesto por la
    /// progresión. No toca las series que ya tengan algo apuntado.
    @MainActor
    @discardableResult
    static func ensureSets(for exerciseLog: ExerciseLog, in context: ModelContext) -> ExerciseContext {
        let prepared = exerciseContext(for: exerciseLog, in: context)
        ensureSets(for: exerciseLog, using: prepared, in: context)
        return prepared
    }

    @MainActor
    static func ensureSets(for exerciseLog: ExerciseLog, using prepared: ExerciseContext,
                           in context: ModelContext) {
        let target = max(exerciseLog.targetSets, 1)
        guard exerciseLog.sets.count < target else { return }
        let planned = ProgressionEngine.plannedSets(previous: prepared.previousSets, advice: prepared.advice,
                                                    targetSets: target, target: exerciseLog.repTarget)
        for index in exerciseLog.sets.count..<target {
            let set = SetLog(order: index)
            if index < planned.count { set.apply(planned[index]) }
            set.order = index
            context.insert(set)
            set.exercise = exerciseLog
        }
        try? context.save()
    }

    @MainActor
    @discardableResult
    static func addSet(to exerciseLog: ExerciseLog, kind: SetKind = .effective, in context: ModelContext) -> SetLog {
        let order = (exerciseLog.sets.map(\.order).max() ?? -1) + 1
        // Una serie nueva hereda el peso de la última con datos: es lo que se espera al añadirla.
        let last = exerciseLog.sortedSets.last { $0.weightKg != nil }
        let set = SetLog(order: order, kind: kind, weightKg: last?.weightKg,
                         restSeconds: last?.restSeconds)
        context.insert(set)
        set.exercise = exerciseLog
        try? context.save()
        return set
    }

    @MainActor
    static func removeSet(_ set: SetLog, in context: ModelContext) {
        // Los supervivientes se anotan ANTES de borrar: justo después del delete, la serie
        // borrada sigue en la relación hasta que se guarda, y renumerar contándola dejaba
        // los números empezando en 1 en vez de en 0.
        let survivors = (set.exercise?.sortedSets ?? []).filter { $0.id != set.id }
        set.exercise = nil
        context.delete(set)
        for (index, remaining) in survivors.enumerated() { remaining.order = index }
        try? context.save()
    }

    // MARK: Historial de un ejercicio

    /// Resúmenes de ese ejercicio en todas las sesiones con datos, de la más antigua a la más reciente.
    @MainActor
    static func history(exerciseID: String, limit: Int? = nil, in context: ModelContext) -> [ExerciseSessionSummary] {
        let descriptor = FetchDescriptor<ExerciseLog>(predicate: #Predicate { $0.exerciseID == exerciseID })
        let logs = (try? context.fetch(descriptor)) ?? []
        let summaries = logs.compactMap { log -> ExerciseSessionSummary? in
            guard let session = log.session else { return nil }
            let date = session.completedAt ?? session.finishedAt ?? session.weekStart
            return log.summary(on: date)
        }
        .sorted { $0.date < $1.date }
        guard let limit, summaries.count > limit else { return summaries }
        return Array(summaries.suffix(limit))
    }

    /// Series de la última sesión anterior con datos de ese ejercicio.
    @MainActor
    static func previousSets(exerciseID: String, before weekStart: Date, in context: ModelContext) -> [LoggedSet] {
        let descriptor = FetchDescriptor<ExerciseLog>(predicate: #Predicate { $0.exerciseID == exerciseID })
        let logs = (try? context.fetch(descriptor)) ?? []
        let candidates = logs.compactMap { log -> (date: Date, sets: [LoggedSet])? in
            guard let session = log.session, session.weekStart < weekStart, log.hasLoggedData else { return nil }
            return (session.weekStart, log.loggedSets)
        }
        return candidates.max { $0.date < $1.date }?.sets ?? []
    }

    /// Propuesta de progresión para un ejercicio de la sesión en curso.
    @MainActor
    static func advice(for exerciseLog: ExerciseLog, in context: ModelContext) -> ProgressionEngine.Advice {
        exerciseContext(for: exerciseLog, in: context).advice
    }

    // MARK: Rutina desde la biblioteca

    /// Añade a la rutina un ejercicio de la biblioteca, con sus series y repeticiones de partida.
    @MainActor
    static func addExercise(to sessionID: String, from info: ExerciseInfo, in context: ModelContext) {
        DataStore.addExercise(to: sessionID, name: info.name, sets: info.defaultSets,
                              repMin: info.defaultRepMin, repMax: info.defaultRepMax, in: context)
    }

    /// Sustituye un ejercicio por otro de la biblioteca MANTENIENDO sus series y repeticiones:
    /// el objetivo de la sesión no cambia, cambia el ejercicio. El historial del anterior se conserva
    /// y el nuevo empieza su propia progresión.
    @MainActor
    static func substitute(_ exercise: RoutineExercise, with info: ExerciseInfo, in context: ModelContext) {
        DataStore.substitute(exercise, withName: info.name, in: context)
    }

    // MARK: Récords

    @MainActor
    static func records(in context: ModelContext) -> [PersonalRecordEntry] {
        let descriptor = FetchDescriptor<PersonalRecordEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @MainActor
    static func previousBest(exerciseID: String, in context: ModelContext) -> [RecordKind: Double] {
        let descriptor = FetchDescriptor<PersonalRecordEntry>(predicate: #Predicate { $0.exerciseID == exerciseID })
        let entries = (try? context.fetch(descriptor)) ?? []
        return Dictionary(entries.map { ($0.kind, $0.value) }, uniquingKeysWith: max)
    }

    /// Revisa los récords de una sesión y guarda los que se hayan batido.
    /// - Returns: los récords nuevos (incluidos los primeros registros, marcados como tal).
    @MainActor
    @discardableResult
    static func updateRecords(from session: WorkoutSessionLog, in context: ModelContext) -> [RecordCandidate] {
        var out: [RecordCandidate] = []
        let date = session.completedAt ?? session.finishedAt ?? Date()

        for exerciseLog in session.exercises {
            guard let summary = exerciseLog.summary(on: date) else { continue }
            let best = previousBest(exerciseID: exerciseLog.exerciseID, in: context)
            let candidates = PersonalRecords.candidates(from: summary, exerciseName: exerciseLog.displayName,
                                                        previousBest: best)
            for candidate in candidates {
                let key = PersonalRecordEntry.makeKey(exerciseID: candidate.exerciseID, kind: candidate.kind)
                var descriptor = FetchDescriptor<PersonalRecordEntry>(predicate: #Predicate { $0.key == key })
                descriptor.fetchLimit = 1
                if let existing = try? context.fetch(descriptor).first {
                    existing.previousValue = existing.value
                    existing.value = candidate.value
                    existing.weightKg = candidate.weightKg
                    existing.reps = candidate.reps
                    existing.date = candidate.date
                    existing.exerciseName = candidate.exerciseName
                } else {
                    context.insert(PersonalRecordEntry(exerciseID: candidate.exerciseID,
                                                       exerciseName: candidate.exerciseName,
                                                       kind: candidate.kind, value: candidate.value,
                                                       weightKg: candidate.weightKg, reps: candidate.reps,
                                                       date: candidate.date, previousValue: candidate.previous))
                }
                out.append(candidate)
            }
        }
        try? context.save()
        return out
    }

    // MARK: Semana de descarga

    @MainActor
    static func trainingWeek(_ weekStart: Date, in context: ModelContext) -> TrainingWeek? {
        let key = DateUtils.dayKey(DateUtils.startOfWeek(weekStart))
        var descriptor = FetchDescriptor<TrainingWeek>(predicate: #Predicate { $0.weekKey == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @MainActor
    static func isDeloadWeek(_ weekStart: Date?, in context: ModelContext) -> Bool {
        guard let weekStart else { return false }
        return trainingWeek(weekStart, in: context)?.isDeload ?? false
    }

    @MainActor
    static func setDeload(_ isDeload: Bool, weekStart: Date, in context: ModelContext) {
        if let existing = trainingWeek(weekStart, in: context) {
            existing.isDeload = isDeload
        } else {
            context.insert(TrainingWeek(weekStart: weekStart, isDeload: isDeload))
        }
        try? context.save()
    }

    // MARK: Trabajo realizado (para volumen e informes)

    /// Todo el trabajo de fuerza apuntado entre dos fechas.
    @MainActor
    static func work(from start: Date, to end: Date, in context: ModelContext) -> [VolumeAnalytics.ExerciseWork] {
        let first = DateUtils.startOfWeek(start)
        // El periodo se acota por los dos lados: si no, pedir una semana de hace dos meses
        // se traía de la base de datos todas las sesiones desde entonces hasta hoy.
        let last = DateUtils.startOfWeek(end)
        let descriptor = FetchDescriptor<WorkoutSessionLog>(predicate: #Predicate { $0.weekStart >= first && $0.weekStart <= last })
        let sessions = (try? context.fetch(descriptor)) ?? []
        var out: [VolumeAnalytics.ExerciseWork] = []
        for session in sessions {
            let date = session.completedAt ?? session.finishedAt ?? session.weekStart
            guard date >= DateUtils.startOfDay(start), date <= endOfDay(end) else { continue }
            for exerciseLog in session.exercises {
                guard let summary = exerciseLog.summary(on: date) else { continue }
                out.append(VolumeAnalytics.ExerciseWork(summary: summary, name: exerciseLog.displayName))
            }
        }
        return out
    }

    static func endOfDay(_ date: Date) -> Date {
        DateUtils.startOfDay(date).addingTimeInterval(86_399)
    }

    /// Series que la rutina programa en una semana (todas las sesiones de fuerza).
    @MainActor
    static func programmedSetsPerWeek(in context: ModelContext) -> Int {
        let all = (try? context.fetch(FetchDescriptor<RoutineExercise>())) ?? []
        return all.reduce(0) { $0 + $1.sets }
    }

    // MARK: Recuperación

    @MainActor
    static func recoveryLog(for date: Date, in context: ModelContext) -> RecoveryLogEntry? {
        let key = DateUtils.dayKey(date)
        var descriptor = FetchDescriptor<RecoveryLogEntry>(predicate: #Predicate { $0.dayKey == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @MainActor
    static func fetchOrCreateRecovery(for date: Date, in context: ModelContext) -> RecoveryLogEntry {
        if let existing = recoveryLog(for: date, in: context) { return existing }
        let entry = RecoveryLogEntry(date: date)
        context.insert(entry)
        try? context.save()
        return entry
    }

    /// Entradas de recuperación de los últimos días, de la más reciente a la más antigua.
    @MainActor
    static func recentRecovery(days: Int, before date: Date = Date(), in context: ModelContext) -> [RecoveryEntry] {
        let start = DateUtils.calendar.date(byAdding: .day, value: -days, to: DateUtils.startOfDay(date)) ?? date
        let descriptor = FetchDescriptor<RecoveryLogEntry>(
            predicate: #Predicate { $0.date >= start && $0.date < date },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return ((try? context.fetch(descriptor)) ?? []).map(\.entry)
    }

    @MainActor
    static func recovery(from start: Date, to end: Date, in context: ModelContext) -> [RecoveryEntry] {
        let first = DateUtils.startOfDay(start)
        let last = endOfDay(end)
        let descriptor = FetchDescriptor<RecoveryLogEntry>(
            predicate: #Predicate { $0.date >= first && $0.date <= last },
            sortBy: [SortDescriptor(\.date)]
        )
        return ((try? context.fetch(descriptor)) ?? []).map(\.entry).filter { !$0.isEmpty }
    }

    // MARK: Suplementos

    @MainActor
    static func supplements(in context: ModelContext) -> [SupplementEntry] {
        let descriptor = FetchDescriptor<SupplementEntry>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    @MainActor
    static func addSupplement(from info: SupplementInfo, amount: Double, unit: DoseUnit,
                              dosesPerDay: Double = 1, hours: [Int] = [], in context: ModelContext) {
        context.insert(SupplementEntry(catalogID: info.id, name: info.name, ingredient: info.ingredient,
                                       amountPerDose: amount, unit: unit, dosesPerDay: dosesPerDay, hours: hours))
        try? context.save()
    }

    @MainActor
    static func remove(_ supplement: SupplementEntry, in context: ModelContext) {
        // Se borran también sus registros de toma, que si no quedarían huérfanos.
        let id = supplement.id
        let intakes = (try? context.fetch(FetchDescriptor<SupplementIntake>(predicate: #Predicate { $0.supplementID == id }))) ?? []
        intakes.forEach { context.delete($0) }
        context.delete(supplement)
        try? context.save()
    }

    @MainActor
    static func intake(for supplement: SupplementEntry, on date: Date, in context: ModelContext) -> SupplementIntake? {
        let key = SupplementIntake.makeKey(dayKey: DateUtils.dayKey(date), supplementID: supplement.id)
        var descriptor = FetchDescriptor<SupplementIntake>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @MainActor
    static func setIntake(_ doses: Double, for supplement: SupplementEntry, on date: Date, in context: ModelContext) {
        if let existing = intake(for: supplement, on: date, in: context) {
            if doses <= 0 {
                context.delete(existing)
            } else {
                existing.dosesTaken = doses
            }
        } else if doses > 0 {
            context.insert(SupplementIntake(date: date, supplementID: supplement.id, dosesTaken: doses))
        }
        try? context.save()
    }

    // MARK: Informes

    /// Reúne todo lo que hace falta para el informe de un periodo.
    @MainActor
    static func reportInput(range: ReportRange, endingAt date: Date = Date(), in context: ModelContext) -> ReportInput {
        reportInput(period: range.period(endingAt: date), in: context)
    }

    @MainActor
    static func reportInput(period: ReportPeriod, in context: ModelContext) -> ReportInput {
        var input = ReportInput(period: period)
        input.work = work(from: period.start, to: period.end, in: context)

        // Sesiones completadas dentro del periodo, acotadas por los dos lados.
        let firstWeek = DateUtils.startOfWeek(period.start)
        let lastWeek = DateUtils.startOfWeek(period.end)
        let sessionDescriptor = FetchDescriptor<WorkoutSessionLog>(
            predicate: #Predicate { $0.weekStart >= firstWeek && $0.weekStart <= lastWeek })
        let sessions = (try? context.fetch(sessionDescriptor)) ?? []
        let inPeriod = sessions.filter { session in
            let date = session.completedAt ?? session.finishedAt ?? session.weekStart
            return period.contains(date)
        }
        input.sessionsCompleted = inPeriod.filter(\.isCompleted).count
        let weeks = max(Double(period.dayCount) / 7, 0)
        input.sessionsScheduled = Int((Double(WeeklyRoutine.trainableSessions.count) * weeks).rounded())
        input.programmedSets = Int((Double(programmedSetsPerWeek(in: context)) * weeks).rounded())

        // Récords logrados dentro del periodo.
        input.records = records(in: context)
            .filter { period.contains($0.date) }
            .map { entry in
                RecordCandidate(kind: entry.kind, exerciseID: entry.exerciseID, exerciseName: entry.exerciseName,
                                value: entry.value, weightKg: entry.weightKg, reps: entry.reps,
                                date: entry.date, previous: entry.previousValue)
            }

        // Nutrición: suma por día de lo registrado.
        let periodStart = DateUtils.startOfDay(period.start)
        let periodEnd = endOfDay(period.end)
        let mealDescriptor = FetchDescriptor<MealRecord>(
            predicate: #Predicate { $0.date >= periodStart && $0.date <= periodEnd })
        let meals = ((try? context.fetch(mealDescriptor)) ?? []).filter { period.contains($0.date) }
        let byDay = Dictionary(grouping: meals, by: \.dayKey)
        input.nutritionDays = byDay.compactMap { key, records in
            guard let date = DateUtils.date(fromDayKey: key) else { return nil }
            let total = NutritionMath.sum(records.map(\.values))
            return ReportInput.NutritionDay(date: date, kcal: total.kcal, protein: total.protein,
                                            carbs: total.carbs, fat: total.fat)
        }
        .sorted { $0.date < $1.date }

        let settings = DataStore.settings(context)
        input.kcalTarget = settings.kcalTarget
        input.proteinTarget = settings.proteinTarget

        // Peso.
        let weightDescriptor = FetchDescriptor<WeightEntry>(
            predicate: #Predicate { $0.date >= periodStart && $0.date <= periodEnd })
        input.weights = ((try? context.fetch(weightDescriptor)) ?? []).map { WeightStats.Point(date: $0.date, kg: $0.weightKg) }

        input.recovery = recovery(from: period.start, to: period.end, in: context)

        // Carreras.
        let runDescriptor = FetchDescriptor<StravaActivityRecord>(
            predicate: #Predicate { $0.startDate >= periodStart && $0.startDate <= periodEnd })
        let runs = (try? context.fetch(runDescriptor)) ?? []
        input.runs = runs.count
        input.runKilometers = runs.reduce(0) { $0 + $1.distanceMeters } / 1000

        return input
    }

    @MainActor
    static func report(range: ReportRange, endingAt date: Date = Date(), in context: ModelContext) -> PeriodReport {
        ReportBuilder.build(reportInput(range: range, endingAt: date, in: context))
    }

    // MARK: Contexto para la IA

    /// Cuántos ejercicios como máximo viajan en el contexto de la IA.
    /// Se limita a propósito: menos texto, menos coste y menos datos fuera del teléfono.
    static let aiExerciseLimit = 15

    /// Monta lo que la IA puede ver. Solo lectura y a partir del mismo informe que ve el usuario.
    @MainActor
    static func aiContext(range: ReportRange, endingAt date: Date = Date(), in context: ModelContext) -> AIContext {
        let period = range.period(endingAt: date)
        let report = ReportBuilder.build(reportInput(period: period, in: context))
        let settings = DataStore.settings(context)
        let weight = DataStore.latestWeight(context)

        let profile: AIContext.Profile? = {
            guard settings.heightCm != nil || settings.age != nil || weight != nil else { return nil }
            return AIContext.Profile(
                sex: settings.sex?.label, age: settings.age, heightCm: settings.heightCm, weightKg: weight,
                activity: settings.activity.label, goal: settings.goal.label,
                kcalTarget: settings.kcalTarget, proteinTarget: settings.proteinTarget,
                carbsTarget: settings.carbsTarget, fatTarget: settings.fatTarget,
                automaticTargets: settings.autoTargets)
        }()

        // Ejercicios: los trabajados en el periodo primero, y luego los de la rutina con historial.
        let work = work(from: period.start, to: period.end, in: context)
        var seen = Set<String>()
        var ordered: [(id: String, name: String)] = []
        for item in work where seen.insert(item.exerciseID).inserted {
            ordered.append((item.exerciseID, item.name))
        }
        for exercise in (try? context.fetch(FetchDescriptor<RoutineExercise>())) ?? []
        where seen.insert(exercise.exerciseID).inserted {
            ordered.append((exercise.exerciseID, exercise.name))
        }

        var lines: [AIContext.Exercise] = []
        for entry in ordered {
            let history = history(exerciseID: entry.id, in: context)
            guard !history.isEmpty else { continue }
            let info = ExerciseCatalog.info(id: entry.id, name: entry.name)
            let target = ProgressionEngine.RepTarget(
                min: info?.defaultRepMin ?? 8, max: info?.defaultRepMax ?? 12)
            let advice = ProgressionEngine.advise(history: history, target: target, equipment: info?.equipment,
                                                  isDeloadWeek: isDeloadWeek(DateUtils.startOfWeek(date), in: context))
            let trend = StrengthTrend(summaries: history)
            let last = history.last
            lines.append(AIContext.Exercise(
                name: entry.name,
                muscle: info?.primary.label,
                lastTopSet: last?.topSetText,
                estimatedOneRepMax: last?.estimatedOneRepMax,
                oneRepMaxConfidence: last?.oneRepMaxConfidence?.label,
                sessionsLogged: history.count,
                trend: trend.verdict.label,
                changePercent: trend.changePercent,
                isStalled: ProgressionEngine.stallReport(history: history).isStalled,
                suggestedAction: advice.action.label,
                suggestedReason: advice.reason))
            if lines.count >= aiExerciseLimit { break }
        }

        return AIContext(report: report, profile: profile, exercises: lines,
                         isDeloadWeek: isDeloadWeek(DateUtils.startOfWeek(date), in: context))
    }
}

// MARK: - Ejercicios creados por el usuario

extension StrengthStore {
    @MainActor
    static func customExercises(in context: ModelContext) -> [CustomExercise] {
        let descriptor = FetchDescriptor<CustomExercise>(sortBy: [SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Mete los ejercicios del usuario en el catálogo. Hay que llamarlo al abrir la app y
    /// cada vez que se crea, cambia o borra uno: a partir de ahí cuentan en el volumen por músculo.
    @MainActor
    static func refreshCustomCatalog(in context: ModelContext) {
        ExerciseCatalog.useCustom(customExercises(in: context).map(\.info))
    }

    /// Crea un ejercicio del usuario. Devuelve nil si el nombre no vale (ya existe, está vacío…).
    @MainActor
    @discardableResult
    static func createCustomExercise(name: String, primary: MuscleGroup, secondary: [MuscleGroup],
                                     pattern: MovementPattern, equipment: Equipment, unilateral: Bool,
                                     sets: Int, repMin: Int, repMax: Int, note: String,
                                     in context: ModelContext) -> CustomExercise? {
        let mine = customExercises(in: context).map { (id: $0.id, name: $0.name) }
        guard CustomExerciseRules.validate(name: name, mine: mine) == nil else { return nil }
        let exercise = CustomExercise(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                      primary: primary, secondary: secondary.filter { $0 != primary },
                                      pattern: pattern, equipment: equipment, unilateral: unilateral,
                                      sets: sets, repMin: repMin, repMax: repMax,
                                      note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        context.insert(exercise)
        try? context.save()
        refreshCustomCatalog(in: context)
        return exercise
    }

    /// Guarda los cambios de un ejercicio del usuario. Al cambiarle el nombre, el anterior se
    /// queda como alias para que lo ya registrado siga contando.
    @MainActor
    static func updateCustomExercise(_ exercise: CustomExercise, name: String, primary: MuscleGroup,
                                     secondary: [MuscleGroup], pattern: MovementPattern,
                                     equipment: Equipment, unilateral: Bool, sets: Int,
                                     repMin: Int, repMax: Int, note: String,
                                     in context: ModelContext) {
        exercise.rename(to: name)
        exercise.primary = primary
        exercise.secondary = secondary.filter { $0 != primary }
        exercise.pattern = pattern
        exercise.equipment = equipment
        exercise.isUnilateral = unilateral
        exercise.defaultSets = sets
        exercise.defaultRepMin = repMin
        exercise.defaultRepMax = repMax
        exercise.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try? context.save()
        refreshCustomCatalog(in: context)
    }

    /// Borra la ficha. Lo registrado NO se borra: lo que pasa es que esas series dejan de
    /// repartirse por músculo (vuelven a contar como ejercicio sin clasificar).
    @MainActor
    static func deleteCustomExercise(_ exercise: CustomExercise, in context: ModelContext) {
        context.delete(exercise)
        try? context.save()
        refreshCustomCatalog(in: context)
    }

    /// Cuántas series tienes ya apuntadas con ese nombre (para avisar antes de borrarlo).
    @MainActor
    static func loggedSetCount(forExerciseNamed name: String, in context: ModelContext) -> Int {
        let normalized = ExerciseCatalog.normalize(name)
        let logs = (try? context.fetch(FetchDescriptor<ExerciseLog>())) ?? []
        return logs.filter { ExerciseCatalog.normalize($0.displayName) == normalized }
            .reduce(0) { $0 + $1.workSets }
    }
}

// MARK: - Rango por músculo

extension StrengthStore {
    /// Todo el trabajo registrado, desde el principio. Es lo que alimenta el mapa del cuerpo.
    @MainActor
    static func allWork(in context: ModelContext) -> [VolumeAnalytics.ExerciseWork] {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSessionLog>())) ?? []
        var out: [VolumeAnalytics.ExerciseWork] = []
        for session in sessions {
            let date = session.completedAt ?? session.finishedAt ?? session.weekStart
            for exerciseLog in session.exercises {
                guard let summary = exerciseLog.summary(on: date) else { continue }
                out.append(VolumeAnalytics.ExerciseWork(summary: summary, name: exerciseLog.displayName))
            }
        }
        return out
    }

    @MainActor
    static func muscleLevels(in context: ModelContext) -> [MuscleLevel.Status] {
        MuscleLevel.statuses(work: allWork(in: context))
    }
}
