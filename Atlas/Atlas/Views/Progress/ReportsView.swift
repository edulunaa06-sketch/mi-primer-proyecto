import SwiftData
import SwiftUI

/// Informes por periodo: entrenamiento, nutrición, cuerpo y recuperación en una sola pantalla,
/// con la comparación con el periodo anterior. Cuando falta información, se dice.
struct ReportsView: View {
    @Environment(\.modelContext) private var context

    @State private var range: ReportRange = .week
    @State private var report: PeriodReport?
    @State private var comparison: ReportComparison?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                picker
                if let report {
                    periodHeader(report)
                    if !report.hasAnyData {
                        EmptyStateView(symbol: "doc.text.magnifyingglass",
                                       title: "Nada apuntado en este periodo",
                                       message: "Apunta entrenamientos, comidas o pesajes y el informe se llenará solo.")
                            .card()
                    } else {
                        if !report.highlights.isEmpty { highlightsCard(report) }
                        trainingCard(report.training)
                        nutritionCard(report.nutrition)
                        bodyCard(report.body)
                        recoveryCard(report.recovery)
                        if let comparison, !comparison.deltas.isEmpty { comparisonCard(comparison) }
                    }
                    if !report.caveats.isEmpty { caveatsCard(report) }
                } else {
                    ProgressView().padding(40)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .tabBarRoom()
        .navigationTitle("Informes")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onChange(of: range) { _, _ in reload() }
    }

    private func reload() {
        let current = ReportBuilder.build(StrengthStore.reportInput(range: range, in: context))
        let previousPeriod = range.previousPeriod(endingAt: Date())
        let previous = ReportBuilder.build(StrengthStore.reportInput(period: previousPeriod, in: context))
        report = current
        comparison = ReportComparer.compare(current: current, previous: previous)
    }

    private var picker: some View {
        Picker("Periodo", selection: $range) {
            ForEach(ReportRange.allCases) { option in Text(option.label).tag(option) }
        }
        .pickerStyle(.segmented)
    }

