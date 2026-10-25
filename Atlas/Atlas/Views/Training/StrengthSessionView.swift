import SwiftData
import SwiftUI

/// La sesión de fuerza en vivo: cada serie con sus kilos, repeticiones y RIR, lo que hiciste
/// la vez anterior y qué propone la progresión. Se puede pausar y cerrar la app: no se pierde nada.
struct StrengthSessionView: View {
    /// Sesión base; los ejercicios reales salen de la rutina personalizada guardada.
    let session: SessionDefinition
    let weekStart: Date

    @Environment(\.modelContext) private var context
    @Query(sort: \RoutineExercise.order) private var routine: [RoutineExercise]
    @State private var log: WorkoutSessionLog?
    @State private var previous: WorkoutSessionLog?
    @State private var editingRoutine = false
    @State private var newRecords: [RecordCandidate] = []
    @State private var showingRecords = false
    @State private var infoExercise: ExerciseInfo?
    @State private var confirmFinish = false
    /// Propuesta de progresión por ejercicio. Se calcula al abrir la pantalla: depende solo de
    /// las sesiones anteriores, así que no hace falta recalcularla con cada cambio.
    @State private var adviceByExercise: [String: ProgressionEngine.Advice] = [:]

    private var current: SessionDefinition { session.resolved(with: routine) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let log {
                    SessionSummaryCard(session: current, log: log, previous: previous,
                                       onToggleClock: { toggleClock(log) })

                    if current.exercises.isEmpty {
                        EmptyStateView(symbol: "dumbbell", title: "Sesión sin ejercicios",
                                       message: "Pulsa “Editar” para añadir ejercicios a esta sesión.")
                            .card()
                    }

                    ForEach(Array(current.exercises.enumerated()), id: \.element.id) { index, exercise in
                        if let exerciseLog = log.exercises.first(where: { $0.exerciseID == exercise.id }) {
                            ExerciseSetsCard(
                                number: index + 1,
                                definition: exercise,
                                log: exerciseLog,
                                previous: previous?.exercises.first { $0.exerciseID == exercise.id },
                                advice: adviceByExercise[exercise.id] ?? ProgressionEngine.advise(history: [], target: exerciseLog.repTarget),
                                onChange: touch,
                                onShowInfo: { infoExercise = $0 }
                            )
                        }
                    }

                    if !current.exercises.isEmpty {
                        finishButton(log)
                    }
                } else {
                    ProgressView().padding(40)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .tabBarRoom()
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Editar") { editingRoutine = true }
            }
            // El teclado numérico no tiene tecla de retorno: hace falta una forma de cerrarlo.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { hideKeyboard() }
            }
        }
        .onAppear(perform: load)
        .sheet(isPresented: $editingRoutine, onDismiss: {
            // Aplica los cambios de la rutina al registro de esta semana (series nuevas, nombres…).
            if let log {
                DataStore.ensureStructure(log, session: current, in: context)
                prepareSets(log)
                try? context.save()
            }
        }) {
            RoutineEditorView(session: session)
        }
        .sheet(item: $infoExercise) { info in
            NavigationStack { ExerciseDetailView(info: info) }
        }
        .sheet(isPresented: $showingRecords) {
            NewRecordsSheet(records: newRecords)
        }
        .confirmationDialog("¿Terminar el entreno?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Terminar y guardar") { finish() }
        } message: {
            Text("Se para el cronómetro, la sesión queda como hecha y se comprueban tus récords. "
                 + "Podrás seguir editando las series después.")
        }
        .onDisappear {
            // Al salir se guarda, pero el cronómetro sigue: el entreno no se ha terminado.
            try? context.save()
        }
    }

    // MARK: Carga

    private func load() {
        // Crear el registro de la semana NO marca nada como completado.
        let created = DataStore.fetchOrCreateLog(for: current, weekStart: weekStart, in: context)
        previous = DataStore.previousLog(for: current, before: weekStart, in: context)
        prepareSets(created)
        var advice: [String: ProgressionEngine.Advice] = [:]
        for exerciseLog in created.exercises {
            advice[exerciseLog.exerciseID] = StrengthStore.advice(for: exerciseLog, in: context)
        }
        adviceByExercise = advice
        log = created
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-AtlasEditRoutine") { editingRoutine = true }
        #endif
    }

    /// Crea las filas de serie que falten, con el peso que propone la progresión.
    private func prepareSets(_ log: WorkoutSessionLog) {
        for exerciseLog in log.exercises {
            StrengthStore.ensureSets(for: exerciseLog, in: context)
        }
    }

    // MARK: Cambios

    /// Cada cambio guarda. La sesión sigue a los ejercicios mientras no se haya terminado.
    /// Lo que NO se hace aquí: tocar el estado de los ejercicios. Eso solo cambia cuando el
    /// usuario marca una serie o el propio ejercicio, para que la app no deshaga lo que marca.
    private func touch() {
        guard let log else { return }
        withAnimation {
            if log.finishedAt == nil {
                log.syncStrengthCompletion(with: current)
            }
        }
        log.lastModified = Date()
        // La primera serie apuntada pone el cronómetro en marcha sin tener que pulsar nada.
        if log.clock.accumulatedSeconds == 0, !log.isRunning, log.workSets > 0 {
            log.startOrResume()
        }
        try? context.save()
    }

    private func toggleClock(_ log: WorkoutSessionLog) {
        log.clock = log.clock.toggled(at: Date())
        log.lastModified = Date()
        try? context.save()
        DS.haptic()
    }

    private func finish() {
        guard let log else { return }
        log.finish()
        log.isCompleted = true
        log.completedAt = log.completedAt ?? Date()
        // Los ejercicios con series apuntadas quedan como hechos.
        for exerciseLog in log.exercises where exerciseLog.hasLoggedData {
            exerciseLog.isCompleted = true
        }
        try? context.save()

        let records = StrengthStore.updateRecords(from: log, in: context)
        newRecords = records
        if !records.isEmpty {
            showingRecords = true
            DS.haptic(.heavy)
        }
    }

    private func finishButton(_ log: WorkoutSessionLog) -> some View {
        VStack(spacing: 8) {
            Button {
                confirmFinish = true
            } label: {
                Label(log.finishedAt == nil ? "Terminar entreno" : "Volver a guardar", systemImage: "checkmark.seal.fill")
            }
            .buttonStyle(LimeButtonStyle())
            .accessibilityIdentifier("session.finish")

            if let finished = log.finishedAt {
                Text("Terminado a las \(DateUtils.time(finished)) · \(SessionClock.text(seconds: log.accumulatedSeconds))")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            } else {
                Text("Apunta los kilos y las repeticiones de cada serie. Si cierras la app, el entreno sigue donde estaba.")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Cabecera de la sesión

struct SessionSummaryCard: View {
    let session: SessionDefinition
    @Bindable var log: WorkoutSessionLog
    let previous: WorkoutSessionLog?
    let onToggleClock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                let progress = SessionProgress(session: session, log: log)
                ProgressRing(fraction: progress.fraction, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(progress.completedExercises) de \(progress.totalExercises) ejercicios")
                        .font(.headline)
                    if log.isCompleted {
                        Label("Sesión completada", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.lime)
                    } else {
                        Text(session.detail).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    if let previous {
                        Text("Sesión anterior: semana del \(DateUtils.dayMonth(previous.weekStart))")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    } else {
                        Text("Sin sesiones anteriores registradas")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
            }

            Divider().overlay(Theme.separator)

            HStack(spacing: 10) {
                clock
                stat(NumberFormat.integer(log.workSets), "series", "list.number")
                stat(NumberFormat.integer(log.tonnageKg), "kg movidos", "scalemass")
            }
        }
        .card()
    }

    /// Cronómetro de la sesión. Se actualiza cada segundo solo mientras está en marcha.
    private var clock: some View {
        Button(action: onToggleClock) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: log.isRunning ? "pause.circle.fill" : "play.circle.fill")
                        .foregroundStyle(Theme.lime)
                    if log.isRunning {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(SessionClock.text(seconds: log.elapsedSeconds(at: context.date)))
                                .font(.subheadline.weight(.bold).monospacedDigit())
                        }
                    } else {
                        Text(SessionClock.text(seconds: log.accumulatedSeconds))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                    }
                }
                Text(log.isRunning ? "en marcha" : "en pausa")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(log.isRunning ? "Pausar el cronómetro" : "Poner el cronómetro en marcha")
    }

    private func stat(_ value: String, _ title: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.caption).foregroundStyle(Theme.textSecondary)
                Text(value).font(.subheadline.weight(.bold).monospacedDigit())
            }
            Text(title).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Tarjeta de un ejercicio con sus series

