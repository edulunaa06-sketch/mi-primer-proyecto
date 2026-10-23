import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(HealthKitManager.self) private var health
    @Query private var sessionTitles: [SessionTitle]
    @Environment(AppRouter.self) private var router

    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query private var settingsList: [UserSettings]
    @Query private var todayMeals: [MealRecord]
    @Query private var weekLogs: [WorkoutSessionLog]
    @Query(sort: \RoutineExercise.order) private var routine: [RoutineExercise]

    @State private var showWeightSheet = false
    @State private var showStravaMissing = false

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
            steps: health.todaySteps,
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
                    stepsAndTraining
                    quickActions
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Now or Never")
            .toolbarBackground(Theme.background, for: .navigationBar)
            .sheet(isPresented: $showWeightSheet) { WeightEntrySheet() }
            .alert("Strava no está instalado", isPresented: $showStravaMissing) {
                Button("Abrir App Store") { StravaLauncher.openAppStore() }
                Button("Abrir strava.com") { StravaLauncher.openWebsite() }
                Button("Cancelar", role: .cancel) {}
            }
            .refreshable { await health.refresh() }
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
                if health.todaySteps == nil {
                    Text("Pasos sin datos de Salud: no cuentan en el cálculo.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
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

    private var stepsCard: some View {
        let goal = settings?.stepGoal ?? 8000
        let steps = health.todaySteps
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ProgressRing(fraction: steps.map { StepEstimates.fraction($0, goal: goal) } ?? 0, size: 84,
                             label: steps == nil ? "—" : nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PASOS DE HOY").font(.caption.weight(.heavy)).foregroundStyle(Theme.lime)
                    Text(steps.map { NumberFormat.integer($0) } ?? "—")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .accessibilityIdentifier("home.steps")
                    Text(steps.map { $0 >= goal ? "¡Objetivo de \(NumberFormat.integer(goal)) cumplido!" : "Te faltan \(NumberFormat.integer(goal - $0)) para \(NumberFormat.integer(goal))" }
                         ?? "Objetivo: \(NumberFormat.integer(goal)) pasos")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            if let steps {
                HStack {
                    Label(String(format: "≈ %.1f km", StepEstimates.kilometers(steps)).replacingOccurrences(of: ".", with: ","), systemImage: "map")
                    Spacer()
                    Label("≈ \(NumberFormat.integer(StepEstimates.kcal(steps))) kcal", systemImage: "flame.fill")
                    Spacer()
                    Text(health.stepsSource ?? "").foregroundStyle(Theme.textTertiary)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            } else if health.state == .notDetermined {
                Button("Contar mis pasos") {
                    Task { await health.requestAuthorization() }
                }
                .buttonStyle(LimeButtonStyle())
            } else {
                Text(health.state == .unavailable
                     ? "Este dispositivo no tiene Apple Salud ni sensor de pasos."
                     : health.state == .motionOnly
                     ? "Sin pasos todavía. Si no aparecen, activa Ajustes › Privacidad y seguridad › Movimiento y forma física › Now or Never."
                     : "Sin pasos todavía. Si no aparecen, revisa Ajustes › Salud › Acceso a datos › Now or Never, o Ajustes › Privacidad › Movimiento y forma física.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }
        .card()
        .task { await health.refresh() }
    }

    private var stepsAndTraining: some View {
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

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Accesos rápidos")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                quickButton("Registrar peso", "scalemass.fill") { showWeightSheet = true }
                quickButton("Ver pasos", "figure.walk") { router.tab = .activity }
                quickButton("Iniciar carrera", "figure.run") {
                    Task {
                        let result = await StravaLauncher.openRecording()
                        if result == .notInstalled { showStravaMissing = true }
                    }
                }
                quickButton("Ver rutina", "dumbbell.fill") { router.tab = .training }
            }
        }
    }

    private func quickButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.footnote.weight(.semibold))
            }
            .foregroundStyle(Theme.lime)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
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