    private func periodHeader(_ report: PeriodReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(report.period.label.uppercased())
                .font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(Theme.accent)
            Text(report.period.text).font(.headline)
            Text("\(report.period.dayCount) días").font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func highlightsCard(_ report: PeriodReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Lo que ha pasado")
            ForEach(Array(report.highlights.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(Theme.accent).frame(width: 5, height: 5).padding(.top, 6)
                    Text(line).font(.footnote).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card()
    }

    private func trainingCard(_ training: TrainingReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Entrenamiento")
            if !training.hasEnoughData {
                Text("Sin entrenamientos apuntados en este periodo.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            } else {
                HStack(spacing: 10) {
                    MetricTile(title: "Sesiones", value: NumberFormat.integer(training.sessionsCompleted),
                               detail: "de \(training.sessionsScheduled) previstas", symbol: "figure.strengthtraining.traditional")
                    MetricTile(title: "Series", value: NumberFormat.integer(training.workSets), symbol: "list.number")
                    MetricTile(title: "Kilos", value: NumberFormat.integer(training.tonnageKg), symbol: "scalemass")
                }
                if training.newRecords > 0 {
                    Label(NumberFormat.plural(training.newRecords, "récord batido", "récords batidos"), systemImage: "rosette")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.gold)
                }
                if !training.muscles.isEmpty {
                    Text("Series directas por músculo").font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(training.muscles.filter { $0.directSets > 0 }) { item in
                        HStack {
                            Text(item.group.label).font(.caption)
                            Spacer()
                            Text(NumberFormat.oneDecimal(item.directSets))
                                .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                if !training.untrainedGroups.isEmpty {
                    Text("Sin trabajo directo: "
                         + training.untrainedGroups.map(\.label).joined(separator: ", ") + ".")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card()
    }

    private func nutritionCard(_ nutrition: NutritionReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Nutrición")
            if !nutrition.hasEnoughData {
                Text(nutrition.daysLogged == 0
                     ? "Sin comidas apuntadas en este periodo."
                     : "Solo " + NumberFormat.plural(nutrition.daysLogged, "día apuntado", "días apuntados")
                     + " de \(nutrition.daysInPeriod): una media con tan pocos días no representa lo que comes.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 10) {
                    MetricTile(title: "Kcal al día",
                               value: nutrition.averageKcal.map { NumberFormat.integer($0) } ?? "—",
                               detail: nutrition.kcalDifference.map {
                                   ($0 > 0 ? "+" : "") + NumberFormat.integer($0) + " vs objetivo" },
                               symbol: "flame.fill")
                    MetricTile(title: "Proteína",
                               value: nutrition.averageProtein.map { NumberFormat.integer($0) + " g" } ?? "—",
                               symbol: "fish.fill", symbolColor: Theme.protein)
                    MetricTile(title: "Días apuntados",
                               value: "\(nutrition.daysLogged)/\(nutrition.daysInPeriod)",
                               detail: nutrition.coverage.map { NumberFormat.percent($0) },
                               symbol: "calendar")
                }
                HStack(spacing: 10) {
                    MetricTile(title: "Hidratos",
                               value: nutrition.averageCarbs.map { NumberFormat.integer($0) + " g" } ?? "—",
                               symbol: "leaf.fill", symbolColor: Theme.carbs)
                    MetricTile(title: "Grasas",
                               value: nutrition.averageFat.map { NumberFormat.integer($0) + " g" } ?? "—",
                               symbol: "drop.fill", symbolColor: Theme.fat)
                }
            }
        }
        .card()
    }

    private func bodyCard(_ body: BodyReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Cuerpo", subtitle: "Comparando medias semanales, no pesajes sueltos.")
            if !body.hasEnoughData {
                Text(body.weighIns == 0
                     ? "Sin pesajes en este periodo."
                     : "Hay " + NumberFormat.plural(body.weighIns, "pesaje", "pesajes")
                     + ", pero hacen falta en dos semanas distintas para ver una tendencia.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 10) {
                    MetricTile(title: "Cambio",
                               value: body.change.map { NumberFormat.signedKg($0) } ?? "—",
                               detail: body.changePerWeek.map { NumberFormat.signedKg($0) + " / semana" },
                               symbol: "arrow.up.arrow.down")
                    MetricTile(title: "Media actual",
                               value: body.lastWeight.map { NumberFormat.weight($0) } ?? "—",
                               symbol: "scalemass.fill")
                    MetricTile(title: "Pesajes", value: NumberFormat.integer(body.weighIns), symbol: "number")
                }
            }
        }
        .card()
    }

    private func recoveryCard(_ recovery: RecoveryReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Recuperación")
            if !recovery.hasEnoughData {
                Text("Con " + NumberFormat.plural(recovery.averages.daysLogged, "día apuntado", "días apuntados")
                     + " no hay base para una media.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            } else {
                HStack(spacing: 10) {
                    MetricTile(title: "Sueño",
                               value: recovery.averages.sleepHours.map { NumberFormat.oneDecimal($0) + " h" } ?? "—",
                               symbol: "moon.fill")
                    MetricTile(title: "Fatiga",
                               value: recovery.averages.fatigue.map { NumberFormat.oneDecimal($0) } ?? "—",
                               detail: "de 5", symbol: "battery.25")
                    MetricTile(title: "Molestias",
                               value: NumberFormat.integer(recovery.averages.daysWithDiscomfort),
                               detail: "días", symbol: "bandage.fill")
                }
            }
        }
        .card()
    }

    private func comparisonCard(_ comparison: ReportComparison) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Frente al periodo anterior",
                          subtitle: comparison.previous.period.text)
            ForEach(Array(comparison.deltas.enumerated()), id: \.offset) { _, delta in
                HStack {
                    Text(delta.label).font(.subheadline)
                    Spacer()
                    Text(valueText(delta))
                        .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    Text(differenceText(delta))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(deltaColor(delta))
                }
            }
            Text("Comparar dos periodos muestra qué ha cambiado, no por qué ha cambiado.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        .card()
    }

    private func valueText(_ delta: ReportComparison.Delta) -> String {
        "\(NumberFormat.oneDecimal(delta.previous)) → \(NumberFormat.oneDecimal(delta.current))"
    }

    private func differenceText(_ delta: ReportComparison.Delta) -> String {
        let sign = delta.difference > 0 ? "+" : ""
        if let percent = delta.percent, abs(percent) < 1000 {
            return "\(sign)\(NumberFormat.oneDecimal(delta.difference)) (\(sign)\(NumberFormat.integer(percent)) %)"
        }
        return "\(sign)\(NumberFormat.oneDecimal(delta.difference))"
    }

    private func deltaColor(_ delta: ReportComparison.Delta) -> Color {
        guard let better = delta.higherIsBetter, abs(delta.difference) > 0.001 else { return Theme.textSecondary }
        let isGood = better ? delta.difference > 0 : delta.difference < 0
        return isGood ? Theme.accent : Theme.warning
    }

    private func caveatsCard(_ report: PeriodReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Qué falta para que esto sea fiable")
            ForEach(Array(report.caveats.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").font(.caption2).foregroundStyle(Theme.textTertiary)
                    Text(line).font(.caption2).foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card()
    }
}
