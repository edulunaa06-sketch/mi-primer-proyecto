import PhotosUI
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
                        Text(record != nil ? "\(NumberFormat.integer(record!.kcal)) kcal · P \(NumberFormat.integer(record!.protein)) g" : "Toca para hacer la foto")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "camera.fill")
                        .padding(10)
                        .background(Theme.lime, in: Circle())
                        .foregroundStyle(.black)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(type.label): añadir con foto")
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

/// Registrar una comida: foto → Claude detecta los alimentos → añades los que falten y pones los gramos
/// de cada uno → Claude calcula kcal y macros con esos gramos → se suma y se añade a la comida.
struct MealLogSheet: View {
    let type: MealType
    let day: Date

    struct Row: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var grams: Double?
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ClaudeService.self) private var claude
    @Query(sort: \FoodItem.name) private var foods: [FoodItem]

    @State private var jpeg: Data?
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var rows: [Row] = []
    @State private var detected = false
    @State private var note = ""
    @State private var result: [ClaudeAPI.EstimatedItem]?
    @State private var resultNote = ""
    @State private var error: String?
    @State private var askedCamera = false

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
    private var validRows: [Row] { rows.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty } }
    private var canCalculate: Bool {
        !validRows.isEmpty && validRows.allSatisfy { ($0.grams ?? 0) > 0 } && !claude.isWorking
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if !claude.isConfigured {
                        InfoBanner(text: "Sin la IA, escribe tú los ingredientes y sus gramos: las kcal se calculan con la tabla de alimentos de la app. Para que reconozca la foto sola, añade una clave de Claude en Ajustes › Claude (IA).")
                    }
                    photoCard
                    ingredientsCard
                    if let result { resultCard(result) }
                    if let error { Text(error).font(.footnote).foregroundStyle(Theme.danger) }
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
            .fullScreenCover(isPresented: $showCamera) {
                SystemCamera { data in setPhoto(data) }.ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) { setPhoto(data) }
                    pickerItem = nil
                }
            }
            .onChange(of: rows) { _, _ in result = nil }
            .onAppear {
                // Al tocar la comida se abre directamente la cámara.
                guard !askedCamera, jpeg == nil else { return }
                askedCamera = true
                if cameraAvailable && !ProcessInfo.processInfo.arguments.contains("-NNLogMeal") { showCamera = true }
            }
        }
    }

    private var photoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let jpeg, let image = UIImage(data: jpeg) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                VStack(spacing: 8) {
                    Button { showCamera = true } label: {
                        Label(jpeg == nil ? "Hacer foto" : "Repetir foto", systemImage: "camera.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LimeButtonStyle(filled: jpeg == nil))
                    .disabled(!cameraAvailable)
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Elegir de la galería", systemImage: "photo").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LimeButtonStyle(filled: false))
                }
            }
            if claude.isWorking && !detected && jpeg != nil {
                HStack { ProgressView(); Text("Claude está mirando qué hay en el plato…").font(.footnote) }
            }
            if detected && !note.isEmpty {
                Text(note).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Ingredientes y gramos",
                          subtitle: rows.isEmpty ? "Haz la foto o añade los ingredientes a mano." : "Revisa lo detectado, añade lo que falte y pon lo que pesa cada uno.")
            ForEach($rows) { $row in
                HStack(spacing: 8) {
                    TextField("Ingrediente", text: $row.name)
                        .padding(8)
                        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    DecimalField(placeholder: "g", value: $row.grams, width: 72)
                        .accessibilityLabel("Gramos de \(row.name)")
                    Text("g").font(.caption).foregroundStyle(Theme.textSecondary)
                    Button { rows.removeAll { $0.id == row.id } } label: {
                        Image(systemName: "trash").foregroundStyle(Theme.danger)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Quitar \(row.name)")
                }
            }
            Button { rows.append(Row(name: "", grams: nil)) } label: {
                Label("Añadir ingrediente", systemImage: "plus.circle.fill")
            }
            .font(.subheadline.weight(.semibold))
            if rows.contains(where: { $0.name.contains("(?)") }) {
                Text("Los marcados con (?) son dudosos: corrige el nombre si no es eso.").font(.caption).foregroundStyle(Theme.warning)
            }
            Button {
                Task { await calculate() }
            } label: {
                if claude.isWorking && detected { ProgressView().tint(.black) } else { Label("Calcular calorías", systemImage: "sparkles") }
            }
            .buttonStyle(LimeButtonStyle())
            .disabled(!canCalculate)
            if !validRows.isEmpty && !validRows.allSatisfy({ ($0.grams ?? 0) > 0 }) {
                Text("Pon los gramos de cada ingrediente.").font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }

    private func resultCard(_ items: [ClaudeAPI.EstimatedItem]) -> some View {
        let total = NutritionMath.sum(items.map(\.values))
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Resultado")
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).font(.subheadline)
                        Text("\(NumberFormat.integer(item.grams)) g · \(NumberFormat.integer(item.kcalPer100g)) kcal/100 g · P \(NumberFormat.oneDecimal(item.values.protein)) · C \(NumberFormat.oneDecimal(item.values.carbs)) · G \(NumberFormat.oneDecimal(item.values.fat))")
                            .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Text("\(NumberFormat.integer(item.values.kcal)) kcal").font(.subheadline.weight(.semibold).monospacedDigit())
                }
            }
            Divider().overlay(Color.white.opacity(0.1))
            HStack {
                Text("Total").font(.headline)
                Spacer()
                Text("\(NumberFormat.integer(total.kcal)) kcal").font(.title3.weight(.heavy).monospacedDigit()).foregroundStyle(Theme.lime)
                    .accessibilityIdentifier("meal.total")
            }
            Text("P \(NumberFormat.integer(total.protein)) g · C \(NumberFormat.integer(total.carbs)) g · G \(NumberFormat.integer(total.fat)) g")
                .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            if !resultNote.isEmpty { Text(resultNote).font(.caption).foregroundStyle(Theme.textTertiary) }
            if items.count < validRows.count {
                Text("Algún ingrediente no se pudo calcular; revisa su nombre.").font(.caption).foregroundStyle(Theme.warning)
            }
            Button("Añadir a \(type.label.lowercased())") {
                DataStore.logFoods(items.map { (name: $0.name, grams: $0.grams, per100: $0.per100) }, as: type, on: day, in: context)
                dismiss()
            }
            .buttonStyle(LimeButtonStyle())
            .disabled(items.isEmpty)
        }
        .card()
    }

    private func setPhoto(_ data: Data) {
        guard let prepared = PhotoMealCard.preparedJPEG(data) else { error = "No se pudo leer la imagen."; return }
        jpeg = prepared
        result = nil
        guard claude.isConfigured else { return }
        Task { await detect(prepared) }
    }

    private func detect(_ jpeg: Data) async {
        error = nil
        detected = false
        do {
            let found = try await claude.detectIngredients(jpeg: jpeg)
            // Se conservan los ingredientes que ya hubieras escrito a mano.
            let manual = rows.filter { !$0.name.isEmpty }
            let known = Set(manual.map { $0.name.lowercased() })
            rows = manual + found.ingredients.filter { !known.contains($0.lowercased()) }.map { Row(name: $0, grams: nil) }
            note = found.note
            if found.ingredients.isEmpty && note.isEmpty { note = "No se ha reconocido comida. Añade los ingredientes a mano." }
        } catch {
            self.error = error.localizedDescription
        }
        detected = true
    }

    private func calculate() async {
        error = nil
        guard claude.isConfigured else { calculateWithCatalog(); return }
        let ingredients = validRows.map { ClaudeAPI.WeighedIngredient(name: $0.name.trimmingCharacters(in: .whitespaces), grams: $0.grams ?? 0) }
        do {
            let answer = try await claude.calculate(ingredients, jpeg: jpeg)
            result = answer.items
            resultNote = answer.note
            if answer.items.isEmpty { error = "Claude no ha devuelto valores válidos. Revisa los nombres." }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Sin clave de Claude: cada ingrediente se busca en la tabla de alimentos de la app.
    private func calculateWithCatalog() {
        var items: [ClaudeAPI.EstimatedItem] = []
        var missing: [String] = []
        for row in validRows {
            let name = row.name.trimmingCharacters(in: .whitespaces)
            guard let food = FoodSearch.bestMatch(for: name, in: foods, name: \.name) else { missing.append(name); continue }
            items.append(ClaudeAPI.EstimatedItem(name: "\(food.name) (\(food.basis.label.lowercased()))", grams: row.grams ?? 0,
                                                 kcalPer100g: food.kcalPer100, proteinPer100g: food.proteinPer100,
                                                 carbsPer100g: food.carbsPer100, fatPer100g: food.fatPer100))
        }
        result = items
        resultNote = "Calculado con la tabla de alimentos de la app. Comprueba que cada ingrediente es el que has comido."
        if !missing.isEmpty {
            error = "No están en la tabla de la app: \(missing.joined(separator: ", ")). Prueba con otro nombre (p. ej. «pollo», «arroz», «huevo»)."
        }
    }
}
