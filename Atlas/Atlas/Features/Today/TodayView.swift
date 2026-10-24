import SwiftData
import SwiftUI

/// Hoy: todo lo que importa del día en una pantalla. Calorías y macros, el entreno que toca,
/// pasos, agua, peso de tendencia, constancia de la semana y un consejo del coach.
struct TodayView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]
    @Query private var todayEntries: [FoodEntry]
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]
    @Query(filter: #Predicate<Workout> { $0.finishedAt != nil }, sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @Query(sort: \WeightLog.date) private var weights: [WeightLog]
    @Query private var waterToday: [WaterLog]

    private let todayKey: String

    init() {
        let key = DateUtils.dayKey(Date())
        todayKey = key
        _todayEntries = Query(filter: #Predicate<FoodEntry> { $0.dayKey == key })
        _waterToday = Query(filter: #Predicate<WaterLog> { $0.dayKey == key })
    }

    private var profile: Profile? { profiles.first }
    private var eaten: NutritionValues { NutritionMath.sum(todayEntries.map(\.values)) }
    private var todayTemplates: [WorkoutTemplate] { templates.filter { $0.weekday == DateUtils.weekdayMondayBased(Date()) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    CaloriesHero(eaten: eaten, targets: profile?.targets ?? .zero, margin: profile?.kcalMargin ?? 100) {
                        app.tab = .food
                    }
                    todayTraining
                    HStack(spacing: 12) {
                        StepsTile(goal: profile?.stepGoal ?? 8000)
                        WaterTile(ml: waterToday.first?.ml ?? 0, goal: profile?.waterGoalMl ?? 2500) {
                            let w = Store.water(todayKey, in: context)
                            w.ml += 250
                            try? context.save()
                            DS.haptic(.light)
                        }
                    }
                    WeightTile(weights: weights) { app.showWeight = true }
                    WeekStrip(templates: templates, workouts: workouts)
                    CoachTip(eaten: eaten, targets: profile?.targets ?? .zero, workouts: workouts)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .atlasScreen()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_ES"))).uppercased())
                    .font(.system(size: 11, weight: .bold).width(.expanded)).tracking(1.2).foregroundStyle(DS.text3)
                Text(greeting).font(.display(26)).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer()
            Button { app.showProfile = true } label: {
                Text(initials)
                    .font(.system(size: 15, weight: .heavy))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(DS.brandDiagonal))
                    .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Perfil y ajustes")
            .accessibilityIdentifier("profile.button")
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        let base = Greeting.text(hour: DateUtils.calendar.component(.hour, from: Date()))
        let name = profile?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? base : "\(base), \(name)"
    }

    private var initials: String {
        let name = profile?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "A" : String(name.prefix(1)).uppercased()
    }

    @ViewBuilder
    private var todayTraining: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Entreno de hoy", trailing: "Semana", action: { app.tab = .train })
            if todayTemplates.isEmpty {
                Text("Hoy no tienes nada planificado. Puedes hacer un entreno libre con el «+».")
                    .font(.footnote).foregroundStyle(DS.text2)
            }
            ForEach(todayTemplates) { t in
                TodaySessionRow(template: t, done: Store.doneThisWeek(t, workouts: workouts).flatMap { w in
                    DateUtils.calendar.isDateInToday(w.startedAt) ? w : nil
                })
            }
        }
        .glass()
    }
}

/// El anillo grande de calorías con los macros.
struct CaloriesHero: View {
    let eaten: NutritionValues
    let targets: NutritionValues
    let margin: Double
    let onTap: () -> Void

    var body: some View {
        let status = CalorieStatus.evaluate(consumed: eaten.kcal, target: targets.kcal, margin: margin)
        let left = targets.kcal - eaten.kcal
        Button(action: onTap) {
            VStack(spacing: 18) {
                HStack(spacing: 20) {
                    ZStack {
                        Ring(progress: targets.kcal > 0 ? eaten.kcal / targets.kcal : 0, lineWidth: 16, style: DS.color(status))
                        VStack(spacing: 0) {
                            Text(NumberFormat.integer(abs(left)))
                                .font(.number(30, .heavy))
                                .contentTransition(.numericText())
                                .accessibilityIdentifier("kcal.left")
                            Text(left >= 0 ? "kcal libres" : "kcal de más")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.text2)
                        }
                    }
                    .frame(width: 142, height: 142)
                    VStack(alignment: .leading, spacing: 12) {
                        figure("Comido", eaten.kcal, DS.text)
                        figure("Objetivo", targets.kcal, DS.text2)
                        Label(status.label, systemImage: statusSymbol(status))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(DS.color(status))
                            .accessibilityIdentifier("kcal.status")
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 14) {
                    MacroBar(name: "Proteína", value: eaten.protein, target: targets.protein, color: DS.protein)
                    MacroBar(name: "Hidratos", value: eaten.carbs, target: targets.carbs, color: DS.carbs)
                    MacroBar(name: "Grasa", value: eaten.fat, target: targets.fat, color: DS.fat)
                }
            }
            .glass(padding: 18)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.35), value: eaten.kcal)
    }

    private func figure(_ title: String, _ v: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased()).font(.system(size: 10, weight: .heavy).width(.expanded)).tracking(1).foregroundStyle(DS.text3)
            Text(NumberFormat.integer(v)).font(.number(22)).foregroundStyle(color).contentTransition(.numericText())
        }
    }

    private func statusSymbol(_ s: CalorieStatus) -> String {
        switch s {
        case .plenty: return "battery.75percent"
        case .approaching: return "scope"
        case .onTarget: return "checkmark.seal.fill"
        case .over: return "exclamationmark.circle.fill"
        }
    }
}

