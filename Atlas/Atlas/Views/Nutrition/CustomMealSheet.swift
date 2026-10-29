import SwiftData
import SwiftUI
import UIKit

/// Tarjeta del día para una comida apuntada a mano ("lo que como").
struct CustomMealCard: View {
    let type: MealType
    let items: [CustomMealItem]
    let isCompleted: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        let totals = NutritionMath.sum(items.map(\.values))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: type.symbol).foregroundStyle(Theme.lime)
                VStack(alignment: .leading, spacing: 1) {
                    Text(type.label).font(.headline)
                    Text("Apuntado por ti").font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button(action: onToggle) {
                    HStack(spacing: 6) {
                        Text(isCompleted ? "Hecha" : "Marcar").font(.caption.weight(.bold))
                        CheckCircle(isOn: isCompleted, size: 24)
                    }
                    .foregroundStyle(isCompleted ? Theme.lime : Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            ForEach(items) { item in
                CustomItemRow(item: item)
            }
            Divider().overlay(Theme.separator)
            HStack {
                Text("Subtotal").font(.subheadline.weight(.semibold))
                Spacer()
                Text("≈ \(NumberFormat.integer(totals.kcal)) kcal")
                    .font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Theme.lime)
            }
            Text("P \(NumberFormat.oneDecimal(totals.protein)) g · C \(NumberFormat.oneDecimal(totals.carbs)) g · G \(NumberFormat.oneDecimal(totals.fat)) g")
                .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 10) {
                Button(action: onEdit) { Label("Editar", systemImage: "square.and.pencil") }
                    .buttonStyle(LimeButtonStyle(filled: false))
                Button("Volver al menú", action: onRemove).font(.caption.weight(.semibold))
            }
        }
        .card()
    }
}

struct CustomItemRow: View {
    let item: CustomMealItem

    var body: some View {
        let v = item.values
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.subheadline)
                Text("\(NumberFormat.oneDecimal(item.grams)) g · \(item.source.label)")
                    .font(.caption)
                    .foregroundStyle(item.source == .claude ? Theme.warning : Theme.textSecondary)
                Text("P \(NumberFormat.oneDecimal(v.protein)) · C \(NumberFormat.oneDecimal(v.carbs)) · G \(NumberFormat.oneDecimal(v.fat))")
                    .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Text("≈ \(NumberFormat.integer(v.kcal)) kcal").font(.subheadline.monospacedDigit())
        }
    }
}

/// Lo que te comes fuera de las cuatro comidas: una cerveza, un paquete de patatas, el trozo
/// de tarta del cumpleaños. No se planifica y no quita sitio a ninguna comida: simplemente
/// suma a las calorías del día en cuanto lo apuntas.
struct ExtrasCard: View {
    let items: [CustomMealItem]
    let onAdd: () -> Void
    let onScan: () -> Void
    let onRemove: (CustomMealItem) -> Void

    var body: some View {
        let totals = NutritionMath.sum(items.map(\.values))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: MealType.extra.symbol).foregroundStyle(Theme.lime)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Extras").font(.headline)
                    Text("Lo que cae fuera de las cuatro comidas")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if !items.isEmpty {
                    Text("≈ \(NumberFormat.integer(totals.kcal)) kcal")
                        .font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Theme.lime)
                }
            }
            if items.isEmpty {
                Text("Nada de momento. Si te tomas algo fuera de las comidas, apúntalo aquí y cuenta en el día.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(items) { item in
                    HStack {
                        CustomItemRow(item: item)
                        Button { onRemove(item) } label: {
                            Image(systemName: "trash").foregroundStyle(Theme.danger)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Quitar \(item.name)")
                    }
                }
                Text("P \(NumberFormat.oneDecimal(totals.protein)) g · C \(NumberFormat.oneDecimal(totals.carbs)) g · G \(NumberFormat.oneDecimal(totals.fat)) g")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 10) {
                Button(action: onAdd) { Label("Añadir un extra", systemImage: "plus") }
                    .buttonStyle(LimeButtonStyle())
                Button(action: onScan) { Label("Escanear", systemImage: "barcode.viewfinder") }
                    .buttonStyle(LimeButtonStyle(filled: false))
            }
        }
        .card()
        .accessibilityIdentifier("nutrition.extras")
    }
}

