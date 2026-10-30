import SwiftUI
import UIKit

/// Lenguaje visual de Now or Never: luz, blanco y azul.
///
/// La app es clara: el papel es casi blanco, las tarjetas son blancas de verdad y lo que las
/// separa del fondo es un filo finísimo y una sombra muy baja, no un relleno gris. El color
/// se gasta solo donde hace falta: el azul índigo para lo que puedes tocar y el azul profundo
/// para acompañarlo.
///
/// Sobre blanco, un color claro no se lee. Por eso los azules, los verdes y los rojos de aquí
/// son más profundos que los de un tema oscuro aunque se llamen igual: el que manda es el
/// contraste contra el papel, no lo bonito que se vea el color suelto.
///
/// Los colores que SIGNIFICAN algo no se tocan de nombre: los macros, el agua, el verde de
/// «vas bien» y el rojo de «te has pasado» siguen diciendo lo mismo. Y el oro sigue siendo oro,
/// porque una medalla de otro color no es una medalla.
enum DS {
    // MARK: Papel y superficies

    /// El papel. Blanco con un suspiro de azul: el blanco puro del todo, a pantalla completa,
    /// deslumbra, y así las tarjetas blancas se recortan encima sin necesitar un borde grueso.
    static let bg = Color(red: 0.961, green: 0.969, blue: 0.984)
    /// Las tarjetas: blanco de verdad, para que se levanten del papel.
    static let surface = Color.white
    /// Un escalón por encima: lo seleccionado, lo relleno, el fondo de un campo.
    static let surfaceHi = Color(red: 0.33, green: 0.27, blue: 0.88).opacity(0.07)
    /// El filo de las tarjetas: azul muy bajado, no gris. Un gris neutro sobre papel azulado
    /// se ve sucio.
    static let stroke = Color(red: 0.09, green: 0.13, blue: 0.28).opacity(0.11)
    /// La sombra de las tarjetas. Azulada y bajísima: en claro, una sombra negra ensucia.
    static let shadow = Color(red: 0.08, green: 0.12, blue: 0.30).opacity(0.07)
    /// La sombra de lo que flota de verdad por encima del contenido (la barra de pestañas).
    static let shadowLift = Color(red: 0.08, green: 0.12, blue: 0.30).opacity(0.16)

    // Barra flotante de pestañas (medidas reales de TabBar, para que nada quede debajo)
    static let tabBarButton: CGFloat = 56
    static let tabBarPaddingV: CGFloat = 8
    static let tabBarBottom: CGFloat = 6
    /// Alto de la cápsula más su separación del borde de abajo.
    static let tabBarHeight: CGFloat = tabBarButton + tabBarPaddingV * 2 + tabBarBottom
    /// Hueco que se reserva al final de cada pantalla. Va holgado a propósito: mejor que sobre
    /// un poco de aire a que la última tarjeta quede medio tapada por la barra.
    static let tabBarSpace: CGFloat = tabBarHeight + 60

    // MARK: Texto

    /// Casi negro, con una gota de azul para que case con el papel. El negro puro sobre blanco
    /// cansa la vista.
    static let text = Color(red: 0.055, green: 0.075, blue: 0.137)
    static let text2 = Color(red: 0.055, green: 0.075, blue: 0.137).opacity(0.64)
    static let text3 = Color(red: 0.055, green: 0.075, blue: 0.137).opacity(0.42)

    // MARK: La marca: azul

    /// El azul de la marca. Más profundo que el de la versión oscura: sobre blanco tiene que
    /// aguantar texto pequeño encima.
    static let indigo = Color(red: 0.33, green: 0.27, blue: 0.88)
    /// El azul del otro extremo del degradado. Profundo a propósito: el cian claro de antes,
    /// sobre blanco, no se leía.
    static let cyan = Color(red: 0.05, green: 0.52, blue: 0.72)
    /// El cian claro, para rellenos, resplandores y adornos. Nunca detrás de un texto.
    static let sky = Color(red: 0.42, green: 0.80, blue: 0.95)
    /// Gris azulado: para lo apagado, lo que descansa y lo que aún no has ganado.
    static let steel = Color(red: 0.42, green: 0.46, blue: 0.55)

