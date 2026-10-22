import SwiftData
import SwiftUI

/// Calendario semanal. Cada semana (lunes a domingo) tiene sus propios registros:
/// al empezar una semana nueva las casillas aparecen vacías y el historial anterior se conserva.
struct TrainingView: View {
    @Query private var weekLogs: [WorkoutSessionLog]

    private let weekStart: Date
    private let todayWeekday: Int

    init() {
        let start = DateUtils.startOfWeek(Date())
        weekStart = start
        todayWeekday = DateUtils.weekdayMondayBased(Date())
        _weekLogs = Query(filter: #Predicate<WorkoutSessionLog> { $0.weekStart == start })
    }

    private func log(for session: SessionDefinition) -> WorkoutSessionLog? {
        weekLogs.first { $0.sessionID == session.id }
    }

    private var completedCount: Int {
        WeeklyRoutine.trainableSessions.filter { log(for: $0)?.isCompleted == true }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    weeklySummary
                    ForEach(1...7, id: \.self) { weekday in
                        dayCard(weekday)
                    }
                    NavigationLink {
                        TrainingHistoryView()
                    } label: {
                        Label("Historial de semanas anteriores", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(LimeButtonStyle(filled: false))
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Entrenamientos")
            .navigationDestination(for: String.self) { sessionID in
                if let session = WeeklyRoutine.session(id: sessionID) {
                    SessionDestination(session: session, weekStart: weekStart)
                }
            }
        }
    }

    private var weeklySummary: some View {
        let total = WeeklyRoutine.trainableSessions.count
        let fraction = total > 0 ? Double(completedCount) / Double(total) : 0
        return HStack(spacing: 16) {
            ProgressRing(fraction: fraction, size: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text("Cumplimiento semanal").font(.headline)
                Text("\(completedCount) de \(total) sesiones completadas")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Text("Semana del \(DateUtils.dayMonth(weekStart))")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .card()
    }

    private func dayCard(_ weekday: Int) -> some View {
        let sessions = WeeklyRoutine.sessions(forWeekday: weekday)
        let date = DateUtils.date(forWeekday: weekday, inWeekOf: weekStart)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(WeeklyRoutine.weekdayName(weekday))
                    .font(.headline)
                    .foregroundStyle(weekday == todayWeekday ? Theme.lime : Theme.textPrimary)
                Text(DateUtils.dayMonth(date))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                if weekday == todayWeekday {
                    Text("HOY")
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.lime, in: Capsule())
                        .foregroundStyle(.black)
                }
                if sessions.count > 1 {
                    Text("\(sessions.count) sesiones")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.lime)
                }
            }
            ForEach(sessions) { session in
                NavigationLink(value: session.id) {
                    sessionRow(session)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private func sessionRow(_ session: SessionDefinition) -> some View {
        let log = log(for: session)
        let progress = SessionProgress(session: session, log: log)
        return HStack(spacing: 12) {
            Image(systemName: session.kind == .run ? "figure.run" : session.kind == .rest ? "bed.double.fill" : "dumbbell.fill")
                .foregroundStyle(Theme.lime)
                .frame(width: 28, height: 28)
                .background(Theme.limeDim, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(.subheadline.weight(.semibold))
                Text(subtitle(session, progress: progress))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if session.kind != .rest {
                CheckCircle(isOn: log?.isCompleted ?? false, size: 22)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .padding(10)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func subtitle(_ session: SessionDefinition, progress: SessionProgress) -> String {
        switch session.kind {
        case .rest: return "Recuperación"
        case .run: return session.detail
        case .strength:
            return "\(progress.completedExercises)/\(progress.totalExercises) ejercicios · \(NumberFormat.percent(progress.fraction))"
        }
    }
}

/// Progreso de una sesión a partir de los ejercicios marcados manualmente.
struct SessionProgress {
    let completedExercises: Int
    let totalExercises: Int

    init(session: SessionDefinition, log: WorkoutSessionLog?) {
        totalExercises = session.exercises.count
        let ids = Set(session.exercises.map(\.id))
        completedExercises = log?.exercises.filter { $0.isCompleted && ids.contains($0.exerciseID) }.count ?? 0
    }

    var fraction: Double {
        totalExercises > 0 ? Double(completedExercises) / Double(totalExercises) : 0
    }
}

/// Elige la pantalla adecuada según el tipo de sesión.
struct SessionDestination: View {
    let session: SessionDefinition
    let weekStart: Date

    var body: some View {
        switch session.kind {
        case .strength: StrengthSessionView(session: session, weekStart: weekStart)
        case .run: RunSessionView(session: session, weekStart: weekStart)
        case .rest: RestDayView(session: session)
        }
    }
}

struct RestDayView: View {
    let session: SessionDefinition
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Theme.lime)
                    .padding(.top, 24)
                Text("Día de descanso").font(.title.bold())
                Text(session.detail)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                VStack(alignment: .leading, spacing: 10) {
                    Label("Duerme 7–9 horas si puedes.", systemImage: "moon.zzz.fill")
                    Label("Mantén la hidratación y tu plan de comidas.", systemImage: "drop.fill")
                    Label("Movilidad o paseo suave opcional.", systemImage: "figure.walk")
                    Label("Sin entrenamiento de fuerza hoy.", systemImage: "xmark.circle")
                }
                .font(.subheadline)
                .card()
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Viernes")
        .navigationBarTitleDisplayMode(.inline)
    }
}
