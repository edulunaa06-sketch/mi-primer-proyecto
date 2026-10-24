import SwiftUI
import SwiftData

/// Perfil: datos físicos, cálculo de calorías y ajuste manual.
struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Bindable var profile: UserProfile

    @State private var age = ""
    @State private var height = ""
    @State private var weight = ""
    @State private var manualCalories = ""
    @State private var manualProtein = ""
    @State private var manualCarbs = ""
    @State private var manualFat = ""
    @State private var savedMessage = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    dataCard
                    activityCard
                    calculatedCard
                    manualCard
                    saveButton
                    footer
                }
                .padding(Theme.Spacing.screen)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle("Perfil")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear(perform: loadFields)
    }

    // MARK: - Secciones

    private var dataCard: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "Tus datos")
            HStack(spacing: 12) {
                NumberField(title: "Edad", text: $age, unit: "años", keyboard: .numberPad)
                NumberField(title: "Altura", text: $height, unit: "cm")
            }
            NumberField(title: "Peso", text: $weight, unit: "kg")
            ChipPicker(title: "Sexo", options: Sex.allCases, label: \.label, selection: $profile.sex)
        }
        .card()
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChipPicker(title: "Nivel de actividad",
                       options: ActivityLevel.allCases,
                       label: \.label,
                       selection: $profile.activity,
                       vertical: true)
            ChipPicker(title: "Objetivo",
                       options: Goal.allCases,
                       label: \.label,
                       selection: $profile.goal,
                       vertical: true)
        }
        .card()
    }

    private var calculatedCard: some View {
        let calculated = profile.calculatedTargets
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Cálculo automático")
            Text("Mifflin-St Jeor por tu factor de actividad\(profile.goal == .loseFat ? ", menos 400 kcal por el déficit" : "").")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
            HStack {
                StatTile(title: "Basal", value: Formatters.kcal(profile.bmr), unit: "kcal")
                StatTile(title: "Gasto total", value: Formatters.kcal(profile.tdee), unit: "kcal")
            }
            Divider().background(Theme.separator)
            HStack {
                StatTile(title: "Calorías", value: Formatters.kcal(calculated.calories), unit: "kcal", color: Theme.accent)
                StatTile(title: "Proteína", value: Formatters.grams(calculated.protein), unit: "g")
            }
            HStack {
                StatTile(title: "Carbos", value: Formatters.grams(calculated.carbs), unit: "g")
                StatTile(title: "Grasa", value: Formatters.grams(calculated.fat), unit: "g")
            }
        }
        .card()
    }

    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $profile.manualOverride) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ajuste manual")
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.text)
                    Text("Usa tus números en Inicio y en los menús.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.accent)

            if profile.manualOverride {
                HStack(spacing: 12) {
                    NumberField(title: "Calorías", text: $manualCalories, unit: "kcal", keyboard: .numberPad)
                    NumberField(title: "Proteína", text: $manualProtein, unit: "g", keyboard: .numberPad)
                }
                HStack(spacing: 12) {
                    NumberField(title: "Carbos", text: $manualCarbs, unit: "g", keyboard: .numberPad)
                    NumberField(title: "Grasa", text: $manualFat, unit: "g", keyboard: .numberPad)
                }
                Button("Copiar los del cálculo") {
                    let calculated = profile.calculatedTargets
                    manualCalories = Formatters.kcal(calculated.calories)
                    manualProtein = Formatters.grams(calculated.protein)
                    manualCarbs = Formatters.grams(calculated.carbs)
                    manualFat = Formatters.grams(calculated.fat)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .card()
    }

    private var saveButton: some View {
        VStack(spacing: 10) {
            Button("Guardar", action: save)
                .buttonStyle(PrimaryButtonStyle())
            if savedMessage {
                Text("Guardado. Los menús se ajustarán a estos números.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.success)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                BoltLogo(size: 16)
                Text("NOW OR NEVER")
                    .font(Theme.overline)
                    .kerning(1.6)
                    .foregroundStyle(Theme.textTertiary)
            }
            Text("Si cambias el peso aquí, también se guarda en Progreso.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Datos

    private func loadFields() {
        age = String(profile.age)
        height = Formatters.weight(profile.heightCm)
        weight = Formatters.weight(profile.weightKg)
        manualCalories = Formatters.kcal(profile.manualCalories)
        manualProtein = Formatters.grams(profile.manualProtein)
        manualCarbs = Formatters.grams(profile.manualCarbs)
        manualFat = Formatters.grams(profile.manualFat)
    }

    private func save() {
        if let value = Int(age.trimmingCharacters(in: .whitespaces)), (10...99).contains(value) {
            profile.age = value
        }
        if let value = Formatters.parse(height), value > 100 {
            profile.heightCm = value
        }
        if let value = Formatters.parse(weight), value > 25 {
            let changed = abs(value - profile.weightKg) > 0.01
            profile.weightKg = value
            if changed {
                // El peso del perfil también cuenta como registro de Progreso.
                PlanService.saveWeight(value, on: .now, context: context)
            }
        }
        if let value = Formatters.parse(manualCalories) { profile.manualCalories = value }
        if let value = Formatters.parse(manualProtein) { profile.manualProtein = value }
        if let value = Formatters.parse(manualCarbs) { profile.manualCarbs = value }
        if let value = Formatters.parse(manualFat) { profile.manualFat = value }

        try? context.save()
        loadFields()

        withAnimation { savedMessage = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { savedMessage = false }
        }
    }
}

#Preview {
    ProfileView(profile: SampleData.profile)
        .modelContainer(SampleData.container)
        .preferredColorScheme(.dark)
}
