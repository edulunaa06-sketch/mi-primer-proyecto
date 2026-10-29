import SwiftUI

/// Paleta y estilos compartidos de Now or Never.
///
/// Todo el color de la app pasa por aquí, y aquí se traduce al lenguaje visual de Now or Never (`DS`):
/// negro cálido, grafito y oro. Las pantallas siguen escribiendo `Theme.algo`, así que cambiar la
/// estética entera es cambiar este archivo.
enum Theme {
    static let background = DS.bg
    static let card = DS.surface
    static let cardRaised = DS.surfaceHi
    /// Color de acento para texto e iconos interactivos: el oro (el degradado va en los botones).
    static let accent = DS.gold
    static let accentDim = DS.gold.opacity(0.16)
    static let textPrimary = DS.text
    static let textSecondary = DS.text2
    static let textTertiary = DS.text3
    static let warning = DS.warn
    static let danger = DS.bad
    /// Texto e iconos encima de un fondo de acento (el oro). Negro, para que se lea.
    static let onAccent = DS.onGold
    /// Líneas separadoras finas.
    static let separator = DS.stroke

    // MARK: Colores con significado (solo cuando comunican algo)

    /// Racha: fuego naranja y ámbar.
    static let flame = Color(red: 1.0, green: 0.45, blue: 0.10)
    static let amber = DS.warn
    static let flameGradient = DS.fire

    /// Medallas, récords y logros: dorado (el mismo oro de la marca, con más brillo).
    static let gold = DS.gold
    static let goldDeep = DS.goldDark
    static let goldGradient = DS.goldGradient

    /// Calorías: platino (te sobra margen), ámbar (te acercas), verde (en el objetivo), rojo (te has
    /// pasado). El platino en vez del oro a propósito: el oro es para lo que has conseguido, y que te
    /// queden calorías por comer no es un logro.
    static let kcalPlenty = DS.steel
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

    /// Días de descanso: platino discreto.
    static let rest = DS.steel

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

/// Botón de acción: cápsula de oro con el texto en negro (relleno), o de grafito (sin relleno).
struct GoldButtonStyle: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(filled ? DS.onGold : DS.text)
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(filled ? AnyShapeStyle(DS.brand) : AnyShapeStyle(DS.surfaceHi)))
            .overlay(Capsule().strokeBorder(filled ? DS.champagne.opacity(0.45) : DS.stroke, lineWidth: 1))
            .shadow(color: DS.gold.opacity(filled && !configuration.isPressed ? 0.35 : 0), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
