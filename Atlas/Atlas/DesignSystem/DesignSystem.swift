import SwiftUI
import UIKit

/// Lenguaje visual de ATLAS: negro profundo con un resplandor índigo, tarjetas de cristal,
/// degradado índigo → cian para las acciones y tipografía ancha para los títulos.
enum DS {
    // Fondo y superficies
    static let bg = Color(red: 0.024, green: 0.027, blue: 0.039)
    static let surface = Color.white.opacity(0.045)
    static let surfaceHi = Color.white.opacity(0.08)
    static let stroke = Color.white.opacity(0.08)

    // Texto
    static let text = Color.white
    static let text2 = Color.white.opacity(0.62)
    static let text3 = Color.white.opacity(0.38)

    // Marca
    static let indigo = Color(red: 0.45, green: 0.38, blue: 1.0)
    static let cyan = Color(red: 0.16, green: 0.83, blue: 0.95)
    static let accent = indigo
    static let brand = LinearGradient(colors: [indigo, cyan], startPoint: .leading, endPoint: .trailing)
    static let brandDiagonal = LinearGradient(colors: [indigo, cyan], startPoint: .topLeading, endPoint: .bottomTrailing)

    // Estados
    static let good = Color(red: 0.20, green: 0.83, blue: 0.55)
    static let warn = Color(red: 0.99, green: 0.75, blue: 0.20)
    static let bad = Color(red: 0.98, green: 0.40, blue: 0.43)
    static let gold = Color(red: 0.97, green: 0.78, blue: 0.32)
    static let goldGradient = LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.55), gold, Color(red: 0.8, green: 0.55, blue: 0.12)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
    static let fire = LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.2), Color(red: 1, green: 0.38, blue: 0.12)],
                                     startPoint: .top, endPoint: .bottom)

    // Macros
    static let protein = Color(red: 1.0, green: 0.48, blue: 0.54)
    static let carbs = Color(red: 1.0, green: 0.71, blue: 0.28)
    static let fat = Color(red: 0.31, green: 0.82, blue: 0.77)
    static let water = Color(red: 0.30, green: 0.62, blue: 1.0)

    static let radius: CGFloat = 22

    static func color(_ status: CalorieStatus) -> AnyShapeStyle {
        switch status {
        case .plenty, .approaching: return AnyShapeStyle(brandDiagonal)
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

/// Fondo con dos resplandores suaves (índigo arriba, cian abajo). Estático: no cuesta nada dibujarlo.
struct AtlasBackground: View {
    var body: some View {
        ZStack {
            DS.bg
            RadialGradient(colors: [DS.indigo.opacity(0.28), .clear], center: .init(x: 0.15, y: -0.05), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [DS.cyan.opacity(0.10), .clear], center: .init(x: 1.0, y: 1.0), startRadius: 0, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

extension View {
    func atlasScreen() -> some View {
        scrollContentBackground(.hidden)
            .background(AtlasBackground())
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// Tarjeta de cristal.
    func glass(padding: CGFloat = 16, radius: CGFloat = DS.radius) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Sin desenfoques: un relleno translúcido es igual de bonito y no frena el desplazamiento.
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(DS.surface))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(DS.stroke, lineWidth: 1))
    }
}

// MARK: - Botones

struct PrimaryButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 15 : 17, weight: .bold))
            .foregroundStyle(.white)
            .padding(.vertical, compact ? 10 : 15)
            .padding(.horizontal, compact ? 16 : 20)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(Capsule().fill(DS.brand))
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
            .shadow(color: DS.indigo.opacity(configuration.isPressed ? 0.2 : 0.45), radius: configuration.isPressed ? 6 : 14, y: 6)
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
                    .foregroundStyle(DS.cyan)
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
    var tint: Color = DS.cyan

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
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(focused ? DS.cyan.opacity(0.7) : .clear, lineWidth: 1.5))
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