/// Apuntar lo que como en una comida: con una foto del plato pesado, describiéndolo para que Claude lo calcule,
/// del catálogo o a mano.
/// También pide a Claude alternativas más saludables con alimentos del catálogo.
struct CustomMealSheet: View {
    let type: MealType
    let day: Date
    /// Objetivo de esta comida según el resto del día.
    let target: NutritionValues
    /// Abrir el escáner de códigos de barras.
    var onScan: (() -> Void)?
    var onDone: () -> Void

    /// Sin IA: de la tabla de alimentos o a mano.
    enum Mode: String, CaseIterable, Identifiable {
        case catalog = "Catálogo", manual = "Manual"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ClaudeService.self) private var claude
    @Query(sort: \FoodItem.name) private var foods: [FoodItem]
    @Query(sort: \CustomMealItem.order) private var allItems: [CustomMealItem]

    @State private var mode: Mode = .catalog
    // Claude
    @State private var description = ""
    @State private var estimate: ClaudeAPI.Estimate?
    @State private var suggestions: [(meal: ClaudeAPI.SuggestedMeal, lines: [(entry: ClaudeAPI.CatalogEntry, grams: Double)])] = []
    @State private var claudeError: String?
    // Catálogo
    @State private var search = ""
    @State private var selectedFood: FoodItem?
    @State private var catalogGrams: Double? = 100
    // Manual
    @State private var manualName = ""
    @State private var manualGrams: Double?
    @State private var manualKcal: Double?
    @State private var manualProtein: Double?
    @State private var manualCarbs: Double?
    @State private var manualFat: Double?
    /// Lo que apuntaste la última vez en esta comida (se lee una vez al abrir la hoja).
    @State private var lastTime: (date: Date?, items: [CustomMealItem])?

    private var items: [CustomMealItem] {
        let key = DateUtils.dayKey(day)
        return allItems.filter { $0.dayKey == key && $0.mealType == type }
    }
    private var totals: NutritionValues { NutritionMath.sum(items.map(\.values)) }

