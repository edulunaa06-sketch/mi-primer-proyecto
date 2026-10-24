import SwiftUI
import SwiftData

/// Decide si enseñar la bienvenida o la app, y monta las cinco pestañas.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        Group {
            if let profile {
                MainTabView(profile: profile)
            } else {
                OnboardingView()
            }
        }
        .onAppear {
            PlanService.seedRoutineIfNeeded(context: context)
        }
    }
}

/// Las cinco pestañas de la app.
struct MainTabView: View {
    let profile: UserProfile

    var body: some View {
        TabView {
            HomeView(profile: profile)
                .tabItem { Label("Inicio", systemImage: "bolt.fill") }

            NutritionView(profile: profile)
                .tabItem { Label("Nutrición", systemImage: "fork.knife") }

            WorkoutView()
                .tabItem { Label("Entreno", systemImage: "dumbbell.fill") }

            ProgressTabView(profile: profile)
                .tabItem { Label("Progreso", systemImage: "chart.line.uptrend.xyaxis") }

            ProfileView(profile: profile)
                .tabItem { Label("Perfil", systemImage: "person.fill") }
        }
        .tint(Theme.accent)
    }
}

#Preview("Con perfil") {
    RootView()
        .modelContainer(SampleData.container)
        .preferredColorScheme(.dark)
}

#Preview("Sin perfil") {
    RootView()
        .modelContainer(SampleData.emptyContainer)
        .preferredColorScheme(.dark)
}