struct ExerciseSetsCard: View {
    let number: Int
    let definition: ExerciseDefinition
    @Bindable var log: ExerciseLog
    let previous: ExerciseLog?
    let advice: ProgressionEngine.Advice
    let onChange: () -> Void
    let onShowInfo: (ExerciseInfo) -> Void

    @Environment(\.modelContext) private var context
    @State private var showingNote = false
    @State private var showingAdvice = false

    private var info: ExerciseInfo? { ExerciseCatalog.info(id: log.exerciseID, name: log.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if showingAdvice { adviceDetail }
            if let previous, previous.hasLoggedData { previousLine(previous) }
            setList
            footer
            if showingNote { noteField }
        }
        .card()
    }

    // MARK: Cabecera

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.heavy))
                .frame(width: 24, height: 24)
                .background(Theme.limeDim, in: Circle())
                .foregroundStyle(Theme.lime)
            VStack(alignment: .leading, spacing: 3) {
                Text(definition.name).font(.headline)
                HStack(spacing: 6) {
                    Text("\(definition.sets) × \(definition.repRange)")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    if let info {
                        Text("·").foregroundStyle(Theme.textTertiary)
                        Text(info.primary.shortLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.lime)
                    }
                    if log.hasDiscomfort {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(Theme.warning)
                    }
                }
                adviceBadge
            }
            Spacer()
            Menu {
                if let info {
                    Button { onShowInfo(info) } label: { Label("Ver la ficha del ejercicio", systemImage: "info.circle") }
                }
                Button { showingNote.toggle() } label: { Label("Nota de este ejercicio", systemImage: "square.and.pencil") }
                Button {
                    log.hasDiscomfort.toggle()
                    onChange()
                } label: {
                    Label(log.hasDiscomfort ? "Quitar la molestia" : "Apuntar una molestia",
                          systemImage: log.hasDiscomfort ? "bandage" : "exclamationmark.triangle")
                }
                Button { StrengthStore.addSet(to: log, kind: .warmup, in: context); onChange() } label: {
                    Label("Añadir calentamiento", systemImage: "flame")
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Theme.textSecondary)
            }
            .accessibilityLabel("Opciones de \(definition.name)")
        }
    }

    private var adviceBadge: some View {
        Button { withAnimation { showingAdvice.toggle() } } label: {
            HStack(spacing: 5) {
                Image(systemName: advice.action.symbol).font(.caption2)
                Text(advice.action.label).font(.caption2.weight(.bold))
                if let weight = advice.suggestedWeightKg, advice.action == .increaseLoad || advice.action == .reduceLoad {
                    Text("· \(NumberFormat.weight(weight))").font(.caption2.weight(.semibold))
                }
                Image(systemName: showingAdvice ? "chevron.up" : "chevron.down").font(.system(size: 8))
            }
            .foregroundStyle(adviceColor)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(adviceColor.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Progresión: \(advice.action.label). Toca para ver el motivo.")
    }

    private var adviceColor: Color {
        switch advice.action {
        case .increaseLoad: return Theme.lime
        case .reduceLoad, .deload: return Theme.warning
        case .needMoreData: return Theme.textSecondary
        default: return Theme.textSecondary
        }
    }

    private var adviceDetail: some View {
        Text(advice.reason)
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func previousLine(_ previous: ExerciseLog) -> some View {
        let sets = previous.loggedSets.filter { $0.kind.countsAsWork && $0.hasReps }
        let text = sets.map { set in
            let weight = set.weightKg.map { NumberFormat.plate($0) + "×" } ?? ""
            return weight + "\(set.reps ?? 0)"
        }.joined(separator: "  ")
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: "clock.arrow.circlepath").font(.caption2).foregroundStyle(Theme.textTertiary)
            Text("La vez anterior: \(text)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Series

    private var setList: some View {
        VStack(spacing: 6) {
            SetRowHeader()
            ForEach(log.sortedSets) { set in
                SetRow(set: set, onChange: onChange, onSetCompleted: {
                    // Marcar o desmarcar una serie SÍ arrastra al ejercicio: es lo que se espera.
                    log.followSets()
                    onChange()
                }, onDelete: {
                    StrengthStore.removeSet(set, in: context)
                    onChange()
                })
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                StrengthStore.addSet(to: log, in: context)
                onChange()
                DS.haptic()
            } label: {
                Label("Añadir serie", systemImage: "plus")
            }
            .buttonStyle(.secondaryCompact)

            Spacer()

            if log.workSets > 0 {
                Text(NumberFormat.plural(log.workSets, "serie", "series") + " · \(NumberFormat.integer(log.volumeKg)) kg")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }

            Button {
                log.isCompleted.toggle()
                onChange()
            } label: {
                CheckCircle(isOn: log.isCompleted, size: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(log.isCompleted ? "Ejercicio completado" : "Marcar ejercicio completado")
        }
    }

    private var noteField: some View {
        TextField("Cómo ha ido, sensaciones, ajustes…", text: $log.note, axis: .vertical)
            .font(.footnote)
            .lineLimit(1...4)
            .padding(10)
            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onChange(of: log.note) { _, _ in onChange() }
    }
}

// MARK: - Fila de una serie

struct SetRowHeader: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("#").frame(width: 22)
            Text("KG").frame(width: 62)
            Text("REPS").frame(width: 50)
            Text("RIR").frame(width: 44)
            Spacer()
        }
        .font(.system(size: 9, weight: .heavy))
        .foregroundStyle(Theme.textTertiary)
        .accessibilityHidden(true)
    }
}

struct SetRow: View {
    @Bindable var set: SetLog
    let onChange: () -> Void
    /// Se llama solo al marcar o desmarcar la serie (no al escribir kilos o repeticiones).
    let onSetCompleted: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                // Toca el número para cambiar entre calentamiento y serie efectiva.
                set.kind = set.kind == .warmup ? .effective : .warmup
                onChange()
            } label: {
                Text(set.kind == .warmup ? "C" : "\(set.order + 1)")
                    .font(.caption2.weight(.heavy))
                    .frame(width: 22, height: 22)
                    .background(set.kind == .warmup ? Theme.warning.opacity(0.2) : Theme.cardRaised, in: Circle())
                    .foregroundStyle(set.kind == .warmup ? Theme.warning : Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.kind == .warmup ? "Serie de calentamiento" : "Serie \(set.order + 1)")
            .accessibilityHint("Cambia entre calentamiento y serie efectiva")

            DecimalField(placeholder: "–", value: $set.weightKg, width: 62)
                .accessibilityLabel("Kilos de la serie \(set.order + 1)")
                .onChange(of: set.weightKg) { _, _ in onChange() }

            IntField(placeholder: "–", value: $set.reps, width: 50)
                .accessibilityLabel("Repeticiones de la serie \(set.order + 1)")
                .onChange(of: set.reps) { _, _ in onChange() }

            IntField(placeholder: "–", value: $set.rir, width: 44)
                .accessibilityLabel("Repeticiones en reserva de la serie \(set.order + 1)")
                .onChange(of: set.rir) { _, _ in onChange() }

            Spacer(minLength: 2)

            Button {
                set.markCompleted(!set.isCompleted)
                onSetCompleted()
                DS.haptic()
            } label: {
                CheckCircle(isOn: set.isCompleted, size: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.isCompleted ? "Serie hecha" : "Marcar serie hecha")
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Quitar esta serie", systemImage: "trash")
            }
        }
    }
}

