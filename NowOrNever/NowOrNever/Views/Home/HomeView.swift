import SwiftData
import SwiftUI
import UIKit

struct HomeView: View {
    @Query private var sessionTitles: [SessionTitle]
    @Environment(AppRouter.self) private var router

    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query private var settingsList: [UserSettings]
    @Query private var todayMeals: [MealRecord]
    @Query private var weekLogs: [WorkoutSessionLog]
    @Query(sort: \RoutineExercise.order) private var routine: [RoutineExercise]

    @State private var showStepGoal = false

    private let today = Date()

    init() {
        let key = DateUtils.dayKey(Date())
        _todayMeals = Query(filter: #Predicate<MealRecord> { $0.dayKey == key })
        let weekStart = DateUtils.startOfWeek(Date())
        _weekLogs = Query(filter: #Predicate<WorkoutSessionLog> { $0.weekStart == weekStart })
    }

    private var settings: UserSettings? { settingsList.first }
    private var todaySessions: [SessionDefinition] {
        WeeklyRoutine.sessions(forWeekday: DateUtils.weekdayMondayBased(today)).map { $0.resolved(with: routine, titles: sessionTitles) }
    }
    private var trainableToday: [SessionDefinition] { todaySessions.filter { $0.kind != .rest } }

    private func isCompleted(_ session: SessionDefinition) -> Bool {
        weekLogs.first { $0.sessionID == session.id }?.isCompleted ?? false
    }

    private var consumed: NutritionValues { NutritionMath.sum(todayMeals.map(\.values)) }


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    caloriesCard
                    // Las tarjetas que leen los pasos en vivo son vistas aparte: cada paso nuevo solo
                    // redibuja esas tarjetas, no toda la pantalla.
                    HomeStepsCard(goal: settings?.stepGoal ?? 8000, adaptive: settings?.stepGoalAdaptive ?? true) { showStepGoal = true }
                    HomeStreakCard()
                    HomeComplianceCard(mealsCompleted: Set(todayMeals.map(\.mealTypeRaw)).count,
                                       sessionsCompleted: trainableToday.filter(isCompleted).count,
                                       sessionsScheduled: trainableToday.count,
                                       stepGoal: settings?.stepGoal ?? 8000)
                    weightCard
                    todayTraining
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Now or Never")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .sheet(isPresented: $showStepGoal) { StepGoalSheet() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sentenceCase(today.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_ES")))))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Text("Hoy cuenta.")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weightCard: some View {
        let points = weights.map { WeightStats.Point(date: $0.date, kg: $0.weightKg) }
        let first = WeightStats.first(points)
        let latest = WeightStats.latest(points)
        return HStack(spacing: 12) {
            MetricTile(
                title: "Peso actual",
                value: latest.map { NumberFormat.kg($0.kg) + " kg" } ?? "—",
                detail: latest.map { DateUtils.shortDate($0.date) } ?? "Sin registros todavía",
                symbol: "scalemass.fill"
            )
            MetricTile(
                title: "Desde el inicio",
                value: (first != nil && latest != nil && points.count > 1) ? NumberFormat.signedKg(latest!.kg - first!.kg) : "—",
                detail: first.map { "Inicial: \(NumberFormat.kg($0.kg)) kg" } ?? "Registra tu primer peso",
                symbol: "arrow.left.arrow.right"
            )
        }
    }

    /// Lo que te queda por comer hoy (objetivo − lo comido), sin anillos. Tocar abre Comidas.
    private var caloriesCard: some View {
        VStack(spacing: 8) {
            CaloriesLeftCard(consumed: consumed,
                             target: NutritionValues(kcal: settings?.kcalTarget ?? 0, protein: settings?.proteinTarget ?? 0,
                                                     carbs: settings?.carbsTarget ?? 0, fat: settings?.fatTarget ?? 0),
                             title: "Calorías de hoy", margin: settings?.kcalMargin ?? CalorieStatus.defaultMargin)
            Button { router.tab = .nutrition } label: {
                Label("Apuntar lo que como", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(LimeButtonStyle(filled: false))
        }
    }

    private var todayTraining: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                MetricTile(
                    title: "Comidas",
                    value: "\(Set(todayMeals.map(\.mealTypeRaw)).count)/4",
                    detail: "\(NumberFormat.integer(consumed.kcal)) kcal registradas",
                    symbol: "fork.knife"
                )
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Entrenamiento de hoy", subtitle: WeeklyRoutine.weekdayName(DateUtils.weekdayMondayBased(today)))
                ForEach(todaySessions) { session in
                    HStack {
                        Image(systemName: icon(for: session.kind))
                            .foregroundStyle(session.kind == .rest ? Theme.rest : isCompleted(session) ? Theme.lime : Theme.textSecondary)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(session.title).font(.subheadline.weight(.semibold))
                            Text(session.kind == .strength ? "\(session.exercises.count) ejercicios" : session.detail)
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        if session.kind != .rest { CheckCircle(isOn: isCompleted(session), size: 22) }
                    }
                }
            }
            .card()
        }
    }

    /// "jueves, 22 de octubre" → "Jueves, 22 de octubre"
    private func sentenceCase(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    private func icon(for kind: SessionKind) -> String {
        switch kind {
        case .run: return "figure.run"
        case .strength: return "dumbbell.fill"
        case .rest: return "bed.double.fill"
        }
    }
}

