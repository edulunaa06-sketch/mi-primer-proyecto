import SwiftUI

/// Línea compacta con las kcal y los macros de un plato.
struct MacroChips: View {
    let totals: MacroTotals
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            chip(Formatters.kcal(totals.calories), unit: "kcal", color: Theme.accent, strong: true)
            chip(Formatters.grams(totals.protein), unit: "P", color: Theme.protein)
            chip(Formatters.grams(totals.carbs), unit: "C", color: Theme.carbs)
            chip(Formatters.grams(totals.fat), unit: "G", color: Theme.fat)
        }
    }

    private func chip(_ value: String, unit: String, color: Color, strong: Bool = false) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.system(size: strong ? 14 : 13, weight: .heavy, design: .rounded))
                .foregroundStyle(strong ? color : Theme.text)
            Text(unit)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(strong ? color.opacity(0.8) : Theme.textTertiary)
        }
    }
}

/// Dato suelto con título arriba y número grande debajo.
struct StatTile: View {
    let title: String
    let value: String
    var unit: String? = nil
    var color: Color = Theme.text

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(Theme.overline)
                .kerning(1.1)
                .foregroundStyle(Theme.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Theme.number(22))
                    .foregroundStyle(color)
                if let unit {
                    Text(unit)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    VStack(spacing: 20) {
        MacroChips(totals: MacroTotals(calories: 540, protein: 38, carbs: 55, fat: 16))
        HStack {
            StatTile(title: "Inicial", value: "81,2", unit: "kg")
            StatTile(title: "Actual", value: "74,5", unit: "kg")
            StatTile(title: "Diferencia", value: "-6,7", unit: "kg", color: Theme.accent)
        }
        .card()
    }
    .padding()
    .frame(maxHeight: .infinity)
    .screenBackground()
}
