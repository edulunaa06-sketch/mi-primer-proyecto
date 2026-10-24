import SwiftUI

/// Colores, tipografías y estilos de "Now or Never".
/// Todo lo visual vive aquí para no repetirlo por el resto del código.
enum Theme {

    // MARK: - Colores

    /// Fondo negro puro.
    static let background = Color.black
    /// Tarjetas en gris muy oscuro.
    static let card = Color(red: 0.078, green: 0.078, blue: 0.078)      // #141414
    /// Un punto más claro, para elementos dentro de una tarjeta.
    static let cardElevated = Color(red: 0.125, green: 0.125, blue: 0.125) // #202020
    /// Amarillo intenso de acento.
    static let accent = Color(red: 1.0, green: 0.839, blue: 0.0)        // #FFD600
    /// Amarillo apagado, para fondos de pistas y rellenos suaves.
    static let accentMuted = Color(red: 1.0, green: 0.839, blue: 0.0).opacity(0.18)
    /// Texto principal.
    static let text = Color.white
    /// Texto secundario.
    static let textSecondary = Color(white: 0.68)
    /// Texto muy apagado.
    static let textTertiary = Color(white: 0.45)
    /// Rojo para avisos (pasarse de calorías).
    static let danger = Color(red: 1.0, green: 0.27, blue: 0.27)
    /// Verde discreto para confirmaciones.
    static let success = Color(red: 0.36, green: 0.86, blue: 0.47)
    /// Separadores.
    static let separator = Color(white: 0.17)

    // MARK: - Colores de macros

    static let protein = accent
    static let carbs = Color(red: 1.0, green: 0.60, blue: 0.0)
    static let fat = Color(red: 0.98, green: 0.92, blue: 0.55)

    // MARK: - Medidas

    enum Radius {
        static let card: CGFloat = 20
        static let control: CGFloat = 14
        static let pill: CGFloat = 999
    }

    enum Spacing {
        static let tight: CGFloat = 8
        static let normal: CGFloat = 14
        static let section: CGFloat = 22
        static let screen: CGFloat = 18
    }

    // MARK: - Tipografía

    /// Números grandes, condensados y agresivos (anillo de calorías, pesos...).
    static func hero(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }

    /// Título de pantalla.
    static let screenTitle = Font.system(size: 30, weight: .black, design: .rounded)
    /// Título de sección / tarjeta.
    static let sectionTitle = Font.system(size: 13, weight: .heavy, design: .rounded)
    /// Título dentro de una tarjeta.
    static let cardTitle = Font.system(size: 17, weight: .bold, design: .rounded)
    /// Texto normal.
    static let body = Font.system(size: 15, weight: .medium, design: .rounded)
    /// Texto pequeño.
    static let caption = Font.system(size: 13, weight: .medium, design: .rounded)
    /// Texto muy pequeño en mayúsculas.
    static let overline = Font.system(size: 11, weight: .heavy, design: .rounded)
    /// Números medianos en negrita.
    static func number(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }
}

// MARK: - Modificadores

/// Tarjeta estándar: gris muy oscuro, esquinas redondeadas y aire interior.
struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

extension View {
    /// Envuelve la vista en una tarjeta del tema.
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Fondo negro a pantalla completa.
    func screenBackground() -> some View {
        self.background(Theme.background.ignoresSafeArea())
    }
}

/// Encabezado de sección en amarillo y mayúsculas.
struct SectionHeader: View {
    let title: String
    var action: (() -> Void)?
    var actionTitle: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(Theme.sectionTitle)
                .kerning(1.4)
                .foregroundStyle(Theme.accent)
            Spacer()
            if let action, let actionTitle {
                Button(actionTitle, action: action)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// Botón principal amarillo.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Botón secundario: borde amarillo sobre fondo oscuro.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.cardElevated)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .stroke(Theme.accent.opacity(0.55), lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Etiqueta pequeña tipo píldora.
struct TagLabel: View {
    let text: String
    var color: Color = Theme.accent

    var body: some View {
        Text(text.uppercased())
            .font(Theme.overline)
            .kerning(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.16))
            .clipShape(Capsule())
    }
}

/// El rayo del logo, reutilizable en cabeceras y pantallas vacías.
struct BoltLogo: View {
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: size, weight: .black))
            .foregroundStyle(Theme.accent)
    }
}
