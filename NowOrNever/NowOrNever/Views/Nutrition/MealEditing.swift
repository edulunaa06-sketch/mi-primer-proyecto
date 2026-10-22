import SwiftData
import SwiftUI

/// Edición de los gramos de un ingrediente con recálculo inmediato de kcal y macros.
struct MealItemEditor: View {
    @Bindable var item: MealItem
    var onSave: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var grams: Double?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                if let food = item.food {
                    Section {
                        LabeledContent("Alimento", value: food.name)
                        LabeledContent("Cómo pesarlo", value: food.basis.label)
                        HStack {
                            Text("Gramos")
                            Spacer()
                            DecimalField(placeholder: "g", value: $grams, width: 110)
                        }
                    } footer: {
                        Text("Pesa el alimento \(food.basis.label.lowercased()) en la báscula de cocina.")
                    }
                    Section("Resultado (aprox.)") {
                        let v = NutritionMath.values(per100: food.per100, grams: grams ?? 0)
                        LabeledContent("Energía", value: "≈ \(NumberFormat.integer(v.kcal)) kcal")
                        if food.macrosKnown {
                            LabeledContent("Proteínas", value: "\(NumberFormat.oneDecimal(v.protein)) g")
                            LabeledContent("Carbohidratos", value: "\(NumberFormat.oneDecimal(v.carbs)) g")
                            LabeledContent("Grasas", value: "\(NumberFormat.oneDecimal(v.fat)) g")
                        } else {
                            Text("Macros no disponibles para este alimento.").foregroundStyle(Theme.textSecondary)
                        }
                        if food.isProvisional {
                            Text("⚠︎ Valor provisional: revísalo en el Catálogo con la etiqueta del producto.")
                                .font(.footnote).foregroundStyle(Theme.warning)
                        }
                    }
                } else {
                    Text("Este ingrediente ya no tiene un alimento asociado.")
                }
                Section {
                    Button("Quitar ingrediente de la comida", role: .destructive) { confirmDelete = true }
                }
            }
            .screenBackground()
            .navigationTitle("Ingrediente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        if let grams, grams > 0 { item.grams = grams }
                        try? context.save()
                        onSave()
                        dismiss()
                    }
                    .disabled((grams ?? 0) <= 0)
                }
            }
            .confirmationDialog("¿Quitar este ingrediente del menú?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Quitar", role: .destructive) {
                    let meal = item.meal
                    context.delete(item)
                    try? context.save()
                    if meal != nil { onSave() }
                    dismiss()
                }
            }
            .onAppear { grams = item.grams }
        }
    }
}

/// Añadir un alimento del catálogo a una comida.
struct AddFoodSheet: View {
    let meal: MealTemplate
    var onSave: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodItem.name) private var foods: [FoodItem]
    @State private var search = ""
    @State private var selected: FoodItem?
    @State private var grams: Double? = 100

    private var filtered: [FoodItem] {
        search.isEmpty ? foods : foods.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let selected {
                    Section("Cantidad") {
                        LabeledContent("Alimento", value: selected.name)
                        HStack {
                            Text("Gramos (\(selected.basis.label.lowercased()))")
                            Spacer()
                            DecimalField(placeholder: "g", value: $grams, width: 100)
                        }
                        let v = NutritionMath.values(per100: selected.per100, grams: grams ?? 0)
                        Text("≈ \(NumberFormat.integer(v.kcal)) kcal").foregroundStyle(Theme.lime)
                    }
                    .listRowBackground(Theme.card)
                }
                Section("Catálogo") {
                    ForEach(filtered) { food in
                        Button {
                            selected = food
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(food.name).foregroundStyle(Theme.textPrimary)
                                    Text("\(NumberFormat.integer(food.kcalPer100)) kcal/100 g · \(food.basis.label.lowercased())")
                                        .font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                if selected?.id == food.id { Image(systemName: "checkmark").foregroundStyle(Theme.lime) }
                            }
                        }
                    }
                }
                .listRowBackground(Theme.card)
            }
            .searchable(text: $search, prompt: "Buscar alimento")
            .screenBackground()
            .navigationTitle("Añadir a \(meal.mealType.label.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Añadir") {
                        guard let selected, let grams, grams > 0 else { return }
                        let nextOrder = (meal.items.map(\.order).max() ?? -1) + 1
                        let item = MealItem(grams: grams, order: nextOrder, food: selected)
                        context.insert(item)
                        item.meal = meal
                        try? context.save()
                        onSave()
                        dismiss()
                    }
                    .disabled(selected == nil || (grams ?? 0) <= 0)
                }
            }
        }
    }
}

