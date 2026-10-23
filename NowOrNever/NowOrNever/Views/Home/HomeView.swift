import SwiftData
import SwiftUI

struct HomeView: View {
    @Query private var sessionTitles: [SessionTitle]
    @Environment(AppRouter.self) private var router
    @Environment(StepCounter.self) private var steps

    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query private var settingsList: [UserSettings]
    @Query private var todayMeals: [MealRecord]
    @Query private var weekLogs: [WorkoutSessionLog]
    @Query(sort: \RoutineExercise.order) private var routine: [RoutineExercise]

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

    private var compliance: DailyCompliance {
        DailyCompliance(
            mealsCompleted: Set(todayMeals.map(\.mealTypeRaw)).count,
            sessionsCompleted: trainableToday.filter(isCompleted).count,
            sessionsScheduled: trainableToday.count,
            steps: steps.todaySteps,
            stepGoal: settings?.stepGoal ?? 8000
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    caloriesCard
                    stepsCard
                    complianceCard
                    weightCard
                    todayTraining
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Now or Never")
            .toolbarBackground(Theme.background, for: .navigationBar)
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

    private var complianceCard: some View {
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
                             title: "Calorías de hoy")
            Button { router.tab = .nutrition } label: {
                Label("Apuntar lo que como", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(LimeButtonStyle(filled: false))
        }
    }

    /// Pasos de hoy con el sensor del iPhone, en vivo mientras la app está abierta.
    private var stepsCard: some View {
        let goal = settings?.stepGoal ?? 8000
        let today = steps.todaySteps
        return VStack(alignment: .leading, spacing: 12) {
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
                }
                Spacer(minLength: 0)
            }
            if let today {
                HStack {
                    Label(String(format: "≈ %.1f km", StepEstimates.kilometers(today)).replacingOccurrences(of: ".", with: ","), systemImage: "map")
                    Spacer()
                    Label("≈ \(NumberFormat.integer(StepEstimates.kcal(today))) kcal", systemImage: "flame.fill")
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
                            .foregroundStyle(Theme.lime)
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
