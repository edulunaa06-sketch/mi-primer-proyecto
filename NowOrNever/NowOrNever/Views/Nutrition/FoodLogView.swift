import SwiftData
import SwiftUI
import UIKit

/// Nutrición: «Comidas» (lo que comes de verdad, por foto) y «Menús» (ideas y planificación).
struct NutritionRootView: View {
    enum Section: String, CaseIterable, Identifiable {
        case log = "Comidas", menus = "Menús"
        var id: String { rawValue }
    }

    @State private var section: Section = .log

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sección", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.background)
            switch section {
            case .log: FoodLogView()
            case .menus: NutritionView()
            }
        }
        .background(Theme.background.ignoresSafeArea())
        #if DEBUG
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-NNMenus") || args.contains("-NNMealBuilder") || args.contains("-NNCustomMeal") || args.contains("-NNSwapMeal") {
                section = .menus
            }
        }
        #endif
    }
}

/// Lo que comes hoy: lo que te queda del día y las cuatro comidas. Tocar una abre la cámara.
struct FoodLogView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @Query private var records: [MealRecord]
    @Query(sort: \CustomMealItem.order) private var allItems: [CustomMealItem]

    @State private var day = DateUtils.startOfDay(Date())
    @State private var logging: MealType?

    private var key: String { DateUtils.dayKey(day) }
    private var dayRecords: [MealRecord] { records.filter { $0.dayKey == key } }
    private var consumed: NutritionValues { NutritionMath.sum(dayRecords.map(\.values)) }
    private var target: NutritionValues {
        let s = settingsList.first
        return NutritionValues(kcal: s?.kcalTarget ?? 0, protein: s?.proteinTarget ?? 0, carbs: s?.carbsTarget ?? 0, fat: s?.fatTarget ?? 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    dayPicker
                    CaloriesLeftCard(consumed: consumed, target: target, title: Calendar.current.isDateInToday(day) ? "Hoy" : DateUtils.shortDate(day))
                    ForEach(MealType.allCases) { type in mealCard(type) }
                    Text("Las kcal las estima Claude con los gramos que pesas tú. Son aproximadas. Para ideas de qué comer, abre «Menús».")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Comidas")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $logging) { type in
                MealLogSheet(type: type, day: day)
            }
            #if DEBUG
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("-NNLogMeal") { logging = .lunch }
            }
            #endif
        }
    }

    private var dayPicker: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Día anterior")
            Spacer()
            DatePicker("Día", selection: $day, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "es_ES"))
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .disabled(Calendar.current.isDateInToday(day))
                .accessibilityLabel("Día siguiente")
        }
        .font(.headline)
        .foregroundStyle(Theme.lime)
    }

    private func shift(_ days: Int) {
        if let d = DateUtils.calendar.date(byAdding: .day, value: days, to: day), d <= Date() { day = DateUtils.startOfDay(d) }
    }

    private func mealCard(_ type: MealType) -> some View {
        let items = allItems.filter { $0.dayKey == key && $0.mealType == type }
        let record = dayRecords.first { $0.mealTypeRaw == type.rawValue }
        return VStack(alignment: .leading, spacing: 10) {
            Button { logging = type } label: {
                HStack {
                    Image(systemName: icon(type)).font(.title3).foregroundStyle(Theme.lime).frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(type.label).font(.headline).foregroundStyle(Theme.textPrimary)
                        Text(record != nil ? "\(NumberFormat.integer(record!.kcal)) kcal · P \(NumberFormat.integer(record!.protein)) g" : "Toca para añadir alimentos")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "plus")
                        .padding(10)
                        .background(Theme.lime, in: Circle())
                        .foregroundStyle(.black)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(type.label): añadir alimentos")
            ForEach(items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).font(.subheadline)
                        Text("\(NumberFormat.integer(item.grams)) g · P \(NumberFormat.oneDecimal(item.values.protein)) · C \(NumberFormat.oneDecimal(item.values.carbs)) · G \(NumberFormat.oneDecimal(item.values.fat))")
                            .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Text("\(NumberFormat.integer(item.values.kcal)) kcal").font(.subheadline.monospacedDigit())
                    Button { DataStore.removeLogged(item, in: context) } label: {
                        Image(systemName: "xmark.circle").foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Quitar \(item.name)")
                }
            }
            if record != nil && items.isEmpty {
                Text("Marcada desde Menús: \(record!.planName)").font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
        .card()
    }

    private func icon(_ type: MealType) -> String {
        switch type {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .snack: return "cup.and.saucer.fill"
        case .dinner: return "moon.stars.fill"
        }
    }
}

/// Lo que te queda por comer hoy: objetivo − comido, en kcal y macros. Sin anillos.
struct CaloriesLeftCard: View {
    let consumed: NutritionValues
    let target: NutritionValues
    var title = "Hoy"
    /// Muestra el botón «Cambiar» para poner tú las calorías que quieres comer.
    var editable = true
    @State private var editing = false

    var body: some View {
        let left = target.kcal - consumed.kcal
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title.uppercased()).font(.caption.weight(.heavy)).foregroundStyle(Theme.lime)
                Spacer()
                if editable {
                    Button { editing = true } label: {
                        Label("Cambiar", systemImage: "pencil").font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .tint(Theme.lime)
                    .accessibilityIdentifier("kcal.edit")
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(left >= 0 ? "Te quedan" : "Te has pasado").font(.subheadline).foregroundStyle(Theme.textSecondary)
                Text("\(NumberFormat.integer(abs(left))) kcal")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(left >= 0 ? Theme.textPrimary : Theme.warning)
                    .accessibilityIdentifier("kcal.left")
                Text("Objetivo \(NumberFormat.integer(target.kcal)) − comido \(NumberFormat.integer(consumed.kcal))")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 10) {
                macro("Proteínas", consumed.protein, target.protein)
                macro("Carbohidratos", consumed.carbs, target.carbs)
                macro("Grasas", consumed.fat, target.fat)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .sheet(isPresented: $editing) { TargetsEditorSheet() }
    }

    private func macro(_ name: String, _ eaten: Double, _ goal: Double) -> some View {
        let left = goal - eaten
        return VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            Text("\(NumberFormat.integer(abs(left))) g").font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(left >= 0 ? Theme.textPrimary : Theme.warning)
            Text(left >= 0 ? "quedan de \(NumberFormat.integer(goal))" : "de más (\(NumberFormat.integer(goal)))")
                .font(.caption2).foregroundStyle(Theme.textTertiary).lineLimit(1).minimumScaleFactor(0.8)
            ProgressBar(fraction: goal > 0 ? eaten / goal : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Registrar una comida: «Añadir alimento» (de la tabla o uno tuyo) → pones los gramos → la app calcula
/// kcal y macros de cada uno y el total, y lo resta de lo que te queda del día. Sin IA.
struct MealLogSheet: View {
    let type: MealType
    let day: Date

    struct Row: Identifiable {
        let id = UUID()
        let food: FoodItem
        var grams: Double?
        var values: NutritionValues { NutritionMath.values(per100: food.per100, grams: grams ?? 0) }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [Row] = []
    @State private var picking = false

    private var ready: Bool { !rows.isEmpty && rows.allSatisfy { ($0.grams ?? 0) > 0 } }
    private var total: NutritionValues { NutritionMath.sum(rows.map(\.values)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Alimentos y gramos",
                                      subtitle: rows.isEmpty ? "Añade cada alimento del plato y pon cuánto pesa." : "Pon los gramos de cada uno tal como lo pesas.")
                        ForEach($rows) { $row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(row.food.name).font(.subheadline.weight(.semibold))
                                        Text("Pesado: \(row.food.basis.label.lowercased())").font(.caption2).foregroundStyle(Theme.textTertiary)
                                    }
                                    Spacer()
                                    DecimalField(placeholder: "g", value: $row.grams, width: 72)
                                        .accessibilityLabel("Gramos de \(row.food.name)")
                                    Text("g").font(.caption).foregroundStyle(Theme.textSecondary)
                                    Button { rows.removeAll { $0.id == row.id } } label: {
                                        Image(systemName: "trash").foregroundStyle(Theme.danger)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Quitar \(row.food.name)")
                                }
                                if (row.grams ?? 0) > 0 {
                                    Text("\(NumberFormat.integer(row.values.kcal)) kcal · P \(NumberFormat.oneDecimal(row.values.protein)) · C \(NumberFormat.oneDecimal(row.values.carbs)) · G \(NumberFormat.oneDecimal(row.values.fat))")
                                        .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .padding(10)
                            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        Button { picking = true } label: {
                            Label("Añadir alimento", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(LimeButtonStyle(filled: rows.isEmpty))
                    }
                    .card()

                    if !rows.isEmpty { totalCard }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle(type.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Listo") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
            .sheet(isPresented: $picking) {
                FoodPickerSheet { food in rows.append(Row(food: food, grams: nil)) }
            }
            .onAppear {
                guard rows.isEmpty else { return }
                #if DEBUG
                // Captura de pantalla: un plato de ejemplo ya pesado.
                if ProcessInfo.processInfo.arguments.contains("-NNLogMeal") {
                    let all = (try? context.fetch(FetchDescriptor<FoodItem>())) ?? []
                    rows = [("sweet_potato_boiled", 200.0), ("chicken_grilled", 150.0)].compactMap { key, grams in
                        all.first { $0.seedKey == key }.map { Row(food: $0, grams: grams) }
                    }
                    return
                }
                #endif
                picking = true
            }
        }
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Total").font(.headline)
                Spacer()
                Text("\(NumberFormat.integer(total.kcal)) kcal").font(.title3.weight(.heavy).monospacedDigit()).foregroundStyle(Theme.lime)
                    .accessibilityIdentifier("meal.total")
            }
            Text("P \(NumberFormat.integer(total.protein)) g · C \(NumberFormat.integer(total.carbs)) g · G \(NumberFormat.integer(total.fat)) g")
                .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            Button("Añadir a \(type.label.lowercased())") {
                DataStore.logFoods(rows.map { (name: $0.food.name, grams: $0.grams ?? 0, per100: $0.food.per100) },
                                   as: type, on: day, in: context)
                dismiss()
            }
            .buttonStyle(LimeButtonStyle())
            .disabled(!ready)
            if !ready {
                Text("Pon los gramos de cada alimento.").font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }
}

/// Elegir un alimento de la tabla (buscando por nombre) o crear uno nuevo con sus valores por 100 g.
struct FoodPickerSheet: View {
    var onPick: (FoodItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodItem.name) private var foods: [FoodItem]
    @State private var search = ""

    private var filtered: [FoodItem] { foods.filter { FoodSearch.matches(name: $0.name, query: search) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        FoodEditorView(food: nil)
                    } label: {
                        Label("Crear un alimento nuevo", systemImage: "plus")
                    }
                } footer: {
                    Text("Si no está en la lista, créalo con los valores por 100 g de la etiqueta. Luego aparecerá aquí.")
                }
                .listRowBackground(Theme.card)
                Section(search.isEmpty ? "Todos los alimentos" : "Resultados") {
                    ForEach(filtered) { food in
                        Button {
                            onPick(food)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(food.name).foregroundStyle(Theme.textPrimary)
                                Text("\(NumberFormat.integer(food.kcalPer100)) kcal · P \(NumberFormat.oneDecimal(food.proteinPer100)) · C \(NumberFormat.oneDecimal(food.carbsPer100)) · G \(NumberFormat.oneDecimal(food.fatPer100)) por 100 g · \(food.basis.label.lowercased())")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    if filtered.isEmpty {
                        Text("No está en la tabla. Créalo arriba.").foregroundStyle(Theme.textSecondary)
                    }
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar: boniato, patata, pollo…")
            .screenBackground()
            .navigationTitle("Añadir alimento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
    }
}