struct TodaySessionRow: View {
    let template: WorkoutTemplate
    let done: Workout?
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(done != nil ? AnyShapeStyle(DS.good) : AnyShapeStyle(DS.brandDiagonal))
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.surfaceHi))
            VStack(alignment: .leading, spacing: 3) {
                Text(template.name).font(.system(size: 17, weight: .bold)).lineLimit(1)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(DS.text2).lineLimit(2)
            }
            Spacer(minLength: 0)
            if let done {
                VStack(spacing: 2) {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(DS.good)
                    if done.volume > 0 {
                        Text("\(NumberFormat.integer(done.volume)) kg").font(.system(size: 10, weight: .bold)).foregroundStyle(DS.text2)
                    }
                }
                .accessibilityLabel("Hecho")
            } else if template.kind == .strength {
                Button("Empezar") {
                    DS.haptic(.medium)
                    app.liveWorkout = Store.startWorkout(from: template, in: context)
                }
                .buttonStyle(.primaryCompact)
                .accessibilityIdentifier("today.start")
            } else if template.kind == .run {
                Button("Registrar") { app.runTemplate = RunRequest(template: template) }
                    .buttonStyle(.secondaryCompact)
            }
        }
    }

    private var symbol: String {
        switch template.kind {
        case .strength: return "dumbbell.fill"
        case .run: return "figure.run"
        case .rest: return "moon.zzz.fill"
        }
    }

    private var subtitle: String {
        switch template.kind {
        case .strength:
            let ex = template.sortedExercises
            let minutes = WorkoutMath.estimatedMinutes(ex.map { (sets: $0.sets, repRange: $0.repRange) })
            return "\(ex.count) ejercicios · ~\(minutes) min"
        case .run: return template.detail
        case .rest: return "Recupera: duerme bien, camina y come tus proteínas."
        }
    }
}

struct StepsTile: View {
    let goal: Int
    @Environment(StepCounter.self) private var steps

    var body: some View {
        let n = steps.todaySteps
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "shoeprints.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(DS.good)
                Spacer()
                Ring(progress: n.map { Double($0) / Double(max(goal, 1)) } ?? 0, lineWidth: 5, style: DS.good)
                    .frame(width: 26, height: 26)
            }
            Text(n.map { NumberFormat.integer($0) } ?? "—").font(.number(24)).contentTransition(.numericText())
                .accessibilityIdentifier("steps.today")
            Text(steps.state == .denied ? "Sin permiso de movimiento" : "de \(NumberFormat.integer(goal)) pasos")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(DS.text2).lineLimit(1).minimumScaleFactor(0.8)
        }
        .glass(padding: 14)
        .onAppear { steps.start() }
    }
}

struct WaterTile: View {
    let ml: Int
    let goal: Int
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "drop.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(DS.water)
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .heavy))
                        .frame(width: 26, height: 26).background(Circle().fill(DS.water.opacity(0.25)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Beber 250 ml")
                .accessibilityIdentifier("water.add")
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.2f", Double(ml) / 1000).replacingOccurrences(of: ".", with: ","))
                    .font(.number(24)).contentTransition(.numericText())
                Text("L").font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.text3)
            }
            .accessibilityIdentifier("water.today")
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.water.opacity(0.15))
                    Capsule().fill(DS.water).frame(width: geo.size.width * min(Double(ml) / Double(max(goal, 1)), 1))
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: ml)
                }
            }
            .frame(height: 6)
        }
        .glass(padding: 14)
    }
}

struct WeightTile: View {
    let weights: [WeightLog]
    let onLog: () -> Void

    var body: some View {
        let points = weights.map { WeightTrend.Point(date: $0.date, kg: $0.kg) }
        let trend = WeightTrend.smoothed(points)
        let rate = WeightTrend.weeklyRate(points)
        Button(action: onLog) {
            HStack(spacing: 14) {
                Image(systemName: "scalemass.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(DS.cyan)
                    .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.cyan.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("PESO DE TENDENCIA").font(.system(size: 10, weight: .heavy).width(.expanded)).tracking(1).foregroundStyle(DS.text3)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(trend.last.map { NumberFormat.kg($0.kg) } ?? "—").font(.number(24))
                        Text("kg").font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.text3)
                    }
                }
                Spacer()
                if let rate {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text((rate >= 0 ? "+" : "−") + NumberFormat.kg(abs(rate), decimals: 2))
                            .font(.number(15)).foregroundStyle(DS.text)
                        Text("kg / semana").font(.system(size: 10, weight: .medium)).foregroundStyle(DS.text2)
                    }
                } else {
                    Text(weights.isEmpty ? "Apunta tu peso" : "Pésate unos días más").font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.cyan)
                }
                Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(DS.brandDiagonal)
            }
            .glass(padding: 14)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("weight.tile")
    }
}

