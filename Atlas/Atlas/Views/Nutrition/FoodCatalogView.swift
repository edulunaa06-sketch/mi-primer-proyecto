import SwiftData
import SwiftUI

/// Catálogo local editable de alimentos (valores por 100 g).
struct FoodCatalogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodItem.name) private var foods: [FoodItem]
    @State private var search = ""
    @State private var creating = false

    private var filtered: [FoodItem] {
        search.isEmpty ? foods : foods.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            Section {
                InfoBanner(text: "Valores aproximados de referencia por 100 g. Compruébalos con la etiqueta de tu producto o una base de datos fiable (p. ej. BEDCA o USDA FoodData Central) y edítalos aquí. Al guardar, todos los menús se recalculan.")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(filtered) { food in
                    NavigationLink {
                        FoodEditorView(food: food)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(food.name)
                                if food.isProvisional { Text("⚠︎").foregroundStyle(Theme.warning) }
                                if food.isUserEdited { Image(systemName: "pencil.circle.fill").font(.caption).foregroundStyle(Theme.lime) }
                            }
                            Text("\(NumberFormat.integer(food.kcalPer100)) kcal · P \(NumberFormat.oneDecimal(food.proteinPer100)) · C \(NumberFormat.oneDecimal(food.carbsPer100)) · G \(NumberFormat.oneDecimal(food.fatPer100)) · \(food.basis.label.lowercased())")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            } footer: {
                Text("⚠︎ = valor provisional · ✎ = editado por ti")
            }
            .listRowBackground(Theme.card)
        }
        .searchable(text: $search, prompt: "Buscar alimento")
        .screenBackground()
        .navigationTitle("Catálogo")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $creating) {
            NavigationStack { FoodEditorView(food: nil) }
        }
    }
}

struct FoodEditorView: View {
    let food: FoodItem?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var basis: WeightBasis = .raw
    @State private var macrosKnown = true
    @State private var provisional = true
    @State private var note = ""
    @State private var showDeleteBlocked = false
    @State private var confirmDelete = false

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (kcal ?? -1) >= 0
            && (!macrosKnown || (protein != nil && carbs != nil && fat != nil))
    }

    private var macroWarning: String? {
        guard macrosKnown, let kcal, let protein, let carbs, let fat, kcal > 0 else { return nil }
        let estimate = NutritionMath.kcalFromMacros(NutritionValues(kcal: kcal, protein: protein, carbs: carbs, fat: fat))
        guard abs(estimate - kcal) / kcal > 0.15 else { return nil }
        return "Las kcal (\(NumberFormat.integer(kcal))) difieren más de un 15 % de las calculadas por macros (\(NumberFormat.integer(estimate))). Revisa los datos (la fibra y el alcohol pueden explicar diferencias)."
    }

    var body: some View {
        Form {
            Section("Alimento") {
                TextField("Nombre", text: $name)
                Picker("Peso en báscula", selection: $basis) {
                    ForEach(WeightBasis.allCases) { Text($0.label).tag($0) }
                }
            }
            Section {
                row("Energía (kcal)", $kcal)
                Toggle("Tengo macros fiables", isOn: $macrosKnown)
                if macrosKnown {
                    row("Proteínas (g)", $protein)
                    row("Carbohidratos (g)", $carbs)
                    row("Grasas (g)", $fat)
                }
            } header: {
                Text("Valores por 100 g")
            } footer: {
                if let macroWarning { Text(macroWarning).foregroundStyle(Theme.warning) }
            }
            Section {
                Toggle("Valor provisional", isOn: $provisional)
                TextField("Fuente / nota", text: $note, axis: .vertical)
            } footer: {
                Text("Desactiva “provisional” cuando hayas comprobado los valores con la etiqueta o una base de datos fiable.")
            }
            if food != nil {
                Section {
                    Button("Eliminar alimento", role: .destructive) {
                        if (food?.usages.isEmpty ?? true) { confirmDelete = true } else { showDeleteBlocked = true }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationTitle(food == nil ? "Nuevo alimento" : "Editar alimento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if food == nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") { save() }.disabled(!isValid)
            }
        }
        .alert("No se puede eliminar", isPresented: $showDeleteBlocked) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Este alimento se usa en \(food?.usages.count ?? 0) ingrediente(s) de los menús. Quítalo primero de esas comidas.")
        }
        .confirmationDialog("¿Eliminar este alimento?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                if let food { context.delete(food); try? context.save() }
                dismiss()
            }
        }
        .onAppear(perform: load)
    }

    private func row(_ title: String, _ binding: Binding<Double?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            DecimalField(placeholder: "0", value: binding, width: 100)
        }
    }

    private func load() {
        guard let food else { return }
        name = food.name
        kcal = food.kcalPer100
        protein = food.proteinPer100
        carbs = food.carbsPer100
        fat = food.fatPer100
        basis = food.basis
        macrosKnown = food.macrosKnown
        provisional = food.isProvisional
        note = food.sourceNote
    }

    private func save() {
        let values = NutritionValues(kcal: kcal ?? 0, protein: macrosKnown ? (protein ?? 0) : 0,
                                     carbs: macrosKnown ? (carbs ?? 0) : 0, fat: macrosKnown ? (fat ?? 0) : 0)
        let target: FoodItem
        if let food {
            target = food
        } else {
            target = FoodItem(name: name, per100: values, basis: basis)
            context.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.kcalPer100 = values.kcal
        target.proteinPer100 = values.protein
        target.carbsPer100 = values.carbs
        target.fatPer100 = values.fat
        target.basis = basis
        target.macrosKnown = macrosKnown
        target.isProvisional = provisional
        target.sourceNote = note
        target.isUserEdited = true
        try? context.save()
        dismiss()
    }
}

/// Registro diario de comidas consumidas (copias guardadas al marcar cada comida).
struct NutritionHistoryView: View {
    @Query(sort: \MealRecord.date, order: .reverse) private var records: [MealRecord]
    @Query private var settingsList: [UserSettings]

    private var days: [(key: String, date: Date, records: [MealRecord])] {
        let grouped = Dictionary(grouping: records) { $0.dayKey }
        return grouped.map { ($0.key, $0.value.first?.date ?? Date(), $0.value) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            if days.isEmpty {
                EmptyStateView(symbol: "calendar", title: "Sin registros", message: "Marca comidas como hechas para ir construyendo tu historial.")
                    .listRowBackground(Theme.card)
            }
            ForEach(days, id: \.key) { day in
                let total = NutritionMath.sum(day.records.map(\.values))
                let target = settingsList.first?.kcalTarget ?? 0
                Section {
                    ForEach(day.records.sorted { $0.mealType.order < $1.mealType.order }) { r in
                        HStack {
                            Text(r.mealType.label)
                            Spacer()
                            Text("≈ \(NumberFormat.integer(r.kcal)) kcal").monospacedDigit().foregroundStyle(Theme.textSecondary)
                        }
                    }
                    HStack {
                        Text("Total").bold()
                        Spacer()
                        Text("≈ \(NumberFormat.integer(total.kcal)) kcal · \(NumberFormat.percent(NutritionMath.progress(consumed: total.kcal, target: target)))")
                            .monospacedDigit().foregroundStyle(Theme.lime)
                    }
                    Text("P \(NumberFormat.integer(total.protein)) g · C \(NumberFormat.integer(total.carbs)) g · G \(NumberFormat.integer(total.fat)) g")
                        .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                } header: {
                    Text(DateUtils.shortDate(day.date))
                }
                .listRowBackground(Theme.card)
            }
        }
        .screenBackground()
        .navigationTitle("Historial de comidas")
    }
}
