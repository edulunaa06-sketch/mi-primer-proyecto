import Charts
import SwiftData
import SwiftUI

/// Edición de la rutina de una sesión de fuerza: añadir, eliminar, sustituir, reordenar
/// y cambiar series/repeticiones. Los cambios se guardan al momento y no borran el historial.
struct RoutineEditorView: View {
    let session: SessionDefinition

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var exercises: [RoutineExercise]

    @State private var editing: RoutineExercise?
    @State private var substituting: RoutineExercise?
    @State private var adding = false
    @State private var confirmRestore = false
    @State private var editMode: EditMode = .inactive

    init(session: SessionDefinition) {
        self.session = session
        let id = session.id
        _exercises = Query(filter: #Predicate<RoutineExercise> { $0.sessionID == id }, sort: \.order)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if exercises.isEmpty {
                        Text("Sin ejercicios. Añade uno abajo.").foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(exercises) { ex in
                        Button { editing = ex } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ex.name).foregroundStyle(Theme.textPrimary)
                                    Text("\(ex.sets) series · \(ex.repRange) reps")
                                        .font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "slider.horizontal.3").foregroundStyle(Theme.lime)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Eliminar", role: .destructive) { DataStore.removeExercise(ex, in: context) }
                            Button("Sustituir") { substituting = ex }.tint(.orange)
                        }
                    }
                    .onMove { from, to in
                        DataStore.moveExercises(in: session.id, from: from, to: to, in: context)
                    }
                } header: {
                    Text(session.title)
                } footer: {
                    Text("Toca un ejercicio para cambiar series y repeticiones. Desliza a la izquierda para sustituir o eliminar. Usa “Ordenar” para cambiar el orden. El historial de semanas anteriores no se modifica.")
                }
                .listRowBackground(Theme.card)

                Section {
                    Button { adding = true } label: { Label("Añadir ejercicio", systemImage: "plus.circle.fill") }
                    Button("Restaurar rutina predeterminada", role: .destructive) { confirmRestore = true }
                }
                .listRowBackground(Theme.card)
            }
            .environment(\.editMode, $editMode)
            .screenBackground()
            .navigationTitle("Editar rutina")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(editMode.isEditing ? "Fin de ordenar" : "Ordenar") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Hecho") { dismiss() } }
            }
            .sheet(item: $editing) { ex in
                ExerciseFormView(title: "Editar ejercicio", name: ex.name, sets: ex.sets, repMin: ex.repMin, repMax: ex.repMax,
                                 nameEditable: false) { _, sets, lo, hi in
                    ex.sets = sets
                    ex.repMin = lo
                    ex.repMax = hi
                    try? context.save()
                }
            }
            .sheet(item: $substituting) { ex in
                ExerciseFormView(title: "Sustituir \(ex.name)", name: "", sets: ex.sets, repMin: ex.repMin, repMax: ex.repMax,
                                 nameEditable: true,
                                 footer: "El ejercicio nuevo ocupa la misma posición y empieza su propia progresión. El historial del anterior se conserva.") { name, _, _, _ in
                    DataStore.substitute(ex, withName: name, in: context)
                }
            }
            .sheet(isPresented: $adding) {
                ExerciseFormView(title: "Nuevo ejercicio", name: "", sets: 3, repMin: 8, repMax: 12, nameEditable: true) { name, sets, lo, hi in
                    DataStore.addExercise(to: session.id, name: name, sets: sets, repMin: lo, repMax: hi, in: context)
                }
            }
            .confirmationDialog("¿Restaurar la rutina predeterminada de esta sesión?", isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("Restaurar", role: .destructive) { DataStore.restoreDefaultRoutine(for: session, in: context) }
            } message: {
                Text("Se perderán tus cambios en esta sesión. Los registros de entrenamientos anteriores se mantienen.")
            }
        }
    }
}

