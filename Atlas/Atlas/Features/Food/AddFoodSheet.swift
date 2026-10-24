import SwiftData
import SwiftUI

/// Añadir comida: buscar alimento, menú de platos (ajustados a lo que te queda), añadir rápido o crear un alimento.
struct AddFoodSheet: View {
    let request: FoodSheetRequest
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .search
    @State private var meal: MealType = .breakfast

    enum Mode: String, CaseIterable, Identifiable {
        case search = "Buscar", menus = "Platos", quick = "Rápido", create = "Crear"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Comida", selection: $meal) {
                    ForEach(MealType.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Modo", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("food.mode")
                switch mode {
                case .search: FoodSearchList(meal: meal, dayKey: request.dayKey, onDone: { dismiss() })
                case .menus: DishList(meal: meal, dayKey: request.dayKey, onDone: { dismiss() })
                case .quick: QuickAddForm(meal: meal, dayKey: request.dayKey, onDone: { dismiss() })
                case .create: CreateFoodForm(onCreated: { mode = .search })
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(AtlasBackground())
            .navigationTitle("Añadir a \(meal.label.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Listo") { hideKeyboard() } }
            }
        }
        .onAppear {
            meal = request.meal
            if request.startWithMenus { mode = .menus }
        }
    }
}

/// Un alimento elegible: del catálogo o propio.
struct PickableFood: Identifiable, Hashable {
    let id: String
    let name: String
    let per100: NutritionValues
    let note: String
}

struct FoodSearchList: View {
    let meal: MealType
    let dayKey: String
    let onDone: () -> Void
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomFood.name) private var custom: [CustomFood]
    @State private var query = ""
    @State private var picked: PickableFood?
    @State private var recents: [PickableFood] = []

    var body: some View {
        let pool = custom.map { PickableFood(id: "custom-\($0.id)", name: $0.name, per100: $0.per100, note: "Tuyo") }
            + Catalog.shared.foods.map { PickableFood(id: $0.id, name: $0.name, per100: $0.per100, note: basisNote($0.basis)) }
        let results = query.isEmpty ? [] : pool.filter { FoodSearch.matches(name: $0.name, query: query) }
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(DS.text3)
                TextField("Pollo, arroz, yogur…", text: $query)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("food.search")
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DS.text3) } }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.surfaceHi))
            List {
                if query.isEmpty {
                    if !recents.isEmpty {
                        Section("Recientes") { ForEach(recents) { row($0) } }
                    }
                    Section("Todos los alimentos") { ForEach(pool) { row($0) } }
                } else if results.isEmpty {
                    Text("Sin resultados. Prueba con otra palabra o créalo en «Crear».").foregroundStyle(DS.text2)
                } else {
                    ForEach(results) { row($0) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .onAppear {
            recents = Store.recentFoods(in: context).compactMap { e in
                guard let p = e.per100 else { return nil }
                return PickableFood(id: e.foodKey, name: e.name, per100: p, note: "Último: \(NumberFormat.integer(e.grams)) g")
            }
        }
        .sheet(item: $picked) { food in
            AmountSheet(food: food, meal: meal, dayKey: dayKey) { onDone() }
                .presentationDetents([.height(440)])
        }
    }

    private func row(_ f: PickableFood) -> some View {
        Button { picked = f } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.text)
                    Text("\(NumberFormat.integer(f.per100.kcal)) kcal · P \(NumberFormat.oneDecimal(f.per100.protein)) por 100 g · \(f.note)")
                        .font(.system(size: 11)).foregroundStyle(DS.text3).lineLimit(1)
                }
                Spacer()
                Image(systemName: "plus.circle.fill").foregroundStyle(DS.brandDiagonal).font(.title3)
            }
        }
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("food.row.\(f.name)")
    }

    private func basisNote(_ basis: String) -> String {
        switch WeightBasis(rawValue: basis) {
        case .raw: return "en crudo"
        case .cooked: return "cocinado"
        case .dry: return "en seco"
        case .drained: return "escurrido"
        case .cookedDrained: return "cocido y escurrido"
        case .edible: return "parte comestible"
        case .none: return ""
        }
    }
}

/// Elegir gramos con el resultado en vivo.
struct AmountSheet: View {
    let food: PickableFood
    let meal: MealType
    let dayKey: String
    let onDone: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var grams: Double? = 100

