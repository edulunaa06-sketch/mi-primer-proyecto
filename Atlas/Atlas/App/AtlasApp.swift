import SwiftData
import SwiftUI

@main
struct AtlasApp: App {
    let container: ModelContainer?
    let error: String?
    @State private var app = AppState()
    @State private var steps = StepCounter()
    @State private var strava = StravaService()

    init() {
        do {
            let schema = Schema(AtlasSchema.models)
            #if DEBUG
            // Pruebas: datos en memoria para empezar siempre de cero.
            let inMemory = ProcessInfo.processInfo.arguments.contains("-AtlasInMemory")
            #else
            let inMemory = false
            #endif
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: inMemory))
            error = nil
        } catch let e {
            container = nil
            error = e.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    RootView()
                        .modelContainer(container)
                        .environment(app)
                        .environment(steps)
                        .environment(strava)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(DS.warn)
                        Text("No se pudieron abrir tus datos").font(.headline)
                        Text(error ?? "").font(.footnote).foregroundStyle(DS.text2).multilineTextAlignment(.center)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AtlasBackground())
                }
            }
            .preferredColorScheme(.dark)
            .tint(DS.cyan)
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case today, food, train, progress
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Hoy"
        case .food: return "Comer"
        case .train: return "Entrenar"
        case .progress: return "Progreso"
        }
    }
    var symbol: String {
        switch self {
        case .today: return "sun.max.fill"
        case .food: return "fork.knife"
        case .train: return "dumbbell.fill"
        case .progress: return "chart.xyaxis.line"
        }
    }
}

/// Estado compartido de la interfaz: pestaña, entreno en curso y hojas que se abren desde cualquier sitio.
@MainActor
@Observable
final class AppState {
    var tab: AppTab = .today
    /// Entreno en curso (se abre a pantalla completa).
    var liveWorkout: Workout?
    var showQuickAdd = false
    var showProfile = false
    var foodSheet: FoodSheetRequest?
    var showWeight = false
    var runTemplate: RunRequest?
    /// Día que se ve en Comer.
    var foodDay = Date()
}

struct FoodSheetRequest: Identifiable {
    let id = UUID()
    let meal: MealType
    let dayKey: String
    var startWithMenus = false
}

struct RunRequest: Identifiable {
    let id = UUID()
    let template: WorkoutTemplate?
}