    static let accent = indigo
    /// Lo que va ENCIMA del azul de la marca. Blanco: los dos extremos del degradado son
    /// suficientemente oscuros para que se lea.
    static let onAccent = Color.white
    /// Degradado de la marca: índigo → azul profundo.
    static let brand = LinearGradient(colors: [indigo, cyan], startPoint: .leading, endPoint: .trailing)
    static let brandDiagonal = LinearGradient(colors: [indigo, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: Estados. Aquí el color es información, no decoración.

    static let good = Color(red: 0.06, green: 0.62, blue: 0.38)
    static let warn = Color(red: 0.78, green: 0.50, blue: 0.02)
    static let bad = Color(red: 0.84, green: 0.16, blue: 0.24)

    /// Medallas y récords: oro de verdad, del profundo, que sobre papel blanco se vea.
    static let gold = Color(red: 0.68, green: 0.49, blue: 0.06)
    static let goldGradient = LinearGradient(colors: [Color(red: 0.85, green: 0.66, blue: 0.20), gold,
                                                      Color(red: 0.49, green: 0.33, blue: 0.02)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
    static let fire = LinearGradient(colors: [Color(red: 0.95, green: 0.60, blue: 0.05),
                                              Color(red: 0.88, green: 0.26, blue: 0.06)],
                                     startPoint: .top, endPoint: .bottom)

    // MARK: Macros y agua

    static let protein = Color(red: 0.84, green: 0.20, blue: 0.36)
    static let carbs = Color(red: 0.80, green: 0.48, blue: 0.04)
    static let fat = Color(red: 0.05, green: 0.56, blue: 0.53)
    static let water = Color(red: 0.11, green: 0.45, blue: 0.90)

    static let radius: CGFloat = 22

    /// Los mismos cuatro colores que `Theme.color`, para que el anillo de calorías y las barras
    /// no digan cosas distintas en pantallas distintas.
    static func color(_ status: CalorieStatus) -> AnyShapeStyle {
        switch status {
        case .plenty: return AnyShapeStyle(steel)
        case .approaching: return AnyShapeStyle(warn)
        case .onTarget: return AnyShapeStyle(good)
        case .over: return AnyShapeStyle(bad)
        }
    }

    static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - Tipografía

extension Font {
    /// Títulos anchos y potentes.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight).width(.expanded)
    }
    /// Números grandes.
    static func number(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

// MARK: - Fondo

/// El fondo, sin extenderlo a los bordes de la pantalla. Aparte porque la entrada necesita
/// dibujarlo por su cuenta.
///
/// Papel casi blanco con dos lavados de color muy flojos: índigo arriba a la izquierda y cian
/// abajo a la derecha. Tan suaves que no se ven como manchas, solo quitan al blanco la
/// sensación de folio. Estático: no cuesta nada dibujarlo.
struct AtlasBackdrop: View {
    var body: some View {
        ZStack {
            DS.bg
            RadialGradient(colors: [DS.indigo.opacity(0.10), .clear],
                           center: .init(x: 0.12, y: -0.05), startRadius: 0, endRadius: 440)
            RadialGradient(colors: [DS.sky.opacity(0.16), .clear],
                           center: .init(x: 1.0, y: 1.0), startRadius: 0, endRadius: 400)
        }
    }
}

/// El fondo de todas las pantallas.
struct AtlasBackground: View {
    var body: some View {
        AtlasBackdrop().ignoresSafeArea()
    }
}


extension View {
    func atlasScreen() -> some View {
        scrollContentBackground(.hidden)
            .tabBarRoom()
            .background(AtlasBackground())
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// Reserva sitio al final para la barra flotante, de modo que lo último de la pantalla
    /// se pueda subir por encima de ella y leerse entero. Va dentro del NavigationStack:
    /// puesto por fuera, la pila de navegación no lo traslada a sus pantallas.
    func tabBarRoom() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: DS.tabBarSpace) }
    }

    /// Tarjeta: blanca sobre el papel, con un filo finísimo y una sombra muy baja.
    /// En claro, lo que levanta una tarjeta del fondo es la sombra; un relleno gris solo
    /// la ensucia. Sin desenfoques: no frenan el desplazamiento.
    func glass(padding: CGFloat = 16, radius: CGFloat = DS.radius) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(DS.surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(DS.stroke, lineWidth: 1))
            .shadow(color: DS.shadow, radius: 10, y: 4)
    }
}

// MARK: - Botones

struct PrimaryButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 15 : 17, weight: .bold))
            // Blanco sobre el azul: los dos extremos del degradado son oscuros de sobra.
            .foregroundStyle(DS.onAccent)
            .padding(.vertical, compact ? 10 : 15)
            .padding(.horizontal, compact ? 16 : 20)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(Capsule().fill(DS.brand))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.28), lineWidth: 1))
            .shadow(color: DS.indigo.opacity(configuration.isPressed ? 0.14 : 0.32), radius: configuration.isPressed ? 6 : 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 14 : 16, weight: .semibold))
            .foregroundStyle(DS.text)
            .padding(.vertical, compact ? 9 : 13)
            .padding(.horizontal, compact ? 14 : 18)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(Capsule().fill(DS.surfaceHi))
            .overlay(Capsule().strokeBorder(DS.stroke, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static var primaryCompact: PrimaryButtonStyle { PrimaryButtonStyle(compact: true) }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static var secondaryCompact: SecondaryButtonStyle { SecondaryButtonStyle(compact: true) }
}

// MARK: - Componentes

struct SectionTitle: View {
    let title: String
    var trailing: String?
    var action: (() -> Void)?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .heavy).width(.expanded))
                .tracking(1.5)
                .foregroundStyle(DS.text2)
            Spacer()
            if let trailing, let action {
                Button(trailing, action: action)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.accent)
            }
        }
    }
}

