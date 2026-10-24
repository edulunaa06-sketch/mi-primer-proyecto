import SwiftUI
import UIKit

/// Campo de texto oscuro con título y unidad, pensado para números.
struct NumberField: View {
    let title: String
    @Binding var text: String
    var unit: String? = nil
    var keyboard: UIKeyboardType = .decimalPad
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(Theme.overline)
                .kerning(1.1)
                .foregroundStyle(Theme.textTertiary)

            HStack(spacing: 6) {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboard)
                    .font(Theme.number(19))
                    .foregroundStyle(Theme.text)
                    .tint(Theme.accent)
                if let unit {
                    Text(unit)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.cardElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
    }
}

/// Campo de texto normal (nombres de comidas, notas...).
struct TextFieldRow: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(Theme.overline)
                .kerning(1.1)
                .foregroundStyle(Theme.textTertiary)

            TextField(placeholder, text: $text)
                .font(Theme.body)
                .foregroundStyle(Theme.text)
                .tint(Theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Theme.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
    }
}

/// Selector en píldoras amarillas para enums cortos.
struct ChipPicker<T: Hashable & Identifiable>: View {
    let title: String
    let options: [T]
    let label: (T) -> String
    @Binding var selection: T
    /// Si las opciones son largas, se apilan en vertical.
    var vertical: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(Theme.overline)
                .kerning(1.1)
                .foregroundStyle(Theme.textTertiary)

            if vertical {
                VStack(spacing: 8) {
                    ForEach(options) { option in
                        chip(option, fullWidth: true)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(options) { option in
                        chip(option, fullWidth: true)
                    }
                }
            }
        }
    }

    private func chip(_ option: T, fullWidth: Bool) -> some View {
        let isSelected = option == selection
        return Button {
            selection = option
        } label: {
            Text(label(option))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? Color.black : Theme.textSecondary)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.vertical, 11)
                .padding(.horizontal, 12)
                .background(isSelected ? Theme.accent : Theme.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Vista de apoyo para la preview.
private struct FormControlsPreview: View {
    @State private var weight = "74,5"
    @State private var sex: Sex = .male
    @State private var goal: Goal = .loseFat

    var body: some View {
        VStack(spacing: 18) {
            NumberField(title: "Peso", text: $weight, unit: "kg")
            ChipPicker(title: "Sexo", options: Sex.allCases, label: \.label, selection: $sex)
            ChipPicker(title: "Objetivo", options: Goal.allCases, label: \.label, selection: $goal, vertical: true)
        }
        .padding()
        .frame(maxHeight: .infinity)
        .screenBackground()
    }
}

#Preview {
    FormControlsPreview()
        .preferredColorScheme(.dark)
}