/// Cumplimiento del día. Lee los pasos en vivo, así que va aparte de la pantalla principal.
private struct HomeComplianceCard: View {
    let mealsCompleted: Int
    let sessionsCompleted: Int
    let sessionsScheduled: Int
    let stepGoal: Int
    @Environment(StepCounter.self) private var steps

    var body: some View {
        let compliance = DailyCompliance(mealsCompleted: mealsCompleted, sessionsCompleted: sessionsCompleted,
                                         sessionsScheduled: sessionsScheduled, steps: steps.todaySteps, stepGoal: stepGoal)
        HStack(spacing: 18) {
            ProgressRing(fraction: compliance.fraction, size: 96)
            VStack(alignment: .leading, spacing: 6) {
                Text("Cumplimiento diario").font(.headline)
                ForEach(compliance.components, id: \.name) { comp in
                    HStack {
                        Text(comp.name).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(NumberFormat.percent(comp.fraction)).monospacedDigit()
                    }
                    .font(.caption)
                }
            }
        }
        .card()
    }
}

/// Pasos de hoy con el sensor del iPhone, en vivo mientras la app está abierta.
private struct HomeStepsCard: View {
    let goal: Int
    let adaptive: Bool
    let onChangeGoal: () -> Void
    @Environment(StepCounter.self) private var steps

