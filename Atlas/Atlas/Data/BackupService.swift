import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Exporta todos los datos a un archivo y los importa de vuelta (reemplazando los actuales).
enum BackupService {
    // MARK: Exportar

    @MainActor
    static func makeBackup(_ context: ModelContext, now: Date = Date()) throws -> BackupFile {
        let s = DataStore.settings(context)
        func all<T: PersistentModel>(_ type: T.Type) throws -> [T] { try context.fetch(FetchDescriptor<T>()) }

        let settings = BackupFile.Settings(
            kcalTarget: s.kcalTarget, proteinTarget: s.proteinTarget, carbsTarget: s.carbsTarget, fatTarget: s.fatTarget,
            stepGoal: s.stepGoal, trackingStartDate: s.trackingStartDate, onboardingCompleted: s.onboardingCompleted,
            creatineReminderEnabled: s.creatineReminderEnabled, creatineHour: s.creatineHour, creatineMinute: s.creatineMinute,
            photoReminderEnabled: s.photoReminderEnabled, photoReminderHour: s.photoReminderHour, defaultPlanID: s.defaultPlanID,
            stravaClientID: s.stravaClientID, stravaBackendURL: s.stravaBackendURL, heightCm: s.heightCm, age: s.age,
            sexRaw: s.sexRaw, activityRaw: s.activityRaw, goalRaw: s.goalRaw, autoTargets: s.autoTargets,
            stepGoalAdaptive: s.stepGoalAdaptive, stepGoalAdjustedDayKey: s.stepGoalAdjustedDayKey,
            stepReminderEnabled: s.stepReminderEnabled, stepReminderFromMinutes: s.stepReminderFromMinutes,
            stepReminderToMinutes: s.stepReminderToMinutes, weightReminderEnabled: s.weightReminderEnabled,
            weightReminderFromMinutes: s.weightReminderFromMinutes, weightReminderToMinutes: s.weightReminderToMinutes,
            kcalMargin: s.kcalMargin)

        var file = BackupFile(createdAt: now,
                              appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
                              settings: settings)
        file.weights = try all(WeightEntry.self).map {
            BackupFile.Weight(id: $0.id, date: $0.date, weightKg: $0.weightKg, waistCm: $0.waistCm, note: $0.note)
        }
        file.routine = try all(RoutineExercise.self).map {
            BackupFile.RoutineExercise(exerciseID: $0.exerciseID, sessionID: $0.sessionID, name: $0.name, sets: $0.sets,
                  repMin: $0.repMin, repMax: $0.repMax, order: $0.order)
        }
        file.sessionTitles = try all(SessionTitle.self).map { BackupFile.SessionTitle(sessionID: $0.sessionID, title: $0.title) }
        file.sessionLogs = try all(WorkoutSessionLog.self).map { log in
            BackupFile.SessionLog(weekStart: log.weekStart, sessionID: log.sessionID, isCompleted: log.isCompleted, completedAt: log.completedAt,
                  notes: log.notes, lastModified: log.lastModified,
                  exercises: log.sortedExercises.map { ex in
                      BackupFile.ExerciseLog(exerciseID: ex.exerciseID, order: ex.order, isCompleted: ex.isCompleted, name: ex.name,
                            targetSets: ex.targetSets, repRange: ex.repRange,
                            sets: ex.sortedSets.map { set in
                                BackupFile.SetEntry(order: set.order, kindRaw: set.kindRaw, weightKg: set.weightKg,
                                      reps: set.reps, rir: set.rir, rpe: set.rpe, restSeconds: set.restSeconds,
                                      isCompleted: set.isCompleted, note: set.note, completedAt: set.completedAt)
                            },
                            note: ex.note, hasDiscomfort: ex.hasDiscomfort)
                  },
                  accumulatedSeconds: log.accumulatedSeconds, finishedAt: log.finishedAt)
        }
        file.records = try all(PersonalRecordEntry.self).map {
            BackupFile.Record(exerciseID: $0.exerciseID, exerciseName: $0.exerciseName, kindRaw: $0.kindRaw,
                  value: $0.value, weightKg: $0.weightKg, reps: $0.reps, date: $0.date, previousValue: $0.previousValue)
        }
        file.recovery = try all(RecoveryLogEntry.self).map {
            BackupFile.Recovery(dayKey: $0.dayKey, date: $0.date, sleepHours: $0.sleepHours, sleepQuality: $0.sleepQuality,
                  energy: $0.energy, fatigue: $0.fatigue, stress: $0.stress, soreness: $0.soreness,
                  hasDiscomfort: $0.hasDiscomfort, note: $0.note)
        }
        file.supplements = try all(SupplementEntry.self).map {
            BackupFile.Supplement(id: $0.id, catalogID: $0.catalogID, name: $0.name, ingredient: $0.ingredient,
                  amountPerDose: $0.amountPerDose, unitRaw: $0.unitRaw, dosesPerDay: $0.dosesPerDay,
                  hoursRaw: $0.hoursRaw, packagePrice: $0.packagePrice, packageDays: $0.packageDays,
                  isActive: $0.isActive, note: $0.note, createdAt: $0.createdAt)
        }
        file.supplementIntakes = try all(SupplementIntake.self).map {
            BackupFile.SupplementTaken(dayKey: $0.dayKey, date: $0.date, supplementID: $0.supplementID, dosesTaken: $0.dosesTaken)
        }
        file.trainingWeeks = try all(TrainingWeek.self).map {
            BackupFile.Week(weekKey: $0.weekKey, weekStart: $0.weekStart, isDeload: $0.isDeload, note: $0.note)
        }
        file.foods = try all(FoodItem.self).map {
            BackupFile.Food(id: $0.id, seedKey: $0.seedKey, name: $0.name, kcalPer100: $0.kcalPer100, proteinPer100: $0.proteinPer100,
                  carbsPer100: $0.carbsPer100, fatPer100: $0.fatPer100, macrosKnown: $0.macrosKnown, basisRaw: $0.basisRaw,
                  isProvisional: $0.isProvisional, isUserEdited: $0.isUserEdited, sourceNote: $0.sourceNote)
        }
        file.plans = try all(MenuPlan.self).map { plan in
            BackupFile.Plan(id: plan.id, number: plan.number, name: plan.name, note: plan.note, isExample: plan.isExample, isLibrary: plan.isLibrary,
                  meals: plan.sortedMeals.map { meal in
                      BackupFile.Meal(mealTypeRaw: meal.mealTypeRaw,
                            items: meal.sortedItems.map { BackupFile.MealItem(grams: $0.grams, order: $0.order, foodID: $0.food?.id) })
                  })
        }
        file.mealRecords = try all(MealRecord.self).map {
            BackupFile.MealRecord(dayKey: $0.dayKey, date: $0.date, mealTypeRaw: $0.mealTypeRaw, planName: $0.planName,
                  kcal: $0.kcal, protein: $0.protein, carbs: $0.carbs, fat: $0.fat, completedAt: $0.completedAt)
        }
        file.daySelections = try all(DayPlanSelection.self).map { BackupFile.DaySelection(dayKey: $0.dayKey, planID: $0.planID) }
        file.dayChoices = try all(DayMealChoice.self).map {
            BackupFile.DayChoice(dayKey: $0.dayKey, mealTypeRaw: $0.mealTypeRaw, planID: $0.planID, factor: $0.factor,
                                 isUserChoice: $0.isUserChoice)
        }
        file.customItems = try all(CustomMealItem.self).map {
            BackupFile.CustomItem(dayKey: $0.dayKey, mealTypeRaw: $0.mealTypeRaw, name: $0.name, grams: $0.grams, kcalPer100: $0.kcalPer100,
                  proteinPer100: $0.proteinPer100, carbsPer100: $0.carbsPer100, fatPer100: $0.fatPer100,
                  sourceRaw: $0.sourceRaw, order: $0.order, createdAt: $0.createdAt)
        }
        file.photos = try all(ProgressPhoto.self).map {
            BackupFile.Photo(year: $0.year, month: $0.month, viewRaw: $0.viewRaw, fileName: $0.fileName,
                  createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                  imageData: try? Data(contentsOf: PhotoStorage.url(for: $0.fileName)))
        }
        file.runs = try all(StravaActivityRecord.self).map {
            BackupFile.Run(stravaID: $0.stravaID, name: $0.name, sportType: $0.sportType, startDate: $0.startDate,
                  distanceMeters: $0.distanceMeters, movingTimeSeconds: $0.movingTimeSeconds,
                  elapsedTimeSeconds: $0.elapsedTimeSeconds, elevationGainMeters: $0.elevationGainMeters, importedAt: $0.importedAt)
        }
        file.dailySteps = try all(DailySteps.self).map { BackupFile.DaySteps(dayKey: $0.dayKey, date: $0.date, steps: $0.steps, goal: $0.goal) }
        file.dayMarks = try all(DayMarkRecord.self).map { BackupFile.DayMarkEntry(dayKey: $0.dayKey, date: $0.date, markRaw: $0.markRaw) }
        return file
    }

