import SwiftData
import SwiftUI

struct NutritionView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: \MenuPlan.number) private var plans: [MenuPlan]
    @Query private var selections: [DayPlanSelection]
    @Query private var choices: [DayMealChoice]
    @Query private var settingsList: [UserSettings]
    @Query private var allRecords: [MealRecord]

    @State private var day = Date()
    @State private var editingItem: MealItem?
    @State private var addingTo: MealTemplate?
    @State private var swapping: MealType?
    @State private var showBuilder = false

    private var settings: UserSettings? { settingsList.first }
    private var dayKey: String { DateUtils.dayKey(day) }
    private var records: [MealRecord] { allRecords.filter { $0.dayKey == dayKey } }
    private var plan: MenuPlan? { DataStore.plan(for: day, plans: plans, selections: selections, settings: settings) }
    private var consumed: NutritionValues { NutritionMath.sum(records.map(\.values)) }
    private var meals: [ResolvedMeal] {
        DataStore.resolvedMeals(for: day, plans: plans, selections: selections, choices: choices, settings: settings)
    }
    private var dailyTargets: NutritionValues {
        NutritionValues(kcal: settings?.kcalTarget ?? 0, protein: settings?.proteinTarget ?? 0,
                        carbs: settings?.carbsTarget ?? 0, fat: settings?.fatTarget ?? 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dayPicker
                    if let plan {
                        planPicker(plan)
                        Button {
                            showBuilder = true
                        } label: {
                            Label("Elegir mis comidas paso a paso", systemImage: "square.stack.3d.up.fill")
                        }
                        .buttonStyle(LimeButtonStyle())
                        consumedCard
                        dayTotalsCard
                        ForEach(meals, id: \.type) { meal in
                            MealCard(
                                meal: meal.template,
                                isCompleted: records.contains { $0.mealTypeRaw == meal.type.rawValue },
                                factor: meal.factor,
                                sourceLabel: meal.isChoice || meal.plan.id != plan.id ? meal.sourceName : nil,
                                onToggle: { toggle(meal) },
                                onEditItem: { editingItem = $0 },
                                onAddItem: { addingTo = meal.template },
                                onSwap: { swapping = meal.type },
                                onReset: resetAction(for: meal)
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
                MealItemEditor(item: item) { refreshRecords() }
            }
            .sheet(item: $addingTo) { meal in
                AddFoodSheet(meal: meal) { refreshRecords() }
            }
            .sheet(item: $swapping) { type in
                MealChooserSheet(
                    type: type,
                    target: MealPlanner.target(for: type, daily: dailyTargets, fixed: fixedValues(except: type)),
                    dayTotalsWithoutThis: NutritionMath.sum(meals.filter { $0.type != type }.map(\.totals)),
                    daily: dailyTargets,
                    candidates: DataStore.candidates(for: type, plans: plans),
                    subtitle: "Opciones que encajan con tus otras tres comidas de hoy"
                ) { option in
                    apply(option, type: type)
                }
            }
            .sheet(isPresented: $showBuilder) {
                DayBuilderSheet(daily: dailyTargets, plans: plans) { picks in
                    for (type, option) in picks { apply(option, type: type) }
                }
            }
            #if DEBUG
            .task {
                if ProcessInfo.processInfo.arguments.contains("-NNMealBuilder") { showBuilder = true }
            }
            #endif
        }
    }

    // MARK: Elección de comidas

    private func fixedValues(except type: MealType) -> [MealType: NutritionValues] {
        Dictionary(uniqueKeysWithValues: meals.filter { $0.type != type }.map { ($0.type, $0.totals) })
    }

    private func apply(_ option: MealPlanner.Option, type: MealType) {
        guard let id = UUID(uuidString: option.id) else { return }
        DataStore.choose(type, planID: id, factor: option.factor, on: day, in: context)
        refreshRecords()
    }

    private func resetAction(for meal: ResolvedMeal) -> (() -> Void)? {
        guard meal.isChoice else { return nil }
        return { reset(meal.type) }
    }

    private func reset(_ type: MealType) {
        DataStore.clearChoice(type, on: day, in: context)
        refreshRecords()
    }

    private func toggle(_ meal: ResolvedMeal) {
        let done = records.contains { $0.mealTypeRaw == meal.type.rawValue }
        DataStore.setMeal(meal.type, values: meal.totals, planName: meal.sourceName, completed: !done, on: day, in: context)
    }

    /// Las comidas ya marcadas del día visible se actualizan con su composición actual.
    private func refreshRecords() {
        for meal in meals where records.contains(where: { $0.mealTypeRaw == meal.type.rawValue }) {
            DataStore.setMeal(meal.type, values: meal.totals, planName: meal.sourceName, completed: true, on: day, in: context)
        }
    }

    // MARK: Tarjetas

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
                    refreshRecords()
                } label: {
                    if p.id == current.id { Label("Menú \(p.number) · \(p.name)", systemImage: "checkmark") }
                    else { Text("Menú \(p.number) · \(p.name)") }
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MENÚ BASE DEL DÍA").font(.caption2.weight(.bold)).foregroundStyle(Theme.lime)
                    Text("Menú \(current.number) · \(current.name)").font(.headline).foregroundStyle(Theme.textPrimary)
                    if choices.contains(where: { $0.dayKey == dayKey }) {
                        Text("Con comidas cambiadas por ti").font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
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

    private var dayTotalsCard: some View {
        let t = NutritionMath.sum(meals.map(\.totals))
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Total del día planificado", subtitle: "Suma automática de las 4 comidas · objetivo debajo")
            HStack {
                totalStat("kcal", NumberFormat.integer(t.kcal), target: dailyTargets.kcal)
                totalStat("Prot.", NumberFormat.integer(t.protein) + " g", target: dailyTargets.protein)
                totalStat("Carb.", NumberFormat.integer(t.carbs) + " g", target: dailyTargets.carbs)
                totalStat("Grasa", NumberFormat.integer(t.fat) + " g", target: dailyTargets.fat)
            }
            Text("Ajuste con tus objetivos: \(NumberFormat.percent(MealPlanner.fit(t, to: dailyTargets)))")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.lime)
            if meals.contains(where: { $0.template.hasProvisionalValues }) {
                Text("Incluye valores provisionales (marcados con ⚠︎).")
                    .font(.caption2).foregroundStyle(Theme.warning)
            }
        }
        .card()
    }

    private func totalStat(_ label: String, _ value: String, target: Double) -> some View {
        VStack(spacing: 2) {
            Text("≈ " + value).font(.subheadline.weight(.bold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
            Text("/ \(NumberFormat.integer(target))").font(.caption2.monospacedDigit()).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MealCard: View {
    let meal: MealTemplate
    let isCompleted: Bool
    var showsCompletion = true
    /// Ración: 1 = gramos del menú; otro valor = ración ajustada (solo lectura en el día).
    var factor: Double = 1
    /// Menú de origen cuando la comida no es la del menú base del día.
    var sourceLabel: String?
    let onToggle: () -> Void
    let onEditItem: (MealItem) -> Void
    let onAddItem: () -> Void
    var onSwap: (() -> Void)?
    var onReset: (() -> Void)?

    private var isScaled: Bool { abs(factor - 1) > 0.001 }

    private var lines: [(item: MealItem, grams: Double, values: NutritionValues)] {
        meal.sortedItems.map { item in
            let g = MealPlanner.grams(item.grams, factor: factor)
            let v = item.food.map { NutritionMath.values(per100: $0.per100, grams: g) } ?? .zero
            return (item, g, v)
        }
    }

    var body: some View {
        let rows = lines
        let totals = NutritionMath.sum(rows.map(\.values))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: meal.mealType.symbol).foregroundStyle(Theme.lime)
                VStack(alignment: .leading, spacing: 1) {
                    Text(meal.mealType.label).font(.headline)
                    if let sourceLabel {
                        Text(sourceLabel + (isScaled ? " · ración al \(Int((factor * 100).rounded())) %" : ""))
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
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
            ForEach(rows, id: \.item.persistentModelID) { row in
                if isScaled {
                    IngredientRow(item: row.item, grams: row.grams, values: row.values)
                } else {
                    Button { onEditItem(row.item) } label: { IngredientRow(item: row.item, grams: row.grams, values: row.values) }
                        .buttonStyle(.plain)
                }
            }
            if isScaled {
                Text("Ración ajustada a tus macros. Para editar los ingredientes base ve a Nutrición › ⋯ › Los 9 menús.")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            } else {
                Button(action: onAddItem) {
                    Label("Añadir ingrediente", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                }
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
            if onSwap != nil || onReset != nil {
                HStack(spacing: 10) {
                    if let onSwap {
                        Button(action: onSwap) {
                            Label("Cambiar \(meal.mealType.label.lowercased())", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(LimeButtonStyle(filled: false))
                    }
                    if let onReset {
                        Button("Volver al menú", action: onReset)
                            .font(.caption.weight(.semibold))
                    }
                }
            }
        }
        .card()
    }
}

struct IngredientRow: View {
    let item: MealItem
    var grams: Double? = nil
    var values: NutritionValues? = nil

    var body: some View {
        let g = grams ?? item.grams
        let v = values ?? item.values
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
                Text("\(NumberFormat.oneDecimal(g)) g · \(item.food?.basis.label.lowercased() ?? "")")
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
