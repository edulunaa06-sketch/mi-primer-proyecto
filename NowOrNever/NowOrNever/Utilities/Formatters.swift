import Foundation

/// Números con el formato que usa la app (sin decimales inútiles y con coma).
enum Formatters {

    private static let decimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = DateHelper.locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    /// Calorías redondeadas: "1.842".
    static func kcal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = DateHelper.locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value.rounded())) ?? "0"
    }

    /// Gramos de macro: "148 g" (se añade la unidad fuera).
    static func grams(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

    /// Peso corporal o de la barra: "72,5".
    static func weight(_ value: Double) -> String {
        decimal.string(from: NSNumber(value: value)) ?? "0"
    }

    /// Diferencia con signo: "-3,4".
    static func signedWeight(_ value: Double) -> String {
        let text = weight(abs(value))
        if value > 0.05 { return "+\(text)" }
        if value < -0.05 { return "-\(text)" }
        return text
    }

    /// Distancia: "5,2 km".
    static func distance(_ value: Double) -> String {
        "\(weight(value)) km"
    }

    /// Tiempo de carrera: "28 min".
    static func minutes(_ value: Double) -> String {
        "\(Int(value.rounded())) min"
    }

    /// Convierte lo que el usuario escribe ("72,5") en número.
    static func parse(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }
}
