import SwiftUI

/// Paleta y estilos compartidos de Now or Never.
///
/// Todo el color de la app pasa por aquí, y aquí se traduce al lenguaje visual de Now or Never (`DS`):
/// negro profundo con resplandor índigo, tarjetas de cristal y degradado índigo → cian en las acciones.
/// Las pantallas siguen escribiendo `Theme.algo`, así que cambiar la estética es cambiar este archivo.
enum Theme {
    static let background = DS.bg
    static let card = DS.surface
    static let cardRaised = DS.surfaceHi
    /// Color de acento para texto e iconos interactivos (el degradado se usa en los botones).
    static let lime = DS.cyan
    static let limeDim = DS.cyan.opacity(0.16)
    static let textPrimary = DS.text
    static let textSecondary = DS.text2
    static let textTertiary = DS.text3
    static let warning = DS.warn
    static let danger = DS.bad
    /// Texto e iconos encima de un fondo de acento.
    static let onLime = Color.black
    /// Líneas separadoras finas.
    static let separator = DS.stroke

    // MARK: Colores con significado (solo cuando comunican algo)

    /// Racha: fuego naranja y ámbar.
    static let flame = Color(red: 1.0, green: 0.45, blue: 0.10)
    static let amber = DS.warn
    static let flameGradient = DS.fire

    /// Medallas, récords y logros: dorado.
    static let gold = DS.gold
    static let goldDeep = Color(red: 0.80, green: 0.55, blue: 0.12)
    static let goldGradient = DS.goldGradient

    /// Calorías: índigo (margen), ámbar (te acercas), verde (objetivo ± margen), rojo (te has pasado).
    static let kcalPlenty = DS.indigo
    static let kcalApproaching = DS.warn
    static let kcalOnTarget = DS.good
    static let kcalOver = DS.bad

    static func color(_ status: CalorieStatus) -> Color {
        switch status {
        case .plenty: return kcalPlenty
        case .approaching: return kcalApproaching
        case .onTarget: return kcalOnTarget
        case .over: return kcalOver
        }
    }

    /// Macronutrientes: cada uno con su color fijo.
    static let protein = DS.protein
    static let carbs = DS.carbs
    static let fat = DS.fat

    /// Días de descanso: gris azulado discreto.
    static let rest = Color(red: 0.55, green: 0.63, blue: 0.75)

    /// Espacio libre al final de cada pantalla para poder leer lo último con holgura.
    static let bottomBreathingRoom: CGFloat = 72

    static let cornerRadius: CGFloat = DS.radius
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content.glass(padding: padding)
    }
}

extension View {
    /// Tarjeta de cristal de Now or Never.
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Fondo común de todas las pantallas: negro con los dos resplandores de Now or Never.
    func screenBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AtlasBackground())
    }
}

/// Botón de acción: cápsula con el degradado índigo → cian (relleno) o de cristal (sin relleno).
struct LimeButtonStyle: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(filled ? Color.white : DS.text)
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(filled ? AnyShapeStyle(DS.brand) : AnyShapeStyle(DS.surfaceHi)))
            .overlay(Capsule().strokeBorder(filled ? .white.opacity(0.25) : DS.stroke, lineWidth: 1))
            .shadow(color: DS.indigo.opacity(filled && !configuration.isPressed ? 0.45 : 0), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