/// Lunes a domingo: entrenos hechos, planificados y descanso, más la racha de semanas.
struct WeekStrip: View {
    let templates: [WorkoutTemplate]
    let workouts: [Workout]

    var body: some View {
        let start = DateUtils.startOfWeek(Date())
        let planned = templates.filter { $0.weekday > 0 && $0.kind != .rest }.count
        let streak = WeekStreak.compute(workoutDays: workouts.filter { $0.kind != .rest }.map(\.startedAt), planned: planned)
        let today = DateUtils.weekdayMondayBased(Date())
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle(title: "Tu semana")
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").foregroundStyle(streak.current > 0 ? AnyShapeStyle(DS.fire) : AnyShapeStyle(DS.text3))
                        .symbolEffect(.bounce, value: streak.current)
                    Text("\(streak.current) \(streak.current == 1 ? "semana" : "semanas")").font(.system(size: 13, weight: .bold))
                }
                .accessibilityIdentifier("streak")
            }
            HStack(spacing: 0) {
                ForEach(1...7, id: \.self) { day in
                    let date = DateUtils.date(forWeekday: day, inWeekOf: start)
                    let did = workouts.contains { DateUtils.calendar.isDate($0.startedAt, inSameDayAs: date) && $0.kind != .rest }
                    let plan = templates.filter { $0.weekday == day }
                    let restDay = !plan.isEmpty && plan.allSatisfy { $0.kind == .rest }
                    VStack(spacing: 6) {
                        Text(String(WeeklyRoutine.weekdayName(day).prefix(1)))
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(day == today ? DS.text : DS.text3)
                        ZStack {
                            if did {
                                Circle().fill(DS.brandDiagonal)
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy))
                            } else if restDay {
                                Circle().fill(DS.surface)
                                Image(systemName: "moon.fill").font(.system(size: 10)).foregroundStyle(DS.text3)
                            } else if !plan.isEmpty {
                                Circle().strokeBorder(day < today ? DS.text3.opacity(0.5) : DS.indigo.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: day < today ? [3, 3] : []))
                            } else {
                                Circle().fill(DS.surface)
                            }
                        }
                        .frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(day == today ? DS.cyan : .clear, lineWidth: 2).padding(-4))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("Objetivo: \(WeekStreak.goal(planned: planned)) sesiones · llevas \(streak.thisWeek). Mejor racha: \(streak.best) \(streak.best == 1 ? "semana" : "semanas").")
                .font(.system(size: 12)).foregroundStyle(DS.text2)
        }
        .glass()
    }
}

/// Un consejo útil según tus datos de hoy.
struct CoachTip: View {
    let eaten: NutritionValues
    let targets: NutritionValues
    let workouts: [Workout]

    var body: some View {
        let tip = self.tip
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tip.symbol).font(.system(size: 18, weight: .bold)).foregroundStyle(DS.brandDiagonal)
                .frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(DS.surfaceHi))
            VStack(alignment: .leading, spacing: 3) {
                Text("COACH").font(.system(size: 10, weight: .heavy).width(.expanded)).tracking(1.4).foregroundStyle(DS.text3)
                Text(tip.text).font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .glass(padding: 14)
    }

    private var tip: (symbol: String, text: String) {
        let hour = DateUtils.calendar.component(.hour, from: Date())
        let proteinLeft = targets.protein - eaten.protein
        if let last = workouts.first, DateUtils.calendar.isDateInToday(last.startedAt), last.recordCount > 0 {
            return ("trophy.fill", "Hoy has batido \(last.recordCount) \(last.recordCount == 1 ? "récord" : "récords"). Esa es la señal de que el plan funciona.")
        }
        if hour >= 17, proteinLeft > 40 {
            return ("fork.knife", "Te faltan \(Int(proteinLeft)) g de proteína. Una cena con pollo, pescado, huevos o un yogur griego te lo deja casi hecho.")
        }
        if eaten.kcal == 0, hour >= 11 {
            return ("square.and.pencil", "Aún no has apuntado nada hoy. Apunta mientras comes: es lo que más ayuda a llegar a tu objetivo.")
        }
        if let last = workouts.first, Date().timeIntervalSince(last.startedAt) > 3 * 86400 {
            return ("bolt.fill", "Llevas unos días sin entrenar. No hace falta que sea perfecto: hoy, aunque sea una sesión corta.")
        }
        return ("moon.stars.fill", "Dormir 7–9 horas mejora tu fuerza y tu apetito más que cualquier suplemento.")
    }
}
