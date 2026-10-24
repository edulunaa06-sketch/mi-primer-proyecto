import SwiftUI
import SwiftData

/// Nutrición: el menú del día, los cambios de plato y lo añadido a mano.
struct NutritionView: View {
    @Environment(\.modelContext) private var context
    @Bindable var profile: UserProfile

    @Query private var dayPlans: [DayPlan]
    @Query(sort: \ManualFood.createdAt) private var manualFoods: [ManualFood]

    @State private var selectedDate = DateHelper.startOfDay()
    @State private var mealToSwap: PlannedMeal?
    @State private var showingManualSheet = false

    private var plan: DayPlan? {
        dayPlans.first { DateHelper.isSameDay($0.date, selectedDate) }
    }

    private var dayManualFoods: [ManualFood] {
        manualFoods.filter { DateHelper.isSameDay($0.date, selectedDate) }
    }

    private var targets: NutritionTargets { profile.targets }

    private var eaten: MacroTotals {
        var total = plan?.eatenTotals ?? .zero
        for food in dayManualFoods { total += food.totals }
        return total
    }

    private var planned: MacroTotals {
        var total = plan?.plannedTotals ?? .zero
        for food in dayManualFoods { total += food.totals }
        return total
    }

    var body: some View {
        NavigationStack {
            List {
                row { DayStrip(selectedDate: $selectedDate) }
                row { summaryCard }

                if let plan {
                    ForEach(plan.sortedMeals) { meal in
                        row {
                            MealCard(meal: meal,
                                     onToggle: { toggle(meal) },
                                     onSwap: { mealToSwap = meal })
                        }
                    }
                }

                row {
                    SectionHeader(title: "Añadido a mano")
                        .padding(.top, 4)
                }

                if dayManualFoods.isEmpty {
                    row {
                        Text("Nada por ahora. Si comes algo fuera del menú, apúntalo aquí.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                } else {
                    ForEach(dayManualFoods) { food in
                        ManualFoodRow(food: food)
                            .listRowInsets(EdgeInsets(top: 5, leading: Theme.Spacing.screen,
                                                      bottom: 5, trailing: Theme.Spacing.screen))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(food)
                                } label: {
                                    Label("Borrar", systemImage: "trash.fill")
                                }
                            }
                    }
                }

                row {
                    Button {
                        showingManualSheet = true
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "plus")
                            Text("Añadir manual")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 2)
                }

                row {
                    Button("Generar otro menú para este día") {
                        if let plan {
                            PlanService.regenerate(plan, profile: profile, context: context)
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.bottom, 20)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Nutrición")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear { ensurePlan() }
        .onChange(of: selectedDate) { ensurePlan() }
        .sheet(item: $mealToSwap) { meal in
            MealSwapSheet(meal: meal, targets: targets) { recipe in
                PlanService.swap(meal, to: recipe, profile: profile, context: context)
            }
        }
        .sheet(isPresented: $showingManualSheet) {
            ManualFoodSheet(date: selectedDate) { food in
                context.insert(food)
                try? context.save()
            }
        }
    }

    // MARK: - Piezas

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: DateHelper.friendlyName(selectedDate))
                Spacer()
                TagLabel(text: "\(Formatters.kcal(eaten.calories)) / \(Formatters.kcal(targets.calories)) kcal")
            }

            MacroBars(eaten: eaten, targets: targets)

            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                Text("El menú completo suma \(Formatters.kcal(planned.calories)) kcal. Solo cuenta lo marcado.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .card()
    }

    /// Envoltorio para que las filas de la lista se vean como tarjetas sueltas.
    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .listRowInsets(EdgeInsets(top: 7, leading: Theme.Spacing.screen,
                                      bottom: 7, trailing: Theme.Spacing.screen))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    // MARK: - Acciones

    private func ensurePlan() {
        PlanService.dayPlan(for: selectedDate, profile: profile, context: context)
    }

    private func toggle(_ meal: PlannedMeal) {
        withAnimation(.easeOut(duration: 0.2)) {
            meal.done.toggle()
        }
        try? context.save()
    }

    private func delete(_ food: ManualFood) {
        context.delete(food)
        try? context.save()
    }
}

// MARK: - Selector de día

/// Tira horizontal de días; por defecto, hoy.
struct DayStrip: View {
    @Binding var selectedDate: Date

    private var days: [Date] {
        (-10...10).map { DateHelper.addDays($0, to: DateHelper.startOfDay()) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        dayChip(day)
                            .id(day)
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear {
                proxy.scrollTo(DateHelper.startOfDay(selectedDate), anchor: .center)
            }
        }
    }

    private func dayChip(_ day: Date) -> some View {
        let isSelected = DateHelper.isSameDay(day, selectedDate)
        let isToday = DateHelper.isSameDay(day, .now)
        return Button {
            withAnimation(.easeOut(duration: 0.2)) { selectedDate = day }
        } label: {
            VStack(spacing: 3) {
                Text(DateHelper.weekdayShortName(DateHelper.weekdayIndex(day)).uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                Text(DateHelper.dayMonth(day))
                    .font(.system(size: 14, weight: .black, design: .rounded))
            }
            .foregroundStyle(isSelected ? Color.black : (isToday ? Theme.accent : Theme.textSecondary))
            .frame(width: 58, height: 54)
            .background(isSelected ? Theme.accent : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fila de comida manual

struct ManualFoodRow: View {
    let food: ManualFood

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "pencil")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Theme.accentMuted)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(food.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                MacroChips(totals: food.totals, compact: true)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 13)
    }
}

#Preview {
    NutritionView(profile: SampleData.profile)
        .modelContainer(SampleData.container)
        .preferredColorScheme(.dark)
}
