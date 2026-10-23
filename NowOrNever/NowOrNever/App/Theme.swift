import SwiftUI
import UIKit

/// Paleta y estilos compartidos. Modo oscuro: fondo carbón, verde lima y texto blanco.
/// Modo claro: fondo gris muy claro, tarjetas blancas, verde más oscuro (para que se lea) y texto negro.
/// Cada color cambia solo según el modo (Ajustes › Apariencia).
enum Theme {
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> UIColor {
        UIColor(red: r, green: g, blue: b, alpha: a)
    }

    static let background = dynamic(light: rgb(0.95, 0.95, 0.96), dark: rgb(0.05, 0.05, 0.06))
    static let card = dynamic(light: rgb(1, 1, 1), dark: rgb(0.11, 0.11, 0.12))
    static let cardRaised = dynamic(light: rgb(0.91, 0.91, 0.93), dark: rgb(0.16, 0.16, 0.17))
    static let lime = dynamic(light: rgb(0.33, 0.56, 0.0), dark: rgb(0.78, 1.0, 0.0))
    static let limeDim = dynamic(light: rgb(0.33, 0.56, 0.0, 0.14), dark: rgb(0.78, 1.0, 0.0, 0.18))
    static let textPrimary = dynamic(light: rgb(0.07, 0.07, 0.08), dark: rgb(1, 1, 1))
    static let textSecondary = dynamic(light: rgb(0.36, 0.36, 0.38), dark: rgb(0.62, 0.62, 0.62))
    static let textTertiary = dynamic(light: rgb(0.54, 0.54, 0.56), dark: rgb(0.42, 0.42, 0.42))
    static let warning = dynamic(light: rgb(0.80, 0.45, 0.0), dark: rgb(1.0, 0.72, 0.2))
    static let danger = dynamic(light: rgb(0.82, 0.16, 0.16), dark: rgb(1.0, 0.36, 0.36))
    /// Texto e iconos encima de un fondo verde: negro sobre el lima del modo oscuro, blanco sobre el verde del claro.
    static let onLime = dynamic(light: rgb(1, 1, 1), dark: rgb(0, 0, 0))
    /// Líneas separadoras finas.
    static let separator = dynamic(light: rgb(0, 0, 0, 0.08), dark: rgb(1, 1, 1, 0.07))

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

/// Apariencia elegida en Ajustes: automática (la del iPhone), clara u oscura.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    static let storageKey = "app.appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Automático (como el iPhone)"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        }
    }

    /// nil = seguir el modo del iPhone.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
