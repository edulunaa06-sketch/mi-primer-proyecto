import SwiftData
import SwiftUI
import UIKit

/// Calendario semanal. Cada semana (lunes a domingo) tiene sus propios registros:
/// al empezar una semana nueva las casillas aparecen vacías y el historial anterior se conserva.
struct TrainingView: View {
    @Environment(\.modelContext) private var context
    @Query private var weekLogs: [WorkoutSessionLog]
    @Query(sort: \RoutineExercise.order) private var routine: [RoutineExercise]
    @Query private var titles: [SessionTitle]
    @Query private var kinds: [SessionKindChoice]
    @State private var path: [String] = []
    @State private var planningWeek = false
    @State private var renaming: SessionDefinition?
    @State private var confirmScratch = false
    @State private var confirmDefaults = false
    @State private var newTitle = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    /// La semana tal y como la tiene montada el usuario.
    private var myWeek: [SessionDefinition] {
        WeeklyRoutine.week(routine: routine, titles: titles, kinds: kinds)
    }

    private var completedCount: Int {
        myWeek.filter { $0.kind != .rest && log(for: $0)?.isCompleted == true }.count
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
                        StrengthStatsView()
                    } label: {
                        Label("Volumen, progresión y récords", systemImage: "chart.bar.xaxis")
                    }
                    .buttonStyle(ActionButtonStyle())
                    NavigationLink {
                        ExerciseLibraryView()
                    } label: {
                        Label("Biblioteca de ejercicios", systemImage: "books.vertical")
                    }
                    .buttonStyle(ActionButtonStyle(filled: false))
                    NavigationLink {
                        TrainingHistoryView()
                    } label: {
                        Label("Historial de semanas anteriores", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(ActionButtonStyle(filled: false))
                    Button {
                        planningWeek = true
                    } label: {
                        Label("Montar mi semana", systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(ActionButtonStyle(filled: false))
                    .accessibilityIdentifier("training.planWeek")
                    Menu {
                        Button("Empezar mi rutina desde cero", role: .destructive) { confirmScratch = true }
                        Button("Volver a la rutina predeterminada") { confirmDefaults = true }
                    } label: {
                        Label("Opciones de la rutina", systemImage: "slider.horizontal.3")
                    }
                    .font(.footnote.weight(.semibold))
                    Text("En «Montar mi semana» decides qué es cada día (fuerza, carrera o descanso), cómo se llama y sus ejercicios.")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Entrenamientos")
            // Arriba además de abajo: el volumen y la biblioteca quedaban enterrados
            // detrás de las siete tarjetas de los días.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { ExerciseLibraryView() } label: { Image(systemName: "books.vertical") }
                        .accessibilityLabel("Biblioteca de ejercicios")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { StrengthStatsView() } label: { Image(systemName: "chart.bar.xaxis") }
                        .accessibilityLabel("Volumen, progresión y récords")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { BodyMapView() } label: { Image(systemName: "figure.stand") }
                        .accessibilityLabel("Cuerpo y rangos por músculo")
                }
            }
            .navigationDestination(for: String.self) { sessionID in
                if let session = WeeklyRoutine.session(id: sessionID) {
                    SessionDestination(session: session, weekStart: weekStart)
                }
            }
            .onChange(of: planningWeek) { _, open in
                // Al cerrar el planificador puede haber cambiado el tipo del día abierto.
                if !open { path.removeAll() }
            }
            .sheet(isPresented: $planningWeek) { WeekPlannerView() }
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
                if path.isEmpty, let i = args.firstIndex(of: "-AtlasSession"), i + 1 < args.count {
                    path = [args[i + 1]]
                }
            }
            #endif
        }
    }

    private var weeklySummary: some View {
        let total = myWeek.filter { $0.kind != .rest }.count
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
                    .foregroundStyle(weekday == todayWeekday ? Theme.accent : Theme.textPrimary)
                Text(DateUtils.dayMonth(date))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                if weekday == todayWeekday {
                    Text("HOY")
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.accent, in: Capsule())
                        .foregroundStyle(Theme.onAccent)
                }
                if sessions.count > 1 {
                    Text("\(sessions.count) sesiones")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            ForEach(sessions) { session in
                swipeableRow(session)
            }
        }
        .card()
    }

    /// Pendiente: gris neutro (legible). Descanso: gris azulado. Hecha: icono y check en lima, borde fino y fondo un poco teñido.
    private func sessionRow(_ base: SessionDefinition) -> some View {
        let session = base.resolved(with: routine, titles: titles, kinds: kinds)
        let log = log(for: session)
        let progress = SessionProgress(session: session, log: log)
        let done = session.kind != .rest && log?.isCompleted == true
        let tint = done ? Theme.accent : session.kind == .rest ? Theme.rest : Theme.textSecondary
        return HStack(spacing: 12) {
            Image(systemName: session.kind == .run ? "figure.run" : session.kind == .rest ? "bed.double.fill" : "dumbbell.fill")
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(done ? Theme.accentDim : tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(.subheadline.weight(.semibold))
                Text(subtitle(session, progress: progress))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if done {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Theme.accent)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.3).combined(with: .opacity))
                    .accessibilityHidden(true)
            } else if session.kind != .rest {
                Text("Pendiente").font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.cardRaised)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent.opacity(done ? 0.07 : 0)))
        }
        // Completada: borde lima fino.
        .overlay {
            if done {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1)
            }
        }
    }

    /// Tocar abre la sesión; deslizar hacia la derecha la marca como hecha (o la desmarca si ya lo estaba).
    /// Mantener pulsado: cambiar el nombre. Los días de descanso solo se abren.
    private func swipeableRow(_ base: SessionDefinition) -> some View {
        let session = base.resolved(with: routine, titles: titles, kinds: kinds)
        let done = log(for: session)?.isCompleted ?? false
        let open = { path.append(base.id) }
        return SwipeToComplete(isDone: done, enabled: session.kind != .rest, onOpen: open) {
            toggleDone(base)
        } content: {
            sessionRow(base)
        }
        .contextMenu {
            Button {
                newTitle = base.renamed(titles).title
                renaming = base
            } label: { Label("Cambiar nombre", systemImage: "pencil") }
        }
        .accessibilityIdentifier("session.\(base.id)")
        .accessibilityLabel(session.kind == .rest ? session.title : "\(session.title), \(done ? "hecha" : "pendiente")")
        .accessibilityHint(session.kind == .rest ? "Abre el día" : "Desliza a la derecha para \(done ? "desmarcarla" : "marcarla como hecha")")
    }

    /// Marca la sesión como hecha (o la desmarca) en el registro de esta semana; reutiliza el registro si ya existe.
    /// Fuerza: marca o desmarca todos sus ejercicios, igual que si lo hicieras dentro; los kilos y repeticiones no se tocan.
    private func toggleDone(_ base: SessionDefinition) {
        let session = base.resolved(with: routine, titles: titles, kinds: kinds)
        let log = DataStore.fetchOrCreateLog(for: session, weekStart: weekStart, in: context)
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.65)) {
            log.toggleDoneFromWeek(session: session)
        }
        try? context.save()
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

