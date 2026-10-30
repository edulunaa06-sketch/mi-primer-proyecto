import SwiftData
import SwiftUI

/// Resumen de una semana (lunes a domingo) en una sola pantalla.
struct WeeklySummaryView: View {
    @Environment(\.modelContext) private var context
    @Query private var meals: [MealRecord]
    @Query private var sessionKinds: [SessionKindChoice]
    @Query private var logs: [WorkoutSessionLog]
    @Query private var dailySteps: [DailySteps]
    @Query private var marks: [DayMarkRecord]
    @Query private var settingsList: [UserSettings]
    @Query(sort: \WeightEntry.date) private var weights: [WeightEntry]
    @Query(sort: \StravaActivityRecord.startDate) private var runs: [StravaActivityRecord]

    @State private var weekStart = DateUtils.startOfWeek(Date())
    @State private var trackingStart = DateUtils.startOfDay(Date())
    /// Se calcula una vez (y de nuevo solo si cambian los datos), no en cada redibujado.
    @State private var snapshot: TrackingSnapshot?

    private var signature: String {
        TrackingSnapshot.signature(meals: meals, logs: logs, steps: dailySteps, marks: marks,
                                   stepGoal: settingsList.first?.stepGoal ?? 8000, trackingStart: trackingStart)
    }

    private var weekEnd: Date { DateUtils.calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart }
    private var isCurrentWeek: Bool { weekStart == DateUtils.startOfWeek(Date()) }

    var body: some View {
        let snap = snapshot ?? TrackingSnapshot(meals: [], logs: [], steps: [], marks: [],
                                                         stepGoal: settingsList.first?.stepGoal ?? 8000, trackingStart: trackingStart)
        let days = snap.days(from: weekStart, through: weekEnd.addingTimeInterval(-1))
        let outcomes = days.map(snap.outcome(for:))
        let summary = WeeklySummary.make(
            stepsByDay: days.compactMap(snap.steps),
            runs: runs.filter { StravaAPI.runSportTypes.contains($0.sportType) || $0.isManual }.map(\.sample),
            weights: weights.map { WeightStats.Point(date: $0.date, kg: $0.weightKg) },
            outcomes: outcomes, weekStart: weekStart, weekEnd: weekEnd)
        let weekLogs = logs.filter { $0.weekStart == weekStart && $0.isCompleted }
        let trainable = WeeklyRoutine.trainable(kinds: sessionKinds).count

        ScrollView {
            VStack(spacing: 16) {
                weekNavigation
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricTile(title: "Media de pasos",
                               value: summary.averageSteps.map { NumberFormat.integer($0) } ?? "—",
                               detail: summary.daysWithSteps == 0 ? "Sin datos de pasos" : "\(summary.daysWithSteps) \(summary.daysWithSteps == 1 ? "día" : "días") con datos",
                               symbol: "shoeprints.fill")
                    MetricTile(title: "Km corridos",
                               value: summary.runs == 0 ? "—" : Medals.km(summary.kilometers),
                               detail: summary.runs == 0 ? "Sin carreras registradas" : "\(summary.runs) \(summary.runs == 1 ? "carrera" : "carreras")",
                               symbol: "figure.run")
                    MetricTile(title: "Cambio de peso",
                               value: summary.weightChange.map(NumberFormat.signedKg) ?? "—",
                               detail: summary.weightChange == nil ? "Necesita pesajes esta semana" : "Último pesaje vs. el anterior",
                               symbol: "scalemass.fill")
                    MetricTile(title: "Días cumplidos",
                               value: "\(summary.daysDone)/\(days.count)",
                               detail: "\(summary.daysExcused) descanso/libres · \(summary.daysMissed) fallados",
                               symbol: "checkmark.seal.fill")
                }
                daysStrip(days: days, outcomes: outcomes)
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Entreno de la semana")
                    HStack {
                        Text("Sesiones completadas").foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text("\(weekLogs.count)/\(trainable)").font(.headline.monospacedDigit())
                    }
                    ProgressBar(fraction: trainable > 0 ? Double(weekLogs.count) / Double(trainable) : 0)
                }
                .card()
                InfoBanner(text: "Pasos: sensor del iPhone (solo hay datos de los días que abriste la app o de los 7 días anteriores a abrirla). Km: carreras importadas de Strava o apuntadas a mano en Entreno.",
                           symbol: "info.circle.fill", color: Theme.accent)
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .onAppear { trackingStart = DataStore.trackingStart(context) }
        .task(id: signature) {
            snapshot = TrackingSnapshot(meals: meals, logs: logs, steps: dailySteps, marks: marks,
                                        stepGoal: settingsList.first?.stepGoal ?? 8000, trackingStart: trackingStart)
        }
    }

    private var weekNavigation: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left").font(.headline) }
                .accessibilityLabel("Semana anterior")
            Spacer()
            VStack(spacing: 2) {
                Text(isCurrentWeek ? "Esta semana" : "Semana del \(DateUtils.dayMonth(weekStart))").font(.headline)
                Text("\(DateUtils.dayMonth(weekStart)) – \(DateUtils.dayMonth(weekEnd.addingTimeInterval(-1)))")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right").font(.headline) }
                .disabled(isCurrentWeek)
                .accessibilityLabel("Semana siguiente")
        }
        .foregroundStyle(Theme.accent)
        .card(padding: 12)
    }

    private func daysStrip(days: [Date], outcomes: [DayOutcome]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Día a día")
            HStack(spacing: 6) {
                ForEach(days.indices, id: \.self) { i in
                    VStack(spacing: 4) {
                        Text(["L", "M", "X", "J", "V", "S", "D"][i % 7])
                            .font(.caption2.weight(.bold)).foregroundStyle(Theme.textTertiary)
                        DayCell(date: days[i], outcome: outcomes[i], isToday: DateUtils.calendar.isDateInToday(days[i]))
                    }
                }
            }
        }
        .card()
    }

    private func shift(_ weeks: Int) {
        guard let next = DateUtils.calendar.date(byAdding: .day, value: 7 * weeks, to: weekStart) else { return }
        withAnimation { weekStart = DateUtils.startOfWeek(next) }
    }
}
