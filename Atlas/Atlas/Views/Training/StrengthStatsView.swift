import Charts
import SwiftData
import SwiftUI

/// Estadísticas de fuerza: volumen por grupo muscular, frecuencia, programado frente a
/// realizado, estancamientos, descarga y récords. Todo sale de las series apuntadas.
struct StrengthStatsView: View {
    @Environment(\.modelContext) private var context

    @State private var range: ReportRange = .week
    @State private var muscles: [VolumeAnalytics.MuscleVolume] = []
    @State private var previousMuscles: [VolumeAnalytics.MuscleVolume] = []
    @State private var unclassified: [String] = []
    @State private var adherence = VolumeAnalytics.Adherence(programmedSets: 0, performedSets: 0)
    @State private var warnings: [VolumeAnalytics.Warning] = []
    @State private var totals: (sets: Int, tonnage: Double) = (0, 0)
    @State private var deload = ProgressionEngine.DeloadSuggestion(isRecommended: false, reason: "", plan: "")
    @State private var stalled: [String] = []
    @State private var records: [PersonalRecordEntry] = []
    @State private var isDeloadWeek = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                rangePicker
                if totals.sets == 0 {
                    EmptyStateView(symbol: "chart.bar",
                                   title: "Todavía no hay series apuntadas",
                                   message: "Apunta kilos y repeticiones en una sesión de fuerza y aquí verás tu volumen por músculo, la frecuencia y la progresión.")
                        .card()
                } else {
                    totalsCard
                    volumeCard
                    frequencyCard
                }
                deloadCard
                if !warnings.isEmpty { warningsCard }
                if !records.isEmpty { recordsCard }
                methodNote
            }
            .padding(16)
        }
        .screenBackground()
        .tabBarRoom()
        .navigationTitle("Fuerza")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onChange(of: range) { _, _ in reload() }
    }

    // MARK: Carga

    private func reload() {
        let period = range.period(endingAt: Date())
        let work = StrengthStore.work(from: period.start, to: period.end, in: context)
        let result = VolumeAnalytics.byMuscle(work)
        muscles = result.muscles
        unclassified = Array(Set(result.unclassified.map(\.name))).sorted()
        totals = (VolumeAnalytics.totalWorkSets(work), VolumeAnalytics.totalTonnage(work))

        let previousPeriod = range.previousPeriod(endingAt: Date())
        let previousWork = StrengthStore.work(from: previousPeriod.start, to: previousPeriod.end, in: context)
        previousMuscles = VolumeAnalytics.byMuscle(previousWork).muscles

        let weeks = max(Double(period.dayCount) / 7, 0.1)
        let programmed = Int((Double(StrengthStore.programmedSetsPerWeek(in: context)) * weeks).rounded())
        adherence = VolumeAnalytics.adherence(programmedSets: programmed, work: work)
        warnings = VolumeAnalytics.warnings(week: muscles, previous: previousMuscles)

        records = StrengthStore.records(in: context)
        isDeloadWeek = StrengthStore.isDeloadWeek(DateUtils.startOfWeek(Date()), in: context)

        // Estancamientos y tendencias que bajan, por ejercicio con historial.
        var stalledNames: [String] = []
        var falling = 0
        let byExercise = Dictionary(grouping: work, by: \.exerciseID)
        for (exerciseID, items) in byExercise {
            let history = StrengthStore.history(exerciseID: exerciseID, in: context)
            if ProgressionEngine.stallReport(history: history).isStalled {
                stalledNames.append(items.first?.name ?? exerciseID)
            }
            if StrengthTrend(summaries: history).verdict == .falling { falling += 1 }
        }
        stalled = stalledNames.sorted()
        deload = ProgressionEngine.deloadSuggestion(
            hardWeeksInARow: 0,
            stalledExercises: stalled.count,
            musclesAboveReference: muscles.filter { $0.verdict == .above }.count,
            fallingTrends: falling
        )
    }

    // MARK: Secciones

    private var rangePicker: some View {
        Picker("Periodo", selection: $range) {
            ForEach(ReportRange.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }

    private var totalsCard: some View {
        HStack(spacing: 10) {
            MetricTile(title: "Series de trabajo", value: NumberFormat.integer(totals.sets), symbol: "list.number")
            MetricTile(title: "Kilos movidos", value: NumberFormat.integer(totals.tonnage), detail: "peso × repeticiones",
                       symbol: "scalemass")
            MetricTile(title: "De lo programado",
                       value: adherence.fraction.map { NumberFormat.percent($0) } ?? "—",
                       detail: adherence.label, symbol: "target")
        }
    }

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Series por grupo muscular",
                          subtitle: "Directas (el músculo era el principal). La línea marca la referencia habitual.")
            Chart {
                ForEach(muscles) { item in
                    BarMark(
                        x: .value("Series", item.directSets),
                        y: .value("Músculo", item.group.shortLabel)
                    )
                    .foregroundStyle(barColor(item.verdict))
                    .cornerRadius(4)
                }
                ForEach(muscles) { item in
                    RuleMark(
                        xStart: .value("Mínimo", item.reference.typical.lowerBound),
                        xEnd: .value("Máximo", item.reference.typical.upperBound),
                        y: .value("Músculo", item.group.shortLabel)
                    )
                    .foregroundStyle(Theme.textTertiary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [3, 2]))
                }
            }
            .chartXAxis { AxisMarks(position: .bottom) }
            .frame(height: CGFloat(max(muscles.count, 1)) * 26 + 30)

            ForEach(muscles.filter { $0.totalSets > $0.directSets }.prefix(4)) { item in
                Text("\(item.group.label): \(NumberFormat.oneDecimal(item.directSets)) directas "
                     + "y \(NumberFormat.oneDecimal(item.totalSets)) contando el trabajo indirecto.")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }

            if !unclassified.isEmpty {
                InfoBanner(text: "Estos ejercicios no están en la biblioteca, así que sus series no se reparten por "
                           + "músculo: \(unclassified.joined(separator: ", ")).",
                           symbol: "questionmark.circle", color: Theme.textSecondary)
            }
        }
        .card()
    }

    private func barColor(_ verdict: VolumeReference.Verdict) -> Color {
        switch verdict {
        case .inRange: return Theme.accent
        case .below: return Theme.textSecondary
        case .above: return Theme.warning
        case .none: return Theme.cardRaised
        }
    }

    private var frequencyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Frecuencia", subtitle: "Días distintos en los que has trabajado cada grupo.")
            ForEach(muscles.filter { $0.directSets > 0 }) { item in
                HStack {
                    Text(item.group.label).font(.subheadline)
                    Spacer()
                    Text(NumberFormat.plural(item.frequency, "día", "días"))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    Text(item.verdict.label)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(barColor(item.verdict).opacity(0.16), in: Capsule())
                        .foregroundStyle(barColor(item.verdict))
                }
            }
        }
        .card()
    }

    private var deloadCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Descarga")
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: deload.isRecommended ? "moon.zzz.fill" : "checkmark.circle")
                    .foregroundStyle(deload.isRecommended ? Theme.warning : Theme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(deload.isRecommended ? "Te vendría bien una semana de descarga" : "Por ahora no hace falta descargar")
                        .font(.subheadline.weight(.semibold))
                    Text(deload.reason).font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if deload.isRecommended {
                        Text(deload.plan).font(.caption2).foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !stalled.isEmpty {
                Text("Estancados: \(stalled.joined(separator: ", ")).")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Toggle("Esta semana es de descarga", isOn: Binding(
                get: { isDeloadWeek },
                set: { value in
                    isDeloadWeek = value
                    StrengthStore.setDeload(value, weekStart: DateUtils.startOfWeek(Date()), in: context)
                }
            ))
            .font(.subheadline)
            Text("Si la marcas, la progresión deja de proponerte subir kilos durante esta semana.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        .card()
    }

    private var warningsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Avisos de volumen")
            ForEach(warnings) { warning in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: warning.kind == .aboveReference || warning.kind == .bigJump
                          ? "exclamationmark.triangle.fill" : "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(warning.kind == .belowReference ? Theme.textSecondary : Theme.warning)
                    Text(warning.message).font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card()
    }

    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Récords personales", subtitle: "Lo mejor que has apuntado en cada ejercicio.")
            ForEach(records.prefix(12)) { record in
                HStack(spacing: 10) {
                    Image(systemName: record.kind.symbol).font(.caption).foregroundStyle(Theme.gold)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(record.exerciseName).font(.subheadline.weight(.semibold))
                        Text("\(record.kind.label) · \(DateUtils.dayMonth(record.date))")
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Text(record.valueText)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                }
            }
            if records.count > 12 {
                Text("Y \(records.count - 12) más.").font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            Text("El 1RM es una estimación a partir de tu mejor serie, no una medición real.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        .card()
    }

    private var methodNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cómo se cuenta").font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
            Text("Una serie cuenta como directa para el músculo principal del ejercicio y como media serie "
                 + "para los que solo ayudan. Los calentamientos no cuentan. La referencia de series semanales "
                 + "es una orientación general de la literatura de entrenamiento, no una receta: lo que te vale "
                 + "depende de tu recuperación y tu experiencia.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
