import SwiftUI
import SwiftData

/// Entreno: la semana entera, con el día de hoy destacado.
struct WorkoutView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutDayPlan.weekday) private var days: [WorkoutDayPlan]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    private var todayIndex: Int { DateHelper.weekdayIndex() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.normal) {
                    ForEach(days) { day in
                        NavigationLink {
                            WorkoutDayView(day: day)
                        } label: {
                            dayCard(day)
                        }
                        .buttonStyle(.plain)
                    }

                    if !recentSessions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Últimos entrenos")
                            ForEach(recentSessions) { session in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.title)
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                            .foregroundStyle(Theme.text)
                                        Text(DateHelper.longName(session.date))
                                            .font(Theme.caption)
                                            .foregroundStyle(Theme.textTertiary)
                                    }
                                    Spacer()
                                    Text(sessionSummary(session))
                                        .font(Theme.caption)
                                        .foregroundStyle(Theme.accent)
                                }
                                if session.id != recentSessions.last?.id {
                                    Divider().background(Theme.separator)
                                }
                            }
                        }
                        .card()
                        .padding(.top, 6)
                    }
                }
                .padding(Theme.Spacing.screen)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Entreno")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear { PlanService.seedRoutineIfNeeded(context: context) }
    }

    private var recentSessions: [WorkoutSession] {
        Array(sessions.filter(\.hasContent).prefix(5))
    }

    private func sessionSummary(_ session: WorkoutSession) -> String {
        var parts: [String] = []
        let filled = session.setLogs.filter(\.isFilled).count
        if filled > 0 { parts.append("\(filled) series") }
        if session.distanceKm > 0 { parts.append(Formatters.distance(session.distanceKm)) }
        if session.durationMinutes > 0 { parts.append(Formatters.minutes(session.durationMinutes)) }
        return parts.joined(separator: " · ")
    }

    private func dayCard(_ day: WorkoutDayPlan) -> some View {
        let isToday = day.weekday == todayIndex
        return HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(DateHelper.weekdayShortName(day.weekday).uppercased())
                    .font(.system(size: 12, weight: .black, design: .rounded))
                Image(systemName: day.kind.icon)
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(isToday ? Color.black : Theme.accent)
            .frame(width: 54, height: 54)
            .background(isToday ? Theme.accent : Theme.accentMuted)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(day.name)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.text)
                    if isToday { TagLabel(text: "Hoy") }
                }
                Text(subtitle(for: day))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(isToday ? Theme.accent.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
    }

    private func subtitle(for day: WorkoutDayPlan) -> String {
        switch day.kind {
        case .rest:
            return day.note.isEmpty ? "Descanso" : day.note
        case .cardio:
            return day.note.isEmpty ? "Carrera suave" : day.note
        case .strength:
            return "\(day.exercises.count) ejercicios"
        case .strengthCardio:
            return "\(day.exercises.count) ejercicios · \(day.note.isEmpty ? "y carrera" : day.note)"
        }
    }
}

#Preview {
    WorkoutView()
        .modelContainer(SampleData.container)
        .preferredColorScheme(.dark)
}
