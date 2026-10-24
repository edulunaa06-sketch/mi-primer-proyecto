import SwiftUI
import SwiftData

/// Pantalla de bienvenida: pide los datos antes de entrar en la app.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context

    @State private var age = "17"
    @State private var sex: Sex = .male
    @State private var height = "175"
    @State private var weight = "70"
    @State private var activity: ActivityLevel = .moderate
    @State private var goal: Goal = .loseFat

    private var isValid: Bool {
        guard let ageValue = Int(age.trimmingCharacters(in: .whitespaces)),
              let heightValue = Formatters.parse(height),
              let weightValue = Formatters.parse(weight) else { return false }
        return (10...99).contains(ageValue) && heightValue > 100 && weightValue > 25
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                header

                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        NumberField(title: "Edad", text: $age, unit: "años", keyboard: .numberPad)
                        NumberField(title: "Altura", text: $height, unit: "cm")
                    }
                    NumberField(title: "Peso", text: $weight, unit: "kg")
                    ChipPicker(title: "Sexo", options: Sex.allCases, label: \.label, selection: $sex)
                }
                .card()

                ChipPicker(title: "Nivel de actividad",
                           options: ActivityLevel.allCases,
                           label: \.label,
                           selection: $activity,
                           vertical: true)
                    .card()

                ChipPicker(title: "Objetivo",
                           options: Goal.allCases,
                           label: \.label,
                           selection: $goal,
                           vertical: true)
                    .card()

                if let preview = previewTargets {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Tu objetivo diario")
                        HStack {
                            StatTile(title: "Calorías", value: Formatters.kcal(preview.calories), unit: "kcal", color: Theme.accent)
                            StatTile(title: "Proteína", value: Formatters.grams(preview.protein), unit: "g")
                        }
                        HStack {
                            StatTile(title: "Carbos", value: Formatters.grams(preview.carbs), unit: "g")
                            StatTile(title: "Grasa", value: Formatters.grams(preview.fat), unit: "g")
                        }
                        Text("Podrás cambiarlo a mano en Perfil cuando quieras.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .card()
                }

                Button("Empezar", action: createProfile)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!isValid)
                    .opacity(isValid ? 1 : 0.45)
                    .padding(.top, 4)
            }
            .padding(Theme.Spacing.screen)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            BoltLogo(size: 46)
            Text("NOW OR NEVER")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .kerning(-0.5)
                .foregroundStyle(Theme.text)
            Text("Cuéntame cómo estás ahora para calcular tus calorías y montarte los menús.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 30)
    }

    private var previewTargets: NutritionTargets? {
        guard let ageValue = Int(age.trimmingCharacters(in: .whitespaces)),
              let heightValue = Formatters.parse(height),
              let weightValue = Formatters.parse(weight),
              isValid else { return nil }
        let profile = UserProfile(age: ageValue,
                                  sex: sex,
                                  heightCm: heightValue,
                                  weightKg: weightValue,
                                  activity: activity,
                                  goal: goal)
        return profile.calculatedTargets
    }

    private func createProfile() {
        guard let ageValue = Int(age.trimmingCharacters(in: .whitespaces)),
              let heightValue = Formatters.parse(height),
              let weightValue = Formatters.parse(weight) else { return }

        let profile = UserProfile(age: ageValue,
                                  sex: sex,
                                  heightCm: heightValue,
                                  weightKg: weightValue,
                                  activity: activity,
                                  goal: goal)
        let targets = profile.calculatedTargets
        profile.manualCalories = targets.calories
        profile.manualProtein = targets.protein
        profile.manualCarbs = targets.carbs
        profile.manualFat = targets.fat
        context.insert(profile)

        PlanService.seedRoutineIfNeeded(context: context)
        PlanService.saveWeight(weightValue, on: .now, context: context)
        try? context.save()
    }
}

#Preview {
    OnboardingView()
        .modelContainer(SampleData.emptyContainer)
        .preferredColorScheme(.dark)
}
