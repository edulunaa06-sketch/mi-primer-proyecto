import SwiftData
import SwiftUI

/// Entrenar: tu semana (tu rutina de siempre, editable), entreno libre, herramientas e historial.
struct TrainView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]
    @Query(filter: #Predicate<Workout> { $0.finishedAt != nil }, sort: \Workout.startedAt, order: .reverse) private var workouts: [Workout]
    @State private var showPlates = false
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("Entrenar").font(.display(28))
                        Spacer()
                        Button { showPlates = true } label: { Image(systemName: "scalemass").font(.system(size: 16, weight: .bold)) }
                            .buttonStyle(.secondaryCompact)
                            .accessibilityLabel("Calculadora de discos")
                    }
                    .padding(.top, 8)
                    weekProgress
                    ForEach(1...7, id: \.self) { day in
                        let list = templates.filter { $0.weekday == day }
                        if !list.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(WeeklyRoutine.weekdayName(day).uppercased() + (day == DateUtils.weekdayMondayBased(Date()) ? " · HOY" : ""))
                                    .font(.system(size: 11, weight: .heavy).width(.expanded)).tracking(1.3)
                                    .foregroundStyle(day == DateUtils.weekdayMondayBased(Date()) ? DS.cyan : DS.text3)
                                ForEach(list) { t in
                                    NavigationLink(value: t.id) { TemplateRow(template: t, done: Store.doneThisWeek(t, workouts: workouts)) }
                                        .buttonStyle(.plain)
                                        .contextMenu {
                                            if t.kind != .rest, Store.doneThisWeek(t, workouts: workouts) == nil {
                                                Button { Store.quickComplete(t, in: context); DS.haptic(.medium) } label: {
                                                    Label("Marcar como hecho", systemImage: "checkmark.circle")
                                                }
                                            }
                                        }
                                }
                            }
                        }
                    }
                    let unscheduled = templates.filter { $0.weekday == 0 }
                    if !unscheduled.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SIN DÍA FIJO").font(.system(size: 11, weight: .heavy).width(.expanded)).tracking(1.3).foregroundStyle(DS.text3)
                            ForEach(unscheduled) { t in
                                NavigationLink(value: t.id) { TemplateRow(template: t, done: Store.doneThisWeek(t, workouts: workouts)) }.buttonStyle(.plain)
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        Button { app.liveWorkout = Store.startWorkout(from: nil, in: context) } label: { Label("Entreno libre", systemImage: "bolt.fill") }
                            .buttonStyle(.secondary)
                        Button { creating = true } label: { Label("Nueva rutina", systemImage: "plus") }
                            .buttonStyle(.secondary)
                    }
                    history
                }
                .padding(.horizontal, 16)
            }
            .atlasScreen()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let t = templates.first(where: { $0.id == id }) { TemplateDetailView(template: t) }
            }
            .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
            .sheet(isPresented: $showPlates) { PlateCalculatorSheet(target: nil) }
            .alert("Nueva rutina", isPresented: $creating) {
                TextField("Nombre (p. ej. Full body)", text: $newName)
                Button("Crear") {
                    let t = WorkoutTemplate(name: newName.isEmpty ? "Mi rutina" : newName, kind: .strength, weekday: 0, order: 100 + templates.count)
                    context.insert(t)
                    try? context.save()
                    newName = ""
                }
                Button("Cancelar", role: .cancel) { newName = "" }
            } message: { Text("Después, ábrela y pulsa «Editar» para añadir ejercicios y elegir el día.") }
        }
    }

    private var weekProgress: some View {
        let planned = templates.filter { $0.weekday > 0 && $0.kind != .rest }
        let done = planned.filter { Store.doneThisWeek($0, workouts: workouts) != nil }.count
        let start = DateUtils.startOfWeek(Date())
        let weekWorkouts = workouts.filter { $0.startedAt >= start }
        let volume = weekWorkouts.reduce(0) { $0 + $1.volume }
        let km = weekWorkouts.reduce(0) { $0 + $1.runMeters } / 1000
        return HStack(spacing: 16) {
            ZStack {
                Ring(progress: planned.isEmpty ? 0 : Double(done) / Double(planned.count), lineWidth: 10, style: DS.brandDiagonal)
                Text("\(done)/\(planned.count)").font(.number(18, .heavy))
            }
            .frame(width: 78, height: 78)
            VStack(alignment: .leading, spacing: 6) {
                Text("Esta semana").font(.system(size: 17, weight: .bold))
                Text("\(done) de \(planned.count) sesiones").font(.system(size: 13)).foregroundStyle(DS.text2)
                HStack(spacing: 12) {
                    Label("\(NumberFormat.integer(volume)) kg", systemImage: "scalemass")
                    Label(String(format: "%.1f km", km).replacingOccurrences(of: ".", with: ","), systemImage: "figure.run")
                }
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.text3)
            }
            Spacer()
        }
        .glass()
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Historial")
            if workouts.isEmpty {
                Text("Aquí aparecerán tus entrenos terminados.").font(.footnote).foregroundStyle(DS.text2)
            }
            ForEach(workouts.prefix(12)) { w in
                NavigationLink(value: w) {
                    HStack {
                        Image(systemName: w.kind == .run ? "figure.run" : "dumbbell.fill").foregroundStyle(DS.text2).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.text)
                            Text(DateUtils.shortDate(w.startedAt) + " · " + detail(w)).font(.system(size: 11)).foregroundStyle(DS.text3)
                        }
                        Spacer()
                        if w.recordCount > 0 { Image(systemName: "trophy.fill").foregroundStyle(DS.goldGradient) }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(DS.text3)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .glass()
    }

    private func detail(_ w: Workout) -> String {
        if w.kind == .run, w.runMeters > 0 {
            return String(format: "%.2f km", w.runMeters / 1000).replacingOccurrences(of: ".", with: ",") + " · " + RunMath.formatDuration(w.runSeconds)
        }
        return w.doneSets.isEmpty ? "Marcado como hecho" : "\(w.doneSets.count) series · \(NumberFormat.integer(w.volume)) kg"
    }
}

