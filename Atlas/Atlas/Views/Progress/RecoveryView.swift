import Charts
import SwiftData
import SwiftUI

/// Recuperación del día: sueño, energía, fatiga, estrés, agujetas y molestias.
/// Resume lo que apuntas. No diagnostica nada.
struct RecoveryView: View {
    @Environment(\.modelContext) private var context

    @State private var entry: RecoveryLogEntry?
    @State private var readiness = Readiness(score: nil, inputsUsed: 0, verdict: .unknown, message: "", warnings: [])
    @State private var weekAverages = RecoveryAnalysis.averages([])
    @State private var relation = RecoveryPerformance.Relation(coefficient: nil, points: 0, summary: "")

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let entry {
                    readinessCard
                    questionsCard(entry)
                    if !readiness.warnings.isEmpty { warningsCard }
                    weekCard
                    relationCard
                    tipsCard
                } else {
                    ProgressView().padding(40)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .tabBarRoom()
        .navigationTitle("Recuperación")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    // MARK: Carga y guardado

    private func load() {
        let today = StrengthStore.fetchOrCreateRecovery(for: Date(), in: context)
        entry = today
        refresh(today)
        // La correlación mira diez semanas: se calcula una vez al abrir, no en cada toque.
        relation = sleepRelation()
    }

    private func refresh(_ today: RecoveryLogEntry) {
        let recent = StrengthStore.recentRecovery(days: 7, in: context)
        readiness = RecoveryAnalysis.readiness(today.entry, recent: recent)
        let week = ReportRange.week.period(endingAt: Date())
        let entries = StrengthStore.recovery(from: week.start, to: week.end, in: context)
        weekAverages = RecoveryAnalysis.averages(entries)
    }

    private func save() {
        guard let entry else { return }
        entry.updatedAt = Date()
        try? context.save()
        refresh(entry)
    }

    /// Relaciona el sueño medio de cada semana con el tonelaje de esa misma semana.
    private func sleepRelation() -> RecoveryPerformance.Relation {
        var sleep: [Double] = []
        var tonnage: [Double] = []
        for weeksAgo in (0..<10).reversed() {
            guard let end = DateUtils.calendar.date(byAdding: .day, value: -7 * weeksAgo, to: Date()) else { continue }
            let week = ReportRange.week.period(endingAt: end)
            let entries = StrengthStore.recovery(from: week.start, to: week.end, in: context)
            guard let hours = RecoveryAnalysis.averages(entries).sleepHours else { continue }
            let work = StrengthStore.work(from: week.start, to: week.end, in: context)
            let total = VolumeAnalytics.totalTonnage(work)
            guard total > 0 else { continue }
            sleep.append(hours)
            tonnage.append(total)
        }
        return RecoveryPerformance.sleepVersusTonnage(sleep: sleep, tonnage: tonnage)
    }

    // MARK: Secciones

    private var readinessCard: some View {
        HStack(spacing: 16) {
            if let score = readiness.score {
                ProgressRing(fraction: Double(score) / 100, size: 76, label: "\(score)",
                             color: readinessColor)
            } else {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 40)).foregroundStyle(Theme.textTertiary)
                    .frame(width: 76, height: 76)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(readiness.verdict.label).font(.headline).foregroundStyle(readinessColor)
                Text(readiness.message)
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if readiness.inputsUsed > 0 {
                    Text("Calculado con \(readiness.inputsUsed) de 6 respuestas.")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    private var readinessColor: Color {
        switch readiness.verdict {
        case .good: return Theme.accent
        case .fair: return Theme.warning
        case .low: return Theme.danger
        case .unknown: return Theme.textSecondary
        }
    }

    private func questionsCard(_ entry: RecoveryLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Hoy", subtitle: "Contesta solo lo que quieras: lo que dejes en blanco no cuenta.")

            HStack {
                Text("Horas de sueño").font(.subheadline)
                Spacer()
                DecimalField(placeholder: "–", value: Binding(
                    get: { entry.sleepHours },
                    set: { entry.sleepHours = $0; save() }
                ), width: 70)
            }

            scaleRow("Calidad del sueño", value: Binding(
                get: { entry.sleepQuality }, set: { entry.sleepQuality = $0; save() }), better: true)
            scaleRow("Energía", value: Binding(
                get: { entry.energy }, set: { entry.energy = $0; save() }), better: true)
            scaleRow("Fatiga", value: Binding(
                get: { entry.fatigue }, set: { entry.fatigue = $0; save() }), better: false)
            scaleRow("Estrés", value: Binding(
                get: { entry.stress }, set: { entry.stress = $0; save() }), better: false)
            scaleRow("Agujetas", value: Binding(
                get: { entry.soreness }, set: { entry.soreness = $0; save() }), better: false)

            Toggle("Tengo una molestia o un dolor", isOn: Binding(
                get: { entry.hasDiscomfort },
                set: { entry.hasDiscomfort = $0; save() }
            ))
            .font(.subheadline)

            TextField("Nota del día (opcional)", text: Binding(
                get: { entry.note }, set: { entry.note = $0 }
            ), axis: .vertical)
                .font(.footnote)
                .lineLimit(1...4)
                .padding(10)
                .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onSubmit(save)
        }
        .card()
    }

    /// Fila de 1 a 5 con el significado escrito, para que no haya que adivinar la escala.
    private func scaleRow(_ title: String, value: Binding<Int?>, better: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                if let current = value.wrappedValue {
                    Text(better ? RecoveryScale.betterLabel(current) : RecoveryScale.worseLabel(current))
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    Button {
                        value.wrappedValue = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityLabel("Borrar \(title)")
                } else {
                    Text("sin contestar").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
            HStack(spacing: 6) {
                ForEach(Array(RecoveryScale.range), id: \.self) { option in
                    Button {
                        value.wrappedValue = option
                        DS.haptic()
                    } label: {
                        Text("\(option)")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(value.wrappedValue == option ? Theme.accentDim : Theme.cardRaised,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(value.wrappedValue == option ? Theme.accent : Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title): \(option)")
                }
            }
        }
    }

    private var warningsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "A tener en cuenta")
            ForEach(Array(readiness.warnings.enumerated()), id: \.offset) { _, warning in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Theme.warning)
                    Text(warning).font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card()
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Esta semana")
            if weekAverages.daysLogged == 0 {
                Text("Aún no has apuntado ningún día esta semana.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            } else {
                HStack(spacing: 10) {
                    MetricTile(title: "Sueño medio",
                               value: weekAverages.sleepHours.map { NumberFormat.oneDecimal($0) + " h" } ?? "—",
                               symbol: "moon.fill")
                    MetricTile(title: "Fatiga media",
                               value: weekAverages.fatigue.map { NumberFormat.oneDecimal($0) } ?? "—",
                               detail: "de 5", symbol: "battery.25")
                    MetricTile(title: "Días apuntados",
                               value: NumberFormat.integer(weekAverages.daysLogged),
                               detail: weekAverages.daysWithDiscomfort > 0
                               ? "\(weekAverages.daysWithDiscomfort) con molestias" : nil,
                               symbol: "calendar")
                }
            }
        }
        .card()
    }

    private var relationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Sueño y entrenamiento")
            Text(relation.summary)
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Descanso y movilidad")
            ForEach(RecoveryTips.all) { tip in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: tip.symbol).font(.subheadline).foregroundStyle(Theme.accent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tip.title).font(.subheadline.weight(.semibold))
                        Text(tip.detail).font(.caption).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .card()
    }
}