    // MARK: Importar

    /// Reemplaza TODOS los datos por los de la copia. Las fotos se reescriben en el almacenamiento de la app.
    @MainActor
    static func restore(_ file: BackupFile, into context: ModelContext) throws {
        try deleteAll(context)

        // Ajustes: se reutiliza el registro existente.
        let s = DataStore.settings(context)
        let b = file.settings
        s.kcalTarget = b.kcalTarget; s.proteinTarget = b.proteinTarget; s.carbsTarget = b.carbsTarget; s.fatTarget = b.fatTarget
        if let margin = b.kcalMargin { s.kcalMargin = margin }
        s.stepGoal = b.stepGoal; s.trackingStartDate = b.trackingStartDate; s.onboardingCompleted = b.onboardingCompleted
        s.creatineReminderEnabled = b.creatineReminderEnabled; s.creatineHour = b.creatineHour; s.creatineMinute = b.creatineMinute
        s.photoReminderEnabled = b.photoReminderEnabled; s.photoReminderHour = b.photoReminderHour; s.defaultPlanID = b.defaultPlanID
        s.stravaClientID = b.stravaClientID; s.stravaBackendURL = b.stravaBackendURL
        s.heightCm = b.heightCm; s.age = b.age; s.sexRaw = b.sexRaw; s.activityRaw = b.activityRaw; s.goalRaw = b.goalRaw
        s.autoTargets = b.autoTargets; s.stepGoalAdaptive = b.stepGoalAdaptive; s.stepGoalAdjustedDayKey = b.stepGoalAdjustedDayKey
        s.stepReminderEnabled = b.stepReminderEnabled; s.stepReminderFromMinutes = b.stepReminderFromMinutes
        s.stepReminderToMinutes = b.stepReminderToMinutes; s.weightReminderEnabled = b.weightReminderEnabled
        s.weightReminderFromMinutes = b.weightReminderFromMinutes; s.weightReminderToMinutes = b.weightReminderToMinutes

        for w in file.weights {
            let entry = WeightEntry(date: w.date, weightKg: w.weightKg, waistCm: w.waistCm, note: w.note)
            entry.id = w.id
            context.insert(entry)
        }
        for r in file.routine {
            context.insert(RoutineExercise(exerciseID: r.exerciseID, sessionID: r.sessionID, name: r.name,
                                           sets: r.sets, repMin: r.repMin, repMax: r.repMax, order: r.order))
        }
        for t in file.sessionTitles { context.insert(SessionTitle(sessionID: t.sessionID, title: t.title)) }
        for l in file.sessionLogs {
            let log = WorkoutSessionLog(weekStart: l.weekStart, sessionID: l.sessionID)
            log.isCompleted = l.isCompleted
            log.completedAt = l.completedAt
            log.notes = l.notes
            log.lastModified = l.lastModified
            log.accumulatedSeconds = l.accumulatedSeconds ?? 0
            log.finishedAt = l.finishedAt
            context.insert(log)
            for e in l.exercises {
                let ex = ExerciseLog(exerciseID: e.exerciseID, order: e.order)
                ex.isCompleted = e.isCompleted
                ex.name = e.name
                ex.targetSets = e.targetSets
                ex.repRange = e.repRange
                ex.note = e.note ?? ""
                ex.hasDiscomfort = e.hasDiscomfort ?? false
                context.insert(ex)
                ex.session = log
                for entry in e.sets ?? [] {
                    let set = SetLog(order: entry.order, kind: SetKind(rawValue: entry.kindRaw) ?? .effective)
                    set.weightKg = entry.weightKg
                    set.reps = entry.reps
                    set.rir = entry.rir
                    set.rpe = entry.rpe
                    set.restSeconds = entry.restSeconds
                    set.isCompleted = entry.isCompleted
                    set.note = entry.note
                    set.completedAt = entry.completedAt
                    context.insert(set)
                    set.exercise = ex
                }
            }
        }
        for r in file.records ?? [] {
            context.insert(PersonalRecordEntry(exerciseID: r.exerciseID, exerciseName: r.exerciseName,
                                               kind: RecordKind(rawValue: r.kindRaw) ?? .topWeight, value: r.value,
                                               weightKg: r.weightKg, reps: r.reps, date: r.date,
                                               previousValue: r.previousValue))
        }
        for r in file.recovery ?? [] {
            let entry = RecoveryLogEntry(date: r.date)
            entry.dayKey = r.dayKey
            entry.sleepHours = r.sleepHours
            entry.sleepQuality = r.sleepQuality
            entry.energy = r.energy
            entry.fatigue = r.fatigue
            entry.stress = r.stress
            entry.soreness = r.soreness
            entry.hasDiscomfort = r.hasDiscomfort
            entry.note = r.note
            context.insert(entry)
        }
        // Ojo: `s` ya es el registro de ajustes en esta función, así que aquí se llama `saved`.
        for saved in file.supplements ?? [] {
            let item = SupplementEntry(catalogID: saved.catalogID, name: saved.name, ingredient: saved.ingredient,
                                       amountPerDose: saved.amountPerDose, unit: DoseUnit(rawValue: saved.unitRaw) ?? .gram,
                                       dosesPerDay: saved.dosesPerDay)
            item.id = saved.id
            item.hoursRaw = saved.hoursRaw
            item.packagePrice = saved.packagePrice
            item.packageDays = saved.packageDays
            item.isActive = saved.isActive
            item.note = saved.note
            item.createdAt = saved.createdAt
            context.insert(item)
        }
        for i in file.supplementIntakes ?? [] {
            let intake = SupplementIntake(date: i.date, supplementID: i.supplementID, dosesTaken: i.dosesTaken)
            intake.dayKey = i.dayKey
            context.insert(intake)
        }
        for w in file.trainingWeeks ?? [] {
            let week = TrainingWeek(weekStart: w.weekStart, isDeload: w.isDeload, note: w.note)
            week.weekKey = w.weekKey
            context.insert(week)
        }
        var foodsByID: [UUID: FoodItem] = [:]
        for f in file.foods {
            let food = FoodItem(name: f.name,
                                per100: NutritionValues(kcal: f.kcalPer100, protein: f.proteinPer100, carbs: f.carbsPer100, fat: f.fatPer100),
                                basis: WeightBasis(rawValue: f.basisRaw) ?? .raw, macrosKnown: f.macrosKnown,
                                isProvisional: f.isProvisional, sourceNote: f.sourceNote, seedKey: f.seedKey)
            food.id = f.id
            food.isUserEdited = f.isUserEdited
            context.insert(food)
            foodsByID[f.id] = food
        }
        for p in file.plans {
            let plan = MenuPlan(number: p.number, name: p.name, note: p.note, isExample: p.isExample)
            plan.id = p.id
            plan.isLibrary = p.isLibrary
            context.insert(plan)
            for m in p.meals {
                guard let type = MealType(rawValue: m.mealTypeRaw) else { continue }
                let template = MealTemplate(mealType: type)
                context.insert(template)
                template.plan = plan
                for i in m.items {
                    let item = MealItem(grams: i.grams, order: i.order, food: i.foodID.flatMap { foodsByID[$0] })
                    context.insert(item)
                    item.meal = template
                }
            }
        }
        for r in file.mealRecords {
            guard let type = MealType(rawValue: r.mealTypeRaw) else { continue }
            let record = MealRecord(date: r.date, mealType: type, planName: r.planName,
                                    values: NutritionValues(kcal: r.kcal, protein: r.protein, carbs: r.carbs, fat: r.fat))
            record.dayKey = r.dayKey
            record.completedAt = r.completedAt
            context.insert(record)
        }
        for d in file.daySelections { context.insert(DayPlanSelection(dayKey: d.dayKey, planID: d.planID)) }
        for c in file.dayChoices {
            guard let type = MealType(rawValue: c.mealTypeRaw) else { continue }
            context.insert(DayMealChoice(dayKey: c.dayKey, mealType: type, planID: c.planID, factor: c.factor,
                                         isUserChoice: c.isUserChoice ?? true))
        }
        for c in file.customItems {
            guard let type = MealType(rawValue: c.mealTypeRaw) else { continue }
            let item = CustomMealItem(dayKey: c.dayKey, mealType: type, name: c.name, grams: c.grams,
                                      per100: NutritionValues(kcal: c.kcalPer100, protein: c.proteinPer100, carbs: c.carbsPer100, fat: c.fatPer100),
                                      source: CustomItemSource(rawValue: c.sourceRaw) ?? .manual, order: c.order)
            item.createdAt = c.createdAt
            context.insert(item)
        }
        for p in file.photos {
            guard let data = p.imageData, let view = PhotoView(rawValue: p.viewRaw) else { continue }
            let name = p.fileName.isEmpty || p.fileName.contains("/") ? "\(UUID().uuidString).jpg" : p.fileName
            try data.write(to: PhotoStorage.url(for: name), options: [.atomic, .completeFileProtection])
            let photo = ProgressPhoto(year: p.year, month: p.month, view: view, fileName: name)
            photo.createdAt = p.createdAt
            photo.updatedAt = p.updatedAt
            context.insert(photo)
        }
        for r in file.runs {
            let run = StravaActivityRecord(stravaID: r.stravaID, name: r.name, sportType: r.sportType, startDate: r.startDate,
                                           distanceMeters: r.distanceMeters, movingTimeSeconds: r.movingTimeSeconds,
                                           elapsedTimeSeconds: r.elapsedTimeSeconds, elevationGainMeters: r.elevationGainMeters)
            run.importedAt = r.importedAt
            context.insert(run)
        }
        for d in file.dailySteps {
            let day = DailySteps(date: d.date, steps: d.steps, goal: d.goal)
            day.dayKey = d.dayKey
            context.insert(day)
        }
        for m in file.dayMarks {
            let mark = DayMarkRecord(date: m.date, mark: DayMark(rawValue: m.markRaw) ?? .normal)
            mark.dayKey = m.dayKey
            context.insert(mark)
        }
        try context.save()
    }

