import SwiftUI
import SwiftData
import UIKit

@main
struct NowOrNeverApp: App {

    /// Todos los modelos que guarda la app en el móvil.
    static let schema = Schema([
        UserProfile.self,
        DayPlan.self,
        PlannedMeal.self,
        ManualFood.self,
        WorkoutDayPlan.self,
        ExercisePlan.self,
        WorkoutSession.self,
        SetLog.self,
        WeightEntry.self
    ])

    let container: ModelContainer

    init() {
        AppAppearance.apply()

        // Modo capturas: datos de ejemplo en memoria, sin tocar lo del móvil.
        if LaunchOptions.isDemo || LaunchOptions.showsOnboarding {
            let configuration = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)
            let demoContainer = try! ModelContainer(for: Self.schema, configurations: configuration)
            if LaunchOptions.isDemo {
                SampleData.populate(demoContainer.mainContext)
            }
            container = demoContainer
            return
        }

        do {
            container = try ModelContainer(for: Self.schema,
                                           configurations: ModelConfiguration(schema: Self.schema))
        } catch {
            // Si el almacén antiguo no encaja, se empieza de cero antes que no arrancar.
            container = try! ModelContainer(for: Self.schema,
                                            configurations: ModelConfiguration(schema: Self.schema,
                                                                               isStoredInMemoryOnly: true))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }
}

/// Ajustes globales de UIKit que SwiftUI no cubre (barra de pestañas y de navegación).
enum AppAppearance {
    static func apply() {
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor.black
        tab.shadowColor = UIColor(white: 1, alpha: 0.08)

        let selected = UIColor(Theme.accent)
        let normal = UIColor(white: 0.55, alpha: 1)
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.selected.iconColor = selected
            item.selected.titleTextAttributes = [
                .foregroundColor: selected,
                .font: UIFont.systemFont(ofSize: 10, weight: .heavy)
            ]
            item.normal.iconColor = normal
            item.normal.titleTextAttributes = [
                .foregroundColor: normal,
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
            ]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor.black
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 32, weight: .black)
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
}
