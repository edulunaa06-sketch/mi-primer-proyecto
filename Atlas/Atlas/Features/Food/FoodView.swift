import SwiftData
import SwiftUI

/// Comer: el diario del día (desayuno, almuerzo, merienda, cena) con calorías y macros en vivo.
struct FoodView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let dayKey = DateUtils.dayKey(app.foodDay)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("Comer").font(.display(28))
                        Spacer()
                        Button {
                            app.foodSheet = FoodSheetRequest(meal: .forNow(), dayKey: dayKey, startWithMenus: true)
                        } label: {
                            Label("Menús", systemImage: "menucard.fill")
                        }
                        .buttonStyle(.secondaryCompact)
                        .accessibilityIdentifier("food.menus")
                    }
                    .padding(.top, 8)
                    DayPicker(day: Binding(get: { app.foodDay }, set: { app.foodDay = $0 }))
                    // Solo se leen los alimentos del día elegido (rápido aunque tengas años de datos).
                    FoodDayContent(dayKey: dayKey).id(dayKey)
                }
                .padding(.horizontal, 16)
            }
            .atlasScreen()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct FoodDayContent: View {
    let dayKey: String
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query private var profiles: [Profile]
    @Query private var entries: [FoodEntry]
    @State private var editing: FoodEntry?
    @State private var copiedMessage: String?

    init(dayKey: String) {
        self.dayKey = dayKey
        _entries = Query(filter: #Predicate<FoodEntry> { $0.dayKey == dayKey }, sort: \FoodEntry.createdAt)
    }

    var body: some View {
        let profile = profiles.first
        let eaten = NutritionMath.sum(entries.map(\.values))
        VStack(spacing: 16) {
            CaloriesHero(eaten: eaten, targets: profile?.targets ?? .zero, margin: profile?.kcalMargin ?? 100) {}
                .allowsHitTesting(false)
            ForEach(MealType.allCases) { meal in
                mealSection(meal, entries: entries.filter { $0.meal == meal }, targets: profile?.targets ?? .zero)
            }
            if entries.isEmpty {
                Button {
                    let previous = DateUtils.date(fromDayKey: dayKey).map { $0.addingTimeInterval(-86400) } ?? Date()
                    let n = Store.copyDay(from: DateUtils.dayKey(previous), to: dayKey, in: context)
                    copiedMessage = n == 0 ? "El día anterior no había nada apuntado." : "Copiados \(n) alimentos del día anterior."
                    DS.haptic(.medium)
                } label: {
                    Label("Repetir lo del día anterior", systemImage: "arrow.uturn.backward.circle")
                }
                .buttonStyle(.secondary)
            }
            if let copiedMessage {
                Text(copiedMessage).font(.footnote).foregroundStyle(DS.text2)
            }
        }
        .sheet(item: $editing) { EntryEditSheet(entry: $0).presentationDetents([.medium]) }
    }

    private func mealSection(_ meal: MealType, entries: [FoodEntry], targets: NutritionValues) -> some View {
        let total = NutritionMath.sum(entries.map(\.values))
        let share = MealPlanner.share[meal] ?? 0.25
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: meal.symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(DS.brandDiagonal)
                    .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DS.surfaceHi))
                VStack(alignment: .leading, spacing: 0) {
                    Text(meal.label).font(.system(size: 17, weight: .bold))
                    Text("\(NumberFormat.integer(total.kcal)) kcal · sugerido ~\(NumberFormat.integer(targets.kcal * share))")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(DS.text3)
                }
                Spacer()
                Button {
                    app.foodSheet = FoodSheetRequest(meal: meal, dayKey: dayKey)
                } label: {
                    Image(systemName: "plus").font(.system(size: 14, weight: .heavy))
                        .frame(width: 34, height: 34).background(Circle().fill(DS.brandDiagonal))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Añadir a \(meal.label)")
                .accessibilityIdentifier("add.\(meal.rawValue)")
            }
            ForEach(entries) { e in
                Button { editing = e } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.text).lineLimit(1)
                            Text(e.grams > 0 ? "\(NumberFormat.integer(e.grams)) g · P \(Int(e.protein)) · H \(Int(e.carbs)) · G \(Int(e.fat))"
                                 : "P \(Int(e.protein)) · H \(Int(e.carbs)) · G \(Int(e.fat))")
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(DS.text3)
                        }
                        Spacer()
                        Text("\(NumberFormat.integer(e.kcal))").font(.number(16)).foregroundStyle(DS.text)
                        Text("kcal").font(.system(size: 10, weight: .semibold)).foregroundStyle(DS.text3)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) { context.delete(e); try? context.save() } label: { Label("Quitar", systemImage: "trash") }
                }
            }
        }
        .glass()
    }
}

/// Semana con el día elegido; flechas para cambiar de semana.
struct DayPicker: View {
    @Binding var day: Date

    var body: some View {
        let start = DateUtils.startOfWeek(day)
        HStack(spacing: 4) {
            Button { day = day.addingTimeInterval(-7 * 86400) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain).foregroundStyle(DS.text2).frame(width: 26)
            ForEach(0..<7, id: \.self) { i in
                let d = DateUtils.calendar.date(byAdding: .day, value: i, to: start) ?? start
                let selected = DateUtils.calendar.isDate(d, inSameDayAs: day)
                let isToday = DateUtils.calendar.isDateInToday(d)
                Button {
                    DS.haptic(.soft)
                    withAnimation(.snappy) { day = d }
                } label: {
                    VStack(spacing: 3) {
                        Text(String(WeeklyRoutine.weekdayName(i + 1).prefix(2)).uppercased())
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(selected ? .white : DS.text3)
                        Text("\(DateUtils.calendar.component(.day, from: d))")
                            .font(.number(16)).foregroundStyle(selected ? .white : (isToday ? DS.cyan : DS.text))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        if selected { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.brandDiagonal) }
                    }
                }
                .buttonStyle(.plain)
            }
            Button { day = day.addingTimeInterval(7 * 86400) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain).foregroundStyle(DS.text2).frame(width: 26)
        }
        .glass(padding: 8, radius: 18)
    }
}

/// Cambiar los gramos de un alimento apuntado, moverlo de comida o quitarlo.
struct EntryEditSheet: View {
    @Bindable var entry: FoodEntry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var grams: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(entry.name).font(.display(20)).lineLimit(2)
            if entry.per100 != nil {
                HStack {
                    Text("Gramos").foregroundStyle(DS.text2)
                    Spacer()
                    NumberField(placeholder: "g", value: $grams, decimals: false, width: 110)
                }
            }
            Picker("Comida", selection: $entry.mealRaw) {
                ForEach(MealType.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            let v = entry.per100.map { $0.scaled(toGrams: grams ?? entry.grams) } ?? entry.values
            Text("\(NumberFormat.integer(v.kcal)) kcal · P \(Int(v.protein)) g · H \(Int(v.carbs)) g · G \(Int(v.fat)) g")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(DS.text2)
            HStack(spacing: 12) {
                Button(role: .destructive) {
                    context.delete(entry); try? context.save(); dismiss()
                } label: { Label("Quitar", systemImage: "trash") }
                .buttonStyle(.secondary)
                Button("Guardar") {
                    if let grams { entry.setGrams(grams) }
                    try? context.save()
                    dismiss()
                }
                .buttonStyle(.primary)
            }
        }
        .padding(20)
        .onAppear { grams = entry.grams }
        .presentationBackground(Color(red: 0.06, green: 0.065, blue: 0.09))
    }
}
