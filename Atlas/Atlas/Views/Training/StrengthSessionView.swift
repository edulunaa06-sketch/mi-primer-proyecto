import SwiftData
import SwiftUI

struct StrengthSessionView: View {
    /// Sesión base; los ejercicios reales salen de la rutina personalizada guardada.
    let session: SessionDefinition
    let weekStart: Date

    @Environment(\.modelContext) private var context
    @Query(sort: \RoutineExercise.order) private var routine: [RoutineExercise]
    @State private var log: WorkoutSessionLog?
    @State private var previous: WorkoutSessionLog?
    @State private var editingRoutine = false

    private var current: SessionDefinition { session.resolved(with: routine) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let log {
                    summary(log)
                    if current.exercises.isEmpty {
                        EmptyStateView(symbol: "dumbbell", title: "Sesión sin ejercicios",
                                       message: "Pulsa “Editar” para añadir ejercicios a esta sesión.")
                            .card()
                    }
                    ForEach(Array(current.exercises.enumerated()), id: \.element.id) { index, exercise in
                        if let exLog = log.exercises.first(where: { $0.exerciseID == exercise.id }) {
                            ExerciseCard(
                                number: index + 1,
                                definition: exercise,
                                log: exLog,
                                previous: previous?.exercises.first { $0.exerciseID == exercise.id },
                                onChange: touch
                            )
                        }
                    }
                } else {
                    ProgressView().padding(40)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Editar") { editingRoutine = true }
            }
        }
        .onAppear {
            // Crear el registro de la semana NO marca nada como completado.
            log = DataStore.fetchOrCreateLog(for: current, weekStart: weekStart, in: context)
            previous = DataStore.previousLog(for: current, before: weekStart, in: context)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-AtlasEditRoutine") { editingRoutine = true }
            #endif
        }
        .sheet(isPresented: $editingRoutine, onDismiss: {
            // Aplica los cambios de la rutina al registro de esta semana (series nuevas, nombres…).
            if let log {
                DataStore.ensureStructure(log, session: current, in: context)
                try? context.save()
            }
        }) {
            RoutineEditorView(session: session)
        }
        .onDisappear { try? context.save() }
    }

    /// Cada cambio guarda y, si ya están marcados todos los ejercicios, la sesión queda completada sola.
    private func touch() {
        guard let log else { return }
        withAnimation { log.syncStrengthCompletion(with: current) }
        log.lastModified = Date()
        try? context.save()
    }

    private func summary(_ log: WorkoutSessionLog) -> some View {
        let progress = SessionProgress(session: current, log: log)
        return HStack(spacing: 16) {
            ProgressRing(fraction: progress.fraction, size: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(progress.completedExercises) de \(progress.totalExercises) ejercicios")
                    .font(.headline)
                if log.isCompleted {
                    Label("Sesión completada", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.lime)
                } else {
                    Text("Marca todos los ejercicios y la sesión se completa sola.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Text(session.detail).font(.subheadline).foregroundStyle(Theme.textSecondary)
                if let previous {
                    Text("Sesión anterior: semana del \(DateUtils.dayMonth(previous.weekStart))")
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                } else {
                    Text("Sin sesiones anteriores registradas")
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
        }
        .card()
    }
}

struct ExerciseCard: View {
    let number: Int
    let definition: ExerciseDefinition
    @Bindable var log: ExerciseLog
    let previous: ExerciseLog?
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text("\(number)")
                    .font(.caption.weight(.heavy))
                    .frame(width: 24, height: 24)
                    .background(Theme.limeDim, in: Circle())
                    .foregroundStyle(Theme.lime)
                VStack(alignment: .leading, spacing: 2) {
                    Text(definition.name).font(.headline)
                    Text("\(definition.sets) series · \(definition.repRange) repeticiones")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Button {
                    log.isCompleted.toggle()
                    onChange()
                } label: {
                    CheckCircle(isOn: log.isCompleted, size: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(log.isCompleted ? "Ejercicio completado" : "Marcar ejercicio completado")
            }

            if previous != nil {
                Label("Ya lo hiciste la semana pasada", systemImage: "arrow.counterclockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .card()
    }
}
