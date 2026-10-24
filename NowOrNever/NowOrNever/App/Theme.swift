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