/// Elige la pantalla adecuada según el tipo de sesión.
struct SessionDestination: View {
    let session: SessionDefinition
    let weekStart: Date

    @Environment(\.modelContext) private var context
    @Query private var titles: [SessionTitle]
    @Query private var kinds: [SessionKindChoice]
    @State private var renaming = false
    @State private var newTitle = ""

    var body: some View {
        // Con el tipo que le haya puesto el usuario: un día que era de carrera y ha pasado a
        // fuerza tiene que abrir la pantalla de fuerza, no la de correr.
        let named = session.resolved(with: [], titles: titles, kinds: kinds)
        Group {
            switch named.kind {
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
                    .foregroundStyle(Theme.accent)
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

/// Fila que se completa deslizándola hacia la derecha (como en Mail o Recordatorios).
/// · Mientras arrastras aparece debajo un fondo verde con un check (o gris con «Desmarcar» si ya estaba hecha).
/// · Al pasar el umbral vibra; si sueltas ahí, se marca. Si sueltas antes, vuelve a su sitio sin cambiar nada.
/// · Un toque normal abre la sesión; un deslizamiento nunca la abre. El gesto solo se activa si el dedo va
///   claramente en horizontal, así que el desplazamiento vertical de la lista sigue igual.
struct SwipeToComplete<Content: View>: View {
    let isDone: Bool
    var enabled = true
    let onOpen: () -> Void
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content

    /// Arrastre en curso. Se vuelve a cero solo (con un muelle) al soltar o si iOS cancela el gesto,
    /// así la fila nunca se queda a medio camino.
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.35, dampingFraction: 0.8)))
    private var dragState = DragState()

    struct DragState {
        var dx: CGFloat = 0
        /// nil = aún no se sabe hacia dónde va el dedo; true = horizontal (es nuestro); false = vertical (es de la lista).
        var horizontal: Bool?
    }

    private var offset: CGFloat {
        guard dragState.horizontal == true else { return 0 }
        let raw = max(dragState.dx, 0)
        // Resistencia suave pasado el umbral, como en iOS.
        return raw <= Self.threshold ? raw : Self.threshold + (raw - Self.threshold) * 0.35
    }

    private var armed: Bool { dragState.horizontal == true && dragState.dx >= Self.threshold }

    /// Cuándo se puso el dedo (para distinguir un toque de una pulsación larga).
    @State private var touchStart: Date?

    static var threshold: CGFloat { 96 }

    var body: some View {
        content()
            .offset(x: offset)
            .background(alignment: .leading) { if offset > 0 { reveal } }
            .contentShape(Rectangle())
            // Un solo gesto decide si es un toque (abrir) o un deslizamiento (completar): así un arrastre,
            // aunque sea corto, nunca abre la sesión.
            .simultaneousGesture(drag)
            .onChange(of: armed) { _, isArmed in
                // Vibración al pasar (o volver a cruzar) el umbral.
                UIImpactFeedbackGenerator(style: isArmed ? .medium : .light).impactOccurred()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen() }
            .accessibilityActions {
                if enabled {
                    Button(isDone ? "Desmarcar" : "Marcar como hecha") { onToggle() }
                }
            }
    }

    private var reveal: some View {
        let color = isDone ? Theme.textTertiary : Theme.accent
        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(color.opacity(armed ? 1 : 0.35 + 0.5 * min(offset / Self.threshold, 1)))
            .frame(width: max(offset, 0))
            .overlay(alignment: .leading) {
                Label(isDone ? "Desmarcar" : "Hecho", systemImage: isDone ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(isDone ? Theme.textPrimary : Theme.onAccent)
                    .scaleEffect(armed ? 1.15 : 0.9)
                    .padding(.leading, 16)
                    .opacity(offset > 28 ? 1 : 0)
            }
            .accessibilityHidden(true)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($dragState) { value, state, _ in
                let dx = value.translation.width, dy = value.translation.height
                // Se decide con el primer movimiento claro: hacia la derecha y bastante más horizontal que vertical.
                if state.horizontal == nil, hypot(dx, dy) >= 12 {
                    state.horizontal = enabled && dx > 0 && abs(dx) > abs(dy) * 1.6
                }
                state.dx = dx
            }
            .onChanged { value in
                // El primer evento llega con el dedo recién puesto (sin desplazamiento).
                if touchStart == nil || value.translation == .zero { touchStart = value.time }
            }
            .onEnded { value in
                let started = touchStart
                touchStart = nil
                let dx = value.translation.width, dy = value.translation.height
                // Toque: el dedo casi no se ha movido y no ha sido una pulsación larga (esa abre el menú).
                if hypot(dx, dy) < 10 {
                    if value.time.timeIntervalSince(started ?? value.time) < 0.5 { onOpen() }
                    return
                }
                // Igual que al empezar: solo cuenta un deslizamiento claramente horizontal hacia la derecha.
                guard enabled, dx > 0, abs(dx) > abs(dy) * 1.6, abs(dy) < 60 else { return }
                if dx >= Self.threshold || value.predictedEndTranslation.width >= Self.threshold * 1.6 {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onToggle()
                }
            }
    }
}