    var body: some View {
        let today = steps.todaySteps
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ProgressRing(fraction: today.map { StepEstimates.fraction($0, goal: goal) } ?? 0, size: 84,
                             label: today == nil ? "—" : nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PASOS DE HOY").font(.caption.weight(.heavy)).foregroundStyle(Theme.lime)
                    Text(today.map { NumberFormat.integer($0) } ?? "—")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .accessibilityIdentifier("home.steps")
                    Text(today.map { $0 >= goal ? "¡Objetivo de \(NumberFormat.integer(goal)) cumplido!" : "Te faltan \(NumberFormat.integer(goal - $0)) para \(NumberFormat.integer(goal))" }
                         ?? "Objetivo: \(NumberFormat.integer(goal)) pasos")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    Button(action: onChangeGoal) {
                        Label(adaptive ? "Objetivo automático · cambiar" : "Objetivo manual · cambiar",
                              systemImage: "slider.horizontal.3")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            if let today {
                HStack {
                    Label(String(format: "≈ %.1f km", StepEstimates.kilometers(today)).replacingOccurrences(of: ".", with: ","), systemImage: "map")
                    Spacer()
                    Label("≈ \(NumberFormat.integer(StepEstimates.kcal(today))) kcal", systemImage: "bolt.fill")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            } else {
                Text(steps.state == .unavailable
                     ? "Este dispositivo no tiene sensor de pasos."
                     : steps.state == .denied
                     ? "Sin permiso para contar pasos. Actívalo en Ajustes › Privacidad y seguridad › Movimiento y forma física › Now or Never."
                     : "Contando pasos… Si no aparecen, revisa Ajustes › Privacidad y seguridad › Movimiento y forma física.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }
        .card()
        .onAppear { steps.start() }
    }
}

/// Racha de días cumplidos (llama naranja y ámbar) y marca de hoy (descanso, enfermo…). Tocar abre el calendario.
/// Sale de los datos reales (DayEvaluator): un día suma 1 solo cuando llega al 70 % de su cumplimiento
/// (comidas, entrenos previstos y pasos) o lo marcas como entrenado. Abrir la app no suma nada.
private struct HomeStreakCard: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var allMeals: [MealRecord]
    @Query private var allLogs: [WorkoutSessionLog]
    @Query private var dailySteps: [DailySteps]
    @Query private var marks: [DayMarkRecord]
    @Query private var settingsList: [UserSettings]
    @State private var trackingStart = DateUtils.startOfDay(Date())
    @State private var streak = Streak.Result(current: 0, best: 0)
    @State private var mark: DayMark = .normal
    /// Sube cada vez que la racha crece, para animar la llama una vez.
    @State private var bounce = 0
    @State private var newRecord = false

    private static let seenCurrentKey = "streak.lastSeenCurrent"
    private static let seenBestKey = "streak.lastSeenBest"

    private var signature: String {
        TrackingSnapshot.signature(meals: allMeals, logs: allLogs, steps: dailySteps, marks: marks,
                                   stepGoal: settingsList.first?.stepGoal ?? 8000, trackingStart: trackingStart)
    }

    var body: some View {
        let active = streak.current > 0
        Button { router.tab = .calendar } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(active ? Theme.flame.opacity(0.16) : Theme.cardRaised)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(active ? AnyShapeStyle(Theme.flameGradient) : AnyShapeStyle(Theme.textTertiary))
                        .symbolEffect(.bounce, value: bounce)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(streak.current)")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                            .accessibilityIdentifier("streak.current")
                        Text(streak.current == 1 ? "día seguido" : "días seguidos")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    }
                    if newRecord {
                        Label("¡Nuevo récord!", systemImage: "trophy.fill")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Theme.gold)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("Calendario").font(.caption.weight(.semibold)).foregroundStyle(Theme.lime)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Racha: \(Medals.days(Double(streak.current))). \(subtitle)")
        .onAppear { trackingStart = DataStore.trackingStart(context) }
        // La racha se calcula una vez y solo de nuevo si cambian los datos.
        .task(id: signature) {
            let today = Date()
            let snapshot = TrackingSnapshot(meals: allMeals, logs: allLogs, steps: dailySteps, marks: marks,
                                            stepGoal: settingsList.first?.stepGoal ?? 8000, trackingStart: trackingStart)
            let result = snapshot.streak
            mark = DayMark.effective(explicit: snapshot.explicitMark(today), weekday: DateUtils.weekdayMondayBased(today))
            celebrateIfNeeded(result)
            withAnimation(reduceMotion ? nil : .snappy) { streak = result }
        }
    }

    private var subtitle: String {
        if mark == .trained { return "Hoy: entrenado (cuenta como cumplido)" }
        if mark != .normal { return "Hoy: \(mark.label.lowercased()) (no rompe la racha)" }
        if streak.current == 0 {
            return streak.best > 0 ? "Hoy puedes empezar una nueva · Mejor: \(Medals.days(Double(streak.best)))"
                                   : "Cumple el día para empezar tu racha"
        }
        return "Mejor racha: \(Medals.days(Double(streak.best)))"
    }

    /// Compara con lo último que se vio en este iPhone: cada subida se anima una sola vez.
    private func celebrateIfNeeded(_ result: Streak.Result) {
        let defaults = UserDefaults.standard
        let seenCurrent = defaults.object(forKey: Self.seenCurrentKey) as? Int
        let seenBest = defaults.object(forKey: Self.seenBestKey) as? Int
        let feedback = StreakFeedback.evaluate(current: result.current, best: result.best,
                                               lastSeenCurrent: seenCurrent, lastSeenBest: seenBest)
        defaults.set(result.current, forKey: Self.seenCurrentKey)
        defaults.set(max(result.best, seenBest ?? 0), forKey: Self.seenBestKey)
        guard feedback != .none else { return }
        if !reduceMotion { bounce += 1 }
        if feedback == .newRecord {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.6)) { newRecord = true }
        }
    }
}