/// Lista de los nueve menús con sus totales calculados.
struct MenuPlansView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MenuPlan.number) private var allPlans: [MenuPlan]
    private var plans: [MenuPlan] { allPlans.filter { !$0.isLibrary } }
    private var ideas: [MenuPlan] { allPlans.filter(\.isLibrary) }
    @Query private var settingsList: [UserSettings]
    @State private var confirmScaleAll = false
    @State private var resultMessage: String?

    private var target: Double { settingsList.first?.kcalTarget ?? 0 }

    var body: some View {
        List {
            Section {
                LabeledContent("Tu objetivo", value: "\(NumberFormat.integer(target)) kcal")
                if let s = settingsList.first {
                    Text("P \(NumberFormat.integer(s.proteinTarget)) g · C \(NumberFormat.integer(s.carbsTarget)) g · G \(NumberFormat.integer(s.fatTarget)) g · \(s.autoTargets ? "calculado desde tu perfil" : "manual")")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Button("Ajustar los 9 menús a \(NumberFormat.integer(target)) kcal") { confirmScaleAll = true }
                    .disabled(target <= 0 || plans.isEmpty)
                if let resultMessage {
                    Text(resultMessage).font(.footnote).foregroundStyle(Theme.lime)
                }
            } header: {
                Text("Ajustar a mis requerimientos")
            } footer: {
                Text("Escala proporcionalmente los gramos de cada ingrediente para que el total del día se acerque a tus calorías objetivo (redondeando a cantidades pesables). Las proporciones entre proteínas, carbohidratos y grasas de cada menú se mantienen; compáralas abajo con tus objetivos.")
            }
            .listRowBackground(Theme.card)

            Section {
                ForEach(plans) { plan in
                    NavigationLink {
                        MenuPlanDetailView(plan: plan)
                    } label: {
                        let t = plan.totals
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Menú \(plan.number) · \(plan.name)").font(.subheadline.weight(.semibold))
                                if settingsList.first?.defaultPlanID == plan.id {
                                    Text("PREDETERMINADO").font(.caption2.weight(.bold)).foregroundStyle(Theme.lime)
                                }
                            }
                            Text("≈ \(NumberFormat.integer(t.kcal)) kcal · P \(NumberFormat.integer(t.protein)) · C \(NumberFormat.integer(t.carbs)) · G \(NumberFormat.integer(t.fat))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                            if target > 0 {
                                let diff = (t.kcal - target) / target
                                Text(abs(diff) <= 0.05 ? "Dentro de ±5 % de tu objetivo" : "\(diff > 0 ? "+" : "")\(NumberFormat.percent(diff)) respecto a tu objetivo")
                                    .font(.caption2)
                                    .foregroundStyle(abs(diff) <= 0.05 ? Theme.lime : Theme.warning)
                            }
                        }
                    }
                }
            } footer: {
                Text("Totales calculados automáticamente a partir de los ingredientes. Menús de ejemplo con valores aproximados.")
            }
            .listRowBackground(Theme.card)

            ForEach(MealType.allCases) { type in
                let list = ideas.filter { $0.meal(type) != nil }
                if !list.isEmpty {
                    Section {
                        ForEach(list) { idea in
                            NavigationLink {
                                MenuPlanDetailView(plan: idea)
                            } label: {
                                let t = idea.totals
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(idea.name).font(.subheadline.weight(.semibold))
                                    Text("≈ \(NumberFormat.integer(t.kcal)) kcal · P \(NumberFormat.integer(t.protein)) · C \(NumberFormat.integer(t.carbs)) · G \(NumberFormat.integer(t.fat))")
                                        .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    } header: {
                        Text("Ideas de \(type.label.lowercased()) (\(list.count))")
                    } footer: {
                        if type == .dinner {
                            Text("Las ideas aparecen como opciones al elegir cada comida, con la ración ajustada a lo que te queda del día. Puedes editar sus ingredientes y gramos.")
                        }
                    }
                    .listRowBackground(Theme.card)
                }
            }
        }
        .screenBackground()
        .navigationTitle("Menús e ideas")
        .confirmationDialog("¿Ajustar los gramos de los 9 menús a \(NumberFormat.integer(target)) kcal?", isPresented: $confirmScaleAll, titleVisibility: .visible) {
            Button("Ajustar menús") {
                let done = plans.compactMap { DataStore.scale($0, toKcal: target, in: context) }.count
                resultMessage = "\(done) menús ajustados. Revisa los gramos antes de pesar."
            }
        } message: {
            Text("Se modificarán los gramos de todos los ingredientes. Las comidas ya marcadas en días anteriores no cambian.")
        }
    }
}

struct MenuPlanDetailView: View {
    @Bindable var plan: MenuPlan
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @State private var editingItem: MealItem?
    @State private var addingTo: MealTemplate?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Nombre del menú", text: $plan.name)
                        .font(.title3.bold())
                    Text(plan.note).font(.footnote).foregroundStyle(Theme.textSecondary)
                    let t = plan.totals
                    Text("Total diario ≈ \(NumberFormat.integer(t.kcal)) kcal · P \(NumberFormat.oneDecimal(t.protein)) g · C \(NumberFormat.oneDecimal(t.carbs)) g · G \(NumberFormat.oneDecimal(t.fat)) g")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.lime)
                    if let settings = settingsList.first, !plan.isLibrary {
                        Button(settings.defaultPlanID == plan.id ? "Menú predeterminado ✓" : "Usar como menú predeterminado") {
                            settings.defaultPlanID = plan.id
                            try? context.save()
                        }
                        .buttonStyle(LimeButtonStyle(filled: settings.defaultPlanID != plan.id))
                        if settings.kcalTarget > 0, abs(t.kcal - settings.kcalTarget) / settings.kcalTarget > 0.02 {
                            Button("Ajustar este menú a \(NumberFormat.integer(settings.kcalTarget)) kcal") {
                                DataStore.scale(plan, toKcal: settings.kcalTarget, in: context)
                            }
                            .buttonStyle(LimeButtonStyle(filled: false))
                        }
                    }
                }
                .card()
                ForEach(plan.sortedMeals) { meal in
                    // En la vista de modelo no se marcan comidas (eso se hace en el día concreto).
                    MealCard(meal: meal, isCompleted: false, showsCompletion: false, onToggle: {},
                             onEditItem: { editingItem = $0 }, onAddItem: { addingTo = meal })
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(plan.isLibrary ? "Idea" : "Menú \(plan.number)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingItem) { MealItemEditor(item: $0) {} }
        .sheet(item: $addingTo) { AddFoodSheet(meal: $0) {} }
        .onDisappear { try? context.save() }
    }
}