struct TemplateRow: View {
    let template: WorkoutTemplate
    let done: Workout?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(done != nil ? AnyShapeStyle(DS.good) : template.kind == .rest ? AnyShapeStyle(DS.text3) : AnyShapeStyle(DS.brandDiagonal))
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(DS.surfaceHi))
            VStack(alignment: .leading, spacing: 3) {
                Text(template.name).font(.system(size: 16, weight: .bold)).foregroundStyle(DS.text)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(DS.text2).lineLimit(1)
            }
            Spacer()
            if done != nil {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(DS.good)
            } else if template.kind != .rest {
                Text("Pendiente").font(.system(size: 11, weight: .bold)).foregroundStyle(DS.text2)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(DS.text3)
        }
        .glass(padding: 12, radius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("template.\(template.seedID.isEmpty ? template.name : template.seedID)")
    }

    private var symbol: String {
        switch template.kind {
        case .strength: return "dumbbell.fill"
        case .run: return "figure.run"
        case .rest: return "moon.zzz.fill"
        }
    }

    private var subtitle: String {
        switch template.kind {
        case .strength:
            let ex = template.sortedExercises
            return "\(ex.count) ejercicios · ~\(WorkoutMath.estimatedMinutes(ex.map { (sets: $0.sets, repRange: $0.repRange) })) min"
        case .run: return template.detail
        case .rest: return "Descanso y recuperación"
        }
    }
}

