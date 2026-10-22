import SwiftData
import SwiftUI

struct NutritionView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \MenuPlan.number) private var plans: [MenuPlan]
    @Query private var selections: [DayPlanSelection]
    @Query private var settingsList: [UserSettings]
    @Query private var allRecords: [MealRecord]

    @State private var day = Date()
    @State private var editingItem: MealItem?
    @State private var addingTo: MealTemplate?

    private var settings: UserSettings? { settingsList.first }
    private var dayKey: String { DateUtils.dayKey(day) }
    private var records: [MealRecord] { allRecords.filter { $0.dayKey == dayKey } }
    private var plan: MenuPlan? { DataStore.plan(for: day, plans: plans, selections: selections, settings: settings) }
    private var consumed: NutritionValues { NutritionMath.sum(records.map(\.values)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dayPicker
                    if let plan {
                        planPicker(plan)
                        consumedCard
                        planTotalsCard(plan)
                        ForEach(plan.sortedMeals) { meal in
                            MealCard(
                                meal: meal,
                                isCompleted: records.contains { $0.mealTypeRaw == meal.mealTypeRaw },
                                onToggle: { toggle(meal, plan: plan) },
                                onEditItem: { editingItem = $0 },
                                onAddItem: { addingTo = meal }
                            )
                        }
                        InfoBanner(text: "Menús y valores de EJEMPLO: cifras aproximadas por 100 g, no un plan calculado clínicamente. Revisa cada alimento con su etiqueta en el Catálogo.")
                    } else {
                        EmptyStateView(symbol: "fork.knife", title: "Sin menús", message: "No se ha podido cargar el catálogo de ejemplo. Crea alimentos en el Catálogo.")
                            .card()
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle("Nutrición")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink { MenuPlansView() } label: { Label("Los 9 menús", systemImage: "list.bullet.rectangle") }
                        NavigationLink { FoodCatalogView() } label: { Label("Catálogo de alimentos", systemImage: "carrot") }
                        NavigationLink { NutritionHistoryView() } label: { Label("Historial de comidas", systemImage: "calendar") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $editingItem) { item in
                MealItemEditor(item: item) { refreshRecord(for: item.meal) }
            }
            .sheet(item: $addingTo) { meal in
                AddFoodSheet(meal: meal) { refreshRecord(for: meal) }
            }
        }
    }

    private var dayPicker: some View {
        HStack {
            Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            DatePicker("Día", selection: $day, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
            Spacer()
            Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                .disabled(DateUtils.calendar.isDateInToday(day))
        }
        .font(.headline)
        .card(padding: 10)
    }

    private func shiftDay(_ delta: Int) {
        if let d = DateUtils.calendar.date(byAdding: .day, value: delta, to: day), d <= Date() { day = d }
    }

    private func planPicker(_ current: MenuPlan) -> some View {
        Menu {
            ForEach(plans) { p in
                Button {
                    DataStore.select(plan: p, for: day, in: context)
                } label: {
                    if p.id == current.id { Label("Menú \(p.number) · \(p.name)", systemImage: "checkmark") }
                    else { Text("Menú \(p.number) · \(p.name)") }
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MENÚ DEL DÍA").font(.caption2.weight(.bold)).foregroundStyle(Theme.lime)
                    Text("Menú \(current.number) · \(current.name)").font(.headline).foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").foregroundStyle(Theme.textSecondary)
            }
            .card(padding: 14)
        }
    }

    private var consumedCard: some View {
        let target = settings
        let kcalFraction = NutritionMath.progress(consumed: consumed.kcal, target: target?.kcalTarget ?? 0)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ProgressRing(fraction: kcalFraction, size: 80)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Consumido (comidas marcadas)").font(.headline)
                    Text("\(NumberFormat.integer(consumed.kcal)) de \(NumberFormat.integer(target?.kcalTarget ?? 0)) kcal")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(records.count) de 4 comidas completadas")
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                }
            }
            MacroRow(name: "Proteínas", consumed: consumed.protein, target: target?.proteinTarget ?? 0)
            MacroRow(name: "Carbohidratos", consumed: consumed.carbs, target: target?.carbsTarget ?? 0)
            MacroRow(name: "Grasas", consumed: consumed.fat, target: target?.fatTarget ?? 0)
        }
        .card()
    }

    private func planTotalsCard(_ plan: MenuPlan) -> some View {
        let t = plan.totals
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Total del menú (calculado)", subtitle: "Suma automática de todos los ingredientes")
            HStack {
                totalStat("kcal", NumberFormat.integer(t.kcal))
                totalStat("Prot.", NumberFormat.integer(t.protein) + " g")
                totalStat("Carb.", NumberFormat.integer(t.carbs) + " g")
                totalStat("Grasa", NumberFormat.integer(t.fat) + " g")
            }
            if plan.hasProvisionalValues {
                Text("Incluye valores provisionales (marcados con ⚠︎).")
                    .font(.caption2).foregroundStyle(Theme.warning)
            }
        }
        .card()
    }

    private func totalStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text("≈ " + value).font(.subheadline.weight(.bold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func toggle(_ meal: MealTemplate, plan: MenuPlan) {
        let done = records.contains { $0.mealTypeRaw == meal.mealTypeRaw }
        DataStore.setMeal(meal, planName: "Menú \(plan.number) · \(plan.name)", completed: !done, on: day, in: context)
    }

    /// Si la comida ya estaba marcada en el día visible, actualiza su registro con los nuevos gramos.
    private func refreshRecord(for meal: MealTemplate?) {
        guard let meal else { return }
        if let record = records.first(where: { $0.mealTypeRaw == meal.mealTypeRaw }) {
            let v = meal.totals
            record.kcal = v.kcal
            record.protein = v.protein
            record.carbs = v.carbs
            record.fat = v.fat
        }
        try? context.save()
    }
}

struct MealCard: View {
    let meal: MealTemplate
    let isCompleted: Bool
    var showsCompletion = true
    let onToggle: () -> Void
    let onEditItem: (MealItem) -> Void
    let onAddItem: () -> Void

    var body: some View {
        let totals = meal.totals
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: meal.mealType.symbol).foregroundStyle(Theme.lime)
                Text(meal.mealType.label).font(.headline)
                Spacer()
                if showsCompletion {
                Button(action: onToggle) {
                    HStack(spacing: 6) {
                        Text(isCompleted ? "Hecha" : "Marcar").font(.caption.weight(.bold))
                        CheckCircle(isOn: isCompleted, size: 24)
                    }
                    .foregroundStyle(isCompleted ? Theme.lime : Theme.textSecondary)
                }
                .buttonStyle(.plain)
                }
            }
            ForEach(meal.sortedItems) { item in
                Button { onEditItem(item) } label: { IngredientRow(item: item) }
                    .buttonStyle(.plain)
            }
            Button(action: onAddItem) {
                Label("Añadir ingrediente", systemImage: "plus")
                    .font(.caption.weight(.semibold))
            }
            Divider().overlay(Color.white.opacity(0.08))
            HStack {
                Text("Subtotal").font(.subheadline.weight(.semibold))
                Spacer()
                Text("≈ \(NumberFormat.integer(totals.kcal)) kcal")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.lime)
            }
            Text("P \(NumberFormat.oneDecimal(totals.protein)) g · C \(NumberFormat.oneDecimal(totals.carbs)) g · G \(NumberFormat.oneDecimal(totals.fat)) g")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .card()
    }
}

struct IngredientRow: View {
    let item: MealItem

    var body: some View {
        let v = item.values
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.food?.name ?? "Alimento eliminado")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                    if item.food?.isProvisional ?? true {
                        Text("⚠︎").font(.caption).foregroundStyle(Theme.warning)
                            .accessibilityLabel("Valor provisional")
                    }
                }
                Text("\(NumberFormat.oneDecimal(item.grams)) g · \(item.food?.basis.label.lowercased() ?? "")")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                if item.food?.macrosKnown ?? false {
                    Text("P \(NumberFormat.oneDecimal(v.protein)) · C \(NumberFormat.oneDecimal(v.carbs)) · G \(NumberFormat.oneDecimal(v.fat))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
            Text("≈ \(NumberFormat.integer(v.kcal)) kcal")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
