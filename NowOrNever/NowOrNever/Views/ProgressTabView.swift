import SwiftUI
import SwiftData
import Charts

/// Progreso: registro de peso y gráfica de la evolución.
struct ProgressTabView: View {
    @Environment(\.modelContext) private var context
    @Bindable var profile: UserProfile
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]

    @State private var showingAddSheet = false

    private var first: WeightEntry? { weights.first }
    private var last: WeightEntry? { weights.last }
    private var difference: Double? {
        guard let first, let last, weights.count > 1 else { return nil }
        return last.kg - first.kg
    }

    var body: some View {
        NavigationStack {
            List {
                row { statsCard }
                row { chartCard }
                row {
                    Button {
                        showingAddSheet = true
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "plus")
                            Text("Añadir peso")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                row {
                    SectionHeader(title: "Registros")
                        .padding(.top, 4)
                }

                if weights.isEmpty {
                    row {
                        Text("Aún no has apuntado ningún peso. Con uno al mes es suficiente para ver la tendencia.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                } else {
                    ForEach(weights.reversed()) { entry in
                        weightRow(entry)
                            .listRowInsets(EdgeInsets(top: 5, leading: Theme.Spacing.screen,
                                                      bottom: 5, trailing: Theme.Spacing.screen))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(entry)
                                } label: {
                                    Label("Borrar", systemImage: "trash.fill")
                                }
                            }
                    }
                }

                row { Color.clear.frame(height: 20) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Progreso")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddWeightSheet { date, kg in
                PlanService.saveWeight(kg, on: date, context: context)
                // El peso más reciente manda también en el perfil.
                if let newest = weights.last, DateHelper.startOfDay(date) >= newest.date {
                    profile.weightKg = kg
                } else if weights.isEmpty {
                    profile.weightKg = kg
                }
                try? context.save()
            }
        }
    }

    // MARK: - Piezas

    private var statsCard: some View {
        HStack(spacing: 10) {
            StatTile(title: "Inicial",
                     value: first.map { Formatters.weight($0.kg) } ?? "—",
                     unit: first == nil ? nil : "kg")
            StatTile(title: "Actual",
                     value: last.map { Formatters.weight($0.kg) } ?? "—",
                     unit: last == nil ? nil : "kg")
            StatTile(title: "Diferencia",
                     value: difference.map { Formatters.signedWeight($0) } ?? "—",
                     unit: difference == nil ? nil : "kg",
                     color: (difference ?? 0) <= 0 ? Theme.accent : Theme.danger)
        }
        .card()
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Evolución del peso")

            if weights.count < 2 {
                Text("Apunta al menos dos pesos y aquí verás la línea de tu progreso.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                    .multilineTextAlignment(.center)
            } else {
                Chart(weights) { entry in
                    AreaMark(x: .value("Fecha", entry.date),
                             y: .value("Peso", entry.kg))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.02)],
                                           startPoint: .top,
                                           endPoint: .bottom)
                        )

                    LineMark(x: .value("Fecha", entry.date),
                             y: .value("Peso", entry.kg))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))

                    PointMark(x: .value("Fecha", entry.date),
                              y: .value("Peso", entry.kg))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(45)
                }
                .chartYScale(domain: yDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(Theme.separator)
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(DateHelper.dayMonth(date))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Theme.separator)
                        AxisValueLabel {
                            if let kg = value.as(Double.self) {
                                Text(Formatters.weight(kg))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
                .frame(height: 210)
            }
        }
        .card()
    }

    private var yDomain: ClosedRange<Double> {
        let values = weights.map(\.kg)
        let low = (values.min() ?? 60) - 1.5
        let high = (values.max() ?? 80) + 1.5
        return low...max(low + 1, high)
    }

    private func weightRow(_ entry: WeightEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(DateHelper.shortDate(entry.date))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(DateHelper.weekdayName(DateHelper.weekdayIndex(entry.date)))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Text("\(Formatters.weight(entry.kg)) kg")
                .font(Theme.number(19))
                .foregroundStyle(Theme.accent)
        }
        .card(padding: 14)
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .listRowInsets(EdgeInsets(top: 7, leading: Theme.Spacing.screen,
                                      bottom: 7, trailing: Theme.Spacing.screen))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func delete(_ entry: WeightEntry) {
        context.delete(entry)
        try? context.save()
    }
}

/// Apuntar un peso con su fecha.
struct AddWeightSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (Date, Double) -> Void

    @State private var date = Date.now
    @State private var kg = ""

    private var isValid: Bool {
        guard let value = Formatters.parse(kg) else { return false }
        return value > 25 && value < 300
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                NumberField(title: "Peso", text: $kg, unit: "kg", placeholder: "74,5")

                VStack(alignment: .leading, spacing: 8) {
                    Text("FECHA")
                        .font(Theme.overline)
                        .kerning(1.1)
                        .foregroundStyle(Theme.textTertiary)
                    DatePicker("", selection: $date, in: ...Date.now, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(Theme.accent)
                        .environment(\.locale, DateHelper.locale)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("Guardar") {
                    if let value = Formatters.parse(kg) {
                        onSave(date, value)
                    }
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isValid)
                .opacity(isValid ? 1 : 0.45)

                Spacer()
            }
            .padding(Theme.Spacing.screen)
            .screenBackground()
            .navigationTitle("Añadir peso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Theme.background)
    }
}

#Preview {
    ProgressTabView(profile: SampleData.profile)
        .modelContainer(SampleData.container)
        .preferredColorScheme(.dark)
}
