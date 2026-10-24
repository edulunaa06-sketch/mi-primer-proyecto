import SwiftUI

/// Apuntar a mano algo que he comido fuera del menú.
struct ManualFoodSheet: View {
    @Environment(\.dismiss) private var dismiss

    let date: Date
    let onSave: (ManualFood) -> Void

    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && Formatters.parse(calories) != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TextFieldRow(title: "Qué has comido", text: $name, placeholder: "Bocadillo del bar")
                    NumberField(title: "Calorías", text: $calories, unit: "kcal", keyboard: .numberPad)
                    HStack(spacing: 12) {
                        NumberField(title: "Proteína", text: $protein, unit: "g")
                        NumberField(title: "Carbos", text: $carbs, unit: "g")
                        NumberField(title: "Grasa", text: $fat, unit: "g")
                    }

                    Button("Guardar", action: save)
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!isValid)
                        .opacity(isValid ? 1 : 0.45)
                        .padding(.top, 6)

                    Text("Se suma a \(DateHelper.friendlyName(date).lowercased()) y cuenta en Inicio al momento.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Theme.Spacing.screen)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle("Añadir manual")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
    }

    private func save() {
        guard let kcal = Formatters.parse(calories) else { return }
        let food = ManualFood(date: DateHelper.startOfDay(date),
                              name: name.trimmingCharacters(in: .whitespaces),
                              calories: kcal,
                              protein: Formatters.parse(protein) ?? 0,
                              carbs: Formatters.parse(carbs) ?? 0,
                              fat: Formatters.parse(fat) ?? 0)
        onSave(food)
        dismiss()
    }
}

#Preview {
    ManualFoodSheet(date: .now, onSave: { _ in })
        .preferredColorScheme(.dark)
}