/// Detalle de una rutina: ejercicios, lo de la última vez, empezar y editar.
struct TemplateDetailView: View {
    @Bindable var template: WorkoutTemplate
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var adding = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    if editing {
                        TextField("Nombre", text: $template.name).font(.display(22))
                        Picker("Día", selection: $template.weekday) {
                            Text("Sin día fijo").tag(0)
                            ForEach(1...7, id: \.self) { Text(WeeklyRoutine.weekdayName($0)).tag($0) }
                        }
                    } else {
                        Text(template.name).font(.display(24))
                        Text(template.weekday > 0 ? WeeklyRoutine.weekdayName(template.weekday) : "Sin día fijo")
                            .font(.footnote).foregroundStyle(DS.text2)
                    }
                    if !template.detail.isEmpty { Text(template.detail).font(.footnote).foregroundStyle(DS.text2) }
                }
                .listRowBackground(Color.clear)
            }
            if template.kind == .strength {
                Section("Ejercicios") {
                    ForEach(template.sortedExercises) { ex in
                        ExerciseTemplateRow(exercise: ex, editing: editing)
                    }
                    .onDelete { offsets in
                        let list = template.sortedExercises
                        for i in offsets { context.delete(list[i]) }
                        renumber()
                    }
                    .onMove { from, to in
                        var list = template.sortedExercises
                        list.move(fromOffsets: from, toOffset: to)
                        for (i, e) in list.enumerated() { e.order = i }
                        try? context.save()
                    }
                    if editing {
                        Button { adding = true } label: { Label("Añadir ejercicio", systemImage: "plus") }
                    }
                }
                .listRowBackground(DS.surface)
            }
            Section {
                switch template.kind {
                case .strength:
                    Button {
                        app.liveWorkout = Store.startWorkout(from: template, in: context)
                    } label: { Label("Empezar entreno", systemImage: "play.fill") }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("template.start")
                case .run:
                    Button { app.runTemplate = RunRequest(template: template) } label: { Label("Registrar carrera", systemImage: "figure.run") }
                        .buttonStyle(.primary)
                case .rest:
                    Text("Día de descanso: duerme bien, camina y come tus proteínas. El músculo crece cuando descansas.")
                        .font(.footnote).foregroundStyle(DS.text2)
                }
                if editing, template.seedID.isEmpty {
                    Button("Borrar rutina", role: .destructive) { confirmDelete = true }
                }
            }
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .background(AtlasBackground())
        .environment(\.editMode, .constant(editing ? .active : .inactive))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(editing ? "Listo" : "Editar") {
                    if editing { try? context.save() }
                    withAnimation { editing.toggle() }
                }
            }
        }
        .sheet(isPresented: $adding) {
            ExercisePicker { ex in
                let e = TemplateExercise(key: ex.id, name: ex.name, sets: ex.defaultSets, repRange: ex.defaultReps, order: template.exercises.count)
                context.insert(e)
                e.template = template
                try? context.save()
            }
        }
        .confirmationDialog("¿Borrar esta rutina?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) { context.delete(template); try? context.save(); dismiss() }
        }
    }

    private func renumber() {
        for (i, e) in template.sortedExercises.enumerated() { e.order = i }
        try? context.save()
    }
}

struct ExerciseTemplateRow: View {
    @Bindable var exercise: TemplateExercise
    let editing: Bool
    @Environment(\.modelContext) private var context
    @State private var last: [SetSample] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.name).font(.system(size: 15, weight: .semibold))
            if editing {
                Stepper("Series: \(exercise.sets)", value: $exercise.sets, in: 1...10)
                TextField("Reps (p. ej. 8–12)", text: $exercise.repRange)
                    .font(.system(size: 14))
            } else {
                HStack(spacing: 8) {
                    Text("\(exercise.sets) × \(exercise.repRange)")
                    if let s = OverloadCoach.suggest(repRange: exercise.repRange, last: last) {
                        Text("· Hoy: \(NumberFormat.kg(s.kg)) kg").foregroundStyle(DS.cyan)
                    } else if let first = last.first {
                        Text("· Última: \(NumberFormat.kg(first.kg)) kg × \(first.reps)")
                    }
                }
                .font(.system(size: 12, weight: .medium)).foregroundStyle(DS.text2)
            }
        }
        .padding(.vertical, 4)
        .task { last = Store.lastPerformance(exercise.key, excluding: nil, in: context) }
    }
}

