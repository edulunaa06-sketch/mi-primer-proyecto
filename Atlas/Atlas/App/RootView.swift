import SwiftData
import SwiftUI

/// Contenedor: cuatro pestañas en una barra flotante con un botón «+» central para apuntar cualquier cosa.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var app
    @Environment(StepCounter.self) private var steps
    @Environment(StravaService.self) private var strava
    @Query private var profiles: [Profile]
    @State private var bootstrapped = false
    @State private var showIntro = !RootView.skipIntro
    @State private var showOnboarding = false

    static var skipIntro: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-AtlasSkipIntro")
        #else
        false
        #endif
    }

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .bottom) {
            Group {
                switch app.tab {
                case .today: TodayView()
                case .food: FoodView()
                case .train: TrainView()
                case .progress: ProgressScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Espacio para la barra flotante: lo último de cada pantalla siempre se puede leer.
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 84) }

            TabBar()
        }
        .background(AtlasBackground())
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task {
            guard !bootstrapped else { return }
            bootstrapped = true
            #if DEBUG
            DebugLaunch.apply(context: context, app: app)
            #endif
            Store.seedTemplatesIfNeeded(context)
            let profile = Store.profile(context)
            showOnboarding = !profile.onboarded
            // Si se cerró la app a mitad de entreno, se retoma.
            if let open = try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.finishedAt == nil })).first {
                app.liveWorkout = open
            }
            await strava.autoSyncIfNeeded(into: context)
        }
        .onOpenURL { url in
            if url.scheme == StravaAPI.callbackScheme {
                Task {
                    await strava.handleCallback(url)
                    await strava.syncRuns(into: context)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                steps.restart()
                Task { await strava.autoSyncIfNeeded(into: context) }
            } else if phase == .background { steps.stop() }
        }
        .sheet(isPresented: $app.showQuickAdd) { QuickAddSheet().presentationDetents([.medium]) }
        .sheet(isPresented: $app.showProfile) { ProfileSheet() }
        .sheet(item: $app.foodSheet) { req in AddFoodSheet(request: req) }
        .sheet(isPresented: $app.showWeight) { WeightSheet().presentationDetents([.height(340)]) }
        .sheet(item: $app.runTemplate) { req in RunLogSheet(template: req.template).presentationDetents([.large]) }
        .fullScreenCover(item: $app.liveWorkout) { w in LiveWorkoutView(workout: w) }
        .fullScreenCover(isPresented: $showOnboarding) { OnboardingView { showOnboarding = false } }
        .overlay {
            if showIntro {
                IntroView { showIntro = false }
                    .zIndex(10)
            }
        }
    }
}

/// Barra de pestañas flotante (cápsula de cristal) con el «+» en el centro.
struct TabBar: View {
    @Environment(AppState.self) private var app
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            item(.today)
            item(.food)
            Button {
                DS.haptic(.medium)
                app.showQuickAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(DS.brandDiagonal))
                    .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                    .shadow(color: DS.indigo.opacity(0.6), radius: 14, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Añadir")
            .accessibilityIdentifier("tab.add")
            .padding(.horizontal, 6)
            item(.train)
            item(.progress)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Color(red: 0.07, green: 0.075, blue: 0.10).opacity(0.96))
                .overlay(Capsule().strokeBorder(DS.stroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 20, y: 8)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private func item(_ tab: AppTab) -> some View {
        let selected = app.tab == tab
        return Button {
            guard app.tab != tab else { return }
            DS.haptic(.soft)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { app.tab = tab }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol).font(.system(size: 18, weight: .semibold))
                    .symbolEffect(.bounce, value: selected)
                Text(tab.title).font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(selected ? AnyShapeStyle(DS.brand) : AnyShapeStyle(DS.text3))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if selected {
                    Capsule().fill(DS.surfaceHi).matchedGeometryEffect(id: "tab", in: ns)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// «+»: apuntar cualquier cosa desde cualquier pantalla.
struct QuickAddSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("¿Qué apuntamos?").font(.display(22)).padding(.top, 8)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                tile("Comida", "fork.knife", DS.carbs) {
                    let meal = MealType.forNow()
                    open { app.foodSheet = FoodSheetRequest(meal: meal, dayKey: DateUtils.dayKey(Date())) }
                }
                tile("Entreno", "dumbbell.fill", DS.indigo) {
                    let today = templates.first { $0.weekday == DateUtils.weekdayMondayBased(Date()) && $0.kind == .strength }
                    open { app.liveWorkout = Store.startWorkout(from: today, in: context) }
                }
                tile("Peso", "scalemass.fill", DS.cyan) { open { app.showWeight = true } }
                tile("Carrera", "figure.run", DS.good) { open { app.runTemplate = RunRequest(template: nil) } }
                tile("Agua +250 ml", "drop.fill", DS.water) {
                    let w = Store.water(DateUtils.dayKey(Date()), in: context)
                    w.ml += 250
                    try? context.save()
                    DS.haptic(.light)
                    dismiss()
                }
                tile("Menú de platos", "menucard.fill", DS.protein) {
                    let meal = MealType.forNow()
                    open { app.foodSheet = FoodSheetRequest(meal: meal, dayKey: DateUtils.dayKey(Date()), startWithMenus: true) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .presentationBackground(Color(red: 0.06, green: 0.065, blue: 0.09))
        .presentationCornerRadius(28)
    }

    /// Cierra esta hoja y abre la siguiente cuando ya se ha ido (dos hojas a la vez no se pueden).
    private func open(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { action() }
    }

    private func tile(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(color)
                    .frame(width: 34, height: 34).background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.text)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .glass(padding: 12, radius: 18)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("quick.\(title)")
    }
}

extension MealType {
    /// La comida que toca según la hora.
    static func forNow(_ date: Date = Date()) -> MealType {
        switch DateUtils.calendar.component(.hour, from: date) {
        case ..<11: return .breakfast
        case ..<16: return .lunch
        case ..<19: return .snack
        default: return .dinner
        }
    }
}