// MARK: - Récords nuevos

struct NewRecordsSheet: View {
    let records: [RecordCandidate]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Image(systemName: "rosette")
                        .font(.system(size: 52))
                        .foregroundStyle(Theme.goldGradient)
                        .padding(.top, 20)

                    Text(records.contains { !$0.isFirstEver } ? "¡Récord!" : "Primeras marcas")
                        .font(.title.bold())

                    Text(records.contains { !$0.isFirstEver }
                         ? "Has superado tu mejor registro en esta sesión."
                         : "Son tus primeras marcas en estos ejercicios: a partir de ahora hay con qué comparar.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)

                    ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                        row(record)
                    }

                    Button("Seguir") { dismiss() }
                        .buttonStyle(LimeButtonStyle())
                        .padding(.top, 8)
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Marcas de hoy")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ record: RecordCandidate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: record.kind.symbol)
                .font(.title3)
                .foregroundStyle(Theme.gold)
                .frame(width: 34, height: 34)
                .background(Theme.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(record.exerciseName).font(.subheadline.weight(.semibold))
                Text(record.kind.label).font(.caption2).foregroundStyle(Theme.textSecondary)
                if record.kind.isEstimate {
                    Text("Es una estimación a partir de tu mejor serie, no una medición.")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(recordValue(record))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                if let improvement = record.improvement {
                    Text("+\(NumberFormat.plate(improvement))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.lime)
                } else {
                    Text("primera vez").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .card(padding: 12)
    }

    private func recordValue(_ record: RecordCandidate) -> String {
        switch record.kind {
        case .topWeight, .estimatedOneRepMax: return NumberFormat.weight(record.value)
        case .sessionVolume: return "\(NumberFormat.integer(record.value)) kg"
        case .repsAtWeight: return "\(NumberFormat.integer(record.value)) reps"
        }
    }
}

// MARK: - Completar un ejercicio desde sus series

extension ExerciseLog {
    /// Pone el ejercicio como hecho exactamente cuando todas sus series de trabajo lo están.
    ///
    /// Se llama SOLO al marcar o desmarcar una serie. Antes se llamaba en cada cambio, y eso
    /// hacía imposible marcar un ejercicio a mano si tenía alguna serie a medias: la app lo
    /// desmarcaba al instante. La casilla del ejercicio manda siempre.
    func followSets() {
        let work = sets.filter { $0.kind.countsAsWork }
        guard !work.isEmpty else { return }
        isCompleted = work.allSatisfy(\.isCompleted)
    }
}