    /// Borra todos los datos (menos el registro de ajustes, que se sobrescribe) y los archivos de fotos.
    @MainActor
    private static func deleteAll(_ context: ModelContext) throws {
        func wipe<T: PersistentModel>(_ type: T.Type) throws {
            for item in try context.fetch(FetchDescriptor<T>()) { context.delete(item) }
        }
        try wipe(SetLog.self)
        try wipe(ExerciseLog.self)
        try wipe(WorkoutSessionLog.self)
        try wipe(PersonalRecordEntry.self)
        try wipe(RecoveryLogEntry.self)
        try wipe(SupplementIntake.self)
        try wipe(SupplementEntry.self)
        try wipe(TrainingWeek.self)
        try wipe(MealItem.self)
        try wipe(MealTemplate.self)
        try wipe(MenuPlan.self)
        try wipe(FoodItem.self)
        try wipe(WeightEntry.self)
        try wipe(RoutineExercise.self)
        try wipe(SessionTitle.self)
        try wipe(MealRecord.self)
        try wipe(DayPlanSelection.self)
        try wipe(DayMealChoice.self)
        try wipe(CustomMealItem.self)
        try wipe(ProgressPhoto.self)
        try wipe(StravaActivityRecord.self)
        try wipe(DailySteps.self)
        try wipe(DayMarkRecord.self)
        try context.save()
        let files = (try? FileManager.default.contentsOfDirectory(at: PhotoStorage.directory, includingPropertiesForKeys: nil)) ?? []
        for f in files { try? FileManager.default.removeItem(at: f) }
    }
}

/// Documento para «Guardar en Archivos» (exportar) con el JSON de la copia.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
