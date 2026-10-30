import SwiftUI

/// Paleta y estilos compartidos de Now or Never.
///
/// Todo el color de la app pasa por aquí, y aquí se traduce al lenguaje visual de Now or Never (`DS`):
/// papel blanco, texto casi negro y azul para lo que se puede tocar. Las pantallas siguen
/// escribiendo `Theme.algo`, así que cambiar la estética entera es cambiar este archivo.
enum Theme {
    static let background = DS.bg
    static let card = DS.surface
    static let cardRaised = DS.surfaceHi
    /// Color de acento para texto e iconos interactivos: el azul (el degradado va en los botones).
    static let accent = DS.accent
    static let accentDim = DS.accent.opacity(0.12)
    static let textPrimary = DS.text
    static let textSecondary = DS.text2
    static let textTertiary = DS.text3
    static let warning = DS.warn
    static let danger = DS.bad
    /// Texto e iconos encima de un fondo de acento (el azul). Blanco, para que se lea.
    static let onAccent = DS.onAccent
    /// Líneas separadoras finas.
    static let separator = DS.stroke

    // MARK: Colores con significado (solo cuando comunican algo)

    /// Racha: fuego naranja. Bajado de luz para que se vea sobre papel blanco.
    static let flame = Color(red: 0.90, green: 0.33, blue: 0.05)
    static let amber = DS.warn
    static let flameGradient = DS.fire

    /// Medallas, récords y logros: oro. Una medalla de otro color no es una medalla, así que
    /// esto no sigue a la marca; solo está bajado de luz para leerse sobre blanco.
    static let gold = DS.gold
    static let goldDeep = Color(red: 0.49, green: 0.33, blue: 0.02)
    static let goldGradient = DS.goldGradient

    /// Calorías: gris (te sobra margen), ámbar (te acercas), verde (en el objetivo), rojo (te has
    /// pasado). Gris en vez del azul de la marca a propósito: que te queden calorías por comer no
    /// es ni bueno ni malo, es simplemente que aún no has llegado.
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

    /// Días de descanso: gris azulado discreto.
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

/// Botón de acción: cápsula azul con el texto en blanco (relleno), o clara con el texto
/// oscuro (sin relleno). El nombre no dice el color a propósito: así el siguiente cambio de
/// paleta no obliga a renombrarlo en medio centenar de sitios.
struct ActionButtonStyle: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(filled ? DS.onAccent : DS.text)
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(filled ? AnyShapeStyle(DS.brand) : AnyShapeStyle(DS.surfaceHi)))
            .overlay(Capsule().strokeBorder(filled ? Color.white.opacity(0.28) : DS.stroke, lineWidth: 1))
            .shadow(color: DS.indigo.opacity(filled && !configuration.isPressed ? 0.30 : 0), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
