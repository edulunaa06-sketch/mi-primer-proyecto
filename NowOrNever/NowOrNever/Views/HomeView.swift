import SwiftUI
import SwiftData

/// Inicio: cuántas calorías quedan hoy y cómo va el día de un vistazo.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Bindable var profile: UserProfile

    @Query private var dayPlans: [DayPlan]
    @Query private var manualFoods: [ManualFood]
    @Query private var workoutDays: [WorkoutDayPlan]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]

    private var today: Date { DateHelper.startOfDay() }

    private var todayPlan: DayPlan? {
        dayPlans.first { DateHelper.isSameDay($0.date, today) }
    }

    private var todayManualFoods: [ManualFood] {
        manualFoods.filter { DateHelper.isSameDay($0.date, today) }
    }

    /// Lo comido hoy: comidas marcadas más lo apuntado a mano.
    private var eaten: MacroTotals {
        var total = todayPlan?.eatenTotals ?? .zero
        for food in todayManualFoods { total += food.totals }
        return total
    }

    private var targets: NutritionTargets { profile.targets }
    private var remaining: Double { targets.calories - eaten.calories }

    private var todayWorkout: WorkoutDayPlan? {
        workoutDays.first { $0.weekday == DateHelper.weekdayIndex() }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.section) {
                    ringCard
                    macrosCard
                    dayCard
                }
                .padding(Theme.Spacing.screen)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Inicio")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    BoltLogo(size: 20)
                }
            }
        }
        .onAppear {
            PlanService.seedRoutineIfNeeded(context: context)
            PlanService.dayPlan(for: .now, profile: profile, context: context)
        }
    }

    // MARK: - Anillo

    private var ringCard: some View {
        VStack(spacing: 14) {
            CalorieRing(eaten: eaten.calories, target: targets.calories)
                .padding(.top, 6)

            if remaining < 0 {
                Text("Te has pasado \(Formatters.kcal(-remaining)) kcal")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.danger)
            } else {
                Text("Llevas \(Formatters.kcal(eaten.calories)) kcal hoy")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: 18)
    }

    // MARK: - Macros

    private var macrosCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Macros de hoy")
            MacroBars(eaten: eaten, targets: targets)
        }
        .card()
    }

    // MARK: - Resumen del día

    private var dayCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Tu día")

            workoutRow
            Divider().background(Theme.separator)
            nextMealRow
            Divider().background(Theme.separator)
            weightRow
        }
        .card()
    }

    private var workoutRow: some View {
        let day = todayWorkout
        return InfoRow(icon: day?.kind.icon ?? "dumbbell.fill",
                       title: "Entreno de hoy",
                       value: day?.shortTitle ?? "Sin rutina",
                       detail: workoutDetail(for: day))
    }

    private func workoutDetail(for day: WorkoutDayPlan?) -> String? {
        guard let day else { return nil }
        if day.kind == .rest { return day.note.isEmpty ? "Día libre" : day.note }
        var parts: [String] = []
        if day.kind.hasExercises { parts.append("\(day.exercises.count) ejercicios") }
        if day.kind.hasCardio { parts.append("carrera") }
        return parts.joined(separator: " · ").capitalizedFirst
    }

    private var nextMealRow: some View {
        let meal = todayPlan?.nextMeal
        return InfoRow(icon: meal?.type.icon ?? "checkmark.circle.fill",
                       title: "Siguiente comida",
                       value: meal.map { "\($0.type.label): \($0.name)" } ?? "Menú completado",
                       detail: meal.map { "\(Formatters.kcal($0.calories)) kcal · \(Formatters.grams($0.protein)) g de proteína" })
    }

    private var weightRow: some View {
        let last = weights.last
        let first = weights.first
        let difference: Double? = {
            guard let last, let first, weights.count > 1 else { return nil }
            return last.kg - first.kg
        }()
        return InfoRow(icon: "scalemass.fill",
                       title: "Último peso",
                       value: last.map { "\(Formatters.weight($0.kg)) kg" } ?? "Sin registros",
                       detail: difference.map { "\(Formatters.signedWeight($0)) kg desde el primero" }
                               ?? last.map { DateHelper.friendlyName($0.date) },
                       valueColor: Theme.text,
                       detailColor: (difference ?? 0) < 0 ? Theme.accent : Theme.textSecondary)
    }
}

/// Fila del resumen: icono amarillo, título pequeño y dato grande.
struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    var detail: String? = nil
    var valueColor: Color = Theme.text
    var detailColor: Color = Theme.textSecondary

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.accentMuted)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(Theme.overline)
                    .kerning(1.1)
                    .foregroundStyle(Theme.textTertiary)
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(valueColor)
                if let detail {
                    Text(detail)
                        .font(Theme.caption)
                        .foregroundStyle(detailColor)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    HomeView(profile: SampleData.profile)
        .modelContainer(SampleData.container)
        .preferredColorScheme(.dark)
}
