import SwiftData
import SwiftUI

/// Calendario semanal. Cada semana (lunes a domingo) tiene sus propios registros:
/// al empezar una semana nueva las casillas aparecen vacías y el historial anterior se conserva.
struct TrainingView: View {
    @Environment(\.modelContext) private var context
    @Query private var weekLogs: [WorkoutSessionLog]
    @Query(sort: \RoutineExercise.order) private var routine: [RoutineExercise]
    @Query private var titles: [SessionTitle]
    @State private var path: [String] = []
    @State private var renaming: SessionDefinition?
    @State private var confirmScratch = false
    @State private var confirmDefaults = false
    @State private var newTitle = ""

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
        NavigationStack(path: $path) {
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
                    Menu {
                        Button("Empezar mi rutina desde cero", role: .destructive) { confirmScratch = true }
                        Button("Volver a la rutina predeterminada") { confirmDefaults = true }
                    } label: {
                        Label("Opciones de la rutina", systemImage: "slider.horizontal.3")
                    }
                    .font(.footnote.weight(.semibold))
                    Text("Mantén pulsada una sesión para cambiarle el nombre; dentro de cada sesión de fuerza, «Editar» para sus ejercicios.")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
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
            .confirmationDialog("¿Empezar la rutina desde cero?", isPresented: $confirmScratch, titleVisibility: .visible) {
                Button("Vaciar las sesiones de fuerza", role: .destructive) { DataStore.startRoutineFromScratch(in: context) }
            } message: {
                Text("Las sesiones de fuerza se quedan sin ejercicios y con nombre genérico para que pongas los tuyos. El historial de semanas anteriores se conserva.")
            }
            .confirmationDialog("¿Volver a la rutina predeterminada?", isPresented: $confirmDefaults, titleVisibility: .visible) {
                Button("Restaurar Push / Pull / Pierna") { DataStore.restoreAllDefaults(in: context) }
            } message: {
                Text("Se recuperan los ejercicios y nombres originales. El historial se conserva.")
            }
            .alert("Nombre de la sesión", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Nombre", text: $newTitle)
                Button("Guardar") { if let s = renaming { DataStore.renameSession(s.id, to: newTitle, in: context) } }
                Button("Nombre original") { if let s = renaming { DataStore.renameSession(s.id, to: "", in: context) } }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("El historial y los registros de la sesión se conservan.")
            }
            #if DEBUG
            .onAppear {
                // Solo en Debug: el CI abre una sesión concreta para capturas de pantalla.
                let args = ProcessInfo.processInfo.arguments
                if path.isEmpty, let i = args.firstIndex(of: "-NNSession"), i + 1 < args.count {
                    path = [args[i + 1]]
                }
            }
            #endif
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
                        .foregroundStyle(Theme.onLime)
                }
                if sessions.count > 1 {
                    Text("\(sessions.count) sesiones")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.lime)
                }
            }
            ForEach(sessions) { session in
                HStack(spacing: 8) {
                    NavigationLink(value: session.id) {
                        sessionRow(session)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            newTitle = session.renamed(titles).title
                            renaming = session
                        } label: { Label("Cambiar nombre", systemImage: "pencil") }
                    }
                    if session.kind != .rest { doneButton(session) }
                }
            }
        }
        .card()
    }

    private func sessionRow(_ base: SessionDefinition) -> some View {
        let session = base.resolved(with: routine, titles: titles)
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
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .padding(10)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Marcar una sesión como hecha (o deshacerlo) directamente desde la semana, sin entrar.
    /// Fuerza: marca (o desmarca) todos sus ejercicios, igual que si lo hicieras dentro; los kilos y repeticiones no se tocan.
    private func doneButton(_ base: SessionDefinition) -> some View {
        let session = base.resolved(with: routine, titles: titles)
        let done = log(for: session)?.isCompleted ?? false
        return Button {
            let log = DataStore.fetchOrCreateLog(for: session, weekStart: weekStart, in: context)
            withAnimation {
                log.toggleDoneFromWeek(session: session)
            }
            try? context.save()
        } label: {
            VStack(spacing: 2) {
                CheckCircle(isOn: done, size: 30)
                Text(done ? "Hecho" : "Marcar").font(.caption2.weight(.semibold))
                    .foregroundStyle(done ? Theme.lime : Theme.textSecondary)
            }
            .frame(width: 56, height: 56)
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done ? "\(session.title): hecha. Deshacer" : "Marcar \(session.title) como hecha")
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

    /// Todos los ejercicios marcados (una sesión sin ejercicios nunca cuenta como hecha sola).
    var isComplete: Bool { totalExercises > 0 && completedExercises == totalExercises }
}

extension WorkoutSessionLog {
    /// Botón «Marcar / Hecho» de la semana. En fuerza marca o desmarca todos los ejercicios
    /// (así dentro de la sesión se ve igual); una sesión sin ejercicios se marca directamente.
    func toggleDoneFromWeek(session: SessionDefinition) {
        let markDone = !isCompleted
        if session.kind == .strength, !session.exercises.isEmpty {
            let ids = Set(session.exercises.map(\.id))
            for ex in exercises where ids.contains(ex.exerciseID) { ex.isCompleted = markDone }
            syncStrengthCompletion(with: session)
        } else {
            isCompleted = markDone
            completedAt = markDone ? Date() : nil
        }
        lastModified = Date()
    }

    /// Fuerza: la sesión está completada exactamente cuando todos sus ejercicios están marcados.
    func syncStrengthCompletion(with session: SessionDefinition) {
        let done = SessionProgress(session: session, log: self).isComplete
        guard done != isCompleted else { return }
        isCompleted = done
        completedAt = done ? Date() : nil
    }
}

extension ExerciseLog {
    /// Al terminar la última serie el ejercicio se marca solo; al desmarcar una serie, se desmarca.
    func syncCompletionWithSets(lastSetDone: Bool) {
        let sets = visibleSets
        if !sets.isEmpty, sets.allSatisfy(\.isDone) {
            isCompleted = true
        } else if !lastSetDone {
            isCompleted = false
        }
    }
}

/// Elige la pantalla adecuada según el tipo de sesión.
struct SessionDestination: View {
    let session: SessionDefinition
    let weekStart: Date

    @Environment(\.modelContext) private var context
    @Query private var titles: [SessionTitle]
    @State private var renaming = false
    @State private var newTitle = ""

    var body: some View {
        let named = session.renamed(titles)
        Group {
            switch session.kind {
            case .strength: StrengthSessionView(session: named, weekStart: weekStart)
            case .run: RunSessionView(session: named, weekStart: weekStart)
            case .rest: RestDayView(session: named)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newTitle = named.title
                    renaming = true
                } label: { Image(systemName: "pencil") }
                .accessibilityLabel("Cambiar nombre de la sesión")
            }
        }
        .alert("Nombre de la sesión", isPresented: $renaming) {
            TextField("Nombre", text: $newTitle)
            Button("Guardar") { DataStore.renameSession(session.id, to: newTitle, in: context) }
            Button("Nombre original") { DataStore.renameSession(session.id, to: "", in: context) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Original: \(session.title). El historial se conserva.")
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
