import Observation
import SwiftData
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, training, nutrition, progress, calendar, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Inicio"
        case .training: return "Entreno"
        case .nutrition: return "Nutrición"
        case .progress: return "Progreso"
        case .calendar: return "Calendario"
        case .settings: return "Ajustes"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .training: return "dumbbell.fill"
        case .nutrition: return "fork.knife"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .calendar: return "calendar"
        case .settings: return "gearshape.fill"
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .home
}

/// Contenedor principal con barra de pestañas propia: Inicio, Entreno, Nutrición, Progreso, Calendario y Ajustes.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(NotificationManager.self) private var notifications
    @Environment(StravaService.self) private var strava
    @Environment(AppRouter.self) private var router
    @Environment(StepCounter.self) private var steps

    @Query private var settingsList: [UserSettings]
    @State private var showOnboarding = false
    @State private var bootstrapped = false
    @State private var splashQuote: Motivation.Quote? = RootView.skipSplashForTests ? nil : RootView.nextQuote()
    @State private var splashAutoDismiss = !RootView.screenshotSplash
    /// Solo al abrir la app: pantalla de carga con el logo antes de la frase.
    @State private var splashIntro = true
    @State private var backgroundedAt: Date?
    @State private var lastTrackingSync: Date?

    /// Solo en Debug (capturas del CI): la intro se queda fija. Se lee al crear la vista, antes de que empiece la intro.
    static var screenshotSplash: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-NNSplash")
        #else
        false
        #endif
    }

    /// Solo en Debug: las pruebas de interfaz arrancan sin intro.
    static var skipSplashForTests: Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-NNSkipOnboarding") && !args.contains("-NNSplash")
        #else
        false
        #endif
    }

    /// Elige una frase distinta de la última mostrada.
    static func nextQuote() -> Motivation.Quote {
        let key = "motivation.lastIndex"
        let last = UserDefaults.standard.object(forKey: key) as? Int
        let index = Motivation.next(after: last)
        UserDefaults.standard.set(index, forKey: key)
        return Motivation.quotes[index]
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
            .task {
                guard !bootstrapped else { return }
                bootstrapped = true
                DataStore.bootstrap(context)
                let settings = DataStore.settings(context)
                strava.configure(clientID: settings.stravaClientID)
                showOnboarding = !settings.onboardingCompleted
                #if DEBUG
                applyScreenshotArguments()
                #endif
                // Después de preparar los datos: así la carga inicial no cuenta como bloqueo.
                HangDetector.shared.start()
                await notifications.refreshStatus()
                await refreshPhotoRemindersIfNeeded(settings)
                await syncTracking()
            }
            .overlay {
                if let quote = splashQuote {
                    MotivationSplash(quote: quote, autoDismiss: splashAutoDismiss, showIntro: splashIntro) {
                        withAnimation(.easeInOut(duration: 0.35)) { splashQuote = nil }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                HangDetector.shared.setPaused(phase != .active)
                if phase == .background {
                    backgroundedAt = Date()
                    // Los pasos de hoy se guardan al salir de la app, no mientras la usas:
                    // así ningún guardado hace recalcular la pantalla mientras te desplazas.
                    if bootstrapped, let today = steps.todaySteps {
                        DataStore.saveSteps(today, for: Date(), goal: DataStore.settings(context).stepGoal, in: context)
                    }
                    steps.stop()
                    // Al salir de la app se rehacen los avisos con los últimos pasos y pesajes.
                    if bootstrapped {
                        Task { await ReminderCoordinator.refresh(context: context, notifications: notifications, todaySteps: steps.todaySteps) }
                    }
                }
                if phase == .active { steps.restart() }
                // Al volver a la app tras 10 minutos o más fuera, otra frase.
                if phase == .active, let since = backgroundedAt, Date().timeIntervalSince(since) >= 600 {
                    splashIntro = false
                    splashQuote = RootView.nextQuote()
                }
                if phase == .active { backgroundedAt = nil }
                guard phase == .active, bootstrapped else { return }
                Task {
                    await notifications.refreshStatus()
                    await syncTracking()
                }
            }

            .onChange(of: router.tab) { _, tab in HangDetector.shared.screen = tab.title }
            .onOpenURL { url in
                if url.scheme == StravaAPI.callbackScheme {
                    Task { await strava.handleCallback(url) }
                }
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView { showOnboarding = false }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch router.tab {
        case .home: HomeView()
        case .training: TrainingView()
        case .nutrition: NutritionRootView()
        case .progress: ProgressHubView()
        case .calendar: CalendarView()
        case .settings: SettingsView()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    router.tab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 18, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(router.tab == tab ? Theme.lime : Theme.textTertiary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(router.tab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .background(
            Theme.card
                .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    #if DEBUG
    /// Solo en Debug: permite al CI abrir una pestaña concreta para capturas de pantalla.
    private func applyScreenshotArguments() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-NNSkipOnboarding") { showOnboarding = false }
        if args.contains("-NNDemoData") { DataStore.seedDemoData(context) }
        if args.contains("-NNClearHangs") { HangDetector.clear() }
        // Las pruebas y capturas no esperan a la frase; con -NNSplash se queda fija para la captura.
        if args.contains("-NNSplash") { splashAutoDismiss = false } else if args.contains("-NNSkipOnboarding") { splashQuote = nil }
        if let i = args.firstIndex(of: "-NNTab"), i + 1 < args.count, let tab = AppTab(rawValue: args[i + 1]) {
            router.tab = tab
        }
    }
    #endif

    /// Guarda los pasos de los últimos 7 días (el iPhone no guarda más), ajusta el objetivo
    /// adaptativo una vez al día y rehace los avisos. Como mucho cada 15 minutos.
    private func syncTracking() async {
        if let last = lastTrackingSync, Date().timeIntervalSince(last) < 15 * 60 { return }
        lastTrackingSync = Date()
        let goal = DataStore.settings(context).stepGoal
        let history = await steps.history()
        for day in history {
            DataStore.saveSteps(day.steps, for: day.date, goal: goal, in: context, save: false)
        }
        try? context.save()
        DataStore.updateAdaptiveStepGoal(context)
        let today = steps.todaySteps ?? history.last(where: { DateUtils.calendar.isDateInToday($0.date) })?.steps
        await ReminderCoordinator.refresh(context: context, notifications: notifications, todaySteps: today)
        await strava.autoSyncIfNeeded(into: context)
    }

    /// Los recordatorios de fotos con día 29–31 se programan mes a mes: se renuevan al abrir la app.
    private func refreshPhotoRemindersIfNeeded(_ settings: UserSettings) async {
        guard settings.photoReminderEnabled, notifications.isAuthorized, let start = settings.trackingStartDate else { return }
        let day = DateUtils.calendar.component(.day, from: start)
        guard day > 28 else { return }
        try? await notifications.schedulePhotoReminders(referenceDay: day, hour: settings.photoReminderHour)
    }
}
