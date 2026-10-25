import SwiftData
import SwiftUI

/// Historial por semanas. Solo lectura: nunca se borra al cambiar de semana.
struct TrainingHistoryView: View {
    @Query(sort: \WorkoutSessionLog.weekStart, order: .reverse) private var logs: [WorkoutSessionLog]
    @Query private var titles: [SessionTitle]

    private var weeks: [(start: Date, logs: [WorkoutSessionLog])] {
        let grouped = Dictionary(grouping: logs.filter(\.hasUserData)) { $0.weekStart }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            if weeks.isEmpty {
                EmptyStateView(symbol: "clock", title: "Sin historial", message: "Cuando registres series o completes sesiones aparecerán aquí, agrupadas por semana.")
                    .listRowBackground(Theme.card)
            }
            ForEach(weeks, id: \.start) { week in
                Section {
                    ForEach(week.logs.sorted(by: sessionOrder)) { log in
                        if let session = WeeklyRoutine.session(id: log.sessionID)?.renamed(titles) {
                            NavigationLink {
                                SessionHistoryDetail(session: session, log: log)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(session.title).font(.subheadline.weight(.semibold))
                                        Text(WeeklyRoutine.weekdayName(session.weekday)).font(.caption).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    CheckCircle(isOn: log.isCompleted, size: 20)
                                }
                            }
                        }
                    }
                } header: {
                    let done = week.logs.filter(\.isCompleted).count
                    Text("Semana del \(DateUtils.shortDate(week.start)) · \(done)/\(WeeklyRoutine.trainableSessions.count)")
                }
                .listRowBackground(Theme.card)
            }
        }
        .screenBackground()
        .navigationTitle("Historial")
    }

    private func sessionOrder(_ a: WorkoutSessionLog, _ b: WorkoutSessionLog) -> Bool {
        let ia = WeeklyRoutine.allSessions.firstIndex { $0.id == a.sessionID } ?? 0
        let ib = WeeklyRoutine.allSessions.firstIndex { $0.id == b.sessionID } ?? 0
        return ia < ib
    }
}

struct SessionHistoryDetail: View {
    let session: SessionDefinition
    let log: WorkoutSessionLog

    var body: some View {
        List {
            Section {
                LabeledContent("Estado", value: log.isCompleted ? "Completada" : "No completada")
                if let date = log.completedAt {
                    LabeledContent("Fecha", value: DateUtils.shortDate(date))
                }
            }
            .listRowBackground(Theme.card)
            // Se muestra lo que se registró esa semana (nombres guardados), aunque la rutina haya cambiado.
            Section {
                ForEach(log.sortedExercises) { exLog in
                    HStack {
                        Text(exLog.displayName)
                        Spacer()
                        if !exLog.repRange.isEmpty {
                            Text("\(exLog.targetSets) × \(exLog.repRange)")
                                .font(.caption.monospacedDigit()).foregroundStyle(Theme.textTertiary)
                        }
                        CheckCircle(isOn: exLog.isCompleted, size: 18)
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("Ejercicios")
            }
            .listRowBackground(Theme.card)
        }
        .screenBackground()
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
