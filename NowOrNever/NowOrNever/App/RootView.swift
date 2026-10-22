import Observation
import SwiftData
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, training, nutrition, activity, progress, friends, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Inicio"
        case .training: return "Entreno"
        case .nutrition: return "Nutrición"
        case .activity: return "Pasos"
        case .progress: return "Progreso"
        case .friends: return "Amigos"
        case .settings: return "Ajustes"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .training: return "dumbbell.fill"
        case .nutrition: return "fork.knife"
        case .activity: return "figure.walk"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .friends: return "person.2.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .home
}

/// Contenedor principal con barra de pestañas propia (7 secciones; la TabView del sistema
/// agruparía las últimas en "Más").
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(HealthKitManager.self) private var health
    @Environment(NotificationManager.self) private var notifications
    @Environment(StravaService.self) private var strava
    @Environment(AppRouter.self) private var router
    @Environment(SocialService.self) private var social

    @Query private var settingsList: [UserSettings]
    @State private var showOnboarding = false
    @State private var bootstrapped = false
    @State private var splashQuote: Motivation.Quote? = RootView.nextQuote()
    @State private var splashAutoDismiss = true
    @State private var backgroundedAt: Date?

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
                strava.configure(clientID: settings.stravaClientID, backendURL: settings.stravaBackendURL)
                showOnboarding = !settings.onboardingCompleted
                #if DEBUG
                applyScreenshotArguments()
                #endif
                await notifications.refreshStatus()
                await refreshPhotoRemindersIfNeeded(settings)
                await health.refreshAuthorizationState()
                await health.refresh()
                try? await SocialSync.publish(social: social, health: health, context: context)
            }
            .overlay {
                if let quote = splashQuote {
                    MotivationSplash(quote: quote, autoDismiss: splashAutoDismiss) {
                        withAnimation(.easeInOut(duration: 0.35)) { splashQuote = nil }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    backgroundedAt = Date()
                    // Al salir de la app se comparte el día con lo último registrado.
                    Task { try? await SocialSync.publish(social: social, health: health, context: context) }
                }
                // Al volver a la app tras 10 minutos o más fuera, otra frase.
                if phase == .active, let since = backgroundedAt, Date().timeIntervalSince(since) >= 600 {
                    splashQuote = RootView.nextQuote()
                }
                if phase == .active { backgroundedAt = nil }
                guard phase == .active, bootstrapped else { return }
                Task {
                    await notifications.refreshStatus()
                    await health.refresh()
                }
            }
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
        case .nutrition: NutritionView()
        case .activity: ActivityView()
        case .progress: ProgressHubView()
        case .friends: FriendsView()
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
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    #if DEBUG
    /// Solo en Debug: permite al CI abrir una pestaña concreta para capturas de pantalla.
    private func applyScreenshotArguments() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-NNSkipOnboarding") { showOnboarding = false }
        // Las pruebas y capturas no esperan a la frase; con -NNSplash se queda fija para la captura.
        if args.contains("-NNSplash") { splashAutoDismiss = false } else if args.contains("-NNSkipOnboarding") { splashQuote = nil }
        if let i = args.firstIndex(of: "-NNTab"), i + 1 < args.count, let tab = AppTab(rawValue: args[i + 1]) {
            router.tab = tab
        }
    }
    #endif

    /// Los recordatorios de fotos con día 29–31 se programan mes a mes: se renuevan al abrir la app.
    private func refreshPhotoRemindersIfNeeded(_ settings: UserSettings) async {
        guard settings.photoReminderEnabled, notifications.isAuthorized, let start = settings.trackingStartDate else { return }
        let day = DateUtils.calendar.component(.day, from: start)
        guard day > 28 else { return }
        try? await notifications.schedulePhotoReminders(referenceDay: day, hour: settings.photoReminderHour)
    }
}
