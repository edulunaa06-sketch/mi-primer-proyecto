import SwiftUI

/// Paleta y estilos compartidos: fondo carbón, acentos verde lima, texto blanco/gris.
/// Colores fijos (la app es siempre oscura): son los más baratos de dibujar.
enum Theme {
    static let background = Color(red: 0.05, green: 0.05, blue: 0.06)
    static let card = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let cardRaised = Color(red: 0.16, green: 0.16, blue: 0.17)
    static let lime = Color(red: 0.78, green: 1.0, blue: 0.0)
    static let limeDim = Color(red: 0.78, green: 1.0, blue: 0.0).opacity(0.18)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.62)
    static let textTertiary = Color(white: 0.42)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.2)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.36)
    /// Texto e iconos encima de un fondo verde lima.
    static let onLime = Color.black
    /// Líneas separadoras finas.
    static let separator = Color.white.opacity(0.07)

    // MARK: Colores con significado (solo cuando comunican algo; el lima sigue siendo el de las acciones)

    /// Racha: fuego naranja y ámbar.
    static let flame = Color(red: 1.0, green: 0.45, blue: 0.10)
    static let amber = Color(red: 1.0, green: 0.70, blue: 0.18)
    static let flameGradient = LinearGradient(colors: [amber, flame], startPoint: .top, endPoint: .bottom)

    /// Medallas, récords y logros: dorado (más profundo y cálido que el lima y que el amarillo de las calorías).
    static let gold = Color(red: 0.93, green: 0.72, blue: 0.26)
    static let goldDeep = Color(red: 0.72, green: 0.50, blue: 0.12)
    static let goldGradient = LinearGradient(colors: [Color(red: 1.0, green: 0.86, blue: 0.48), gold, goldDeep],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Calorías: azul (margen), amarillo dorado (te acercas), verde (objetivo ± margen), rojo (te has pasado).
    static let kcalPlenty = Color(red: 0.33, green: 0.62, blue: 1.0)
    static let kcalApproaching = Color(red: 1.0, green: 0.84, blue: 0.32)
    static let kcalOnTarget = Color(red: 0.25, green: 0.84, blue: 0.45)
    static let kcalOver = Color(red: 1.0, green: 0.33, blue: 0.33)

    static func color(_ status: CalorieStatus) -> Color {
        switch status {
        case .plenty: return kcalPlenty
        case .approaching: return kcalApproaching
        case .onTarget: return kcalOnTarget
        case .over: return kcalOver
        }
    }

    /// Macronutrientes: cada uno con su color fijo.
    static let protein = Color(red: 1.0, green: 0.50, blue: 0.42)   // coral
    static let carbs = Color(red: 0.66, green: 0.52, blue: 1.0)     // violeta
    static let fat = Color(red: 0.22, green: 0.84, blue: 0.80)      // turquesa

    /// Días de descanso: gris azulado discreto.
    static let rest = Color(red: 0.55, green: 0.63, blue: 0.75)

    /// Espacio libre al final de cada pantalla para poder leer lo último sin que lo tape la barra de pestañas.
    static let bottomBreathingRoom: CGFloat = 56

    static let cornerRadius: CGFloat = 18
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Fondo oscuro común para todas las pantallas.
    func screenBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }
}

struct LimeButtonStyle: ButtonStyle {
    var filled = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(filled ? Theme.onLime : Theme.lime)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(filled ? Theme.lime : Theme.limeDim)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
