import SwiftData
import SwiftUI

/// Hoja para registrar un pesaje (fecha, peso y cintura opcional).
struct WeightEntrySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var weight: Double?
    @State private var waist: Double?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Fecha", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    HStack {
                        Text("Peso (kg)")
                        Spacer()
                        DecimalField(placeholder: "0,0", value: $weight, width: 110)
                    }
                    HStack {
                        Text("Cintura (cm)")
                        Spacer()
                        DecimalField(placeholder: "Opcional", value: $waist, width: 110)
                    }
                } footer: {
                    Text("Pésate en condiciones similares (por ejemplo, en ayunas). Las variaciones de un día a otro suelen deberse a agua y digestión, no a cambios confirmados de grasa.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(Theme.danger) }
                }
            }
            .screenBackground()
            .navigationTitle("Registrar peso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }.disabled(weight == nil)
                }
            }
        }
    }

    private func save() {
        guard let weight, (20...400).contains(weight) else {
            errorMessage = "Introduce un peso válido entre 20 y 400 kg."
            return
        }
        if let waist, !(30...250).contains(waist) {
            errorMessage = "Introduce una cintura válida entre 30 y 250 cm o déjala vacía."
            return
        }
        if DataStore.addWeight(weight, waist: waist, date: date, in: context) {
            dismiss()
        } else {
            errorMessage = "Ya existe un registro idéntico para ese día."
        }
    }
}
