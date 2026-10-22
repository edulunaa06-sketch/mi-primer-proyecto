import SwiftData
import SwiftUI
import UIKit

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
                                previousDate: previous?.weekStart,
                                onChange: touch
                            )
                        }
                    }
                    completeButton(log)
                } else {
                    ProgressView().padding(40)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Editar") { editingRoutine = true }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .onAppear {
            // Crear el registro de la semana NO marca nada como completado.
            log = DataStore.fetchOrCreateLog(for: current, weekStart: weekStart, in: context)
            previous = DataStore.previousLog(for: current, before: weekStart, in: context)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-NNEditRoutine") { editingRoutine = true }
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

    private func touch() {
        log?.lastModified = Date()
        try? context.save()
    }

    private func summary(_ log: WorkoutSessionLog) -> some View {
        let progress = SessionProgress(session: current, log: log)
        return HStack(spacing: 16) {
            ProgressRing(fraction: progress.fraction, size: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(progress.completedExercises) de \(progress.totalExercises) ejercicios")
                    .font(.headline)
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

    private func completeButton(_ log: WorkoutSessionLog) -> some View {
        VStack(spacing: 8) {
            Button {
                withAnimation {
                    log.isCompleted.toggle()
                    log.completedAt = log.isCompleted ? Date() : nil
                }
                touch()
            } label: {
                Label(log.isCompleted ? "Sesión completada · Deshacer" : "Marcar sesión completa",
                      systemImage: log.isCompleted ? "checkmark.seal.fill" : "flag.checkered")
            }
            .buttonStyle(LimeButtonStyle(filled: !log.isCompleted))
            if let date = log.completedAt {
                Text("Completada el \(DateUtils.shortDate(date))")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.top, 4)
    }
}

struct ExerciseCard: View {
    let number: Int
    let definition: ExerciseDefinition
    @Bindable var log: ExerciseLog
    let previous: ExerciseLog?
    let previousDate: Date?
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

            HStack {
                Text("Serie").frame(width: 44, alignment: .leading)
                Text("Kg").frame(maxWidth: .infinity)
                Text("Reps").frame(maxWidth: .infinity)
                Text("Hecha").frame(width: 48)
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.textTertiary)

            ForEach(log.visibleSets) { set in
                SetRow(set: set, onChange: onChange)
            }

            if let previous {
                previousResults(previous)
            }

            NavigationLink {
                ExerciseProgressView(exerciseID: definition.id, name: definition.name)
            } label: {
                Label("Ver progresión de cargas", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption.weight(.semibold))
            }
        }
        .card()
    }

    private func previousResults(_ prev: ExerciseLog) -> some View {
        let sets = prev.sortedSets.filter { $0.weightKg != nil || $0.reps != nil }
        let text: String = sets.isEmpty
            ? "Sin datos de series"
            : sets.map { s in
                let w = s.weightKg.map { NumberFormat.oneDecimal($0) + " kg" } ?? "— kg"
                let r = s.reps.map(String.init) ?? "—"
                return "\(w) × \(r)"
            }.joined(separator: "  ·  ")
        return VStack(alignment: .leading, spacing: 2) {
            Text("Anterior\(previousDate.map { " (" + DateUtils.dayMonth($0) + ")" } ?? "")")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.lime)
            Text(text)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct SetRow: View {
    @Bindable var set: SetLog
    let onChange: () -> Void

    var body: some View {
        HStack {
            Text("\(set.index + 1)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(width: 44, alignment: .leading)
            DecimalField(placeholder: "kg", value: $set.weightKg)
                .frame(maxWidth: .infinity)
            IntField(placeholder: "reps", value: $set.reps)
                .frame(maxWidth: .infinity)
            Button {
                set.isDone.toggle()
                onChange()
            } label: {
                CheckCircle(isOn: set.isDone, size: 24)
            }
            .buttonStyle(.plain)
            .frame(width: 48)
            .accessibilityLabel(set.isDone ? "Serie terminada" : "Marcar serie terminada")
        }
        .onChange(of: set.weightKg) { _, _ in onChange() }
        .onChange(of: set.reps) { _, _ in onChange() }
    }
}