    /// Catálogo con ids cortos para Claude (f1, f2…), que se traducen de vuelta a alimentos de la app.
    private var catalogEntries: [(entry: ClaudeAPI.CatalogEntry, food: FoodItem)] {
        foods.enumerated().map { index, food in
            (ClaudeAPI.CatalogEntry(id: "f\(index + 1)", name: food.name, basis: food.basis.label.lowercased(), per100: food.per100), food)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if type.isPlanned {
                        TargetHeader(title: "Objetivo para tu \(type.label.lowercased())",
                                     subtitle: "Lo que te queda según el resto de comidas del día", target: target)
                    } else {
                        InfoBanner(text: "Un extra no quita sitio a ninguna comida: suma a las calorías del día "
                                   + "en cuanto lo apuntas.")
                    }
                    currentCard
                    quickCard
                    Picker("Cómo añadir", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch mode {
                    case .catalog: catalogCard
                    case .manual: manualCard
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle("Lo que como · \(type.label)")
            .task { lastTime = DataStore.lastLogged(type, before: day, in: context) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hecho") { onDone(); dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Listo") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
    }

    // MARK: Lo de siempre

    /// Los alimentos que más usas, de un toque y con los gramos que sueles poner.
    /// Es lo que hace que apuntar el desayuno de todos los días no sea una excursión.
    private var quickCard: some View {
        let favourites = foods.filter { $0.timesUsed > 0 }
            .sorted { ($0.timesUsed, $0.lastUsedAt ?? .distantPast) > ($1.timesUsed, $1.lastUsedAt ?? .distantPast) }
            .prefix(8)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "De un toque",
                          subtitle: favourites.isEmpty
                            ? "Aquí irán saliendo los alimentos que más apuntes, con tus gramos de siempre."
                            : "Repite lo de la última vez o tira de lo que más apuntas, con tus gramos.")
            if let onScan {
                Button { onScan() } label: {
                    Label("Escanear un código de barras", systemImage: "barcode.viewfinder")
                }
                .buttonStyle(LimeButtonStyle())
                .accessibilityIdentifier("custom.scan")
            }
            // Solo mientras no hayas apuntado nada todavía: así no se repite dos veces sin querer.
            if items.isEmpty, let previous = lastTime, !previous.items.isEmpty {
                Button { repeatPrevious(previous.items) } label: {
                    Label(previous.date.map { "Repetir lo del \(DateUtils.shortDate($0))" }
                          ?? "Repetir la última vez", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(LimeButtonStyle(filled: false))
                Text(previous.items.map(\.name).joined(separator: ", "))
                    .font(.caption2).foregroundStyle(Theme.textTertiary).lineLimit(2)
            }
            if !favourites.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(favourites)) { food in
                            Button { quickAdd(food) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.displayName).font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Text("\(NumberFormat.integer(food.lastGrams)) g · \(NumberFormat.integer(food.per100.scaled(toGrams: food.lastGrams).kcal)) kcal")
                                        .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .frame(maxWidth: 170, alignment: .leading)
                                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .foregroundStyle(Theme.textPrimary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .card()
    }

    private func repeatPrevious(_ items: [CustomMealItem]) {
        DataStore.repeatMeal(items, as: type, on: day, in: context)
        DS.haptic(.medium)
    }

    private func quickAdd(_ food: FoodItem) {
        let grams = food.lastGrams > 0 ? food.lastGrams : 100
        DataStore.addCustomItem(type, name: food.displayName, grams: grams, per100: food.per100,
                                source: .catalog, on: day, in: context)
        DataStore.recordUse(of: food, grams: grams, in: context)
        DS.haptic(.light)
    }

    // MARK: Lo apuntado

    private var currentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Lo que como", subtitle: items.isEmpty ? "Aún no has añadido nada" : nil)
            ForEach(items) { item in
                HStack {
                    CustomItemRow(item: item)
                    Button {
                        context.delete(item)
                        try? context.save()
                    } label: {
                        Image(systemName: "trash").foregroundStyle(Theme.danger)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Quitar \(item.name)")
                }
            }
            if !items.isEmpty {
                Divider().overlay(Theme.separator)
                Text("Total: \(NumberFormat.integer(totals.kcal)) kcal · P \(NumberFormat.integer(totals.protein)) g · C \(NumberFormat.integer(totals.carbs)) g · G \(NumberFormat.integer(totals.fat)) g")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                if type.isPlanned {
                    let diff = totals.kcal - target.kcal
                    Text(abs(diff) < 50 ? "Encaja con tu objetivo para esta comida."
                         : diff > 0 ? "\(NumberFormat.integer(diff)) kcal por encima del objetivo: el resto del día se puede reajustar."
                                    : "\(NumberFormat.integer(-diff)) kcal por debajo del objetivo.")
                        .font(.caption).foregroundStyle(abs(diff) < 50 ? Theme.lime : Theme.warning)
                }
                if items.contains(where: { $0.source == .claude }) {
                    Text("Los alimentos marcados como «Estimación de Claude (IA)» son aproximados.")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .card()
    }

    // MARK: Claude

    private var claudeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Descríbelo y Claude lo calcula", subtitle: "Ej.: «150 g de macarrones con tomate y un poco de queso»")
            TextField("¿Qué comes?", text: $description, axis: .vertical)
                .lineLimit(2...5)
                .padding(10)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if !claude.isConfigured {
                InfoBanner(text: "Para usar Claude añade tu clave de la API en Ajustes › Claude (IA). Mientras tanto puedes usar Catálogo o Manual.")
            }
            Button {
                Task { await runEstimate() }
            } label: {
                if claude.isWorking { ProgressView().tint(Theme.onLime) } else { Label("Calcular con Claude", systemImage: "sparkles") }
            }
            .buttonStyle(LimeButtonStyle())
            .disabled(description.trimmingCharacters(in: .whitespaces).isEmpty || claude.isWorking || !claude.isConfigured)
            if let claudeError { Text(claudeError).font(.footnote).foregroundStyle(Theme.danger) }
            if let estimate {
                ForEach(Array(estimate.items.enumerated()), id: \.offset) { _, item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.name).font(.subheadline)
                            Text("\(NumberFormat.oneDecimal(item.grams)) g · \(NumberFormat.integer(item.kcalPer100g)) kcal/100 g")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Text("≈ \(NumberFormat.integer(item.values.kcal)) kcal").font(.subheadline.monospacedDigit())
                    }
                }
                let t = NutritionMath.sum(estimate.items.map(\.values))
                Text("Total estimado: \(NumberFormat.integer(t.kcal)) kcal · P \(NumberFormat.integer(t.protein)) g · C \(NumberFormat.integer(t.carbs)) g · G \(NumberFormat.integer(t.fat)) g")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.lime)
                if !estimate.note.isEmpty {
                    Text(estimate.note).font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Button("Añadir a mi \(type.label.lowercased())") {
                    for item in estimate.items {
                        DataStore.addCustomItem(type, name: item.name, grams: item.grams, per100: item.per100,
                                                source: .claude, on: day, in: context)
                    }
                    self.estimate = nil
                    description = ""
                }
                .buttonStyle(LimeButtonStyle(filled: false))
                .disabled(estimate.items.isEmpty)
            }
        }
        .card()
    }

    private func runEstimate() async {
        claudeError = nil
        do {
            estimate = try await claude.estimate(description)
            if estimate?.items.isEmpty == true { claudeError = "Claude no devolvió ingredientes válidos. Prueba a describirlo con más detalle." }
        } catch {
            claudeError = error.localizedDescription
        }
    }

    private var healthierCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Alternativa más saludable", subtitle: "Claude propone comidas con alimentos de tu catálogo que encajan con tu objetivo; los macros se calculan en la app.")
            Button {
                Task { await runSuggest() }
            } label: {
                if claude.isWorking { ProgressView() } else { Label("Pedir ideas a Claude", systemImage: "leaf.fill") }
            }
            .buttonStyle(LimeButtonStyle(filled: false))
            .disabled(claude.isWorking || !claude.isConfigured)
            ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                let values = NutritionMath.sum(suggestion.lines.map { $0.entry.per100.scaled(toGrams: $0.grams) })
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(suggestion.meal.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("Encaja \(NumberFormat.percent(MealPlanner.fit(values, to: target)))")
                            .font(.caption.weight(.bold)).foregroundStyle(Theme.lime)
                    }
                    Text(suggestion.meal.why).font(.caption).foregroundStyle(Theme.textSecondary)
                    ForEach(Array(suggestion.lines.enumerated()), id: \.offset) { _, line in
                        HStack {
                            Text(line.entry.name).font(.caption)
                            Spacer()
                            Text("\(NumberFormat.integer(line.grams)) g · \(NumberFormat.integer(line.entry.per100.scaled(toGrams: line.grams).kcal)) kcal")
                                .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Text("\(NumberFormat.integer(values.kcal)) kcal · P \(NumberFormat.integer(values.protein)) · C \(NumberFormat.integer(values.carbs)) · G \(NumberFormat.integer(values.fat))")
                        .font(.caption.weight(.semibold).monospacedDigit())
                    Button("Usar esta comida") { use(suggestion.lines) }
                        .buttonStyle(LimeButtonStyle())
                }
                .padding(12)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .card()
    }

    private func runSuggest() async {
        claudeError = nil
        let entries = catalogEntries.map(\.entry)
        let context = items.isEmpty
            ? (description.isEmpty ? "" : "Quiere comer algo parecido a: \(description)")
            : "Había apuntado: " + items.map { "\(Int($0.grams)) g de \($0.name)" }.joined(separator: ", ") + ". Quiere una opción más saludable."
        do {
            let meals = try await claude.suggest(mealLabel: type.label, target: target, context: context, catalog: entries)
            suggestions = meals.map { (meal: $0, lines: ClaudeAPI.resolve($0, catalog: entries)) }.filter { !$0.lines.isEmpty }
            if suggestions.isEmpty { claudeError = "Claude no devolvió comidas válidas con tu catálogo." }
        } catch {
            claudeError = error.localizedDescription
        }
    }

    /// Sustituye lo apuntado por la comida sugerida (con valores del catálogo).
    private func use(_ lines: [(entry: ClaudeAPI.CatalogEntry, grams: Double)]) {
        items.forEach { context.delete($0) }
        try? context.save()
        for line in lines {
            DataStore.addCustomItem(type, name: line.entry.name, grams: line.grams, per100: line.entry.per100,
                                    source: .catalog, on: day, in: self.context)
        }
        suggestions = []
    }

    // MARK: Catálogo y manual

    private var catalogCard: some View {
        let filtered = search.isEmpty ? foods : foods.filter { FoodSearch.matches(name: $0.name, query: search) }
        return VStack(alignment: .leading, spacing: 10) {
            TextField("Buscar alimento", text: $search)
                .padding(10)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if let food = selectedFood {
                HStack {
                    Text("\(food.name) (\(food.basis.label.lowercased()))").font(.subheadline.weight(.semibold))
                    Spacer()
                    DecimalField(placeholder: "g", value: $catalogGrams, width: 90)
                }
                let v = NutritionMath.values(per100: food.per100, grams: catalogGrams ?? 0)
                Text("≈ \(NumberFormat.integer(v.kcal)) kcal · P \(NumberFormat.oneDecimal(v.protein)) · C \(NumberFormat.oneDecimal(v.carbs)) · G \(NumberFormat.oneDecimal(v.fat))")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.lime)
                Button("Añadir") {
                    guard let g = catalogGrams, g > 0 else { return }
                    DataStore.addCustomItem(type, name: food.displayName, grams: g, per100: food.per100,
                                            source: .catalog, on: day, in: context)
                    DataStore.recordUse(of: food, grams: g, in: context)
                    selectedFood = nil
                }
                .buttonStyle(LimeButtonStyle())
                .disabled((catalogGrams ?? 0) <= 0)
            }
            ForEach(filtered.prefix(30)) { food in
                Button {
                    selectedFood = food
                    catalogGrams = food.lastGrams > 0 ? food.lastGrams : 100
                } label: {
                    HStack {
                        Text(food.displayName).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(NumberFormat.integer(food.kcalPer100)) kcal/100 g").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Añadir a mano", subtitle: "Con los datos de la etiqueta. Kcal y macros del TOTAL que comes.")
            TextField("Nombre (p. ej. bocadillo de lomo)", text: $manualName)
                .padding(10)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            field("Gramos", $manualGrams)
            field("Kcal totales", $manualKcal)
            field("Proteínas (g, opcional)", $manualProtein)
            field("Carbohidratos (g, opcional)", $manualCarbs)
            field("Grasas (g, opcional)", $manualFat)
            Button("Añadir") { addManual() }
                .buttonStyle(LimeButtonStyle())
                .disabled(manualName.trimmingCharacters(in: .whitespaces).isEmpty || (manualGrams ?? 0) <= 0 || manualKcal == nil)
        }
        .card()
    }

    private func field(_ title: String, _ binding: Binding<Double?>) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            DecimalField(placeholder: "0", value: binding, width: 90)
        }
    }

    private func addManual() {
        guard let grams = manualGrams, grams > 0, let kcal = manualKcal else { return }
        let factor = 100 / grams
        let per100 = NutritionValues(kcal: kcal * factor, protein: (manualProtein ?? 0) * factor,
                                     carbs: (manualCarbs ?? 0) * factor, fat: (manualFat ?? 0) * factor)
        DataStore.addCustomItem(type, name: manualName.trimmingCharacters(in: .whitespaces), grams: grams,
                                per100: per100, source: .manual, on: day, in: context)
        manualName = ""
        manualGrams = nil
        manualKcal = nil
        manualProtein = nil
        manualCarbs = nil
        manualFat = nil
    }
}
