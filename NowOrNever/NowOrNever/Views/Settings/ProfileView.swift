import SwiftData
import SwiftUI
import UIKit

/// Perfil personal: peso, altura, edad, sexo, actividad y objetivo.
/// Calcula el gasto estimado (Mifflin-St Jeor) y, si se activa, ajusta kcal y macros automáticamente.
struct ProfileView: View {
    @Bindable var settings: UserSettings

    @Environment(\.modelContext) private var context
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    @State private var weight: Double?
    @State private var height: Double?
    @State private var age: Int?
    @State private var sex: BiologicalSex?
    @State private var activity: ActivityLevel = .moderate
    @State private var goal: FitnessGoal = .recomposition
    @State private var auto = true
    @State private var message: String?
    @State private var messageIsError = false
    @State private var loaded = false

    private var draft: BodyProfile? {
        guard let weight, let height, let age, let sex else { return nil }
        let p = BodyProfile(weightKg: weight, heightCm: height, age: age, sex: sex, activity: activity, goal: goal)
        return p.isValid ? p : nil
    }

    var body: some View {
        Form {
            Section {
                row("Peso (kg)") { DecimalField(placeholder: "kg", value: $weight, width: 100) }
                row("Altura (cm)") { DecimalField(placeholder: "cm", value: $height, width: 100) }
                row("Edad (años)") { IntField(placeholder: "años", value: $age, width: 100) }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sexo (lo usa la fórmula)")
                    Picker("Sexo", selection: $sex) {
                        ForEach(BiologicalSex.allCases) { Text($0.label).tag(BiologicalSex?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Datos personales")
            } footer: {
                Text(weights.first.map { "Último pesaje: \(NumberFormat.kg($0.weightKg)) kg (\(DateUtils.shortDate($0.date))). Si cambias el peso aquí se guarda como un pesaje nuevo de hoy." }
                     ?? "Aún no hay pesajes: el peso que indiques se guardará como tu primer registro.")
            }

            Section("Actividad física") {
                Picker("Nivel", selection: $activity) {
                    ForEach(ActivityLevel.allCases) { level in
                        VStack(alignment: .leading) {
                            Text(level.label)
                            Text(level.detail).font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        .tag(level)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section("Objetivo") {
                Picker("Objetivo", selection: $goal) {
                    ForEach(FitnessGoal.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section {
                if let draft {
                    let t = EnergyCalculator.targets(for: draft)
                    LabeledContent("Metabolismo basal", value: "\(NumberFormat.integer(t.bmr)) kcal")
                    LabeledContent("Gasto diario estimado", value: "\(NumberFormat.integer(t.tdee)) kcal")
                    LabeledContent("Calorías objetivo", value: "\(NumberFormat.integer(t.kcal)) kcal")
                        .foregroundStyle(Theme.lime)
                    LabeledContent("Proteínas", value: "\(NumberFormat.integer(t.protein)) g")
                    LabeledContent("Carbohidratos", value: "\(NumberFormat.integer(t.carbs)) g")
                    LabeledContent("Grasas", value: "\(NumberFormat.integer(t.fat)) g")
                } else {
                    Text("Completa peso, altura, edad y sexo con valores válidos para ver el cálculo.")
                        .foregroundStyle(Theme.textSecondary)
                }
            } header: {
                Text("Cálculo (Mifflin-St Jeor)")
            } footer: {
                Text("Basal = 10×peso + 6,25×altura − 5×edad + 5 (hombre) / −161 (mujer). Gasto = basal × factor de actividad (\(NumberFormat.oneDecimal(activity.factor))). Objetivo: −20 % perder grasa, +10 % ganar músculo, −10 % recomposición. Proteína \(Int(goal.proteinShare * 100)) % de las kcal (entre 1,6 y 2,4 g/kg), grasa 25 % de las kcal, carbohidratos el resto. Es una ESTIMACIÓN orientativa, no una pauta médica.")
            }

            Section {
                Toggle("Objetivos automáticos", isOn: $auto)
                Button("Guardar perfil") { save() }
                    .disabled(weight == nil && height == nil && age == nil && sex == nil)
                if let message {
                    Text(message).font(.footnote).foregroundStyle(messageIsError ? Theme.danger : Theme.lime)
                }
                NavigationLink("Ajustar los menús a mis calorías") { MenuPlansView() }
            } footer: {
                Text(auto
                     ? "Al guardar se aplican las kcal y macros calculadas, y se recalculan solas cada vez que cambies el perfil o registres un peso nuevo. Si editas los objetivos a mano en Ajustes, pasarán a ser manuales."
                     : "Objetivos manuales: el cálculo se muestra como referencia pero no cambia tus objetivos.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationTitle("Perfil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder field: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            field()
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        weight = weights.first?.weightKg
        height = settings.heightCm
        age = settings.age
        sex = settings.sex
        activity = settings.activity
        goal = settings.goal
        auto = settings.autoTargets || settings.heightCm == nil
    }

    private func save() {
        messageIsError = false
        if let height, !(120...230).contains(height) { return showError("Altura fuera de rango (120–230 cm).") }
        if let age, !(14...100).contains(age) { return showError("Edad fuera de rango (14–100 años).") }
        if let weight, !(30...300).contains(weight) { return showError("Peso fuera de rango (30–300 kg).") }

        settings.heightCm = height
        settings.age = age
        settings.sex = sex
        settings.activity = activity
        settings.goal = goal
        settings.autoTargets = auto
        try? context.save()

        // Un peso distinto del último se guarda como pesaje nuevo (queda en el historial).
        if let weight, abs(weight - (weights.first?.weightKg ?? -1)) >= 0.05 {
            DataStore.addWeight(weight, waist: nil, date: Date(), in: context)
        }

        if auto {
            if let t = DataStore.recalculateTargets(context) {
                message = "Perfil guardado. Objetivos: \(NumberFormat.integer(t.kcal)) kcal · P \(NumberFormat.integer(t.protein)) g · C \(NumberFormat.integer(t.carbs)) g · G \(NumberFormat.integer(t.fat)) g."
            } else {
                message = "Perfil guardado. Faltan datos para calcular los objetivos."
            }
        } else {
            message = "Perfil guardado. Tus objetivos manuales no se han modificado."
        }
    }

    private func showError(_ text: String) {
        messageIsError = true
        message = text
    }
}