    var body: some View {
        let g = grams ?? 0
        let v = food.per100.scaled(toGrams: g)
        VStack(alignment: .leading, spacing: 16) {
            Text(food.name).font(.display(20)).lineLimit(2)
            HStack(spacing: 10) {
                ForEach([50.0, 100, 150, 200], id: \.self) { q in
                    Button("\(Int(q)) g") { grams = q; DS.haptic(.soft) }
                        .buttonStyle(.secondaryCompact)
                }
            }
            HStack {
                Text("Gramos").foregroundStyle(DS.text2)
                Spacer()
                NumberField(placeholder: "g", value: $grams, decimals: false, width: 120)
                    .accessibilityIdentifier("amount.grams")
            }
            HStack(spacing: 12) {
                macro("kcal", v.kcal, DS.text)
                macro("Proteína", v.protein, DS.protein)
                macro("Hidratos", v.carbs, DS.carbs)
                macro("Grasa", v.fat, DS.fat)
            }
            Button {
                Store.addFood(name: food.name, per100: food.per100, grams: g, meal: meal, dayKey: dayKey, foodKey: food.id, in: context)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
                onDone()
            } label: { Label("Añadir \(NumberFormat.integer(v.kcal)) kcal", systemImage: "plus") }
            .buttonStyle(.primary)
            .disabled(g <= 0)
            .accessibilityIdentifier("amount.add")
        }
        .padding(20)
        .presentationBackground(Color(red: 0.06, green: 0.065, blue: 0.09))
    }

    private func macro(_ name: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(NumberFormat.integer(value)).font(.number(20)).foregroundStyle(color).contentTransition(.numericText())
            Text(name).font(.system(size: 10, weight: .semibold)).foregroundStyle(DS.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.surface))
    }
}

/// Menú de platos: comidas de los menús e ideas, cada una con la ración ajustada a lo que te queda hoy.
struct DishList: View {
    let meal: MealType
    let dayKey: String
    let onDone: () -> Void
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]
    @State private var selected: RankedDish?
    @State private var ranked: [RankedDish] = []

    struct RankedDish: Identifiable {
        let dish: Dish
        let option: MealPlanner.Option
        var id: String { dish.id }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Text("Raciones ajustadas a lo que te queda hoy para \(meal.label.lowercased()). Los mejores encajes primero.")
                    .font(.footnote).foregroundStyle(DS.text2).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(ranked) { item in
                    Button { selected = item } label: { card(item.dish, item.option) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 20)
        }
        .task(id: meal) { rank() }
        .sheet(item: $selected) { s in
            DishDetail(dish: s.dish, factor: s.option.factor, meal: meal, dayKey: dayKey) { onDone() }
        }
    }

    /// Ordena los platos de esta comida por lo bien que encajan con el objetivo (lo que queda del día).
    private func rank() {
        let targets = profiles.first?.targets ?? NutritionValues(kcal: 2200, protein: 150, carbs: 240, fat: 70)
        let entries = Store.entries(dayKey, in: context)
        var fixed: [MealType: NutritionValues] = [:]
        for type in MealType.allCases where type != meal {
            let list = entries.filter { $0.meal == type }
            if !list.isEmpty { fixed[type] = NutritionMath.sum(list.map(\.values)) }
        }
        let target = MealPlanner.target(for: meal, daily: targets, fixed: fixed)
        let dishes = Dish.all.filter { $0.meal == meal }
        ranked = dishes.compactMap { dish -> RankedDish? in
            let items = Catalog.shared.items(dish.items).map { MealPlanner.Item(per100: $0.food.per100, grams: $0.grams) }
            let candidate = MealPlanner.Candidate(id: dish.id, items: items)
            return MealPlanner.bestOption(candidate, target: target).map { RankedDish(dish: dish, option: $0) }
        }
        .sorted { $0.option.fit > $1.option.fit }
    }

    private func card(_ dish: Dish, _ option: MealPlanner.Option) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(dish.name).font(.system(size: 16, weight: .bold)).foregroundStyle(DS.text).lineLimit(2)
                    Text(dish.source).font(.system(size: 11, weight: .medium)).foregroundStyle(DS.text3)
                }
                Spacer()
                Text("\(Int((option.fit * 100).rounded())) %")
                    .font(.system(size: 12, weight: .heavy))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(option.fit > 0.85 ? DS.good.opacity(0.2) : DS.surfaceHi))
                    .foregroundStyle(option.fit > 0.85 ? DS.good : DS.text2)
                    .accessibilityLabel("Encaje \(Int((option.fit * 100).rounded())) por ciento")
            }
            HStack(spacing: 12) {
                Text("\(NumberFormat.integer(option.values.kcal)) kcal").font(.number(15))
                Text("P \(Int(option.values.protein))").foregroundStyle(DS.protein)
                Text("H \(Int(option.values.carbs))").foregroundStyle(DS.carbs)
                Text("G \(Int(option.values.fat))").foregroundStyle(DS.fat)
                Spacer()
                if abs(option.factor - 1) > 0.001 {
                    Text("ración ×\(NumberFormat.oneDecimal(option.factor))").font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.text3)
                }
            }
            .font(.system(size: 12, weight: .bold))
        }
        .glass(padding: 14, radius: 18)
    }
}