/// Anillo de progreso con degradado y punta redondeada.
struct Ring<S: ShapeStyle>: View {
    let progress: Double
    var lineWidth: CGFloat = 14
    let style: S
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(DS.surfaceHi, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(shown, 0), 1))
                .stroke(style, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // Si te pasas del 100 %, una segunda vuelta más fina.
            if shown > 1 {
                Circle()
                    .trim(from: 0, to: min(shown - 1, 1))
                    .stroke(DS.bad.opacity(0.9), style: StrokeStyle(lineWidth: lineWidth * 0.45, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .onAppear { withAnimation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.85)) { shown = progress } }
        .onChange(of: progress) { _, p in withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8)) { shown = p } }
    }
}

struct MacroBar: View {
    let name: String
    let value: Double
    let target: Double
    let color: Color

    var body: some View {
        let left = target - value
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.text2)
                Spacer()
                Text("\(Int(value.rounded()))")
                    .font(.number(15)).foregroundStyle(DS.text)
                + Text(" / \(Int(target.rounded())) g").font(.system(size: 11, weight: .medium)).foregroundStyle(DS.text3)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule().fill(color)
                        .frame(width: geo.size.width * min(max(target > 0 ? value / target : 0, 0), 1))
                        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: value)
                }
            }
            .frame(height: 7)
            Text(left >= 0 ? "Quedan \(Int(left.rounded())) g" : "+\(Int((-left).rounded())) g de más")
                .font(.system(size: 10, weight: left >= 0 ? .medium : .bold))
                .foregroundStyle(left >= 0 ? DS.text3 : DS.text)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var unit: String = ""
    var symbol: String
    var tint: Color = DS.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(tint)
                .frame(width: 30, height: 30).background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.number(24)).contentTransition(.numericText())
                    .lineLimit(1).minimumScaleFactor(0.6)
                if !unit.isEmpty { Text(unit).font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.text3) }
            }
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(DS.text2)
        }
        .glass(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

struct EmptyHint: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 30, weight: .semibold)).foregroundStyle(DS.brandDiagonal)
            Text(title).font(.headline)
            Text(message).font(.footnote).foregroundStyle(DS.text2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }
}

/// Campo numérico con coma decimal, vinculado a un Double opcional.
struct NumberField: View {
    let placeholder: String
    @Binding var value: Double?
    var decimals = true
    var width: CGFloat? = nil
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(decimals ? .decimalPad : .numberPad)
            .multilineTextAlignment(.center)
            .font(.number(17, .semibold))
            .padding(.vertical, 9).padding(.horizontal, 6)
            .frame(width: width)
            .background(DS.surfaceHi, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(focused ? DS.accent.opacity(0.75) : .clear, lineWidth: 1.5))
            .focused($focused)
            .onAppear { text = Self.format(value, decimals: decimals) }
            .onChange(of: value) { _, v in if !focused { text = Self.format(v, decimals: decimals) } }
            .onChange(of: text) { _, t in
                let trimmed = t.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { if value != nil { value = nil } }
                else if let p = NumberFormat.parseDecimal(trimmed), p >= 0, p != value { value = p }
            }
    }

    static func format(_ v: Double?, decimals: Bool) -> String {
        guard let v else { return "" }
        return decimals ? NumberFormat.oneDecimal(v) : String(Int(v.rounded()))
    }
}

/// Cierra el teclado.
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