/// Formulario de nombre, series y rango de repeticiones.
struct ExerciseFormView: View {
    let title: String
    @State var name: String
    @State var sets: Int
    @State var repMin: Int
    @State var repMax: Int
    var nameEditable: Bool
    var footer: String?
    var onSave: (String, Int, Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss

    init(title: String, name: String, sets: Int, repMin: Int, repMax: Int, nameEditable: Bool,
         footer: String? = nil, onSave: @escaping (String, Int, Int, Int) -> Void) {
        self.title = title
        _name = State(initialValue: name)
        _sets = State(initialValue: sets)
        _repMin = State(initialValue: repMin)
        _repMax = State(initialValue: repMax)
        self.nameEditable = nameEditable
        self.footer = footer
        self.onSave = onSave
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if nameEditable {
                        TextField("Nombre del ejercicio", text: $name)
                    } else {
                        Text(name)
                    }
                    Stepper("Series: \(sets)", value: $sets, in: 1...10)
                    Stepper("Reps mínimas: \(repMin)", value: $repMin, in: 1...100)
                        .onChange(of: repMin) { _, v in if repMax < v { repMax = v } }
                    Stepper("Reps máximas: \(repMax)", value: $repMax, in: 1...100)
                        .onChange(of: repMax) { _, v in if repMin > v { repMin = v } }
                    LabeledContent("Prescripción", value: "\(sets) × \(ExerciseDefinition.formatRange(min: repMin, max: repMax))")
                } footer: {
                    if let footer { Text(footer) }
                }
            }
            .screenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(trimmedName, sets, repMin, repMax)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Progresión de cargas y repeticiones de un ejercicio a lo largo de las semanas.
struct ExerciseProgressView: View {
    let exerciseID: String
    let name: String

    @Query private var logs: [ExerciseLog]

    init(exerciseID: String, name: String) {
        self.exerciseID = exerciseID
        self.name = name
        _logs = Query(filter: #Predicate<ExerciseLog> { $0.exerciseID == exerciseID })
    }

    private var summaries: [ExerciseSessionSummary] {
        logs.compactMap { log -> ExerciseSessionSummary? in
            guard let date = log.session?.weekStart else { return nil }
            let entries = log.sortedSets.map { ExerciseSessionSummary.SetEntry(weightKg: $0.weightKg, reps: $0.reps) }
            return ExerciseSessionSummary(date: date, sets: entries)
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        let data = summaries
        ScrollView {
            VStack(spacing: 16) {
                if data.isEmpty {
                    EmptyStateView(symbol: "chart.xyaxis.line", title: "Sin registros todavía",
                                   message: "Anota kg y repeticiones en las series de este ejercicio para ver aquí tu progresión semana a semana.")
                        .card()
                } else {
                    if data.contains(where: { $0.topWeightKg != nil }) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Carga máxima por semana", subtitle: "Kg de la serie más pesada con repeticiones")
                            Chart(data.filter { $0.topWeightKg != nil }, id: \.date) { s in
                                LineMark(x: .value("Semana", s.date, unit: .day), y: .value("Kg", s.topWeightKg ?? 0))
                                    .foregroundStyle(Theme.lime)
                                PointMark(x: .value("Semana", s.date, unit: .day), y: .value("Kg", s.topWeightKg ?? 0))
                                    .foregroundStyle(Theme.lime)
                            }
                            .frame(height: 180)
                        }
                        .card()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Historial")
                        ForEach(data.reversed(), id: \.date) { s in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Semana del \(DateUtils.shortDate(s.date))").font(.subheadline.weight(.semibold))
                                HStack(spacing: 14) {
                                    stat("Mejor serie", s.topWeightKg.map { "\(NumberFormat.oneDecimal($0)) kg × \(s.repsAtTopWeight ?? 0)" } ?? "—")
                                    stat("Volumen", s.volumeKg > 0 ? "\(NumberFormat.integer(s.volumeKg)) kg" : "—")
                                    stat("Reps totales", "\(s.totalReps)")
                                }
                                if let rm = s.estimatedOneRepMax {
                                    Text("1RM estimado (Epley, orientativo): \(NumberFormat.oneDecimal(rm)) kg")
                                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .card()
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(Theme.textTertiary)
            Text(value).font(.footnote.weight(.semibold).monospacedDigit())
        }
    }
}
