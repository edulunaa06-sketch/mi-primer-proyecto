import Foundation
import SwiftData

/// Datos de seguimiento: pasos guardados por día, marcas del calendario y objetivo de pasos adaptativo.
extension DataStore {
    // MARK: Pasos

    /// Guarda (o actualiza) los pasos de un día. No baja un valor ya guardado de ese día:
    /// el sensor puede devolver menos pasos si se consulta en mitad de una actualización.
    @MainActor
    static func saveSteps(_ steps: Int, for date: Date, goal: Int, in context: ModelContext, save: Bool = true) {
        guard steps >= 0 else { return }
        let key = DateUtils.dayKey(date)
        var descriptor = FetchDescriptor<DailySteps>(predicate: #Predicate { $0.dayKey == key })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            guard steps > existing.steps else { return }
            existing.steps = steps
            existing.updatedAt = Date()
            if DateUtils.calendar.isDateInToday(date) { existing.goal = goal }
        } else {
            context.insert(DailySteps(date: date, steps: steps, goal: goal))
        }
        if save { try? context.save() }
    }

    /// Objetivo adaptativo: como mucho una vez al día, con la media de los 7 días anteriores a hoy.
    /// Devuelve el objetivo nuevo si ha cambiado.
    @MainActor
    @discardableResult
    static func updateAdaptiveStepGoal(_ context: ModelContext, today: Date = Date()) -> Int? {
        let s = settings(context)
        let todayKey = DateUtils.dayKey(today)
        guard s.stepGoalAdaptive, s.stepGoalAdjustedDayKey != todayKey else { return nil }
        let start = DateUtils.startOfDay(today)
        guard let from = DateUtils.calendar.date(byAdding: .day, value: -7, to: start) else { return nil }
        let descriptor = FetchDescriptor<DailySteps>(predicate: #Predicate { $0.date >= from && $0.date < start })
        let recent = ((try? context.fetch(descriptor)) ?? []).map(\.steps)
        guard let suggested = AdaptiveStepGoal.suggest(recentDailySteps: recent) else { return nil }
        s.stepGoalAdjustedDayKey = todayKey
        let changed = suggested != s.stepGoal
        s.stepGoal = suggested
        try? context.save()
        return changed ? suggested : nil
    }

    // MARK: Calendario

    /// Primer día que cuenta en el calendario: el primer uso de la app o la fecha de inicio, la anterior.
    @MainActor
    static func trackingStart(_ context: ModelContext) -> Date {
        let firstLaunch = UserDefaults.standard.object(forKey: firstLaunchKey) as? Date ?? Date()
        let configured = settings(context).trackingStartDate ?? firstLaunch
        return DateUtils.startOfDay(min(firstLaunch, configured))
    }

    /// Marca uno o varios días seguidos. Si la marca es la de por defecto de ese día (descanso los viernes,
    /// normal el resto) no se guarda nada: el día vuelve a su valor por defecto.
    @MainActor
    static func setMark(_ chosen: DayMark, from start: Date, through end: Date, in context: ModelContext) {
        var day = DateUtils.startOfDay(min(start, end))
        let last = DateUtils.startOfDay(max(start, end))
        var guardCount = 0
        while day <= last, guardCount < 400 {
            let key = DateUtils.dayKey(day)
            var descriptor = FetchDescriptor<DayMarkRecord>(predicate: #Predicate { $0.dayKey == key })
            descriptor.fetchLimit = 1
            let existing = try? context.fetch(descriptor).first
            let isDefault = chosen == DayMark.effective(explicit: nil, weekday: DateUtils.weekdayMondayBased(day))
            let mark: DayMark? = isDefault ? nil : chosen
            switch (mark, existing) {
            case (nil, let record?): context.delete(record)
            case (let m?, let record?): record.mark = m
            case (let m?, nil): context.insert(DayMarkRecord(date: day, mark: m))
            case (nil, nil): break
            }
            guard let next = DateUtils.calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            guardCount += 1
        }
        try? context.save()
    }
}

/// Foto de los datos necesarios para evaluar días (calendario, racha, resumen semanal y medallas).
/// Se construye con lo que las vistas ya tienen en sus @Query.
struct TrackingSnapshot {
    let today: Date
    let trackingStart: Date
    let currentStepGoal: Int
    private let mealsByDay: [String: Int]
    private let completedLogKeys: Set<String>
    private let stepsByDay: [String: DailySteps]
    private let marksByDay: [String: DayMark]

    init(meals: [MealRecord], logs: [WorkoutSessionLog], steps: [DailySteps], marks: [DayMarkRecord],
         stepGoal: Int, trackingStart: Date, today: Date = Date()) {
        self.today = today
        self.trackingStart = trackingStart
        self.currentStepGoal = stepGoal
        var meals2: [String: Set<String>] = [:]
        for m in meals { meals2[m.dayKey, default: []].insert(m.mealTypeRaw) }
        mealsByDay = meals2.mapValues(\.count)
        completedLogKeys = Set(logs.filter(\.isCompleted).map(\.key))
        stepsByDay = Dictionary(steps.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, b in a.steps >= b.steps ? a : b })
        marksByDay = Dictionary(marks.map { ($0.dayKey, $0.mark) }, uniquingKeysWith: { a, _ in a })
    }

    func explicitMark(_ date: Date) -> DayMark? { marksByDay[DateUtils.dayKey(date)] }

    func steps(_ date: Date) -> Int? { stepsByDay[DateUtils.dayKey(date)]?.steps }

    func input(for date: Date) -> DayInput {
        let key = DateUtils.dayKey(date)
        let scheduled = WeeklyRoutine.sessions(forWeekday: DateUtils.weekdayMondayBased(date)).filter { $0.kind != .rest }
        let weekStart = DateUtils.startOfWeek(date)
        let completed = scheduled.filter {
            completedLogKeys.contains(WorkoutSessionLog.makeKey(weekStart: weekStart, sessionID: $0.id))
        }
        let stepRecord = stepsByDay[key]
        return DayInput(date: DateUtils.startOfDay(date),
                        mealsCompleted: mealsByDay[key] ?? 0,
                        sessionsScheduled: scheduled.count,
                        sessionsCompleted: completed.count,
                        steps: stepRecord?.steps,
                        stepGoal: stepRecord?.goal ?? currentStepGoal,
                        explicitMark: marksByDay[key])
    }

    func outcome(for date: Date) -> DayOutcome {
        DayEvaluator.outcome(input(for: date), today: today, trackingStart: trackingStart)
    }

    /// Días desde `start` hasta `end` (ambos incluidos).
    func days(from start: Date, through end: Date) -> [Date] {
        var result: [Date] = []
        var day = DateUtils.startOfDay(start)
        let last = DateUtils.startOfDay(end)
        while day <= last, result.count < 3700 {
            result.append(day)
            guard let next = DateUtils.calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// Como mucho se miran los últimos 400 días: así calcular la racha es rápido aunque lleves años.
    static let streakWindowDays = 400

    /// Racha actual y mejor racha desde el primer día con datos o marcas hasta hoy (máx. 400 días).
    var streak: Streak.Result {
        let earliestMark = marksByDay.keys.compactMap(DateUtils.date(fromDayKey:)).min()
        let window = DateUtils.calendar.date(byAdding: .day, value: -Self.streakWindowDays, to: DateUtils.startOfDay(today)) ?? today
        let start = max(min(trackingStart, earliestMark ?? trackingStart), window)
        return Streak.compute(days(from: start, through: today).map(outcome(for:)))
    }

    var allDailySteps: [(date: Date, steps: Int)] {
        stepsByDay.values.map { (date: $0.date, steps: $0.steps) }
    }
}
