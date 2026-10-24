import Foundation

/// Opciones de arranque que solo se usan para hacer capturas de la app
/// en el simulador desde GitHub Actions. En el uso normal no hacen nada.
enum LaunchOptions {
    private static let arguments = ProcessInfo.processInfo.arguments

    /// Arranca con datos de ejemplo en memoria, sin tocar lo guardado en el móvil.
    static var isDemo: Bool { arguments.contains("-demo") }

    /// Fuerza la pantalla de bienvenida.
    static var showsOnboarding: Bool { arguments.contains("-onboarding") }

    /// Pestaña que se abre al arrancar (0 = Inicio ... 4 = Perfil).
    static var initialTab: Int {
        guard let index = arguments.firstIndex(of: "-tab"),
              arguments.indices.contains(index + 1),
              let value = Int(arguments[index + 1]) else { return 0 }
        return min(max(value, 0), 4)
    }

    /// Abre directamente un día de la rutina dentro de Entreno.
    static var opensWorkoutDay: Bool { arguments.contains("-workout") }
}