/// Registrar una carrera: distancia y tiempo; ritmo y predicciones al momento.
struct RunLogSheet: View {
    let template: WorkoutTemplate?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Workout> { $0.runMeters > 0 }) private var runs: [Workout]
    @State private var km: Double?
    @State private var minutes: Double?
    @State private var seconds: Double?
    @State private var date = Date()

    var body: some View {
        let total = Int((minutes ?? 0) * 60 + (seconds ?? 0))
        let meters = (km ?? 0) * 1000
        let samples = runs.map { RunSample(date: $0.startedAt, meters: $0.runMeters, seconds: $0.runSeconds) }
            + (meters > 0 && total > 0 ? [RunSample(date: date, meters: meters, seconds: total)] : [])
        let reference = RacePredictor.reference(samples)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 12) {
                        row("Distancia", "km") { NumberField(placeholder: "5,0", value: $km, width: 110).accessibilityIdentifier("run.km") }
                        row("Tiempo", "min") { NumberField(placeholder: "30", value: $minutes, decimals: false, width: 110).accessibilityIdentifier("run.min") }
                        row("", "s") { NumberField(placeholder: "0", value: $seconds, decimals: false, width: 110) }
                        DatePicker("Fecha", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    }
                    .glass()
                    if meters > 0, total > 0 {
                        HStack(spacing: 12) {
                            StatTile(title: "Ritmo medio", value: RunMath.formatPace(RunMath.paceSecondsPerKm(distanceMeters: meters, seconds: total)).replacingOccurrences(of: " /km", with: ""),
                                     unit: "/km", symbol: "speedometer", tint: DS.good)
                            StatTile(title: "Velocidad", value: NumberFormat.oneDecimal(meters / 1000 / (Double(total) / 3600)), unit: "km/h", symbol: "hare.fill", tint: DS.cyan)
                        }
                    }
                    if let reference {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(title: "Tus tiempos estimados")
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(RacePredictor.distances, id: \.meters) { d in
                                    let t = RacePredictor.predict(fromMeters: reference.meters, seconds: reference.seconds, toMeters: d.meters) ?? 0
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(d.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.text2)
                                        Text(RunMath.formatDuration(t)).font(.number(18))
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.surfaceHi))
                                }
                            }
                            Text("Con la fórmula de Riegel a partir de tu mejor carrera. Orientativo.")
                                .font(.caption2).foregroundStyle(DS.text3)
                        }
                        .glass()
                    }
                    Button {
                        Store.logRun(meters: meters, seconds: total, date: date, template: template, in: context)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    } label: { Label("Guardar carrera", systemImage: "checkmark") }
                    .buttonStyle(.primary)
                    .disabled(meters <= 0 || total <= 0)
                    .accessibilityIdentifier("run.save")
                }
                .padding(16)
            }
            .background(AtlasBackground())
            .navigationTitle(template?.name ?? "Carrera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Listo") { hideKeyboard() } }
            }
        }
    }

    private func row<F: View>(_ title: String, _ unit: String, @ViewBuilder field: () -> F) -> some View {
        HStack {
            Text(title).foregroundStyle(DS.text2)
            Spacer()
            field()
            Text(unit).foregroundStyle(DS.text3).frame(width: 30, alignment: .leading)
        }
    }
}

/// Un entreno terminado: series, volumen y récords.
struct WorkoutDetailView: View {
    let workout: Workout
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(workout.name).font(.display(24))
                Text(workout.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute().locale(Locale(identifier: "es_ES"))))
                    .font(.footnote).foregroundStyle(DS.text2)
                if workout.kind == .run, workout.runMeters > 0 {
                    HStack(spacing: 12) {
                        StatTile(title: "Distancia", value: NumberFormat.oneDecimal(workout.runMeters / 1000), unit: "km", symbol: "map.fill", tint: DS.good)
                        StatTile(title: "Ritmo", value: RunMath.formatPace(RunMath.paceSecondsPerKm(distanceMeters: workout.runMeters, seconds: workout.runSeconds)).replacingOccurrences(of: " /km", with: ""),
                                 unit: "/km", symbol: "speedometer", tint: DS.cyan)
                    }
                } else if !workout.doneSets.isEmpty {
                    HStack(spacing: 12) {
                        StatTile(title: "Volumen", value: NumberFormat.integer(workout.volume), unit: "kg", symbol: "scalemass.fill", tint: DS.indigo)
                        StatTile(title: "Duración", value: WorkoutMath.duration(workout.durationSeconds), symbol: "stopwatch.fill", tint: DS.cyan)
                    }
                    ForEach(workout.exerciseGroups) { g in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(g.name).font(.system(size: 15, weight: .bold))
                            ForEach(g.sets.filter(\.done)) { s in
                                HStack {
                                    Text("\(s.index + 1)").foregroundStyle(DS.text3).frame(width: 22, alignment: .leading)
                                    Text("\(NumberFormat.kg(s.kg ?? 0)) kg × \(s.reps ?? 0)").font(.system(size: 14).monospacedDigit())
                                    if s.isRecord { Image(systemName: "trophy.fill").foregroundStyle(DS.goldGradient).font(.caption) }
                                }
                            }
                        }
                        .glass(padding: 14, radius: 18)
                    }
                } else {
                    Text("Marcado como hecho sin series apuntadas.").foregroundStyle(DS.text2)
                }
                Button("Borrar este entreno", role: .destructive) { confirmDelete = true }
                    .font(.footnote.weight(.semibold)).padding(.top, 8)
            }
            .padding(16)
        }
        .background(AtlasBackground())
        .confirmationDialog("¿Borrar este entreno?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) { context.delete(workout); try? context.save(); dismiss() }
        }
    }
}
