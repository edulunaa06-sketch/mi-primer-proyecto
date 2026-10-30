import SwiftData
import SwiftUI

@main
struct AtlasApp: App {
    private let container: ModelContainer?
    private let containerError: String?

    @State private var notifications = NotificationManager()
    @State private var strava = StravaService()
    @State private var router = AppRouter()
    @State private var claude = ClaudeService()
    @State private var steps = StepCounter()

    static let schema = Schema([
        UserSettings.self,
        WeightEntry.self,
        WorkoutSessionLog.self,
        ExerciseLog.self,
        SetLog.self,
        PersonalRecordEntry.self,
        TrainingWeek.self,
        RecoveryLogEntry.self,
        SupplementEntry.self,
        SupplementIntake.self,
        RoutineExercise.self,
        CustomExercise.self,
        SessionTitle.self,
        FoodItem.self,
        MenuPlan.self,
        MealTemplate.self,
        MealItem.self,
        MealRecord.self,
        DayPlanSelection.self,
        DayMealChoice.self,
        CustomMealItem.self,
        ProgressPhoto.self,
        StravaActivityRecord.self,
        DailySteps.self,
        WaterLog.self,
        DayMarkRecord.self,
    ])

    init() {
        do {
            // Solo almacenamiento local: sin sincronización con iCloud.
            let config = ModelConfiguration("Atlas", schema: Self.schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
            container = try ModelContainer(for: Self.schema, configurations: [config])
            containerError = nil
        } catch {
            // No se borra nada automáticamente: se informa del error para no perder el historial.
            container = nil
            containerError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                RootView()
                    .modelContainer(container)
                    .environment(notifications)
                    .environment(strava)
                    .environment(router)
                    .environment(claude)
                    .environment(steps)
                    .preferredColorScheme(.light)
                    .tint(Theme.accent)
            } else {
                StorageErrorView(message: containerError ?? "Error desconocido")
                    .preferredColorScheme(.light)
            }
        }
        .backgroundTask(.appRefresh(ReminderCoordinator.refreshTaskID)) {
            guard let container else { return }
            await ReminderCoordinator.backgroundRefresh(container: container)
        }
    }
}

private struct StorageErrorView: View {
    let message: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(Theme.warning)
            Text("No se pudo abrir la base de datos local")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("Tus datos no se han borrado. Cierra la app y vuelve a abrirla. Si el problema persiste, actualiza la app.\n\nDetalle: \(message)")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}
