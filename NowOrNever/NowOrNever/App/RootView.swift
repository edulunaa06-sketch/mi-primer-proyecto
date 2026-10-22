import Observation
import SwiftData
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, training, nutrition, activity, progress, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Inicio"
        case .training: return "Entreno"
        case .nutrition: return "Nutrición"
        case .activity: return "Pasos"
        case .progress: return "Progreso"
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
        case .settings: return "gearshape.fill"
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    var tab: AppTab = .home
}

/// Contenedor principal con barra de pestañas propia (6 secciones; la TabView del sistema
/// agruparía la sexta en "Más").
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(HealthKitManager.self) private var health
    @Environment(NotificationManager.self) private var notifications
    @Environment(StravaService.self) private var strava
    @Environment(AppRouter.self) private var router

    @Query private var settingsList: [UserSettings]
    @State private var showOnboarding = false
    @State private var bootstrapped = false

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
                await notifications.refreshStatus()
                await refreshPhotoRemindersIfNeeded(settings)
                await health.refreshAuthorizationState()
                if health.state == .requested { await health.refresh() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, bootstrapped else { return }
                Task {
                    await notifications.refreshStatus()
                    if health.state == .requested { await health.refresh() }
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
                            .minimumScaleFactor(0.8)
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

    /// Los recordatorios de fotos con día 29–31 se programan mes a mes: se renuevan al abrir la app.
    private func refreshPhotoRemindersIfNeeded(_ settings: UserSettings) async {
        guard settings.photoReminderEnabled, notifications.isAuthorized, let start = settings.trackingStartDate else { return }
        let day = DateUtils.calendar.component(.day, from: start)
        guard day > 28 else { return }
        try? await notifications.schedulePhotoReminders(referenceDay: day, hour: settings.photoReminderHour)
    }
}