struct DishDetail: View {
    let dish: Dish
    let factor: Double
    let meal: MealType
    let dayKey: String
    let onDone: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let items = Catalog.shared.items(dish.items)
        let total = Catalog.shared.values(dish.items, factor: factor)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(dish.name).font(.display(22))
                    Text(dish.source).font(.footnote).foregroundStyle(DS.text2)
                    VStack(spacing: 10) {
                        ForEach(items, id: \.food.id) { item in
                            let g = MealPlanner.grams(item.grams, factor: factor)
                            HStack {
                                Text(item.food.name).font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Text("\(NumberFormat.integer(g)) g").font(.number(15)).foregroundStyle(DS.cyan)
                            }
                        }
                    }
                    .glass()
                    HStack(spacing: 10) {
                        StatTile(title: "kcal", value: NumberFormat.integer(total.kcal), symbol: "flame.fill", tint: DS.indigo)
                        StatTile(title: "Proteína", value: "\(Int(total.protein))", unit: "g", symbol: "bolt.fill", tint: DS.protein)
                    }
                    HStack(spacing: 10) {
                        StatTile(title: "Hidratos", value: "\(Int(total.carbs))", unit: "g", symbol: "leaf.fill", tint: DS.carbs)
                        StatTile(title: "Grasa", value: "\(Int(total.fat))", unit: "g", symbol: "drop.fill", tint: DS.fat)
                    }
                    Button {
                        Store.addDish(dish, factor: factor, meal: meal, dayKey: dayKey, in: context)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                        onDone()
                    } label: { Label("Añadir a \(meal.label.lowercased())", systemImage: "plus") }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("dish.add")
                    Text("Valores aproximados de tablas generales. Pesa los alimentos en el estado indicado (crudo, cocido…).")
                        .font(.caption2).foregroundStyle(DS.text3)
                }
                .padding(20)
            }
            .background(AtlasBackground())
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        }
    }
}

struct QuickAddForm: View {
    let meal: MealType
    let dayKey: String
    let onDone: () -> Void
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Para cuando comes fuera o tienes la etiqueta delante: pon las kcal y, si las sabes, los macros.")
                    .font(.footnote).foregroundStyle(DS.text2)
                TextField("Nombre (opcional)", text: $name)
                    .padding(12).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.surfaceHi))
                field("Calorías", "kcal", $kcal)
                field("Proteína", "g", $protein)
                field("Hidratos", "g", $carbs)
                field("Grasa", "g", $fat)
                Button {
                    let v = NutritionValues(kcal: kcal ?? 0, protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0)
                    Store.addFood(name: name.isEmpty ? "Añadido rápido" : name, per100: nil, grams: 0, quick: v,
                                  meal: meal, dayKey: dayKey, foodKey: "", in: context)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onDone()
                } label: { Label("Añadir", systemImage: "plus") }
                .buttonStyle(.primary)
                .disabled((kcal ?? 0) <= 0)
            }
        }
    }

    private func field(_ title: String, _ unit: String, _ value: Binding<Double?>) -> some View {
        HStack {
            Text(title).foregroundStyle(DS.text2)
            Spacer()
            NumberField(placeholder: "0", value: value, width: 110)
            Text(unit).foregroundStyle(DS.text3).frame(width: 34, alignment: .leading)
        }
    }
}

struct CreateFoodForm: View {
    let onCreated: () -> Void
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Crea un alimento con los datos de su etiqueta (por 100 g). Luego lo encuentras en «Buscar».")
                    .font(.footnote).foregroundStyle(DS.text2)
                TextField("Nombre", text: $name)
                    .padding(12).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.surfaceHi))
                field("Calorías", "kcal", $kcal)
                field("Proteína", "g", $protein)
                field("Hidratos", "g", $carbs)
                field("Grasa", "g", $fat)
                Button {
                    let per100 = NutritionValues(kcal: kcal ?? 0, protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0)
                    context.insert(CustomFood(name: name.trimmingCharacters(in: .whitespaces), per100: per100))
                    try? context.save()
                    DS.haptic(.medium)
                    onCreated()
                } label: { Label("Guardar alimento", systemImage: "checkmark") }
                .buttonStyle(.primary)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (kcal ?? 0) <= 0)
            }
        }
    }

    private func field(_ title: String, _ unit: String, _ value: Binding<Double?>) -> some View {
        HStack {
            Text(title).foregroundStyle(DS.text2)
            Spacer()
            NumberField(placeholder: "0", value: value, width: 110)
            Text(unit + "/100 g").font(.caption).foregroundStyle(DS.text3).frame(width: 64, alignment: .leading)
        }
    }
}
