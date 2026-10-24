import SwiftData
import SwiftUI
import UIKit

/// «Mis calorías»: pones las kcal que quieres comer y los macros se rellenan solos (puedes retocarlos).
/// Guardar las deja fijas (manuales): ni el perfil ni un pesaje nuevo las vuelven a cambiar.
struct TargetsEditorSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var loaded = false
    @State private var error: String?

    private var settings: UserSettings { DataStore.settings(context) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    row("Calorías", "kcal", $kcal)
                        .onChange(of: kcal) { _, value in fill(from: value) }
                        .accessibilityIdentifier("targets.kcal")
                    row("Proteínas", "g", $protein)
                    row("Carbohidratos", "g", $carbs)
                    row("Grasas", "g", $fat)
                } header: {
                    Text("Lo que quiero comer al día")
                } footer: {
                    Text("Al cambiar las calorías, los macros se recalculan (proteína según tu objetivo y tu peso, grasa 25 %, el resto carbohidratos). Puedes retocarlos antes de guardar.")
                }
                Section {
                    Picker("Margen del objetivo", selection: Binding(get: { settings.kcalMargin },
                                                                     set: { settings.kcalMargin = $0; try? context.save() })) {
                        ForEach([50.0, 100, 150, 200], id: \.self) { Text("± \(NumberFormat.integer($0)) kcal").tag($0) }
                    }
                    .accessibilityIdentifier("targets.margin")
                } footer: {
                    Text("Si acabas el día a menos de esta diferencia de tu objetivo (por arriba o por abajo), cuenta como cumplido y se ve en verde. Se guarda al momento.")
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(Theme.danger)
                }
                Section {
                    Button("Guardar mis calorías") { save() }
                        .disabled((kcal ?? 0) < 800)
                } footer: {
                    Text(settings.autoTargets
                         ? "Ahora mismo se calculan solas con tu perfil. Al guardar, se quedan fijas en lo que pongas."
                         : "Son tuyas: no cambian aunque edites el perfil o te peses.")
                }
                if !settings.autoTargets {
                    Section {
                        Button("Volver a calcularlas con mi perfil") { automatic() }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Mis calorías")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Listo") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                kcal = settings.kcalTarget
                protein = settings.proteinTarget
                carbs = settings.carbsTarget
                fat = settings.fatTarget
            }
        }
    }

    private func row(_ title: String, _ unit: String, _ value: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            DecimalField(placeholder: "0", value: value, width: 90)
            Text(unit).foregroundStyle(Theme.textSecondary).frame(width: 34, alignment: .leading)
        }
    }

    private func fill(from value: Double?) {
        guard let value, value >= 800, value <= 6000, value != settings.kcalTarget || protein == nil else { return }
        let m = EnergyCalculator.macros(forKcal: value, weightKg: weights.first?.weightKg, goal: settings.goal)
        protein = m.protein
        carbs = m.carbs
        fat = m.fat
    }

    private func save() {
        guard let kcal, kcal >= 800, kcal <= 6000 else { error = "Pon entre 800 y 6.000 kcal."; return }
        let m = EnergyCalculator.macros(forKcal: kcal, weightKg: weights.first?.weightKg, goal: settings.goal)
        let s = settings
        s.kcalTarget = kcal.rounded()
        s.proteinTarget = (protein ?? m.protein).rounded()
        s.carbsTarget = (carbs ?? m.carbs).rounded()
        s.fatTarget = (fat ?? m.fat).rounded()
        s.autoTargets = false
        try? context.save()
        dismiss()
    }

    private func automatic() {
        let s = settings
        s.autoTargets = true
        if DataStore.recalculateTargets(context) == nil {
            s.autoTargets = false
            error = "Completa tu perfil (Ajustes › Perfil personal) para calcularlas solas."
            return
        }
        dismiss()
    }
}
